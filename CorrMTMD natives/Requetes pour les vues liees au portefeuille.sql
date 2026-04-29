/*
REQUETE POUR LA TABLE PortfolioAnalyses
*/

SELECT
	PAU.AlternateProjectEndDateCustomFieldUID	AS IdChampPersonnaliséAutreDateFinProjet,
	PAU.AlternateProjectEndDateCustomFieldName	AS NomChampPersonnaliséAutreDateFinProjet,
	PAU.AlternateProjectStartDateCustomFieldUID	AS IdChampPersonnaliséAutreDateDébutProjet,
	PAU.AlternateProjectStartDateCustomFieldName	AS NomChampPersonnaliséAutreDateDébutProjet,
	PAU.AnalysisDescription	AS DescriptionAnalyse,
	PAU.AnalysisUID	AS IdAnalyse,
	PAU.AnalysisName	AS NomAnalyse,
	PAU.AnalysisType	AS TypeAnalyse,
	PAU.BookingType	AS TypeRéservation,
	PAU.CreatedByResourceUID	AS IdRessourceCréation,
	PAU.CreatedByResourceName	AS NomRessourceCréation,
	PAU.CreatedDate	AS DateCréation,
	PAU.DepartmentUID	AS IdService,
	PAU.DepartmentName	AS NomService,
	PAU.FilterResourcesByDepartment	AS FiltrerRessourcesParService,
	PAU.FilterResourcesByRBS	AS FiltrerRessourcesParRBS,
	PAU.FilterResourcesByRBSValueUID	AS IdValeurFiltrerRessourcesParRBS,
	PAU.FilterResourcesByRBSValueText	AS TexteValeurFiltrerRessourcesParRBS,
	PAU.ForcedInAliasLookupTableUID	AS IdTableChoixAliasInclusDeForce,
	PAU.ForcedInAliasLookupTableName	AS NomTableChoixAliasInclusForce,
	PAU.ForcedOutAliasLookupTableUID	AS IdTableChoixAliasExcluDeForce,
	PAU.ForcedOutAliasLookupTableName	AS NomTableChoixAliasExcluDeForce,
	PAU.HardConstraintCustomFieldUID	AS IdChampPersonnaliséContrainteImpérative,
	PAU.HardConstraintCustomFieldName	AS NomChampPersonnaliséContrainteImpérative,
	PAU.ModifiedByResourceUID	AS IdRessourceModification,
	PAU.ModifiedByResourceName	AS NomRessourceModification,
	PAU.ModifiedDate	AS DateModification,
	PAU.PlanningHorizonEndDate	AS DateFinHorizonPlanification,
	PAU.PlanningHorizonStartDate	AS DateDébutHorizonPlanification,
	PAU.PrioritizationUID	AS IdDéfinitionPriorités,
	PAU.PrioritizationName	AS NomDéfinitionPriorités,
	PAU.PrioritizationType	AS TypeDéfinitionPriorités,
	PAU.RoleCustomFieldUID	AS IdChampPersonnaliséRôle,
	PAU.RoleCustomFieldName	AS NomChampPersonnaliséRôle,
	PAU.TimeScale	AS ÉchelleTemps,
	PAU.UseAlternateProjectDatesForResourcePlans	AS UtiliserDatesProjetAlternativesPourPlansRessources
FROM
	pjrep.MSP_EpmPortfolioAnalysis_UserView PAU


/*
REQUETE POUR LA TABLE PortfolioAnalysisProjects
*/

SELECT
	PAPU.AbsolutePriority	AS PrioritéAbsolue,
	PAPU.AnalysisUID	AS IdAnalyse,
	PAPU.AnalysisName	AS NomAnalyse,
	PAPU.Duration	AS Durée,
	PAPU.FinishNoLaterThan	AS FinAuPlusTardLe,
	PAPU.Locked	AS Verrouillé,
	PAPU.OriginalEndDate	AS DateFinOrigine,
	PAPU.OriginalStartDate	AS DateDébutOrigine,
	PAPU.Priority	AS Priorité,
	PAPU.ProjectUID	AS IdProjet,
	PAPU.ProjectName	AS NomProjet,
	PAPU.StartDate	AS DateDébut,
	PAPU.StartNoEarlierThan	AS DébutAuPlusTôtLe
FROM
	pjrep.MSP_EpmPortfolioAnalysisProject_UserView PAPU