# Guide d'administration — SmartBox V6

**Base de données cible :** `SPR`
**Serveur :** `sdevl01-sd2215\sd2215`
**Dépôt Git :** https://github.com/Ledobs23/SmartBox.git

---

## 1. Vue d'ensemble du pipeline

SmartBox V6 est une couche d'abstraction SQL qui reconstruit les endpoints OData de Project Online à partir de PSSE (Project Server Subscription Edition). Le pipeline s'exécute en séquence sur la base `SPR` :

```
v6_02a  →  v6_03a  →  v6_05a  →  v6_06a  →  v6_07a
  ↑              ↑          ↑
Config      Inventaire   Dictionnaire
tenant      + synonymes   (via PS1)
```

| Script | Rôle |
|--------|------|
| `v6_02a` | Déclare le tenant (cfg.PWA, cfg.Settings, cfg.PwaSchemaScope) |
| `v6_03a` | Inventorie PSSE, crée les synonymes `src_*`, crée les tables de travail |
| `Load-DictionaryCSV.ps1` | Charge les 3 CSV du dictionnaire dans `stg.import_*` |
| `v6_05a` | Normalise le dictionnaire dans `dic.*` |
| `v6_06a` | Construit le plan de publication colonne par colonne dans `dic.EntityColumnPublication` |
| `v6_07a` | Génère les vues `ProjectData`, `tbx`, `tbx_fr` à partir du plan |

Pour rejouer le pipeline en entier, exécuter d'abord `v6_00z` (remise à zéro).

---

## 2. Tables de configuration (`cfg`)

### `cfg.PWA` — Identité du tenant PWA

Table à **une seule ligne** (`PWAId = 1`). Source d'autorité pour la langue des vues.

| Colonne | Type | Rôle |
|---------|------|------|
| `PWAId` | int | Toujours `1` (contrainte CHECK) |
| `ContentDatabaseName` | sysname | Nom de la base PSSE source (ex. `SP_SPR_POC_Contenu`) |
| `Language` | nvarchar(10) | Langue des vues générées : `FR` ou `EN` |
| `Notes` | nvarchar(4000) | Notes libres sur le tenant |

**Requêtes utiles :**
```sql
-- État actuel du tenant
SELECT * FROM cfg.PWA;

-- Forcer la langue
UPDATE cfg.PWA SET Language = N'FR', UpdatedBy = SUSER_SNAME(), UpdatedOn = SYSDATETIME();
```

> Modifier `Language` nécessite de rejouer `v6_07a` pour régénérer les vues avec les bons alias.

---

### `cfg.Settings` — Paramètres clés du tenant

Table clé-valeur. Chaque script lit ses paramètres ici au démarrage.

| Colonne | Rôle |
|---------|------|
| `SettingKey` | Clé unique (PK) |
| `SettingValue` | Valeur sous forme de texte |
| `SettingGroup` | Regroupement logique (`PIPELINE`, `GENERAL`, etc.) |
| `IsRequired` | Le pipeline échoue si manquant |
| `IsSecret` | Valeur à masquer dans les rapports |
| `IsDeprecated` | Paramètre hors usage — conservé pour historique |

**Paramètres critiques V6 :**

| SettingKey | Valeur attendue | Script consommateur |
|---|---|---|
| `ContentDbName` | `SP_SPR_POC_Contenu` | v6_03a |
| `PwaId` | `1` | v6_03a, v6_05a, v6_06a |
| `ViewDefinitionMode` | `FROZEN_SNAPSHOT` | v6_04a |
| `ViewGenerationMode` | `NATIVE_STACKS` | v6_06a, v6_07a |
| `ExcludePsseContentCustomFields` | `1` | v6_06a |

**Requêtes utiles :**
```sql
-- Tous les paramètres actifs et requis
SELECT SettingKey, SettingValue, SettingGroup, IsRequired
FROM cfg.Settings
WHERE IsDeprecated = 0
ORDER BY SettingGroup, SettingKey;

-- Paramètres manquants requis
SELECT SettingKey FROM cfg.Settings
WHERE IsRequired = 1 AND NULLIF(LTRIM(RTRIM(SettingValue)), N'') IS NULL;
```

---

## 3. Tables de journal (`log`)

### `log.ScriptExecutionLog` — Journal d'exécution des scripts

Chaque script écrit au minimum deux entrées : `START` et `COMPLETED` (ou `ERROR`). Point d'entrée principal pour diagnostiquer une exécution.

| Colonne | Rôle |
|---------|------|
| `RunId` | Identifiant unique de l'exécution (GUID) — regroupe toutes les phases d'un même script |
| `ScriptName` | Nom du script (`v6_03a_Create_Foundations.sql`, etc.) |
| `Phase` | Étape dans le script (`START`, `INVENTORY`, `SYNONYMS`, `COMPLETED`, `ERROR`) |
| `Severity` | `INFO`, `WARNING`, `ERROR` |
| `Status` | `STARTED`, `COMPLETED`, `FAILED` |
| `Message` | Texte libre — résumé de l'étape |
| `RowsAffected` | Nombre de lignes traitées (inventaire, synonymes, vues, etc.) |
| `ErrorMessage` | Message d'erreur SQL si `Severity = ERROR` |
| `LoginName` | Compte Windows qui a exécuté le script |
| `LoggedAt` | Horodatage |

**Requêtes utiles :**
```sql
-- Dernière exécution de chaque script
SELECT ScriptName, Phase, Severity, Status, Message, RowsAffected, LoggedAt
FROM log.ScriptExecutionLog
WHERE RunId IN (
    SELECT TOP 1 RunId FROM log.ScriptExecutionLog
    WHERE ScriptName = N'v6_07a_Generate_Views_From_Publication.sql'
    ORDER BY LoggedAt DESC
)
ORDER BY ExecutionLogId;

-- Toutes les erreurs récentes (30 derniers jours)
SELECT ScriptName, Phase, Message, ErrorMessage, LoggedAt
FROM log.ScriptExecutionLog
WHERE Severity = N'ERROR'
  AND LoggedAt >= DATEADD(DAY, -30, SYSDATETIME())
ORDER BY LoggedAt DESC;

-- Historique condensé du pipeline
SELECT ScriptName,
       MIN(LoggedAt)  AS DebutExecution,
       MAX(LoggedAt)  AS FinExecution,
       MAX(CASE WHEN Phase = N'COMPLETED' THEN RowsAffected END) AS LignesTraitees,
       MAX(Severity)  AS PireSeverite
FROM log.ScriptExecutionLog
GROUP BY ScriptName, RunId
ORDER BY MIN(LoggedAt) DESC;
```

> **Rétention recommandée :** conserver 90 jours. Voir section 6 (optimisation).

---

## 4. Tables d'inventaire PSSE (`stg`)

### `stg.ObjectInventory` — Objets PSSE découverts

Remplie à chaque exécution de `v6_03a`. Contient la liste de toutes les tables et vues de la base PSSE source filtrées par `cfg.PwaSchemaScope`.

| Colonne | Rôle |
|---------|------|
| `RunId` | Identifiant de la passe d'inventaire |
| `PWAId` | Lien vers cfg.PWA |
| `SourceDatabaseName` | Base PSSE (`SP_SPR_POC_Contenu`) |
| `SourceSchemaName` | Schéma PSSE (`pjrep`, `pjpub`) |
| `SourceObjectName` | Nom de la table ou vue |
| `ObjectType` | `USER_TABLE` ou `VIEW` |
| `RowEstimate` | Estimation du nombre de lignes |

**Requêtes utiles :**
```sql
-- Répartition par schéma (dernière passe)
SELECT SourceSchemaName, ObjectType, COUNT(*) AS NbObjets
FROM stg.ObjectInventory
WHERE RunId = (SELECT TOP 1 RunId FROM stg.ObjectInventory ORDER BY InventoriedAt DESC)
GROUP BY SourceSchemaName, ObjectType
ORDER BY SourceSchemaName, ObjectType;
```

---

### `stg.ColumnInventory` — Colonnes PSSE découvertes

Remplie en même temps que `stg.ObjectInventory`. Permet à `v6_06a` de détecter automatiquement les clés de jointure entre objets PSSE.

| Colonne | Rôle |
|---------|------|
| `SourceObjectName` | Table ou vue PSSE |
| `ColumnName` | Nom de la colonne |
| `DataType` | Type SQL (`uniqueidentifier`, `int`, `nvarchar`, etc.) |
| `MaxLength`, `PrecisionValue`, `ScaleValue` | Précision du type |
| `IsNullable` | Nullabilité |

**Requêtes utiles :**
```sql
-- Colonnes d'un objet PSSE spécifique
SELECT ColumnName, DataType, MaxLength, IsNullable
FROM stg.ColumnInventory
WHERE SourceObjectName = N'MSP_EpmProject_UserView'
  AND PWAId = 1
ORDER BY ColumnId;

-- Clés communes entre deux objets (pour diagnostiquer des jointures)
SELECT ci1.ColumnName, ci1.DataType
FROM stg.ColumnInventory ci1
JOIN stg.ColumnInventory ci2
    ON ci2.ColumnName = ci1.ColumnName
   AND ci2.DataType   = ci1.DataType
   AND ci2.SourceObjectName = N'MSP_EpmProjectDecision_UserView'
   AND ci2.PWAId = 1
WHERE ci1.SourceObjectName = N'MSP_EpmProject_UserView'
  AND ci1.PWAId = 1;
```

---

### `cfg.PwaObjectScope` — Périmètre d'exposition PSSE

Alimentée par le MERGE de `v6_03a` à partir de `stg.ObjectInventory`. Définit quels objets PSSE sont exposés sous quel schéma `src_*`.

| Colonne | Rôle |
|---------|------|
| `SourceSchemaName` | Schéma d'origine dans PSSE |
| `SourceObjectName` | Objet d'origine |
| `SmartBoxSchemaName` | Schéma SmartBox correspondant (`src_pjrep`, etc.) |
| `SmartBoxObjectName` | Nom du synonyme |
| `IsActive` | `1` = inclus dans le pipeline |
| `IsSelected` | `1` = synonyme créé |

**Requêtes utiles :**
```sql
-- Objets actifs exposés
SELECT SourceSchemaName, SourceObjectName, SmartBoxSchemaName, SmartBoxObjectName
FROM cfg.PwaObjectScope
WHERE IsActive = 1 AND IsSelected = 1
ORDER BY SmartBoxSchemaName, SourceObjectName;

-- Désactiver un objet (l'exclure des synonymes au prochain v6_03a)
UPDATE cfg.PwaObjectScope
SET IsActive = 0, IsSelected = 0,
    UpdatedBy = SUSER_SNAME(), UpdatedOn = SYSDATETIME()
WHERE SourceObjectName = N'MSP_EpmAssignmentType';
```

---

## 5. Tables du dictionnaire (`dic`)

### `dic.EntityBinding` — Source principale de chaque entité

Une ligne par entité OData. Détermine quel objet PSSE constitue la table de base (`FROM`) dans la vue générée.

| Colonne | Rôle |
|---------|------|
| `EntityName_EN` | Nom canonique EN (`Projects`, `Tasks`, etc.) |
| `EntityName_FR` | Nom FR (`Projets`, `Tâches`, etc.) |
| `PsseObjectName` | Objet PSSE principal (`MSP_EpmProject_UserView`) |
| `SmartBoxSchemaName` | Schéma synonyme (`src_pjrep`) |
| `BindingAlias` | Alias SQL dans la vue (`src`) |
| `CoverageScore` | % de colonnes OData couvertes par cet objet |
| `BindingStatus` | `AUTO_HIGH`, `AUTO_LOW`, `MANUAL` |
| `IsActive` | `1` = inclus dans la génération des vues |

**Requêtes utiles :**
```sql
-- État des bindings
SELECT EntityName_EN, EntityName_FR, PsseObjectName,
       SmartBoxSchemaName, CoverageScore, BindingStatus, IsActive
FROM dic.EntityBinding
ORDER BY EntityName_EN;

-- Entités sans binding actif (bloquantes pour v6_07a)
SELECT e.EntityName_EN
FROM dic.Entity e
LEFT JOIN dic.EntityBinding eb ON eb.EntityName_EN = e.EntityName_EN AND eb.IsActive = 1
WHERE eb.EntityBindingId IS NULL;
```

---

### `dic.EntityColumnPublication` — Plan de publication colonne par colonne

Table centrale du pipeline. Construite par `v6_06a`, lue par `v6_07a`. Contient exactement ce qui doit apparaître dans chaque vue générée.

| Colonne | Rôle |
|---------|------|
| `EntityName_EN` | Entité parente |
| `Column_EN` / `Column_FR` | Alias colonne EN et FR |
| `ColumnClassification` | `PRIMITIVE`, `LOOKUP`, `CALCULATED`, `NULL_PLACEHOLDER` |
| `PsseSourceObject` | Objet PSSE source de la colonne |
| `PsseColumnName` | Colonne physique dans PSSE |
| `SourceAlias` | Alias de jointure dans la vue (`src`, `j1`, etc.) |
| `SourceExpression` | Expression SQL complète pour la colonne |
| `MapStatus` | `MAPPED`, `MAPPED_NEEDS_JOIN`, `UNMAPPED`, `NULL_PLACEHOLDER` |
| `IsPublished` | `1` = colonne incluse dans la vue, `0` = exclue |

**Requêtes de diagnostic critiques :**
```sql
-- Colonnes non mappées par entité
SELECT EntityName_EN, COUNT(*) AS NbColonnesNonMappees
FROM dic.EntityColumnPublication
WHERE MapStatus = N'UNMAPPED' AND IsPublished = 1
GROUP BY EntityName_EN
ORDER BY NbColonnesNonMappees DESC;

-- Colonnes exclues car jointure manquante
SELECT EntityName_EN, Column_EN, PsseSourceObject, MapStatus
FROM dic.EntityColumnPublication
WHERE MapStatus = N'MAPPED_NEEDS_JOIN'
ORDER BY EntityName_EN, Column_EN;

-- Vue complète d'une entité : ce qui sera généré
SELECT ColumnPosition, Column_EN, Column_FR, ColumnClassification,
       SourceAlias, PsseColumnName, MapStatus, IsPublished
FROM dic.EntityColumnPublication
WHERE EntityName_EN = N'Projects'
ORDER BY ColumnPosition;
```

---

### `stg.DictionaryQualityIssue` — Anomalies détectées dans le dictionnaire

Remplie par `v6_05a`. Chaque anomalie bloque ou avertit sur la fiabilité d'un mapping.

| Colonne | Rôle |
|---------|------|
| `IssueSeverity` | `ERROR` (bloquant), `WARNING`, `INFO` |
| `IssueCode` | Code court identifiant le type d'anomalie |
| `EntityName_EN` | Entité concernée |
| `ColumnName` | Colonne concernée |
| `IssueMessage` | Description détaillée |

**Requêtes utiles :**
```sql
-- Anomalies bloquantes en cours
SELECT IssueCode, EntityName_EN, ColumnName, IssueMessage
FROM stg.DictionaryQualityIssue
WHERE IssueSeverity = N'ERROR'
ORDER BY EntityName_EN, ColumnName;

-- Synthèse par sévérité et code
SELECT IssueSeverity, IssueCode, COUNT(*) AS NbOccurrences
FROM stg.DictionaryQualityIssue
GROUP BY IssueSeverity, IssueCode
ORDER BY IssueSeverity, NbOccurrences DESC;
```

---

## 6. Tables de rapport (`report`)

### `report.ViewStackValidation` — Résultats de génération des vues

Remplie par `v6_07a`. Une ligne par vue tentée.

| Colonne | Rôle |
|---------|------|
| `RunId` | Identifiant de la passe de génération |
| `ViewSchema` | Schéma de la vue (`ProjectData`, `tbx`, `tbx_fr`) |
| `ViewName` | Nom de la vue créée |
| `ValidationStatus` | `CREATED`, `FAILED`, `SKIPPED` |
| `Message` | Détail d'erreur si `FAILED` |

**Requêtes utiles :**
```sql
-- Résultats de la dernière génération
SELECT ViewSchema, ViewName, ValidationStatus, Message
FROM report.ViewStackValidation
WHERE RunId = (SELECT TOP 1 RunId FROM report.ViewStackValidation ORDER BY ReportedAt DESC)
ORDER BY ViewSchema, ValidationStatus DESC, ViewName;

-- Toutes les vues en échec
SELECT ViewSchema, ViewName, Message, ReportedAt
FROM report.ViewStackValidation
WHERE ValidationStatus = N'FAILED'
ORDER BY ReportedAt DESC;

-- Comptage par résultat (dernière passe)
SELECT ValidationStatus, COUNT(*) AS NbVues
FROM report.ViewStackValidation
WHERE RunId = (SELECT TOP 1 RunId FROM report.ViewStackValidation ORDER BY ReportedAt DESC)
GROUP BY ValidationStatus;
```

---

## 7. Tâches d'administration courantes

### Rejouer le pipeline complet

Utiliser quand la base PSSE source a changé, ou après correction de paramètres.

```sql
-- 1. Remettre à zéro (conserve cfg.PWA et cfg.Settings)
-- Exécuter v6_00z_Reset_SmartBox_V6_Working_Tables.sql

-- 2. Rejouer dans l'ordre
-- v6_03a → Load-DictionaryCSV.ps1 → v6_05a → v6_06a → v6_07a
```

```powershell
# Charger les CSV du dictionnaire avant v6_05a
.\Load-DictionaryCSV.ps1 -Server "sdevl01-sd2215\sd2215" -Database "SPR"
```

---

### Changer la base PSSE source

```sql
-- 1. Mettre à jour la configuration
UPDATE cfg.Settings
SET SettingValue = N'NouvelleBaseContentDb',
    UpdatedBy = SUSER_SNAME(), UpdatedOn = SYSDATETIME()
WHERE SettingKey = N'ContentDbName';

UPDATE cfg.PWA
SET ContentDatabaseName = N'NouvelleBaseContentDb',
    UpdatedBy = SUSER_SNAME(), UpdatedOn = SYSDATETIME();

-- 2. Vider le scope (v6_03a reconstruira les synonymes)
DELETE FROM cfg.PwaObjectScope;

-- 3. Rejouer le pipeline complet (v6_00z → v6_07a)
```

---

### Forcer une jointure manquante (`MAPPED_NEEDS_JOIN`)

Quand une colonne est exclue des vues car sa jointure n'a pas pu être détectée automatiquement :

```sql
-- 1. Identifier la jointure manquante
SELECT ej.EntityName_EN, ej.JoinTag, ej.JoinExpression, ej.JoinStatus, ej.PsseObjectName
FROM dic.EntityJoin ej
WHERE ej.JoinStatus = N'MANUAL_REQUIRED';

-- 2. Corriger la condition de jointure
UPDATE dic.EntityJoin
SET JoinExpression = N'j2.ProjectUID = src.ProjectUID',
    JoinStatus     = N'VALIDATED',
    UpdatedBy      = SUSER_SNAME(),
    UpdatedOn      = SYSDATETIME()
WHERE EntityName_EN = N'Projects'
  AND JoinTag       = N'j2';

-- 3. Rejouer uniquement v6_06a puis v6_07a (pas besoin de v6_00z)
```

---

### Exclure un champ personnalisé PSSE des vues

```sql
-- Option 1 : exclure toute la colonne de la publication
UPDATE dic.EntityColumnPublication
SET IsPublished = 0,
    UpdatedBy   = SUSER_SNAME(),
    UpdatedOn   = SYSDATETIME()
WHERE EntityName_EN = N'Projects'
  AND Column_EN     = N'NomDuChamp';

-- Option 2 : exclure l'objet PSSE entier du scope
UPDATE cfg.PwaObjectScope
SET IsActive = 0, IsSelected = 0,
    UpdatedBy = SUSER_SNAME(), UpdatedOn = SYSDATETIME()
WHERE SourceObjectName = N'MSP_EpmXxx';

-- Rejouer v6_06a → v6_07a
```

---

### Vérifier l'état général de la base (tableau de bord rapide)

```sql
SELECT
    N'cfg.PWA — langue'              AS Élément,
    Language                          AS Valeur
FROM cfg.PWA
UNION ALL
SELECT N'cfg.PWA — base source',      ContentDatabaseName FROM cfg.PWA
UNION ALL
SELECT N'Synonymes src_* actifs',
    CAST(COUNT(*) AS nvarchar) FROM sys.synonyms WHERE SCHEMA_NAME(schema_id) LIKE N'src_%'
UNION ALL
SELECT N'Bindings actifs',
    CAST(COUNT(*) AS nvarchar) FROM dic.EntityBinding WHERE IsActive = 1
UNION ALL
SELECT N'Colonnes publiées',
    CAST(COUNT(*) AS nvarchar) FROM dic.EntityColumnPublication WHERE IsPublished = 1
UNION ALL
SELECT N'Colonnes MAPPED_NEEDS_JOIN',
    CAST(COUNT(*) AS nvarchar) FROM dic.EntityColumnPublication WHERE MapStatus = N'MAPPED_NEEDS_JOIN'
UNION ALL
SELECT N'Vues ProjectData',
    CAST(COUNT(*) AS nvarchar) FROM sys.views v JOIN sys.schemas s ON s.schema_id = v.schema_id WHERE s.name = N'ProjectData'
UNION ALL
SELECT N'Vues tbx',
    CAST(COUNT(*) AS nvarchar) FROM sys.views v JOIN sys.schemas s ON s.schema_id = v.schema_id WHERE s.name = N'tbx'
UNION ALL
SELECT N'Erreurs qualité dictionnaire',
    CAST(COUNT(*) AS nvarchar) FROM stg.DictionaryQualityIssue WHERE IssueSeverity = N'ERROR'
UNION ALL
SELECT N'Erreurs log (30j)',
    CAST(COUNT(*) AS nvarchar) FROM log.ScriptExecutionLog WHERE Severity = N'ERROR' AND LoggedAt >= DATEADD(DAY,-30,SYSDATETIME());
```

---

## 8. Optimisation

### Purge du journal d'exécution

Le journal `log.ScriptExecutionLog` grossit à chaque exécution de script. Conserver 90 jours suffit pour l'audit courant.

```sql
-- Purge des entrées de plus de 90 jours
DELETE FROM log.ScriptExecutionLog
WHERE LoggedAt < DATEADD(DAY, -90, SYSDATETIME());

-- Optionnel : reconstruire l'index après purge massive
ALTER INDEX ALL ON log.ScriptExecutionLog REBUILD;
```

---

### Purge des données de staging obsolètes

Les tables `stg.*` conservent les résultats de chaque RunId. Entre deux exécutions de pipeline, les anciennes passes peuvent être purgées.

```sql
-- Conserver uniquement la dernière passe d'inventaire
DECLARE @LastRunId uniqueidentifier;
SELECT TOP 1 @LastRunId = RunId FROM stg.ObjectInventory ORDER BY InventoriedAt DESC;

DELETE FROM stg.ColumnInventory WHERE RunId <> @LastRunId;
DELETE FROM stg.ObjectInventory  WHERE RunId <> @LastRunId;

-- Idem pour stg.DictionaryQualityIssue (garder la dernière passe v6_05a)
DELETE FROM stg.DictionaryQualityIssue
WHERE RunId <> (SELECT TOP 1 RunId FROM stg.DictionaryQualityIssue ORDER BY ReportedAt DESC);
```

---

### Maintenance des index

```sql
-- Niveau de fragmentation des index SmartBox
SELECT
    OBJECT_NAME(ips.object_id)      AS TableName,
    i.name                           AS IndexName,
    ips.avg_fragmentation_in_percent AS Fragmentation
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, N'LIMITED') ips
JOIN sys.indexes i ON i.object_id = ips.object_id AND i.index_id = ips.index_id
JOIN sys.schemas s ON s.schema_id = OBJECTPROPERTY(ips.object_id, N'SchemaId')
WHERE s.name IN (N'stg', N'dic', N'cfg', N'log', N'report', N'review')
  AND ips.avg_fragmentation_in_percent > 10
ORDER BY ips.avg_fragmentation_in_percent DESC;

-- Rebuild ciblé (exemple)
ALTER INDEX IX_log_ScriptExecutionLog_Status ON log.ScriptExecutionLog REBUILD;
ALTER INDEX IX_dic_ECP_MapStatus             ON dic.EntityColumnPublication REBUILD;
```

---

### Statistiques

Mettre à jour après chaque exécution complète du pipeline ou si des requêtes ralentissent.

```sql
UPDATE STATISTICS dic.EntityColumnPublication WITH FULLSCAN;
UPDATE STATISTICS dic.EntityBinding            WITH FULLSCAN;
UPDATE STATISTICS stg.ColumnInventory          WITH FULLSCAN;
UPDATE STATISTICS log.ScriptExecutionLog       WITH FULLSCAN;
```

---

## 9. Maintenir la base à jour

### Quand rejouer le pipeline ?

| Événement | Scripts à rejouer |
|---|---|
| Nouvelle version des CSV du dictionnaire | `Load-DictionaryCSV.ps1` → `v6_05a` → `v6_06a` → `v6_07a` |
| Ajout d'objets dans la base PSSE | `v6_03a` → `v6_06a` → `v6_07a` |
| Changement de base PSSE source | `v6_00z` → `v6_03a` → `v6_05a` → `v6_06a` → `v6_07a` |
| Correction d'un mapping manuel (jointure, alias) | `v6_06a` → `v6_07a` |
| Changement de langue (`cfg.PWA.Language`) | `v6_07a` uniquement |
| Réinstallation complète | `v6_00z` (avec `@ClearSettings=1`) → `v6_02a` → pipeline complet |

---

### Vérification post-pipeline

Après toute exécution, valider :

```sql
-- 1. Aucune erreur dans le journal
SELECT ScriptName, Phase, Message, ErrorMessage
FROM log.ScriptExecutionLog
WHERE Severity = N'ERROR'
  AND LoggedAt >= DATEADD(MINUTE, -30, SYSDATETIME());

-- 2. Toutes les vues ont été créées
SELECT ValidationStatus, COUNT(*) AS NbVues
FROM report.ViewStackValidation
WHERE RunId = (SELECT TOP 1 RunId FROM report.ViewStackValidation ORDER BY ReportedAt DESC)
GROUP BY ValidationStatus;

-- 3. Les vues ProjectData sont interrogeables
SELECT TOP 5 * FROM ProjectData.Projets;
SELECT TOP 5 * FROM ProjectData.Tâches;

-- 4. Aucune colonne MAPPED_NEEDS_JOIN non intentionnelle
SELECT EntityName_EN, Column_EN, PsseSourceObject
FROM dic.EntityColumnPublication
WHERE MapStatus = N'MAPPED_NEEDS_JOIN'
ORDER BY EntityName_EN;
```

---

### Versionnement et déploiement

Le dépôt Git `https://github.com/Ledobs23/SmartBox.git` contient tous les scripts V6. Bonnes pratiques :

- **Ne jamais modifier directement en production** sans créer d'abord une branche Git.
- **Commiter après chaque correction validée** de mapping ou de jointure pour garder un historique des décisions.
- **Taguer les versions stables** (`git tag v6.1.0`) avant une mise à jour majeure du dictionnaire ou un changement de base PSSE.
- Les corrections manuelles dans `dic.EntityJoin` et `dic.EntityColumnPublication` doivent être documentées dans un commit pour traçabilité.

---

*Document maintenu dans le dépôt SmartBox. Mettre à jour après chaque évolution structurelle du pipeline.*
