/*
REQUETE POUR LA TABLE Engagements
*/

SELECT
	EU.CommittedFinishDate	AS DateFinValidée,
	EU.CommittedMaxUnits	AS NbMaxUnitésValidées,
	EU.CommittedStartDate	AS DateDébutValidée,
	EU.CommittedWork	AS TravailValidé,
	EU.CreatedDate	AS DateCréationEngagement,
	EU.EngagementUID	AS IDEngagement,
	EU.ModifiedDate	AS DateModificationEngagement,
	EU.EngagementName	AS NomEngagement,
	EU.ReviewedDate	AS DateRévisionEngagement,
	EU.Status	AS ÉtatEngagement,
	EU.SubmittedDate	AS DateSoumissionEngagement,
	EU.ModifiedByResourceUID	AS IdRessourceModification,
	EU.ModifiedByResourceName	AS NomRessourceModification,
	EU.ProjectUID	AS IdProjet,
	EU.ProjectName	AS NomProjet,
	EU.ProposedFinishDate	AS DateFinProposée,
	EU.ProposedMaxUnits	AS NbMaxUnitésProposées,
	EU.ProposedStartDate	AS DateDébutProposée,
	EU.ProposedWork	AS TravailProposé,
	EU.ResourceUID	AS IdRessource,
	EU.ResourceName	AS NomRessource,
	EU.ReviewedByResourceUID	AS RévisionParIDRessource,
	EU.ReviewedByResourceName	AS RévisionParNomRessource,
	EU.SubmittedByResourceUID	AS SoumisParIDRessource,
	EU.SubmittedByResourceName	AS SoumisParNomRessource
FROM
	pjrep.MSP_EpmEngagements_UserView EU


/*
REQUETE POUR LA TABLE EngagementsComments
*/

SELECT
	ECU.AuthorUID	AS IDAuteur,
	ECU.AuthorName	AS NomAuteur,
	ECU.CreatedDate	AS DateCréationCommentaire,
	ECU.CommentUID	AS IDCommentaire,
	ECU.CommentMessage	AS MessageCommentaire,
	ECU.EngagementUID	AS IDEngagement,
	ECU.EngagementName	AS NomEngagement
FROM
	pjrep.MSP_EpmEngagementComments_UserView ECU



/*
REQUETE POUR LA TABLE EngagementsTimephasedDataSet
*/

SELECT
	EBDU.CommittedUnits	AS NbMaxUnitésValidées,
	EBDU.CommittedWork	AS TravailValidé,
	EBDU.EngagementModifiedDate	AS DateModificationEngagement,
	EBDU.EngagementName	AS NomEngagement,
	EBDU.EngagementUID	AS IDEngagement,
	EBDU.ProjectUID	AS IdProjet,
	EBDU.ProposedUnits	AS NbMaxUnitésProposées,
	EBDU.ProposedWork	AS TravailProposé,
	EBDU.ResourceUID	AS IdRessource,
	EBDU.EngagementDate	AS HeureParJour,
	PU.ProjectName	AS NomProjet,
	RU.ResourceName	AS NomRessource
FROM
	pjrep.MSP_EpmEngagementByDay_UserView EBDU
LEFT JOIN
	pjrep.MSP_EpmProject_UserView PU
ON
	EBDU.ProjectUID = PU.ProjectUID
LEFT JOIN
	pjrep.MSP_EpmResource_UserView RU
ON
	EBDU.ResourceUID = RU.ResourceUID



