/*
REQUETE POUR LA TABLE ResourceConstraintScenarios
*/

SELECT
	PRCSU.AllocationThreshold	AS SeuilRépartition,
	PRCSU.AnalysisUID	AS IdAnalyse,
	PRCSU.AnalysisName	AS NomAnalyse,
	PRCSU.ConstraintType	AS TypeContrainte,
	PRCSU.ConstraintValue	AS ValeurContrainte,
	PRCSU.CostConstraintScenarioUID	AS IdScénarioContrainteCoût,
	PRCSU.CostConstraintScenarioName	AS NomScénarioContrainteCoût,
	PRCSU.CreatedByResourceUID	AS IdRessourceCréation,
	PRCSU.CreatedByResourceName	AS NomRessourceCréation,
	PRCSU.CreatedDate	AS DateCréation,
	PRCSU.EnforceProjectDependencies	AS AppliquerDépendancesProjet,
	PRCSU.EnforceSchedulingConstraints	AS AppliquerContraintesPlanification,
	PRCSU.HiringType	AS TypeEmbauche,
	PRCSU.ModifiedByResourceUID	AS IdRessourceModification,
	PRCSU.ModifiedByResourceName	AS NomRessourceModification,
	PRCSU.ModifiedDate	AS DateModification,
	PRCSU.RateTable	AS TableTaux,
	PRCSU.ScenarioDescription	AS DescriptionScénario,
	PRCSU.ScenarioUID	AS IdScénario,
	PRCSU.ScenarioName	AS NomScénario
FROM
	pjrep.MSP_EpmPortfolioResourceConstraintScenario_UserView PRCSU


/*
REQUETE POUR LA TABLE ResourceScenarioProjects
*/

SELECT
	PRCPU.AbsolutePriority	AS PrioritéAbsolue,
	PRCPU.AnalysisUID	AS IdAnalyse,
	PRCPU.AnalysisName	AS NomAnalyse,
	PRCPU.CostConstraintScenarioUID	AS IdScénarioContrainteCoût,
	PRCPU.CostConstraintScenarioName	AS NomScénarioContrainteCoût,
	PRCPU.ForceAliasLookupTableUID	AS IdTableChoixAliasForcé,
	PRCPU.ForceAliasLookupTableName	AS NomTableChoixAliasForcé,
	PRCPU.ForceStatus	AS ÉtatForcé,
	PRCPU.HardConstraintValue	AS ValeurContrainteImpérative,
	PRCPU.NewStartDate	AS NouvelleDateDébut,
	PRCPU.Priority	AS Priorité,
	PRCPU.ProjectUID	AS IdProjet,
	PRCPU.ProjectName	AS NomProjet,
	PRCPU.ResourceCost	AS CoûtRessource,
	PRCPU.ResourceWork	AS TravailRessource,
	PRCPU.ScenarioUID	AS IdScénario,
	PRCPU.ScenarioName	AS NomScénario,
	PRCPU.Status	AS Statut
FROM
	pjrep.MSP_EpmPortfolioResourceConstraintProject_UserView PRCPU


/*
REQUETE POUR LA TABLE ResourceTimephasedDataSet 
*/


SELECT
	RBDU.BaseCapacity	AS CapacitéBase,
	RBDU.Capacity	AS Capacité,
	RBDU.ResourceUID	AS IdRessource,
	RBDU.TimeByDay	AS HeureParJour,
	TBD.FiscalPeriodUID	AS IDPériodeFiscale,
	RU.ResourceModifiedDate	AS DateModificationRessource,
	RU.ResourceName	AS NomRessource
FROM
	pjrep.MSP_EpmResourceByDay_UserView RBDU
LEFT JOIN
	pjrep.MSP_TimeByDay TBD
ON
	RBDU.TimeByDay = TBD.TimeByDay
LEFT JOIN
	pjrep.MSP_EpmResource_UserView RU
ON
	RBDU.ResourceUID = RU.ResourceUID


/*
REQUETE POUR LA TABLE ResourceDemandTimephasedDataSet
*/

SELECT
	RDBDU.ProjectUID	AS IdProjet,
	RDBDU.ProjectName	AS NomProjet,
	RDBDU.ResourceDemand	AS ResourceDemand,
	RDBDU.ResourceDemandModifiedDate	AS ResourceDemandModifiedDate,
	RDBDU.ResourceUID	AS IdRessource,
	RDBDU.TimeByDay	AS HeureParJour,
	TBD.FiscalPeriodUID	AS IDPériodeFiscale,
	PU.ResourcePlanUtilizationDate	AS DatePlanUtilisationRessource,
	PU.ResourcePlanUtilizationType	AS TypePlanUtilisationRessource,
	RU.ResourceName	AS NomRessource
FROM
	pjrep.MSP_EpmResourceDemandByDay_UserView RDBDU
LEFT JOIN
	pjrep.MSP_TimeByDay TBD
ON
	RDBDU.TimeByDay = TBD.TimeByDay
LEFT JOIN
	pjrep.MSP_EpmProject_UserView PU
ON
	RDBDU.ProjectUID = PU.ProjectUID
LEFT JOIN
	pjrep.MSP_EpmResource_UserView RU
ON
	RDBDU.ResourceUID = RU.ResourceUID
