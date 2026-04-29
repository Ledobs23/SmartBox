# Plan de travail — SmartBox V6 Refonte Architecture

**Dernière mise à jour :** 2026-04-28  
**Contexte :** Continuation de la session d'architecture. Reprendre ici si interruption de crédits.

---

## Objectif de livraison court terme

Terminer la trousse SmartBox V6 au plus vite avec une architecture suffisamment stable pour supporter les prochains projets sans réouvrir le chantier de fond.

### Cible finale recherchée

1. **Tout ce qui est natif et connu** dans les endpoints OData PSSE est seedé de façon **hardcodée et déterministe** à partir des fichiers de référence.
2. **Tout ce qui dépend du projet de migration** (champs personnalisés simples, lookups, libellés variables) est **détecté et mappé automatiquement** depuis les tables sources PSSE (`pjpub`, `pjrep`).
3. **Aucune colonne native ne dépend de l'auto-découverte**.
4. **Aucun CAST(NULL) silencieux** sur des colonnes réelles en production finale.
5. La trousse doit pouvoir être rejouée sur un autre environnement en ne changeant que la configuration (`ContentDbName`, synonymes, PWA, dictionnaire CSV).

### Définition de "trousse terminée"

La trousse est considérée terminée lorsque :

- `v6_00z` → `v6_07a` s'exécutent sans correction manuelle intermédiaire sur MTMD
- les vues `ProjectData.*` EN et FR prioritaires se chargent
- les colonnes natives attendues proviennent du seed
- les champs personnalisés connus du client sont récupérés automatiquement depuis PSSE
- il n'y a plus de dépendance fonctionnelle à `v6_04a` pour la génération finale des vues

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

### Répartition des responsabilités (gelée pour finir vite)

1. **`v6_04a`** = référence native / oracle de régression pendant la transition.  
   Il ne doit plus devenir le propriétaire de la logique finale des vues dynamiques.

2. **`v6_05b`** = propriétaire du **seed natif**.  
   Il alimente les bindings, jointures et colonnes connues/stables à partir des fichiers de référence OData.

3. **`v6_06a`** = propriétaire du **complément variable par environnement**.  
   Il ne doit servir qu'à :
   - résoudre les champs personnalisés
   - générer les jointures dérivées nécessaires aux CFs/lookups
   - journaliser les écarts restants

4. **`v6_07a`** = propriétaire exclusif de la **génération mécanique des couches de vues**.  
   Il ne doit pas contenir de logique métier de mapping autre que la projection des métadonnées de publication.

5. **`tbx_fr`** = schéma en voie de retrait.  
   Aucun nouveau développement ne doit dépendre de `tbx_fr`. Si une compatibilité temporaire est nécessaire, elle doit être explicitement documentée comme transition.

### Contrat canonique de nommage

- Les noms d'entités canoniques côté contrat public sont les noms **EN pluriels OData** : `Projects`, `Tasks`, `Assignments`, `Resources`, `Timesheets`, etc.
- Les noms FR publics dérivent du dictionnaire d'alias : `Projets`, `Tâches`, `Affectations`, `Ressources`, `FeuillesDeTemps`, etc.
- Les couches cibles finales sont :
  - `tbx_master.<EntityName_EN>`
  - `tbx.<EntityName_EN>`
  - `ProjectData.<EntityName_EN>`
  - `ProjectData.<EntityName_FR>`
- Le plan doit éviter tout doublon de type `Timesheet` vs `Timesheets` ou toute variation non documentée de nom d'entité.

---

## Sources disponibles

| Fichier | Rôle |
|---|---|
| `Equivalence des tables OData_sans custom field.sql` | Référence native : Projects, Tasks, Assignments, Resources, TimeSet, Timesheets |
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

## Hors périmètre pour accélérer la livraison

1. Pas de refonte supplémentaire de `v6_01a` à `v6_03a` sauf blocage réel.
2. Pas de nouvelles couches de consommation au-delà de `tbx_master`, `tbx`, `ProjectData`.
3. Pas de support long terme de `tbx_fr` comme surface publique.
4. Pas de correction manuelle entité par entité pour des colonnes natives déjà couvertes par les fichiers de référence.
5. Pas d'optimisation cosmétique prioritaire de documentation tant que le pipeline final n'est pas stable.

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
Projects, Tasks, Assignments, Resources, TimeSet, Timesheets, PortfolioAnalyses, PortfolioAnalysisProjects, AssignmentBaselines, AssignmentBaselineTimephasedDataSet, AssignmentTimephasedDataSet, BusinessDrivers, BusinessDriverDepartments, Deliverables, CostScenarioProjects, CostConstraintScenarios, Engagements, EngagementsComments, EngagementsTimephasedDataSet, Prioritizations, PrioritizationDrivers, PrioritizationDriverRelations, ProjectBaselines, ProjectWorkflowStageDataSet, ResourceConstraintScenarios, ResourceScenarioProjects, ResourceTimephasedDataSet, ResourceDemandTimephasedDataSet, Risks, RiskTaskAssociations, Issues, IssueTaskAssociations, TaskBaselines, TaskBaselineTimephasedDataSet, TaskTimephasedDataSet, TimesheetClasses, TimesheetPeriods, TimesheetLines, FiscalPeriods, TimesheetLineActualDataSet

**Comment construire le seed :**
- Lire chaque fichier de référence
- Pour chaque entité : extraire SourceAlias (alias de table dans la requête), SourceExpression (nom de colonne PSSE), Column_EN (alias OData anglais tel quel), Column_FR (alias français tel quel)
- Les CAST(NULL) explicites dans les fichiers de référence = NAVIGATION

**Critères de sortie de la phase 1 :**
- 100 % des entités natives listées sont seedées
- 0 doublon `(EntityName_EN, Column_EN)` dans `dic.EntityColumnPublication`
- 0 doublon `(EntityName_EN, JoinTag)` dans `dic.EntityJoin`
- 100 % des colonnes natives des fichiers de référence sont marquées `MAPPED` ou `NAVIGATION`
- le seed natif devient la source de vérité des colonnes connues, sans dépendre de l'auto-découverte

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

**Critères de sortie de la phase 2 :**
- 0 GUID hardcodé résiduel dans `v6_06a`
- les CFs simples et CFs lookup sont résolus automatiquement par tables sources PSSE
- toute colonne restant `UNMAPPED` après auto-découverte est journalisée explicitement
- aucune colonne native n'est rétrogradée par l'auto-découverte

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

**Critères de sortie de la phase 3 :**
- `tbx_master` lit directement les synonymes `src_*`
- `tbx` lit uniquement `tbx_master`
- `ProjectData` lit uniquement `tbx`
- aucune vue finale générée par `v6_07a` ne dépend directement de `src_*`
- le schéma `tbx_fr` n'est plus requis pour le contrat final

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

**Préflight / sécurité avant refonte :**
- Sauvegarder les définitions actuelles des vues avant toute refonte majeure
- Conserver un point Git propre avant démarrage de la Phase 1
- Vérifier la collation attendue de la BDI avant les phases de matching normalisé
- Noter explicitement si une compatibilité temporaire avec des consommateurs `tbx_fr` est requise

---

### PHASE 5 — Validation sur MTMD

**Séquence de test :**
0. Vérifier la collation de la base (`Latin1_General_CI_AS_KS_WS`) et sauvegarder les vues existantes
1. v6_00z — reset tables de travail
2. v6_02a — attacher base existante (ContentDbName = SP_SPR_POC_Contenu)
3. v6_03a — créer fondations (cfg, dic, stg, etc.)
4. v6_04a — snapshot vues internes PSSE (mode FROZEN_SNAPSHOT, utilisé comme référence/oracle de comparaison pendant la transition)
5. v6_05a — chargement dictionnaire existant (à garder en parallèle pendant transition)
6. **v6_05b** — seed natif depuis fichiers de référence (nouveau)
7. v6_06a — auto-découverte CFs + publication
8. v6_07a — génération vues 3 couches

**Checks de validation :**
- 0 colonne native `UNMAPPED` dans `dic.EntityColumnPublication` après pipeline complet
- 0 vue invalide ou en erreur dans `report.ViewStackValidation` sur le périmètre prioritaire
- Toutes les colonnes des fichiers de référence présentes dans `tbx.*`
- Colonnes CFs clients MTMD présentes dans `tbx.*` (Axe, StatutProjet, etc.)
- `ProjectData.Projects`, `ProjectData.Projets`, `ProjectData.Tasks`, `ProjectData.Tâches`, `ProjectData.Assignments`, `ProjectData.Affectations`, `ProjectData.Timesheets`, `ProjectData.FeuillesDeTemps` accessibles et correctes
- `tbx_master.*` sert bien de source unique à `tbx.*`
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

**État Git à rafraîchir avant reprise :**
- Toujours vérifier `git status --short` avant de commencer la Phase 1
- Ne pas se fier à cette section comme source de vérité sur les commits en attente

---

## Ordre d'exécution recommandé pour reprise

1. Geler le scope et vérifier l'état Git réel
2. Sauvegarder les vues actuelles + vérifier la collation
3. Phase 1 : construire `v6_05b` depuis les fichiers de référence
4. Phase 2 : réviser `v6_06a` pour que l'auto-découverte ne traite que le variable par environnement
5. Phase 3 : réviser `v6_07a` pour appliquer strictement le modèle 3 couches
6. Phase 4 : nettoyage ciblé (`v6_05a` normalisation F2, `.gitignore`, compatibilité transitoire si nécessaire)
7. Phase 5 : validation MTMD complète
8. Commit + push final
