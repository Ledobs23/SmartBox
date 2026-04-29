/*
REQUETE POUR LA TABLE Risks
*/

SELECT
	R.AssignedToResource	AS AssignéÀRessource,
	R.Category	AS Catégorie,
	R.ContingencyPlan	AS PlanUrgence,
	R.Cost	AS Coût,
	R.CostExposure	AS ExpositionCoût,
	R.CreateByResource	AS CréerParRessource,
	R.CreatedDate	AS DateCréation,
	R.Description	AS Description,
	R.DueDate	AS Échéance,
	R.Exposure	AS  Exposition,
	R.Impact	AS ÀPercussion,
	R.IsFolder	AS EstUnDossier,
	R.ItemRelativeUrlPath	AS CheminURLRelativeÉlément,
	R.MitigationPlan	AS PlanAtténuation,
	R.ModifiedByResource	AS ModifiéParRessource,
	R.ModifiedDate	AS DateModification,
	R.NumberOfAttachments	AS NombreDePiècesjointes,
	R.Owner	AS Propriétaire,
	R.Probability	AS Probabilité,
	R.ProjectUID	AS IdProjet,
	R.RiskID	AS IdRisque,
	R.Status	AS Statut,
	R.Title	AS Titre,
	R.TriggerDescription	AS DescriptionDéclencheur,
	R.TriggerTask	AS TâcheDéclencheur,
	PU.ProjectName	AS NomProjet
FROM
	pjrep.MSP_WssRisk R
LEFT JOIN
	pjrep.MSP_EpmProject_UserView PU
ON
	R.ProjectUID = PU.ProjectUID


/*
REQUETE POUR LA TABLE RiskTaskAssociations
*/

SELECT
	RTAU.ProjectId	AS IdProjet,
	RTAU.ProjectName	AS NomProjet,
	RTAU.RelatedProjectId	AS IDProjetApparenté,
	RTAU.RelatedProjectName	AS NomProjetApparenté,
	RTAU.RelationshipType	AS TypeRelation,
	RTAU.RiskId	AS IdRisque,
	RTAU.TaskId	AS IdTâche,
	RTAU.TaskName	AS NomTâche,
	RTAU.Title	AS Titre
FROM
	pjrep.MSP_WssRiskTaskAssociation_UserView RTAU

/*
REQUETE POUR LA TABLE Issues
*/

SELECT
	I.AssignedToResource	AS AssignéÀRessource,
	I.Category	AS Catégorie,
	I.CreateByResource	AS CréerParRessource,
	I.CreatedDate	AS DateCréation,
	I.Discussion	AS Discussion,
	I.DueDate	AS Échéance,
	I.IsFolder	AS EstUnDossier,
	I.IssueID	AS IdProblème,
	I.ItemRelativeUrlPath	AS CheminURLRelativeÉlément,
	I.ModifiedByResource	AS ModifiéParRessource,
	I.ModifiedDate	AS DateModification,
	I.NumberOfAttachments	AS NombreDePiècesjointes,
	I.Owner	AS Propriétaire,
	I.Priority	AS Priorité,
	I.ProjectUID	AS IdProjet,
	I.Resolution	AS Résolution,
	I.Status	AS Statut,
	I.Title	AS Titre,
	PU.ProjectName	AS NomProjet
FROM
	pjrep.MSP_WssIssue I
LEFT JOIN
	pjrep.MSP_EpmProject_UserView PU
ON
	I.ProjectUID = PU.ProjectUID


/*
REQUETE POUR LA TABLE IssueTaskAssociations
*/

SELECT
	ITAU.IssueId	AS IdProblème,
	ITAU.ProjectId	AS IdProjet,
	ITAU.ProjectName	AS NomProjet,
	ITAU.RelatedProjectId	AS IDProjetApparenté,
	ITAU.RelatedProjectName	AS NomProjetApparenté,
	ITAU.RelationshipType	AS TypeRelation,
	ITAU.TaskId	AS IdTâche,
	ITAU.TaskName	AS NomTâche,
	ITAU.Title	Titre
FROM
	pjrep.MSP_WssIssueTaskAssociation_UserView ITAU

