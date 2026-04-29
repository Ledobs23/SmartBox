# Rapport de concordance des vues `ProjectData`

## Objet

Ce rapport résume l'analyse des vues `ProjectData.*` afin d'identifier :

- les vues qui ne se chargent pas proprement dans un diagnostic global ;
- les colonnes `MAPPED` ou `MAPPED_NEEDS_JOIN` qui retournent `NULL` sur toutes les lignes d'une vue non vide ;
- le comportement de `stg.ODataPsseExactColumnMatch`, en particulier la présence apparente de nombreux "doublons".

Les données brutes de l'analyse se trouvent dans :

- [smartbox_projectdata_analysis](</c:/Users/franbreton/Downloads/SPR SmartBox/Correction/smartbox_projectdata_analysis>)
- [smartbox_projectdata_by_entity](</c:/Users/franbreton/Downloads/SPR SmartBox/Correction/smartbox_projectdata_by_entity>)

Les fichiers les plus utiles sont :

- [entity_summary.csv](</c:/Users/franbreton/Downloads/SPR SmartBox/Correction/smartbox_projectdata_by_entity/entity_summary.csv>)
- [mapped_all_null_non_empty_all_entities.csv](</c:/Users/franbreton/Downloads/SPR SmartBox/Correction/smartbox_projectdata_by_entity/mapped_all_null_non_empty_all_entities.csv>)
- [mapped_all_null_en_with_fanout.csv](</c:/Users/franbreton/Downloads/SPR SmartBox/Correction/smartbox_projectdata_by_entity/mapped_all_null_en_with_fanout.csv>)

## Méthode

L'analyse a été faite en deux temps :

1. un balayage global de toutes les vues `ProjectData.*`, colonne par colonne ;
2. un découpage par `EntityName_EN` pour réduire la taille des lots, contourner les erreurs mémoire du diagnostic global, et produire un dossier par entité.

Important : une vue avec `0` ligne produit mécaniquement des colonnes "tout NULL". Ces cas ont été séparés des vrais problèmes, c'est-à-dire des colonnes mappées mais entièrement nulles sur des vues non vides.

## Résumé exécutif

- Le diagnostic global a échoué avec une erreur mémoire SQL `701` sur `Assignments`, `Affectations`, `Tasks` et `Tâches`, mais les mêmes vues répondent lorsqu'on les analyse en lots plus petits.
- Il n'y a **aucun vrai doublon exact** dans `stg.ODataPsseExactColumnMatch`.
- En revanche, cette table contient un **grand nombre de candidats** pour une même colonne OData, ce qui est normal pour une table de matching intermédiaire, mais qui peut biaiser le choix final de source si le ranking n'est pas assez strict.
- Les entités les plus à risque en ce moment sont `Projects`, `Assignments`, `Tasks` et `Resources`.

## Résultats principaux

### 1. Vues touchées par l'erreur mémoire du diagnostic global

Le balayage global a signalé :

- `ProjectData.Assignments`
- `ProjectData.Affectations`
- `ProjectData.Tasks`
- `ProjectData.Tâches`

Erreur observée :

```text
There is insufficient system memory in resource pool 'default' to run this query.
```

Ce point concerne la **requête de diagnostic** elle-même. La validation découpée par entité montre que ces vues sont interrogeables :

- `Assignments` : 1772 lignes, 31 colonnes tout `NULL`, dont 26 mappées
- `Affectations` : 1772 lignes, 31 colonnes tout `NULL`, dont 26 mappées
- `Tasks` : 22462 lignes, 24 colonnes tout `NULL`, dont 15 mappées
- `Tâches` : 22462 lignes, 24 colonnes tout `NULL`, dont 15 mappées

### 2. Entités prioritaires

Les entités les plus chargées en colonnes mappées mais entièrement nulles sur des vues non vides sont :

| Entité | Vues | Colonnes tout NULL | Colonnes mappées tout NULL | Colonnes avec fan-out candidat | Max candidats |
|---|---|---:|---:|---:|---:|
| `Projects` | `Projects`, `Projets` | 74 | 56 | 37 | 53 |
| `Assignments` | `Assignments`, `Affectations` | 62 | 52 | 62 | 53 |
| `Tasks` | `Tasks`, `Tâches` | 48 | 30 | 83 | 53 |
| `Resources` | `Resources`, `Ressources` | 22 | 16 | 31 | 14 |
| `ProjectBaselines` | `ProjectBaselines`, `PlanningsDeRéférenceProjet` | 8 | 6 | 4 | 53 |
| `TaskBaselines` | `TaskBaselines`, `PlanningsDeRéférenceTâche` | 12 | 6 | 11 | 53 |
| `TimesheetClasses` | `TimesheetClasses`, `ClassesFeuilleDeTemps` | 2 | 2 | 5 | 32 |

Source : [entity_summary.csv](</c:/Users/franbreton/Downloads/SPR SmartBox/Correction/smartbox_projectdata_by_entity/entity_summary.csv>)

### 3. Colonnes suspectes par entité

#### `Projects / Projets`

Grand lot de colonnes mappées mais entièrement nulles, notamment :

- `OptimizerDecisionID`
- `PlannerDecisionID`
- `OptimizerCommitDate`
- `OptimizerDecisionAliasLookupTableId`
- `OptimizerDecisionName`
- `OptimizerSolutionName`
- `ParentProjectId`
- `PlannerCommitDate`
- `PlannerDecisionAliasLookupTableId`
- `PlannerDecisionName`
- `PlannerEndDate`
- `PlannerSolutionName`
- `PlannerStartDate`
- `ProjectStatusDate`
- `ResourcePlanUtilizationDate`

Interprétation :

- plusieurs de ces colonnes ont peu de candidats, souvent `2` ou `3`, donc le problème ne semble pas venir d'une explosion de matching ;
- il s'agit plus probablement d'un choix de source acceptable syntaxiquement, mais vide dans le contexte réel MTMD, ou d'un besoin de jointure/override métier plus précis. (Il est confirmé que ces valeurs sont vides dans les données du service Project.)

#### `Assignments / Affectations`

Très gros bloc de colonnes mappées mais entièrement nulles, entre autres :

- `AssignmentAllUpdatesApplied`
- `AssignmentUpdatesAppliedDate`
- plusieurs colonnes MTMD suffixées ou libellées comme `_T` et `_R`
- `Afficherrapport_T`
- `Catdepenses_R`
- `CodelivrableGID_T`
- `Commentaire_GPR_T`
- `DateapprouvéeDGEI_T`
- `DatedemandéeDGT_T`
- `Dateoccupation_T`
- `DernierPCatteinttache_T`
- `Servicesderessources_R`
- `Servicespublics_T`
- `Statut_T`
- `Typedecoût_R`
- `Typeterrain_T`

Interprétation :

- ici, le problème ressemble surtout à des colonnes natives ou custom présentes dans `MSP_EpmAssignment_UserView` mais vides dans les données ;
- le fan-out n'explique pas tout, car plusieurs de ces colonnes n'ont pas de conflit candidat fort dans `ODataPsseExactColumnMatch`.

#### `Tasks / Tâches`

Colonnes mappées mais entièrement nulles, notamment :

- `TaskStartDateString`
- `TaskFinishDateString`
- `TaskDurationString`
- `TaskDeliverableStartDate`
- `TaskDeliverableFinishDate`
- `TaskHyperLinkSubAddress`
- plusieurs colonnes MTMD : `CodelivrableGID`, `DateapprouvéeDGEI`, `DatedemandéeDGT`, `Dateoccupation`, `NodedossierAGI`, `Prisedepossessionlégale`, `Servicespublics`, `Statut`, `Typeterrain`

Interprétation :

- une partie du lot ressemble à des colonnes métier réellement vides dans la source ;
- les colonnes date/chaîne de tâche méritent quand même vérification, car elles devraient souvent être peuplées si la vue source retenue est la bonne.

#### `Resources / Ressources`

Colonnes mappées mais entièrement nulles :

- `ResourceCode`
- `ResourceCostCenter`
- `ResourceEarliestAvailableFrom`
- `ResourceHyperlinkHref`
- `ResourceLatestAvailableTo`
- `ResourceWorkgroup`
- `Servicesderessources`
- `Typedecoût`

Interprétation :

- plusieurs colonnes ont seulement `2` candidats, donc là encore ce n'est pas d'abord un problème de doublons massifs ;
- cela ressemble davantage à un besoin de revue de contenu réel dans la source retenue.

#### `TimesheetClasses / ClassesFeuilleDeTemps`

Cas petit mais révélateur :

- `DepartmentName / NomService`
- `TimesheetClassId`

La source active est `pjrep.MSP_TimesheetClass_UserView`, qui ne contient que `8` colonnes. Pourtant, la table de matching affiche plusieurs candidats pour certaines colonnes. Ce comportement est **attendu** pour une table de candidats, mais mérite une réduction plus stricte avant publication.

## `ODataPsseExactColumnMatch` : doublons ou candidats ?

### Constat

Le fichier [table_4.csv](</c:/Users/franbreton/Downloads/SPR SmartBox/Correction/smartbox_projectdata_analysis/table_4.csv>) est vide : il n'y a **aucun doublon exact réel** sur la combinaison :

- `EntityName_EN`
- `Column_EN`
- `PsseSchemaName`
- `PsseObjectName`
- `PsseColumnName`
- `MatchType`

En revanche, [table_3.csv](</c:/Users/franbreton/Downloads/SPR SmartBox/Correction/smartbox_projectdata_analysis/table_3.csv>) montre beaucoup de colonnes avec un fan-out élevé de candidats, par exemple :

- `ProjectId` jusqu'à `53` candidats selon l'entité
- `TaskId` jusqu'à `21`
- `ResourceId` jusqu'à `14`
- `TimesheetClasses.LCID` jusqu'à `32`
- `TimesheetClasses.Description` jusqu'à `18`

### Conclusion

Ces lignes ne sont pas des doublons "inutiles" au sens strict. Elles représentent un **ensemble de correspondances candidates** construit depuis l'inventaire PSSE.

Cela signifie :

- **oui**, la multiplication des lignes dans `ODataPsseExactColumnMatch` est en grande partie intentionnelle ;
- **non**, cela ne veut pas dire qu'autant de jointures sont réellement utilisées dans la vue finale ;
- **oui**, cela peut produire de mauvais résultats si la phase de réduction choisit une source peu pertinente ou trop générale.

Autrement dit, le problème n'est pas la présence de candidats en soi, mais la **qualité du ranking et des overrides** qui sélectionnent la source finale.

## Cas particulier : `TimesheetClasses`

Le cas `TimesheetClasses` confirme bien la lecture précédente :

- binding actif : `pjrep.MSP_TimesheetClass_UserView`
- nombre de colonnes sources recensées : `8`
- malgré cela, plusieurs colonnes dans `ODataPsseExactColumnMatch` pointent aussi vers d'autres objets PSSE portant les mêmes noms de colonnes

Conclusion :

- ce n'est pas, à lui seul, une erreur de génération de `ODataPsseExactColumnMatch` ;
- c'est un signal que la table est trop "large" comme source de candidats pour certaines familles de colonnes génériques comme `Description`, `LCID`, `DepartmentName`.

## Hypothèse de cause racine

Le comportement observé suggère deux familles de problèmes :

1. **Colonnes réellement vides dans la source retenue**  
   Cas fréquent sur les colonnes MTMD custom, certains champs de décision/planning, et plusieurs colonnes texte ou dates de confort.

2. **Matching ou binding trop permissif**  
   Cas visible surtout lorsqu'une colonne possède beaucoup de candidats potentiels dans l'inventaire, même si le nombre de vrais doublons exacts reste nul.

## Priorité de correction recommandée

Ordre conseillé pour la suite :

1. `Assignments`
2. `Tasks`
3. `Projects`
4. `Resources`
5. `TimesheetClasses`

Pour chacune :

- comparer la colonne publiée à la source PSSE effectivement retenue ;
- valider si la source est réellement vide ou si une meilleure source existe dans les candidats ;
- resserrer les règles de ranking pour les colonnes génériques ou très ambiguës ;
- décider explicitement quelles colonnes custom MTMD doivent être traitées comme "attendues mais parfois vides" et lesquelles doivent être recâblées.

## Livrables produits

### Dossier global

- [table_0.csv](</c:/Users/franbreton/Downloads/SPR SmartBox/Correction/smartbox_projectdata_analysis/table_0.csv>) : résumé par vue
- [table_1.csv](</c:/Users/franbreton/Downloads/SPR SmartBox/Correction/smartbox_projectdata_analysis/table_1.csv>) : toutes les colonnes entièrement nulles
- [table_2.csv](</c:/Users/franbreton/Downloads/SPR SmartBox/Correction/smartbox_projectdata_analysis/table_2.csv>) : colonnes nulles avec focus sur les statuts mappés
- [table_3.csv](</c:/Users/franbreton/Downloads/SPR SmartBox/Correction/smartbox_projectdata_analysis/table_3.csv>) : fan-out des candidats
- [table_4.csv](</c:/Users/franbreton/Downloads/SPR SmartBox/Correction/smartbox_projectdata_analysis/table_4.csv>) : vrais doublons exacts, vide à ce stade

### Dossier par entité

- [entity_summary.csv](</c:/Users/franbreton/Downloads/SPR SmartBox/Correction/smartbox_projectdata_by_entity/entity_summary.csv>)
- [mapped_all_null_non_empty_all_entities.csv](</c:/Users/franbreton/Downloads/SPR SmartBox/Correction/smartbox_projectdata_by_entity/mapped_all_null_non_empty_all_entities.csv>)
- [mapped_all_null_en_with_fanout.csv](</c:/Users/franbreton/Downloads/SPR SmartBox/Correction/smartbox_projectdata_by_entity/mapped_all_null_en_with_fanout.csv>)
- [entities](</c:/Users/franbreton/Downloads/SPR SmartBox/Correction/smartbox_projectdata_by_entity/entities>)

## Conclusion

Le système ne montre pas un problème de "vrais doublons" dans `ODataPsseExactColumnMatch`. Le problème réel est plus subtil :

- trop de colonnes publiées restent vides alors qu'elles sont considérées mappées ;
- le pool de candidats est souvent très large pour des colonnes génériques ;
- la réduction finale vers la bonne source n'est pas toujours assez discriminante pour le contexte métier visé.

La prochaine étape naturelle est une revue entité par entité des colonnes listées comme `MAPPED` mais entièrement `NULL`, en commençant par `Assignments`, `Tasks`, `Projects` et `Resources`.
