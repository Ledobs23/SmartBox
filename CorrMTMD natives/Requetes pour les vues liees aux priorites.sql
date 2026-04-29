/*
REQUETE POUR LA TABLE Prioritizations
*/

SELECT
	PRU.ConsistencyRatio	AS TauxCohérence,
	PRU.CreatedByResourceUID	AS IdRessourceCréation,
	PRU.CreatedByResourceName	AS NomRessourceCréation,
	PRU.DepartmentUID	AS IdService,
	PRU.DepartmentName	AS NomService,
	PRU.ModifiedByResourceUID	AS IdRessourceModification,
	PRU.ModifiedByResourceName	AS NomRessourceModification,
	PRU.CreatedDate	AS DateCréationDéfinitionPriorités,
	PRU.PrioritizationDescription	AS DescriptionDéfinitionPriorités,
	PRU.PrioritizationUID	AS IdDéfinitionPriorités,
	PRU.PrioritizationIsManual	AS DéfinitionPrioritésEstManuelle,
	PRU.ModifiedDate	AS DateModificationDéfinitionPriorités,
	PRU.PrioritizationName	AS NomDéfinitionPriorités
FROM
	pjrep.MSP_EpmPrioritization_UserView PRU


/*
REQUETE POUR LA TABLE PrioritizationDrivers
*/

SELECT
	PDU.BusinessDriverUID	AS IdAxeStratégiqueEntreprise,
	PDU.BusinessDriverName	AS NomAxeStratégiqueEntreprise,
	PDU.BusinessDriverPriority	AS PrioritéAxeStratégiqueEntreprise,
	PDU.PrioritizationUID	AS IdDéfinitionPriorités,
	PDU.PrioritizationName	AS NomDéfinitionPriorités
FROM
	pjrep.MSP_EpmPrioritizationDriver_UserView PDU


/*
REQUETE POUR LA TABLE PrioritizationDriverRelations
*/

SELECT
	PDRU.BusinessDriver1UID	AS IdAxeStratégiqueEntreprise1,
	PDRU.BusinessDriver1Name	AS NomAxeStratégiqueEntreprise1,
	PDRU.BusinessDriver2UID	AS IdAxeStratégiqueEntreprise2,
	PDRU.BusinessDriver2Name	AS NomAxeStratégiqueEntreprise2,
	PDRU.PrioritizationUID	AS IdDéfinitionPriorités,
	PDRU.PrioritizationName	AS NomDéfinitionPriorités,
	PDRU.RelationValue	AS ValeurRelation
FROM
	pjrep.MSP_EpmPrioritizationDriverRelation_UserView PDRU
