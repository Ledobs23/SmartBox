/*
REQUETE POUR LA TABLE TASKBASELINES
*/

SELECT
	PU.ProjectName	AS NomProjet,
	TU.TaskName	AS NomTâche,
	TB.BaselineNumber	AS NuméroPlanningDeRéférence,
	TB.ProjectUID	AS IdProjet,
	TB.TaskBaselineBudgetCost	AS CoûtBudgétaireRéférenceTâche,
	TB.TaskBaselineBudgetWork	AS TravailBudgétaireRéférenceTâche,
	TB.TaskBaselineCost	AS CoûtRéférenceTâche,
	TB.TaskBaselineDeliverableFinishDate	AS DateFinLivrableRéférenceTâche,
	TB.TaskBaselineDeliverableStartDate	AS DateDébutLivrableRéférenceTâche,
	TB.TaskBaselineDuration	AS DuréeRéférenceTâche,
	TB.TaskBaselineDurationString	AS ChaîneDuréeRéférenceTâche,
	TB.TaskBaselineFinishDate	AS DateFinRéférenceTâche,
	TB.TaskBaselineFinishDateString	AS ChaîneDateFinRéférenceTâche,
	TB.TaskBaselineFixedCost	AS CoûtFixeRéférenceTâche,
	TB.TaskBaselineModifiedDate	AS TaskBaselineModifiedDate,
	TB.TaskBaselineStartDate	AS DateDébutRéférenceTâche,
	TB.TaskBaselineStartDateString	AS ChaîneDateDébutRéférenceTâche,
	TB.TaskBaselineWork	AS TravailRéférenceTâche,
	TB.TaskUID	AS IdTâche
FROM
	pjrep.MSP_EpmTaskBaseline TB
LEFT JOIN
	pjrep.MSP_EpmTask_UserView TU
ON
	TB.TaskUID = TU.TaskUID
LEFT JOIN
	pjrep.MSP_EpmProject_UserView PU
ON
	TB.ProjectUID = PU.ProjectUID


/*
REQUETE POUR LA TABLE TaskBaselineTimephasedDataSet
*/


SELECT
	TBBD.BaselineNumber	AS NuméroPlanningDeRéférence,
	TBBD.FiscalPeriodUID	AS IDPériodeFiscale,
	TBBD.ProjectUID	AS IdProjet,
	TBBD.TaskBaselineBudgetCost	AS CoûtBudgétaireRéférenceTâche,
	TBBD.TaskBaselineBudgetWork	AS TravailBudgétaireRéférenceTâche,
	TBBD.TaskBaselineCost	AS CoûtRéférenceTâche,
	TBBD.TaskBaselineFixedCost	AS CoûtFixeRéférenceTâche,
	TBBD.TaskBaselineModifiedDate	AS TaskBaselineModifiedDate,
	TBBD.TaskBaselineWork	AS TravailRéférenceTâche,
	TBBD.TaskUID	AS IdTâche,
	TBBD.TimeByDay	AS HeureParJour,
	PU.ProjectName	AS NomProjet,
	TU.TaskName	AS NomTâche
FROM
	pjrep.MSP_EpmTaskBaselineByDay TBBD
LEFT JOIN
	pjrep.MSP_EpmProject_UserView PU
ON
	TBBD.ProjectUID = PU.ProjectUID
LEFT JOIN
	pjrep.MSP_EpmTask_UserView TU
ON
	TBBD.TaskUID = TU.TaskUID


/*
REQUETE POUR LA TABLE TaskTimephasedDataSet
*/


SELECT
	TBD.FiscalPeriodUID	AS IDPériodeFiscale,
	TBD.ProjectUID	AS IdProjet,
	TBD.TaskActualCost	AS CoûtRéelTâche,
	TBD.TaskActualWork	AS TravailRéelTâche,
	TBD.TaskBudgetCost	AS CoûtBudgétaireTâche,
	TBD.TaskBudgetWork	AS TravailBudgétaireTâche,
	TBD.TaskCost	AS CoûtTâche,
	TBD.TaskIsActive	AS TâcheEstActive,
	TBD.TaskIsProjectSummary	AS TâcheRécapitulativeProjet,
	TBD.TaskModifiedDate	AS DateModificationTâche,
	TBD.TaskOvertimeWork	AS TravailHeuresSupplémentairesTâche,
	TBD.TaskResourcePlanWork	AS TravailPlanRessourcesTâche,
	TBD.TaskUID	AS IdTâche,
	TBD.TaskWork	AS TravailTâche,
	TBD.TimeByDay	AS HeureParJour,
	PU.ProjectName	AS NomProjet,
	TU.TaskName	AS NomTâche
FROM
	pjrep.MSP_EpmTaskByDay TBD
LEFT JOIN
	pjrep.MSP_EpmProject_UserView PU
ON
	TBD.ProjectUID = PU.ProjectUID
LEFT JOIN
	pjrep.MSP_EpmTask_UserView TU
ON
	TBD.TaskUID = TU.TaskUID