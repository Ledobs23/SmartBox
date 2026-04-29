/*=====================================================================================================================
    v6_05b_Load_Native_OData_Seed.sql
    Projet      : SmartBox V6
    Phase       : 05b - Seed natif OData → dic.*
    Rôle        : Peupler dic.EntityBinding, dic.EntityJoin et dic.EntityColumnPublication
                  à partir des requêtes de référence OData/PSSE (colonnes natives stables).
                  Les champs personnalisés client sont gérés par v6_06a (auto-découverte).

    Contrat
    - JoinStatus  = MANUAL  pour toutes les jointures natives (jamais écrasées par l'auto-découverte)
    - BindingStatus = MANUAL pour toutes les entités
    - MapStatus   = MAPPED     pour colonnes réelles issues de PSSE
    - MapStatus   = NAVIGATION pour CAST(NULL) — liens OData inter-entités, sans source PSSE
    - MapStatus   ≠ UNMAPPED   — ce statut signale une anomalie après pipeline complet

    Idempotence
    - Script rejouable : utilise MERGE sur clés naturelles
    - Ne touche pas aux lignes dont le statut est déjà MAPPED / NAVIGATION / MANUAL
      (les surcharges manuelles post-déploiement sont préservées)

    Prérequis
    - v6_06a exécuté (tables dic.EntityBinding, dic.EntityJoin, dic.EntityColumnPublication créées)
    - Synonymes src_pjrep.* configurés (v6_03a)

    Source
    - Equivalence des tables OData_sans custom field.sql
    - Requetes pour les vues liees aux *.sql (10 fichiers)
    - Requetes corrections.sql (colonnes NAVIGATION Tasks / Assignments)
=====================================================================================================================*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb')
    THROW 65001, N'Exécuter ce script dans la base SmartBox cible.', 1;

IF OBJECT_ID(N'dic.EntityBinding', N'U') IS NULL
    THROW 65010, N'dic.EntityBinding absente. Exécuter v6_06a avant v6_05b.', 1;

IF OBJECT_ID(N'dic.EntityJoin', N'U') IS NULL
    THROW 65011, N'dic.EntityJoin absente. Exécuter v6_06a avant v6_05b.', 1;

IF OBJECT_ID(N'dic.EntityColumnPublication', N'U') IS NULL
    THROW 65012, N'dic.EntityColumnPublication absente. Exécuter v6_06a avant v6_05b.', 1;

DECLARE @RunId uniqueidentifier = NEWID();
DECLARE @Msg   nvarchar(max);

/* ===========================================================================================
   PHASE A — dic.EntityBinding  (40 entités)
   Règle : BindingStatus = MANUAL → jamais écrasé par l'auto-détection
   =========================================================================================== */
RAISERROR(N'Phase A : EntityBinding...', 0, 1) WITH NOWAIT;

MERGE dic.EntityBinding AS tgt
USING (VALUES
    /* Groupe 1 : Entités principales */
    (N'Projects',    N'Projets',              N'pjrep', N'MSP_EpmProject_UserView'),
    (N'Tasks',       N'Tâches',               N'pjrep', N'MSP_EpmTask_UserView'),
    (N'Assignments', N'Affectations',         N'pjrep', N'MSP_EpmAssignment_UserView'),
    (N'Resources',   N'Ressources',           N'pjrep', N'MSP_EpmResource_UserView'),
    /* Groupe 2 : Temps et feuilles de temps */
    (N'TimeSet',                    N'CalendrierTemps',          N'pjrep', N'MSP_TimeByDay'),
    (N'Timesheet',                  N'FeuilleDeTemps',           N'pjrep', N'MSP_Timesheet'),
    (N'TimesheetClasses',           N'ClassesFeuilleTemps',      N'pjrep', N'MSP_TimesheetClass_UserView'),
    (N'TimesheetPeriods',           N'PériodesFeuilleTemps',     N'pjrep', N'MSP_TimesheetPeriod'),
    (N'TimesheetLines',             N'LignesFeuilleTemps',       N'pjrep', N'MSP_TimesheetLine_UserView'),
    (N'FiscalPeriods',              N'PériodesFiscales',         N'pjrep', N'MSP_FiscalPeriods_ODATAView'),
    (N'TimesheetLineActualDataSet', N'RéelsLigneFeuilleTemps',   N'pjrep', N'MSP_TimesheetActual'),
    /* Groupe 3 : Données chronologiques */
    (N'AssignmentTimephasedDataSet',         N'JeuDonnéesChronologiquesAffectation',         N'pjrep', N'MSP_EpmAssignmentByDay_UserView'),
    (N'TaskTimephasedDataSet',               N'JeuDonnéesChronologiquesTâche',               N'pjrep', N'MSP_EpmTaskByDay'),
    (N'ResourceTimephasedDataSet',           N'JeuDonnéesChronologiquesRessource',           N'pjrep', N'MSP_EpmResourceByDay_UserView'),
    (N'ResourceDemandTimephasedDataSet',     N'JeuDonnéesChronologiquesDemandRessource',     N'pjrep', N'MSP_EpmResourceDemandByDay_UserView'),
    (N'EngagementsTimephasedDataSet',        N'JeuDonnéesChronologiquesEngagements',         N'pjrep', N'MSP_EpmEngagementByDay_UserView'),
    /* Groupe 4 : Références (Baselines) */
    (N'AssignmentBaselines',                 N'RéférencesAffectation',                       N'pjrep', N'MSP_EpmAssignmentBaseline'),
    (N'AssignmentBaselineTimephasedDataSet', N'JeuDonnéesChronologiquesRéférenceAffectation',N'pjrep', N'MSP_EpmAssignmentBaselineByDay'),
    (N'TaskBaselines',                       N'RéférencesTâche',                             N'pjrep', N'MSP_EpmTaskBaseline'),
    (N'TaskBaselineTimephasedDataSet',       N'JeuDonnéesChronologiquesRéférenceTâche',      N'pjrep', N'MSP_EpmTaskBaselineByDay'),
    (N'ProjectBaselines',                    N'RéférencesProjet',                            N'pjrep', N'MSP_ProjectBaseline_ODATAView'),
    /* Groupe 5 : Risques, problèmes, livrables */
    (N'Risks',                 N'Risques',                      N'pjrep', N'MSP_WssRisk'),
    (N'RiskTaskAssociations',  N'AssociationsTâchesRisques',    N'pjrep', N'MSP_WssRiskTaskAssociation_UserView'),
    (N'Issues',                N'Problèmes',                    N'pjrep', N'MSP_WssIssue'),
    (N'IssueTaskAssociations', N'AssociationsTâchesProblèmes',  N'pjrep', N'MSP_WssIssueTaskAssociation_UserView'),
    (N'Deliverables',          N'Livrables',                    N'pjrep', N'MSP_WssDeliverable'),
    /* Groupe 6 : Portefeuille */
    (N'PortfolioAnalyses',          N'AnalysesPortefeuille',           N'pjrep', N'MSP_EpmPortfolioAnalysis_UserView'),
    (N'PortfolioAnalysisProjects',  N'ProjetsAnalysePortefeuille',     N'pjrep', N'MSP_EpmPortfolioAnalysisProject_UserView'),
    (N'CostScenarioProjects',       N'ProjetsScénarioCoût',            N'pjrep', N'MSP_EpmPortfolioCostConstraintProject_UserView'),
    (N'CostConstraintScenarios',    N'ScénariosContrainteCoût',        N'pjrep', N'MSP_EpmPortfolioCostConstraintScenario_UserView'),
    (N'ResourceConstraintScenarios',N'ScénariosContrainteRessources',  N'pjrep', N'MSP_EpmPortfolioResourceConstraintScenario_UserView'),
    (N'ResourceScenarioProjects',   N'ProjetsScénarioRessources',      N'pjrep', N'MSP_EpmPortfolioResourceConstraintProject_UserView'),
    /* Groupe 7 : Priorités et axes stratégiques */
    (N'Prioritizations',             N'DéfinitionsPriorités',               N'pjrep', N'MSP_EpmPrioritization_UserView'),
    (N'PrioritizationDrivers',       N'AxesDéfinitionsPriorités',           N'pjrep', N'MSP_EpmPrioritizationDriver_UserView'),
    (N'PrioritizationDriverRelations',N'RelationsAxesDéfinitionsPriorités', N'pjrep', N'MSP_EpmPrioritizationDriverRelation_UserView'),
    (N'BusinessDrivers',             N'AxesStratégiquesEntreprise',         N'pjrep', N'MSP_EpmBusinessDriver_UserView'),
    (N'BusinessDriverDepartments',   N'ServicesAxesStratégiques',           N'pjrep', N'MSP_EpmBusinessDriverDepartment_UserView'),
    /* Groupe 8 : Engagements et flux de travail */
    (N'Engagements',                  N'Engagements',                          N'pjrep', N'MSP_EpmEngagements_UserView'),
    (N'EngagementsComments',          N'CommentairesEngagements',              N'pjrep', N'MSP_EpmEngagementComments_UserView'),
    (N'ProjectWorkflowStageDataSet',  N'JeuDonnéesÉtapesFluxTravailProjet',   N'pjrep', N'MSP_EpmProjectWorkflowStatusInformation_UserView')
) AS src (EntityName_EN, EntityName_FR, PsseSchemaName, PsseObjectName)
ON tgt.EntityName_EN = src.EntityName_EN
WHEN NOT MATCHED THEN
    INSERT (EntityName_EN, EntityName_FR, PsseSchemaName, PsseObjectName, BindingAlias, BindingStatus)
    VALUES (src.EntityName_EN, src.EntityName_FR, src.PsseSchemaName, src.PsseObjectName, N'src', N'MANUAL')
WHEN MATCHED AND tgt.BindingStatus <> N'MANUAL' THEN
    UPDATE SET
        EntityName_FR  = src.EntityName_FR,
        PsseSchemaName = src.PsseSchemaName,
        PsseObjectName = src.PsseObjectName,
        BindingAlias   = N'src',
        BindingStatus  = N'MANUAL',
        UpdatedOn      = sysdatetime(),
        UpdatedBy      = suser_sname();

SET @Msg = CONCAT(N'  EntityBinding : ', @@ROWCOUNT, N' ligne(s) affectée(s).');
RAISERROR(@Msg, 0, 1) WITH NOWAIT;

/* ===========================================================================================
   PHASE B — dic.EntityJoin  (jointures natives, ~54 lignes)
   Règle : JoinStatus = MANUAL → jamais écrasé par v6_06a E7/E8
   Format JoinExpression : clause ON sans le mot-clé ON (ex. EPT.Col = src.Col)
   =========================================================================================== */
RAISERROR(N'Phase B : EntityJoin...', 0, 1) WITH NOWAIT;

MERGE dic.EntityJoin AS tgt
USING (VALUES
    /* --- Projects (6 joins) --- */
    (N'Projects', N'jEPT',     N'pjrep', N'MSP_EpmEnterpriseProjectType',              N'EPT',      N'LEFT', N'EPT.EnterpriseProjectTypeUID = src.EnterpriseProjectTypeUID',                                                        N'MANUAL', NULL),
    (N'Projects', N'jP',       N'pjrep', N'MSP_EpmProject',                            N'P',        N'LEFT', N'P.ProjectUID = src.ProjectUID',                                                                                       N'MANUAL', NULL),
    (N'Projects', N'jPDec',    N'pjrep', N'MSP_EpmProjectDecision_UserView',           N'PDU',      N'LEFT', N'PDU.ProjectUID = src.ProjectUID',                                                                                     N'MANUAL', NULL),
    (N'Projects', N'jPTRI',    N'pjrep', N'MSP_ProjectTimephasedRollupInfo_ODATAView', N'PTRI',     N'LEFT', N'PTRI.ProjectId = src.ProjectUID',                                                                                    N'MANUAL', NULL),
    (N'Projects', N'jWFI',     N'pjrep', N'MSP_EpmWorkflowInstance_UserView',          N'WIU',      N'LEFT', N'WIU.ProjectId = src.ProjectUID',                                                                                     N'MANUAL', NULL),
    (N'Projects', N'jWFOwner', N'pjrep', N'MSP_EpmResource_UserView',                  N'RU',       N'LEFT', N'RU.ResourceUID = WIU.WorkflowOwner',                                                                                N'MANUAL', N'jWFI'),
    /* --- Tasks (2 joins) --- */
    (N'Tasks', N'jParent',  N'pjrep', N'MSP_EpmTask_UserView',    N'jParent',  N'LEFT', N'jParent.TaskUID = src.TaskParentUID',  N'MANUAL', NULL),
    (N'Tasks', N'jProject', N'pjrep', N'MSP_EpmProject_UserView', N'jProject', N'LEFT', N'jProject.ProjectUID = src.ProjectUID', N'MANUAL', NULL),
    /* --- Assignments (6 joins) --- */
    (N'Assignments', N'jBook',     N'pjrep', N'MSP_EpmAssignmentBooking',          N'AB',  N'LEFT', N'AB.AssignmentBookingID = src.AssignmentBookingID',                                                                            N'MANUAL', NULL),
    (N'Assignments', N'jApplied',  N'pjrep', N'MSP_EpmAssignmentsApplied_UserView',N'AAU', N'LEFT', N'AAU.AssignmentUID = src.AssignmentUID',                                                                                      N'MANUAL', NULL),
    (N'Assignments', N'jAType',    N'pjrep', N'MSP_EpmAssignmentType',             N'AT',  N'LEFT', N'AT.AssignmentType = src.AssignmentType AND AT.LCID = (SELECT TOP 1 CASE WHEN Language = N''FR'' THEN 1036 ELSE 1033 END FROM cfg.PWA)', N'MANUAL', NULL),
    (N'Assignments', N'jProject',  N'pjrep', N'MSP_EpmProject_UserView',           N'PU',  N'LEFT', N'PU.ProjectUID = src.ProjectUID',                                                                                             N'MANUAL', NULL),
    (N'Assignments', N'jResource', N'pjrep', N'MSP_EpmResource_UserView',          N'RU',  N'LEFT', N'RU.ResourceUID = src.ResourceUID',                                                                                           N'MANUAL', NULL),
    (N'Assignments', N'jTask',     N'pjrep', N'MSP_EpmTask_UserView',              N'TU',  N'LEFT', N'TU.TaskUID = src.TaskUID',                                                                                                   N'MANUAL', NULL),
    /* --- Resources (2 joins) --- */
    (N'Resources', N'jStatus', N'pjrep', N'MSP_EpmResourceStatus', N'RS', N'LEFT', N'RS.ResourceStatusUID = src.ResourceStatusUID', N'MANUAL', NULL),
    (N'Resources', N'jRType',  N'pjrep', N'MSP_EpmResourceType',   N'RT', N'LEFT', N'RT.ResourceType = src.ResourceType',           N'MANUAL', NULL),
    /* --- TimeSet (1 join) --- */
    (N'TimeSet', N'jFP', N'pjrep', N'MSP_FiscalPeriods_ODATAView', N'FP', N'LEFT', N'FP.FiscalPeriodUID = src.FiscalPeriodUID', N'MANUAL', NULL),
    /* --- Timesheet (3 joins) --- */
    (N'Timesheet', N'jTSP',   N'pjrep', N'MSP_TimesheetPeriod', N'TSP', N'LEFT', N'TSP.PeriodUID = src.PeriodUID',                           N'MANUAL', NULL),
    (N'Timesheet', N'jTSS',   N'pjrep', N'MSP_TimesheetStatus', N'TSS', N'LEFT', N'TSS.TimesheetStatusID = src.TimesheetStatusID',            N'MANUAL', NULL),
    (N'Timesheet', N'jMTR',   N'pjrep', N'MSP_TimesheetResource',    N'MTR',N'LEFT', N'MTR.ResourceNameUID = src.OwnerResourceNameUID',       N'MANUAL', NULL),
    /* --- AssignmentBaselines (2 joins) --- */
    (N'AssignmentBaselines', N'jProject', N'pjrep', N'MSP_EpmProject_UserView', N'PU', N'LEFT', N'PU.ProjectUID = src.ProjectUID', N'MANUAL', NULL),
    (N'AssignmentBaselines', N'jTask',    N'pjrep', N'MSP_EpmTask_UserView',    N'TU', N'LEFT', N'TU.TaskUID = src.TaskUID',       N'MANUAL', NULL),
    /* --- AssignmentBaselineTimephasedDataSet (3 joins) --- */
    (N'AssignmentBaselineTimephasedDataSet', N'jAssign',  N'pjrep', N'MSP_EpmAssignment_UserView', N'AU', N'LEFT', N'AU.AssignmentUID = src.AssignmentUID', N'MANUAL', NULL),
    (N'AssignmentBaselineTimephasedDataSet', N'jProject', N'pjrep', N'MSP_EpmProject_UserView',    N'PU', N'LEFT', N'PU.ProjectUID = src.ProjectUID',       N'MANUAL', NULL),
    (N'AssignmentBaselineTimephasedDataSet', N'jTask',    N'pjrep', N'MSP_EpmTask_UserView',       N'TU', N'LEFT', N'TU.TaskUID = src.TaskUID',             N'MANUAL', NULL),
    /* --- AssignmentTimephasedDataSet (4 joins) --- */
    (N'AssignmentTimephasedDataSet', N'jABD',     N'pjrep', N'MSP_EpmAssignmentByDay',        N'ABD', N'LEFT', N'ABD.AssignmentUID = src.AssignmentUID', N'MANUAL', NULL),
    (N'AssignmentTimephasedDataSet', N'jProject', N'pjrep', N'MSP_EpmProject_UserView',       N'PU',  N'LEFT', N'PU.ProjectUID = src.ProjectUID',         N'MANUAL', NULL),
    (N'AssignmentTimephasedDataSet', N'jTask',    N'pjrep', N'MSP_EpmTask_UserView',          N'TU',  N'LEFT', N'TU.TaskUID = src.TaskUID',               N'MANUAL', NULL),
    (N'AssignmentTimephasedDataSet', N'jAssign',  N'pjrep', N'MSP_EpmAssignment_UserView',    N'AU',  N'LEFT', N'AU.AssignmentUID = src.AssignmentUID',   N'MANUAL', NULL),
    /* --- Deliverables (1 join) --- */
    (N'Deliverables', N'jProject', N'pjrep', N'MSP_EpmProject_UserView', N'PU', N'LEFT', N'PU.ProjectUID = src.ProjectUID', N'MANUAL', NULL),
    /* --- EngagementsTimephasedDataSet (2 joins) --- */
    (N'EngagementsTimephasedDataSet', N'jProject',  N'pjrep', N'MSP_EpmProject_UserView',  N'PU', N'LEFT', N'PU.ProjectUID = src.ProjectUID',   N'MANUAL', NULL),
    (N'EngagementsTimephasedDataSet', N'jResource', N'pjrep', N'MSP_EpmResource_UserView', N'RU', N'LEFT', N'RU.ResourceUID = src.ResourceUID', N'MANUAL', NULL),
    /* --- ProjectBaselines (1 join) --- */
    (N'ProjectBaselines', N'jProject', N'pjrep', N'MSP_EpmProject_UserView', N'PU', N'LEFT', N'PU.ProjectUID = src.ProjectUID', N'MANUAL', NULL),
    /* --- ResourceTimephasedDataSet (2 joins) --- */
    (N'ResourceTimephasedDataSet', N'jTBD',      N'pjrep', N'MSP_TimeByDay',           N'TBD', N'LEFT', N'TBD.TimeByDay = src.TimeByDay',       N'MANUAL', NULL),
    (N'ResourceTimephasedDataSet', N'jResource', N'pjrep', N'MSP_EpmResource_UserView',N'RU',  N'LEFT', N'RU.ResourceUID = src.ResourceUID',    N'MANUAL', NULL),
    /* --- ResourceDemandTimephasedDataSet (3 joins) --- */
    (N'ResourceDemandTimephasedDataSet', N'jTBD',      N'pjrep', N'MSP_TimeByDay',           N'TBD', N'LEFT', N'TBD.TimeByDay = src.TimeByDay',       N'MANUAL', NULL),
    (N'ResourceDemandTimephasedDataSet', N'jProject',  N'pjrep', N'MSP_EpmProject_UserView', N'PU',  N'LEFT', N'PU.ProjectUID = src.ProjectUID',       N'MANUAL', NULL),
    (N'ResourceDemandTimephasedDataSet', N'jResource', N'pjrep', N'MSP_EpmResource_UserView',N'RU',  N'LEFT', N'RU.ResourceUID = src.ResourceUID',    N'MANUAL', NULL),
    /* --- Risks / Issues (1 join each) --- */
    (N'Risks',   N'jProject', N'pjrep', N'MSP_EpmProject_UserView', N'PU', N'LEFT', N'PU.ProjectUID = src.ProjectUID', N'MANUAL', NULL),
    (N'Issues',  N'jProject', N'pjrep', N'MSP_EpmProject_UserView', N'PU', N'LEFT', N'PU.ProjectUID = src.ProjectUID', N'MANUAL', NULL),
    /* --- TaskBaselines (2 joins) --- */
    (N'TaskBaselines', N'jTask',    N'pjrep', N'MSP_EpmTask_UserView',    N'TU', N'LEFT', N'TU.TaskUID = src.TaskUID',       N'MANUAL', NULL),
    (N'TaskBaselines', N'jProject', N'pjrep', N'MSP_EpmProject_UserView', N'PU', N'LEFT', N'PU.ProjectUID = src.ProjectUID', N'MANUAL', NULL),
    /* --- TaskBaselineTimephasedDataSet (2 joins) --- */
    (N'TaskBaselineTimephasedDataSet', N'jProject', N'pjrep', N'MSP_EpmProject_UserView', N'PU', N'LEFT', N'PU.ProjectUID = src.ProjectUID', N'MANUAL', NULL),
    (N'TaskBaselineTimephasedDataSet', N'jTask',    N'pjrep', N'MSP_EpmTask_UserView',    N'TU', N'LEFT', N'TU.TaskUID = src.TaskUID',       N'MANUAL', NULL),
    /* --- TaskTimephasedDataSet (2 joins) --- */
    (N'TaskTimephasedDataSet', N'jProject', N'pjrep', N'MSP_EpmProject_UserView', N'PU', N'LEFT', N'PU.ProjectUID = src.ProjectUID', N'MANUAL', NULL),
    (N'TaskTimephasedDataSet', N'jTask',    N'pjrep', N'MSP_EpmTask_UserView',    N'TU', N'LEFT', N'TU.TaskUID = src.TaskUID',       N'MANUAL', NULL),
    /* --- TimesheetPeriods (1 join) --- */
    (N'TimesheetPeriods', N'jTSPS', N'pjrep', N'MSP_TimesheetPeriodStatus', N'TSPS', N'LEFT', N'TSPS.PeriodStatusID = src.PeriodStatusID', N'MANUAL', NULL),
    /* --- TimesheetLines (6 joins) --- */
    (N'TimesheetLines', N'jTSL',      N'pjrep', N'MSP_TimesheetLine',          N'TSL',  N'LEFT', N'TSL.TimesheetLineUID = src.TimesheetLineUID',           N'MANUAL', NULL),
    (N'TimesheetLines', N'jTSLS',     N'pjrep', N'MSP_TimesheetLineStatus',    N'TSLS', N'LEFT', N'TSLS.TimesheetLineStatusID = src.TimesheetLineStatusID', N'MANUAL', NULL),
    (N'TimesheetLines', N'jTS',       N'pjrep', N'MSP_Timesheet',              N'TS',   N'LEFT', N'TS.TimesheetUID = src.TimesheetUID',                    N'MANUAL', NULL),
    (N'TimesheetLines', N'jTSCU',     N'pjrep', N'MSP_TimesheetClass_UserView',N'TSCU', N'LEFT', N'TSCU.ClassUID = src.TimesheetLineClassUID',              N'MANUAL', NULL),
    (N'TimesheetLines', N'jApprover', N'pjrep', N'MSP_EpmResource_UserView',   N'RU1',  N'LEFT', N'RU1.ResourceUID = TSL.ApproverResourceNameUID',          N'MANUAL', N'jTSL'),
    (N'TimesheetLines', N'jMTR',     N'pjrep', N'MSP_TimesheetResource',      N'MTR',  N'LEFT', N'MTR.ResourceNameUID = TS.OwnerResourceNameUID',          N'MANUAL', N'jTS'),
    /* --- TimesheetLineActualDataSet (1 join) --- */
    (N'TimesheetLineActualDataSet', N'jResource', N'pjrep', N'MSP_EpmResource_UserView', N'RU', N'LEFT', N'RU.ResourceUID = src.LastChangedResourceNameUID', N'MANUAL', NULL)
) AS src (EntityName_EN, JoinTag, PsseSchemaName, PsseObjectName, JoinAlias, JoinType, JoinExpression, JoinStatus, JoinDependsOn)
ON  tgt.EntityName_EN = src.EntityName_EN
AND tgt.JoinTag       = src.JoinTag
WHEN NOT MATCHED THEN
    INSERT (EntityName_EN, JoinTag, PsseSchemaName, PsseObjectName, JoinAlias, JoinType, JoinExpression, JoinStatus, JoinDependsOn, IsActive)
    VALUES (src.EntityName_EN, src.JoinTag, src.PsseSchemaName, src.PsseObjectName, src.JoinAlias, src.JoinType, src.JoinExpression, src.JoinStatus, src.JoinDependsOn, 1)
WHEN MATCHED AND tgt.JoinStatus <> N'MANUAL' THEN
    UPDATE SET
        PsseSchemaName = src.PsseSchemaName,
        PsseObjectName = src.PsseObjectName,
        JoinAlias      = src.JoinAlias,
        JoinType       = src.JoinType,
        JoinExpression = src.JoinExpression,
        JoinStatus     = src.JoinStatus,
        JoinDependsOn  = src.JoinDependsOn,
        IsActive       = 1,
        UpdatedOn      = sysdatetime(),
        UpdatedBy      = suser_sname();

SET @Msg = CONCAT(N'  EntityJoin : ', @@ROWCOUNT, N' ligne(s) affectée(s).');
RAISERROR(@Msg, 0, 1) WITH NOWAIT;

/* ===========================================================================================
   PHASE C — dic.EntityColumnPublication  (colonnes natives)
   Une MERGE par entité pour lisibilité et débogage.
   Format SourceExpression : alias.ColonnePSSE (ex. src.ProjectName, EPT.IsDefault)
   Règle MERGE : ne met à jour que si MapStatus ∉ {MAPPED, NAVIGATION} (préserve les surcharges)
   =========================================================================================== */
RAISERROR(N'Phase C : EntityColumnPublication — Projects...', 0, 1) WITH NOWAIT;

MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'Projects',N'Projets',  1,N'EnterpriseProjectTypeDescription',      N'DescriptionTypeProjetEntreprise',                     N'EPT',  N'EPT.EnterpriseProjectTypeDescription',      N'MAPPED'),
    (N'Projects',N'Projets',  2,N'EnterpriseProjectTypeName',             N'NomTypeProjetEntreprise',                             N'EPT',  N'EPT.EnterpriseProjectTypeName',             N'MAPPED'),
    (N'Projects',N'Projets',  3,N'IsDefault',                             N'TypeProjetEntrepriseParDéfaut',                       N'EPT',  N'EPT.IsDefault',                             N'MAPPED'),
    (N'Projects',N'Projets',  4,N'ProjectIdentifier',                     N'IdentificateurProjet',                                N'P',    N'P.ProjectIdentifier',                       N'MAPPED'),
    (N'Projects',N'Projets',  5,N'ProjectLastPublishedDate',              N'ProjectLastPublishedDate',                            N'P',    N'P.ProjectLastPublishedDate',                N'MAPPED'),
    (N'Projects',N'Projets',  6,N'EnterpriseProjectTypeUID',              N'IdTypeProjetEntreprise',                              N'src',  N'src.EnterpriseProjectTypeUID',              N'MAPPED'),
    (N'Projects',N'Projets',  7,N'ParentProjectUID',                      N'IdProjetParent',                                      N'src',  N'src.ParentProjectUID',                      N'MAPPED'),
    (N'Projects',N'Projets',  8,N'ProjectActualCost',                     N'CoûtRéelProjet',                                      N'src',  N'src.ProjectActualCost',                     N'MAPPED'),
    (N'Projects',N'Projets',  9,N'ProjectActualDuration',                 N'DuréeRéelleProjet',                                   N'src',  N'src.ProjectActualDuration',                 N'MAPPED'),
    (N'Projects',N'Projets', 10,N'ProjectActualFinishDate',               N'DateFinRéelleProjet',                                 N'src',  N'src.ProjectActualFinishDate',               N'MAPPED'),
    (N'Projects',N'Projets', 11,N'ProjectActualOvertimeCost',             N'CoûtsHeuresSupplémentairesRéellesProjet',             N'src',  N'src.ProjectActualOvertimeCost',             N'MAPPED'),
    (N'Projects',N'Projets', 12,N'ProjectActualOvertimeWork',             N'TravailHeuresSupplémentairesRéellesProjet',           N'src',  N'src.ProjectActualOvertimeWork',             N'MAPPED'),
    (N'Projects',N'Projets', 13,N'ProjectActualRegularCost',              N'CoûtNormaRéelProjet',                                 N'src',  N'src.ProjectActualRegularCost',              N'MAPPED'),
    (N'Projects',N'Projets', 14,N'ProjectActualRegularWork',              N'TravailNormalRéelProjet',                             N'src',  N'src.ProjectActualRegularWork',              N'MAPPED'),
    (N'Projects',N'Projets', 15,N'ProjectActualStartDate',                N'DateDébutRéelProjet',                                 N'src',  N'src.ProjectActualStartDate',                N'MAPPED'),
    (N'Projects',N'Projets', 16,N'ProjectActualWork',                     N'TravailRéelProjet',                                   N'src',  N'src.ProjectActualWork',                     N'MAPPED'),
    (N'Projects',N'Projets', 17,N'ProjectACWP',                           N'CRTEProjet',                                          N'src',  N'src.ProjectACWP',                           N'MAPPED'),
    (N'Projects',N'Projets', 18,N'ProjectAuthorName',                     N'NomAuteurProjet',                                     N'src',  N'src.ProjectAuthorName',                     N'MAPPED'),
    (N'Projects',N'Projets', 19,N'ProjectBCWP',                           N'VAProjet',                                            N'src',  N'src.ProjectBCWP',                           N'MAPPED'),
    (N'Projects',N'Projets', 20,N'ProjectBCWS',                           N'VPProjet',                                            N'src',  N'src.ProjectBCWS',                           N'MAPPED'),
    (N'Projects',N'Projets', 21,N'ProjectBudgetCost',                     N'CoûtBudgétaireProjet',                                N'src',  N'src.ProjectBudgetCost',                     N'MAPPED'),
    (N'Projects',N'Projets', 22,N'ProjectBudgetWork',                     N'TravailBudgétaireProjet',                             N'src',  N'src.ProjectBudgetWork',                     N'MAPPED'),
    (N'Projects',N'Projets', 23,N'ProjectCalculationsAreStale',           N'CalculsProjetPérimés',                                N'src',  N'src.ProjectCalculationsAreStale',           N'MAPPED'),
    (N'Projects',N'Projets', 24,N'ProjectCalendarDuration',               N'DuréeCalendrierProjet',                               N'src',  N'src.ProjectCalendarDuration',               N'MAPPED'),
    (N'Projects',N'Projets', 25,N'ProjectCategoryName',                   N'NomCatégorieProjet',                                  N'src',  N'src.ProjectCategoryName',                   N'MAPPED'),
    (N'Projects',N'Projets', 26,N'ProjectCompanyName',                    N'NomSociétéProjet',                                    N'src',  N'src.ProjectCompanyName',                    N'MAPPED'),
    (N'Projects',N'Projets', 27,N'ProjectCost',                           N'CoûtProjet',                                          N'src',  N'src.ProjectCost',                           N'MAPPED'),
    (N'Projects',N'Projets', 28,N'ProjectCostVariance',                   N'VariationCoûtProjet',                                 N'src',  N'src.ProjectCostVariance',                   N'MAPPED'),
    (N'Projects',N'Projets', 29,N'ProjectCPI',                            N'IPCProjet',                                           N'src',  N'src.ProjectCPI',                            N'MAPPED'),
    (N'Projects',N'Projets', 30,N'ProjectCreatedDate',                    N'DateCréationProjet',                                  N'src',  N'src.ProjectCreatedDate',                    N'MAPPED'),
    (N'Projects',N'Projets', 31,N'ProjectCurrency',                       N'DeviseProjet',                                        N'src',  N'src.ProjectCurrency',                       N'MAPPED'),
    (N'Projects',N'Projets', 32,N'ProjectCV',                             N'VCProjet',                                            N'src',  N'src.ProjectCV',                             N'MAPPED'),
    (N'Projects',N'Projets', 33,N'ProjectCVP',                            N'PVCProjet',                                           N'src',  N'src.ProjectCVP',                            N'MAPPED'),
    (N'Projects',N'Projets', 34,N'ProjectDescription',                    N'DescriptionProjet',                                   N'src',  N'src.ProjectDescription',                    N'MAPPED'),
    (N'Projects',N'Projets', 35,N'ProjectDuration',                       N'DuréeProjet',                                         N'src',  N'src.ProjectDuration',                       N'MAPPED'),
    (N'Projects',N'Projets', 36,N'ProjectDurationVariance',               N'VariationDuréeProjet',                                N'src',  N'src.ProjectDurationVariance',               N'MAPPED'),
    (N'Projects',N'Projets', 37,N'ProjectEAC',                            N'EAAProjet',                                           N'src',  N'src.ProjectEAC',                            N'MAPPED'),
    (N'Projects',N'Projets', 38,N'ProjectEarlyFinish',                    N'FinAuPlusTôtProjet',                                  N'src',  N'src.ProjectEarlyFinish',                    N'MAPPED'),
    (N'Projects',N'Projets', 39,N'ProjectEarlyStart',                     N'DébutAuPlusTôtProjet',                                N'src',  N'src.ProjectEarlyStart',                     N'MAPPED'),
    (N'Projects',N'Projets', 40,N'ProjectEarnedValueIsStale',             N'AuditCoûtProjetEstPérimé',                            N'src',  N'src.ProjectEarnedValueIsStale',             N'MAPPED'),
    (N'Projects',N'Projets', 41,N'ProjectFinishDate',                     N'DateFinProjet',                                       N'src',  N'src.ProjectFinishDate',                     N'MAPPED'),
    (N'Projects',N'Projets', 42,N'ProjectFinishVariance',                 N'VariationFinProjet',                                  N'src',  N'src.ProjectFinishVariance',                 N'MAPPED'),
    (N'Projects',N'Projets', 43,N'ProjectFixedCost',                      N'CoûtFixeProjet',                                      N'src',  N'src.ProjectFixedCost',                      N'MAPPED'),
    (N'Projects',N'Projets', 44,N'ProjectKeywords',                       N'MotsClésProjet',                                      N'src',  N'src.ProjectKeywords',                       N'MAPPED'),
    (N'Projects',N'Projets', 45,N'ProjectLateFinish',                     N'FinAuPlusTardProjet',                                 N'src',  N'src.ProjectLateFinish',                     N'MAPPED'),
    (N'Projects',N'Projets', 46,N'ProjectLateStart',                      N'DébutAuPlusTardProjet',                               N'src',  N'src.ProjectLateStart',                      N'MAPPED'),
    (N'Projects',N'Projets', 47,N'ProjectManagerName',                    N'NomResponsableProjet',                                N'src',  N'src.ProjectManagerName',                    N'MAPPED'),
    (N'Projects',N'Projets', 48,N'ProjectModifiedDate',                   N'DateModificationProjet',                              N'src',  N'src.ProjectModifiedDate',                   N'MAPPED'),
    (N'Projects',N'Projets', 49,N'ProjectName',                           N'NomProjet',                                           N'src',  N'src.ProjectName',                           N'MAPPED'),
    (N'Projects',N'Projets', 50,N'ProjectOvertimeCost',                   N'CoûtHeuresSupplémentairesProjet',                     N'src',  N'src.ProjectOvertimeCost',                   N'MAPPED'),
    (N'Projects',N'Projets', 51,N'ProjectOvertimeWork',                   N'TravailHeuresSupplémentairesProjet',                  N'src',  N'src.ProjectOvertimeWork',                   N'MAPPED'),
    (N'Projects',N'Projets', 52,N'ProjectOwnerName',                      N'NomPropriétaireProjet',                               N'src',  N'src.ProjectOwnerName',                      N'MAPPED'),
    (N'Projects',N'Projets', 53,N'ProjectOwnerResourceUID',               N'IdPropriétaireProjet',                                N'src',  N'src.ProjectOwnerResourceUID',               N'MAPPED'),
    (N'Projects',N'Projets', 54,N'ProjectPercentCompleted',               N'PourcentageTerminéProjet',                            N'src',  N'src.ProjectPercentCompleted',               N'MAPPED'),
    (N'Projects',N'Projets', 55,N'ProjectPercentWorkCompleted',           N'PourcentageTravailTerminéProjet',                     N'src',  N'src.ProjectPercentWorkCompleted',           N'MAPPED'),
    (N'Projects',N'Projets', 56,N'ProjectRegularCost',                    N'CoûtNormalProjet',                                    N'src',  N'src.ProjectRegularCost',                    N'MAPPED'),
    (N'Projects',N'Projets', 57,N'ProjectRegularWork',                    N'TravailNormalProjet',                                 N'src',  N'src.ProjectRegularWork',                    N'MAPPED'),
    (N'Projects',N'Projets', 58,N'ProjectRemainingCost',                  N'CoûtRestantProjet',                                   N'src',  N'src.ProjectRemainingCost',                  N'MAPPED'),
    (N'Projects',N'Projets', 59,N'ProjectRemainingDuration',              N'DuréeRestanteProjet',                                 N'src',  N'src.ProjectRemainingDuration',              N'MAPPED'),
    (N'Projects',N'Projets', 60,N'ProjectRemainingOvertimeCost',          N'CoûtHeuresSupplémentairesRestantesProjet',            N'src',  N'src.ProjectRemainingOvertimeCost',          N'MAPPED'),
    (N'Projects',N'Projets', 61,N'ProjectRemainingOvertimeWork',          N'TravailHeuresSupplémentairesRestantesProjet',         N'src',  N'src.ProjectRemainingOvertimeWork',          N'MAPPED'),
    (N'Projects',N'Projets', 62,N'ProjectRemainingRegularCost',           N'CoûtNormalRestantProjet',                             N'src',  N'src.ProjectRemainingRegularCost',           N'MAPPED'),
    (N'Projects',N'Projets', 63,N'ProjectRemainingRegularWork',           N'TravailNormalRestantProjet',                          N'src',  N'src.ProjectRemainingRegularWork',           N'MAPPED'),
    (N'Projects',N'Projets', 64,N'ProjectRemainingWork',                  N'TravailRestantProjet',                                N'src',  N'src.ProjectRemainingWork',                  N'MAPPED'),
    (N'Projects',N'Projets', 65,N'ProjectResourcePlanWork',               N'TravailPlanRessourcesProjet',                         N'src',  N'src.ProjectResourcePlanWork',               N'MAPPED'),
    (N'Projects',N'Projets', 66,N'ProjectSPI',                            N'SPIProjet',                                           N'src',  N'src.ProjectSPI',                            N'MAPPED'),
    (N'Projects',N'Projets', 67,N'ProjectStartDate',                      N'DateDébutProjet',                                     N'src',  N'src.ProjectStartDate',                      N'MAPPED'),
    (N'Projects',N'Projets', 68,N'ProjectStartVariance',                  N'VariationDébutProjet',                                N'src',  N'src.ProjectStartVariance',                  N'MAPPED'),
    (N'Projects',N'Projets', 69,N'ProjectStatusDate',                     N'DateÉtatProjet',                                      N'src',  N'src.ProjectStatusDate',                     N'MAPPED'),
    (N'Projects',N'Projets', 70,N'ProjectSubject',                        N'ObjetProjet',                                         N'src',  N'src.ProjectSubject',                        N'MAPPED'),
    (N'Projects',N'Projets', 71,N'ProjectSV',                             N'VSProjet',                                            N'src',  N'src.ProjectSV',                             N'MAPPED'),
    (N'Projects',N'Projets', 72,N'ProjectSVP',                            N'SVPProjet',                                           N'src',  N'src.ProjectSVP',                            N'MAPPED'),
    (N'Projects',N'Projets', 73,N'ProjectTCPI',                           N'TCPIProjet',                                          N'src',  N'src.ProjectTCPI',                           N'MAPPED'),
    (N'Projects',N'Projets', 74,N'ProjectTitle',                          N'TitreProjet',                                         N'src',  N'src.ProjectTitle',                          N'MAPPED'),
    (N'Projects',N'Projets', 75,N'ProjectType',                           N'TypeProjet',                                          N'src',  N'src.ProjectType',                           N'MAPPED'),
    (N'Projects',N'Projets', 76,N'ProjectUID',                            N'IdProjet',                                            N'src',  N'src.ProjectUID',                            N'MAPPED'),
    (N'Projects',N'Projets', 77,N'ProjectVAC',                            N'VAAProjet',                                           N'src',  N'src.ProjectVAC',                            N'MAPPED'),
    (N'Projects',N'Projets', 78,N'ProjectWork',                           N'TravailProjet',                                       N'src',  N'src.ProjectWork',                           N'MAPPED'),
    (N'Projects',N'Projets', 79,N'ProjectWorkspaceInternalHRef',          N'UrlInterneEspaceDeTravailProjet',                     N'src',  N'src.ProjectWorkspaceInternalHRef',          N'MAPPED'),
    (N'Projects',N'Projets', 80,N'ProjectWorkVariance',                   N'VariationTravailProjet',                              N'src',  N'src.ProjectWorkVariance',                   N'MAPPED'),
    (N'Projects',N'Projets', 81,N'ResourcePlanUtilizationDate',           N'DatePlanUtilisationRessource',                        N'src',  N'src.ResourcePlanUtilizationDate',           N'MAPPED'),
    (N'Projects',N'Projets', 82,N'ResourcePlanUtilizationType',           N'TypePlanUtilisationRessource',                        N'src',  N'src.ResourcePlanUtilizationType',           N'MAPPED'),
    (N'Projects',N'Projets', 83,N'OptimizerCommitDate',                   N'DateValidationOptimiseur',                            N'PDU',  N'PDU.OptimizerCommitDate',                   N'MAPPED'),
    (N'Projects',N'Projets', 84,N'OptimizerDecisionAliasLookupTableUID',  N'IdTableChoixAliasDécisionOptimiseur',                 N'PDU',  N'PDU.OptimizerDecisionAliasLookupTableUID',  N'MAPPED'),
    (N'Projects',N'Projets', 85,N'OptimizerDecisionID',                   N'IdDécisionOptimiseur',                                N'PDU',  N'PDU.OptimizerDecisionID',                   N'MAPPED'),
    (N'Projects',N'Projets', 86,N'OptimizerDecisionName',                 N'NomDécisionOptimiseur',                               N'PDU',  N'PDU.OptimizerDecisionName',                 N'MAPPED'),
    (N'Projects',N'Projets', 87,N'OptimizerSolutionName',                 N'NomSolutionOptimiseur',                               N'PDU',  N'PDU.OptimizerSolutionName',                 N'MAPPED'),
    (N'Projects',N'Projets', 88,N'PlannerCommitDate',                     N'DateValidationPlanificateur',                         N'PDU',  N'PDU.PlannerCommitDate',                     N'MAPPED'),
    (N'Projects',N'Projets', 89,N'PlannerDecisionAliasLookupTableUID',    N'IdTableChoixAliasDécisionPlanificateur',              N'PDU',  N'PDU.PlannerDecisionAliasLookupTableUID',    N'MAPPED'),
    (N'Projects',N'Projets', 90,N'PlannerDecisionID',                     N'IdDécisionPlanificateur',                             N'PDU',  N'PDU.PlannerDecisionID',                     N'MAPPED'),
    (N'Projects',N'Projets', 91,N'PlannerDecisionName',                   N'NomDécisionPlanificateur',                            N'PDU',  N'PDU.PlannerDecisionName',                   N'MAPPED'),
    (N'Projects',N'Projets', 92,N'PlannerEndDate',                        N'DateFinPlanificateur',                                N'PDU',  N'PDU.PlannerEndDate',                        N'MAPPED'),
    (N'Projects',N'Projets', 93,N'PlannerSolutionName',                   N'NomSolutionPlanificateur',                            N'PDU',  N'PDU.PlannerSolutionName',                   N'MAPPED'),
    (N'Projects',N'Projets', 94,N'PlannerStartDate',                      N'DateDébutPlanificateur',                              N'PDU',  N'PDU.PlannerStartDate',                      N'MAPPED'),
    (N'Projects',N'Projets', 95,N'WorkflowOwnerResourceName',             N'NomPropriétaireFluxDeTravail',                        N'RU',   N'RU.ResourceName',                           N'MAPPED'),
    (N'Projects',N'Projets', 96,N'WorkflowCreated',                       N'DateCréationFluxDeTravail',                           N'WIU',  N'WIU.WorkflowCreated',                       N'MAPPED'),
    (N'Projects',N'Projets', 97,N'WorkflowError',                         N'ErreurFluxDeTravail',                                 N'WIU',  N'WIU.WorkflowError',                         N'MAPPED'),
    (N'Projects',N'Projets', 98,N'WorkflowErrorResponseCode',             N'CodeRéponseErreurFluxDeTravail',                      N'WIU',  N'WIU.WorkflowErrorResponseCode',             N'MAPPED'),
    (N'Projects',N'Projets', 99,N'WorkflowInstanceId',                    N'IdInstanceFluxDeTravail',                             N'WIU',  N'WIU.WorkflowInstanceId',                    N'MAPPED'),
    (N'Projects',N'Projets',100,N'WorkflowOwner',                         N'IdPropriétaireFluxDeTravail',                         N'WIU',  N'WIU.WorkflowOwner',                         N'MAPPED'),
    (N'Projects',N'Projets',101,N'TimePhased',                            N'ProjetChronologique',                                 N'PTRI', N'PTRI.TimePhased',                           N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON  tgt.EntityName_EN = src.EntityName_EN
AND tgt.Column_EN     = src.Column_EN
WHEN NOT MATCHED THEN
    INSERT (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus, IsPublished)
    VALUES (src.EntityName_EN, src.EntityName_FR, src.ColumnPosition, src.Column_EN, src.Column_FR, src.SourceAlias, src.SourceExpression, src.MapStatus, 1)
WHEN MATCHED AND tgt.MapStatus NOT IN (N'MAPPED', N'NAVIGATION') THEN
    UPDATE SET
        EntityName_FR    = src.EntityName_FR,
        ColumnPosition   = src.ColumnPosition,
        Column_FR        = src.Column_FR,
        SourceAlias      = src.SourceAlias,
        SourceExpression = src.SourceExpression,
        MapStatus        = src.MapStatus,
        IsPublished      = 1,
        UpdatedOn        = sysdatetime(),
        UpdatedBy        = suser_sname();

SET @Msg = CONCAT(N'  Projects : ', @@ROWCOUNT, N' ligne(s).');
RAISERROR(@Msg, 0, 1) WITH NOWAIT;

/* ---- Tasks ---- */
RAISERROR(N'Phase C : EntityColumnPublication — Tasks...', 0, 1) WITH NOWAIT;
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'Tasks',N'Tâches',  1,N'ProjectUID',                         N'IdProjet',                                        N'src',     N'src.ProjectUID',                           N'MAPPED'),
    (N'Tasks',N'Tâches',  2,N'TaskUID',                            N'IdTâche',                                         N'src',     N'src.TaskUID',                              N'MAPPED'),
    (N'Tasks',N'Tâches',  3,N'TaskParentUID',                      N'IdTâcheParente',                                  N'src',     N'src.TaskParentUID',                        N'MAPPED'),
    (N'Tasks',N'Tâches',  4,N'ParentTaskName',                     N'NomTâcheParente',                                 N'jParent', N'jParent.TaskName',                         N'MAPPED'),
    (N'Tasks',N'Tâches',  5,N'ProjectName',                        N'NomProjet',                                       N'jProject',N'jProject.ProjectName',                    N'MAPPED'),
    (N'Tasks',N'Tâches',  6,N'FixedCostAssignmentUID',             N'IdAffectationCoûtFixeTâche',                      N'src',     N'src.FixedCostAssignmentUID',               N'MAPPED'),
    (N'Tasks',N'Tâches',  7,N'TaskActualCost',                     N'CoûtRéelTâche',                                   N'src',     N'src.TaskActualCost',                       N'MAPPED'),
    (N'Tasks',N'Tâches',  8,N'TaskActualDuration',                 N'DuréeRéelleTâche',                                N'src',     N'src.TaskActualDuration',                   N'MAPPED'),
    (N'Tasks',N'Tâches',  9,N'TaskActualFinishDate',               N'DateFinRéelleTâche',                              N'src',     N'src.TaskActualFinishDate',                 N'MAPPED'),
    (N'Tasks',N'Tâches', 10,N'TaskActualFixedCost',                N'CoûtFixeRéelTâche',                               N'src',     N'src.TaskActualFixedCost',                  N'MAPPED'),
    (N'Tasks',N'Tâches', 11,N'TaskActualOvertimeCost',             N'CoûtHeuresSupplémentairesRéelTâche',              N'src',     N'src.TaskActualOvertimeCost',               N'MAPPED'),
    (N'Tasks',N'Tâches', 12,N'TaskActualOvertimeWork',             N'TravailHeuresSupplémentairesRéellesTâche',        N'src',     N'src.TaskActualOvertimeWork',               N'MAPPED'),
    (N'Tasks',N'Tâches', 13,N'TaskActualRegularCost',              N'CoûtNormalRéelTâche',                             N'src',     N'src.TaskActualRegularCost',                N'MAPPED'),
    (N'Tasks',N'Tâches', 14,N'TaskActualRegularWork',              N'TravailNormalRéelTâche',                          N'src',     N'src.TaskActualRegularWork',                N'MAPPED'),
    (N'Tasks',N'Tâches', 15,N'TaskActualStartDate',                N'DateDébutRéelleTâche',                            N'src',     N'src.TaskActualStartDate',                  N'MAPPED'),
    (N'Tasks',N'Tâches', 16,N'TaskActualWork',                     N'TravailRéelTâche',                                N'src',     N'src.TaskActualWork',                       N'MAPPED'),
    (N'Tasks',N'Tâches', 17,N'TaskACWP',                           N'CRTETâche',                                       N'src',     N'src.TaskACWP',                             N'MAPPED'),
    (N'Tasks',N'Tâches', 18,N'TaskBCWP',                           N'VATâche',                                         N'src',     N'src.TaskBCWP',                             N'MAPPED'),
    (N'Tasks',N'Tâches', 19,N'TaskBCWS',                           N'VPTâche',                                         N'src',     N'src.TaskBCWS',                             N'MAPPED'),
    (N'Tasks',N'Tâches', 20,N'TaskBudgetCost',                     N'CoûtBudgétaireTâche',                             N'src',     N'src.TaskBudgetCost',                       N'MAPPED'),
    (N'Tasks',N'Tâches', 21,N'TaskBudgetWork',                     N'TravailBudgétaireTâche',                          N'src',     N'src.TaskBudgetWork',                       N'MAPPED'),
    (N'Tasks',N'Tâches', 22,N'TaskClientUniqueId',                 N'IDUniqueClientTâche',                             N'src',     N'src.TaskClientUniqueId',                   N'MAPPED'),
    (N'Tasks',N'Tâches', 23,N'TaskCost',                           N'CoûtTâche',                                       N'src',     N'src.TaskCost',                             N'MAPPED'),
    (N'Tasks',N'Tâches', 24,N'TaskCostVariance',                   N'VariationCoûtTâche',                              N'src',     N'src.TaskCostVariance',                     N'MAPPED'),
    (N'Tasks',N'Tâches', 25,N'TaskCPI',                            N'IPCTâche',                                        N'src',     N'src.TaskCPI',                              N'MAPPED'),
    (N'Tasks',N'Tâches', 26,N'TaskCreatedDate',                    N'DateCréationTâche',                               N'src',     N'src.TaskCreatedDate',                      N'MAPPED'),
    (N'Tasks',N'Tâches', 27,N'TaskCreatedRevisionCounter',         N'NombreRévisionsCrééesTâche',                      N'src',     N'src.TaskCreatedRevisionCounter',           N'MAPPED'),
    (N'Tasks',N'Tâches', 28,N'TaskCV',                             N'VCTâche',                                         N'src',     N'src.TaskCV',                               N'MAPPED'),
    (N'Tasks',N'Tâches', 29,N'TaskCVP',                            N'PVCTâche',                                        N'src',     N'src.TaskCVP',                              N'MAPPED'),
    (N'Tasks',N'Tâches', 30,N'TaskDeadline',                       N'ÉchéanceTâche',                                   N'src',     N'src.TaskDeadline',                         N'MAPPED'),
    (N'Tasks',N'Tâches', 31,N'TaskDeliverableFinishDate',          N'DateFinLivrableTâche',                            N'src',     N'src.TaskDeliverableFinishDate',            N'MAPPED'),
    (N'Tasks',N'Tâches', 32,N'TaskDeliverableStartDate',           N'DateDébutLivrableTâche',                          N'src',     N'src.TaskDeliverableStartDate',             N'MAPPED'),
    (N'Tasks',N'Tâches', 33,N'TaskDuration',                       N'DuréeTâche',                                      N'src',     N'src.TaskDuration',                         N'MAPPED'),
    (N'Tasks',N'Tâches', 34,N'TaskDurationIsEstimated',            N'DuréeEstiméeTâche',                               N'src',     N'src.TaskDurationIsEstimated',              N'MAPPED'),
    (N'Tasks',N'Tâches', 35,N'TaskDurationString',                 N'ChaîneDuréeTâche',                                N'src',     N'src.TaskDurationString',                   N'MAPPED'),
    (N'Tasks',N'Tâches', 36,N'TaskDurationVariance',               N'VariationDuréeTâche',                             N'src',     N'src.TaskDurationVariance',                 N'MAPPED'),
    (N'Tasks',N'Tâches', 37,N'TaskEAC',                            N'EAATâche',                                        N'src',     N'src.TaskEAC',                              N'MAPPED'),
    (N'Tasks',N'Tâches', 38,N'TaskEarlyFinish',                    N'FinAuPlusTôtTâche',                               N'src',     N'src.TaskEarlyFinish',                      N'MAPPED'),
    (N'Tasks',N'Tâches', 39,N'TaskEarlyStart',                     N'DébutAuPlusTôtTâche',                             N'src',     N'src.TaskEarlyStart',                       N'MAPPED'),
    (N'Tasks',N'Tâches', 40,N'TaskFinishDate',                     N'DateFinTâche',                                    N'src',     N'src.TaskFinishDate',                       N'MAPPED'),
    (N'Tasks',N'Tâches', 41,N'TaskFinishDateString',               N'ChaîneDateFinTâche',                              N'src',     N'src.TaskFinishDateString',                 N'MAPPED'),
    (N'Tasks',N'Tâches', 42,N'TaskFinishVariance',                 N'VariationFinTâche',                               N'src',     N'src.TaskFinishVariance',                   N'MAPPED'),
    (N'Tasks',N'Tâches', 43,N'TaskFixedCost',                      N'CoûtFixeTâche',                                   N'src',     N'src.TaskFixedCost',                        N'MAPPED'),
    (N'Tasks',N'Tâches', 44,N'TaskFreeSlack',                      N'MargeLibreTâche',                                 N'src',     N'src.TaskFreeSlack',                        N'MAPPED'),
    (N'Tasks',N'Tâches', 45,N'TaskHyperLinkAddress',               N'AdresseLienHypertexteTâche',                      N'src',     N'src.TaskHyperLinkAddress',                 N'MAPPED'),
    (N'Tasks',N'Tâches', 46,N'TaskHyperLinkFriendlyName',          N'LienHypertexteNomConvivialTâche',                 N'src',     N'src.TaskHyperLinkFriendlyName',            N'MAPPED'),
    (N'Tasks',N'Tâches', 47,N'TaskHyperLinkSubAddress',            N'SousAdresseLienHypertexteTâche',                  N'src',     N'src.TaskHyperLinkSubAddress',              N'MAPPED'),
    (N'Tasks',N'Tâches', 48,N'TaskIgnoresResourceCalendar',        N'TâcheIgnoreCalendrierRessources',                 N'src',     N'src.TaskIgnoresResourceCalendar',          N'MAPPED'),
    (N'Tasks',N'Tâches', 49,N'TaskIndex',                          N'IndexTâche',                                      N'src',     N'src.TaskIndex',                            N'MAPPED'),
    (N'Tasks',N'Tâches', 50,N'TaskIsActive',                       N'TâcheEstActive',                                  N'src',     N'src.TaskIsActive',                         N'MAPPED'),
    (N'Tasks',N'Tâches', 51,N'TaskIsCritical',                     N'TâcheEstCritique',                                N'src',     N'src.TaskIsCritical',                       N'MAPPED'),
    (N'Tasks',N'Tâches', 52,N'TaskIsEffortDriven',                 N'TâchePilotéeParEffort',                           N'src',     N'src.TaskIsEffortDriven',                   N'MAPPED'),
    (N'Tasks',N'Tâches', 53,N'TaskIsExternal',                     N'TâcheExterne',                                    N'src',     N'src.TaskIsExternal',                       N'MAPPED'),
    (N'Tasks',N'Tâches', 54,N'TaskIsManuallyScheduled',            N'TâchePlanifiéeManuellement',                      N'src',     N'src.TaskIsManuallyScheduled',              N'MAPPED'),
    (N'Tasks',N'Tâches', 55,N'TaskIsMarked',                       N'TâcheEstMarquée',                                 N'src',     N'src.TaskIsMarked',                         N'MAPPED'),
    (N'Tasks',N'Tâches', 56,N'TaskIsMilestone',                    N'TâcheEstUnJalon',                                 N'src',     N'src.TaskIsMilestone',                      N'MAPPED'),
    (N'Tasks',N'Tâches', 57,N'TaskIsOverallocated',                N'TâcheEstEnSurutilisation',                        N'src',     N'src.TaskIsOverallocated',                  N'MAPPED'),
    (N'Tasks',N'Tâches', 58,N'TaskIsProjectSummary',               N'TâcheRécapitulativeProjet',                       N'src',     N'src.TaskIsProjectSummary',                 N'MAPPED'),
    (N'Tasks',N'Tâches', 59,N'TaskIsRecurring',                    N'TâcheRécurrente',                                 N'src',     N'src.TaskIsRecurring',                      N'MAPPED'),
    (N'Tasks',N'Tâches', 60,N'TaskIsSummary',                      N'TâcheRécapitulative',                             N'src',     N'src.TaskIsSummary',                        N'MAPPED'),
    (N'Tasks',N'Tâches', 61,N'TaskLateFinish',                     N'FinAuPlusTardTâche',                              N'src',     N'src.TaskLateFinish',                       N'MAPPED'),
    (N'Tasks',N'Tâches', 62,N'TaskLateStart',                      N'DébutAuPlusTardTâche',                            N'src',     N'src.TaskLateStart',                        N'MAPPED'),
    (N'Tasks',N'Tâches', 63,N'TaskLevelingDelay',                  N'RetardNivellementTâche',                          N'src',     N'src.TaskLevelingDelay',                    N'MAPPED'),
    (N'Tasks',N'Tâches', 64,N'TaskModifiedDate',                   N'DateModificationTâche',                           N'src',     N'src.TaskModifiedDate',                     N'MAPPED'),
    (N'Tasks',N'Tâches', 65,N'TaskModifiedRevisionCounter',        N'NombreRévisionsModifiéesTâche',                   N'src',     N'src.TaskModifiedRevisionCounter',          N'MAPPED'),
    (N'Tasks',N'Tâches', 66,N'TaskName',                           N'NomTâche',                                        N'src',     N'src.TaskName',                             N'MAPPED'),
    (N'Tasks',N'Tâches', 67,N'TaskOutlineLevel',                   N'NiveauHiérarchiqueTâche',                         N'src',     N'src.TaskOutlineLevel',                     N'MAPPED'),
    (N'Tasks',N'Tâches', 68,N'TaskOutlineNumber',                  N'NuméroHiérarchiqueTâche',                         N'src',     N'src.TaskOutlineNumber',                    N'MAPPED'),
    (N'Tasks',N'Tâches', 69,N'TaskOvertimeCost',                   N'CoûtHeuresSupplémentairesTâche',                  N'src',     N'src.TaskOvertimeCost',                     N'MAPPED'),
    (N'Tasks',N'Tâches', 70,N'TaskOvertimeWork',                   N'TravailHeuresSupplémentairesTâche',               N'src',     N'src.TaskOvertimeWork',                     N'MAPPED'),
    (N'Tasks',N'Tâches', 71,N'TaskPercentCompleted',               N'PourcentageAchevéTâche',                          N'src',     N'src.TaskPercentCompleted',                 N'MAPPED'),
    (N'Tasks',N'Tâches', 72,N'TaskPercentWorkCompleted',           N'PourcentageTravailAchevéTâche',                   N'src',     N'src.TaskPercentWorkCompleted',             N'MAPPED'),
    (N'Tasks',N'Tâches', 73,N'TaskPhysicalPercentCompleted',       N'PourcentagePhysiqueAchevéTâche',                  N'src',     N'src.TaskPhysicalPercentCompleted',         N'MAPPED'),
    (N'Tasks',N'Tâches', 74,N'TaskPriority',                       N'PrioritéTâche',                                   N'src',     N'src.TaskPriority',                         N'MAPPED'),
    (N'Tasks',N'Tâches', 75,N'TaskRegularCost',                    N'CoûtNormalTâche',                                 N'src',     N'src.TaskRegularCost',                      N'MAPPED'),
    (N'Tasks',N'Tâches', 76,N'TaskRegularWork',                    N'TravailNormalTâche',                              N'src',     N'src.TaskRegularWork',                      N'MAPPED'),
    (N'Tasks',N'Tâches', 77,N'TaskRemainingCost',                  N'CoûtRestantTâche',                                N'src',     N'src.TaskRemainingCost',                    N'MAPPED'),
    (N'Tasks',N'Tâches', 78,N'TaskRemainingDuration',              N'DuréeRestanteTâche',                              N'src',     N'src.TaskRemainingDuration',                N'MAPPED'),
    (N'Tasks',N'Tâches', 79,N'TaskRemainingOvertimeCost',          N'CoûtHeuresSupplémentairesRestantesTâche',         N'src',     N'src.TaskRemainingOvertimeCost',            N'MAPPED'),
    (N'Tasks',N'Tâches', 80,N'TaskRemainingOvertimeWork',          N'TravailHeuresSupplémentairesRestantesTâche',      N'src',     N'src.TaskRemainingOvertimeWork',            N'MAPPED'),
    (N'Tasks',N'Tâches', 81,N'TaskRemainingRegularCost',           N'CoûtNormalRestantTâche',                          N'src',     N'src.TaskRemainingRegularCost',             N'MAPPED'),
    (N'Tasks',N'Tâches', 82,N'TaskRemainingRegularWork',           N'TravailNormalRestantTâche',                       N'src',     N'src.TaskRemainingRegularWork',             N'MAPPED'),
    (N'Tasks',N'Tâches', 83,N'TaskRemainingWork',                  N'TravailRestantTâche',                             N'src',     N'src.TaskRemainingWork',                    N'MAPPED'),
    (N'Tasks',N'Tâches', 84,N'TaskResourcePlanWork',               N'TravailPlanRessourcesTâche',                      N'src',     N'src.TaskResourcePlanWork',                 N'MAPPED'),
    (N'Tasks',N'Tâches', 85,N'TaskSPI',                            N'SPITâche',                                        N'src',     N'src.TaskSPI',                              N'MAPPED'),
    (N'Tasks',N'Tâches', 86,N'TaskStartDate',                      N'DateDébutTâche',                                  N'src',     N'src.TaskStartDate',                        N'MAPPED'),
    (N'Tasks',N'Tâches', 87,N'TaskStartDateString',                N'ChaîneDateDébutTâche',                            N'src',     N'src.TaskStartDateString',                  N'MAPPED'),
    (N'Tasks',N'Tâches', 88,N'TaskStartVariance',                  N'VariationDébutTâche',                             N'src',     N'src.TaskStartVariance',                    N'MAPPED'),
    (N'Tasks',N'Tâches', 89,N'TaskStatusManagerUID',               N'UIDGestionnaireÉtatTâche',                        N'src',     N'src.TaskStatusManagerUID',                 N'MAPPED'),
    (N'Tasks',N'Tâches', 90,N'TaskSV',                             N'VSTâche',                                         N'src',     N'src.TaskSV',                               N'MAPPED'),
    (N'Tasks',N'Tâches', 91,N'TaskSVP',                            N'PVPTâche',                                        N'src',     N'src.TaskSVP',                              N'MAPPED'),
    (N'Tasks',N'Tâches', 92,N'TaskTCPI',                           N'TCPITâche',                                       N'src',     N'src.TaskTCPI',                             N'MAPPED'),
    (N'Tasks',N'Tâches', 93,N'TaskTotalSlack',                     N'MargeTotaleTâche',                                N'src',     N'src.TaskTotalSlack',                       N'MAPPED'),
    (N'Tasks',N'Tâches', 94,N'TaskVAC',                            N'VAATâche',                                        N'src',     N'src.TaskVAC',                              N'MAPPED'),
    (N'Tasks',N'Tâches', 95,N'TaskWBS',                            N'WBSTâche',                                        N'src',     N'src.TaskWBS',                              N'MAPPED'),
    (N'Tasks',N'Tâches', 96,N'TaskWork',                           N'TravailTâche',                                    N'src',     N'src.TaskWork',                             N'MAPPED'),
    (N'Tasks',N'Tâches', 97,N'TaskWorkVariance',                   N'VariationTravailTâche',                           N'src',     N'src.TaskWorkVariance',                     N'MAPPED'),
    /* NAVIGATION — liens OData inter-entités, pas de source PSSE */
    (N'Tasks',N'Tâches', 98,N'Assignments',                        N'Affectations',                                    NULL, NULL, N'NAVIGATION'),
    (N'Tasks',N'Tâches', 99,N'AssignmentBaselines',                N'PlanningsDeRéférenceAffectations',                NULL, NULL, N'NAVIGATION'),
    (N'Tasks',N'Tâches',100,N'AssignmentBaselineTimephasedDataSet',N'DonnéesChronologiquesRéférenceAffectations',      NULL, NULL, N'NAVIGATION'),
    (N'Tasks',N'Tâches',101,N'TaskBaselines',                      N'PlanningsDeRéférence',                            NULL, NULL, N'NAVIGATION'),
    (N'Tasks',N'Tâches',102,N'TaskBaselineTimephasedDataSet',      N'JeuDonnéesChronologiquesPlanningsDeRéférence',    NULL, NULL, N'NAVIGATION'),
    (N'Tasks',N'Tâches',103,N'Issues',                             N'Problèmes',                                       NULL, NULL, N'NAVIGATION'),
    (N'Tasks',N'Tâches',104,N'Project',                            N'Projet',                                          NULL, NULL, N'NAVIGATION'),
    (N'Tasks',N'Tâches',105,N'Risks',                              N'Risques',                                         NULL, NULL, N'NAVIGATION'),
    (N'Tasks',N'Tâches',106,N'TaskTimephasedDataSet',              N'InfosChronologiques',                             NULL, NULL, N'NAVIGATION')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON  tgt.EntityName_EN = src.EntityName_EN AND tgt.Column_EN = src.Column_EN
WHEN NOT MATCHED THEN
    INSERT (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus, IsPublished)
    VALUES (src.EntityName_EN, src.EntityName_FR, src.ColumnPosition, src.Column_EN, src.Column_FR, src.SourceAlias, src.SourceExpression, src.MapStatus, 1)
WHEN MATCHED AND tgt.MapStatus NOT IN (N'MAPPED', N'NAVIGATION') THEN
    UPDATE SET EntityName_FR=src.EntityName_FR, ColumnPosition=src.ColumnPosition, Column_FR=src.Column_FR,
               SourceAlias=src.SourceAlias, SourceExpression=src.SourceExpression, MapStatus=src.MapStatus,
               IsPublished=1, UpdatedOn=sysdatetime(), UpdatedBy=suser_sname();
SET @Msg = CONCAT(N'  Tasks : ', @@ROWCOUNT, N' ligne(s).');
RAISERROR(@Msg, 0, 1) WITH NOWAIT;

/* ---- Assignments ---- */
RAISERROR(N'Phase C : EntityColumnPublication — Assignments...', 0, 1) WITH NOWAIT;
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'Assignments',N'Affectations',  1,N'ProjectUID',                         N'IdProjet',                                        N'src',  N'src.ProjectUID',                          N'MAPPED'),
    (N'Assignments',N'Affectations',  2,N'AssignmentUID',                       N'IdAffectation',                                   N'src',  N'src.AssignmentUID',                       N'MAPPED'),
    (N'Assignments',N'Affectations',  3,N'AssignmentActualCost',                N'CoûtRéelAffectation',                             N'src',  N'src.AssignmentActualCost',                N'MAPPED'),
    (N'Assignments',N'Affectations',  4,N'AssignmentActualFinishDate',          N'AffectationDateFinRéelle',                        N'src',  N'src.AssignmentActualFinishDate',          N'MAPPED'),
    (N'Assignments',N'Affectations',  5,N'AssignmentActualOvertimeCost',        N'CoûtHeuresSupplémentairesRéellesAffectation',     N'src',  N'src.AssignmentActualOvertimeCost',        N'MAPPED'),
    (N'Assignments',N'Affectations',  6,N'AssignmentActualOvertimeWork',        N'HeuresSupplémentairesRéellesAffectation',         N'src',  N'src.AssignmentActualOvertimeWork',        N'MAPPED'),
    (N'Assignments',N'Affectations',  7,N'AssignmentActualRegularCost',         N'CoûtNormalRéelAffectation',                       N'src',  N'src.AssignmentActualRegularCost',         N'MAPPED'),
    (N'Assignments',N'Affectations',  8,N'AssignmentActualRegularWork',         N'TravailNormalRéelAffectation',                    N'src',  N'src.AssignmentActualRegularWork',         N'MAPPED'),
    (N'Assignments',N'Affectations',  9,N'AssignmentActualStartDate',           N'AffectationDateDébutRéelle',                      N'src',  N'src.AssignmentActualStartDate',           N'MAPPED'),
    (N'Assignments',N'Affectations', 10,N'AssignmentActualWork',                N'AffectationTravailRéel',                          N'src',  N'src.AssignmentActualWork',                N'MAPPED'),
    (N'Assignments',N'Affectations', 11,N'AssignmentACWP',                      N'CRTEAffectation',                                 N'src',  N'src.AssignmentACWP',                      N'MAPPED'),
    (N'Assignments',N'Affectations', 12,N'AssignmentAllUpdatesApplied',         N'AssignmentAllUpdatesApplied',                     N'AAU',  N'AAU.AssignmentAllUpdatesApplied',         N'MAPPED'),
    (N'Assignments',N'Affectations', 13,N'AssignmentBCWP',                      N'VAAffectation',                                   N'src',  N'src.AssignmentBCWP',                      N'MAPPED'),
    (N'Assignments',N'Affectations', 14,N'AssignmentBCWS',                      N'VPAffectation',                                   N'src',  N'src.AssignmentBCWS',                      N'MAPPED'),
    (N'Assignments',N'Affectations', 15,N'AssignmentBookingDescription',        N'DescriptionRéservationAffectation',               N'AB',   N'AB.AssignmentBookingDescription',         N'MAPPED'),
    (N'Assignments',N'Affectations', 16,N'AssignmentBookingID',                 N'IdRéservationAffectation',                        N'src',  N'src.AssignmentBookingID',                 N'MAPPED'),
    (N'Assignments',N'Affectations', 17,N'AssignmentBookingName',               N'NomRéservationAffectation',                       N'AB',   N'AB.AssignmentBookingName',                N'MAPPED'),
    (N'Assignments',N'Affectations', 18,N'AssignmentBudgetCost',                N'CoûtBudgétaireAffectation',                       N'src',  N'src.AssignmentBudgetCost',                N'MAPPED'),
    (N'Assignments',N'Affectations', 19,N'AssignmentBudgetMaterialWork',        N'TravailMatériauBudgétaireAffectation',            N'src',  N'src.AssignmentBudgetMaterialWork',        N'MAPPED'),
    (N'Assignments',N'Affectations', 20,N'AssignmentBudgetWork',                N'TravailBudgétaireAffectation',                    N'src',  N'src.AssignmentBudgetWork',                N'MAPPED'),
    (N'Assignments',N'Affectations', 21,N'AssignmentCost',                      N'AffectationCoût',                                 N'src',  N'src.AssignmentCost',                      N'MAPPED'),
    (N'Assignments',N'Affectations', 22,N'AssignmentCostVariance',              N'VarianceCoûtAffectation',                         N'src',  N'src.AssignmentCostVariance',              N'MAPPED'),
    (N'Assignments',N'Affectations', 23,N'AssignmentCreatedDate',               N'DateCréationAffectation',                         N'src',  N'src.AssignmentCreatedDate',               N'MAPPED'),
    (N'Assignments',N'Affectations', 24,N'AssignmentCreatedRevisionCounter',    N'CompteurRévisionsCrééAffectation',                N'src',  N'src.AssignmentCreatedRevisionCounter',    N'MAPPED'),
    (N'Assignments',N'Affectations', 25,N'AssignmentCV',                        N'VCAffectation',                                   N'src',  N'src.AssignmentCV',                        N'MAPPED'),
    (N'Assignments',N'Affectations', 26,N'AssignmentDelay',                     N'RetardAffectation',                               N'src',  N'src.AssignmentDelay',                     N'MAPPED'),
    (N'Assignments',N'Affectations', 27,N'AssignmentFinishDate',                N'AffectationDateFin',                              N'src',  N'src.AssignmentFinishDate',                N'MAPPED'),
    (N'Assignments',N'Affectations', 28,N'AssignmentFinishVariance',            N'VarianceFinAffectation',                          N'src',  N'src.AssignmentFinishVariance',            N'MAPPED'),
    (N'Assignments',N'Affectations', 29,N'AssignmentIsOverallocated',           N'AffectationEstSurutilisée',                       N'src',  N'src.AssignmentIsOverallocated',           N'MAPPED'),
    (N'Assignments',N'Affectations', 30,N'AssignmentIsPublished',               N'AffectationEstPubliée',                           N'src',  N'src.AssignmentIsPublished',               N'MAPPED'),
    (N'Assignments',N'Affectations', 31,N'AssignmentMaterialActualWork',        N'TravailRéelMatériauAffectation',                  N'src',  N'src.AssignmentMaterialActualWork',        N'MAPPED'),
    (N'Assignments',N'Affectations', 32,N'AssignmentMaterialWork',              N'TravailMatériauAffectation',                      N'src',  N'src.AssignmentMaterialWork',              N'MAPPED'),
    (N'Assignments',N'Affectations', 33,N'AssignmentModifiedDate',              N'AffectationDateModification',                     N'src',  N'src.AssignmentModifiedDate',              N'MAPPED'),
    (N'Assignments',N'Affectations', 34,N'AssignmentModifiedRevisionCounter',   N'CompteurRévisionsModifiéAffectation',             N'src',  N'src.AssignmentModifiedRevisionCounter',   N'MAPPED'),
    (N'Assignments',N'Affectations', 35,N'AssignmentOvertimeCost',              N'CoûtHeuresSupplémentairesAffectation',            N'src',  N'src.AssignmentOvertimeCost',              N'MAPPED'),
    (N'Assignments',N'Affectations', 36,N'AssignmentOvertimeWork',              N'HeuresSupplémentairesAffectation',                N'src',  N'src.AssignmentOvertimeWork',              N'MAPPED'),
    (N'Assignments',N'Affectations', 37,N'AssignmentPeakUnits',                 N'UnitésPicAffectation',                            N'src',  N'src.AssignmentPeakUnits',                 N'MAPPED'),
    (N'Assignments',N'Affectations', 38,N'AssignmentPercentWorkCompleted',      N'AffectationPourcentageTravailEffectué',           N'src',  N'src.AssignmentPercentWorkCompleted',      N'MAPPED'),
    (N'Assignments',N'Affectations', 39,N'AssignmentRegularCost',               N'CoûtNormalAffectation',                           N'src',  N'src.AssignmentRegularCost',               N'MAPPED'),
    (N'Assignments',N'Affectations', 40,N'AssignmentRegularWork',               N'TravailNormalAffectation',                        N'src',  N'src.AssignmentRegularWork',               N'MAPPED'),
    (N'Assignments',N'Affectations', 41,N'AssignmentRemainingCost',             N'AffectationCoûtRestant',                          N'src',  N'src.AssignmentRemainingCost',             N'MAPPED'),
    (N'Assignments',N'Affectations', 42,N'AssignmentRemainingOvertimeCost',     N'CoûtHeuresSupplémentairesRestantes',              N'src',  N'src.AssignmentRemainingOvertimeCost',     N'MAPPED'),
    (N'Assignments',N'Affectations', 43,N'AssignmentRemainingOvertimeWork',     N'HeuresSupplémentairesRestantesAffectation',       N'src',  N'src.AssignmentRemainingOvertimeWork',     N'MAPPED'),
    (N'Assignments',N'Affectations', 44,N'AssignmentRemainingRegularCost',      N'CoûtNormalRestantAffectation',                    N'src',  N'src.AssignmentRemainingRegularCost',      N'MAPPED'),
    (N'Assignments',N'Affectations', 45,N'AssignmentRemainingRegularWork',      N'TravailNormalRestantAffectation',                 N'src',  N'src.AssignmentRemainingRegularWork',      N'MAPPED'),
    (N'Assignments',N'Affectations', 46,N'AssignmentRemainingWork',             N'AffectationTravailRestant',                       N'src',  N'src.AssignmentRemainingWork',             N'MAPPED'),
    (N'Assignments',N'Affectations', 47,N'AssignmentResourcePlanWork',          N'AffectationRessourcePlanTravail',                 N'src',  N'src.AssignmentResourcePlanWork',          N'MAPPED'),
    (N'Assignments',N'Affectations', 48,N'AssignmentResourceType',              N'AffectationTypeRessource',                        N'src',  N'src.AssignmentResourceType',              N'MAPPED'),
    (N'Assignments',N'Affectations', 49,N'AssignmentStartDate',                 N'AffectationDateDébut',                            N'src',  N'src.AssignmentStartDate',                 N'MAPPED'),
    (N'Assignments',N'Affectations', 50,N'AssignmentStartVariance',             N'VarianceDébutAffectation',                        N'src',  N'src.AssignmentStartVariance',             N'MAPPED'),
    (N'Assignments',N'Affectations', 51,N'AssignmentSV',                        N'EDAffectation',                                   N'src',  N'src.AssignmentSV',                        N'MAPPED'),
    (N'Assignments',N'Affectations', 52,N'AssignmentType',                      N'AffectationType',                                 N'src',  N'src.AssignmentType',                      N'MAPPED'),
    (N'Assignments',N'Affectations', 53,N'AssignmentUpdatesAppliedDate',        N'AssignmentUpdatesAppliedDate',                    N'AAU',  N'AAU.AssignmentUpdatesAppliedDate',        N'MAPPED'),
    (N'Assignments',N'Affectations', 54,N'AssignmentVAC',                       N'VAAAffectation',                                  N'src',  N'src.AssignmentVAC',                       N'MAPPED'),
    (N'Assignments',N'Affectations', 55,N'AssignmentWork',                      N'AffectationTravail',                              N'src',  N'src.AssignmentWork',                      N'MAPPED'),
    (N'Assignments',N'Affectations', 56,N'AssignmentWorkVariance',              N'VarianceTravailAffectation',                      N'src',  N'src.AssignmentWorkVariance',              N'MAPPED'),
    (N'Assignments',N'Affectations', 57,N'IsPublic',                            N'EstPublic',                                       N'src',  N'src.IsPublic',                            N'MAPPED'),
    (N'Assignments',N'Affectations', 58,N'ProjectName',                         N'NomProjet',                                       N'PU',   N'PU.ProjectName',                          N'MAPPED'),
    (N'Assignments',N'Affectations', 59,N'ResourceUID',                         N'IdRessource',                                     N'src',  N'src.ResourceUID',                         N'MAPPED'),
    (N'Assignments',N'Affectations', 60,N'ResourceName',                        N'NomRessource',                                    N'RU',   N'RU.ResourceName',                         N'MAPPED'),
    (N'Assignments',N'Affectations', 61,N'TaskUID',                             N'IdTâche',                                         N'src',  N'src.TaskUID',                             N'MAPPED'),
    (N'Assignments',N'Affectations', 62,N'TaskIsActive',                        N'TâcheEstActive',                                  N'src',  N'src.TaskIsActive',                        N'MAPPED'),
    (N'Assignments',N'Affectations', 63,N'TaskName',                            N'NomTâche',                                        N'TU',   N'TU.TaskName',                             N'MAPPED'),
    (N'Assignments',N'Affectations', 64,N'TimesheetClassUID',                   N'IdClasseFeuilleDeTemps',                          N'src',  N'src.TimesheetClassUID',                   N'MAPPED'),
    (N'Assignments',N'Affectations', 65,N'TypeDescription',                     N'DescriptionType',                                 N'AT',   N'AT.TypeDescription',                      N'MAPPED'),
    (N'Assignments',N'Affectations', 66,N'TypeName',                            N'NomType',                                         N'AT',   N'AT.TypeName',                             N'MAPPED'),
    /* NAVIGATION */
    (N'Assignments',N'Affectations', 67,N'AssignmentBaselines',                 N'DébutRéférenceFinRéférence',                      NULL, NULL, N'NAVIGATION'),
    (N'Assignments',N'Affectations', 68,N'Project',                             N'Projet',                                          NULL, NULL, N'NAVIGATION'),
    (N'Assignments',N'Affectations', 69,N'Resource',                            N'Ressource',                                       NULL, NULL, N'NAVIGATION'),
    (N'Assignments',N'Affectations', 70,N'Task',                                N'Tâche',                                           NULL, NULL, N'NAVIGATION'),
    (N'Assignments',N'Affectations', 71,N'AssignmentTimephasedDataSet',         N'DonnéesChronologiques',                           NULL, NULL, N'NAVIGATION')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON  tgt.EntityName_EN = src.EntityName_EN AND tgt.Column_EN = src.Column_EN
WHEN NOT MATCHED THEN
    INSERT (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus, IsPublished)
    VALUES (src.EntityName_EN, src.EntityName_FR, src.ColumnPosition, src.Column_EN, src.Column_FR, src.SourceAlias, src.SourceExpression, src.MapStatus, 1)
WHEN MATCHED AND tgt.MapStatus NOT IN (N'MAPPED', N'NAVIGATION') THEN
    UPDATE SET EntityName_FR=src.EntityName_FR, ColumnPosition=src.ColumnPosition, Column_FR=src.Column_FR,
               SourceAlias=src.SourceAlias, SourceExpression=src.SourceExpression, MapStatus=src.MapStatus,
               IsPublished=1, UpdatedOn=sysdatetime(), UpdatedBy=suser_sname();
SET @Msg = CONCAT(N'  Assignments : ', @@ROWCOUNT, N' ligne(s).');
RAISERROR(@Msg, 0, 1) WITH NOWAIT;

/* ---- Resources ---- */
RAISERROR(N'Phase C : EntityColumnPublication — Resources...', 0, 1) WITH NOWAIT;
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'Resources',N'Ressources',  1,N'ResourceUID',                    N'IdRessource',                             N'src', N'src.ResourceUID',                    N'MAPPED'),
    (N'Resources',N'Ressources',  2,N'ResourceBaseCalendar',           N'CalendrierBaseRessource',                 N'src', N'src.ResourceBaseCalendar',           N'MAPPED'),
    (N'Resources',N'Ressources',  3,N'ResourceBookingType',            N'TypeRéservationRessource',                N'src', N'src.ResourceBookingType',            N'MAPPED'),
    (N'Resources',N'Ressources',  4,N'ResourceCanLevel',               N'RessourceÀniveler',                       N'src', N'src.ResourceCanLevel',               N'MAPPED'),
    (N'Resources',N'Ressources',  5,N'ResourceCode',                   N'CodeRessource',                           N'src', N'src.ResourceCode',                   N'MAPPED'),
    (N'Resources',N'Ressources',  6,N'ResourceCostCenter',             N'CentreCoûtRessource',                     N'src', N'src.ResourceCostCenter',             N'MAPPED'),
    (N'Resources',N'Ressources',  7,N'ResourceCostPerUse',             N'CoûtRessourceParUtilisation',             N'src', N'src.ResourceCostPerUse',             N'MAPPED'),
    (N'Resources',N'Ressources',  8,N'ResourceCreatedDate',            N'DateCréationRessource',                   N'src', N'src.ResourceCreatedDate',            N'MAPPED'),
    (N'Resources',N'Ressources',  9,N'ResourceEarliestAvailableFrom',  N'RessourceDisponibleAuPlusTôtDu',          N'src', N'src.ResourceEarliestAvailableFrom',  N'MAPPED'),
    (N'Resources',N'Ressources', 10,N'ResourceEmailAddress',           N'AdresseMessagerieRessource',              N'src', N'src.ResourceEmailAddress',           N'MAPPED'),
    (N'Resources',N'Ressources', 11,N'ResourceGroup',                  N'GroupeRessources',                        N'src', N'src.ResourceGroup',                  N'MAPPED'),
    (N'Resources',N'Ressources', 12,N'ResourceHyperlink',              N'LienHypertexteRessource',                 N'src', N'src.ResourceHyperlink',              N'MAPPED'),
    (N'Resources',N'Ressources', 13,N'ResourceHyperlinkHref',          N'RéfÉlevéeLienHypertexteRessource',        N'src', N'src.ResourceHyperlinkHref',          N'MAPPED'),
    (N'Resources',N'Ressources', 14,N'ResourceInitials',               N'InitialesRessource',                      N'src', N'src.ResourceInitials',               N'MAPPED'),
    (N'Resources',N'Ressources', 15,N'ResourceIsActive',               N'RessourceEstActive',                      N'src', N'src.ResourceIsActive',               N'MAPPED'),
    (N'Resources',N'Ressources', 16,N'ResourceIsGeneric',              N'RessourceEstGénérique',                   N'src', N'src.ResourceIsGeneric',              N'MAPPED'),
    (N'Resources',N'Ressources', 17,N'ResourceIsTeam',                 N'RessourceÉquipe',                         N'src', N'src.ResourceIsTeam',                 N'MAPPED'),
    (N'Resources',N'Ressources', 18,N'ResourceLatestAvailableTo',      N'RessourceDisponibleAuPlusTardAu',         N'src', N'src.ResourceLatestAvailableTo',      N'MAPPED'),
    (N'Resources',N'Ressources', 19,N'ResourceMaterialLabel',          N'ÉtiquetteMatériauRessource',              N'src', N'src.ResourceMaterialLabel',          N'MAPPED'),
    (N'Resources',N'Ressources', 20,N'ResourceMaxUnits',               N'UnitésMaxRessource',                      N'src', N'src.ResourceMaxUnits',               N'MAPPED'),
    (N'Resources',N'Ressources', 21,N'ResourceModifiedDate',           N'DateModificationRessource',               N'src', N'src.ResourceModifiedDate',           N'MAPPED'),
    (N'Resources',N'Ressources', 22,N'ResourceName',                   N'NomRessource',                            N'src', N'src.ResourceName',                   N'MAPPED'),
    (N'Resources',N'Ressources', 23,N'ResourceNTAccount',              N'CompteNTRessource',                       N'src', N'src.ResourceNTAccount',              N'MAPPED'),
    (N'Resources',N'Ressources', 24,N'ResourceOvertimeRate',           N'TauxHeuresSupplémentairesRessource',      N'src', N'src.ResourceOvertimeRate',           N'MAPPED'),
    (N'Resources',N'Ressources', 25,N'ResourceStandardRate',           N'TauxStandardRessource',                   N'src', N'src.ResourceStandardRate',           N'MAPPED'),
    (N'Resources',N'Ressources', 26,N'ResourceStatusUID',              N'IdÉtatRessource',                         N'src', N'src.ResourceStatusUID',              N'MAPPED'),
    (N'Resources',N'Ressources', 27,N'ResourceTimesheetManagerUID',    N'IdGestionFeuilleDeTempsRessource',        N'src', N'src.ResourceTimesheetManagerUID',    N'MAPPED'),
    (N'Resources',N'Ressources', 28,N'ResourceType',                   N'TypeRessource',                           N'src', N'src.ResourceType',                   N'MAPPED'),
    (N'Resources',N'Ressources', 29,N'ResourceWorkgroup',              N'GroupeTravailRessource',                  N'src', N'src.ResourceWorkgroup',              N'MAPPED'),
    (N'Resources',N'Ressources', 30,N'ResourceStatusName',             N'NomÉtatRessource',                        N'RS',  N'RS.ResourceStatusName',              N'MAPPED'),
    (N'Resources',N'Ressources', 31,N'TypeDescription',                N'DescriptionType',                         N'RT',  N'RT.TypeDescription',                 N'MAPPED'),
    (N'Resources',N'Ressources', 32,N'TypeName',                       N'NomType',                                 N'RT',  N'RT.TypeName',                        N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON  tgt.EntityName_EN = src.EntityName_EN AND tgt.Column_EN = src.Column_EN
WHEN NOT MATCHED THEN
    INSERT (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus, IsPublished)
    VALUES (src.EntityName_EN, src.EntityName_FR, src.ColumnPosition, src.Column_EN, src.Column_FR, src.SourceAlias, src.SourceExpression, src.MapStatus, 1)
WHEN MATCHED AND tgt.MapStatus NOT IN (N'MAPPED', N'NAVIGATION') THEN
    UPDATE SET EntityName_FR=src.EntityName_FR, ColumnPosition=src.ColumnPosition, Column_FR=src.Column_FR,
               SourceAlias=src.SourceAlias, SourceExpression=src.SourceExpression, MapStatus=src.MapStatus,
               IsPublished=1, UpdatedOn=sysdatetime(), UpdatedBy=suser_sname();
SET @Msg = CONCAT(N'  Resources : ', @@ROWCOUNT, N' ligne(s).');
RAISERROR(@Msg, 0, 1) WITH NOWAIT;

/* ---- TimeSet ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'TimeSet',N'CalendrierTemps',  1,N'TimeByDay',          N'HeureParJour',              N'src', N'src.TimeByDay',          N'MAPPED'),
    (N'TimeSet',N'CalendrierTemps',  2,N'TimeDayOfTheMonth',  N'HeureJourDuMois',           N'src', N'src.TimeDayOfTheMonth',  N'MAPPED'),
    (N'TimeSet',N'CalendrierTemps',  3,N'TimeDayOfTheWeek',   N'HeureJourDeLaSemaine',      N'src', N'src.TimeDayOfTheWeek',   N'MAPPED'),
    (N'TimeSet',N'CalendrierTemps',  4,N'TimeMonthOfTheYear', N'HeureMoisDeLAnnée',         N'src', N'src.TimeMonthOfTheYear', N'MAPPED'),
    (N'TimeSet',N'CalendrierTemps',  5,N'TimeQuarter',        N'TempsTrimestre',             N'src', N'src.TimeQuarter',        N'MAPPED'),
    (N'TimeSet',N'CalendrierTemps',  6,N'TimeWeekOfTheYear',  N'HeureSemaineDeLAnnée',      N'src', N'src.TimeWeekOfTheYear',  N'MAPPED'),
    (N'TimeSet',N'CalendrierTemps',  7,N'FiscalPeriodUID',    N'IDPériodeFiscale',           N'src', N'src.FiscalPeriodUID',    N'MAPPED'),
    (N'TimeSet',N'CalendrierTemps',  8,N'FiscalPeriodName',   N'NomPériodeFiscale',          N'src', N'src.FiscalPeriodName',   N'MAPPED'),
    (N'TimeSet',N'CalendrierTemps',  9,N'FiscalQuarter',      N'TrimestreFiscal',            N'src', N'src.FiscalQuarter',      N'MAPPED'),
    (N'TimeSet',N'CalendrierTemps', 10,N'FiscalYear',         N'AnnéePériodeFiscale',        N'src', N'src.FiscalYear',         N'MAPPED'),
    (N'TimeSet',N'CalendrierTemps', 11,N'FiscalPeriodStart',  N'DébutPériodeFiscale',        N'FP',  N'FP.FiscalPeriodStart',   N'MAPPED'),
    (N'TimeSet',N'CalendrierTemps', 12,N'FiscalPeriodModifiedDate', N'DateModificationPériodeFiscale', N'FP', N'FP.ModifiedDate',N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

/* ---- FiscalPeriods ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'FiscalPeriods',N'PériodesFiscales',  1,N'FiscalPeriodUID',     N'IDPériodeFiscale',               N'src', N'src.FiscalPeriodUID',     N'MAPPED'),
    (N'FiscalPeriods',N'PériodesFiscales',  2,N'FiscalPeriodName',    N'NomPériodeFiscale',              N'src', N'src.FiscalPeriodName',    N'MAPPED'),
    (N'FiscalPeriods',N'PériodesFiscales',  3,N'FiscalPeriodStart',   N'DébutPériodeFiscale',            N'src', N'src.FiscalPeriodStart',   N'MAPPED'),
    (N'FiscalPeriods',N'PériodesFiscales',  4,N'FiscalPeriodFinish',  N'FinPériodeFiscale',              N'src', N'src.FiscalPeriodFinish',  N'MAPPED'),
    (N'FiscalPeriods',N'PériodesFiscales',  5,N'FiscalPeriodQuarter', N'PériodeFiscaleTrimestre',        N'src', N'src.FiscalPeriodQuarter', N'MAPPED'),
    (N'FiscalPeriods',N'PériodesFiscales',  6,N'FiscalPeriodYear',    N'AnnéePériodeFiscale',            N'src', N'src.FiscalPeriodYear',    N'MAPPED'),
    (N'FiscalPeriods',N'PériodesFiscales',  7,N'CreatedDate',         N'DateCréation',                   N'src', N'src.CreatedDate',         N'MAPPED'),
    (N'FiscalPeriods',N'PériodesFiscales',  8,N'ModifiedDate',        N'DateModificationPériodeFiscale', N'src', N'src.ModifiedDate',        N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

/* ---- Timesheet ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'Timesheet',N'FeuilleDeTemps',  1,N'TimesheetUID',        N'TimesheetId',         N'src', N'src.TimesheetUID',        N'MAPPED'),
    (N'Timesheet',N'FeuilleDeTemps',  2,N'Comment',             N'Comment',             N'src', N'src.Comment',             N'MAPPED'),
    (N'Timesheet',N'FeuilleDeTemps',  3,N'ModifiedDate',        N'ModifiedDate',        N'src', N'src.ModifiedDate',        N'MAPPED'),
    (N'Timesheet',N'FeuilleDeTemps',  4,N'PeriodUID',           N'PeriodId',            N'src', N'src.PeriodUID',           N'MAPPED'),
    (N'Timesheet',N'FeuilleDeTemps',  5,N'TimesheetName',       N'TimesheetName',       N'src', N'src.TimesheetName',       N'MAPPED'),
    (N'Timesheet',N'FeuilleDeTemps',  6,N'OwnerResourceNameUID',N'TimesheetOwnerId',    N'src', N'src.OwnerResourceNameUID',N'MAPPED'),
    (N'Timesheet',N'FeuilleDeTemps',  7,N'TimesheetStatusID',   N'TimesheetStatusId',   N'src', N'src.TimesheetStatusID',   N'MAPPED'),
    (N'Timesheet',N'FeuilleDeTemps',  8,N'EndDate',             N'EndDate',             N'TSP', N'TSP.EndDate',             N'MAPPED'),
    (N'Timesheet',N'FeuilleDeTemps',  9,N'PeriodName',          N'PeriodName',          N'TSP', N'TSP.PeriodName',          N'MAPPED'),
    (N'Timesheet',N'FeuilleDeTemps', 10,N'PeriodStatusID',      N'PeriodStatusId',      N'TSP', N'TSP.PeriodStatusID',      N'MAPPED'),
    (N'Timesheet',N'FeuilleDeTemps', 11,N'StartDate',           N'StartDate',           N'TSP', N'TSP.StartDate',           N'MAPPED'),
    (N'Timesheet',N'FeuilleDeTemps', 12,N'StatusDescription',   N'StatusDescription',   N'TSS', N'TSS.Description',         N'MAPPED'),
    (N'Timesheet',N'FeuilleDeTemps', 13,N'TimesheetOwner',      N'TimesheetOwner',      N'MTR', N'MTR.ResourceName',        N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

/* ---- TimesheetClasses ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'TimesheetClasses',N'ClassesFeuilleTemps',  1,N'ClassUID',          N'IdClasseFeuilleDeTemps',  N'src', N'src.ClassUID',      N'MAPPED'),
    (N'TimesheetClasses',N'ClassesFeuilleTemps',  2,N'DepartmentUID',     N'IdService',               N'src', N'src.DepartmentUID', N'MAPPED'),
    (N'TimesheetClasses',N'ClassesFeuilleTemps',  3,N'DepartmentName',    N'NomService',              N'src', N'src.DepartmentName',N'MAPPED'),
    (N'TimesheetClasses',N'ClassesFeuilleTemps',  4,N'Description',       N'Description',             N'src', N'src.Description',  N'MAPPED'),
    (N'TimesheetClasses',N'ClassesFeuilleTemps',  5,N'LCID',              N'LCID',                    N'src', N'src.LCID',          N'MAPPED'),
    (N'TimesheetClasses',N'ClassesFeuilleTemps',  6,N'TimesheetClassName', N'NomClasseFeuilleDeTemps', N'src', N'src.ClassName',     N'MAPPED'),
    (N'TimesheetClasses',N'ClassesFeuilleTemps',  7,N'TimesheetClassType', N'TypeClasseFeuilleDeTemps',N'src', N'src.Type',          N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

/* ---- TimesheetPeriods ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'TimesheetPeriods',N'PériodesFeuilleTemps',  1,N'PeriodUID',      N'IdPériode',       N'src',  N'src.PeriodUID',      N'MAPPED'),
    (N'TimesheetPeriods',N'PériodesFeuilleTemps',  2,N'EndDate',        N'DateFin',         N'src',  N'src.EndDate',        N'MAPPED'),
    (N'TimesheetPeriods',N'PériodesFeuilleTemps',  3,N'LCID',           N'LCID',            N'src',  N'src.LCID',           N'MAPPED'),
    (N'TimesheetPeriods',N'PériodesFeuilleTemps',  4,N'PeriodName',     N'NomPériode',      N'src',  N'src.PeriodName',     N'MAPPED'),
    (N'TimesheetPeriods',N'PériodesFeuilleTemps',  5,N'PeriodStatusID', N'IdÉtatPériode',   N'src',  N'src.PeriodStatusID', N'MAPPED'),
    (N'TimesheetPeriods',N'PériodesFeuilleTemps',  6,N'StartDate',      N'DateDébut',       N'src',  N'src.StartDate',      N'MAPPED'),
    (N'TimesheetPeriods',N'PériodesFeuilleTemps',  7,N'PeriodStatusDescription', N'Description', N'TSPS', N'TSPS.Description', N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

/* ---- TimesheetLineActualDataSet ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'TimesheetLineActualDataSet',N'RéelsLigneFeuilleTemps',  1,N'TimesheetLineUID',              N'IdLigneFeuilleDeTemps',                               N'src', N'src.TimesheetLineUID',              N'MAPPED'),
    (N'TimesheetLineActualDataSet',N'RéelsLigneFeuilleTemps',  2,N'TimeByDay',                     N'HeureParJour',                                        N'src', N'src.TimeByDay',                     N'MAPPED'),
    (N'TimesheetLineActualDataSet',N'RéelsLigneFeuilleTemps',  3,N'ActualOvertimeWorkBillable',     N'TravailHeuresSupplémentairesRéelFacturable',          N'src', N'src.ActualOvertimeWorkBillable',     N'MAPPED'),
    (N'TimesheetLineActualDataSet',N'RéelsLigneFeuilleTemps',  4,N'ActualOvertimeWorkNonBillable',  N'TravailHeuresSupplémentairesRéelNonFacturable',       N'src', N'src.ActualOvertimeWorkNonBillable',  N'MAPPED'),
    (N'TimesheetLineActualDataSet',N'RéelsLigneFeuilleTemps',  5,N'ActualWorkBillable',             N'TravailRéelFacturable',                               N'src', N'src.ActualWorkBillable',             N'MAPPED'),
    (N'TimesheetLineActualDataSet',N'RéelsLigneFeuilleTemps',  6,N'ActualWorkNonBillable',          N'TravailRéelNonFacturable',                            N'src', N'src.ActualWorkNonBillable',          N'MAPPED'),
    (N'TimesheetLineActualDataSet',N'RéelsLigneFeuilleTemps',  7,N'AdjustmentIndex',               N'IndexAjustement',                                     N'src', N'src.AdjustmentIndex',               N'MAPPED'),
    (N'TimesheetLineActualDataSet',N'RéelsLigneFeuilleTemps',  8,N'Comment',                       N'Commentaire',                                         N'src', N'src.Comment',                       N'MAPPED'),
    (N'TimesheetLineActualDataSet',N'RéelsLigneFeuilleTemps',  9,N'CreatedDate',                   N'DateCréation',                                        N'src', N'src.CreatedDate',                   N'MAPPED'),
    (N'TimesheetLineActualDataSet',N'RéelsLigneFeuilleTemps', 10,N'PlannedWork',                   N'TravailPrévu',                                        N'src', N'src.PlannedWork',                   N'MAPPED'),
    (N'TimesheetLineActualDataSet',N'RéelsLigneFeuilleTemps', 11,N'TimeByDay_DayOfMonth',          N'HeureParJour_JourDuMois',                             N'src', N'src.TimeByDay_DayOfMonth',          N'MAPPED'),
    (N'TimesheetLineActualDataSet',N'RéelsLigneFeuilleTemps', 12,N'TimeByDay_DayOfWeek',           N'HeureParJour_JourDeLaSemaine',                        N'src', N'src.TimeByDay_DayOfWeek',           N'MAPPED'),
    (N'TimesheetLineActualDataSet',N'RéelsLigneFeuilleTemps', 13,N'TimesheetLineModifiedDate',     N'TimesheetLineModifiedDate',                           N'src', N'src.TimesheetLineModifiedDate',     N'MAPPED'),
    (N'TimesheetLineActualDataSet',N'RéelsLigneFeuilleTemps', 14,N'LastChangedResourceName',       N'NomRessourceDernièreModification',                    N'RU',  N'RU.ResourceName',                  N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

RAISERROR(N'  Timesheet group done.', 0, 1) WITH NOWAIT;
GO

/* ---- TimesheetLines ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'TimesheetLines',N'LignesFeuilleTemps',  1,N'TimesheetLineUID',          N'IdLigneFeuilleDeTemps',                            N'src', N'src.TimesheetLineUID',          N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps',  2,N'ActualOvertimeWorkBillable', N'TravailHeuresSupplémentairesRéelFacturable',        N'src', N'src.ActualOvertimeWorkBillable', N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps',  3,N'ActualOvertimeWorkNonBillable',N'TravailHeuresSupplémentairesRéelNonFacturable',   N'src', N'src.ActualOvertimeWorkNonBillable',N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps',  4,N'ActualWorkBillable',         N'TravailRéelFacturable',                            N'src', N'src.ActualWorkBillable',         N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps',  5,N'ActualWorkNonBillable',      N'TravailRéelNonFacturable',                         N'src', N'src.ActualWorkNonBillable',      N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps',  6,N'CreatedDate',                N'DateCréation',                                     N'src', N'src.CreatedDate',                N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps',  7,N'ModifiedDate',               N'DateModification',                                 N'src', N'src.ModifiedDate',               N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps',  8,N'PeriodEndDate',              N'DateFinPériode',                                   N'src', N'src.PeriodEndDate',              N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps',  9,N'PeriodStartDate',            N'DateDébutPériode',                                 N'src', N'src.PeriodStartDate',            N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps', 10,N'PlannedWork',                N'TravailPrévu',                                     N'src', N'src.PlannedWork',                N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps', 11,N'ProjectUID',                 N'IdProjet',                                         N'src', N'src.ProjectUID',                 N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps', 12,N'ProjectName',                N'NomProjet',                                        N'src', N'src.ProjectName',                N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps', 13,N'TaskUID',                    N'IdTâche',                                          N'src', N'src.TaskUID',                    N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps', 14,N'TaskName',                   N'NomTâche',                                         N'src', N'src.TaskName',                   N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps', 15,N'TimesheetLineClassUID',       N'IdClasseFeuilleDeTemps',                           N'src', N'src.TimesheetLineClassUID',       N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps', 16,N'TimesheetLineClass',          N'NomClasseFeuilleDeTemps',                          N'src', N'src.TimesheetLineClass',          N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps', 17,N'TimesheetLineClassType',      N'TypeClasseFeuilleDeTemps',                         N'src', N'src.TimesheetLineClassType',      N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps', 18,N'TimesheetUID',                N'IdFeuilleDeTemps',                                 N'src', N'src.TimesheetUID',                N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps', 19,N'TimesheetLineStatus',         N'ÉtatLigneFeuilleDeTemps',                          N'src', N'src.TimesheetLineStatus',         N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps', 20,N'TimesheetLineStatusID',       N'IdÉtatLigneFeuilleDeTemps',                        N'src', N'src.TimesheetLineStatusID',       N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps', 21,N'TimesheetName',               N'NomFeuilleTemps',                                  N'src', N'src.TimesheetName',               N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps', 22,N'PeriodUID',                   N'IdPériodeFeuilleDeTemps',                          N'src', N'src.PeriodUID',                   N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps', 23,N'PeriodName',                  N'NomPériodeFeuilleDeTemps',                         N'src', N'src.PeriodName',                  N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps', 24,N'PeriodStatus',                N'ÉtatPériodeFeuilleDeTemps',                        N'src', N'src.PeriodStatus',                N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps', 25,N'PeriodStatusID',              N'IdÉtatPériodeFeuilleDeTemps',                      N'src', N'src.PeriodStatusID',              N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps', 26,N'TimesheetStatus',             N'ÉtatFeuilleDeTemps',                               N'src', N'src.TimesheetStatus',             N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps', 27,N'TimesheetStatusID',           N'IdÉtatFeuilleDeTemps',                             N'src', N'src.TimesheetStatusID',           N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps', 28,N'ApproverResourceNameUID',     N'IdRessourceApprobateurFeuilleDeTemps',              N'TSL', N'TSL.ApproverResourceNameUID',     N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps', 29,N'AssignmentUID',               N'IdAffectation',                                    N'TSL', N'TSL.AssignmentUID',               N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps', 30,N'LastSavedWork',               N'DernierTravailEnregistré',                         N'TSL', N'TSL.LastSavedWork',               N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps', 31,N'TaskHierarchy',               N'HiérarchieTâches',                                 N'TSL', N'TSL.TaskHierarchy',               N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps', 32,N'TimesheetLineComment',        N'CommentaireLigneFeuilleDeTemps',                   N'TSL', N'TSL.Comment',                     N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps', 33,N'LCID',                        N'LCID',                                             N'TSLS',N'TSLS.LCID',                       N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps', 34,N'TimesheetOwnerUID',           N'IdPropriétaireFeuilleDeTemps',                     N'TS',  N'TS.OwnerResourceNameUID',          N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps', 35,N'TimesheetClassDescription',   N'DescriptionClasseFeuilleDeTemps',                  N'TSCU',N'TSCU.Description',                N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps', 36,N'ApproverTimesheetResourceName',N'NomRessourceApprobateurFeuilleDeTemps',            N'RU1', N'RU1.ResourceName',                N'MAPPED'),
    (N'TimesheetLines',N'LignesFeuilleTemps', 37,N'TimesheetOwner',              N'PropriétaireFeuilleDeTemps',                       N'MTR', N'MTR.ResourceName',                N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

RAISERROR(N'  TimesheetLines done.', 0, 1) WITH NOWAIT;
GO

/* ---- AssignmentBaselines ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'AssignmentBaselines',N'RéférencesAffectation',  1,N'AssignmentBaselineBudgetCost',        N'CoûtBudgétaireRéférenceAffectation',               N'src',N'src.AssignmentBaselineBudgetCost',        N'MAPPED'),
    (N'AssignmentBaselines',N'RéférencesAffectation',  2,N'AssignmentBaselineBudgetMaterialWork', N'TravailMatériauBudgétaireRéférenceAffectation',    N'src',N'src.AssignmentBaselineBudgetMaterialWork', N'MAPPED'),
    (N'AssignmentBaselines',N'RéférencesAffectation',  3,N'AssignmentBaselineBudgetWork',         N'TravailBudgétaireRéférenceAffectation',            N'src',N'src.AssignmentBaselineBudgetWork',         N'MAPPED'),
    (N'AssignmentBaselines',N'RéférencesAffectation',  4,N'AssignmentBaselineCost',               N'CoûtRéférenceAffectation',                         N'src',N'src.AssignmentBaselineCost',               N'MAPPED'),
    (N'AssignmentBaselines',N'RéférencesAffectation',  5,N'AssignmentBaselineFinishDate',         N'DateFinRéférenceAffectation',                      N'src',N'src.AssignmentBaselineFinishDate',         N'MAPPED'),
    (N'AssignmentBaselines',N'RéférencesAffectation',  6,N'AssignmentBaselineMaterialWork',       N'TravailMatériauRéférenceAffectation',              N'src',N'src.AssignmentBaselineMaterialWork',       N'MAPPED'),
    (N'AssignmentBaselines',N'RéférencesAffectation',  7,N'AssignmentBaselineModifiedDate',       N'AssignmentBaselineModifiedDate',                   N'src',N'src.AssignmentBaselineModifiedDate',       N'MAPPED'),
    (N'AssignmentBaselines',N'RéférencesAffectation',  8,N'AssignmentBaselineStartDate',          N'DateDébutRéférenceAffectation',                    N'src',N'src.AssignmentBaselineStartDate',          N'MAPPED'),
    (N'AssignmentBaselines',N'RéférencesAffectation',  9,N'AssignmentBaselineWork',               N'TravailRéférenceAffectation',                      N'src',N'src.AssignmentBaselineWork',               N'MAPPED'),
    (N'AssignmentBaselines',N'RéférencesAffectation', 10,N'AssignmentUID',                        N'IdAffectation',                                    N'src',N'src.AssignmentUID',                        N'MAPPED'),
    (N'AssignmentBaselines',N'RéférencesAffectation', 11,N'AssignmentType',                       N'AffectationType',                                  N'src',N'src.AssignmentType',                       N'MAPPED'),
    (N'AssignmentBaselines',N'RéférencesAffectation', 12,N'BaselineNumber',                       N'NuméroPlanningDeRéférence',                        N'src',N'src.BaselineNumber',                       N'MAPPED'),
    (N'AssignmentBaselines',N'RéférencesAffectation', 13,N'ProjectUID',                           N'IdProjet',                                         N'src',N'src.ProjectUID',                           N'MAPPED'),
    (N'AssignmentBaselines',N'RéférencesAffectation', 14,N'TaskUID',                              N'IdTâche',                                          N'src',N'src.TaskUID',                              N'MAPPED'),
    (N'AssignmentBaselines',N'RéférencesAffectation', 15,N'ProjectName',                          N'NomProjet',                                        N'PU', N'PU.ProjectName',                           N'MAPPED'),
    (N'AssignmentBaselines',N'RéférencesAffectation', 16,N'TaskName',                             N'NomTâche',                                         N'TU', N'TU.TaskName',                              N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

/* ---- AssignmentBaselineTimephasedDataSet ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'AssignmentBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceAffectation',  1,N'ProjectUID',                        N'IdProjet',                                     N'src', N'src.ProjectUID',                        N'MAPPED'),
    (N'AssignmentBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceAffectation',  2,N'AssignmentUID',                     N'IdAffectation',                                N'src', N'src.AssignmentUID',                     N'MAPPED'),
    (N'AssignmentBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceAffectation',  3,N'TimeByDay',                         N'HeureParJour',                                 N'src', N'src.TimeByDay',                         N'MAPPED'),
    (N'AssignmentBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceAffectation',  4,N'BaselineNumber',                    N'NuméroPlanningDeRéférence',                    N'src', N'src.BaselineNumber',                    N'MAPPED'),
    (N'AssignmentBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceAffectation',  5,N'AssignmentBaselineBudgetCost',       N'CoûtBudgétaireRéférenceAffectation',           N'src', N'src.AssignmentBaselineBudgetCost',       N'MAPPED'),
    (N'AssignmentBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceAffectation',  6,N'AssignmentBaselineBudgetMaterialWork',N'TravailMatériauBudgétaireRéférenceAffectation',N'src', N'src.AssignmentBaselineBudgetMaterialWork',N'MAPPED'),
    (N'AssignmentBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceAffectation',  7,N'AssignmentBaselineBudgetWork',       N'TravailBudgétaireRéférenceAffectation',        N'src', N'src.AssignmentBaselineBudgetWork',       N'MAPPED'),
    (N'AssignmentBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceAffectation',  8,N'AssignmentBaselineCost',             N'CoûtRéférenceAffectation',                     N'src', N'src.AssignmentBaselineCost',             N'MAPPED'),
    (N'AssignmentBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceAffectation',  9,N'AssignmentBaselineMaterialWork',     N'TravailMatériauRéférenceAffectation',          N'src', N'src.AssignmentBaselineMaterialWork',     N'MAPPED'),
    (N'AssignmentBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceAffectation', 10,N'AssignmentBaselineModifiedDate',     N'AssignmentBaselineModifiedDate',               N'src', N'src.AssignmentBaselineModifiedDate',     N'MAPPED'),
    (N'AssignmentBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceAffectation', 11,N'AssignmentBaselineWork',             N'TravailRéférenceAffectation',                  N'src', N'src.AssignmentBaselineWork',             N'MAPPED'),
    (N'AssignmentBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceAffectation', 12,N'FiscalPeriodUID',                    N'IDPériodeFiscale',                             N'src', N'src.FiscalPeriodUID',                    N'MAPPED'),
    (N'AssignmentBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceAffectation', 13,N'TaskUID',                            N'IdTâche',                                      N'src', N'src.TaskUID',                            N'MAPPED'),
    (N'AssignmentBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceAffectation', 14,N'ResourceUID',                        N'IdRessource',                                  N'AU',  N'AU.ResourceUID',                         N'MAPPED'),
    (N'AssignmentBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceAffectation', 15,N'ProjectName',                        N'NomProjet',                                    N'PU',  N'PU.ProjectName',                         N'MAPPED'),
    (N'AssignmentBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceAffectation', 16,N'TaskName',                           N'NomTâche',                                     N'TU',  N'TU.TaskName',                            N'MAPPED'),
    (N'AssignmentBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceAffectation', 17,N'Assignment',                         N'Affectation',                                  NULL,   NULL,                                      N'NAVIGATION'),
    (N'AssignmentBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceAffectation', 18,N'AssignmentBaselines',                N'DébutRéférenceFinRéférence',                   NULL,   NULL,                                      N'NAVIGATION'),
    (N'AssignmentBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceAffectation', 19,N'Project',                            N'Projet',                                       NULL,   NULL,                                      N'NAVIGATION'),
    (N'AssignmentBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceAffectation', 20,N'Tasks',                              N'Tâches',                                       NULL,   NULL,                                      N'NAVIGATION'),
    (N'AssignmentBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceAffectation', 21,N'Hour',                               N'Heure',                                        NULL,   NULL,                                      N'NAVIGATION')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

/* ---- AssignmentTimephasedDataSet ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation',  1,N'FiscalPeriodUID',                   N'IDPériodeFiscale',                                      N'ABD', N'ABD.FiscalPeriodUID',                   N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation',  2,N'AssignmentActualCost',               N'CoûtRéelAffectation',                                   N'src', N'src.AssignmentActualCost',               N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation',  3,N'AssignmentActualOvertimeCost',       N'CoûtHeuresSupplémentairesRéellesAffectation',           N'src', N'src.AssignmentActualOvertimeCost',       N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation',  4,N'AssignmentActualOvertimeWork',       N'HeuresSupplémentairesRéellesAffectation',               N'src', N'src.AssignmentActualOvertimeWork',       N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation',  5,N'AssignmentActualRegularCost',        N'CoûtNormalRéelAffectation',                             N'src', N'src.AssignmentActualRegularCost',        N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation',  6,N'AssignmentActualRegularWork',        N'TravailNormalRéelAffectation',                          N'src', N'src.AssignmentActualRegularWork',        N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation',  7,N'AssignmentActualWork',               N'AffectationTravailRéel',                                N'src', N'src.AssignmentActualWork',               N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation',  8,N'AssignmentBudgetCost',               N'CoûtBudgétaireAffectation',                             N'src', N'src.AssignmentBudgetCost',               N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation',  9,N'AssignmentBudgetMaterialWork',       N'TravailMatériauBudgétaireAffectation',                  N'src', N'src.AssignmentBudgetMaterialWork',       N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation', 10,N'AssignmentBudgetWork',               N'TravailBudgétaireAffectation',                          N'src', N'src.AssignmentBudgetWork',               N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation', 11,N'AssignmentCombinedWork',             N'TravailCombiné Affectation',                            N'src', N'src.AssignmentCombinedWork',             N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation', 12,N'AssignmentCost',                     N'AffectationCoût',                                       N'src', N'src.AssignmentCost',                     N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation', 13,N'AssignmentMaterialActualWork',       N'TravailRéelMatériauAffectation',                        N'src', N'src.AssignmentMaterialActualWork',       N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation', 14,N'AssignmentMaterialWork',             N'TravailMatériauAffectation',                            N'src', N'src.AssignmentMaterialWork',             N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation', 15,N'AssignmentOvertimeCost',             N'CoûtHeuresSupplémentairesAffectation',                  N'src', N'src.AssignmentOvertimeCost',             N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation', 16,N'AssignmentOvertimeWork',             N'HeuresSupplémentairesAffectation',                      N'src', N'src.AssignmentOvertimeWork',             N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation', 17,N'AssignmentRegularCost',              N'CoûtNormalAffectation',                                 N'src', N'src.AssignmentRegularCost',              N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation', 18,N'AssignmentRegularWork',              N'TravailNormalAffectation',                              N'src', N'src.AssignmentRegularWork',              N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation', 19,N'AssignmentRemainingCost',            N'AffectationCoûtRestant',                                N'src', N'src.AssignmentRemainingCost',            N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation', 20,N'AssignmentRemainingOvertimeCost',    N'CoûtHeuresSupplémentairesRestantes',                    N'src', N'src.AssignmentRemainingOvertimeCost',    N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation', 21,N'AssignmentRemainingOvertimeWork',    N'HeuresSupplémentairesRestantesAffectation',             N'src', N'src.AssignmentRemainingOvertimeWork',    N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation', 22,N'AssignmentRemainingRegularCost',     N'CoûtNormalRestantAffectation',                          N'src', N'src.AssignmentRemainingRegularCost',     N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation', 23,N'AssignmentRemainingRegularWork',     N'TravailNormalRestantAffectation',                       N'src', N'src.AssignmentRemainingRegularWork',     N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation', 24,N'AssignmentRemainingWork',            N'AffectationTravailRestant',                             N'src', N'src.AssignmentRemainingWork',            N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation', 25,N'AssignmentResourcePlanWork',         N'AffectationRessourcePlanTravail',                       N'src', N'src.AssignmentResourcePlanWork',         N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation', 26,N'AssignmentUID',                      N'IdAffectation',                                         N'src', N'src.AssignmentUID',                      N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation', 27,N'AssignmentWork',                     N'AffectationTravail',                                    N'src', N'src.AssignmentWork',                     N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation', 28,N'ProjectUID',                         N'IdProjet',                                              N'src', N'src.ProjectUID',                         N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation', 29,N'TaskIsActive',                       N'TâcheEstActive',                                        N'src', N'src.TaskIsActive',                       N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation', 30,N'TaskUID',                            N'IdTâche',                                               N'src', N'src.TaskUID',                            N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation', 31,N'TimeByDay',                          N'HeureParJour',                                          N'src', N'src.TimeByDay',                          N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation', 32,N'AssignmentModifiedDate',             N'AffectationDateModification',                           N'AU',  N'AU.AssignmentModifiedDate',              N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation', 33,N'ResourceUID',                        N'IdRessource',                                           N'AU',  N'AU.ResourceUID',                         N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation', 34,N'ProjectName',                        N'NomProjet',                                             N'PU',  N'PU.ProjectName',                         N'MAPPED'),
    (N'AssignmentTimephasedDataSet',N'JeuDonnéesChronologiquesAffectation', 35,N'TaskName',                           N'NomTâche',                                              N'TU',  N'TU.TaskName',                            N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

RAISERROR(N'  Assignment baselines & timephased done.', 0, 1) WITH NOWAIT;
GO

/* ---- TaskBaselines ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'TaskBaselines',N'RéférencesTâche',  1,N'ProjectName',                      N'NomProjet',                         N'PU', N'PU.ProjectName',                      N'MAPPED'),
    (N'TaskBaselines',N'RéférencesTâche',  2,N'TaskName',                          N'NomTâche',                          N'TU', N'TU.TaskName',                          N'MAPPED'),
    (N'TaskBaselines',N'RéférencesTâche',  3,N'BaselineNumber',                    N'NuméroPlanningDeRéférence',         N'src',N'src.BaselineNumber',                    N'MAPPED'),
    (N'TaskBaselines',N'RéférencesTâche',  4,N'ProjectUID',                        N'IdProjet',                          N'src',N'src.ProjectUID',                        N'MAPPED'),
    (N'TaskBaselines',N'RéférencesTâche',  5,N'TaskBaselineBudgetCost',            N'CoûtBudgétaireRéférenceTâche',     N'src',N'src.TaskBaselineBudgetCost',            N'MAPPED'),
    (N'TaskBaselines',N'RéférencesTâche',  6,N'TaskBaselineBudgetWork',            N'TravailBudgétaireRéférenceTâche',  N'src',N'src.TaskBaselineBudgetWork',            N'MAPPED'),
    (N'TaskBaselines',N'RéférencesTâche',  7,N'TaskBaselineCost',                  N'CoûtRéférenceTâche',               N'src',N'src.TaskBaselineCost',                  N'MAPPED'),
    (N'TaskBaselines',N'RéférencesTâche',  8,N'TaskBaselineDeliverableFinishDate', N'DateFinLivrableRéférenceTâche',    N'src',N'src.TaskBaselineDeliverableFinishDate', N'MAPPED'),
    (N'TaskBaselines',N'RéférencesTâche',  9,N'TaskBaselineDeliverableStartDate',  N'DateDébutLivrableRéférenceTâche',  N'src',N'src.TaskBaselineDeliverableStartDate',  N'MAPPED'),
    (N'TaskBaselines',N'RéférencesTâche', 10,N'TaskBaselineDuration',              N'DuréeRéférenceTâche',              N'src',N'src.TaskBaselineDuration',              N'MAPPED'),
    (N'TaskBaselines',N'RéférencesTâche', 11,N'TaskBaselineDurationString',        N'ChaîneDuréeRéférenceTâche',        N'src',N'src.TaskBaselineDurationString',        N'MAPPED'),
    (N'TaskBaselines',N'RéférencesTâche', 12,N'TaskBaselineFinishDate',            N'DateFinRéférenceTâche',            N'src',N'src.TaskBaselineFinishDate',            N'MAPPED'),
    (N'TaskBaselines',N'RéférencesTâche', 13,N'TaskBaselineFinishDateString',      N'ChaîneDateFinRéférenceTâche',      N'src',N'src.TaskBaselineFinishDateString',      N'MAPPED'),
    (N'TaskBaselines',N'RéférencesTâche', 14,N'TaskBaselineFixedCost',             N'CoûtFixeRéférenceTâche',           N'src',N'src.TaskBaselineFixedCost',             N'MAPPED'),
    (N'TaskBaselines',N'RéférencesTâche', 15,N'TaskBaselineModifiedDate',          N'TaskBaselineModifiedDate',          N'src',N'src.TaskBaselineModifiedDate',          N'MAPPED'),
    (N'TaskBaselines',N'RéférencesTâche', 16,N'TaskBaselineStartDate',             N'DateDébutRéférenceTâche',          N'src',N'src.TaskBaselineStartDate',             N'MAPPED'),
    (N'TaskBaselines',N'RéférencesTâche', 17,N'TaskBaselineStartDateString',       N'ChaîneDateDébutRéférenceTâche',    N'src',N'src.TaskBaselineStartDateString',       N'MAPPED'),
    (N'TaskBaselines',N'RéférencesTâche', 18,N'TaskBaselineWork',                  N'TravailRéférenceTâche',            N'src',N'src.TaskBaselineWork',                  N'MAPPED'),
    (N'TaskBaselines',N'RéférencesTâche', 19,N'TaskUID',                           N'IdTâche',                          N'src',N'src.TaskUID',                           N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

/* ---- TaskBaselineTimephasedDataSet ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'TaskBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceTâche',  1,N'BaselineNumber',          N'NuméroPlanningDeRéférence',      N'src',N'src.BaselineNumber',          N'MAPPED'),
    (N'TaskBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceTâche',  2,N'FiscalPeriodUID',          N'IDPériodeFiscale',                N'src',N'src.FiscalPeriodUID',          N'MAPPED'),
    (N'TaskBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceTâche',  3,N'ProjectUID',               N'IdProjet',                        N'src',N'src.ProjectUID',               N'MAPPED'),
    (N'TaskBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceTâche',  4,N'TaskBaselineBudgetCost',   N'CoûtBudgétaireRéférenceTâche',   N'src',N'src.TaskBaselineBudgetCost',   N'MAPPED'),
    (N'TaskBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceTâche',  5,N'TaskBaselineBudgetWork',   N'TravailBudgétaireRéférenceTâche', N'src',N'src.TaskBaselineBudgetWork',   N'MAPPED'),
    (N'TaskBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceTâche',  6,N'TaskBaselineCost',         N'CoûtRéférenceTâche',              N'src',N'src.TaskBaselineCost',         N'MAPPED'),
    (N'TaskBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceTâche',  7,N'TaskBaselineFixedCost',    N'CoûtFixeRéférenceTâche',          N'src',N'src.TaskBaselineFixedCost',    N'MAPPED'),
    (N'TaskBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceTâche',  8,N'TaskBaselineModifiedDate', N'TaskBaselineModifiedDate',         N'src',N'src.TaskBaselineModifiedDate', N'MAPPED'),
    (N'TaskBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceTâche',  9,N'TaskBaselineWork',         N'TravailRéférenceTâche',            N'src',N'src.TaskBaselineWork',         N'MAPPED'),
    (N'TaskBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceTâche', 10,N'TaskUID',                  N'IdTâche',                          N'src',N'src.TaskUID',                  N'MAPPED'),
    (N'TaskBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceTâche', 11,N'TimeByDay',                N'HeureParJour',                     N'src',N'src.TimeByDay',                N'MAPPED'),
    (N'TaskBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceTâche', 12,N'ProjectName',              N'NomProjet',                        N'PU', N'PU.ProjectName',              N'MAPPED'),
    (N'TaskBaselineTimephasedDataSet',N'JeuDonnéesChronologiquesRéférenceTâche', 13,N'TaskName',                 N'NomTâche',                         N'TU', N'TU.TaskName',                 N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

/* ---- TaskTimephasedDataSet ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'TaskTimephasedDataSet',N'JeuDonnéesChronologiquesTâche',  1,N'FiscalPeriodUID',         N'IDPériodeFiscale',             N'src',N'src.FiscalPeriodUID',         N'MAPPED'),
    (N'TaskTimephasedDataSet',N'JeuDonnéesChronologiquesTâche',  2,N'ProjectUID',               N'IdProjet',                     N'src',N'src.ProjectUID',               N'MAPPED'),
    (N'TaskTimephasedDataSet',N'JeuDonnéesChronologiquesTâche',  3,N'TaskActualCost',           N'CoûtRéelTâche',               N'src',N'src.TaskActualCost',           N'MAPPED'),
    (N'TaskTimephasedDataSet',N'JeuDonnéesChronologiquesTâche',  4,N'TaskActualWork',           N'TravailRéelTâche',             N'src',N'src.TaskActualWork',           N'MAPPED'),
    (N'TaskTimephasedDataSet',N'JeuDonnéesChronologiquesTâche',  5,N'TaskBudgetCost',           N'CoûtBudgétaireTâche',          N'src',N'src.TaskBudgetCost',           N'MAPPED'),
    (N'TaskTimephasedDataSet',N'JeuDonnéesChronologiquesTâche',  6,N'TaskBudgetWork',           N'TravailBudgétaireTâche',       N'src',N'src.TaskBudgetWork',           N'MAPPED'),
    (N'TaskTimephasedDataSet',N'JeuDonnéesChronologiquesTâche',  7,N'TaskCost',                 N'CoûtTâche',                   N'src',N'src.TaskCost',                 N'MAPPED'),
    (N'TaskTimephasedDataSet',N'JeuDonnéesChronologiquesTâche',  8,N'TaskIsActive',             N'TâcheEstActive',               N'src',N'src.TaskIsActive',             N'MAPPED'),
    (N'TaskTimephasedDataSet',N'JeuDonnéesChronologiquesTâche',  9,N'TaskIsProjectSummary',     N'TâcheRécapitulativeProjet',    N'src',N'src.TaskIsProjectSummary',     N'MAPPED'),
    (N'TaskTimephasedDataSet',N'JeuDonnéesChronologiquesTâche', 10,N'TaskModifiedDate',         N'DateModificationTâche',        N'src',N'src.TaskModifiedDate',         N'MAPPED'),
    (N'TaskTimephasedDataSet',N'JeuDonnéesChronologiquesTâche', 11,N'TaskOvertimeWork',         N'TravailHeuresSupplémentairesTâche',N'src',N'src.TaskOvertimeWork',     N'MAPPED'),
    (N'TaskTimephasedDataSet',N'JeuDonnéesChronologiquesTâche', 12,N'TaskResourcePlanWork',     N'TravailPlanRessourcesTâche',   N'src',N'src.TaskResourcePlanWork',     N'MAPPED'),
    (N'TaskTimephasedDataSet',N'JeuDonnéesChronologiquesTâche', 13,N'TaskUID',                  N'IdTâche',                      N'src',N'src.TaskUID',                  N'MAPPED'),
    (N'TaskTimephasedDataSet',N'JeuDonnéesChronologiquesTâche', 14,N'TaskWork',                 N'TravailTâche',                 N'src',N'src.TaskWork',                 N'MAPPED'),
    (N'TaskTimephasedDataSet',N'JeuDonnéesChronologiquesTâche', 15,N'TimeByDay',                N'HeureParJour',                 N'src',N'src.TimeByDay',                N'MAPPED'),
    (N'TaskTimephasedDataSet',N'JeuDonnéesChronologiquesTâche', 16,N'ProjectName',              N'NomProjet',                    N'PU', N'PU.ProjectName',              N'MAPPED'),
    (N'TaskTimephasedDataSet',N'JeuDonnéesChronologiquesTâche', 17,N'TaskName',                 N'NomTâche',                     N'TU', N'TU.TaskName',                 N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

/* ---- ProjectBaselines ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'ProjectBaselines',N'RéférencesProjet',  1,N'ProjectName',                       N'NomProjet',                          N'PU', N'PU.ProjectName',                       N'MAPPED'),
    (N'ProjectBaselines',N'RéférencesProjet',  2,N'BaselineNumber',                    N'NuméroPlanningDeRéférence',          N'src',N'src.BaselineNumber',                    N'MAPPED'),
    (N'ProjectBaselines',N'RéférencesProjet',  3,N'ProjectBaselineBudgetCost',         N'CoûtBudgétaireRéférenceProjet',     N'src',N'src.ProjectBaselineBudgetCost',         N'MAPPED'),
    (N'ProjectBaselines',N'RéférencesProjet',  4,N'ProjectBaselineBudgetWork',         N'TravailBudgétaireRéférenceProjet',  N'src',N'src.ProjectBaselineBudgetWork',         N'MAPPED'),
    (N'ProjectBaselines',N'RéférencesProjet',  5,N'ProjectBaselineCost',               N'CoûtRéférenceProjet',               N'src',N'src.ProjectBaselineCost',               N'MAPPED'),
    (N'ProjectBaselines',N'RéférencesProjet',  6,N'ProjectBaselineDeliverableFinishDate',N'DateFinLivrableRéférenceProjet',  N'src',N'src.ProjectBaselineDeliverableFinishDate',N'MAPPED'),
    (N'ProjectBaselines',N'RéférencesProjet',  7,N'ProjectBaselineDeliverableStartDate',N'DateDébutLivrableRéférenceProjet', N'src',N'src.ProjectBaselineDeliverableStartDate', N'MAPPED'),
    (N'ProjectBaselines',N'RéférencesProjet',  8,N'ProjectBaselineDuration',           N'DuréeRéférenceProjet',              N'src',N'src.ProjectBaselineDuration',           N'MAPPED'),
    (N'ProjectBaselines',N'RéférencesProjet',  9,N'ProjectBaselineDurationString',     N'ChaîneDuréeRéférenceProjet',        N'src',N'src.ProjectBaselineDurationString',     N'MAPPED'),
    (N'ProjectBaselines',N'RéférencesProjet', 10,N'ProjectBaselineFinishDate',         N'DateFinRéférenceProjet',            N'src',N'src.ProjectBaselineFinishDate',         N'MAPPED'),
    (N'ProjectBaselines',N'RéférencesProjet', 11,N'ProjectBaselineFinishDateString',   N'ChaîneDateFinRéférenceProjet',      N'src',N'src.ProjectBaselineFinishDateString',   N'MAPPED'),
    (N'ProjectBaselines',N'RéférencesProjet', 12,N'ProjectBaselineFixedCost',          N'CoûtFixeRéférenceProjet',           N'src',N'src.ProjectBaselineFixedCost',          N'MAPPED'),
    (N'ProjectBaselines',N'RéférencesProjet', 13,N'ProjectBaselineModifiedDate',       N'ProjectBaselineModifiedDate',        N'src',N'src.ProjectBaselineModifiedDate',       N'MAPPED'),
    (N'ProjectBaselines',N'RéférencesProjet', 14,N'ProjectBaselineStartDate',          N'DateDébutRéférenceProjet',          N'src',N'src.ProjectBaselineStartDate',          N'MAPPED'),
    (N'ProjectBaselines',N'RéférencesProjet', 15,N'ProjectBaselineStartDateString',    N'ChaîneDateDébutRéférenceProjet',    N'src',N'src.ProjectBaselineStartDateString',    N'MAPPED'),
    (N'ProjectBaselines',N'RéférencesProjet', 16,N'ProjectBaselineWork',               N'TravailRéférenceProjet',            N'src',N'src.ProjectBaselineWork',               N'MAPPED'),
    (N'ProjectBaselines',N'RéférencesProjet', 17,N'ProjectUID',                        N'IdProjet',                          N'src',N'src.ProjectUID',                        N'MAPPED'),
    (N'ProjectBaselines',N'RéférencesProjet', 18,N'TaskUID',                           N'IdTâche',                           N'src',N'src.TaskUID',                           N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

/* ---- ResourceTimephasedDataSet ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'ResourceTimephasedDataSet',N'JeuDonnéesChronologiquesRessource',  1,N'BaseCapacity',          N'CapacitéBase',              N'src',N'src.BaseCapacity',          N'MAPPED'),
    (N'ResourceTimephasedDataSet',N'JeuDonnéesChronologiquesRessource',  2,N'Capacity',               N'Capacité',                  N'src',N'src.Capacity',               N'MAPPED'),
    (N'ResourceTimephasedDataSet',N'JeuDonnéesChronologiquesRessource',  3,N'ResourceUID',            N'IdRessource',               N'src',N'src.ResourceUID',            N'MAPPED'),
    (N'ResourceTimephasedDataSet',N'JeuDonnéesChronologiquesRessource',  4,N'TimeByDay',              N'HeureParJour',              N'src',N'src.TimeByDay',              N'MAPPED'),
    (N'ResourceTimephasedDataSet',N'JeuDonnéesChronologiquesRessource',  5,N'FiscalPeriodUID',        N'IDPériodeFiscale',          N'TBD',N'TBD.FiscalPeriodUID',        N'MAPPED'),
    (N'ResourceTimephasedDataSet',N'JeuDonnéesChronologiquesRessource',  6,N'ResourceModifiedDate',   N'DateModificationRessource', N'RU', N'RU.ResourceModifiedDate',   N'MAPPED'),
    (N'ResourceTimephasedDataSet',N'JeuDonnéesChronologiquesRessource',  7,N'ResourceName',           N'NomRessource',              N'RU', N'RU.ResourceName',           N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

/* ---- ResourceDemandTimephasedDataSet ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'ResourceDemandTimephasedDataSet',N'JeuDonnéesChronologiquesDemandRessource',  1,N'ProjectUID',                    N'IdProjet',                       N'src',N'src.ProjectUID',                    N'MAPPED'),
    (N'ResourceDemandTimephasedDataSet',N'JeuDonnéesChronologiquesDemandRessource',  2,N'ProjectName',                   N'NomProjet',                      N'src',N'src.ProjectName',                   N'MAPPED'),
    (N'ResourceDemandTimephasedDataSet',N'JeuDonnéesChronologiquesDemandRessource',  3,N'ResourceDemand',                N'ResourceDemand',                 N'src',N'src.ResourceDemand',                N'MAPPED'),
    (N'ResourceDemandTimephasedDataSet',N'JeuDonnéesChronologiquesDemandRessource',  4,N'ResourceDemandModifiedDate',    N'ResourceDemandModifiedDate',     N'src',N'src.ResourceDemandModifiedDate',    N'MAPPED'),
    (N'ResourceDemandTimephasedDataSet',N'JeuDonnéesChronologiquesDemandRessource',  5,N'ResourceUID',                   N'IdRessource',                    N'src',N'src.ResourceUID',                   N'MAPPED'),
    (N'ResourceDemandTimephasedDataSet',N'JeuDonnéesChronologiquesDemandRessource',  6,N'TimeByDay',                     N'HeureParJour',                   N'src',N'src.TimeByDay',                     N'MAPPED'),
    (N'ResourceDemandTimephasedDataSet',N'JeuDonnéesChronologiquesDemandRessource',  7,N'FiscalPeriodUID',               N'IDPériodeFiscale',               N'TBD',N'TBD.FiscalPeriodUID',               N'MAPPED'),
    (N'ResourceDemandTimephasedDataSet',N'JeuDonnéesChronologiquesDemandRessource',  8,N'ResourcePlanUtilizationDate',   N'DatePlanUtilisationRessource',   N'PU', N'PU.ResourcePlanUtilizationDate',   N'MAPPED'),
    (N'ResourceDemandTimephasedDataSet',N'JeuDonnéesChronologiquesDemandRessource',  9,N'ResourcePlanUtilizationType',   N'TypePlanUtilisationRessource',   N'PU', N'PU.ResourcePlanUtilizationType',   N'MAPPED'),
    (N'ResourceDemandTimephasedDataSet',N'JeuDonnéesChronologiquesDemandRessource', 10,N'ResourceName',                  N'NomRessource',                   N'RU', N'RU.ResourceName',                  N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

/* ---- EngagementsTimephasedDataSet ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'EngagementsTimephasedDataSet',N'JeuDonnéesChronologiquesEngagements',  1,N'CommittedUnits',           N'NbMaxUnitésValidées',            N'src',N'src.CommittedUnits',           N'MAPPED'),
    (N'EngagementsTimephasedDataSet',N'JeuDonnéesChronologiquesEngagements',  2,N'CommittedWork',            N'TravailValidé',                  N'src',N'src.CommittedWork',            N'MAPPED'),
    (N'EngagementsTimephasedDataSet',N'JeuDonnéesChronologiquesEngagements',  3,N'EngagementModifiedDate',   N'DateModificationEngagement',     N'src',N'src.EngagementModifiedDate',   N'MAPPED'),
    (N'EngagementsTimephasedDataSet',N'JeuDonnéesChronologiquesEngagements',  4,N'EngagementName',           N'NomEngagement',                  N'src',N'src.EngagementName',           N'MAPPED'),
    (N'EngagementsTimephasedDataSet',N'JeuDonnéesChronologiquesEngagements',  5,N'EngagementUID',            N'IDEngagement',                   N'src',N'src.EngagementUID',            N'MAPPED'),
    (N'EngagementsTimephasedDataSet',N'JeuDonnéesChronologiquesEngagements',  6,N'ProjectUID',               N'IdProjet',                       N'src',N'src.ProjectUID',               N'MAPPED'),
    (N'EngagementsTimephasedDataSet',N'JeuDonnéesChronologiquesEngagements',  7,N'ProposedUnits',            N'NbMaxUnitésProposées',           N'src',N'src.ProposedUnits',            N'MAPPED'),
    (N'EngagementsTimephasedDataSet',N'JeuDonnéesChronologiquesEngagements',  8,N'ProposedWork',             N'TravailProposé',                 N'src',N'src.ProposedWork',             N'MAPPED'),
    (N'EngagementsTimephasedDataSet',N'JeuDonnéesChronologiquesEngagements',  9,N'ResourceUID',              N'IdRessource',                    N'src',N'src.ResourceUID',              N'MAPPED'),
    (N'EngagementsTimephasedDataSet',N'JeuDonnéesChronologiquesEngagements', 10,N'EngagementDate',           N'HeureParJour',                   N'src',N'src.EngagementDate',           N'MAPPED'),
    (N'EngagementsTimephasedDataSet',N'JeuDonnéesChronologiquesEngagements', 11,N'ProjectName',              N'NomProjet',                      N'PU', N'PU.ProjectName',              N'MAPPED'),
    (N'EngagementsTimephasedDataSet',N'JeuDonnéesChronologiquesEngagements', 12,N'ResourceName',             N'NomRessource',                   N'RU', N'RU.ResourceName',             N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

RAISERROR(N'  Task/Project baselines, Resource/Engagement timephased done.', 0, 1) WITH NOWAIT;
GO

/* ---- Risks ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'Risks',N'Risques',  1,N'AssignedToResource',    N'AssignéeRessource',             N'src',N'src.AssignedToResource',    N'MAPPED'),
    (N'Risks',N'Risques',  2,N'Category',               N'Catégorie',                    N'src',N'src.Category',               N'MAPPED'),
    (N'Risks',N'Risques',  3,N'ContingencyPlan',        N'PlanUrgence',                  N'src',N'src.ContingencyPlan',        N'MAPPED'),
    (N'Risks',N'Risques',  4,N'Cost',                   N'Coût',                         N'src',N'src.Cost',                   N'MAPPED'),
    (N'Risks',N'Risques',  5,N'CostExposure',           N'ExpositionCoût',               N'src',N'src.CostExposure',           N'MAPPED'),
    (N'Risks',N'Risques',  6,N'CreateByResource',       N'CréerParRessource',            N'src',N'src.CreateByResource',       N'MAPPED'),
    (N'Risks',N'Risques',  7,N'CreatedDate',            N'DateCréation',                 N'src',N'src.CreatedDate',            N'MAPPED'),
    (N'Risks',N'Risques',  8,N'Description',            N'Description',                  N'src',N'src.Description',            N'MAPPED'),
    (N'Risks',N'Risques',  9,N'DueDate',                N'Échéance',                     N'src',N'src.DueDate',                N'MAPPED'),
    (N'Risks',N'Risques', 10,N'Exposure',               N'Exposition',                   N'src',N'src.Exposure',               N'MAPPED'),
    (N'Risks',N'Risques', 11,N'Impact',                 N'Impact',                       N'src',N'src.Impact',                 N'MAPPED'),
    (N'Risks',N'Risques', 12,N'IsFolder',               N'EstUnDossier',                 N'src',N'src.IsFolder',               N'MAPPED'),
    (N'Risks',N'Risques', 13,N'ItemRelativeUrlPath',    N'CheminURLRelativeÉlément',     N'src',N'src.ItemRelativeUrlPath',    N'MAPPED'),
    (N'Risks',N'Risques', 14,N'MitigationPlan',         N'PlanAtténuation',              N'src',N'src.MitigationPlan',         N'MAPPED'),
    (N'Risks',N'Risques', 15,N'ModifiedByResource',     N'ModifiéParRessource',          N'src',N'src.ModifiedByResource',     N'MAPPED'),
    (N'Risks',N'Risques', 16,N'ModifiedDate',           N'DateModification',             N'src',N'src.ModifiedDate',           N'MAPPED'),
    (N'Risks',N'Risques', 17,N'NumberOfAttachments',    N'NombreDePièces jointes',       N'src',N'src.NumberOfAttachments',    N'MAPPED'),
    (N'Risks',N'Risques', 18,N'Owner',                  N'Propriétaire',                 N'src',N'src.Owner',                  N'MAPPED'),
    (N'Risks',N'Risques', 19,N'Probability',            N'Probabilité',                  N'src',N'src.Probability',            N'MAPPED'),
    (N'Risks',N'Risques', 20,N'ProjectUID',             N'IdProjet',                     N'src',N'src.ProjectUID',             N'MAPPED'),
    (N'Risks',N'Risques', 21,N'RiskID',                 N'IdRisque',                     N'src',N'src.RiskID',                 N'MAPPED'),
    (N'Risks',N'Risques', 22,N'Status',                 N'Statut',                       N'src',N'src.Status',                 N'MAPPED'),
    (N'Risks',N'Risques', 23,N'Title',                  N'Titre',                        N'src',N'src.Title',                  N'MAPPED'),
    (N'Risks',N'Risques', 24,N'TriggerDescription',     N'DescriptionDéclencheur',       N'src',N'src.TriggerDescription',     N'MAPPED'),
    (N'Risks',N'Risques', 25,N'TriggerTask',            N'TâcheDéclencheur',             N'src',N'src.TriggerTask',            N'MAPPED'),
    (N'Risks',N'Risques', 26,N'ProjectName',            N'NomProjet',                    N'PU', N'PU.ProjectName',            N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

/* ---- RiskTaskAssociations ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'RiskTaskAssociations',N'AssociationsTâchesRisques',  1,N'ProjectId',          N'IdProjet',              N'src',N'src.ProjectId',          N'MAPPED'),
    (N'RiskTaskAssociations',N'AssociationsTâchesRisques',  2,N'ProjectName',        N'NomProjet',             N'src',N'src.ProjectName',        N'MAPPED'),
    (N'RiskTaskAssociations',N'AssociationsTâchesRisques',  3,N'RelatedProjectId',   N'IDProjetApparenté',     N'src',N'src.RelatedProjectId',   N'MAPPED'),
    (N'RiskTaskAssociations',N'AssociationsTâchesRisques',  4,N'RelatedProjectName', N'NomProjetApparenté',    N'src',N'src.RelatedProjectName', N'MAPPED'),
    (N'RiskTaskAssociations',N'AssociationsTâchesRisques',  5,N'RelationshipType',   N'TypeRelation',          N'src',N'src.RelationshipType',   N'MAPPED'),
    (N'RiskTaskAssociations',N'AssociationsTâchesRisques',  6,N'RiskId',             N'IdRisque',              N'src',N'src.RiskId',             N'MAPPED'),
    (N'RiskTaskAssociations',N'AssociationsTâchesRisques',  7,N'TaskId',             N'IdTâche',               N'src',N'src.TaskId',             N'MAPPED'),
    (N'RiskTaskAssociations',N'AssociationsTâchesRisques',  8,N'TaskName',           N'NomTâche',              N'src',N'src.TaskName',           N'MAPPED'),
    (N'RiskTaskAssociations',N'AssociationsTâchesRisques',  9,N'Title',              N'Titre',                 N'src',N'src.Title',              N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

/* ---- Issues ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'Issues',N'Problèmes',  1,N'AssignedToResource',  N'AssignéeRessource',           N'src',N'src.AssignedToResource',  N'MAPPED'),
    (N'Issues',N'Problèmes',  2,N'Category',             N'Catégorie',                  N'src',N'src.Category',             N'MAPPED'),
    (N'Issues',N'Problèmes',  3,N'CreateByResource',     N'CréerParRessource',          N'src',N'src.CreateByResource',     N'MAPPED'),
    (N'Issues',N'Problèmes',  4,N'CreatedDate',          N'DateCréation',               N'src',N'src.CreatedDate',          N'MAPPED'),
    (N'Issues',N'Problèmes',  5,N'Discussion',           N'Discussion',                 N'src',N'src.Discussion',           N'MAPPED'),
    (N'Issues',N'Problèmes',  6,N'DueDate',              N'Échéance',                   N'src',N'src.DueDate',              N'MAPPED'),
    (N'Issues',N'Problèmes',  7,N'IsFolder',             N'EstUnDossier',               N'src',N'src.IsFolder',             N'MAPPED'),
    (N'Issues',N'Problèmes',  8,N'IssueID',              N'IdProblème',                 N'src',N'src.IssueID',              N'MAPPED'),
    (N'Issues',N'Problèmes',  9,N'ItemRelativeUrlPath',  N'CheminURLRelativeÉlément',   N'src',N'src.ItemRelativeUrlPath',  N'MAPPED'),
    (N'Issues',N'Problèmes', 10,N'ModifiedByResource',   N'ModifiéParRessource',        N'src',N'src.ModifiedByResource',   N'MAPPED'),
    (N'Issues',N'Problèmes', 11,N'ModifiedDate',         N'DateModification',           N'src',N'src.ModifiedDate',         N'MAPPED'),
    (N'Issues',N'Problèmes', 12,N'NumberOfAttachments',  N'NombreDePièces jointes',     N'src',N'src.NumberOfAttachments',  N'MAPPED'),
    (N'Issues',N'Problèmes', 13,N'Owner',                N'Propriétaire',               N'src',N'src.Owner',                N'MAPPED'),
    (N'Issues',N'Problèmes', 14,N'Priority',             N'Priorité',                   N'src',N'src.Priority',             N'MAPPED'),
    (N'Issues',N'Problèmes', 15,N'ProjectUID',           N'IdProjet',                   N'src',N'src.ProjectUID',           N'MAPPED'),
    (N'Issues',N'Problèmes', 16,N'Resolution',           N'Résolution',                 N'src',N'src.Resolution',           N'MAPPED'),
    (N'Issues',N'Problèmes', 17,N'Status',               N'Statut',                     N'src',N'src.Status',               N'MAPPED'),
    (N'Issues',N'Problèmes', 18,N'Title',                N'Titre',                      N'src',N'src.Title',                N'MAPPED'),
    (N'Issues',N'Problèmes', 19,N'ProjectName',          N'NomProjet',                  N'PU', N'PU.ProjectName',          N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

/* ---- IssueTaskAssociations ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'IssueTaskAssociations',N'AssociationsTâchesProblèmes',  1,N'IssueId',           N'IdProblème',            N'src',N'src.IssueId',           N'MAPPED'),
    (N'IssueTaskAssociations',N'AssociationsTâchesProblèmes',  2,N'ProjectId',          N'IdProjet',              N'src',N'src.ProjectId',          N'MAPPED'),
    (N'IssueTaskAssociations',N'AssociationsTâchesProblèmes',  3,N'ProjectName',        N'NomProjet',             N'src',N'src.ProjectName',        N'MAPPED'),
    (N'IssueTaskAssociations',N'AssociationsTâchesProblèmes',  4,N'RelatedProjectId',   N'IDProjetApparenté',     N'src',N'src.RelatedProjectId',   N'MAPPED'),
    (N'IssueTaskAssociations',N'AssociationsTâchesProblèmes',  5,N'RelatedProjectName', N'NomProjetApparenté',    N'src',N'src.RelatedProjectName', N'MAPPED'),
    (N'IssueTaskAssociations',N'AssociationsTâchesProblèmes',  6,N'RelationshipType',   N'TypeRelation',          N'src',N'src.RelationshipType',   N'MAPPED'),
    (N'IssueTaskAssociations',N'AssociationsTâchesProblèmes',  7,N'TaskId',             N'IdTâche',               N'src',N'src.TaskId',             N'MAPPED'),
    (N'IssueTaskAssociations',N'AssociationsTâchesProblèmes',  8,N'TaskName',           N'NomTâche',              N'src',N'src.TaskName',           N'MAPPED'),
    (N'IssueTaskAssociations',N'AssociationsTâchesProblèmes',  9,N'Title',              N'Titre',                 N'src',N'src.Title',              N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

/* ---- Deliverables ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'Deliverables',N'Livrables',  1,N'CreateByResource',     N'CréerParRessource',          N'src',N'src.CreateByResource',     N'MAPPED'),
    (N'Deliverables',N'Livrables',  2,N'CreatedDate',          N'DateCréation',               N'src',N'src.CreatedDate',          N'MAPPED'),
    (N'Deliverables',N'Livrables',  3,N'DeliverableID',        N'IdLivrable',                 N'src',N'src.DeliverableID',        N'MAPPED'),
    (N'Deliverables',N'Livrables',  4,N'Description',          N'Description',                N'src',N'src.Description',          N'MAPPED'),
    (N'Deliverables',N'Livrables',  5,N'FinishDate',           N'FinishDate',                 N'src',N'src.FinishDate',           N'MAPPED'),
    (N'Deliverables',N'Livrables',  6,N'IsFolder',             N'EstUnDossier',               N'src',N'src.IsFolder',             N'MAPPED'),
    (N'Deliverables',N'Livrables',  7,N'ItemRelativeUrlPath',  N'CheminURLRelativeÉlément',   N'src',N'src.ItemRelativeUrlPath',  N'MAPPED'),
    (N'Deliverables',N'Livrables',  8,N'ModifiedByResource',   N'ModifiéParRessource',        N'src',N'src.ModifiedByResource',   N'MAPPED'),
    (N'Deliverables',N'Livrables',  9,N'ModifiedDate',         N'DateModification',           N'src',N'src.ModifiedDate',         N'MAPPED'),
    (N'Deliverables',N'Livrables', 10,N'ProjectUID',           N'IdProjet',                   N'src',N'src.ProjectUID',           N'MAPPED'),
    (N'Deliverables',N'Livrables', 11,N'StartDate',            N'DateDébut',                  N'src',N'src.StartDate',            N'MAPPED'),
    (N'Deliverables',N'Livrables', 12,N'Title',                N'Titre',                      N'src',N'src.Title',                N'MAPPED'),
    (N'Deliverables',N'Livrables', 13,N'ProjectName',          N'NomProjet',                  N'PU', N'PU.ProjectName',          N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

RAISERROR(N'  Risks, Issues, Deliverables done.', 0, 1) WITH NOWAIT;
GO

/* ---- PortfolioAnalyses ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'PortfolioAnalyses',N'AnalysesPortefeuille',  1,N'AlternateProjectEndDateCustomFieldUID',   N'IdChampPersonnaliséAutreDateFinProjet',                 N'src',N'src.AlternateProjectEndDateCustomFieldUID',   N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille',  2,N'AlternateProjectEndDateCustomFieldName',  N'NomChampPersonnaliséAutreDateFinProjet',                N'src',N'src.AlternateProjectEndDateCustomFieldName',  N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille',  3,N'AlternateProjectStartDateCustomFieldUID', N'IdChampPersonnaliséAutreDateDébutProjet',               N'src',N'src.AlternateProjectStartDateCustomFieldUID', N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille',  4,N'AlternateProjectStartDateCustomFieldName',N'NomChampPersonnaliséAutreDateDébutProjet',              N'src',N'src.AlternateProjectStartDateCustomFieldName',N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille',  5,N'AnalysisDescription',                     N'DescriptionAnalyse',                                    N'src',N'src.AnalysisDescription',                     N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille',  6,N'AnalysisUID',                              N'IdAnalyse',                                             N'src',N'src.AnalysisUID',                              N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille',  7,N'AnalysisName',                             N'NomAnalyse',                                            N'src',N'src.AnalysisName',                             N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille',  8,N'AnalysisType',                             N'TypeAnalyse',                                           N'src',N'src.AnalysisType',                             N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille',  9,N'BookingType',                              N'TypeRéservation',                                       N'src',N'src.BookingType',                              N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille', 10,N'CreatedByResourceUID',                     N'IdRessourceCréation',                                   N'src',N'src.CreatedByResourceUID',                     N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille', 11,N'CreatedByResourceName',                    N'NomRessourceCréation',                                  N'src',N'src.CreatedByResourceName',                    N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille', 12,N'CreatedDate',                              N'DateCréation',                                          N'src',N'src.CreatedDate',                              N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille', 13,N'DepartmentUID',                            N'IdService',                                             N'src',N'src.DepartmentUID',                            N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille', 14,N'DepartmentName',                           N'NomService',                                            N'src',N'src.DepartmentName',                           N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille', 15,N'FilterResourcesByDepartment',              N'FiltrerRessourcesParService',                           N'src',N'src.FilterResourcesByDepartment',              N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille', 16,N'FilterResourcesByRBS',                     N'FiltrerRessourcesParRBS',                               N'src',N'src.FilterResourcesByRBS',                     N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille', 17,N'FilterResourcesByRBSValueUID',             N'IdValeurFiltrerRessourcesParRBS',                       N'src',N'src.FilterResourcesByRBSValueUID',             N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille', 18,N'FilterResourcesByRBSValueText',            N'TexteValeurFiltrerRessourcesParRBS',                    N'src',N'src.FilterResourcesByRBSValueText',            N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille', 19,N'ForcedInAliasLookupTableUID',              N'IdTableChoixAliasInclusDeForce',                        N'src',N'src.ForcedInAliasLookupTableUID',              N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille', 20,N'ForcedInAliasLookupTableName',             N'NomTableChoixAliasInclusForce',                         N'src',N'src.ForcedInAliasLookupTableName',             N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille', 21,N'ForcedOutAliasLookupTableUID',             N'IdTableChoixAliasExcluDeForce',                         N'src',N'src.ForcedOutAliasLookupTableUID',             N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille', 22,N'ForcedOutAliasLookupTableName',            N'NomTableChoixAliasExcluDeForce',                        N'src',N'src.ForcedOutAliasLookupTableName',            N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille', 23,N'HardConstraintCustomFieldUID',             N'IdChampPersonnaliséContrainteImpérative',               N'src',N'src.HardConstraintCustomFieldUID',             N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille', 24,N'HardConstraintCustomFieldName',            N'NomChampPersonnaliséContrainteImpérative',              N'src',N'src.HardConstraintCustomFieldName',            N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille', 25,N'ModifiedByResourceUID',                    N'IdRessourceModification',                               N'src',N'src.ModifiedByResourceUID',                    N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille', 26,N'ModifiedByResourceName',                   N'NomRessourceModification',                              N'src',N'src.ModifiedByResourceName',                   N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille', 27,N'ModifiedDate',                             N'DateModification',                                      N'src',N'src.ModifiedDate',                             N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille', 28,N'PlanningHorizonEndDate',                   N'DateFinHorizonPlanification',                           N'src',N'src.PlanningHorizonEndDate',                   N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille', 29,N'PlanningHorizonStartDate',                 N'DateDébutHorizonPlanification',                         N'src',N'src.PlanningHorizonStartDate',                 N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille', 30,N'PrioritizationUID',                        N'IdDéfinitionPriorités',                                 N'src',N'src.PrioritizationUID',                        N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille', 31,N'PrioritizationName',                       N'NomDéfinitionPriorités',                                N'src',N'src.PrioritizationName',                       N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille', 32,N'PrioritizationType',                       N'TypeDéfinitionPriorités',                               N'src',N'src.PrioritizationType',                       N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille', 33,N'RoleCustomFieldUID',                       N'IdChampPersonnaliséRôle',                               N'src',N'src.RoleCustomFieldUID',                       N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille', 34,N'RoleCustomFieldName',                      N'NomChampPersonnaliséRôle',                              N'src',N'src.RoleCustomFieldName',                      N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille', 35,N'TimeScale',                                N'ÉchelleTemps',                                          N'src',N'src.TimeScale',                                N'MAPPED'),
    (N'PortfolioAnalyses',N'AnalysesPortefeuille', 36,N'UseAlternateProjectDatesForResourcePlans', N'UtiliserDatesProjetAlternativesPourPlansRessources',    N'src',N'src.UseAlternateProjectDatesForResourcePlans', N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

/* ---- PortfolioAnalysisProjects ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'PortfolioAnalysisProjects',N'ProjetsAnalysePortefeuille',  1,N'AbsolutePriority',     N'PrioritéAbsolue',       N'src',N'src.AbsolutePriority',     N'MAPPED'),
    (N'PortfolioAnalysisProjects',N'ProjetsAnalysePortefeuille',  2,N'AnalysisUID',           N'IdAnalyse',             N'src',N'src.AnalysisUID',           N'MAPPED'),
    (N'PortfolioAnalysisProjects',N'ProjetsAnalysePortefeuille',  3,N'AnalysisName',          N'NomAnalyse',            N'src',N'src.AnalysisName',          N'MAPPED'),
    (N'PortfolioAnalysisProjects',N'ProjetsAnalysePortefeuille',  4,N'Duration',              N'Durée',                 N'src',N'src.Duration',              N'MAPPED'),
    (N'PortfolioAnalysisProjects',N'ProjetsAnalysePortefeuille',  5,N'FinishNoLaterThan',     N'FinAuPlusTardLe',       N'src',N'src.FinishNoLaterThan',     N'MAPPED'),
    (N'PortfolioAnalysisProjects',N'ProjetsAnalysePortefeuille',  6,N'Locked',                N'Verrouillé',            N'src',N'src.Locked',                N'MAPPED'),
    (N'PortfolioAnalysisProjects',N'ProjetsAnalysePortefeuille',  7,N'OriginalEndDate',       N'DateFinOrigine',        N'src',N'src.OriginalEndDate',       N'MAPPED'),
    (N'PortfolioAnalysisProjects',N'ProjetsAnalysePortefeuille',  8,N'OriginalStartDate',     N'DateDébutOrigine',      N'src',N'src.OriginalStartDate',     N'MAPPED'),
    (N'PortfolioAnalysisProjects',N'ProjetsAnalysePortefeuille',  9,N'Priority',              N'Priorité',              N'src',N'src.Priority',              N'MAPPED'),
    (N'PortfolioAnalysisProjects',N'ProjetsAnalysePortefeuille', 10,N'ProjectUID',            N'IdProjet',              N'src',N'src.ProjectUID',            N'MAPPED'),
    (N'PortfolioAnalysisProjects',N'ProjetsAnalysePortefeuille', 11,N'ProjectName',           N'NomProjet',             N'src',N'src.ProjectName',           N'MAPPED'),
    (N'PortfolioAnalysisProjects',N'ProjetsAnalysePortefeuille', 12,N'StartDate',             N'DateDébut',             N'src',N'src.StartDate',             N'MAPPED'),
    (N'PortfolioAnalysisProjects',N'ProjetsAnalysePortefeuille', 13,N'StartNoEarlierThan',    N'DébutAuPlusTôtLe',      N'src',N'src.StartNoEarlierThan',    N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

/* ---- CostScenarioProjects ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'CostScenarioProjects',N'ProjetsScénarioCoût',  1,N'AbsolutePriority',           N'PrioritéAbsolue',             N'src',N'src.AbsolutePriority',           N'MAPPED'),
    (N'CostScenarioProjects',N'ProjetsScénarioCoût',  2,N'AnalysisUID',                N'IdAnalyse',                   N'src',N'src.AnalysisUID',                N'MAPPED'),
    (N'CostScenarioProjects',N'ProjetsScénarioCoût',  3,N'AnalysisName',               N'NomAnalyse',                  N'src',N'src.AnalysisName',               N'MAPPED'),
    (N'CostScenarioProjects',N'ProjetsScénarioCoût',  4,N'ForceAliasLookupTableUID',   N'IdTableChoixAliasForçé',      N'src',N'src.ForceAliasLookupTableUID',   N'MAPPED'),
    (N'CostScenarioProjects',N'ProjetsScénarioCoût',  5,N'ForceAliasLookupTableName',  N'NomTableChoixAliasForçé',     N'src',N'src.ForceAliasLookupTableName',  N'MAPPED'),
    (N'CostScenarioProjects',N'ProjetsScénarioCoût',  6,N'ForceStatus',                N'ÉtatForçé',                   N'src',N'src.ForceStatus',                N'MAPPED'),
    (N'CostScenarioProjects',N'ProjetsScénarioCoût',  7,N'HardConstraintValue',        N'ValeurContrainteImpérative',  N'src',N'src.HardConstraintValue',        N'MAPPED'),
    (N'CostScenarioProjects',N'ProjetsScénarioCoût',  8,N'Priority',                   N'Priorité',                    N'src',N'src.Priority',                   N'MAPPED'),
    (N'CostScenarioProjects',N'ProjetsScénarioCoût',  9,N'ProjectUID',                 N'IdProjet',                    N'src',N'src.ProjectUID',                 N'MAPPED'),
    (N'CostScenarioProjects',N'ProjetsScénarioCoût', 10,N'ProjectName',                N'NomProjet',                   N'src',N'src.ProjectName',                N'MAPPED'),
    (N'CostScenarioProjects',N'ProjetsScénarioCoût', 11,N'ScenarioUID',                N'IdScénario',                  N'src',N'src.ScenarioUID',                N'MAPPED'),
    (N'CostScenarioProjects',N'ProjetsScénarioCoût', 12,N'ScenarioName',               N'NomScénario',                 N'src',N'src.ScenarioName',               N'MAPPED'),
    (N'CostScenarioProjects',N'ProjetsScénarioCoût', 13,N'Status',                     N'Statut',                      N'src',N'src.Status',                     N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

/* ---- CostConstraintScenarios ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'CostConstraintScenarios',N'ScénariosContrainteCoût',  1,N'AnalysisUID',                    N'IdAnalyse',                          N'src',N'src.AnalysisUID',                    N'MAPPED'),
    (N'CostConstraintScenarios',N'ScénariosContrainteCoût',  2,N'AnalysisName',                   N'NomAnalyse',                         N'src',N'src.AnalysisName',                   N'MAPPED'),
    (N'CostConstraintScenarios',N'ScénariosContrainteCoût',  3,N'CreatedByResourceUID',           N'IdRessourceCréation',                N'src',N'src.CreatedByResourceUID',           N'MAPPED'),
    (N'CostConstraintScenarios',N'ScénariosContrainteCoût',  4,N'CreatedByResourceName',          N'NomRessourceCréation',               N'src',N'src.CreatedByResourceName',          N'MAPPED'),
    (N'CostConstraintScenarios',N'ScénariosContrainteCoût',  5,N'CreatedDate',                    N'DateCréation',                       N'src',N'src.CreatedDate',                    N'MAPPED'),
    (N'CostConstraintScenarios',N'ScénariosContrainteCoût',  6,N'ModifiedByResourceUID',          N'IdRessourceModification',            N'src',N'src.ModifiedByResourceUID',          N'MAPPED'),
    (N'CostConstraintScenarios',N'ScénariosContrainteCoût',  7,N'ModifiedByResourceName',         N'NomRessourceModification',           N'src',N'src.ModifiedByResourceName',         N'MAPPED'),
    (N'CostConstraintScenarios',N'ScénariosContrainteCoût',  8,N'ModifiedDate',                   N'DateModification',                   N'src',N'src.ModifiedDate',                   N'MAPPED'),
    (N'CostConstraintScenarios',N'ScénariosContrainteCoût',  9,N'ScenarioDescription',            N'DescriptionScénario',                N'src',N'src.ScenarioDescription',            N'MAPPED'),
    (N'CostConstraintScenarios',N'ScénariosContrainteCoût', 10,N'ScenarioUID',                    N'IdScénario',                         N'src',N'src.ScenarioUID',                    N'MAPPED'),
    (N'CostConstraintScenarios',N'ScénariosContrainteCoût', 11,N'ScenarioName',                   N'NomScénario',                        N'src',N'src.ScenarioName',                   N'MAPPED'),
    (N'CostConstraintScenarios',N'ScénariosContrainteCoût', 12,N'SelectedProjectsCost',           N'CoûtProjetsSélectionnés',            N'src',N'src.SelectedProjectsCost',           N'MAPPED'),
    (N'CostConstraintScenarios',N'ScénariosContrainteCoût', 13,N'SelectedProjectsPriority',       N'PrioritéProjetSélectionnée',         N'src',N'src.SelectedProjectsPriority',       N'MAPPED'),
    (N'CostConstraintScenarios',N'ScénariosContrainteCoût', 14,N'UnselectedProjectsCost',         N'CoûtProjetsNonSélectionné',          N'src',N'src.UnselectedProjectsCost',         N'MAPPED'),
    (N'CostConstraintScenarios',N'ScénariosContrainteCoût', 15,N'UnselectedProjectsPriority',     N'PrioritéProjetNonSélectionnée',      N'src',N'src.UnselectedProjectsPriority',     N'MAPPED'),
    (N'CostConstraintScenarios',N'ScénariosContrainteCoût', 16,N'UseDependencies',                N'UtiliserDépendances',                N'src',N'src.UseDependencies',                N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

/* ---- ResourceConstraintScenarios ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'ResourceConstraintScenarios',N'ScénariosContrainteRessources',  1,N'AllocationThreshold',          N'SeuilRépartition',                   N'src',N'src.AllocationThreshold',          N'MAPPED'),
    (N'ResourceConstraintScenarios',N'ScénariosContrainteRessources',  2,N'AnalysisUID',                  N'IdAnalyse',                          N'src',N'src.AnalysisUID',                  N'MAPPED'),
    (N'ResourceConstraintScenarios',N'ScénariosContrainteRessources',  3,N'AnalysisName',                 N'NomAnalyse',                         N'src',N'src.AnalysisName',                 N'MAPPED'),
    (N'ResourceConstraintScenarios',N'ScénariosContrainteRessources',  4,N'ConstraintType',               N'TypeContrainte',                     N'src',N'src.ConstraintType',               N'MAPPED'),
    (N'ResourceConstraintScenarios',N'ScénariosContrainteRessources',  5,N'ConstraintValue',              N'ValeurContrainte',                   N'src',N'src.ConstraintValue',              N'MAPPED'),
    (N'ResourceConstraintScenarios',N'ScénariosContrainteRessources',  6,N'CostConstraintScenarioUID',    N'IdScénarioContrainteCoût',           N'src',N'src.CostConstraintScenarioUID',    N'MAPPED'),
    (N'ResourceConstraintScenarios',N'ScénariosContrainteRessources',  7,N'CostConstraintScenarioName',   N'NomScénarioContrainteCoût',          N'src',N'src.CostConstraintScenarioName',   N'MAPPED'),
    (N'ResourceConstraintScenarios',N'ScénariosContrainteRessources',  8,N'CreatedByResourceUID',         N'IdRessourceCréation',                N'src',N'src.CreatedByResourceUID',         N'MAPPED'),
    (N'ResourceConstraintScenarios',N'ScénariosContrainteRessources',  9,N'CreatedByResourceName',        N'NomRessourceCréation',               N'src',N'src.CreatedByResourceName',        N'MAPPED'),
    (N'ResourceConstraintScenarios',N'ScénariosContrainteRessources', 10,N'CreatedDate',                  N'DateCréation',                       N'src',N'src.CreatedDate',                  N'MAPPED'),
    (N'ResourceConstraintScenarios',N'ScénariosContrainteRessources', 11,N'EnforceProjectDependencies',   N'AppliquerDépendancesProjet',         N'src',N'src.EnforceProjectDependencies',   N'MAPPED'),
    (N'ResourceConstraintScenarios',N'ScénariosContrainteRessources', 12,N'EnforceSchedulingConstraints', N'AppliquerContraintesPlanification',  N'src',N'src.EnforceSchedulingConstraints', N'MAPPED'),
    (N'ResourceConstraintScenarios',N'ScénariosContrainteRessources', 13,N'HiringType',                   N'TypeEmbauche',                       N'src',N'src.HiringType',                   N'MAPPED'),
    (N'ResourceConstraintScenarios',N'ScénariosContrainteRessources', 14,N'ModifiedByResourceUID',        N'IdRessourceModification',            N'src',N'src.ModifiedByResourceUID',        N'MAPPED'),
    (N'ResourceConstraintScenarios',N'ScénariosContrainteRessources', 15,N'ModifiedByResourceName',       N'NomRessourceModification',           N'src',N'src.ModifiedByResourceName',       N'MAPPED'),
    (N'ResourceConstraintScenarios',N'ScénariosContrainteRessources', 16,N'ModifiedDate',                 N'DateModification',                   N'src',N'src.ModifiedDate',                 N'MAPPED'),
    (N'ResourceConstraintScenarios',N'ScénariosContrainteRessources', 17,N'RateTable',                    N'TableTaux',                          N'src',N'src.RateTable',                    N'MAPPED'),
    (N'ResourceConstraintScenarios',N'ScénariosContrainteRessources', 18,N'ScenarioDescription',          N'DescriptionScénario',                N'src',N'src.ScenarioDescription',          N'MAPPED'),
    (N'ResourceConstraintScenarios',N'ScénariosContrainteRessources', 19,N'ScenarioUID',                  N'IdScénario',                         N'src',N'src.ScenarioUID',                  N'MAPPED'),
    (N'ResourceConstraintScenarios',N'ScénariosContrainteRessources', 20,N'ScenarioName',                 N'NomScénario',                        N'src',N'src.ScenarioName',                 N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

/* ---- ResourceScenarioProjects ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'ResourceScenarioProjects',N'ProjetsScénarioRessources',  1,N'AbsolutePriority',          N'PrioritéAbsolue',            N'src',N'src.AbsolutePriority',          N'MAPPED'),
    (N'ResourceScenarioProjects',N'ProjetsScénarioRessources',  2,N'AnalysisUID',               N'IdAnalyse',                  N'src',N'src.AnalysisUID',               N'MAPPED'),
    (N'ResourceScenarioProjects',N'ProjetsScénarioRessources',  3,N'AnalysisName',              N'NomAnalyse',                 N'src',N'src.AnalysisName',              N'MAPPED'),
    (N'ResourceScenarioProjects',N'ProjetsScénarioRessources',  4,N'CostConstraintScenarioUID', N'IdScénarioContrainteCoût',   N'src',N'src.CostConstraintScenarioUID', N'MAPPED'),
    (N'ResourceScenarioProjects',N'ProjetsScénarioRessources',  5,N'CostConstraintScenarioName',N'NomScénarioContrainteCoût',  N'src',N'src.CostConstraintScenarioName',N'MAPPED'),
    (N'ResourceScenarioProjects',N'ProjetsScénarioRessources',  6,N'ForceAliasLookupTableUID',  N'IdTableChoixAliasForçé',     N'src',N'src.ForceAliasLookupTableUID',  N'MAPPED'),
    (N'ResourceScenarioProjects',N'ProjetsScénarioRessources',  7,N'ForceAliasLookupTableName', N'NomTableChoixAliasForçé',    N'src',N'src.ForceAliasLookupTableName', N'MAPPED'),
    (N'ResourceScenarioProjects',N'ProjetsScénarioRessources',  8,N'ForceStatus',               N'ÉtatForçé',                  N'src',N'src.ForceStatus',               N'MAPPED'),
    (N'ResourceScenarioProjects',N'ProjetsScénarioRessources',  9,N'HardConstraintValue',       N'ValeurContrainteImpérative', N'src',N'src.HardConstraintValue',       N'MAPPED'),
    (N'ResourceScenarioProjects',N'ProjetsScénarioRessources', 10,N'NewStartDate',              N'NouvelleDateDébut',          N'src',N'src.NewStartDate',              N'MAPPED'),
    (N'ResourceScenarioProjects',N'ProjetsScénarioRessources', 11,N'Priority',                  N'Priorité',                   N'src',N'src.Priority',                  N'MAPPED'),
    (N'ResourceScenarioProjects',N'ProjetsScénarioRessources', 12,N'ProjectUID',                N'IdProjet',                   N'src',N'src.ProjectUID',                N'MAPPED'),
    (N'ResourceScenarioProjects',N'ProjetsScénarioRessources', 13,N'ProjectName',               N'NomProjet',                  N'src',N'src.ProjectName',               N'MAPPED'),
    (N'ResourceScenarioProjects',N'ProjetsScénarioRessources', 14,N'ResourceCost',              N'CoûtRessource',              N'src',N'src.ResourceCost',              N'MAPPED'),
    (N'ResourceScenarioProjects',N'ProjetsScénarioRessources', 15,N'ResourceWork',              N'TravailRessource',           N'src',N'src.ResourceWork',              N'MAPPED'),
    (N'ResourceScenarioProjects',N'ProjetsScénarioRessources', 16,N'ScenarioUID',               N'IdScénario',                 N'src',N'src.ScenarioUID',               N'MAPPED'),
    (N'ResourceScenarioProjects',N'ProjetsScénarioRessources', 17,N'ScenarioName',              N'NomScénario',                N'src',N'src.ScenarioName',              N'MAPPED'),
    (N'ResourceScenarioProjects',N'ProjetsScénarioRessources', 18,N'Status',                    N'Statut',                     N'src',N'src.Status',                    N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

RAISERROR(N'  Portfolio group done.', 0, 1) WITH NOWAIT;
GO

/* ---- Prioritizations ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'Prioritizations',N'DéfinitionsPriorités',  1,N'ConsistencyRatio',          N'TauxCohérence',                       N'src',N'src.ConsistencyRatio',          N'MAPPED'),
    (N'Prioritizations',N'DéfinitionsPriorités',  2,N'CreatedByResourceUID',      N'IdRessourceCréation',                 N'src',N'src.CreatedByResourceUID',      N'MAPPED'),
    (N'Prioritizations',N'DéfinitionsPriorités',  3,N'CreatedByResourceName',     N'NomRessourceCréation',                N'src',N'src.CreatedByResourceName',     N'MAPPED'),
    (N'Prioritizations',N'DéfinitionsPriorités',  4,N'DepartmentUID',             N'IdService',                           N'src',N'src.DepartmentUID',             N'MAPPED'),
    (N'Prioritizations',N'DéfinitionsPriorités',  5,N'DepartmentName',            N'NomService',                          N'src',N'src.DepartmentName',            N'MAPPED'),
    (N'Prioritizations',N'DéfinitionsPriorités',  6,N'ModifiedByResourceUID',     N'IdRessourceModification',             N'src',N'src.ModifiedByResourceUID',     N'MAPPED'),
    (N'Prioritizations',N'DéfinitionsPriorités',  7,N'ModifiedByResourceName',    N'NomRessourceModification',            N'src',N'src.ModifiedByResourceName',    N'MAPPED'),
    (N'Prioritizations',N'DéfinitionsPriorités',  8,N'CreatedDate',               N'DateCréationDéfinitionPriorités',     N'src',N'src.CreatedDate',               N'MAPPED'),
    (N'Prioritizations',N'DéfinitionsPriorités',  9,N'PrioritizationDescription', N'DescriptionDéfinitionPriorités',      N'src',N'src.PrioritizationDescription', N'MAPPED'),
    (N'Prioritizations',N'DéfinitionsPriorités', 10,N'PrioritizationUID',         N'IdDéfinitionPriorités',               N'src',N'src.PrioritizationUID',         N'MAPPED'),
    (N'Prioritizations',N'DéfinitionsPriorités', 11,N'PrioritizationIsManual',    N'DéfinitionPrioritésEstManuelle',      N'src',N'src.PrioritizationIsManual',    N'MAPPED'),
    (N'Prioritizations',N'DéfinitionsPriorités', 12,N'ModifiedDate',              N'DateModificationDéfinitionPriorités', N'src',N'src.ModifiedDate',              N'MAPPED'),
    (N'Prioritizations',N'DéfinitionsPriorités', 13,N'PrioritizationName',        N'NomDéfinitionPriorités',              N'src',N'src.PrioritizationName',        N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

/* ---- PrioritizationDrivers ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'PrioritizationDrivers',N'AxesDéfinitionsPriorités',  1,N'BusinessDriverUID',       N'IdAxeStratégiqueEntreprise',         N'src',N'src.BusinessDriverUID',       N'MAPPED'),
    (N'PrioritizationDrivers',N'AxesDéfinitionsPriorités',  2,N'BusinessDriverName',      N'NomAxeStratégiqueEntreprise',        N'src',N'src.BusinessDriverName',      N'MAPPED'),
    (N'PrioritizationDrivers',N'AxesDéfinitionsPriorités',  3,N'BusinessDriverPriority',  N'PrioritéAxeStratégiqueEntreprise',   N'src',N'src.BusinessDriverPriority',  N'MAPPED'),
    (N'PrioritizationDrivers',N'AxesDéfinitionsPriorités',  4,N'PrioritizationUID',       N'IdDéfinitionPriorités',              N'src',N'src.PrioritizationUID',       N'MAPPED'),
    (N'PrioritizationDrivers',N'AxesDéfinitionsPriorités',  5,N'PrioritizationName',      N'NomDéfinitionPriorités',             N'src',N'src.PrioritizationName',      N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

/* ---- PrioritizationDriverRelations ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'PrioritizationDriverRelations',N'RelationsAxesDéfinitionsPriorités',  1,N'BusinessDriver1UID',    N'IdAxeStratégiqueEntreprise1',   N'src',N'src.BusinessDriver1UID',    N'MAPPED'),
    (N'PrioritizationDriverRelations',N'RelationsAxesDéfinitionsPriorités',  2,N'BusinessDriver1Name',   N'NomAxeStratégiqueEntreprise1',  N'src',N'src.BusinessDriver1Name',   N'MAPPED'),
    (N'PrioritizationDriverRelations',N'RelationsAxesDéfinitionsPriorités',  3,N'BusinessDriver2UID',    N'IdAxeStratégiqueEntreprise2',   N'src',N'src.BusinessDriver2UID',    N'MAPPED'),
    (N'PrioritizationDriverRelations',N'RelationsAxesDéfinitionsPriorités',  4,N'BusinessDriver2Name',   N'NomAxeStratégiqueEntreprise2',  N'src',N'src.BusinessDriver2Name',   N'MAPPED'),
    (N'PrioritizationDriverRelations',N'RelationsAxesDéfinitionsPriorités',  5,N'PrioritizationUID',     N'IdDéfinitionPriorités',         N'src',N'src.PrioritizationUID',     N'MAPPED'),
    (N'PrioritizationDriverRelations',N'RelationsAxesDéfinitionsPriorités',  6,N'PrioritizationName',    N'NomDéfinitionPriorités',        N'src',N'src.PrioritizationName',    N'MAPPED'),
    (N'PrioritizationDriverRelations',N'RelationsAxesDéfinitionsPriorités',  7,N'RelationValue',         N'ValeurRelation',                N'src',N'src.RelationValue',         N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

/* ---- BusinessDrivers ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'BusinessDrivers',N'AxesStratégiquesEntreprise',  1,N'CreatedDate',                 N'DateCréationAxeStratégiqueEntreprise',       N'src',N'src.CreatedDate',                 N'MAPPED'),
    (N'BusinessDrivers',N'AxesStratégiquesEntreprise',  2,N'BusinessDriverDescription',   N'DescriptionAxeStratégiqueEntreprise',        N'src',N'src.BusinessDriverDescription',   N'MAPPED'),
    (N'BusinessDrivers',N'AxesStratégiquesEntreprise',  3,N'BusinessDriverUID',           N'IdAxeStratégiqueEntreprise',                 N'src',N'src.BusinessDriverUID',           N'MAPPED'),
    (N'BusinessDrivers',N'AxesStratégiquesEntreprise',  4,N'BusinessDriverIsActive',      N'AxeStratégiqueEntrepriseEstActif',           N'src',N'src.BusinessDriverIsActive',      N'MAPPED'),
    (N'BusinessDrivers',N'AxesStratégiquesEntreprise',  5,N'ModifiedDate',                N'DateModificationAxeStratégiqueEntreprise',   N'src',N'src.ModifiedDate',                N'MAPPED'),
    (N'BusinessDrivers',N'AxesStratégiquesEntreprise',  6,N'BusinessDriverName',          N'NomAxeStratégiqueEntreprise',                N'src',N'src.BusinessDriverName',          N'MAPPED'),
    (N'BusinessDrivers',N'AxesStratégiquesEntreprise',  7,N'CreatedByResourceUID',        N'IdRessourceCréation',                       N'src',N'src.CreatedByResourceUID',        N'MAPPED'),
    (N'BusinessDrivers',N'AxesStratégiquesEntreprise',  8,N'CreatedByResourceName',       N'NomRessourceCréation',                      N'src',N'src.CreatedByResourceName',       N'MAPPED'),
    (N'BusinessDrivers',N'AxesStratégiquesEntreprise',  9,N'ImpactDescriptionExtreme',    N'DescriptionImpactExtrême',                  N'src',N'src.ImpactDescriptionExtreme',    N'MAPPED'),
    (N'BusinessDrivers',N'AxesStratégiquesEntreprise', 10,N'ImpactDescriptionLow',        N'DescriptionImpactFaible',                   N'src',N'src.ImpactDescriptionLow',        N'MAPPED'),
    (N'BusinessDrivers',N'AxesStratégiquesEntreprise', 11,N'ImpactDescriptionModerate',   N'DescriptionImpactModéré',                   N'src',N'src.ImpactDescriptionModerate',   N'MAPPED'),
    (N'BusinessDrivers',N'AxesStratégiquesEntreprise', 12,N'ImpactDescriptionNone',       N'DescriptionImpactAucun',                    N'src',N'src.ImpactDescriptionNone',       N'MAPPED'),
    (N'BusinessDrivers',N'AxesStratégiquesEntreprise', 13,N'ImpactDescriptionStrong',     N'DescriptionImpactFort',                     N'src',N'src.ImpactDescriptionStrong',     N'MAPPED'),
    (N'BusinessDrivers',N'AxesStratégiquesEntreprise', 14,N'ModifiedByResourceUID',       N'IdRessourceModification',                   N'src',N'src.ModifiedByResourceUID',       N'MAPPED'),
    (N'BusinessDrivers',N'AxesStratégiquesEntreprise', 15,N'ModifiedByResourceName',      N'NomRessourceModification',                  N'src',N'src.ModifiedByResourceName',      N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

/* ---- BusinessDriverDepartments ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'BusinessDriverDepartments',N'ServicesAxesStratégiques',  1,N'BusinessDriverUID',   N'IdAxeStratégiqueEntreprise',  N'src',N'src.BusinessDriverUID',   N'MAPPED'),
    (N'BusinessDriverDepartments',N'ServicesAxesStratégiques',  2,N'BusinessDriverName',  N'NomAxeStratégiqueEntreprise', N'src',N'src.BusinessDriverName',  N'MAPPED'),
    (N'BusinessDriverDepartments',N'ServicesAxesStratégiques',  3,N'DepartmentUID',       N'IdService',                   N'src',N'src.DepartmentUID',       N'MAPPED'),
    (N'BusinessDriverDepartments',N'ServicesAxesStratégiques',  4,N'DepartmentName',      N'NomService',                  N'src',N'src.DepartmentName',      N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

RAISERROR(N'  Prioritizations & BusinessDrivers done.', 0, 1) WITH NOWAIT;
GO

/* ---- Engagements ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'Engagements',N'Engagements',  1,N'CommittedFinishDate',       N'DateFinValidée',               N'src',N'src.CommittedFinishDate',       N'MAPPED'),
    (N'Engagements',N'Engagements',  2,N'CommittedMaxUnits',         N'NbMaxUnitésValidées',          N'src',N'src.CommittedMaxUnits',         N'MAPPED'),
    (N'Engagements',N'Engagements',  3,N'CommittedStartDate',        N'DateDébutValidée',             N'src',N'src.CommittedStartDate',        N'MAPPED'),
    (N'Engagements',N'Engagements',  4,N'CommittedWork',             N'TravailValidé',                N'src',N'src.CommittedWork',             N'MAPPED'),
    (N'Engagements',N'Engagements',  5,N'CreatedDate',               N'DateCréationEngagement',       N'src',N'src.CreatedDate',               N'MAPPED'),
    (N'Engagements',N'Engagements',  6,N'EngagementUID',             N'IDEngagement',                 N'src',N'src.EngagementUID',             N'MAPPED'),
    (N'Engagements',N'Engagements',  7,N'ModifiedDate',              N'DateModificationEngagement',   N'src',N'src.ModifiedDate',              N'MAPPED'),
    (N'Engagements',N'Engagements',  8,N'EngagementName',            N'NomEngagement',                N'src',N'src.EngagementName',            N'MAPPED'),
    (N'Engagements',N'Engagements',  9,N'ReviewedDate',              N'DateRévisionEngagement',       N'src',N'src.ReviewedDate',              N'MAPPED'),
    (N'Engagements',N'Engagements', 10,N'Status',                    N'ÉtatEngagement',               N'src',N'src.Status',                    N'MAPPED'),
    (N'Engagements',N'Engagements', 11,N'SubmittedDate',             N'DateSoumissionEngagement',     N'src',N'src.SubmittedDate',             N'MAPPED'),
    (N'Engagements',N'Engagements', 12,N'ModifiedByResourceUID',     N'IdRessourceModification',      N'src',N'src.ModifiedByResourceUID',     N'MAPPED'),
    (N'Engagements',N'Engagements', 13,N'ModifiedByResourceName',    N'NomRessourceModification',     N'src',N'src.ModifiedByResourceName',    N'MAPPED'),
    (N'Engagements',N'Engagements', 14,N'ProjectUID',                N'IdProjet',                     N'src',N'src.ProjectUID',                N'MAPPED'),
    (N'Engagements',N'Engagements', 15,N'ProjectName',               N'NomProjet',                    N'src',N'src.ProjectName',               N'MAPPED'),
    (N'Engagements',N'Engagements', 16,N'ProposedFinishDate',        N'DateFinProposée',              N'src',N'src.ProposedFinishDate',        N'MAPPED'),
    (N'Engagements',N'Engagements', 17,N'ProposedMaxUnits',          N'NbMaxUnitésProposées',         N'src',N'src.ProposedMaxUnits',          N'MAPPED'),
    (N'Engagements',N'Engagements', 18,N'ProposedStartDate',         N'DateDébutProposée',            N'src',N'src.ProposedStartDate',         N'MAPPED'),
    (N'Engagements',N'Engagements', 19,N'ProposedWork',              N'TravailProposé',               N'src',N'src.ProposedWork',              N'MAPPED'),
    (N'Engagements',N'Engagements', 20,N'ResourceUID',               N'IdRessource',                  N'src',N'src.ResourceUID',               N'MAPPED'),
    (N'Engagements',N'Engagements', 21,N'ResourceName',              N'NomRessource',                 N'src',N'src.ResourceName',              N'MAPPED'),
    (N'Engagements',N'Engagements', 22,N'ReviewedByResourceUID',     N'RévisionParIDRessource',       N'src',N'src.ReviewedByResourceUID',     N'MAPPED'),
    (N'Engagements',N'Engagements', 23,N'ReviewedByResourceName',    N'RévisionParNomRessource',      N'src',N'src.ReviewedByResourceName',    N'MAPPED'),
    (N'Engagements',N'Engagements', 24,N'SubmittedByResourceUID',    N'SoumisPar IDRessource',        N'src',N'src.SubmittedByResourceUID',    N'MAPPED'),
    (N'Engagements',N'Engagements', 25,N'SubmittedByResourceName',   N'SoumisPar NomRessource',       N'src',N'src.SubmittedByResourceName',   N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

/* ---- EngagementsComments ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'EngagementsComments',N'CommentairesEngagements',  1,N'AuthorUID',       N'IDAuteur',                  N'src',N'src.AuthorUID',       N'MAPPED'),
    (N'EngagementsComments',N'CommentairesEngagements',  2,N'AuthorName',      N'NomAuteur',                 N'src',N'src.AuthorName',      N'MAPPED'),
    (N'EngagementsComments',N'CommentairesEngagements',  3,N'CreatedDate',     N'DateCréationCommentaire',   N'src',N'src.CreatedDate',     N'MAPPED'),
    (N'EngagementsComments',N'CommentairesEngagements',  4,N'CommentUID',      N'IDCommentaire',             N'src',N'src.CommentUID',      N'MAPPED'),
    (N'EngagementsComments',N'CommentairesEngagements',  5,N'CommentMessage',  N'MessageCommentaire',        N'src',N'src.CommentMessage',  N'MAPPED'),
    (N'EngagementsComments',N'CommentairesEngagements',  6,N'EngagementUID',   N'IDEngagement',              N'src',N'src.EngagementUID',   N'MAPPED'),
    (N'EngagementsComments',N'CommentairesEngagements',  7,N'EngagementName',  N'NomEngagement',             N'src',N'src.EngagementName',  N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

/* ---- ProjectWorkflowStageDataSet ---- */
MERGE dic.EntityColumnPublication AS tgt
USING (VALUES
    (N'ProjectWorkflowStageDataSet',N'JeuDonnéesÉtapesFluxTravailProjet',  1,N'LastModifiedDate',      N'DateDernièreModification', N'src',N'src.LastModifiedDate',      N'MAPPED'),
    (N'ProjectWorkflowStageDataSet',N'JeuDonnéesÉtapesFluxTravailProjet',  2,N'LCID',                  N'LCID',                     N'src',N'src.LCID',                  N'MAPPED'),
    (N'ProjectWorkflowStageDataSet',N'JeuDonnéesÉtapesFluxTravailProjet',  3,N'PhaseDescription',      N'DescriptionPhase',         N'src',N'src.PhaseDescription',      N'MAPPED'),
    (N'ProjectWorkflowStageDataSet',N'JeuDonnéesÉtapesFluxTravailProjet',  4,N'PhaseName',             N'NomPhase',                 N'src',N'src.PhaseName',             N'MAPPED'),
    (N'ProjectWorkflowStageDataSet',N'JeuDonnéesÉtapesFluxTravailProjet',  5,N'ProjectId',             N'IdProjet',                 N'src',N'src.ProjectId',             N'MAPPED'),
    (N'ProjectWorkflowStageDataSet',N'JeuDonnéesÉtapesFluxTravailProjet',  6,N'ProjectName',           N'NomProjet',                N'src',N'src.ProjectName',           N'MAPPED'),
    (N'ProjectWorkflowStageDataSet',N'JeuDonnéesÉtapesFluxTravailProjet',  7,N'StageCompletionDate',   N'DateFinÉtape',             N'src',N'src.StageCompletionDate',   N'MAPPED'),
    (N'ProjectWorkflowStageDataSet',N'JeuDonnéesÉtapesFluxTravailProjet',  8,N'StageDescription',      N'DescriptionÉtape',         N'src',N'src.StageDescription',      N'MAPPED'),
    (N'ProjectWorkflowStageDataSet',N'JeuDonnéesÉtapesFluxTravailProjet',  9,N'StageEntryDate',        N'DateEntréeÉtape',          N'src',N'src.StageEntryDate',        N'MAPPED'),
    (N'ProjectWorkflowStageDataSet',N'JeuDonnéesÉtapesFluxTravailProjet', 10,N'StageId',               N'IdÉtape',                  N'src',N'src.StageId',               N'MAPPED'),
    (N'ProjectWorkflowStageDataSet',N'JeuDonnéesÉtapesFluxTravailProjet', 11,N'StageInformation',      N'InformationsÉtape',        N'src',N'src.StageInformation',      N'MAPPED'),
    (N'ProjectWorkflowStageDataSet',N'JeuDonnéesÉtapesFluxTravailProjet', 12,N'StageLastSubmitted',    N'DateDernierEnvoiÉtape',    N'src',N'src.StageLastSubmitted',    N'MAPPED'),
    (N'ProjectWorkflowStageDataSet',N'JeuDonnéesÉtapesFluxTravailProjet', 13,N'StageName',             N'NomÉtape',                 N'src',N'src.StageName',             N'MAPPED'),
    (N'ProjectWorkflowStageDataSet',N'JeuDonnéesÉtapesFluxTravailProjet', 14,N'StageOrder',            N'OrdreÉtape',               N'src',N'src.StageOrder',            N'MAPPED'),
    (N'ProjectWorkflowStageDataSet',N'JeuDonnéesÉtapesFluxTravailProjet', 15,N'StageStateDescription', N'DescriptionÉtatÉtape',     N'src',N'src.StageStateDescription', N'MAPPED'),
    (N'ProjectWorkflowStageDataSet',N'JeuDonnéesÉtapesFluxTravailProjet', 16,N'StageStatus',           N'ÉtatÉtape',                N'src',N'src.StageStatus',           N'MAPPED')
) AS src (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, SourceAlias, SourceExpression, MapStatus)
ON tgt.EntityName_EN=src.EntityName_EN AND tgt.Column_EN=src.Column_EN
WHEN NOT MATCHED THEN INSERT (EntityName_EN,EntityName_FR,ColumnPosition,Column_EN,Column_FR,SourceAlias,SourceExpression,MapStatus,IsPublished) VALUES(src.EntityName_EN,src.EntityName_FR,src.ColumnPosition,src.Column_EN,src.Column_FR,src.SourceAlias,src.SourceExpression,src.MapStatus,1)
WHEN MATCHED AND tgt.MapStatus NOT IN(N'MAPPED',N'NAVIGATION') THEN UPDATE SET EntityName_FR=src.EntityName_FR,ColumnPosition=src.ColumnPosition,Column_FR=src.Column_FR,SourceAlias=src.SourceAlias,SourceExpression=src.SourceExpression,MapStatus=src.MapStatus,IsPublished=1,UpdatedOn=sysdatetime(),UpdatedBy=suser_sname();

RAISERROR(N'  Engagements, EngagementsComments, ProjectWorkflowStageDataSet done.', 0, 1) WITH NOWAIT;
GO

/* ===========================================================================================
   FIN PHASE C — Validation rapide
   =========================================================================================== */
DECLARE @nBinding   int = (SELECT COUNT(*) FROM dic.EntityBinding);
DECLARE @nJoin      int = (SELECT COUNT(*) FROM dic.EntityJoin);
DECLARE @nCol       int = (SELECT COUNT(*) FROM dic.EntityColumnPublication);
DECLARE @nMapped    int = (SELECT COUNT(*) FROM dic.EntityColumnPublication WHERE MapStatus = N'MAPPED');
DECLARE @nNav       int = (SELECT COUNT(*) FROM dic.EntityColumnPublication WHERE MapStatus = N'NAVIGATION');
DECLARE @nUnmapped  int = (SELECT COUNT(*) FROM dic.EntityColumnPublication WHERE MapStatus = N'UNMAPPED');
DECLARE @nEntitiesWithCols int = (SELECT COUNT(DISTINCT EntityName_EN) FROM dic.EntityColumnPublication);

RAISERROR(N'=== v6_05b terminé ===', 0, 1) WITH NOWAIT;
RAISERROR(N'  dic.EntityBinding   : %d entités', 0, 1, @nBinding) WITH NOWAIT;
RAISERROR(N'  dic.EntityJoin      : %d jointures', 0, 1, @nJoin) WITH NOWAIT;
RAISERROR(N'  dic.EntityColumnPublication : %d colonnes (%d MAPPED / %d NAVIGATION / %d UNMAPPED)', 0, 1, @nCol, @nMapped, @nNav, @nUnmapped) WITH NOWAIT;
RAISERROR(N'  Entités avec colonnes : %d / 40', 0, 1, @nEntitiesWithCols) WITH NOWAIT;

IF @nUnmapped > 0
    RAISERROR(N'AVERTISSEMENT : %d colonnes UNMAPPED détectées — vérifier dic.EntityColumnPublication.', 16, 1, @nUnmapped);
ELSE
    RAISERROR(N'OK : aucune colonne UNMAPPED.', 0, 1) WITH NOWAIT;
GO
