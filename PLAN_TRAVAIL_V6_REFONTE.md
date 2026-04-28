# Plan de travail — SmartBox V6 Refonte Architecture

**Dernière mise à jour :** 2026-04-28  
**Contexte :** Continuation de la session d'architecture. Reprendre ici si interruption de crédits.

---

## Décisions architecturales confirmées

### Modèle de vues en 3 couches

```
PSSE (synonymes src_pjrep.*, src_pjpub.*)
    ↓  toutes les jointures ici, une seule fois
tbx_master.*   — vue large et brute : toutes les colonnes PSSE assemblées,
                  noms techniques, pas de transformation
    ↓  transformation ici, source = tbx_master uniquement
tbx.*          — mapping : aliases EN et FR, CASTs, colonnes nommées proprement
    ↓  filtre langue ici
ProjectData.*  — contrat stable
                  .Projects, .Tasks, .Resources... (colonnes EN)
                  .Projets,  .Tâches, .Ressources... (colonnes FR)
```

### Règles de design validées

1. **CAST(NULL)** uniquement pour les colonnes NAVIGATION (liens OData inter-entités). Jamais pour des colonnes réelles.
2. **UNMAPPED** = signal d'erreur à logger, pas un comportement silencieux acceptable.
3. **tbx_fr** supprimé comme schéma séparé — le FR vit dans ProjectData directement.
4. **tbx** est une vue pipeline interne (couche de mapping), pas une surface consommateur.
5. **tbx_master** fait toutes les jointures une seule fois — tbx et ProjectData n'accèdent plus jamais aux synonymes directement.
6. **Aucun GUID hardcodé** — tous les UID résolus dynamiquement depuis MSP_CUSTOM_FIELDS par nom normalisé.
7. **Aucun mapping manuel** pour les colonnes natives — le seed vient des fichiers de référence OData.
8. **Portabilité totale** — changer d'environnement PSSE = reconfigurer ContentDbName + synonymes uniquement.

---

## Sources disponibles

| Fichier | Rôle |
|---|---|
| `Equivalence des tables OData_sans custom field.sql` | Référence native : Projects, Tasks, Assignments, Resources, TimeSet, Timesheet |
| `Requetes pour les vues liees au portefeuille.sql` | Référence native : PortfolioAnalyses, PortfolioAnalysisProjects |
| `Requetes pour les vues liees aux affectations.sql` | Référence native : AssignmentBaselines, AssignmentBaselineTimephased, AssignmentTimephased |
| `Requetes pour les vues liees aux business driver, livrables et couts.sql` | Référence native : BusinessDrivers, BusinessDriverDepartments, Deliverables, CostScenario, CostConstraint |
| `Requetes pour les vues liees aux engagements.sql` | Référence native : Engagements, EngagementsComments, EngagementsTimephased |
| `Requetes pour les vues liees aux priorites.sql` | Référence native : Prioritizations, PrioritizationDrivers, PrioritizationDriverRelations |
| `Requetes pour les vues liees aux projets.sql` | Référence native : ProjectBaselines, ProjectWorkflowStageDataSet |
| `Requetes pour les vues liees aux ressources.sql` | Référence native : ResourceConstraintScenarios, ResourceScenarioProjects, ResourceTimephased, ResourceDemandTimephased |
| `Requetes pour les vues liees aux risques et problemes.sql` | Référence native : Risks, RiskTaskAssociations, Issues, IssueTaskAssociations |
| `Requetes pour les vues liees aux taches.sql` | Référence native : TaskBaselines, TaskBaselineTimephased, TaskTimephased |
| `Requetes pour les vues liees aux timesheet.sql` | Référence native : TimesheetClasses, TimesheetPeriods, TimesheetLines, FiscalPeriods, TimesheetLineActualDataSet |
| `Requetes corrections.sql` | Requêtes corrigées avec CFs clients (Tasks + Assignments avec ITT et autres CFs) |

---

## Plan de travail — Phases

---

### PHASE 1 — Seed natif (nouveau script v6_05b)

**Objectif :** Peupler `dic.EntityBinding`, `dic.EntityJoin` et `dic.EntityColumnPublication` à partir des fichiers de référence OData, pour toutes les colonnes natives (stables entre installations).

**Ce que le script doit faire :**

1. Pour chaque entité OData : insérer dans `dic.EntityBinding` la table PSSE principale (clause FROM des requêtes de référence).

2. Pour chaque jointure des requêtes de référence : insérer dans `dic.EntityJoin` avec `JoinStatus = 'MANUAL'` (les jointures natives ne doivent jamais être écrasées par l'auto-découverte).

3. Pour chaque colonne SELECT des requêtes de référence :
   - Si la colonne est un `CAST(NULL)` → `MapStatus = 'NAVIGATION'`
   - Sinon → `MapStatus = 'MAPPED'`, `SourceExpression` = expression SQL PSSE, `Column_EN` = alias anglais, `Column_FR` = alias français

4. Le script est idempotent (MERGE, pas INSERT brut).

5. Les CFs clients (colonnes qui varient par environnement) ne sont PAS dans ce seed — elles sont gérées par v6_06a auto-découverte.

**Entités à couvrir (40 au total) :**
Projects, Tasks, Assignments, Resources, TimeSet, Timesheet, PortfolioAnalyses, PortfolioAnalysisProjects, AssignmentBaselines, AssignmentBaselineTimephasedDataSet, AssignmentTimephasedDataSet, BusinessDrivers, BusinessDriverDepartments, Deliverables, CostScenarioProjects, CostConstraintScenarios, Engagements, EngagementsComments, EngagementsTimephasedDataSet, Prioritizations, PrioritizationDrivers, PrioritizationDriverRelations, ProjectBaselines, ProjectWorkflowStageDataSet, ResourceConstraintScenarios, ResourceScenarioProjects, ResourceTimephasedDataSet, ResourceDemandTimephasedDataSet, Risks, RiskTaskAssociations, Issues, IssueTaskAssociations, TaskBaselines, TaskBaselineTimephasedDataSet, TaskTimephasedDataSet, TimesheetClasses, TimesheetPeriods, TimesheetLines, FiscalPeriods, TimesheetLineActualDataSet

**Comment construire le seed :**
- Lire chaque fichier de référence
- Pour chaque entité : extraire SourceAlias (alias de table dans la requête), SourceExpression (nom de colonne PSSE), Column_EN (alias OData anglais tel quel), Column_FR (alias français tel quel)
- Les CAST(NULL) explicites dans les fichiers de référence = NAVIGATION

---

### PHASE 2 — Auto-découverte CFs généralisée (révision v6_06a)

**Objectif :** Après le seed natif, détecter automatiquement tous les champs personnalisés PSSE de l'installation et les ajouter dans `dic.EntityColumnPublication`.

**Logique actuelle à conserver :**
- ETAPE E7 : match normalisé entre colonnes UNMAPPED de l'ECP et `MSP_CUSTOM_FIELDS` → résolution des CFs simples (non-lookup)
- ETAPE E8 : CFs de type Lookup (MD_PROP_T=21) → génération automatique de deux jointures (jCF_<uid> + jCF_<uid>_L) dans `dic.EntityJoin`
- Phase P : CFs spéciaux avec jointures nommées explicitement (ex. jITT pour "Indicateur type tâche") — UID résolu dynamiquement, pas hardcodé

**À ajouter / corriger :**
- Généraliser E7 pour couvrir toutes les entités (Projects, Resources aussi, pas seulement Tasks/Assignments)
- Si après E7+E8 une colonne reste UNMAPPED → logger en WARN dans `stg.EntityDraftBuildLog`, ne pas émettre CAST(NULL) silencieux
- Supprimer tout GUID hardcodé résiduel

---

### PHASE 3 — Génération 3 couches (révision v6_07a)

**Objectif :** Restructurer la génération de vues pour produire les 3 couches dans l'ordre : tbx_master → tbx → ProjectData (EN + FR).

**Couche 1 — tbx_master** :
- SELECT large depuis les sources PSSE directement (via synonymes)
- Toutes les jointures incluses (EntityJoin complet)
- Noms de colonnes techniques PSSE (pas encore d'alias propres)
- Une vue par entité : `tbx_master.Projects`, `tbx_master.Tasks`, etc.

**Couche 2 — tbx** :
- SELECT depuis `tbx_master.*`
- Applique tous les aliases EN et FR côte à côte
- Applique les CASTs pour NAVIGATION
- Une vue par entité : `tbx.Projects`, `tbx.Tasks`, etc.
- Vue pipeline interne — pas destinée aux consommateurs finaux directs

**Couche 3 — ProjectData** :
- SELECT depuis `tbx.*`
- Vue EN : `ProjectData.Projects` → colonnes avec alias anglais uniquement
- Vue FR : `ProjectData.Projets` → colonnes avec alias français uniquement
- Contrat stable — ne change que par décision intentionnelle

**Supprimer :**
- Blocs de génération `tbx_fr.*` (remplacés par ProjectData FR)
- Génération indépendante parallèle des 4 variantes (remplacée par la cascade 3 couches)

---

### PHASE 4 — Nettoyage et cohérence des scripts existants

**v6_05a :**
- Backporter la normalisation `LOWER(REPLACE(...))` dans Phase F2 (correspondance noms CFs)
- Actuellement Phase F2 utilise encore un match exact — risque de rater des CFs avec espaces/accents

**v6_02a :**
- Déjà corrigé (paramètres portables, validation @ContentDbName obligatoire)
- Valider que FrozenViewSnapshotName est bien auto-dérivé si NULL

**v6_04a :**
- Déjà corrigé (suppression hardcoding MTMD, auto-dérivation générique)

**v6_06a :**
- Déjà corrigé (Phase P portabilité UID, E7 filtre entity type, E8 Lookup auto)
- Valider cohérence après refonte Phase 1/2

**v6_07a :**
- Refonte complète Phase 3 ci-dessus

**.gitignore :**
- Ajouter `BACKUP_Views_*.sql` pour exclure les fichiers de sauvegarde locaux

---

### PHASE 5 — Validation sur MTMD

**Séquence de test :**
1. v6_00z — reset tables de travail
2. v6_02a — attacher base existante (ContentDbName = SP_SPR_POC_Contenu)
3. v6_03a — créer fondations (cfg, dic, stg, etc.)
4. v6_04a — snapshot vues internes PSSE (mode FROZEN_SNAPSHOT)
5. v6_05a — chargement dictionnaire existant (à garder en parallèle pendant transition)
6. **v6_05b** — seed natif depuis fichiers de référence (nouveau)
7. v6_06a — auto-découverte CFs + publication
8. v6_07a — génération vues 3 couches

**Checks de validation :**
- 0 vue UNMAPPED dans `dic.EntityColumnPublication` après pipeline complet
- 0 vue invalide dans `sys.objects` après v6_07a
- Toutes les colonnes des fichiers de référence présentes dans tbx.*
- Colonnes CFs clients MTMD présentes dans tbx.* (Axe, StatutProjet, etc.)
- `ProjectData.Projects` et `ProjectData.Projets` accessibles et correctes
- Test de portabilité : changer ContentDbName → synonymes → re-exécuter → vues correctes

---

## État des scripts au moment de la rédaction de ce plan

| Script | État |
|---|---|
| v6_00z | Stable, non modifié |
| v6_02a | Corrigé — portabilité paramètres |
| v6_03a | Stable |
| v6_04a | Corrigé — portabilité FrozenViewSnapshotName |
| v6_05a | Stable — backport normalisation F2 à faire (Phase 4) |
| v6_05b | À créer (Phase 1) |
| v6_06a | Corrigé — Phase P portabilité UID, E7/E8 auto-découverte |
| v6_07a | Corrigé — JoinDependsOn, NAVIGATION CAST — refonte 3 couches à faire (Phase 3) |

**Commits en attente (à pousser avant de commencer la Phase 1) :**
- v6_02a, v6_04a, v6_06a, v6_07a — toutes les corrections de la session précédente

---

## Ordre d'exécution recommandé pour reprise

1. Git commit + push des corrections existantes (v6_02a, v6_04a, v6_06a, v6_07a)
2. Phase 1 : construire v6_05b depuis les fichiers de référence
3. Phase 2 : réviser v6_06a auto-découverte si nécessaire après test
4. Phase 3 : réviser v6_07a génération 3 couches
5. Phase 4 : nettoyage (v6_05a normalisation F2, .gitignore)
6. Phase 5 : validation MTMD complète
7. Git commit + push final
