# Guide d'exécution — SmartBox V6

**Projet :** SmartBox — couche d'abstraction SQL pour Project Server Subscription Edition (PSSE)  
**Version :** V6  
**Base SmartBox cible :** `SPR`  
**Base PSSE source :** `SP_SPR_POC_Contenu`  
**Serveur :** `sdevl01-sd2215\sd2215`

---

## Vue d'ensemble

SmartBox V6 reconstruit les endpoints OData de Project Online directement depuis une base SQL Server PSSE, sans dépendance à SharePoint ni à xp_cmdshell. Le résultat est un ensemble de vues SQL (`ProjectData.*`, `tbx.*`, `tbx_fr.*`) interrogeables par n'importe quel client OData ou Power BI.

Le pipeline se divise en quatre volets :

| Volet | Scripts | Exécuté dans |
|---|---|---|
| Migration de Project Online vers PSSE | Prérequis à l'exécution des scripts | FluentBook et maintient des UID |
| Extractions du schéma OData | Consignation des csv d'alias et de schéma | Utilisation iD-ODataSmartBoxGenerator |
| Infrastructure PSSE vers BDI | exécution des scripts v6_01a → v6_04a | SSMS |
| Dictionnaire et publication | Load-DictionaryCSV.ps1 + v6_05a → v6_07a | PowerShell + SSMS |

---

## Prérequis

### Prérequis SQL Server

- SQL Server 2019+ (niveau de compatibilité ≥ 140)
- La base `SPR` existe déjà en collation Latin1_General_CI_AS_KS_WS (vide ou partiellement déployée)
- Le compte exécutant les scripts est membre du rôle `db_owner` sur `SPR`
- Accès en lecture sur la BD de `Contenu` de PSSE (création des synonymes src_*)

**Vérifier la compatibilité et les permissions depuis SSMS :**

```sql
-- Niveau de compatibilité (doit être >= 140)
SELECT name, compatibility_level FROM sys.databases WHERE name = DB_NAME();

-- Permissions du compte courant
SELECT
    IS_MEMBER('db_owner')           AS IsDbOwner,
    IS_SRVROLEMEMBER('sysadmin')    AS IsSysAdmin,
    SUSER_SNAME()                   AS LoginName;
```

---

### Prérequis PowerShell (pour l'étape 4 uniquement)

Le script `Load-DictionaryCSV.ps1` utilise **Windows PowerShell 5.1** (inclus dans Windows 10/11) et **System.Data.SqlClient** (inclus dans le .NET Framework natif). Aucune installation additionnelle n'est requise.

#### 1. Vérifier la version PowerShell

```powershell
$PSVersionTable.PSVersion
```

La colonne `Major` doit être **5** ou supérieure. Si la commande échoue, installer PowerShell depuis le Microsoft Store.

#### 2. Vérifier et ajuster la politique d'exécution

```powershell
Get-ExecutionPolicy -Scope CurrentUser
```

Si le résultat est `Restricted` ou `AllSigned`, autoriser les scripts locaux :

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

> `RemoteSigned` autorise les scripts locaux non signés. Les scripts téléchargés depuis Internet doivent être signés. C'est le niveau habituel pour un poste DBA.

#### 3. Tester la connectivité SQL Server depuis PowerShell

```powershell
$conn = New-Object System.Data.SqlClient.SqlConnection(
    "Server=sdevl01-sd2215\sd2215;Database=SPR;Integrated Security=SSPI;TrustServerCertificate=True;"
)
try {
    $conn.Open()
    Write-Host "Connexion OK — SQL Server version : $($conn.ServerVersion)" -ForegroundColor Green
    $conn.Close()
} catch {
    Write-Host "ERREUR : $_" -ForegroundColor Red
}
```

#### 4. Vérifier la présence des fichiers CSV

```powershell
$csvPath = "C:\Users\franbreton\Downloads\SPR SmartBox"
@(
    "Fields_ProjectData_Export.csv",
    "Lookups_ProjectServer_Export.csv",
    "ProjectData_Alias.csv"
) | ForEach-Object {
    $f = Join-Path $csvPath $_
    if (Test-Path $f) {
        $lines = (Get-Content $f).Count - 1   # -1 pour l'entête
        Write-Host "OK  $_  ($lines lignes)" -ForegroundColor Green
    } else {
        Write-Host "MANQUANT  $_" -ForegroundColor Red
    }
}
```

---

## Ordre d'exécution

---

### Étape 0 — Diagnostic (optionnel, recommandé au premier déploiement)

**Script :** `v6_01a_Prereq_Diagnostic.sql`  
**Exécuter dans :** SSMS → base `SPR`

Effectue une série de vérifications en lecture seule sans modifier la base :

- Niveau de compatibilité SQL Server
- Présence des permissions BULK, sysadmin
- Existence et accessibilité de la base PSSE (`SP_SPR_POC_Contenu`)
- État de xp_cmdshell (diagnostique uniquement — non requis par V6)

Produit un rapport console. Aucun effet de bord.

---

### Étape 1 — Rattachement et configuration

**Script :** `v6_02a_Attach_Existing_SmartBox_Database.sql`  
**Exécuter dans :** SSMS → base `SPR`  
**Idempotent :** Oui (MERGE sur cfg.Settings)

Crée la structure de configuration minimale V6 dans la base existante :

- Schémas `cfg`, `log`, `stg`, `dic`, `tbx`, `tbx_fr`, `tbx_master`, `ProjectData`, `review`, `report`
- Table `cfg.Settings` et ses paramètres (ContentDbName, PwaId, PwaLanguage, etc.)
- Table `cfg.PWA` (définition de l'instance Project Web App)
- Procédure `log.usp_WriteScriptLog` et table `log.ScriptExecutionLog`
- Tables d'import `stg.import_*` (stg.import_dictionary_od_fields, stg.import_dictionary_lookup_entries, stg.import_dictionary_projectdata_alias)

> **À personnaliser avant exécution :** rechercher `PARAMETRES CLIENT` dans le script (Ctrl+F) et ajuster `@ContentDbName`, `@PwaUrl`, `@PwaLanguage` selon le client.

---

### Étape 2 — Fondations et inventaire PSSE

**Script :** `v6_03a_Create_Foundations.sql`  
**Exécuter dans :** SSMS → base `SPR`  
**Idempotent :** Oui (DELETE par PwaId + MERGE + DROP/CREATE synonymes)

Crée l'ensemble des tables de staging et effectue l'inventaire physique de la base PSSE :

- Crée toutes les tables `stg.*` (ObjectInventory, ColumnInventory, PwaObjectScope, import_dictionary_*, etc.)
- Interroge `SP_SPR_POC_Contenu` pour inventorier tous les objets (vues, tables) et leurs colonnes
- Peuple `stg.ObjectInventory` et `stg.ColumnInventory`
- Peuple `cfg.PwaObjectScope` avec le scope des objets par PWA
- Supprime tous les synonymes `src_*` existants et les recrée vers `SP_SPR_POC_Contenu`

**Résultat attendu :** ~647 synonymes créés (`src_pjpub.*`, `src_pjrep.*`).

**Validation post-exécution :**

```sql
SELECT
    'ObjectInventory'   AS TableName, SourceDatabaseName, COUNT(*) AS Lignes
    FROM stg.ObjectInventory GROUP BY SourceDatabaseName
UNION ALL
SELECT 'ColumnInventory', SourceDatabaseName, COUNT(*)
    FROM stg.ColumnInventory GROUP BY SourceDatabaseName
UNION ALL
SELECT 'PwaObjectScope',  SourceDatabaseName, COUNT(*)
    FROM cfg.PwaObjectScope  GROUP BY SourceDatabaseName
ORDER BY TableName, SourceDatabaseName;

-- Synonymes créés
SELECT SCHEMA_NAME(schema_id) AS Schema_, COUNT(*) AS NbSynonymes
FROM sys.synonyms
WHERE SCHEMA_NAME(schema_id) LIKE 'src_%'
GROUP BY SCHEMA_NAME(schema_id)
ORDER BY Schema_;
```

---

### Étape 3 — Vues natives ProjectData

**Script :** `v6_04a_Create_Native_ProjectData_Views.sql`  
**Exécuter dans :** SSMS → base `SPR`  
**Idempotent :** Oui (DROP VIEW IF EXISTS + CREATE VIEW)

Crée les vues internes depuis un snapshot figé des définitions PSSE :

- Vues `tbx.*` (couche interne, alias anglais)
- Vues `tbx_fr.*` (couche interne, alias français)
- Vues `tbx_master.*` (couche consolidée)
- Vues `ProjectData.*` (couche publique, nom FR si `cfg.PWA.Language = 'FR'`, sinon nom EN)

Les vues utilisent les synonymes `src_*` créés à l'étape 2. Elles ne dépendent pas de `SP_SPR_POC_Contenu` au runtime — toute la résolution passe par les synonymes.

> Le script inclut un garde de cohérence : si les synonymes `src_*` ne pointent pas vers `cfg.Settings.ContentDbName`, l'exécution est interrompue avec une erreur explicite.

**Validation post-exécution :**

```sql
-- Compter les vues par couche
SELECT SCHEMA_NAME(schema_id) AS Couche, COUNT(*) AS NbVues
FROM sys.views
WHERE SCHEMA_NAME(schema_id) IN ('ProjectData','tbx','tbx_fr','tbx_master')
GROUP BY SCHEMA_NAME(schema_id)
ORDER BY Couche;

-- Vérifier qu'il n'y a aucune vue invalide
SELECT SCHEMA_NAME(v.schema_id) + '.' + v.name AS Vue, d.referenced_entity_name
FROM sys.views v
CROSS APPLY sys.dm_sql_referenced_entities(
    SCHEMA_NAME(v.schema_id) + '.' + v.name, 'OBJECT') d
WHERE d.is_ambiguous = 1 OR OBJECT_ID(d.referenced_entity_name) IS NULL;
```

---

### Étape 4 — Chargement des CSV du dictionnaire

**Script :** `Load-DictionaryCSV.ps1`  
**Exécuter dans :** Terminal PowerShell sur le poste DBA  
**Idempotent :** Oui (tronque les tables stg.import_* avant chargement si `TruncateLoadTablesBeforeCsvImport = 1`)
**Command :** .\Load-DictionaryCSV.ps1 -Server "sdevl01-sd2215\sd2215" -Database "SPR" -Truncate -Verbose

#### Pourquoi ce script PowerShell ?

Comme SQL Server `BULK INSERT` exige que le fichier soit accessible par le **compte de service SQL Server**, non par le poste du DBA et étant donné que les CSV sont sur le poste local et que `AllowFileSystemAccess = 0` dans les paramètres MTMD, `BULK INSERT` ne fonctionnera pas. On procède donc par un chargement via PowerShell. Ainsi le script `Load-DictionaryCSV.ps1` lit les CSV localement et pousse les lignes via **SqlBulkCopy** (protocole TDS pur). Le serveur SQL ne voit jamais le chemin du fichier.

#### Fichiers CSV requis

| Fichier CSV | Table SQL cible | Contenu |
|---|---|---|
| `Fields_ProjectData_Export.csv` | `stg.import_dictionary_od_fields` | Contrat OData FR : entités, champs, types Edm |
| `Lookups_ProjectServer_Export.csv` | `stg.import_dictionary_lookup_entries` | Tables de lookup PSSE (valeurs codifiées) |
| `ProjectData_Alias.csv` | `stg.import_dictionary_projectdata_alias` | Correspondances bilingues EN↔FR, positions, types |

#### Commande d'exécution

```powershell
# Depuis le dossier contenant les scripts
cd "C:\Users\franbreton\Downloads\SPR SmartBox"

.\Load-DictionaryCSV.ps1 `
    -Server   "sdevl01-sd2215\sd2215" `
    -Database "SPR" `
    -CsvPath  "C:\Users\franbreton\Downloads\SPR SmartBox" `
    -Truncate
```

Le paramètre `-Truncate` force la troncature des tables `stg.import_*` avant chargement, indépendamment du paramètre `TruncateLoadTablesBeforeCsvImport` dans `cfg.Settings`. Recommandé à chaque re-run pour garantir l'idempotence.

#### Résultat attendu dans la console

```
Connecte a sdevl01-sd2215\sd2215 / SPR
Fichiers attendus :
  od_fields  : Fields_ProjectData_Export.csv
  lookups    : Lookups_ProjectServer_Export.csv
  alias      : ProjectData_Alias.csv
Troncature   : True

stg.import_dictionary_od_fields         : 1058 lignes chargees.
stg.import_dictionary_lookup_entries    : 2161 lignes chargees.
stg.import_dictionary_projectdata_alias : 1071 lignes chargees.

Chargement termine. Total lignes inserees : 4290
Prochaine etape : executer v6_05a_Load_Dictionary_From_LoadTables.sql dans SSMS.
```

#### Validation post-chargement (depuis SSMS ou SSMS)

```sql
-- Vérifier que les 3 tables sont peuplées
SELECT 'stg.import_dictionary_od_fields'         AS Table_, COUNT(*) AS Lignes
    FROM stg.import_dictionary_od_fields
UNION ALL
SELECT 'stg.import_dictionary_lookup_entries',    COUNT(*)
    FROM stg.import_dictionary_lookup_entries
UNION ALL
SELECT 'stg.import_dictionary_projectdata_alias', COUNT(*)
    FROM stg.import_dictionary_projectdata_alias;

-- Aperçu des entités dans le fichier alias
SELECT DISTINCT Endpoint_EN, Endpoint_FR, EndpointMatchCountRaw
FROM stg.import_dictionary_projectdata_alias
ORDER BY Endpoint_EN;
```

#### Adapter pour un autre client

Les noms de fichiers et le chemin sont lus depuis `cfg.Settings` automatiquement. Pour un autre contexte :

```sql
-- Modifier dans cfg.Settings avant de relancer le script
UPDATE cfg.Settings SET SettingValue = N'C:\MonClient\CSV' WHERE SettingKey = N'DictionarySourcePath';
UPDATE cfg.Settings SET SettingValue = N'MonFichier_Fields.csv' WHERE SettingKey = N'DictionaryFile_ProjectData';
UPDATE cfg.Settings SET SettingValue = N'MonFichier_Lookups.csv' WHERE SettingKey = N'DictionaryFile_Lookups';
UPDATE cfg.Settings SET SettingValue = N'MonFichier_Alias.csv' WHERE SettingKey = N'DictionaryFile_ProjectDataAlias';
```

Ou passer les paramètres directement en ligne de commande :

```powershell
.\Load-DictionaryCSV.ps1 -Server "AUTRE-SERVEUR\INST" -Database "NomBase" -CsvPath "D:\Client\CSV" -Truncate
```

---

### Étape 5 — Construction du dictionnaire canonique

**Script :** `v6_05a_Load_Dictionary_From_LoadTables.sql`  
**Exécuter dans :** SSMS → base `SPR`  
**Idempotent :** Oui (MERGE + TRUNCATE des tables stg de travail)

Transforme les données CSV brutes en tables structurées consommables :

- Normalise `stg.import_*` → `cfg.dictionary_od_fields`, `cfg.dictionary_lookup_entries`, `cfg.dictionary_projectdata_alias`
- Enrichit `cfg.dictionary_od_fields` avec les équivalents anglais depuis le fichier alias
- Construit `dic.Entity` (40 entités OData) et `dic.EntityColumnMap` (1 071 colonnes)
- Construit `dic.LookupMap` (valeurs de lookup canoniques)
- Effectue le **matching OData ↔ PSSE** : cherche chaque colonne OData (`Column_EN`) dans `stg.ColumnInventory`
- Détermine la **source PSSE dominante** par entité (objet PSSE couvrant le plus de colonnes)
- Peuple `stg.EntitySource_Draft` avec un score de couverture et un niveau de confiance (`HIGH` / `MEDIUM` / `LOW` / `NONE`)
- Produit un **rapport qualité** dans `stg.DictionaryQualityIssue` (colonnes OData sans équivalent PSSE, entités sans source, etc.)

**Validation post-exécution :**

```sql
-- Résumé des tables construites
SELECT 'dic.Entity'                         AS Table_,  COUNT(*) AS Lignes FROM dic.Entity
UNION ALL SELECT 'dic.EntityColumnMap',                 COUNT(*) FROM dic.EntityColumnMap
UNION ALL SELECT 'dic.EntityColumnMap PRIMITIVE',       COUNT(*) FROM dic.EntityColumnMap WHERE ColumnClassification = 'PRIMITIVE'
UNION ALL SELECT 'dic.LookupMap',                       COUNT(*) FROM dic.LookupMap
ORDER BY Table_;

-- Top 10 entités par couverture PSSE
SELECT TOP 10
    EntityName_EN, ProposedSchema, ProposedObject,
    ColumnMatchCount, TotalPrimitiveCols,
    CoverageScore, ConfidenceLevel
FROM stg.EntitySource_Draft
ORDER BY CoverageScore DESC;

-- Issues qualité à traiter
SELECT IssueSeverity, IssueCode, COUNT(*) AS Nb
FROM stg.DictionaryQualityIssue
GROUP BY IssueSeverity, IssueCode
ORDER BY IssueSeverity, IssueCode;
```

---

### Étape 6 — Publication des colonnes

**Script :** `v6_06a_Build_EntityColumnPublication.sql`  
**Exécuter dans :** SSMS → base `SPR`  
**Idempotent :** Oui (MERGE avec protection des overrides manuels `BindingStatus/MapStatus = 'MANUAL'`)

Construit la couche de publication canonique — source de vérité pour la génération de vues :

- Construit `dic.EntityBinding` : source PSSE primaire retenue par entité (clause `FROM` des vues futures)
- Détecte les jointures secondaires nécessaires → `dic.EntityJoin` + `stg.EntityJoin_Draft`
- Construit `dic.EntityColumnPublication` : une ligne par colonne OData par entité, avec :
  - `SourceExpression` : expression SQL à inclure dans le SELECT (`src.ColonnePSSE`)
  - `FallbackExpression` : `CAST(NULL AS type)` pour les colonnes sans équivalent PSSE
  - `MapStatus` : `MAPPED` | `MAPPED_NEEDS_JOIN` | `UNMAPPED` | `NAVIGATION`
  - `IsPublished` : `0` pour `MAPPED_NEEDS_JOIN` (jointure manquante), `1` pour tous les autres

| MapStatus | Signification | IsPublished |
|---|---|---|
| `MAPPED` | Colonne PSSE trouvée, source résolue | 1 |
| `MAPPED_NEEDS_JOIN` | Colonne PSSE trouvée mais jointure secondaire non définie | 0 |
| `UNMAPPED` | Aucune colonne PSSE correspondante → CAST(NULL) | 1 |
| `NAVIGATION` | Lien navigationnel OData (non PRIMITIVE) | 1 |

**Validation post-exécution :**

```sql
-- Distribution des statuts
SELECT MapStatus, IsPublished, COUNT(*) AS Nb
FROM dic.EntityColumnPublication
GROUP BY MapStatus, IsPublished
ORDER BY MapStatus;

-- Colonnes MAPPED_NEEDS_JOIN à traiter manuellement
SELECT EntityName_EN, Column_EN, SourceExpression
FROM dic.EntityColumnPublication
WHERE MapStatus = 'MAPPED_NEEDS_JOIN'
ORDER BY EntityName_EN, Column_EN;

-- Liaisons retenues par entité
SELECT EntityName_EN, PsseSchemaName, PsseObjectName,
       CoverageScore, ConfidenceLevel, BindingStatus
FROM dic.EntityBinding
ORDER BY CoverageScore DESC;
```

---

### Étape 7 — Génération des vues finales

**Script :** `v6_07a_Generate_Views_From_Publication.sql`  
**Exécuter dans :** SSMS → base `SPR`  
**Idempotent :** Oui (`CREATE OR ALTER VIEW`)

Génère dynamiquement toutes les vues depuis `dic.EntityColumnPublication` :

- `ProjectData.<EntityName>` — vues publiques (nom FR si `cfg.PWA.Language = 'FR'`, sinon nom EN)
- `tbx.<EntityName>` — couche interne avec alias anglais
- `tbx_fr.<EntityName>` — couche interne avec alias français

Les colonnes `MAPPED_NEEDS_JOIN` (`IsPublished = 0`) sont automatiquement exclues des vues jusqu'à ce qu'une `JoinExpression` soit définie dans `dic.EntityJoin` et que v6_06a soit rejoué.

En cas d'erreur sur une entité, le script continue et journalise l'erreur dans `report.ViewStackValidation`.

**Validation post-exécution :**

```sql
-- Résumé des vues créées / échouées
SELECT ViewSchema, ValidationStatus, COUNT(*) AS Nb
FROM report.ViewStackValidation
ORDER BY ValidationStatus DESC, ViewSchema;

-- Toutes les vues générées
SELECT SCHEMA_NAME(schema_id) AS Couche, COUNT(*) AS NbVues
FROM sys.views
WHERE SCHEMA_NAME(schema_id) IN ('ProjectData','tbx','tbx_fr')
GROUP BY SCHEMA_NAME(schema_id);

-- Tester une vue (adapter le nom selon cfg.PWA.Language)
SELECT TOP 5 * FROM ProjectData.Projets;   -- tenant FR
SELECT TOP 5 * FROM ProjectData.Projects;  -- tenant EN
```

---

## Reprise complète — repartir de zéro

Pour réinitialiser l'environnement sans supprimer la base ni les paramètres `cfg.Settings` :

**Script :** `v6_00z_Reset_SmartBox_V6_Working_Tables.sql`  
**Exécuter dans :** SSMS → base `SPR`

Le script supprime :
- Toutes les vues générées (`ProjectData.*`, `tbx.*`, `tbx_fr.*`, `tbx_master.*`)
- Tous les synonymes `src_*`
- Toutes les tables de travail `stg.*`, `dic.*`, `review.*`, `report.*`, `log.*`
- Toutes les tables `cfg.*` sauf `cfg.Settings` et `cfg.PWA`

Il **conserve** par défaut :
- `cfg.Settings` et `cfg.PWA` (configuration client)
- aucune autre table de travail

Après la remise à zéro, reprendre à l'**étape 1** si tu veux réappliquer la configuration, sinon à l'**étape 2** si `cfg.Settings` et `cfg.PWA` sont déjà correctes.

---

## Récapitulatif

| Étape | Script / Commande | Outil | Durée estimée |
|---|---|---|---|
| 0 | `v6_01a_Prereq_Diagnostic.sql` | SSMS | < 1 min |
| 1 | `v6_02a_Attach_Existing_SmartBox_Database.sql` | SSMS | < 1 min |
| 2 | `v6_03a_Create_Foundations.sql` | SSMS | 1–3 min |
| 3 | `v6_04a_Create_Native_ProjectData_Views.sql` | SSMS | 1–2 min |
| 4 | `Load-DictionaryCSV.ps1` | PowerShell | < 1 min |
| 5 | `v6_05a_Load_Dictionary_From_LoadTables.sql` | SSMS | < 1 min |
| 6 | `v6_06a_Build_EntityColumnPublication.sql` | SSMS | < 1 min |
| 7 | `v6_07a_Generate_Views_From_Publication.sql` | SSMS | < 1 min |
| Reset | `v6_00z_Reset_SmartBox_V6_Working_Tables.sql` | SSMS | < 1 min |
