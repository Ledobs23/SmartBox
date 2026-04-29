/*
REQUETE POUR LA TABLE BusinessDrivers
*/

SELECT
	BDU.CreatedDate	AS DateCréationAxeStratégiqueEntreprise,
	BDU.BusinessDriverDescription	AS DescriptionAxeStratégiqueEntreprise,
	BDU.BusinessDriverUID	AS IdAxeStratégiqueEntreprise,
	BDU.BusinessDriverIsActive	AS AxeStratégiqueEntrepriseEstActif,
	BDU.ModifiedDate	AS DateModificationAxeStratégiqueEntreprise,
	BDU.BusinessDriverName	AS NomAxeStratégiqueEntreprise,
	BDU.CreatedByResourceUID	AS IdRessourceCréation,
	BDU.CreatedByResourceName	AS NomRessourceCréation,
	BDU.ImpactDescriptionExtreme	AS DescriptionImpactExtrême,
	BDU.ImpactDescriptionLow	AS DescriptionImpactFaible,
	BDU.ImpactDescriptionModerate	AS DescriptionImpactModéré,
	BDU.ImpactDescriptionNone	AS DescriptionImpactAucun,
	BDU.ImpactDescriptionStrong	AS DescriptionImpactFort,
	BDU.ModifiedByResourceUID	AS IdRessourceModification,
	BDU.ModifiedByResourceName	AS NomRessourceModification
FROM
	pjrep.MSP_EpmBusinessDriver_UserView BDU



/*
REQUETE POUR LA TABLE BusinessDriverDepartments
*/

SELECT
	BDDU.BusinessDriverUID	AS IdAxeStratégiqueEntreprise,
	BDDU.BusinessDriverName	AS NomAxeStratégiqueEntreprise,
	BDDU.DepartmentUID	AS IdService,
	BDDU.DepartmentName	AS NomService
FROM
	pjrep.MSP_EpmBusinessDriverDepartment_UserView BDDU


/*
REQUETE POUR LA TABLE Deliverables
*/

SELECT
	D.CreateByResource	AS CréerParRessource,
	D.CreatedDate	AS DateCréation,
	D.DeliverableID	AS IdLivrable,
	D.Description	AS Description,
	D.FinishDate	AS FinishDate,
	D.IsFolder	AS EstUnDossier,
	D.ItemRelativeUrlPath	AS CheminURLRelativeÉlément,
	D.ModifiedByResource	AS ModifiéParRessource,
	D.ModifiedDate	AS DateModification,
	D.ProjectUID	AS IdProjet,
	D.StartDate	AS DateDébut,
	D.Title	AS Titre,
	PU.ProjectName	AS NomProjet
FROM
	pjrep.MSP_WssDeliverable D
LEFT JOIN
	pjrep.MSP_EpmProject_UserView PU
ON
	D.ProjectUID = PU.ProjectUID


/*
REQUETE POUR LA TABLE CostScenarioProjects
*/

SELECT
	PCCPU.AbsolutePriority	AS PrioritéAbsolue,
	PCCPU.AnalysisUID	AS IdAnalyse,
	PCCPU.AnalysisName	AS NomAnalyse,
	PCCPU.ForceAliasLookupTableUID	AS IdTableChoixAliasForcé,
	PCCPU.ForceAliasLookupTableName	AS NomTableChoixAliasForcé,
	PCCPU.ForceStatus	AS ÉtatForcé,
	PCCPU.HardConstraintValue	AS ValeurContrainteImpérative,
	PCCPU.Priority	AS Priorité,
	PCCPU.ProjectUID	AS IdProjet,
	PCCPU.ProjectName	AS NomProjet,
	PCCPU.ScenarioUID	AS IdScénario,
	PCCPU.ScenarioName	AS NomScénario,
	PCCPU.Status	AS Statut
FROM
	pjrep.MSP_EpmPortfolioCostConstraintProject_UserView PCCPU


/*
REQUETE POUR LA TABLE CostConstraintScenarios
*/

SELECT
	PCCSU.AnalysisUID	AS IdAnalyse,
	PCCSU.AnalysisName	AS NomAnalyse,
	PCCSU.CreatedByResourceUID	AS IdRessourceCréation,
	PCCSU.CreatedByResourceName	AS NomRessourceCréation,
	PCCSU.CreatedDate	AS DateCréation,
	PCCSU.ModifiedByResourceUID	AS IdRessourceModification,
	PCCSU.ModifiedByResourceName	AS NomRessourceModification,
	PCCSU.ModifiedDate	AS DateModification,
	PCCSU.ScenarioDescription	AS DescriptionScénario,
	PCCSU.ScenarioUID	AS IdScénario,
	PCCSU.ScenarioName	AS NomScénario,
	PCCSU.SelectedProjectsCost	AS CoûtProjetsSélectionnés,
	PCCSU.SelectedProjectsPriority	AS PrioritéProjetSélectionnée,
	PCCSU.UnselectedProjectsCost	AS CoûtProjetsNonSélectionné,
	PCCSU.UnselectedProjectsPriority	AS PrioritéProjetNonSélectionnée,
	PCCSU.UseDependencies	AS UtiliserDépendances
FROM
	pjrep.MSP_EpmPortfolioCostConstraintScenario_UserView PCCSU
