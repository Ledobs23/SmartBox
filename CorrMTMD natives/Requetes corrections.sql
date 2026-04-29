/*
REQUETE POUR LA TABLE TACHES
*/

SELECT        src.ProjectUID AS IdProjet, src.TaskUID AS IdTâche, src.TaskParentUID AS IdTâcheParente, jParent.TaskName AS NomTâcheParente, jProject.ProjectName AS NomProjet, src.TaskActualCost AS CoûtRéelTâche, 
                         src.TaskActualDuration AS DuréeRéelleTâche, src.TaskActualFinishDate AS DateFinRéelleTâche, src.TaskActualFixedCost AS CoûtFixeRéelTâche, src.TaskActualOvertimeCost AS CoûtHeuresSupplémentairesRéelTâche, 
                         src.TaskActualOvertimeWork AS TravailHeuresSupplémentairesRéellesTâche, src.TaskActualRegularCost AS CoûtNormalRéelTâche, src.TaskActualRegularWork AS TravailNormalRéelTâche, 
                         src.TaskActualStartDate AS DateDébutRéelleTâche, src.TaskActualWork AS TravailRéelTâche, src.TaskACWP AS CRTETâche, src.TaskBCWP AS VATâche, src.TaskBCWS AS VPTâche, 
                         src.TaskBudgetCost AS CoûtBudgétaireTâche, src.TaskBudgetWork AS TravailBudgétaireTâche, src.TaskClientUniqueId AS IDUniqueClientTâche, src.TaskCost AS CoûtTâche, src.TaskCostVariance AS VariationCoûtTâche, 
                         src.TaskCPI AS IPCTâche, src.TaskCreatedDate AS DateCréationTâche, src.TaskCreatedRevisionCounter AS NombreRévisionsCrééesTâche, src.TaskCV AS VCTâche, src.TaskCVP AS PVCTâche, 
                         src.TaskDeadline AS ÉchéanceTâche, src.TaskDeliverableFinishDate AS DateFinLivrableTâche, src.TaskDeliverableStartDate AS DateDébutLivrableTâche, src.TaskDuration AS DuréeTâche, 
                         src.TaskDurationIsEstimated AS DuréeEstiméeTâche, src.TaskDurationString AS ChaîneDuréeTâche, src.TaskDurationVariance AS VariationDuréeTâche, src.TaskEAC AS EAATâche, src.TaskEarlyFinish AS FinAuPlusTôtTâche, 
                         src.TaskEarlyStart AS DébutAuPlusTôtTâche, src.TaskFinishDate AS DateFinTâche, src.TaskFinishDateString AS ChaîneDateFinTâche, src.TaskFinishVariance AS VariationFinTâche, src.TaskFixedCost AS CoûtFixeTâche, 
                         src.FixedCostAssignmentUID AS IdAffectationCoûtFixeTâche, src.TaskFreeSlack AS MargeLibreTâche, src.TaskHyperLinkAddress AS AdresseLienHypertexteTâche, 
                         src.TaskHyperLinkFriendlyName AS LienHypertexteNomConvivialTâche, src.TaskHyperLinkSubAddress AS SousAdresseLienHypertexteTâche, src.TaskIgnoresResourceCalendar AS TâcheIgnoreCalendrierRessources, 
                         src.TaskIndex AS IndexTâche, src.TaskIsActive AS TâcheEstActive, src.TaskIsCritical AS TâcheEstCritique, src.TaskIsEffortDriven AS TâchePilotéeParEffort, src.TaskIsExternal AS TâcheExterne, 
                         src.TaskIsManuallyScheduled AS TâchePlanifiéeManuellement, src.TaskIsMarked AS TâcheEstMarquée, src.TaskIsMilestone AS TâcheEstUnJalon, src.TaskIsOverallocated AS TâcheEstEnSurutilisation, 
                         src.TaskIsProjectSummary AS TâcheRécapitulativeProjet, src.TaskIsRecurring AS TâcheRécurrente, src.TaskIsSummary AS TâcheRécapitulative, src.TaskLateFinish AS FinAuPlusTardTâche, 
                         src.TaskLateStart AS DébutAuPlusTardTâche, src.TaskLevelingDelay AS RetardNivellementTâche, src.TaskModifiedDate AS DateModificationTâche, src.TaskModifiedRevisionCounter AS NombreRévisionsModifiéesTâche, 
                         src.TaskName AS NomTâche, src.TaskOutlineLevel AS NiveauHiérarchiqueTâche, src.TaskOutlineNumber AS NuméroHiérarchiqueTâche, src.TaskOvertimeCost AS CoûtHeuresSupplémentairesTâche, 
                         src.TaskOvertimeWork AS TravailHeuresSupplémentairesTâche, src.TaskPercentCompleted AS PourcentageAchevéTâche, src.TaskPercentWorkCompleted AS PourcentageTravailAchevéTâche, 
                         src.TaskPhysicalPercentCompleted AS PourcentagePhysiqueAchevéTâche, src.TaskPriority AS PrioritéTâche, src.TaskRegularCost AS CoûtNormalTâche, src.TaskRegularWork AS TravailNormalTâche, 
                         src.TaskRemainingCost AS CoûtRestantTâche, src.TaskRemainingDuration AS DuréeRestanteTâche, src.TaskRemainingOvertimeCost AS CoûtHeuresSupplémentairesRestantesTâche, 
                         src.TaskRemainingOvertimeWork AS TravailHeuresSupplémentairesRestantesTâche, src.TaskRemainingRegularCost AS CoûtNormalRestantTâche, src.TaskRemainingRegularWork AS TravailNormalRestantTâche, 
                         src.TaskRemainingWork AS TravailRestantTâche, src.TaskResourcePlanWork AS TravailPlanRessourcesTâche, src.TaskSPI AS SPITâche, src.TaskStartDate AS DateDébutTâche, 
                         src.TaskStartDateString AS ChaîneDateDébutTâche, src.TaskStartVariance AS VariationDébutTâche, src.TaskStatusManagerUID AS UIDGestionnaireÉtatTâche, src.TaskSV AS VSTâche, src.TaskSVP AS PVPTâche, 
                         src.TaskTCPI AS TCPITâche, src.TaskTotalSlack AS MargeTotaleTâche, src.TaskVAC AS VAATâche, src.TaskWBS AS WBSTâche, src.TaskWork AS TravailTâche, src.TaskWorkVariance AS VariationTravailTâche, src.Sante, 
                         src.[État de l’indicateur] AS [Étatdel’indicateur], src.[Afficher rapport] AS Afficherrapport, src.[Code livrable GID] AS CodelivrableGID, src.Commentaire_GPR, src.[Date approuvée DGEI] AS DateapprouvéeDGEI, 
                         src.[Date demandée DGT] AS DatedemandéeDGT, src.[Date occupation] AS Dateoccupation, src.Lots, src.[No de dossier AGI] AS NodedossierAGI, 
                         src.[Numero de lot] AS Numerodelot, src.[Prise de possession légale] AS Prisedepossessionlégale, src.[WBS GPR] AS WBSGPR, src.[Dernier PC atteint tache] AS DernierPCatteinttache, src.[Écart PC0-PC1] AS ÉcartPC0PC1, 
                         src.[Écart PC0-PC2] AS ÉcartPC0PC2, src.[Écart PC0-PC3] AS ÉcartPC0PC3, src.[Écart PC0-PC4] AS ÉcartPC0PC4, src.[Écart PC0-PC5] AS ÉcartPC0PC5, src.[Écart PC0-PC6] AS ÉcartPC0PC6, src.[Écart PC0-PC7] AS ÉcartPC0PC7, 
                         src.[No de dossier] AS Nodedossier, src.[Services publics] AS Servicespublics, src.Statut, src.[Type terrain] AS Typeterrain, I.[MemberFullValue]	AS Indicateurtypetâche, CAST(NULL AS nvarchar(255)) AS Affectations, CAST(NULL AS nvarchar(255)) 
                         AS PlanningsDeRéférenceAffectations, CAST(NULL AS nvarchar(255)) AS DonnéesChronologiquesRéférenceAffectations, CAST(NULL AS nvarchar(255)) AS PlanningsDeRéférence, CAST(NULL AS nvarchar(255)) 
                         AS JeuDonnéesChronologiquesPlanningsDeRéférence, CAST(NULL AS nvarchar(255)) AS Problèmes, CAST(NULL AS nvarchar(255)) AS Projet, CAST(NULL AS nvarchar(255)) AS Risques, CAST(NULL AS nvarchar(255)) 
                         AS InfosChronologiques
FROM            src_pjrep.MSP_EpmTask_UserView AS src LEFT OUTER JOIN
                         src_pjrep.MSP_EpmTask_UserView AS jParent ON jParent.TaskUID = src.TaskParentUID LEFT OUTER JOIN
                         src_pjrep.MSP_EpmProject_UserView AS jProject ON jProject.ProjectUID = src.ProjectUID LEFT OUTER JOIN
                         src_pjrep.[MSPCFTASK_Indicateur type tâche_AssociationView] AS TI ON src.TaskUID = TI.EntityUID LEFT OUTER JOIN
                         src_pjrep.[MSPLT_Indicateur Type tache_UserView] AS I ON TI.LookupMemberUID = I.LookupMemberUID





/*
REQUETE POUR LA TABLE AFFECTATIONS
*/

SELECT        src.ProjectUID AS IdProjet, src.AssignmentUID AS IdAffectation, src.AssignmentActualCost AS CoûtRéelAffectation, src.AssignmentActualFinishDate AS AffectationDateFinRéelle, 
                         src.AssignmentActualOvertimeCost AS CoûtHeuresSupplémentairesRéellesAffectation, src.AssignmentActualOvertimeWork AS HeuresSupplémentairesRéellesAffectation, 
                         src.AssignmentActualRegularCost AS CoûtNormalRéelAffectation, src.AssignmentActualRegularWork AS TravailNormalRéelAffectation, src.AssignmentActualStartDate AS AffectationDateDébutRéelle, 
                         src.AssignmentActualWork AS AffectationTravailRéel, src.AssignmentACWP AS CRTEAffectation, jAssignApplied.AssignmentAllUpdatesApplied, src.AssignmentBCWP AS VAAffectation, src.AssignmentBCWS AS VPAffectation, 
                         j1.AssignmentBookingDescription AS DescriptionRéservationAffectation, src.AssignmentBookingID AS IdRéservationAffectation, j1.AssignmentBookingName AS NomRéservationAffectation, 
                         src.AssignmentBudgetCost AS CoûtBudgétaireAffectation, src.AssignmentBudgetMaterialWork AS TravailMatériauBudgétaireAffectation, src.AssignmentBudgetWork AS TravailBudgétaireAffectation, 
                         src.AssignmentCost AS AffectationCoût, src.AssignmentCostVariance AS VarianceCoûtAffectation, src.AssignmentCreatedDate AS DateCréationAffectation, 
                         src.AssignmentCreatedRevisionCounter AS CompteurRévisionsCrééAffectation, src.AssignmentCV AS VCAffectation, src.AssignmentDelay AS RetardAffectation, src.AssignmentFinishDate AS AffectationDateFin, 
                         src.AssignmentFinishVariance AS VarianceFinAffectation, src.AssignmentIsOverallocated AS AffectationEstSurutilisée, src.AssignmentIsPublished AS AffectationEstPubliée, 
                         src.AssignmentMaterialActualWork AS TravailRéelMatériauAffectation, src.AssignmentMaterialWork AS TravailMatériauAffectation, src.AssignmentModifiedDate AS AffectationDateModification, 
                         src.AssignmentModifiedRevisionCounter AS CompteurRévisionsModifiéAffectation, src.AssignmentOvertimeCost AS CoûtHeuresSupplémentairesAffectation, src.AssignmentOvertimeWork AS HeuresSupplémentairesAffectation, 
                         src.AssignmentPeakUnits AS UnitésPicAffectation, src.AssignmentPercentWorkCompleted AS AffectationPourcentageTravailEffectué, src.AssignmentRegularCost AS CoûtNormalAffectation, 
                         src.AssignmentRegularWork AS TravailNormalAffectation, src.AssignmentRemainingCost AS AffectationCoûtRestant, src.AssignmentRemainingOvertimeCost AS CoûtHeuresSupplémentairesRestantes, 
                         src.AssignmentRemainingOvertimeWork AS HeuresSupplémentairesRestantesAffectation, src.AssignmentRemainingRegularCost AS CoûtNormalRestantAffectation, 
                         src.AssignmentRemainingRegularWork AS TravailNormalRestantAffectation, src.AssignmentRemainingWork AS AffectationTravailRestant, src.AssignmentResourcePlanWork AS AffectationRessourcePlanTravail, 
                         src.AssignmentResourceType AS AffectationTypeRessource, src.AssignmentStartDate AS AffectationDateDébut, src.AssignmentStartVariance AS VarianceDébutAffectation, src.AssignmentSV AS EDAffectation, 
                         src.AssignmentType AS AffectationType, jAssignApplied.AssignmentUpdatesAppliedDate, src.AssignmentVAC AS VAAAffectation, src.AssignmentWork AS AffectationTravail, 
                         src.AssignmentWorkVariance AS VarianceTravailAffectation, src.IsPublic AS EstPublic, jProject.ProjectName AS NomProjet, src.ResourceUID AS IdRessource, jResource.ResourceName AS NomRessource, 
                         src.TaskUID AS IdTâche, src.TaskIsActive AS TâcheEstActive, jTask.TaskName AS NomTâche, src.TimesheetClassUID AS IdClasseFeuilleDeTemps, j3.TypeDescription AS DescriptionType, j3.TypeName AS NomType, 
                         src.RBS_R, src.[Type de coût_R] AS Typedecoût_R, src.[Services de ressources_R] AS Servicesderessources_R, src.Sante_T, src.[État de l’indicateur_T] AS [Étatdel’indicateur_T], src.[Afficher rapport_T] AS Afficherrapport_T, 
                         src.[Cat depenses_R] AS Catdepenses_R, src.[Code livrable GID_T] AS CodelivrableGID_T, src.Commentaire_GPR_T, src.[Corps emploi_R] AS Corpsemploi_R, src.[Date approuvée DGEI_T] AS DateapprouvéeDGEI_T, 
                         src.[Date demandée DGT_T] AS DatedemandéeDGT_T, src.[Date occupation_T] AS Dateoccupation_T, I.MemberFullValue	AS Indicateurtypetâche_T, src.Lots_T, src.[No de dossier AGI_T] AS NodedossierAGI_T, 
                         src.NU_R, src.[Numero de lot_T] AS Numerodelot_T, src.[Prise de possession légale_T] AS Prisedepossessionlégale_T, src.UA_R, src.[WBS GPR_T] AS WBSGPR_T, src.[Dernier PC atteint tache_T] AS DernierPCatteinttache_T, 
                         src.[Écart PC0-PC1_T] AS ÉcartPC0PC1_T, src.[Écart PC0-PC2_T] AS ÉcartPC0PC2_T, src.[Écart PC0-PC3_T] AS ÉcartPC0PC3_T, src.[Écart PC0-PC4_T] AS ÉcartPC0PC4_T, src.[Écart PC0-PC5_T] AS ÉcartPC0PC5_T, 
                         src.[Écart PC0-PC6_T] AS ÉcartPC0PC6_T, src.[Écart PC0-PC7_T] AS ÉcartPC0PC7_T, src.[No de dossier_T] AS Nodedossier_T, src.[Services publics_T] AS Servicespublics_T, src.Statut_T, src.[Type terrain_T] AS Typeterrain_T, 
                         CAST(NULL AS nvarchar(255)) AS DébutRéférenceFinRéférence, CAST(NULL AS nvarchar(255)) AS Projet, CAST(NULL AS nvarchar(255)) AS Ressource, CAST(NULL AS nvarchar(255)) AS Tâche, CAST(NULL AS nvarchar(255)) 
                         AS DonnéesChronologiques
FROM            src_pjrep.MSP_EpmAssignment_UserView AS src LEFT OUTER JOIN
                         src_pjrep.MSP_EpmAssignmentBooking AS j1 ON j1.AssignmentBookingID = src.AssignmentBookingID LEFT OUTER JOIN
                         src_pjrep.MSP_EpmAssignmentType AS j3 ON j3.AssignmentType = src.AssignmentType AND j3.LCID =
                             (SELECT        TOP (1) CASE WHEN Language = N'FR' THEN 1036 ELSE 1033 END AS Expr1
                               FROM            cfg.PWA) LEFT OUTER JOIN
                         src_pjrep.MSP_EpmAssignmentsApplied_UserView AS jAssignApplied ON jAssignApplied.AssignmentUID = src.AssignmentUID LEFT OUTER JOIN
                         src_pjrep.MSP_EpmProject_UserView AS jProject ON jProject.ProjectUID = src.ProjectUID LEFT OUTER JOIN
                         src_pjrep.MSP_EpmResource_UserView AS jResource ON jResource.ResourceUID = src.ResourceUID LEFT OUTER JOIN
                         src_pjrep.MSP_EpmTask_UserView AS jTask ON jTask.TaskUID = src.TaskUID LEFT JOIN
                         src_pjrep.[MSPCFASSN_Indicateur type tâche_T_AssociationView] AS AI ON src.TaskUID = AI.EntityUID LEFT JOIN
                         src_pjrep.[MSPLT_Indicateur Type tache_UserView] I ON AI.LookupMemberUID = I.LookupMemberUID




/*
REQUETE POUR LA TABLE JeuDonnéesChronologiquesRéférenceAffectation
*/

SELECT        src.ProjectUID AS IdProjet, src.AssignmentUID AS IdAffectation, src.TimeByDay AS HeureParJour, src.BaselineNumber AS NuméroPlanningDeRéférence, 
                         src.AssignmentBaselineBudgetCost AS CoûtBudgétaireRéférenceAffectation, src.AssignmentBaselineBudgetMaterialWork AS TravailMatériauBudgétaireRéférenceAffectation, 
                         src.AssignmentBaselineBudgetWork AS TravailBudgétaireRéférenceAffectation, src.AssignmentBaselineCost AS CoûtRéférenceAffectation, src.AssignmentBaselineMaterialWork AS TravailMatériauRéférenceAffectation, 
                         src.AssignmentBaselineModifiedDate, src.AssignmentBaselineWork AS TravailRéférenceAffectation, src.FiscalPeriodUID AS IDPériodeFiscale, jProject.ProjectName AS NomProjet, j2.ResourceUID AS IdRessource, 
                         src.TaskUID AS IdTâche, jTask.TaskName AS NomTâche, CAST(NULL AS nvarchar(255)) AS Affectation, CAST(NULL AS nvarchar(255)) AS DébutRéférenceFinRéférence, CAST(NULL AS nvarchar(255)) AS Projet, CAST(NULL 
                         AS nvarchar(255)) AS Tâches, CAST(NULL AS nvarchar(255)) AS Heure
FROM            src_pjrep.MSP_EpmAssignmentBaselineByDay AS src LEFT OUTER JOIN
						 src_pjrep.MSP_EpmAssignment_UserView j2 ON src.AssignmentUID = j2.AssignmentUID LEFT OUTER JOIN
                         src_pjrep.MSP_EpmProject_UserView AS jProject ON jProject.ProjectUID = src.ProjectUID LEFT OUTER JOIN
                         src_pjrep.MSP_EpmTask_UserView AS jTask ON jTask.TaskUID = src.TaskUID