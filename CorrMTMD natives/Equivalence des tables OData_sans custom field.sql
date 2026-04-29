/*
REQUETE POUR LA TABLE PROJETS
*/

SELECT 
EPT.[EnterpriseProjectTypeDescription]	AS DescriptionTypeProjetEntreprise,
EPT.[EnterpriseProjectTypeName]	AS NomTypeProjetEntreprise,
EPT.[IsDefault]	AS TypeProjetEntrepriseParDéfaut,
P.[ProjectIdentifier]	AS IdentificateurProjet,
P.[ProjectLastPublishedDate]	AS ProjectLastPublishedDate,
PU.[EnterpriseProjectTypeUID]	AS IdTypeProjetEntreprise,
PU.[ParentProjectUID]	AS IdProjetParent,
PU.[ProjectActualCost]	AS CoûtRéelProjet,
PU.[ProjectActualDuration]	AS DuréeRéelleProjet,
PU.[ProjectActualFinishDate]	AS DateFinRéelleProjet,
PU.[ProjectActualOvertimeCost]	AS CoûtsHeuresSupplémentairesRéellesProjet,
PU.[ProjectActualOvertimeWork]	AS TravailHeuresSupplémentairesRéellesProjet,
PU.[ProjectActualRegularCost]	AS CoûtNormaRéelProjet,
PU.[ProjectActualRegularWork]	AS TravailNormalRéelProjet,
PU.[ProjectActualStartDate]	AS DateDébutRéelProjet,
PU.[ProjectActualWork]	AS TravailRéelProjet,
PU.[ProjectACWP]	AS CRTEProjet,
PU.[ProjectAuthorName]	AS NomAuteurProjet,
PU.[ProjectBCWP]	AS VAProjet,
PU.[ProjectBCWS]	AS VPProjet,
PU.[ProjectBudgetCost]	AS CoûtBudgétaireProjet,
PU.[ProjectBudgetWork]	AS TravailBudgétaireProjet,
PU.[ProjectCalculationsAreStale]	AS CalculsProjetPérimés,
PU.[ProjectCalendarDuration]	AS DuréeCalendrierProjet,
PU.[ProjectCategoryName]	AS NomCatégorieProjet,
PU.[ProjectCompanyName]	AS NomSociétéProjet,
PU.[ProjectCost]	AS CoûtProjet,
PU.[ProjectCostVariance]	AS VariationCoûtProjet,
PU.[ProjectCPI]	AS IPCProjet,
PU.[ProjectCreatedDate]	AS DateCréationProjet,
PU.[ProjectCurrency]	AS DeviseProjet,
PU.[ProjectCV]	AS VCProjet,
PU.[ProjectCVP]	AS PVCProjet,
PU.[ProjectDescription]	AS DescriptionProjet,
PU.[ProjectDuration]	AS DuréeProjet,
PU.[ProjectDurationVariance]	AS VariationDuréeProjet,
PU.[ProjectEAC]	AS EAAProjet,
PU.[ProjectEarlyFinish]	AS FinAuPlusTôtProjet,
PU.[ProjectEarlyStart]	AS DébutAuPlusTôtProjet,
PU.[ProjectEarnedValueIsStale]	AS AuditCoûtProjetEstPérimé,
PU.[ProjectFinishDate]	AS DateFinProjet,
PU.[ProjectFinishVariance]	AS VariationFinProjet,
PU.[ProjectFixedCost]	AS CoûtFixeProjet,
PU.[ProjectKeywords]	AS MotsClésProjet,
PU.[ProjectLateFinish]	AS FinAuPlusTardProjet,
PU.[ProjectLateStart]	AS DébutAuPlusTardProjet,
PU.[ProjectManagerName]	AS NomResponsableProjet,
PU.[ProjectModifiedDate]	AS DateModificationProjet,
PU.[ProjectName]	AS NomProjet,
PU.[ProjectOvertimeCost]	AS CoûtHeuresSupplémentairesProjet,
PU.[ProjectOvertimeWork]	AS TravailHeuresSupplémentairesProjet,
PU.[ProjectOwnerName]	AS NomPropriétaireProjet,
PU.[ProjectOwnerResourceUID]	AS IdPropriétaireProjet,
PU.[ProjectPercentCompleted]	AS PourcentageTerminéProjet,
PU.[ProjectPercentWorkCompleted]	AS PourcentageTravailTerminéProjet,
PU.[ProjectRegularCost]	AS CoûtNormalProjet,
PU.[ProjectRegularWork]	AS TravailNormalProjet,
PU.[ProjectRemainingCost]	AS CoûtRestantProjet,
PU.[ProjectRemainingDuration]	AS DuréeRestanteProjet,
PU.[ProjectRemainingOvertimeCost]	AS CoûtHeuresSupplémentairesRestantesProjet,
PU.[ProjectRemainingOvertimeWork]	AS TravailHeuresSupplémentairesRestantesProjet,
PU.[ProjectRemainingRegularCost]	AS CoûtNormalRestantProjet,
PU.[ProjectRemainingRegularWork]	AS TravailNormalRestantProjet,
PU.[ProjectRemainingWork]	AS TravailRestantProjet,
PU.[ProjectResourcePlanWork]	AS TravailPlanRessourcesProjet,
PU.[ProjectSPI]	AS SPIProjet,
PU.[ProjectStartDate]	AS DateDébutProjet,
PU.[ProjectStartVariance]	AS VariationDébutProjet,
PU.[ProjectStatusDate]	AS DateÉtatProjet,
PU.[ProjectSubject]	AS ObjetProjet,
PU.[ProjectSV]	AS VSProjet,
PU.[ProjectSVP]	AS SVPProjet,
PU.[ProjectTCPI]	AS TCPIProjet,
PU.[ProjectTitle]	AS TitreProjet,
PU.[ProjectType]	AS TypeProjet,
PU.[ProjectUID]	AS IdProjet,
PU.[ProjectVAC]	AS VAAProjet,
PU.[ProjectWork]	AS TravailProjet,
PU.[ProjectWorkspaceInternalHRef]	AS UrlInterneEspaceDeTravailProjet,
PU.[ProjectWorkVariance]	AS VariationTravailProjet,
PU.[ResourcePlanUtilizationDate]	AS DatePlanUtilisationRessource,
PU.[ResourcePlanUtilizationType]	AS TypePlanUtilisationRessource,
PDU.[OptimizerCommitDate]	AS DateValidationOptimiseur,
PDU.[OptimizerDecisionAliasLookupTableUID]	AS IdTableChoixAliasDécisionOptimiseur,
PDU.[OptimizerDecisionID]	AS IdDécisionOptimiseur,
PDU.[OptimizerDecisionName]	AS NomDécisionOptimiseur,
PDU.[OptimizerSolutionName]	AS NomSolutionOptimiseur,
PDU.[PlannerCommitDate]	AS DateValidationPlanificateur,
PDU.[PlannerDecisionAliasLookupTableUID]	AS IdTableChoixAliasDécisionPlanificateur,
PDU.[PlannerDecisionID]	AS IdDécisionPlanificateur,
PDU.[PlannerDecisionName]	AS NomDécisionPlanificateur,
PDU.[PlannerEndDate]	AS DateFinPlanificateur,
PDU.[PlannerSolutionName]	AS NomSolutionPlanificateur,
PDU.[PlannerStartDate]	AS DateDébutPlanificateur,
RU.[ResourceName]	AS NomPropriétaireFluxDeTravail,
WIU.[WorkflowCreated]	AS DateCréationFluxDeTravail,
WIU.[WorkflowError]	AS ErreurFluxDeTravail,
WIU.[WorkflowErrorResponseCode]	AS CodeRéponseErreurFluxDeTravail,
WIU.[WorkflowInstanceId]	AS IdInstanceFluxDeTravail,
WIU.[WorkflowOwner]	AS IdPropriétaireFluxDeTravail,
PTRI.[TimePhased]	AS ProjetChronologique
FROM
pjrep.MSP_EpmProject_UserView PU
LEFT JOIN
pjrep.MSP_EpmEnterpriseProjectType EPT
ON 
PU.[EnterpriseProjectTypeUID] = EPT.[EnterpriseProjectTypeUID]
LEFT JOIN
pjrep.MSP_EpmProject P
ON
PU.[ProjectUID] = P.[ProjectUID]
LEFT JOIN
pjrep.MSP_EpmProjectDecision_UserView PDU
ON
PU.[ProjectUID] = PDU.[ProjectUID]
LEFT JOIN
pjrep.MSP_ProjectTimephasedRollupInfo_ODATAView PTRI
ON
PU.[ProjectUID] = PTRI.[ProjectId]
LEFT JOIN
pjrep.MSP_EpmWorkflowInstance_UserView WIU
ON
PU.[ProjectUID] = WIU.[ProjectId]
LEFT JOIN
pjrep.MSP_EpmResource_UserView RU
ON
WIU.[WorkflowOwner] = RU.[ResourceUID]


/*
REQUETE POUR LA TABLE TACHES
*/

SELECT
PU.[ProjectName]	AS NomProjet,
TU.[FixedCostAssignmentUID]	AS IdAffectationCoûtFixeTâche,
TU.[ProjectUID]	AS IdProjet,
TU.[TaskActualCost]	AS CoûtRéelTâche,
TU.[TaskActualDuration]	AS DuréeRéelleTâche,
TU.[TaskActualFinishDate]	AS DateFinRéelleTâche,
TU.[TaskActualFixedCost]	AS CoûtFixeRéelTâche,
TU.[TaskActualOvertimeCost]	AS CoûtHeuresSupplémentairesRéelTâche,
TU.[TaskActualOvertimeWork]	AS TravailHeuresSupplémentairesRéellesTâche,
TU.[TaskActualRegularCost]	AS CoûtNormalRéelTâche,
TU.[TaskActualRegularWork]	AS TravailNormalRéelTâche,
TU.[TaskActualStartDate]	AS DateDébutRéelleTâche,
TU.[TaskActualWork]	AS TravailRéelTâche,
TU.[TaskACWP]	AS CRTETâche,
TU.[TaskBCWP]	AS VATâche,
TU.[TaskBCWS]	AS VPTâche,
TU.[TaskBudgetCost]	AS CoûtBudgétaireTâche,
TU.[TaskBudgetWork]	AS TravailBudgétaireTâche,
TU.[TaskClientUniqueId]	AS IDUniqueClientTâche,
TU.[TaskCost]	AS CoûtTâche,
TU.[TaskCostVariance]	AS VariationCoûtTâche,
TU.[TaskCPI]	AS IPCTâche,
TU.[TaskCreatedDate]	AS DateCréationTâche,
TU.[TaskCreatedRevisionCounter]	AS NombreRévisionsCrééesTâche,
TU.[TaskCV]	AS VCTâche,
TU.[TaskCVP]	AS PVCTâche,
TU.[TaskDeadline]	AS ÉchéanceTâche,
TU.[TaskDeliverableFinishDate]	AS DateFinLivrableTâche,
TU.[TaskDeliverableStartDate]	AS DateDébutLivrableTâche,
TU.[TaskDuration]	AS DuréeTâche,
TU.[TaskDurationIsEstimated]	AS DuréeEstiméeTâche,
TU.[TaskDurationString]	AS ChaîneDuréeTâche,
TU.[TaskDurationVariance]	AS VariationDuréeTâche,
TU.[TaskEAC]	AS EAATâche,
TU.[TaskEarlyFinish]	AS FinAuPlusTôtTâche,
TU.[TaskEarlyStart]	AS DébutAuPlusTôtTâche,
TU.[TaskFinishDate]	AS DateFinTâche,
TU.[TaskFinishDateString]	AS ChaîneDateFinTâche,
TU.[TaskFinishVariance]	AS VariationFinTâche,
TU.[TaskFixedCost]	AS CoûtFixeTâche,
TU.[TaskFreeSlack]	AS MargeLibreTâche,
TU.[TaskHyperLinkAddress]	AS AdresseLienHypertexteTâche,
TU.[TaskHyperLinkFriendlyName]	AS LienHypertexteNomConvivialTâche,
TU.[TaskHyperLinkSubAddress]	AS SousAdresseLienHypertexteTâche,
TU.[TaskIgnoresResourceCalendar]	AS TâcheIgnoreCalendrierRessources,
TU.[TaskIndex]	AS IndexTâche,
TU.[TaskIsActive]	AS TâcheEstActive,
TU.[TaskIsCritical]	AS TâcheEstCritique,
TU.[TaskIsEffortDriven]	AS TâchePilotéeParEffort,
TU.[TaskIsExternal]	AS TâcheExterne,
TU.[TaskIsManuallyScheduled]	AS TâchePlanifiéeManuellement,
TU.[TaskIsMarked]	AS TâcheEstMarquée,
TU.[TaskIsMilestone]	AS TâcheEstUnJalon,
TU.[TaskIsOverallocated]	AS TâcheEstEnSurutilisation,
TU.[TaskIsProjectSummary]	AS TâcheRécapitulativeProjet,
TU.[TaskIsRecurring]	AS TâcheRécurrente,
TU.[TaskIsSummary]	AS TâcheRécapitulative,
TU.[TaskLateFinish]	AS FinAuPlusTardTâche,
TU.[TaskLateStart]	AS DébutAuPlusTardTâche,
TU.[TaskLevelingDelay]	AS RetardNivellementTâche,
TU.[TaskModifiedDate]	AS DateModificationTâche,
TU.[TaskModifiedRevisionCounter]	AS NombreRévisionsModifiéesTâche,
TU.[TaskName]	AS NomTâche,
TU2.[TaskName]	AS NomTâcheParente,
TU.[TaskOutlineLevel]	AS NiveauHiérarchiqueTâche,
TU.[TaskOutlineNumber]	AS NuméroHiérarchiqueTâche,
TU.[TaskOvertimeCost]	AS CoûtHeuresSupplémentairesTâche,
TU.[TaskOvertimeWork]	AS TravailHeuresSupplémentairesTâche,
TU.[TaskParentUID]	AS IdTâcheParente,
TU.[TaskPercentCompleted]	AS PourcentageAchevéTâche,
TU.[TaskPercentWorkCompleted]	AS PourcentageTravailAchevéTâche,
TU.[TaskPhysicalPercentCompleted]	AS PourcentagePhysiqueAchevéTâche,
TU.[TaskPriority]	AS PrioritéTâche,
TU.[TaskRegularCost]	AS CoûtNormalTâche,
TU.[TaskRegularWork]	AS TravailNormalTâche,
TU.[TaskRemainingCost]	AS CoûtRestantTâche,
TU.[TaskRemainingDuration]	AS DuréeRestanteTâche,
TU.[TaskRemainingOvertimeCost]	AS CoûtHeuresSupplémentairesRestantesTâche,
TU.[TaskRemainingOvertimeWork]	AS TravailHeuresSupplémentairesRestantesTâche,
TU.[TaskRemainingRegularCost]	AS CoûtNormalRestantTâche,
TU.[TaskRemainingRegularWork]	AS TravailNormalRestantTâche,
TU.[TaskRemainingWork]	AS TravailRestantTâche,
TU.[TaskResourcePlanWork]	AS TravailPlanRessourcesTâche,
TU.[TaskSPI]	AS SPITâche,
TU.[TaskStartDate]	AS DateDébutTâche,
TU.[TaskStartDateString]	AS haîneDateDébutTâche,
TU.[TaskStartVariance]	AS VariationDébutTâche,
TU.[TaskStatusManagerUID]	AS UIDGestionnaireÉtatTâche,
TU.[TaskSV]	AS VSTâche,
TU.[TaskSVP]	AS PVPTâche,
TU.[TaskTCPI]	AS TCPITâche,
TU.[TaskTotalSlack]	AS MargeTotaleTâche,
TU.[TaskUID]	AS IdTâche,
TU.[TaskVAC]	AS VAATâche,
TU.[TaskWBS]	AS WBSTâche,
TU.[TaskWork]	AS TravailTâche,
TU.[TaskWorkVariance]	AS VariationTravailTâche
FROM
pjrep.MSP_EpmTask_UserView TU
LEFT JOIN
pjrep.MSP_EpmTask_UserView TU2
ON
TU.[TaskParentUID] = TU2.[TaskUID]
LEFT JOIN
pjrep.MSP_EpmProject_UserView PU
ON 
TU.ProjectUID = PU.ProjectUID


/*
REQUETE POUR LA TABLE AFFECTATIONS
*/

SELECT
AU.AssignmentActualCost	AS CoûtRéelAffectation,
AU.AssignmentActualFinishDate	AS AffectationDateFinRéelle,
AU.AssignmentActualOvertimeCost	AS CoûtHeuresSupplémentairesRéellesAffectation,
AU.AssignmentActualOvertimeWork	AS HeuresSupplémentairesRéellesAffectation,
AU.AssignmentActualRegularCost	AS CoûtNormalRéelAffectation,
AU.AssignmentActualRegularWork	AS TravailNormalRéelAffectation,
AU.AssignmentActualStartDate	AS AffectationDateDébutRéelle,
AU.AssignmentActualWork	AS AffectationTravailRéel,
AU.AssignmentACWP	AS CRTEAffectation,
AU.AssignmentBCWP	AS VAAffectation,
AU.AssignmentBCWS	AS VPAffectation,
AU.AssignmentBookingID	AS IdRéservationAffectation,
AU.AssignmentBudgetCost	AS CoûtBudgétaireAffectation,
AU.AssignmentBudgetMaterialWork	AS TravailMatériauBudgétaireAffectation,
AU.AssignmentBudgetWork	AS TravailBudgétaireAffectation,
AU.AssignmentCost	AS AffectationCoût,
AU.AssignmentCostVariance	AS VarianceCoûtAffectation,
AU.AssignmentCreatedDate	AS DateCréationAffectation,
AU.AssignmentCreatedRevisionCounter	AS CompteurRévisionsCrééAffectation,
AU.AssignmentCV	AS VCAffectation,
AU.AssignmentDelay	AS RetardAffectation,
AU.AssignmentFinishDate	AS AffectationDateFin,
AU.AssignmentFinishVariance	AS VarianceFinAffectation,
AU.AssignmentIsOverallocated	AS AffectationEstSurutilisée,
AU.AssignmentIsPublished	AS AffectationEstPubliée,
AU.AssignmentMaterialActualWork	AS TravailRéelMatériauAffectation,
AU.AssignmentMaterialWork	AS TravailMatériauAffectation,
AU.AssignmentModifiedDate	AS AffectationDateModification,
AU.AssignmentModifiedRevisionCounter	AS CompteurRévisionsModifiéAffectation,
AU.AssignmentOvertimeCost	AS CoûtHeuresSupplémentairesAffectation,
AU.AssignmentOvertimeWork	AS HeuresSupplémentairesAffectation,
AU.AssignmentPeakUnits	AS UnitésPicAffectation,
AU.AssignmentPercentWorkCompleted	AS AffectationPourcentageTravailEffectué,
AU.AssignmentRegularCost	AS CoûtNormalAffectation,
AU.AssignmentRegularWork	ASTravailNormalAffectation,
AU.AssignmentRemainingCost	AS AffectationCoûtRestant,
AU.AssignmentRemainingOvertimeCost	AS CoûtHeuresSupplémentairesRestantes,
AU.AssignmentRemainingOvertimeWork	AS HeuresSupplémentairesRestantesAffectation,
AU.AssignmentRemainingRegularCost	AS CoûtNormalRestantAffectation,
AU.AssignmentRemainingRegularWork	AS TravailNormalRestantAffectation,
AU.AssignmentRemainingWork	AS AffectationTravailRestant,
AU.AssignmentResourcePlanWork	AS AffectationRessourcePlanTravail,
AU.AssignmentResourceType	AS AffectationTypeRessource,
AU.AssignmentStartDate	AS AffectationDateDébut,
AU.AssignmentStartVariance	AS VarianceDébutAffectation,
AU.AssignmentSV	AS EDAffectation,
AU.AssignmentType	AS AffectationType,
AU.AssignmentUID	AS IdAffectation,
AU.AssignmentVAC	AS VAAAffectation,
AU.AssignmentWork	AS AffectationTravail,
AU.AssignmentWorkVariance	AS VarianceTravailAffectation,
AU.IsPublic	AS EstPublic,
AU.ProjectUID	AS IdProjet,
AU.ResourceUID	AS IdRessource,
AU.TaskIsActive	AS TâcheEstActive,
AU.TaskUID	AS IdTâche,
AU.TimesheetClassUID	AS IdClasseFeuilleDeTemps,
AB.AssignmentBookingDescription	AS DescriptionRéservationAffectation,
AB.AssignmentBookingName	AS NomRéservationAffectation,
AAU.AssignmentAllUpdatesApplied	AS AssignmentAllUpdatesApplied,
AAU.AssignmentUpdatesAppliedDate	AS AssignmentUpdatesAppliedDate,
AT.TypeDescription	AS DescriptionType,
AT.TypeName	AS NomType,
PU.ProjectName	AS NomProjet,
RU.ResourceName	AS NomRessource,
TU.TaskName	AS NomTâche
FROM
pjrep.MSP_EpmAssignment_UserView AU
LEFT JOIN
pjrep.MSP_EpmAssignmentBooking AB
ON 
AU.AssignmentBookingID = AB.AssignmentBookingID
LEFT JOIN
pjrep.MSP_EpmAssignmentsApplied_UserView AAU
ON
AU.AssignmentUID = AAU.AssignmentUID
LEFT JOIN
pjrep.MSP_EpmAssignmentType AT
ON
AU.AssignmentType = AT.AssignmentType
LEFT JOIN
pjrep.MSP_EpmProject_UserView PU
ON
AU.ProjectUID = PU.ProjectUID
LEFT JOIN
pjrep.MSP_EpmResource_UserView RU
ON
AU.ResourceUID = RU.ResourceUID
LEFT JOIN
pjrep.MSP_EpmTask_UserView TU
ON
AU.TaskUID = TU.TaskUID


/*
REQUETE POUR LA TABLE RESSOURCES
*/

SELECT
RU.ResourceBaseCalendar	AS CalendrierBaseRessource,
RU.ResourceBookingType	AS TypeRéservationRessource,
RU.ResourceCanLevel	AS RessourceÀniveler,
RU.ResourceCode	AS CodeRessource,
RU.ResourceCostCenter	AS CentreCoûtRessource,
RU.ResourceCostPerUse	AS CoûtRessourceParUtilisation,
RU.ResourceCreatedDate	AS DateCréationRessource,
RU.ResourceEarliestAvailableFrom	AS RessourceDisponibleAuPlusTôtDu,
RU.ResourceEmailAddress	AS AdresseMessagerieRessource,
RU.ResourceGroup	AS GroupeRessources,
RU.ResourceHyperlink	AS LienHypertexteRessource,
RU.ResourceHyperlinkHref	AS RéfÉlevéeLienHypertexteRessource,
RU.ResourceUID	AS IdRessource,
RU.ResourceInitials	AS InitialesRessource,
RU.ResourceIsActive	AS RessourceEstActive,
RU.ResourceIsGeneric	AS RessourceEstGénérique,
RU.ResourceIsTeam	AS RessourceÉquipe,
RU.ResourceLatestAvailableTo	AS RessourceDisponibleAuPlusTardAu,
RU.ResourceMaterialLabel	AS ÉtiquetteMatériauRessource,
RU.ResourceMaxUnits	AS UnitésMaxRessource,
RU.ResourceModifiedDate	AS DateModificationRessource,
RU.ResourceName	AS NomRessource,
RU.ResourceNTAccount	AS CompteNTRessource,
RU.ResourceOvertimeRate	AS TauxHeuresSupplémentairesRessource,
RU.ResourceStandardRate	AS TauxStandardRessource,
RU.ResourceStatusUID	AS IdÉtatRessource,
RU.ResourceTimesheetManagerUID	AS IdGestionFeuilleDeTempsRessource,
RU.ResourceType	AS TypeRessource,
RU.ResourceWorkgroup	AS GroupeTravailRessource,
RS.ResourceStatusName	AS NomÉtatRessource,
RT.TypeDescription	AS DescriptionType,
RT.TypeName	AS NomType
FROM
pjrep.MSP_EpmResource_UserView RU
LEFT JOIN
pjrep.MSP_EpmResourceStatus RS
ON
RU.ResourceStatusUID = RS.ResourceStatusUID
LEFT JOIN
pjrep.MSP_EpmResourceType RT
ON
RU.ResourceType = RT.ResourceType

/*
REQUETE POUR LA TABLE TIMESET
*/

SELECT
TBD.TimeByDay	AS HeureParJour,
TBD.TimeDayOfTheMonth	AS  HeureJourDuMois,
TBD.TimeDayOfTheWeek	AS HeureJourDeLaSemaine,
TBD.TimeMonthOfTheYear	AS HeureMoisDeLAnnée,
TBD.TimeQuarter	AS TempsTrimestre,
TBD.TimeWeekOfTheYear	AS HeureSemaineDeLAnnée,
TBD.FiscalPeriodUID	AS IDPériodeFiscale,
TBD.FiscalPeriodName	AS NomPériodeFiscale,
TBD.FiscalQuarter	AS TrimestreFiscal,
TBD.FiscalYear	AS AnnéePériodeFiscale,
FP.FiscalPeriodStart	AS DébutPériodeFiscale,
FP.ModifiedDate	AS DateModificationPériodeFiscale
FROM
pjrep.MSP_TimeByDay TBD
LEFT JOIN
pjrep.MSP_FiscalPeriods_ODATAView FP
ON
TBD.FiscalPeriodUID = FP.FiscalPeriodUID 

/*
REQUETE POUR LA TABLE TIMESHEET
*/

-- IL MANQUE LA COLONNE DESCRIPTION QUI EST DIFFERENTE DE LA COLONNE STATUSDESCRIPTION ET QUE JE NE RETROUVE PAS

SELECT
TS.TimesheetUID	AS TimesheetId,
TS.Comment	AS Comment,
TS.ModifiedDate	AS ModifiedDate,
TS.PeriodUID	AS PeriodId,
TS.TimesheetName	AS TimesheetName,
TS.OwnerResourceNameUID	AS TimesheetOwnerId,
TS.TimesheetStatusID	AS TimesheetStatusId,
TSP.EndDate	AS EndDate,
TSP.PeriodName	AS PeriodName,
TSP.PeriodStatusID	AS PeriodStatusId,
TSP.StartDate	AS StartDate,
TSS.Description	AS StatusDescription,
MTR.ResourceName	AS TimesheetOwner
FROM
pjrep.MSP_Timesheet TS
LEFT JOIN
pjrep.MSP_TimesheetPeriod TSP
ON
TS.PeriodUID = TSP.PeriodUID
LEFT JOIN
pjrep.MSP_TimesheetStatus TSS
ON
TS.TimesheetStatusID = TSS.TimesheetStatusID
LEFT JOIN
pjrep.MSP_TimesheetResource MTR
ON MTR.ResourceNameUID = TS.OwnerResourceNameUID