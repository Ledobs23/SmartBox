/*
REQUETE POUR LA TABLE TIMESHEETCLASSES
*/

SELECT
	TSCU.ClassUID	AS IdClasseFeuilleDeTemps,
	TSCU.DepartmentUID	AS IdService,
	TSCU.DepartmentName	AS NomService,
	TSCU.Description	AS Description,
	TSCU.LCID	AS LCID,
	TSCU.ClassName	AS NomClasseFeuilleDeTemps,
	TSCU.Type	AS TypeClasseFeuilleDeTemps
FROM
	pjrep.MSP_TimesheetClass_UserView TSCU


/*
REQUETE POUR LA TABLE TIMESHEETPERIODS
*/

SELECT
	TSP.EndDate	AS DateFin,
	TSP.LCID	AS LCID,
	TSP.PeriodName	AS NomPériode,
	TSP.PeriodStatusID	AS IdÉtatPériode,
	TSP.PeriodUID	AS IdPériode,
	TSP.StartDate	AS DateDébut,
	TSPS.Description	AS Description
FROM
	pjrep.MSP_TimesheetPeriod TSP
LEFT JOIN
	pjrep.MSP_TimesheetPeriodStatus TSPS
ON
	TSP.PeriodStatusID = TSPS.PeriodStatusID


/*
REQUETE POUR LA TABLE TIMESHEETLINES
*/

SELECT
	RU1.ResourceName	AS NomRessourceApprobateurFeuilleDeTemps,
	RU2.ResourceName	AS PropriétaireFeuilleDeTemps,
	TS.OwnerResourceNameUID	AS IdPropriétaireFeuilleDeTemps,
	TSCU.Description	AS DescriptionClasseFeuilleDeTemps,
	TSL.ApproverResourceNameUID	AS IdRessourceApprobateurFeuilleDeTemps,
	TSL.AssignmentUID	AS IdAffectation,
	TSL.LastSavedWork	AS DernierTravailEnregistré,
	TSL.TaskHierarchy	AS HiérarchieTâches,
	TSL.Comment	AS CommentaireLigneFeuilleDeTemps,
	TSLU.ActualOvertimeWorkBillable	AS TravailHeuresSupplémentairesRéelFacturable,
	TSLU.ActualOvertimeWorkNonBillable	AS TravailHeuresSupplémentairesRéelNonFacturable,
	TSLU.ActualWorkBillable	AS TravailRéelFacturable,
	TSLU.ActualWorkNonBillable	AS TravailRéelNonFacturable,
	TSLU.CreatedDate	AS DateCréation,
	TSLU.ModifiedDate	AS DateModification,
	TSLU.PeriodEndDate	AS DateFinPériode,
	TSLU.PeriodStartDate	AS DateDébutPériode,
	TSLU.PlannedWork	AS TravailPrévu,
	TSLU.ProjectUID	AS IdProjet,
	TSLU.ProjectName	AS NomProjet,
	TSLU.TaskUID	AS IdTâche,
	TSLU.TaskName	AS NomTâche,
	TSLU.TimesheetLineClassUID	AS IdClasseFeuilleDeTemps,
	TSLU.TimesheetLineClass	AS NomClasseFeuilleDeTemps,
	TSLU.TimesheetLineClassType	AS TypeClasseFeuilleDeTemps,
	TSLU.TimesheetUID	AS IdFeuilleDeTemps,
	TSLU.TimesheetLineUID	AS IdLigneFeuilleDeTemps,
	TSLU.TimesheetLineStatus	AS ÉtatLigneFeuilleDeTemps,
	TSLU.TimesheetLineStatusID	AS IdÉtatLigneFeuilleDeTemps,
	TSLU.TimesheetName	AS NomFeuilleTemps,
	TSLU.PeriodUID	AS IdPériodeFeuilleDeTemps,
	TSLU.PeriodName	AS NomPériodeFeuilleDeTemps,
	TSLU.PeriodStatus	AS ÉtatPériodeFeuilleDeTemps,
	TSLU.PeriodStatusID	AS IdÉtatPériodeFeuilleDeTemps,
	TSLU.TimesheetStatus	AS ÉtatFeuilleDeTemps,
	TSLU.TimesheetStatusID	AS IdÉtatFeuilleDeTemps,
	TSLS.LCID	AS LCID
FROM
	pjrep.MSP_TimesheetLine_UserView TSLU
LEFT JOIN
	pjrep.MSP_TimesheetLine TSL
ON
	TSLU.TimesheetLineUID = TSL.TimesheetLineUID
LEFT JOIN
	pjrep.MSP_TimesheetLineStatus TSLS
ON
	TSLU.TimesheetLineStatusID = TSLS.TimesheetLineStatusID
LEFT JOIN
	pjrep.MSP_Timesheet TS
ON
	TSLU.TimesheetUID = TS.TimesheetUID
LEFT JOIN
	pjrep.MSP_TimesheetClass_UserView TSCU
ON
	TSLU.TimesheetLineClassUID = TSCU.ClassUID
LEFT JOIN
	pjrep.MSP_EpmResource_UserView RU1
ON
	TSL.ApproverResourceNameUID = RU1.ResourceUID
LEFT JOIN
	pjrep.MSP_EpmResource_UserView RU2
ON
	TS.OwnerResourceNameUID = RU2.ResourceUID


/*
REQUETE POUR LA TABLE FISCALPERIODS
*/

SELECT
	FP.FiscalPeriodUID	AS IDPériodeFiscale,
	FP.FiscalPeriodName	AS NomPériodeFiscale,
	FP.FiscalPeriodStart	AS DébutPériodeFiscale,
	FP.FiscalPeriodFinish	AS FinPériodeFiscale,
	FP.FiscalPeriodQuarter	AS PériodeFiscaleTrimestre,
	FP.FiscalPeriodYear	AS AnnéePériodeFiscale,
	FP.CreatedDate	AS DateCréation,
	FP.ModifiedDate	AS DateModificationPériodeFiscale
FROM
	pjrep.MSP_FiscalPeriods_ODATAView FP


/*
REQUETE POUR LA TABLE TimesheetLineActualDataSet
*/


--IL MANQUE LA COLONNE RESSOURCE QUI EST DIFFERENTE DE LA COLONNE NomRessourceDernièreModification ET QUE JE NE RETROUVE PAS


SELECT
	TSA.ActualOvertimeWorkBillable	AS TravailHeuresSupplémentairesRéelFacturable,
	TSA.ActualOvertimeWorkNonBillable	AS TravailHeuresSupplémentairesRéelNonFacturable,
	TSA.ActualWorkBillable	AS TravailRéelFacturable,
	TSA.ActualWorkNonBillable	AS TravailRéelNonFacturable,
	TSA.AdjustmentIndex	AS IndexAjustement,
	TSA.Comment	AS Commentaire,
	TSA.CreatedDate	AS DateCréation,
	TSA.PlannedWork	AS TravailPrévu,
	TSA.TimeByDay	AS HeureParJour,
	TSA.TimeByDay_DayOfMonth	AS HeureParJour_JourDuMois,
	TSA.TimeByDay_DayOfWeek	AS HeureParJour_JourDeLaSemaine,
	TSA.TimesheetLineUID	AS IdLigneFeuilleDeTemps,
	TSA.TimesheetLineModifiedDate	AS TimesheetLineModifiedDate,
	RU.ResourceName	AS NomRessourceDernièreModification
FROM
	pjrep.MSP_TimesheetActual TSA
LEFT JOIN
	pjrep.MSP_EpmResource_UserView RU
ON
	TSA.LastChangedResourceNameUID = RU.ResourceUID


