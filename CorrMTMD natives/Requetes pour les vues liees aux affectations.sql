/*
REQUETE POUR LA TABLE AssignmentBaselines
*/

SELECT
	AB.AssignmentBaselineBudgetCost	AS CoûtBudgétaireRéférenceAffectation,
	AB.AssignmentBaselineBudgetMaterialWork	AS TravailMatériauBudgétaireRéférenceAffectation,
	AB.AssignmentBaselineBudgetWork	AS TravailBudgétaireRéférenceAffectation,
	AB.AssignmentBaselineCost	AS CoûtRéférenceAffectation,
	AB.AssignmentBaselineFinishDate	AS DateFinRéférenceAffectation,
	AB.AssignmentBaselineMaterialWork	AS TravailMatériauRéférenceAffectation,
	AB.AssignmentBaselineModifiedDate	AS AssignmentBaselineModifiedDate,
	AB.AssignmentBaselineStartDate	AS DateDébutRéférenceAffectation,
	AB.AssignmentBaselineWork	AS TravailRéférenceAffectation,
	AB.AssignmentUID	AS IdAffectation,
	AB.AssignmentType	AS AffectationType,
	AB.BaselineNumber	AS NuméroPlanningDeRéférence,
	AB.ProjectUID	AS IdProjet,
	AB.TaskUID	AS IdTâche,
	PU.ProjectName	AS NomProjet,
	TU.TaskName	AS NomTâche
FROM
	pjrep.MSP_EpmAssignmentBaseline AB
LEFT JOIN
	pjrep.MSP_EpmProject_UserView PU
ON
	AB.ProjectUID = PU.ProjectUID
LEFT JOIN
	pjrep.MSP_EpmTask_UserView TU
ON
	AB.TaskUID = TU.TaskUID



/*
REQUETE POUR LA TABLE AssignmentBaselineTimephasedDataSet
*/


SELECT
	ABBD.AssignmentBaselineBudgetCost	AS CoûtBudgétaireRéférenceAffectation,
	ABBD.AssignmentBaselineBudgetMaterialWork	AS TravailMatériauBudgétaireRéférenceAffectation,
	ABBD.AssignmentBaselineBudgetWork	AS TravailBudgétaireRéférenceAffectation,
	ABBD.AssignmentBaselineCost	AS CoûtRéférenceAffectation,
	ABBD.AssignmentBaselineMaterialWork	AS TravailMatériauRéférenceAffectation,
	ABBD.AssignmentBaselineModifiedDate	AS AssignmentBaselineModifiedDate,
	ABBD.AssignmentBaselineWork	AS TravailRéférenceAffectation,
	ABBD.AssignmentUID	AS IdAffectation,
	ABBD.BaselineNumber	AS NuméroPlanningDeRéférence,
	ABBD.FiscalPeriodUID	AS IDPériodeFiscale,
	ABBD.ProjectUID	AS IdProjet,
	ABBD.TaskUID	AS IdTâche,
	ABBD.TimeByDay	AS HeureParJour,
	AU.ResourceUID	AS IdRessource,
	PU.ProjectName	AS NomProjet,
	TU.TaskName	AS NomTâche
FROM
	pjrep.MSP_EpmAssignmentBaselineByDay ABBD
LEFT JOIN
	pjrep.MSP_EpmAssignment_UserView AU
ON
	ABBD.AssignmentUID = AU.AssignmentUID
LEFT JOIN
	pjrep.MSP_EpmProject_UserView PU
ON
	ABBD.ProjectUID = PU.ProjectUID
LEFT JOIN
	pjrep.MSP_EpmTask_UserView TU
ON
	ABBD.TaskUID = TU.TaskUID


/*
REQUETE POUR LA TABLE AssignmentTimephasedDataSet
*/


SELECT
	ABD.FiscalPeriodUID	AS IDPériodeFiscale,
	ABDU.AssignmentActualCost	AS CoûtRéelAffectation,
	ABDU.AssignmentActualOvertimeCost	AS CoûtHeuresSupplémentairesRéellesAffectation,
	ABDU.AssignmentActualOvertimeWork	AS HeuresSupplémentairesRéellesAffectation,
	ABDU.AssignmentActualRegularCost	AS CoûtNormalRéelAffectation,
	ABDU.AssignmentActualRegularWork	AS TravailNormalRéelAffectation,
	ABDU.AssignmentActualWork	AS AffectationTravailRéel,
	ABDU.AssignmentBudgetCost	AS CoûtBudgétaireAffectation,
	ABDU.AssignmentBudgetMaterialWork	AS TravailMatériauBudgétaireAffectation,
	ABDU.AssignmentBudgetWork	AS TravailBudgétaireAffectation,
	ABDU.AssignmentCombinedWork	AS TravailCombinéAffectation,
	ABDU.AssignmentCost	AS AffectationCoût,
	ABDU.AssignmentMaterialActualWork	AS TravailRéelMatériauAffectation,
	ABDU.AssignmentMaterialWork	AS TravailMatériauAffectation,
	ABDU.AssignmentOvertimeCost	AS CoûtHeuresSupplémentairesAffectation,
	ABDU.AssignmentOvertimeWork	AS HeuresSupplémentairesAffectation,
	ABDU.AssignmentRegularCost	AS CoûtNormalAffectation,
	ABDU.AssignmentRegularWork	AS TravailNormalAffectation,
	ABDU.AssignmentRemainingCost	AS AffectationCoûtRestant,
	ABDU.AssignmentRemainingOvertimeCost	AS CoûtHeuresSupplémentairesRestantes,
	ABDU.AssignmentRemainingOvertimeWork	AS HeuresSupplémentairesRestantesAffectation,
	ABDU.AssignmentRemainingRegularCost	AS CoûtNormalRestantAffectation,
	ABDU.AssignmentRemainingRegularWork	AS TravailNormalRestantAffectation,
	ABDU.AssignmentRemainingWork	AS AffectationTravailRestant,
	ABDU.AssignmentResourcePlanWork	AS AffectationRessourcePlanTravail,
	ABDU.AssignmentUID	AS IdAffectation,
	ABDU.AssignmentWork	AS AffectationTravail,
	ABDU.ProjectUID	AS IdProjet,
	ABDU.TaskIsActive	AS TâcheEstActive,
	ABDU.TaskUID	AS IdTâche,
	ABDU.TimeByDay	AS HeureParJour,
	AU.AssignmentModifiedDate	AS AffectationDateModification,
	AU.ResourceUID	AS IdRessource,
	PU.ProjectName	AS NomProjet,
	TU.TaskName	AS NomTâche
FROM
	pjrep.MSP_EpmAssignmentByDay_UserView ABDU
LEFT JOIN
	pjrep.MSP_EpmAssignmentByDay ABD
ON
	ABDU.AssignmentUID = ABD.AssignmentUID
LEFT JOIN
	pjrep.MSP_EpmProject_UserView PU
ON
	ABDU.ProjectUID = PU.ProjectUID
LEFT JOIN
	pjrep.MSP_EpmTask_UserView TU
ON
	ABDU.TaskUID = TU.TaskUID
LEFT JOIN
	pjrep.MSP_EpmAssignment_UserView AU
ON
	ABDU.AssignmentUID = AU.AssignmentUID