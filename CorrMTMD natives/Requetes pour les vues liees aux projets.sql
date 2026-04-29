/*
REQUETE POUR LA TABLE ProjectBaselines
*/

SELECT
PU.[ProjectName]	AS NomProjet,
PB.[BaselineNumber]	AS NuméroPlanningDeRéférence,
PB.[ProjectBaselineBudgetCost]	AS CoûtBudgétaireRéférenceProjet,
PB.[ProjectBaselineBudgetWork]	AS TravailBudgétaireRéférenceProjet,
PB.[ProjectBaselineCost]	AS CoûtRéférenceProjet,
PB.[ProjectBaselineDeliverableFinishDate]	AS DateFinLivrableRéférenceProjet,
PB.[ProjectBaselineDeliverableStartDate]	AS DateDébutLivrableRéférenceProjet,
PB.[ProjectBaselineDuration]	AS DuréeRéférenceProjet,
PB.[ProjectBaselineDurationString]	AS ChaîneDuréeRéférenceProjet,
PB.[ProjectBaselineFinishDate]	AS DateFinRéférenceProjet,
PB.[ProjectBaselineFinishDateString]	AS ChaîneDateFinRéférenceProjet,
PB.[ProjectBaselineFixedCost]	AS CoûtFixeRéférenceProjet,
PB.[ProjectBaselineModifiedDate]	AS ProjectBaselineModifiedDate,
PB.[ProjectBaselineStartDate]	AS DateDébutRéférenceProjet,
PB.[ProjectBaselineStartDateString]	AS ChaîneDateDébutRéférenceProjet,
PB.[ProjectBaselineWork]	AS TravailRéférenceProjet,
PB.[ProjectUID]	AS IdProjet,
PB.[TaskUID]	AS IdTâche
FROM
pjrep.MSP_ProjectBaseline_ODATAView PB
LEFT JOIN
pjrep.MSP_EpmProject_UserView PU
ON
PB.[ProjectUID] = PU.[ProjectUID]


/*
REQUETE POUR LA TABLE ProjectWorkflowStageDataSet
*/

SELECT
	PWSI.LastModifiedDate	AS DateDernièreModification,
	PWSI.LCID	AS LCID,
	PWSI.PhaseDescription	AS DescriptionPhase,
	PWSI.PhaseName	AS NomPhase,
	PWSI.ProjectId	AS IdProjet,
	PWSI.ProjectName	AS NomProjet,
	PWSI.StageCompletionDate	AS DateFinÉtape,
	PWSI.StageDescription	AS DescriptionÉtape,
	PWSI.StageEntryDate	AS DateEntréeÉtape,
	PWSI.StageId	AS IdÉtape,
	PWSI.StageInformation	AS InformationsÉtape,
	PWSI.StageLastSubmitted	AS DateDernierEnvoiÉtape,
	PWSI.StageName	AS NomÉtape,
	PWSI.StageOrder	AS OrdreÉtape,
	PWSI.StageStateDescription	AS DescriptionÉtatÉtape,
	PWSI.StageStatus	AS ÉtatÉtape
FROM
	pjrep.MSP_EpmProjectWorkflowStatusInformation_UserView PWSI
