/*=====================================================================================================================
    v6_04a_Create_Native_ProjectData_Views.sql
    Projet      : SmartBox
    Phase       : 04a - Vues ProjectData natives
    Role        : Créer les vues OData-like ProjectOnline depuis un snapshot figé dans la trousse V6.

    Notes V6
    - Ne depend plus de la BD de contenu au runtime.
    - Les couches internes tbx/tbx_fr/tbx_master sont intégrées dans ce script pour exécution SSMS directe.
    - Les vues publiques ProjectData.* sont regénérées depuis tbx.vw_* en excluant les champs personnalisés
      présents dans la BD content PSSE. Les champs personnalisés client seront ajoutés par une tranche ultérieure.
=====================================================================================================================*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb')
BEGIN
    THROW 66001, N'Exécuter ce script dans la base SmartBox cible.', 1;
END;

IF OBJECT_ID(N'cfg.Settings', N'U') IS NULL
    THROW 66002, N'cfg.Settings absente. Exécuter v6_02a avant v6_04a.', 1;

IF OBJECT_ID(N'log.usp_WriteScriptLog', N'P') IS NULL
    THROW 66003, N'log.usp_WriteScriptLog absente. Exécuter v6_02a avant v6_04a.', 1;

IF OBJECT_ID(N'src_pjrep.MSP_EpmProject_UserView', N'SN') IS NULL
    THROW 66004, N'Synonyme src_pjrep.MSP_EpmProject_UserView absent. Exécuter v6_03a.', 1;

/* Correctif 5: valider que les synonymes src_* pointent vers cfg.Settings.ContentDbName. */
IF NOT EXISTS
(
    SELECT 1
    FROM sys.synonyms AS syn
    JOIN cfg.Settings AS s ON s.SettingKey = N'ContentDbName'
    WHERE syn.object_id = OBJECT_ID(N'src_pjrep.MSP_EpmProject_UserView')
      AND (
              syn.base_object_name LIKE N'[[]' + s.SettingValue + N']%'
           OR syn.base_object_name LIKE s.SettingValue + N'.%'
          )
)
    THROW 66005, N'Les synonymes src_* ne pointent pas vers cfg.Settings.ContentDbName. Rejouer v6_03a après v6_02a.', 1;

IF SCHEMA_ID(N'ProjectData') IS NULL EXEC(N'CREATE SCHEMA ProjectData AUTHORIZATION dbo;');
IF SCHEMA_ID(N'tbx') IS NULL EXEC(N'CREATE SCHEMA tbx AUTHORIZATION dbo;');
IF SCHEMA_ID(N'tbx_fr') IS NULL EXEC(N'CREATE SCHEMA tbx_fr AUTHORIZATION dbo;');
IF SCHEMA_ID(N'tbx_master') IS NULL EXEC(N'CREATE SCHEMA tbx_master AUTHORIZATION dbo;');

IF OBJECT_ID(N'tempdb..#V6ScriptContext') IS NOT NULL DROP TABLE #V6ScriptContext;

CREATE TABLE #V6ScriptContext
(
    RunId uniqueidentifier NOT NULL,
    ScriptName sysname NOT NULL
);

INSERT INTO #V6ScriptContext (RunId, ScriptName)
VALUES (newid(), N'v6_04a_Create_Native_ProjectData_Views.sql');

DECLARE @RunId uniqueidentifier = (SELECT RunId FROM #V6ScriptContext);
DECLARE @ScriptName sysname = (SELECT ScriptName FROM #V6ScriptContext);
DECLARE @DropSql nvarchar(max);
DECLARE @ViewDefinitionMode nvarchar(100);
DECLARE @FrozenViewSnapshotName nvarchar(260);

SELECT @ViewDefinitionMode = NULLIF(LTRIM(RTRIM(SettingValue)), N'')
FROM cfg.Settings
WHERE SettingKey = N'ViewDefinitionMode';

SELECT @FrozenViewSnapshotName = NULLIF(LTRIM(RTRIM(SettingValue)), N'')
FROM cfg.Settings
WHERE SettingKey = N'FrozenViewSnapshotName';

SET @ViewDefinitionMode = ISNULL(@ViewDefinitionMode, N'FROZEN_SNAPSHOT');

/* Auto-dériver FrozenViewSnapshotName depuis ContentDbName si absent (convention portabilité :
   v6_04a_Frozen_<ContentDbName>_Internal_Views.sql). Défini par v6_02a lors du déploiement initial. */
IF @FrozenViewSnapshotName IS NULL
BEGIN
    DECLARE @_ContentDbForSnap sysname;
    SELECT @_ContentDbForSnap = NULLIF(LTRIM(RTRIM(SettingValue)), N'')
    FROM cfg.Settings WHERE SettingKey = N'ContentDbName';
    IF @_ContentDbForSnap IS NOT NULL
        SET @FrozenViewSnapshotName = CONCAT(N'v6_04a_Frozen_', @_ContentDbForSnap, N'_Internal_Views.sql');
END;

IF @ViewDefinitionMode <> N'FROZEN_SNAPSHOT'
    THROW 66008, N'v6_04a supporte actuellement seulement cfg.Settings.ViewDefinitionMode = FROZEN_SNAPSHOT.', 1;

IF @FrozenViewSnapshotName IS NULL OR LTRIM(RTRIM(@FrozenViewSnapshotName)) = N''
    THROW 66009, N'cfg.Settings.FrozenViewSnapshotName non configuré. Exécuter v6_02a avant v6_04a.', 1;

EXEC log.usp_WriteScriptLog
    @RunId = @RunId,
    @ScriptName = @ScriptName,
    @ScriptVersion = N'V6-DRAFT',
    @Phase = N'START',
    @Severity = N'INFO',
    @Status = N'STARTED',
    @Message = N'Début création des vues natives depuis le snapshot figé V6.';

SELECT @DropSql = STRING_AGG
(
    CONVERT(nvarchar(max), N'DROP VIEW ' + QUOTENAME(target_schema.name) + N'.' + QUOTENAME(target_view.name) + N';'),
    CHAR(13) + CHAR(10)
)
WITHIN GROUP
(
    ORDER BY
        CASE target_schema.name
            WHEN N'ProjectData' THEN 1
            WHEN N'tbx_fr' THEN 2
            WHEN N'tbx' THEN 3
            WHEN N'tbx_master' THEN 4
            ELSE 9
        END,
        target_view.name
)
FROM sys.views AS target_view
JOIN sys.schemas AS target_schema
    ON target_schema.schema_id = target_view.schema_id
WHERE target_schema.name IN (N'ProjectData', N'tbx', N'tbx_fr', N'tbx_master');

IF @DropSql IS NOT NULL
    EXEC sys.sp_executesql @DropSql;
GO

/*=====================================================================================================================
    v6_04a_Frozen_SP_SPR_POC_Contenu_Internal_Views.sql
    Generated from SP_SPR_POC_Contenu on 2026-04-21.
    Frozen internal view définitions for SmartBox V6.
    Do not edit manually; regenerate deliberately when the reference changes.
=====================================================================================================================*/

CREATE   VIEW tbx.[vw_AssignmentBaselines_src]
AS
SELECT
    [src].*,
    [src].[AssignmentBaselineBudgetCost] AS [x_AssignmentBaselineBudgetCost],
    [src].[AssignmentBaselineBudgetMaterialWork] AS [x_AssignmentBaselineBudgetMaterialWork],
    [src].[AssignmentBaselineBudgetWork] AS [x_AssignmentBaselineBudgetWork],
    [src].[AssignmentBaselineCost] AS [x_AssignmentBaselineCost],
    [src].[AssignmentBaselineFinishDate] AS [x_AssignmentBaselineFinishDate],
    [src].[AssignmentBaselineMaterialWork] AS [x_AssignmentBaselineMaterialWork],
    [src].[AssignmentBaselineModifiedDate] AS [x_AssignmentBaselineModifiedDate],
    [src].[AssignmentBaselineStartDate] AS [x_AssignmentBaselineStartDate],
    [src].[AssignmentBaselineWork] AS [x_AssignmentBaselineWork],
    [src].[AssignmentUID] AS [x_AssignmentId],
    [src].[AssignmentType] AS [x_AssignmentType],
    [src].[BaselineNumber] AS [x_BaselineNumber],
    [src].[ProjectUID] AS [x_ProjectId],
    [prj].[ProjectName] AS [x_ProjectName],
    [src].[TaskUID] AS [x_TaskId],
    [tsk].[TaskName] AS [x_TaskName]
FROM src_pjrep.MSP_EpmAssignmentBaseline AS [src]
LEFT JOIN src_pjrep.MSP_EpmProject_UserView AS [prj]
        ON [prj].[ProjectUID] = [src].[ProjectUID]
      LEFT JOIN src_pjrep.MSP_EpmTask_UserView AS [tsk]
        ON [tsk].[TaskUID] = [src].[TaskUID];
GO

CREATE   VIEW tbx.[vw_AssignmentBaselineTimephasedDataSet_src]
AS
SELECT
    [src].*,
    [src].[AssignmentBaselineBudgetCost] AS [x_AssignmentBaselineBudgetCost],
    [src].[AssignmentBaselineBudgetMaterialWork] AS [x_AssignmentBaselineBudgetMaterialWork],
    [src].[AssignmentBaselineBudgetWork] AS [x_AssignmentBaselineBudgetWork],
    [src].[AssignmentBaselineCost] AS [x_AssignmentBaselineCost],
    [src].[AssignmentBaselineMaterialWork] AS [x_AssignmentBaselineMaterialWork],
    [src].[AssignmentBaselineModifiedDate] AS [x_AssignmentBaselineModifiedDate],
    [src].[AssignmentBaselineWork] AS [x_AssignmentBaselineWork],
    [src].[AssignmentUID] AS [x_AssignmentId],
    [src].[BaselineNumber] AS [x_BaselineNumber],
    [src].[FiscalPeriodUID] AS [x_FiscalPeriodId],
    [src].[ProjectUID] AS [x_ProjectId],
    [prj].[ProjectName] AS [x_ProjectName],
    [asg].[ResourceUID] AS [x_ResourceId],
    [src].[TaskUID] AS [x_TaskId],
    [tsk].[TaskName] AS [x_TaskName],
    [src].[TimeByDay] AS [x_TimeByDay]
FROM src_pjrep.MSP_EpmAssignmentBaselineByDay AS [src]
LEFT JOIN src_pjrep.MSP_EpmAssignment_UserView AS [asg]
        ON [asg].[AssignmentUID] = [src].[AssignmentUID]
      LEFT JOIN src_pjrep.MSP_EpmProject_UserView AS [prj]
        ON [prj].[ProjectUID] = [src].[ProjectUID]
      LEFT JOIN src_pjrep.MSP_EpmTask_UserView AS [tsk]
        ON [tsk].[TaskUID] = [src].[TaskUID];
GO

CREATE   VIEW tbx.[vw_Assignments_src]
AS
SELECT
    [src].*,
    [aau].[AssignmentAllUpdatesApplied] AS [x_AssignmentAllUpdatesApplied],
    [abk].[AssignmentBookingDescription] AS [x_AssignmentBookingDescription],
    [abk].[AssignmentBookingName] AS [x_AssignmentBookingName],
    [src].[AssignmentUID] AS [x_AssignmentId],
    [aau].[AssignmentUpdatesAppliedDate] AS [x_AssignmentUpdatesAppliedDate],
    [src].[ProjectUID] AS [x_ProjectId],
    [prj].[ProjectName] AS [x_ProjectName],
    [src].[ResourceUID] AS [x_ResourceId],
    [res].[ResourceName] AS [x_ResourceName],
    [src].[TaskUID] AS [x_TaskId],
    [tsk].[TaskName] AS [x_TaskName],
    [src].[TimesheetClassUID] AS [x_TimesheetClassId],
    [aty].[TypeDescription] AS [x_TypeDescription],
    [aty].[TypeName] AS [x_TypeName]
FROM src_pjrep.MSP_EpmAssignment_UserView AS [src]
LEFT JOIN src_pjrep.MSP_EpmAssignmentBooking AS [abk]
        ON [abk].[AssignmentBookingID] = [src].[AssignmentBookingID]
      LEFT JOIN src_pjrep.MSP_EpmAssignmentsApplied_UserView AS [aau]
        ON [aau].[AssignmentUID] = [src].[AssignmentUID]
      LEFT JOIN src_pjrep.MSP_EpmAssignmentType AS [aty]
        ON [aty].[AssignmentType] = [src].[AssignmentType]
      LEFT JOIN src_pjrep.MSP_EpmProject_UserView AS [prj]
        ON [prj].[ProjectUID] = [src].[ProjectUID]
      LEFT JOIN src_pjrep.MSP_EpmTask_UserView AS [tsk]
        ON [tsk].[TaskUID] = [src].[TaskUID]
      LEFT JOIN src_pjrep.MSP_EpmResource_UserView AS [res]
        ON [res].[ResourceUID] = [src].[ResourceUID];
GO

CREATE   VIEW tbx.[vw_AssignmentTimephasedDataSet_src]
AS
SELECT
    [src].*,
    [src].[AssignmentActualCost] AS [x_AssignmentActualCost],
    [src].[AssignmentActualOvertimeCost] AS [x_AssignmentActualOvertimeCost],
    [src].[AssignmentActualOvertimeWork] AS [x_AssignmentActualOvertimeWork],
    [src].[AssignmentActualRegularCost] AS [x_AssignmentActualRegularCost],
    [src].[AssignmentActualRegularWork] AS [x_AssignmentActualRegularWork],
    [src].[AssignmentActualWork] AS [x_AssignmentActualWork],
    [src].[AssignmentBudgetCost] AS [x_AssignmentBudgetCost],
    [src].[AssignmentBudgetMaterialWork] AS [x_AssignmentBudgetMaterialWork],
    [src].[AssignmentBudgetWork] AS [x_AssignmentBudgetWork],
    [src].[AssignmentCombinedWork] AS [x_AssignmentCombinedWork],
    [src].[AssignmentCost] AS [x_AssignmentCost],
    [src].[AssignmentUID] AS [x_AssignmentId],
    [src].[AssignmentMaterialActualWork] AS [x_AssignmentMaterialActualWork],
    [src].[AssignmentMaterialWork] AS [x_AssignmentMaterialWork],
    [asg].[AssignmentModifiedDate] AS [x_AssignmentModifiedDate],
    [src].[AssignmentOvertimeCost] AS [x_AssignmentOvertimeCost],
    [src].[AssignmentOvertimeWork] AS [x_AssignmentOvertimeWork],
    [src].[AssignmentRegularCost] AS [x_AssignmentRegularCost],
    [src].[AssignmentRegularWork] AS [x_AssignmentRegularWork],
    [src].[AssignmentRemainingCost] AS [x_AssignmentRemainingCost],
    [src].[AssignmentRemainingOvertimeCost] AS [x_AssignmentRemainingOvertimeCost],
    [src].[AssignmentRemainingOvertimeWork] AS [x_AssignmentRemainingOvertimeWork],
    [src].[AssignmentRemainingRegularCost] AS [x_AssignmentRemainingRegularCost],
    [src].[AssignmentRemainingRegularWork] AS [x_AssignmentRemainingRegularWork],
    [src].[AssignmentRemainingWork] AS [x_AssignmentRemainingWork],
    [src].[AssignmentResourcePlanWork] AS [x_AssignmentResourcePlanWork],
    [src].[AssignmentWork] AS [x_AssignmentWork],
    COALESCE([tbd].[FiscalPeriodUID], [fp].[FiscalPeriodUID]) AS [x_FiscalPeriodId],
    [src].[ProjectUID] AS [x_ProjectId],
    [prj].[ProjectName] AS [x_ProjectName],
    [asg].[ResourceUID] AS [x_ResourceId],
    [src].[TaskUID] AS [x_TaskId],
    [src].[TaskIsActive] AS [x_TaskIsActive],
    [tsk].[TaskName] AS [x_TaskName],
    [src].[TimeByDay] AS [x_TimeByDay]
FROM src_pjrep.MSP_EpmAssignmentByDay_UserView AS [src]
LEFT JOIN src_pjrep.MSP_EpmAssignment_UserView AS [asg]
        ON [asg].[AssignmentUID] = [src].[AssignmentUID]
      LEFT JOIN src_pjrep.MSP_EpmProject_UserView AS [prj]
        ON [prj].[ProjectUID] = [src].[ProjectUID]
      LEFT JOIN src_pjrep.MSP_EpmTask_UserView AS [tsk]
        ON [tsk].[TaskUID] = [src].[TaskUID]
      LEFT JOIN src_pjrep.MSP_TimeByDay AS [tbd]
        ON [tbd].[TimeByDay] = [src].[TimeByDay]
      LEFT JOIN src_pjrep.MSP_FiscalPeriods_ODATAView AS [fp]
        ON [fp].[FiscalPeriodUID] = [tbd].[FiscalPeriodUID];
GO

CREATE   VIEW tbx.[vw_BusinessDriverDepartments_src]
AS
SELECT
    [src].*,
    [src].[BusinessDriverUID] AS [x_BusinessDriverId],
    [src].[BusinessDriverName] AS [x_BusinessDriverName],
    [src].[DepartmentUID] AS [x_DepartmentId],
    [src].[DepartmentName] AS [x_DepartmentName]
FROM src_pjrep.MSP_EpmBusinessDriverDepartment_UserView AS [src];
GO

CREATE   VIEW tbx.[vw_BusinessDrivers_src]
AS
SELECT
    [src].*,
    [src].[CreatedDate] AS [x_BusinessDriverCreatedDate],
    [src].[BusinessDriverUID] AS [x_BusinessDriverId],
    [src].[ModifiedDate] AS [x_BusinessDriverModifiedDate],
    [src].[CreatedByResourceUID] AS [x_CreatedByResourceId],
    [src].[ModifiedByResourceUID] AS [x_ModifiedByResourceId]
FROM src_pjrep.MSP_EpmBusinessDriver_UserView AS [src];
GO

CREATE   VIEW tbx.[vw_CostConstraintScenarios_src]
AS
SELECT
    [src].*,
    [src].[AnalysisUID] AS [x_AnalysisId],
    [src].[CreatedByResourceUID] AS [x_CreatedByResourceId],
    [src].[ModifiedByResourceUID] AS [x_ModifiedByResourceId],
    [src].[ScenarioUID] AS [x_ScenarioId]
FROM src_pjrep.MSP_EpmPortfolioCostConstraintScenario_UserView AS [src];
GO

CREATE   VIEW tbx.[vw_CostScenarioProjects_src]
AS
SELECT
    [src].*,
    [src].[AnalysisUID] AS [x_AnalysisId],
    [src].[ForceAliasLookupTableUID] AS [x_ForceAliasLookupTableId],
    [src].[ProjectUID] AS [x_ProjectId],
    [src].[ScenarioUID] AS [x_ScenarioId]
FROM src_pjrep.MSP_EpmPortfolioCostConstraintProject_UserView AS [src];
GO

CREATE   VIEW tbx.[vw_Deliverables_src]
AS
SELECT
    [src].*,
    [src].[CreateByResource] AS [x_CreateByResource],
    [src].[CreatedDate] AS [x_CreatedDate],
    [src].[DeliverableID] AS [x_DeliverableId],
    [src].[Description] AS [x_Description],
    [src].[FinishDate] AS [x_FinishDate],
    [src].[IsFolder] AS [x_IsFolder],
    [src].[ItemRelativeUrlPath] AS [x_ItemRelativeUrlPath],
    [src].[ModifiedByResource] AS [x_ModifiedByResource],
    [src].[ModifiedDate] AS [x_ModifiedDate],
    [src].[ProjectUID] AS [x_ProjectId],
    [prj].[ProjectName] AS [x_ProjectName],
    [src].[StartDate] AS [x_StartDate],
    [src].[Title] AS [x_Title]
FROM src_pjrep.MSP_WssDeliverable AS [src]
LEFT JOIN src_pjrep.MSP_EpmProject_UserView AS [prj]
        ON [prj].[ProjectUID] = [src].[ProjectUID];
GO

CREATE   VIEW tbx.[vw_Engagements_src]
AS
SELECT
    [src].*,
    [src].[CreatedDate] AS [x_EngagementCreatedDate],
    [src].[EngagementUID] AS [x_EngagementId],
    [src].[ModifiedDate] AS [x_EngagementModifiedDate],
    [src].[ReviewedDate] AS [x_EngagementReviewedDate],
    [src].[Status] AS [x_EngagementStatus],
    [src].[SubmittedDate] AS [x_EngagementSubmittedDate],
    [src].[ModifiedByResourceUID] AS [x_ModifiedByResourceId],
    [src].[ProjectUID] AS [x_ProjectId],
    [src].[ResourceUID] AS [x_ResourceId],
    [src].[ReviewedByResourceUID] AS [x_ReviewedByResourceId],
    [src].[SubmittedByResourceUID] AS [x_SubmittedByResourceId]
FROM src_pjrep.MSP_EpmEngagements_UserView AS [src];
GO

CREATE   VIEW tbx.[vw_EngagementsComments_src]
AS
SELECT
    [src].*,
    [src].[AuthorUID] AS [x_AuthorId],
    [src].[CreatedDate] AS [x_CommentCreatedDate],
    [src].[CommentUID] AS [x_CommentId],
    [src].[EngagementUID] AS [x_EngagementId]
FROM src_pjrep.MSP_EpmEngagementComments_UserView AS [src];
GO

CREATE   VIEW tbx.[vw_EngagementsTimephasedDataSet_src]
AS
SELECT
    [src].*,
    [src].[CommittedUnits] AS [x_CommittedMaxUnits],
    [src].[CommittedWork] AS [x_CommittedWork],
    [src].[EngagementUID] AS [x_EngagementId],
    [src].[EngagementModifiedDate] AS [x_EngagementModifiedDate],
    [src].[EngagementName] AS [x_EngagementName],
    [src].[ProjectUID] AS [x_ProjectId],
    [prj].[ProjectName] AS [x_ProjectName],
    [src].[ProposedUnits] AS [x_ProposedMaxUnits],
    [src].[ProposedWork] AS [x_ProposedWork],
    [src].[ResourceUID] AS [x_ResourceId],
    [res].[ResourceName] AS [x_ResourceName],
    [src].[EngagementDate] AS [x_TimeByDay]
FROM src_pjrep.MSP_EpmEngagementByDay_UserView AS [src]
LEFT JOIN src_pjrep.MSP_EpmProject_UserView AS [prj]
        ON [prj].[ProjectUID] = [src].[ProjectUID]
      LEFT JOIN src_pjrep.MSP_EpmResource_UserView AS [res]
        ON [res].[ResourceUID] = [src].[ResourceUID];
GO

CREATE   VIEW tbx.[vw_FiscalPeriods_src]
AS
SELECT
    [src].*,
    [src].[CreatedDate] AS [x_CreatedDate],
    [src].[FiscalPeriodFinish] AS [x_FiscalPeriodFinish],
    [src].[FiscalPeriodUID] AS [x_FiscalPeriodId],
    [src].[ModifiedDate] AS [x_FiscalPeriodModifiedDate],
    [src].[FiscalPeriodName] AS [x_FiscalPeriodName],
    [src].[FiscalPeriodQuarter] AS [x_FiscalPeriodQuarter],
    [src].[FiscalPeriodStart] AS [x_FiscalPeriodStart],
    [src].[FiscalPeriodYear] AS [x_FiscalPeriodYear]
FROM src_pjrep.MSP_FiscalPeriods_ODATAView AS [src];
GO

CREATE   VIEW tbx.[vw_Issues_src]
AS
SELECT
    [src].*,
    [src].[AssignedToResource] AS [x_AssignedToResource],
    [src].[Category] AS [x_Category],
    [src].[CreateByResource] AS [x_CreateByResource],
    [src].[CreatedDate] AS [x_CreatedDate],
    [src].[Discussion] AS [x_Discussion],
    [src].[DueDate] AS [x_DueDate],
    [src].[IsFolder] AS [x_IsFolder],
    [src].[IssueID] AS [x_IssueId],
    [src].[ItemRelativeUrlPath] AS [x_ItemRelativeUrlPath],
    [src].[ModifiedByResource] AS [x_ModifiedByResource],
    [src].[ModifiedDate] AS [x_ModifiedDate],
    [src].[NumberOfAttachments] AS [x_NumberOfAttachments],
    [src].[Owner] AS [x_Owner],
    [src].[Priority] AS [x_Priority],
    [src].[ProjectUID] AS [x_ProjectId],
    [prj].[ProjectName] AS [x_ProjectName],
    [src].[Resolution] AS [x_Resolution],
    [src].[Status] AS [x_Status],
    [src].[Title] AS [x_Title]
FROM src_pjrep.MSP_WssIssue AS [src]
LEFT JOIN src_pjrep.MSP_EpmProject_UserView AS [prj]
        ON [prj].[ProjectUID] = [src].[ProjectUID];
GO

CREATE   VIEW tbx.[vw_IssueTaskAssociations_src]
AS
SELECT
    [src].*
FROM src_pjrep.MSP_WssIssueTaskAssociation_UserView AS [src];
GO

CREATE   VIEW tbx.[vw_PortfolioAnalyses_src]
AS
SELECT
    [src].*,
    [src].[AlternateProjectEndDateCustomFieldUID] AS [x_AlternateProjectEndDateCustomFieldId],
    [src].[AlternateProjectStartDateCustomFieldUID] AS [x_AlternateProjectStartDateCustomFieldId],
    [src].[AnalysisUID] AS [x_AnalysisId],
    [src].[CreatedByResourceUID] AS [x_CreatedByResourceId],
    [src].[DepartmentUID] AS [x_DepartmentId],
    [src].[FilterResourcesByRBSValueUID] AS [x_FilterResourcesByRBSValueId],
    [src].[ForcedInAliasLookupTableUID] AS [x_ForcedInAliasLookupTableId],
    [src].[ForcedOutAliasLookupTableUID] AS [x_ForcedOutAliasLookupTableId],
    [src].[HardConstraintCustomFieldUID] AS [x_HardConstraintCustomFieldId],
    [src].[ModifiedByResourceUID] AS [x_ModifiedByResourceId],
    [src].[PrioritizationUID] AS [x_PrioritizationId],
    [src].[RoleCustomFieldUID] AS [x_RoleCustomFieldId]
FROM src_pjrep.MSP_EpmPortfolioAnalysis_UserView AS [src];
GO

CREATE   VIEW tbx.[vw_PortfolioAnalysisProjects_src]
AS
SELECT
    [src].*,
    [src].[AnalysisUID] AS [x_AnalysisId],
    [src].[ProjectUID] AS [x_ProjectId]
FROM src_pjrep.MSP_EpmPortfolioAnalysisProject_UserView AS [src];
GO

CREATE   VIEW tbx.[vw_PrioritizationDriverRelations_src]
AS
SELECT
    [src].*,
    [src].[BusinessDriver1UID] AS [x_BusinessDriver1Id],
    [src].[BusinessDriver2UID] AS [x_BusinessDriver2Id],
    [src].[PrioritizationUID] AS [x_PrioritizationId]
FROM src_pjrep.MSP_EpmPrioritizationDriverRelation_UserView AS [src];
GO

CREATE   VIEW tbx.[vw_PrioritizationDrivers_src]
AS
SELECT
    [src].*,
    [src].[BusinessDriverUID] AS [x_BusinessDriverId],
    [src].[PrioritizationUID] AS [x_PrioritizationId]
FROM src_pjrep.MSP_EpmPrioritizationDriver_UserView AS [src];
GO

CREATE   VIEW tbx.[vw_Prioritizations_src]
AS
SELECT
    [src].*,
    [src].[CreatedByResourceUID] AS [x_CreatedByResourceId],
    [src].[DepartmentUID] AS [x_DepartmentId],
    [src].[ModifiedByResourceUID] AS [x_ModifiedByResourceId],
    [src].[CreatedDate] AS [x_PrioritizationCreatedDate],
    [src].[PrioritizationUID] AS [x_PrioritizationId],
    [src].[ModifiedDate] AS [x_PrioritizationModifiedDate]
FROM src_pjrep.MSP_EpmPrioritization_UserView AS [src];
GO

CREATE   VIEW tbx.[vw_ProjectBaselines_src]
AS
SELECT
    [src].*,
    [src].[BaselineNumber] AS [x_BaselineNumber],
    [src].[ProjectBaselineBudgetCost] AS [x_ProjectBaselineBudgetCost],
    [src].[ProjectBaselineBudgetWork] AS [x_ProjectBaselineBudgetWork],
    [src].[ProjectBaselineCost] AS [x_ProjectBaselineCost],
    [src].[ProjectBaselineDeliverableFinishDate] AS [x_ProjectBaselineDeliverableFinishDate],
    [src].[ProjectBaselineDeliverableStartDate] AS [x_ProjectBaselineDeliverableStartDate],
    [src].[ProjectBaselineDuration] AS [x_ProjectBaselineDuration],
    [src].[ProjectBaselineDurationString] AS [x_ProjectBaselineDurationString],
    [src].[ProjectBaselineFinishDate] AS [x_ProjectBaselineFinishDate],
    [src].[ProjectBaselineFinishDateString] AS [x_ProjectBaselineFinishDateString],
    [src].[ProjectBaselineFixedCost] AS [x_ProjectBaselineFixedCost],
    [src].[ProjectBaselineModifiedDate] AS [x_ProjectBaselineModifiedDate],
    [src].[ProjectBaselineStartDate] AS [x_ProjectBaselineStartDate],
    [src].[ProjectBaselineStartDateString] AS [x_ProjectBaselineStartDateString],
    [src].[ProjectBaselineWork] AS [x_ProjectBaselineWork],
    [src].[ProjectUID] AS [x_ProjectId],
    [prj].[ProjectName] AS [x_ProjectName],
    [src].[TaskUID] AS [x_TaskId]
FROM src_pjrep.MSP_ProjectBaseline_ODATAView AS [src]
LEFT JOIN src_pjrep.MSP_EpmProject_UserView AS [prj]
        ON [prj].[ProjectUID] = [src].[ProjectUID]
      LEFT JOIN src_pjrep.MSP_EpmTask_UserView AS [tsk]
        ON [tsk].[TaskUID] = [src].[TaskUID];
GO

CREATE   VIEW tbx.[vw_Projects_src]
AS
SELECT
    [src].*,
    [ept].[EnterpriseProjectTypeDescription] AS [x_EnterpriseProjectTypeDescription],
    [src].[EnterpriseProjectTypeUID] AS [x_EnterpriseProjectTypeId],
    [ept].[IsDefault] AS [x_EnterpriseProjectTypeIsDefault],
    [ept].[EnterpriseProjectTypeName] AS [x_EnterpriseProjectTypeName],
    [pdu].[OptimizerCommitDate] AS [x_OptimizerCommitDate],
    [pdu].[OptimizerDecisionAliasLookupTableUID] AS [x_OptimizerDecisionAliasLookupTableId],
    [pdu].[OptimizerDecisionAliasMemberUID] AS [x_OptimizerDecisionAliasLookupTableValueId],
    [pdu].[OptimizerDecisionID] AS [x_OptimizerDecisionID],
    [pdu].[OptimizerDecisionName] AS [x_OptimizerDecisionName],
    [pdu].[OptimizerSolutionName] AS [x_OptimizerSolutionName],
    [src].[ParentProjectUID] AS [x_ParentProjectId],
    [pdu].[PlannerCommitDate] AS [x_PlannerCommitDate],
    [pdu].[PlannerDecisionAliasLookupTableUID] AS [x_PlannerDecisionAliasLookupTableId],
    [pdu].[PlannerDecisionAliasMemberUID] AS [x_PlannerDecisionAliasLookupTableValueId],
    [pdu].[PlannerDecisionID] AS [x_PlannerDecisionID],
    [pdu].[PlannerDecisionName] AS [x_PlannerDecisionName],
    [pdu].[PlannerEndDate] AS [x_PlannerEndDate],
    [pdu].[PlannerSolutionName] AS [x_PlannerSolutionName],
    [pdu].[PlannerStartDate] AS [x_PlannerStartDate],
    [src].[ProjectUID] AS [x_ProjectId],
    [pr].[ProjectIdentifier] AS [x_ProjectIdentifier],
    [pr].[ProjectLastPublishedDate] AS [x_ProjectLastPublishedDate],
    [src].[ProjectOwnerResourceUID] AS [x_ProjectOwnerId],
    [ptri].[TimePhased] AS [x_ProjectTimephased],
    [src].[ProjectName] AS [x_ProjectTitle],
    [src].[ProjectWorkspaceInternalHRef] AS [x_ProjectWorkspaceInternalUrl],
    [wiu].[WorkflowCreated] AS [x_WorkflowCreatedDate],
    [wiu].[WorkflowError] AS [x_WorkflowError],
    [wiu].[WorkflowErrorResponseCode] AS [x_WorkflowErrorResponseCode],
    [wiu].[WorkflowInstanceId] AS [x_WorkflowInstanceId],
    [wiu].[WorkflowOwner] AS [x_WorkflowOwnerId],
    [wro].[ResourceName] AS [x_WorkflowOwnerName]
FROM src_pjrep.MSP_EpmProject_UserView AS [src]
LEFT JOIN src_pjrep.MSP_EpmEnterpriseProjectType AS [ept]
        ON [ept].[EnterpriseProjectTypeUID] = [src].[EnterpriseProjectTypeUID]
      LEFT JOIN src_pjrep.MSP_EpmProject AS [pr]
        ON [pr].[ProjectUID] = [src].[ProjectUID]
      LEFT JOIN src_pjrep.MSP_EpmProjectDecision_UserView AS [pdu]
        ON [pdu].[ProjectUID] = [src].[ProjectUID]
      LEFT JOIN src_pjrep.MSP_ProjectTimephasedRollupInfo_ODATAView AS [ptri]
        ON [ptri].[ProjectId] = [src].[ProjectUID]
      LEFT JOIN src_pjrep.MSP_EpmWorkflowInstance_UserView AS [wiu]
        ON [wiu].[ProjectId] = [src].[ProjectUID]
      LEFT JOIN src_pjrep.MSP_EpmResource_UserView AS [wro]
        ON [wro].[ResourceUID] = [wiu].[WorkflowOwner];
GO

CREATE   VIEW tbx.[vw_ProjectWorkflowStageDataSet_src]
AS
SELECT
    [src].*,
    [src].[StageLastSubmitted] AS [x_StageLastSubmittedDate]
FROM src_pjrep.MSP_EpmProjectWorkflowStatusInformation_UserView AS [src];
GO

CREATE   VIEW tbx.[vw_ResourceConstraintScenarios_src]
AS
SELECT
    [src].*,
    [src].[AnalysisUID] AS [x_AnalysisId],
    [src].[CostConstraintScenarioUID] AS [x_CostConstraintScenarioId],
    [src].[CreatedByResourceUID] AS [x_CreatedByResourceId],
    [src].[ModifiedByResourceUID] AS [x_ModifiedByResourceId],
    [src].[ScenarioUID] AS [x_ScenarioId]
FROM src_pjrep.MSP_EpmPortfolioResourceConstraintScenario_UserView AS [src];
GO

CREATE   VIEW tbx.[vw_ResourceDemandTimephasedDataSet_src]
AS
SELECT
    [src].*,
    COALESCE([tbd].[FiscalPeriodUID], [fp].[FiscalPeriodUID]) AS [x_FiscalPeriodId],
    [src].[ProjectUID] AS [x_ProjectId],
    [prj].[ProjectName] AS [x_ProjectName],
    [src].[ResourceUID] AS [x_ResourceId],
    [res].[ResourceName] AS [x_ResourceName],
    [prj].[ResourcePlanUtilizationDate] AS [x_ResourcePlanUtilizationDate],
    [prj].[ResourcePlanUtilizationType] AS [x_ResourcePlanUtilizationType],
    [src].[TimeByDay] AS [x_TimeByDay]
FROM src_pjrep.MSP_EpmResourceDemandByDay_UserView AS [src]
LEFT JOIN src_pjrep.MSP_EpmProject_UserView AS [prj]
        ON [prj].[ProjectUID] = [src].[ProjectUID]
      LEFT JOIN src_pjrep.MSP_EpmResource_UserView AS [res]
        ON [res].[ResourceUID] = [src].[ResourceUID]
      LEFT JOIN src_pjrep.MSP_TimeByDay AS [tbd]
        ON [tbd].[TimeByDay] = [src].[TimeByDay]
      LEFT JOIN src_pjrep.MSP_FiscalPeriods_ODATAView AS [fp]
        ON [fp].[FiscalPeriodUID] = [tbd].[FiscalPeriodUID];
GO

CREATE   VIEW tbx.[vw_Resources_src]
AS
SELECT
    [src].*,
    [src].[ResourceUID] AS [x_ResourceId],
    [src].[ResourceStatusUID] AS [x_ResourceStatusId],
    [rst].[ResourceStatusName] AS [x_ResourceStatusName],
    [src].[ResourceTimesheetManagerUID] AS [x_ResourceTimesheetManageId],
    [rty].[TypeDescription] AS [x_TypeDescription],
    [rty].[TypeName] AS [x_TypeName]
FROM src_pjrep.MSP_EpmResource_UserView AS [src]
LEFT JOIN src_pjrep.MSP_EpmResourceStatus AS [rst]
        ON [rst].[ResourceStatusUID] = [src].[ResourceStatusUID]
      LEFT JOIN src_pjrep.MSP_EpmResourceType AS [rty]
        ON [rty].[ResourceType] = [src].[ResourceType];
GO

CREATE   VIEW tbx.[vw_ResourceScenarioProjects_src]
AS
SELECT
    [src].*,
    [src].[AnalysisUID] AS [x_AnalysisId],
    [src].[CostConstraintScenarioUID] AS [x_CostConstraintScenarioId],
    [src].[ForceAliasLookupTableUID] AS [x_ForceAliasLookupTableId],
    [src].[ProjectUID] AS [x_ProjectId],
    [src].[ScenarioUID] AS [x_ScenarioId]
FROM src_pjrep.MSP_EpmPortfolioResourceConstraintProject_UserView AS [src];
GO

CREATE   VIEW tbx.[vw_ResourceTimephasedDataSet_src]
AS
SELECT
    [src].*,
    [src].[BaseCapacity] AS [x_BaseCapacity],
    [src].[Capacity] AS [x_Capacity],
    COALESCE([tbd].[FiscalPeriodUID], [fp].[FiscalPeriodUID]) AS [x_FiscalPeriodId],
    [src].[ResourceUID] AS [x_ResourceId],
    [res].[ResourceModifiedDate] AS [x_ResourceModifiedDate],
    [res].[ResourceName] AS [x_ResourceName],
    [src].[TimeByDay] AS [x_TimeByDay]
FROM src_pjrep.MSP_EpmResourceByDay_UserView AS [src]
LEFT JOIN src_pjrep.MSP_EpmResource_UserView AS [res]
        ON [res].[ResourceUID] = [src].[ResourceUID]
      LEFT JOIN src_pjrep.MSP_TimeByDay AS [tbd]
        ON [tbd].[TimeByDay] = [src].[TimeByDay]
      LEFT JOIN src_pjrep.MSP_FiscalPeriods_ODATAView AS [fp]
        ON [fp].[FiscalPeriodUID] = [tbd].[FiscalPeriodUID];
GO

CREATE   VIEW tbx.[vw_Risks_src]
AS
SELECT
    [src].*,
    [src].[AssignedToResource] AS [x_AssignedToResource],
    [src].[Category] AS [x_Category],
    [src].[ContingencyPlan] AS [x_ContingencyPlan],
    [src].[Cost] AS [x_Cost],
    [src].[CostExposure] AS [x_CostExposure],
    [src].[CreateByResource] AS [x_CreateByResource],
    [src].[CreatedDate] AS [x_CreatedDate],
    [src].[Description] AS [x_Description],
    [src].[DueDate] AS [x_DueDate],
    [src].[Exposure] AS [x_Exposure],
    [src].[Impact] AS [x_Impact],
    [src].[IsFolder] AS [x_IsFolder],
    [src].[ItemRelativeUrlPath] AS [x_ItemRelativeUrlPath],
    [src].[MitigationPlan] AS [x_MitigationPlan],
    [src].[ModifiedByResource] AS [x_ModifiedByResource],
    [src].[ModifiedDate] AS [x_ModifiedDate],
    [src].[NumberOfAttachments] AS [x_NumberOfAttachments],
    [src].[Owner] AS [x_Owner],
    [src].[Probability] AS [x_Probability],
    [src].[ProjectUID] AS [x_ProjectId],
    [prj].[ProjectName] AS [x_ProjectName],
    [src].[RiskID] AS [x_RiskId],
    [src].[Status] AS [x_Status],
    [src].[Title] AS [x_Title],
    [src].[TriggerDescription] AS [x_TriggerDescription],
    [src].[TriggerTask] AS [x_TriggerTask]
FROM src_pjrep.MSP_WssRisk AS [src]
LEFT JOIN src_pjrep.MSP_EpmProject_UserView AS [prj]
        ON [prj].[ProjectUID] = [src].[ProjectUID];
GO

CREATE   VIEW tbx.[vw_RiskTaskAssociations_src]
AS
SELECT
    [src].*
FROM src_pjrep.MSP_WssRiskTaskAssociation_UserView AS [src];
GO

CREATE   VIEW tbx.[vw_TaskBaselines_src]
AS
SELECT
    [src].*,
    [src].[BaselineNumber] AS [x_BaselineNumber],
    [src].[ProjectUID] AS [x_ProjectId],
    [prj].[ProjectName] AS [x_ProjectName],
    [src].[TaskBaselineBudgetCost] AS [x_TaskBaselineBudgetCost],
    [src].[TaskBaselineBudgetWork] AS [x_TaskBaselineBudgetWork],
    [src].[TaskBaselineCost] AS [x_TaskBaselineCost],
    [src].[TaskBaselineDeliverableFinishDate] AS [x_TaskBaselineDeliverableFinishDate],
    [src].[TaskBaselineDeliverableStartDate] AS [x_TaskBaselineDeliverableStartDate],
    [src].[TaskBaselineDuration] AS [x_TaskBaselineDuration],
    [src].[TaskBaselineDurationString] AS [x_TaskBaselineDurationString],
    [src].[TaskBaselineFinishDate] AS [x_TaskBaselineFinishDate],
    [src].[TaskBaselineFinishDateString] AS [x_TaskBaselineFinishDateString],
    [src].[TaskBaselineFixedCost] AS [x_TaskBaselineFixedCost],
    [src].[TaskBaselineModifiedDate] AS [x_TaskBaselineModifiedDate],
    [src].[TaskBaselineStartDate] AS [x_TaskBaselineStartDate],
    [src].[TaskBaselineStartDateString] AS [x_TaskBaselineStartDateString],
    [src].[TaskBaselineWork] AS [x_TaskBaselineWork],
    [src].[TaskUID] AS [x_TaskId],
    [tsk].[TaskName] AS [x_TaskName]
FROM src_pjrep.MSP_EpmTaskBaseline AS [src]
LEFT JOIN src_pjrep.MSP_EpmProject_UserView AS [prj]
        ON [prj].[ProjectUID] = [src].[ProjectUID]
      LEFT JOIN src_pjrep.MSP_EpmTask_UserView AS [tsk]
        ON [tsk].[TaskUID] = [src].[TaskUID];
GO

CREATE   VIEW tbx.[vw_TaskBaselineTimephasedDataSet_src]
AS
SELECT
    [src].*,
    [src].[BaselineNumber] AS [x_BaselineNumber],
    [src].[FiscalPeriodUID] AS [x_FiscalPeriodId],
    [src].[ProjectUID] AS [x_ProjectId],
    [prj].[ProjectName] AS [x_ProjectName],
    [src].[TaskBaselineBudgetCost] AS [x_TaskBaselineBudgetCost],
    [src].[TaskBaselineBudgetWork] AS [x_TaskBaselineBudgetWork],
    [src].[TaskBaselineCost] AS [x_TaskBaselineCost],
    [src].[TaskBaselineFixedCost] AS [x_TaskBaselineFixedCost],
    [src].[TaskBaselineModifiedDate] AS [x_TaskBaselineModifiedDate],
    [src].[TaskBaselineWork] AS [x_TaskBaselineWork],
    [src].[TaskUID] AS [x_TaskId],
    [tsk].[TaskName] AS [x_TaskName],
    [src].[TimeByDay] AS [x_TimeByDay]
FROM src_pjrep.MSP_EpmTaskBaselineByDay AS [src]
LEFT JOIN src_pjrep.MSP_EpmProject_UserView AS [prj]
        ON [prj].[ProjectUID] = [src].[ProjectUID]
      LEFT JOIN src_pjrep.MSP_EpmTask_UserView AS [tsk]
        ON [tsk].[TaskUID] = [src].[TaskUID];
GO

CREATE   VIEW tbx.[vw_Tasks_src]
AS
SELECT
    [src].*,
    [src].[TaskParentUID] AS [x_ParentTaskId],
    [pt].[TaskName] AS [x_ParentTaskName],
    [src].[ProjectUID] AS [x_ProjectId],
    [prj].[ProjectName] AS [x_ProjectName],
    [src].[FixedCostAssignmentUID] AS [x_TaskFixedCostAssignmentId],
    [src].[TaskUID] AS [x_TaskId]
FROM src_pjrep.MSP_EpmTask_UserView AS [src]
LEFT JOIN src_pjrep.MSP_EpmTask_UserView AS [pt]
        ON [pt].[TaskUID] = [src].[TaskParentUID]
      LEFT JOIN src_pjrep.MSP_EpmProject_UserView AS [prj]
        ON [prj].[ProjectUID] = [src].[ProjectUID];
GO

CREATE   VIEW tbx.[vw_TaskTimephasedDataSet_src]
AS
SELECT
    [src].*,
    [src].[FiscalPeriodUID] AS [x_FiscalPeriodId],
    [src].[ProjectUID] AS [x_ProjectId],
    [prj].[ProjectName] AS [x_ProjectName],
    [src].[TaskActualCost] AS [x_TaskActualCost],
    [src].[TaskActualWork] AS [x_TaskActualWork],
    [src].[TaskBudgetCost] AS [x_TaskBudgetCost],
    [src].[TaskBudgetWork] AS [x_TaskBudgetWork],
    [src].[TaskCost] AS [x_TaskCost],
    [src].[TaskUID] AS [x_TaskId],
    [src].[TaskIsActive] AS [x_TaskIsActive],
    [src].[TaskIsProjectSummary] AS [x_TaskIsProjectSummary],
    [src].[TaskModifiedDate] AS [x_TaskModifiedDate],
    [tsk].[TaskName] AS [x_TaskName],
    [src].[TaskOvertimeWork] AS [x_TaskOvertimeWork],
    [src].[TaskResourcePlanWork] AS [x_TaskResourcePlanWork],
    [src].[TaskWork] AS [x_TaskWork],
    [src].[TimeByDay] AS [x_TimeByDay]
FROM src_pjrep.MSP_EpmTaskByDay AS [src]
LEFT JOIN src_pjrep.MSP_EpmProject_UserView AS [prj]
        ON [prj].[ProjectUID] = [src].[ProjectUID]
      LEFT JOIN src_pjrep.MSP_EpmTask_UserView AS [tsk]
        ON [tsk].[TaskUID] = [src].[TaskUID];
GO

CREATE   VIEW tbx.[vw_TimeSet_src]
AS
SELECT
    [src].*,
    COALESCE([src].[FiscalPeriodUID], [fp].[FiscalPeriodUID]) AS [x_FiscalPeriodId],
    [fp].[ModifiedDate] AS [x_FiscalPeriodModifiedDate],
    COALESCE([src].[FiscalPeriodName], [fp].[FiscalPeriodName]) AS [x_FiscalPeriodName],
    [fp].[FiscalPeriodStart] AS [x_FiscalPeriodStart],
    COALESCE([fp].[FiscalPeriodYear], [src].[FiscalYear]) AS [x_FiscalPeriodYear],
    COALESCE([fp].[FiscalPeriodQuarter], [src].[FiscalQuarter]) AS [x_FiscalQuarter],
    [src].[TimeByDay] AS [x_TimeByDay],
    [src].[TimeDayOfTheMonth] AS [x_TimeDayOfTheMonth],
    [src].[TimeDayOfTheWeek] AS [x_TimeDayOfTheWeek],
    [src].[TimeMonthOfTheYear] AS [x_TimeMonthOfTheYear],
    [src].[TimeQuarter] AS [x_TimeQuarter],
    [src].[TimeWeekOfTheYear] AS [x_TimeWeekOfTheYear]
FROM src_pjrep.MSP_TimeByDay AS [src]
LEFT JOIN src_pjrep.MSP_FiscalPeriods_ODATAView AS [fp]
        ON [fp].[FiscalPeriodUID] = [src].[FiscalPeriodUID];
GO

CREATE   VIEW tbx.[vw_TimesheetClasses_src]
AS
SELECT
    [src].*,
    [src].[DepartmentUID] AS [x_DepartmentId],
    [src].[DepartmentName] AS [x_DepartmentName],
    [src].[Description] AS [x_Description],
    [src].[LCID] AS [x_LCID],
    [src].[ClassUID] AS [x_TimesheetClassId],
    [src].[ClassName] AS [x_TimesheetClassName],
    [src].[Type] AS [x_TimesheetClassType]
FROM src_pjrep.MSP_TimesheetClass_UserView AS [src];
GO

CREATE   VIEW tbx.[vw_TimesheetLineActualDataSet_src]
AS
SELECT
    [src].*,
    [src].[ActualOvertimeWorkBillable] AS [x_ActualOvertimeWorkBillable],
    [src].[ActualOvertimeWorkNonBillable] AS [x_ActualOvertimeWorkNonBillable],
    [src].[ActualWorkBillable] AS [x_ActualWorkBillable],
    [src].[ActualWorkNonBillable] AS [x_ActualWorkNonBillable],
    [src].[AdjustmentIndex] AS [x_AdjustmentIndex],
    [src].[Comment] AS [x_Comment],
    [src].[CreatedDate] AS [x_CreatedDate],
    [rc].[ResourceName] AS [x_LastChangedResourceName],
    [src].[PlannedWork] AS [x_PlannedWork],
    [rc].[ResourceName] AS [x_ResourceName],
    [src].[TimeByDay] AS [x_TimeByDay],
    [src].[TimeByDay_DayOfMonth] AS [x_TimeByDay_DayOfMonth],
    [src].[TimeByDay_DayOfWeek] AS [x_TimeByDay_DayOfWeek],
    [src].[TimesheetLineUID] AS [x_TimesheetLineId],
    [src].[TimesheetLineModifiedDate] AS [x_TimesheetLineModifiedDate]
FROM src_pjrep.MSP_TimesheetActual AS [src]
LEFT JOIN src_pjrep.MSP_EpmResource_UserView AS [rc]
        ON [rc].[ResourceUID] = [src].[LastChangedResourceNameUID];
GO

CREATE   VIEW tbx.[vw_TimesheetLines_src]
AS
SELECT
    [src].*,
    [src].[ActualOvertimeWorkBillable] AS [x_ActualOvertimeWorkBillable],
    [src].[ActualOvertimeWorkNonBillable] AS [x_ActualOvertimeWorkNonBillable],
    [src].[ActualWorkBillable] AS [x_ActualWorkBillable],
    [src].[ActualWorkNonBillable] AS [x_ActualWorkNonBillable],
    [tsl].[AssignmentUID] AS [x_AssignmentId],
    [src].[CreatedDate] AS [x_CreatedDate],
    [tsl].[LastSavedWork] AS [x_LastSavedWork],
    [tls].[LCID] AS [x_LCID],
    [src].[ModifiedDate] AS [x_ModifiedDate],
    [src].[PeriodEndDate] AS [x_PeriodEndDate],
    [src].[PeriodStartDate] AS [x_PeriodStartDate],
    [src].[PlannedWork] AS [x_PlannedWork],
    [src].[ProjectUID] AS [x_ProjectId],
    [src].[ProjectName] AS [x_ProjectName],
    [tsl].[TaskHierarchy] AS [x_TaskHierarchy],
    [src].[TaskUID] AS [x_TaskId],
    [src].[TaskName] AS [x_TaskName],
    [tsl].[ApproverResourceNameUID] AS [x_TimesheetApproverResourceId],
    [apr].[ResourceName] AS [x_TimesheetApproverResourceName],
    [tsc].[Description] AS [x_TimesheetClassDescription],
    [src].[TimesheetLineClassUID] AS [x_TimesheetClassId],
    [src].[TimesheetLineClass] AS [x_TimesheetClassName],
    [src].[TimesheetLineClassType] AS [x_TimesheetClassType],
    [src].[TimesheetUID] AS [x_TimesheetId],
    [tsl].[Comment] AS [x_TimesheetLineComment],
    [src].[TimesheetLineUID] AS [x_TimesheetLineId],
    [src].[TimesheetLineStatus] AS [x_TimesheetLineStatus],
    [src].[TimesheetLineStatusID] AS [x_TimesheetLineStatusId],
    [src].[TimesheetName] AS [x_TimesheetName],
    [own].[ResourceName] AS [x_TimesheetOwner],
    [ts].[OwnerResourceNameUID] AS [x_TimesheetOwnerId],
    [src].[PeriodUID] AS [x_TimesheetPeriodId],
    [src].[PeriodName] AS [x_TimesheetPeriodName],
    [src].[PeriodStatus] AS [x_TimesheetPeriodStatus],
    [src].[PeriodStatusID] AS [x_TimesheetPeriodStatusId],
    [src].[TimesheetStatus] AS [x_TimesheetStatus],
    [src].[TimesheetStatusID] AS [x_TimesheetStatusId]
FROM src_pjrep.MSP_TimesheetLine_UserView AS [src]
LEFT JOIN src_pjrep.MSP_TimesheetLine AS [tsl]
        ON [tsl].[TimesheetLineUID] = [src].[TimesheetLineUID]
      LEFT JOIN src_pjrep.MSP_Timesheet AS [ts]
        ON [ts].[TimesheetUID] = [src].[TimesheetUID]
      LEFT JOIN src_pjrep.MSP_TimesheetClass_UserView AS [tsc]
        ON [tsc].[ClassUID] = [src].[TimesheetLineClassUID]
      LEFT JOIN src_pjrep.MSP_TimesheetLineStatus AS [tls]
        ON [tls].[TimesheetLineStatusID] = [src].[TimesheetLineStatusID]
      LEFT JOIN src_pjrep.MSP_EpmResource_UserView AS [apr]
        ON [apr].[ResourceUID] = [tsl].[ApproverResourceNameUID]
      LEFT JOIN src_pjrep.MSP_EpmResource_UserView AS [own]
        ON [own].[ResourceUID] = [ts].[OwnerResourceNameUID];
GO

CREATE   VIEW tbx.[vw_TimesheetPeriods_src]
AS
SELECT
    [src].*,
    [tps].[Description] AS [x_Description],
    [src].[EndDate] AS [x_EndDate],
    [src].[LCID] AS [x_LCID],
    [src].[PeriodUID] AS [x_PeriodId],
    [src].[PeriodName] AS [x_PeriodName],
    [src].[PeriodStatusID] AS [x_PeriodStatusId],
    [src].[StartDate] AS [x_StartDate]
FROM src_pjrep.MSP_TimesheetPeriod AS [src]
LEFT JOIN src_pjrep.MSP_TimesheetPeriodStatus AS [tps]
        ON [tps].[PeriodStatusID] = [src].[PeriodStatusID];
GO

CREATE   VIEW tbx.[vw_Timesheets_src]
AS
SELECT
    [src].*,
    [src].[Comment] AS [x_Comment],
    [tp].[EndDate] AS [x_EndDate],
    [src].[ModifiedDate] AS [x_ModifiedDate],
    [src].[PeriodUID] AS [x_PeriodId],
    [tp].[PeriodName] AS [x_PeriodName],
    [tp].[PeriodStatusID] AS [x_PeriodStatusId],
    [tp].[StartDate] AS [x_StartDate],
    [tst].[Description] AS [x_StatusDescription],
    [src].[TimesheetUID] AS [x_TimesheetId],
    [src].[TimesheetName] AS [x_TimesheetName],
    [own].[ResourceName] AS [x_TimesheetOwner],
    [src].[OwnerResourceNameUID] AS [x_TimesheetOwnerId],
    [src].[TimesheetStatusID] AS [x_TimesheetStatusId]
FROM src_pjrep.MSP_Timesheet AS [src]
LEFT JOIN src_pjrep.MSP_TimesheetPeriod AS [tp]
        ON [tp].[PeriodUID] = [src].[PeriodUID]
      LEFT JOIN src_pjrep.MSP_TimesheetStatus AS [tst]
        ON [tst].[TimesheetStatusID] = [src].[TimesheetStatusID]
      LEFT JOIN src_pjrep.MSP_EpmResource_UserView AS [own]
        ON [own].[ResourceUID] = [src].[OwnerResourceNameUID];
GO

CREATE   VIEW tbx_master.[vw_AssignmentBaselines_Master]
AS
SELECT *
FROM tbx.[vw_AssignmentBaselines_src];
GO

CREATE   VIEW tbx_master.[vw_AssignmentBaselineTimephasedDataSet_Master]
AS
SELECT *
FROM tbx.[vw_AssignmentBaselineTimephasedDataSet_src];
GO

CREATE   VIEW tbx_master.[vw_Assignments_Master]
AS
SELECT *
FROM tbx.[vw_Assignments_src];
GO

CREATE   VIEW tbx_master.[vw_AssignmentTimephasedDataSet_Master]
AS
SELECT *
FROM tbx.[vw_AssignmentTimephasedDataSet_src];
GO

CREATE   VIEW tbx_master.[vw_BusinessDriverDepartments_Master]
AS
SELECT *
FROM tbx.[vw_BusinessDriverDepartments_src];
GO

CREATE   VIEW tbx_master.[vw_BusinessDrivers_Master]
AS
SELECT *
FROM tbx.[vw_BusinessDrivers_src];
GO

CREATE   VIEW tbx_master.[vw_CostConstraintScenarios_Master]
AS
SELECT *
FROM tbx.[vw_CostConstraintScenarios_src];
GO

CREATE   VIEW tbx_master.[vw_CostScenarioProjects_Master]
AS
SELECT *
FROM tbx.[vw_CostScenarioProjects_src];
GO

CREATE   VIEW tbx_master.[vw_Deliverables_Master]
AS
SELECT *
FROM tbx.[vw_Deliverables_src];
GO

CREATE   VIEW tbx_master.[vw_Engagements_Master]
AS
SELECT *
FROM tbx.[vw_Engagements_src];
GO

CREATE   VIEW tbx_master.[vw_EngagementsComments_Master]
AS
SELECT *
FROM tbx.[vw_EngagementsComments_src];
GO

CREATE   VIEW tbx_master.[vw_EngagementsTimephasedDataSet_Master]
AS
SELECT *
FROM tbx.[vw_EngagementsTimephasedDataSet_src];
GO

CREATE   VIEW tbx_master.[vw_FiscalPeriods_Master]
AS
SELECT *
FROM tbx.[vw_FiscalPeriods_src];
GO

CREATE   VIEW tbx_master.[vw_Issues_Master]
AS
SELECT *
FROM tbx.[vw_Issues_src];
GO

CREATE   VIEW tbx_master.[vw_IssueTaskAssociations_Master]
AS
SELECT *
FROM tbx.[vw_IssueTaskAssociations_src];
GO

CREATE   VIEW tbx_master.[vw_PortfolioAnalyses_Master]
AS
SELECT *
FROM tbx.[vw_PortfolioAnalyses_src];
GO

CREATE   VIEW tbx_master.[vw_PortfolioAnalysisProjects_Master]
AS
SELECT *
FROM tbx.[vw_PortfolioAnalysisProjects_src];
GO

CREATE   VIEW tbx_master.[vw_PrioritizationDriverRelations_Master]
AS
SELECT *
FROM tbx.[vw_PrioritizationDriverRelations_src];
GO

CREATE   VIEW tbx_master.[vw_PrioritizationDrivers_Master]
AS
SELECT *
FROM tbx.[vw_PrioritizationDrivers_src];
GO

CREATE   VIEW tbx_master.[vw_Prioritizations_Master]
AS
SELECT *
FROM tbx.[vw_Prioritizations_src];
GO

CREATE   VIEW tbx_master.[vw_ProjectBaselines_Master]
AS
SELECT *
FROM tbx.[vw_ProjectBaselines_src];
GO

CREATE   VIEW tbx_master.[vw_Projects_Master]
AS
SELECT *
FROM tbx.[vw_Projects_src];
GO

CREATE   VIEW tbx_master.[vw_ProjectWorkflowStageDataSet_Master]
AS
SELECT *
FROM tbx.[vw_ProjectWorkflowStageDataSet_src];
GO

CREATE   VIEW tbx_master.[vw_ResourceConstraintScenarios_Master]
AS
SELECT *
FROM tbx.[vw_ResourceConstraintScenarios_src];
GO

CREATE   VIEW tbx_master.[vw_ResourceDemandTimephasedDataSet_Master]
AS
SELECT *
FROM tbx.[vw_ResourceDemandTimephasedDataSet_src];
GO

CREATE   VIEW tbx_master.[vw_Resources_Master]
AS
SELECT *
FROM tbx.[vw_Resources_src];
GO

CREATE   VIEW tbx_master.[vw_ResourceScenarioProjects_Master]
AS
SELECT *
FROM tbx.[vw_ResourceScenarioProjects_src];
GO

CREATE   VIEW tbx_master.[vw_ResourceTimephasedDataSet_Master]
AS
SELECT *
FROM tbx.[vw_ResourceTimephasedDataSet_src];
GO

CREATE   VIEW tbx_master.[vw_Risks_Master]
AS
SELECT *
FROM tbx.[vw_Risks_src];
GO

CREATE   VIEW tbx_master.[vw_RiskTaskAssociations_Master]
AS
SELECT *
FROM tbx.[vw_RiskTaskAssociations_src];
GO

CREATE   VIEW tbx_master.[vw_TaskBaselines_Master]
AS
SELECT *
FROM tbx.[vw_TaskBaselines_src];
GO

CREATE   VIEW tbx_master.[vw_TaskBaselineTimephasedDataSet_Master]
AS
SELECT *
FROM tbx.[vw_TaskBaselineTimephasedDataSet_src];
GO

CREATE   VIEW tbx_master.[vw_Tasks_Master]
AS
SELECT *
FROM tbx.[vw_Tasks_src];
GO

CREATE   VIEW tbx_master.[vw_TaskTimephasedDataSet_Master]
AS
SELECT *
FROM tbx.[vw_TaskTimephasedDataSet_src];
GO

CREATE   VIEW tbx_master.[vw_TimeSet_Master]
AS
SELECT *
FROM tbx.[vw_TimeSet_src];
GO

CREATE   VIEW tbx_master.[vw_TimesheetClasses_Master]
AS
SELECT *
FROM tbx.[vw_TimesheetClasses_src];
GO

CREATE   VIEW tbx_master.[vw_TimesheetLineActualDataSet_Master]
AS
SELECT *
FROM tbx.[vw_TimesheetLineActualDataSet_src];
GO

CREATE   VIEW tbx_master.[vw_TimesheetLines_Master]
AS
SELECT *
FROM tbx.[vw_TimesheetLines_src];
GO

CREATE   VIEW tbx_master.[vw_TimesheetPeriods_Master]
AS
SELECT *
FROM tbx.[vw_TimesheetPeriods_src];
GO

CREATE   VIEW tbx_master.[vw_Timesheets_Master]
AS
SELECT *
FROM tbx.[vw_Timesheets_src];
GO

CREATE   VIEW tbx.[vw_AssignmentBaselines_alias]
AS
SELECT
    [s].[x_AssignmentId] AS [AssignmentId],
    [s].[x_BaselineNumber] AS [BaselineNumber],
    [s].[x_AssignmentBaselineBudgetCost] AS [AssignmentBaselineBudgetCost],
    [s].[x_AssignmentBaselineBudgetMaterialWork] AS [AssignmentBaselineBudgetMaterialWork],
    [s].[x_AssignmentBaselineBudgetWork] AS [AssignmentBaselineBudgetWork],
    [s].[x_AssignmentBaselineCost] AS [AssignmentBaselineCost],
    [s].[x_AssignmentBaselineFinishDate] AS [AssignmentBaselineFinishDate],
    [s].[x_AssignmentBaselineMaterialWork] AS [AssignmentBaselineMaterialWork],
    [s].[x_AssignmentBaselineModifiedDate] AS [AssignmentBaselineModifiedDate],
    [s].[x_AssignmentBaselineStartDate] AS [AssignmentBaselineStartDate],
    [s].[x_AssignmentBaselineWork] AS [AssignmentBaselineWork],
    [s].[x_AssignmentType] AS [AssignmentType],
    [s].[x_ProjectName] AS [ProjectName],
    [s].[x_TaskId] AS [TaskId],
    [s].[x_TaskName] AS [TaskName],
    CAST(N'view=tbx.vw_Assignments;source_uid=AssignmentId;target_uid=AssignmentId' AS nvarchar(4000)) AS [Assignment],
    CAST(N'view=tbx.vw_AssignmentBaselineTimephasedDataSet;source_uid=AssignmentId;target_uid=AssignmentId' AS nvarchar(4000)) AS [AssignmentBaselineTimephasedDataSet],
    CAST(N'view=tbx.vw_Projects;source_uid=ProjectId;target_uid=ProjectId' AS nvarchar(4000)) AS [Project],
    CAST(N'view=tbx.vw_Tasks;source_uid=TaskId;target_uid=TaskId' AS nvarchar(4000)) AS [Task],
    [s].[x_ProjectId] AS [ProjectId]
FROM tbx.[vw_AssignmentBaselines_src] AS [s];
GO

CREATE   VIEW tbx.[vw_AssignmentBaselineTimephasedDataSet_alias]
AS
SELECT
    [s].[x_AssignmentId] AS [AssignmentId],
    [s].[x_TimeByDay] AS [TimeByDay],
    [s].[x_BaselineNumber] AS [BaselineNumber],
    [s].[x_AssignmentBaselineBudgetCost] AS [AssignmentBaselineBudgetCost],
    [s].[x_AssignmentBaselineBudgetMaterialWork] AS [AssignmentBaselineBudgetMaterialWork],
    [s].[x_AssignmentBaselineBudgetWork] AS [AssignmentBaselineBudgetWork],
    [s].[x_AssignmentBaselineCost] AS [AssignmentBaselineCost],
    [s].[x_AssignmentBaselineMaterialWork] AS [AssignmentBaselineMaterialWork],
    [s].[x_AssignmentBaselineModifiedDate] AS [AssignmentBaselineModifiedDate],
    [s].[x_AssignmentBaselineWork] AS [AssignmentBaselineWork],
    [s].[x_FiscalPeriodId] AS [FiscalPeriodId],
    [s].[x_ProjectName] AS [ProjectName],
    [s].[x_ResourceId] AS [ResourceId],
    [s].[x_TaskId] AS [TaskId],
    [s].[x_TaskName] AS [TaskName],
    CAST(N'view=tbx.vw_Assignments;source_uid=AssignmentId;target_uid=AssignmentId' AS nvarchar(4000)) AS [Assignment],
    CAST(N'view=tbx.vw_AssignmentBaselines;source_uid=AssignmentId;target_uid=AssignmentId' AS nvarchar(4000)) AS [Baseline],
    CAST(N'view=tbx.vw_Projects;source_uid=ProjectId;target_uid=ProjectId' AS nvarchar(4000)) AS [Project],
    CAST(N'view=tbx.vw_Tasks;source_uid=TaskId;target_uid=TaskId' AS nvarchar(4000)) AS [Tasks],
    CAST(N'view=tbx.vw_TimeSet;source_uid=TimeByDay;target_uid=TimeByDay' AS nvarchar(4000)) AS [Time],
    [s].[x_ProjectId] AS [ProjectId]
FROM tbx.[vw_AssignmentBaselineTimephasedDataSet_src] AS [s];
GO

CREATE   VIEW tbx.[vw_Assignments_alias]
AS
SELECT
    [s].[x_AssignmentId] AS [AssignmentId],
    [s].[AssignmentActualCost] AS [AssignmentActualCost],
    [s].[AssignmentActualFinishDate] AS [AssignmentActualFinishDate],
    [s].[AssignmentActualOvertimeCost] AS [AssignmentActualOvertimeCost],
    [s].[AssignmentActualOvertimeWork] AS [AssignmentActualOvertimeWork],
    [s].[AssignmentActualRegularCost] AS [AssignmentActualRegularCost],
    [s].[AssignmentActualRegularWork] AS [AssignmentActualRegularWork],
    [s].[AssignmentActualStartDate] AS [AssignmentActualStartDate],
    [s].[AssignmentActualWork] AS [AssignmentActualWork],
    [s].[AssignmentACWP] AS [AssignmentACWP],
    [s].[x_AssignmentAllUpdatesApplied] AS [AssignmentAllUpdatesApplied],
    [s].[AssignmentBCWP] AS [AssignmentBCWP],
    [s].[AssignmentBCWS] AS [AssignmentBCWS],
    [s].[x_AssignmentBookingDescription] AS [AssignmentBookingDescription],
    [s].[AssignmentBookingId] AS [AssignmentBookingId],
    [s].[x_AssignmentBookingName] AS [AssignmentBookingName],
    [s].[AssignmentBudgetCost] AS [AssignmentBudgetCost],
    [s].[AssignmentBudgetMaterialWork] AS [AssignmentBudgetMaterialWork],
    [s].[AssignmentBudgetWork] AS [AssignmentBudgetWork],
    [s].[AssignmentCost] AS [AssignmentCost],
    [s].[AssignmentCostVariance] AS [AssignmentCostVariance],
    [s].[AssignmentCreatedDate] AS [AssignmentCreatedDate],
    [s].[AssignmentCreatedRevisionCounter] AS [AssignmentCreatedRevisionCounter],
    [s].[AssignmentCV] AS [AssignmentCV],
    [s].[AssignmentDelay] AS [AssignmentDelay],
    [s].[AssignmentFinishDate] AS [AssignmentFinishDate],
    [s].[AssignmentFinishVariance] AS [AssignmentFinishVariance],
    [s].[AssignmentIsOverallocated] AS [AssignmentIsOverallocated],
    [s].[AssignmentIsPublished] AS [AssignmentIsPublished],
    [s].[AssignmentMaterialActualWork] AS [AssignmentMaterialActualWork],
    [s].[AssignmentMaterialWork] AS [AssignmentMaterialWork],
    [s].[AssignmentModifiedDate] AS [AssignmentModifiedDate],
    [s].[AssignmentModifiedRevisionCounter] AS [AssignmentModifiedRevisionCounter],
    [s].[AssignmentOvertimeCost] AS [AssignmentOvertimeCost],
    [s].[AssignmentOvertimeWork] AS [AssignmentOvertimeWork],
    [s].[AssignmentPeakUnits] AS [AssignmentPeakUnits],
    [s].[AssignmentPercentWorkCompleted] AS [AssignmentPercentWorkCompleted],
    [s].[AssignmentRegularCost] AS [AssignmentRegularCost],
    [s].[AssignmentRegularWork] AS [AssignmentRegularWork],
    [s].[AssignmentRemainingCost] AS [AssignmentRemainingCost],
    [s].[AssignmentRemainingOvertimeCost] AS [AssignmentRemainingOvertimeCost],
    [s].[AssignmentRemainingOvertimeWork] AS [AssignmentRemainingOvertimeWork],
    [s].[AssignmentRemainingRegularCost] AS [AssignmentRemainingRegularCost],
    [s].[AssignmentRemainingRegularWork] AS [AssignmentRemainingRegularWork],
    [s].[AssignmentRemainingWork] AS [AssignmentRemainingWork],
    [s].[AssignmentResourcePlanWork] AS [AssignmentResourcePlanWork],
    [s].[AssignmentResourceType] AS [AssignmentResourceType],
    [s].[AssignmentStartDate] AS [AssignmentStartDate],
    [s].[AssignmentStartVariance] AS [AssignmentStartVariance],
    [s].[AssignmentSV] AS [AssignmentSV],
    [s].[AssignmentType] AS [AssignmentType],
    [s].[x_AssignmentUpdatesAppliedDate] AS [AssignmentUpdatesAppliedDate],
    [s].[AssignmentVAC] AS [AssignmentVAC],
    [s].[AssignmentWork] AS [AssignmentWork],
    [s].[AssignmentWorkVariance] AS [AssignmentWorkVariance],
    [s].[IsPublic] AS [IsPublic],
    [s].[x_ProjectName] AS [ProjectName],
    [s].[x_ResourceId] AS [ResourceId],
    [s].[x_ResourceName] AS [ResourceName],
    [s].[x_TaskId] AS [TaskId],
    [s].[TaskIsActive] AS [TaskIsActive],
    [s].[x_TaskName] AS [TaskName],
    [s].[x_TimesheetClassId] AS [TimesheetClassId],
    [s].[x_TypeDescription] AS [TypeDescription],
    [s].[x_TypeName] AS [TypeName],
    CAST(NULL AS nvarchar(4000)) AS [RBS_R],
    CAST(NULL AS nvarchar(4000)) AS [CostType_R],
    CAST(NULL AS nvarchar(4000)) AS [FlagStatus_T],
    CAST(NULL AS nvarchar(4000)) AS [TeamName_R],
    CAST(NULL AS nvarchar(4000)) AS [ResourceDepartments_R],
    CAST(NULL AS nvarchar(4000)) AS [Health_T],
    CAST(NULL AS nvarchar(4000)) AS [Profilderessource_R],
    CAST(NULL AS nvarchar(4000)) AS [Contexte_T],
    CAST(NULL AS bit) AS [CongédeFdT_R],
    CAST(NULL AS nvarchar(4000)) AS [Courrielsupérieurhiérarchique_R],
    CAST(NULL AS nvarchar(4000)) AS [Notedepilotage_R],
    CAST(NULL AS nvarchar(4000)) AS [OBS_R],
    CAST(NULL AS bit) AS [RappelFdTavisersupérieur_R],
    CAST(NULL AS bit) AS [Verrouilléeentreprise_T],
    CAST(NULL AS nvarchar(4000)) AS [Typedecoût_R],
    CAST(NULL AS bit) AS [IgnorerRàF_T],
    CAST(NULL AS bit) AS [Capitalisable_T],
    CAST(NULL AS nvarchar(4000)) AS [CompteComptableExterne_T],
    CAST(NULL AS nvarchar(4000)) AS [CodeDeProjet_T],
    CAST(NULL AS nvarchar(4000)) AS [zzUnitéAdministrative_T],
    CAST(NULL AS nvarchar(4000)) AS [UnitéAdministrative_T],
    CAST(NULL AS nvarchar(4000)) AS [NoContrat_T],
    CAST(NULL AS nvarchar(4000)) AS [NoDemande_T],
    CAST(NULL AS nvarchar(4000)) AS [NoItem_T],
    CAST(NULL AS nvarchar(4000)) AS [DescItem_T],
    CAST(NULL AS decimal(38,6)) AS [NoEpic_T],
    CAST(NULL AS nvarchar(4000)) AS [NoRéférence_T],
    CAST(N'view=tbx.vw_AssignmentBaselines;source_uid=AssignmentId;target_uid=AssignmentId' AS nvarchar(4000)) AS [Baseline],
    CAST(N'view=tbx.vw_Projects;source_uid=ProjectId;target_uid=ProjectId' AS nvarchar(4000)) AS [Project],
    CAST(N'view=tbx.vw_Resources;source_uid=ResourceId;target_uid=ResourceId' AS nvarchar(4000)) AS [Resource],
    CAST(N'view=tbx.vw_Tasks;source_uid=TaskId;target_uid=TaskId' AS nvarchar(4000)) AS [Task],
    CAST(N'view=tbx.vw_AssignmentTimephasedDataSet;source_uid=AssignmentId;target_uid=AssignmentId' AS nvarchar(4000)) AS [TimephasedData],
    [s].[x_ProjectId] AS [ProjectId],
    CAST(NULL AS nvarchar(4000)) AS [CF_CentreCout_T],
    CAST(NULL AS nvarchar(4000)) AS [CF_Fin_T],
    CAST(NULL AS nvarchar(4000)) AS [CF_Priorite_T_T],
    CAST(NULL AS nvarchar(4000)) AS [CF_UA_R],
    CAST(NULL AS nvarchar(4000)) AS [CF_UAC_T]
FROM tbx.[vw_Assignments_src] AS [s];
GO

CREATE   VIEW tbx.[vw_AssignmentTimephasedDataSet_alias]
AS
SELECT
    [s].[x_AssignmentId] AS [AssignmentId],
    [s].[x_TimeByDay] AS [TimeByDay],
    [s].[x_AssignmentActualCost] AS [AssignmentActualCost],
    [s].[x_AssignmentActualOvertimeCost] AS [AssignmentActualOvertimeCost],
    [s].[x_AssignmentActualOvertimeWork] AS [AssignmentActualOvertimeWork],
    [s].[x_AssignmentActualRegularCost] AS [AssignmentActualRegularCost],
    [s].[x_AssignmentActualRegularWork] AS [AssignmentActualRegularWork],
    [s].[x_AssignmentActualWork] AS [AssignmentActualWork],
    [s].[x_AssignmentBudgetCost] AS [AssignmentBudgetCost],
    [s].[x_AssignmentBudgetMaterialWork] AS [AssignmentBudgetMaterialWork],
    [s].[x_AssignmentBudgetWork] AS [AssignmentBudgetWork],
    [s].[x_AssignmentCombinedWork] AS [AssignmentCombinedWork],
    [s].[x_AssignmentCost] AS [AssignmentCost],
    [s].[x_AssignmentMaterialActualWork] AS [AssignmentMaterialActualWork],
    [s].[x_AssignmentMaterialWork] AS [AssignmentMaterialWork],
    [s].[x_AssignmentModifiedDate] AS [AssignmentModifiedDate],
    [s].[x_AssignmentOvertimeCost] AS [AssignmentOvertimeCost],
    [s].[x_AssignmentOvertimeWork] AS [AssignmentOvertimeWork],
    [s].[x_AssignmentRegularCost] AS [AssignmentRegularCost],
    [s].[x_AssignmentRegularWork] AS [AssignmentRegularWork],
    [s].[x_AssignmentRemainingCost] AS [AssignmentRemainingCost],
    [s].[x_AssignmentRemainingOvertimeCost] AS [AssignmentRemainingOvertimeCost],
    [s].[x_AssignmentRemainingOvertimeWork] AS [AssignmentRemainingOvertimeWork],
    [s].[x_AssignmentRemainingRegularCost] AS [AssignmentRemainingRegularCost],
    [s].[x_AssignmentRemainingRegularWork] AS [AssignmentRemainingRegularWork],
    [s].[x_AssignmentRemainingWork] AS [AssignmentRemainingWork],
    [s].[x_AssignmentResourcePlanWork] AS [AssignmentResourcePlanWork],
    [s].[x_AssignmentWork] AS [AssignmentWork],
    [s].[x_FiscalPeriodId] AS [FiscalPeriodId],
    [s].[x_ProjectName] AS [ProjectName],
    [s].[x_ResourceId] AS [ResourceId],
    [s].[x_TaskId] AS [TaskId],
    [s].[x_TaskIsActive] AS [TaskIsActive],
    [s].[x_TaskName] AS [TaskName],
    CAST(N'view=tbx.vw_Assignments;source_uid=AssignmentId;target_uid=AssignmentId' AS nvarchar(4000)) AS [Assignment],
    CAST(N'view=tbx.vw_Projects;source_uid=ProjectId;target_uid=ProjectId' AS nvarchar(4000)) AS [Project],
    CAST(N'view=tbx.vw_Tasks;source_uid=TaskId;target_uid=TaskId' AS nvarchar(4000)) AS [Task],
    CAST(N'view=tbx.vw_TimeSet;source_uid=TimeByDay;target_uid=TimeByDay' AS nvarchar(4000)) AS [Time],
    [s].[x_ProjectId] AS [ProjectId]
FROM tbx.[vw_AssignmentTimephasedDataSet_src] AS [s];
GO

CREATE   VIEW tbx.[vw_BusinessDriverDepartments_alias]
AS
SELECT
    [s].[x_DepartmentId] AS [DepartmentId],
    [s].[x_BusinessDriverName] AS [BusinessDriverName],
    [s].[x_DepartmentName] AS [DepartmentName],
    CAST(N'view=tbx.vw_BusinessDrivers;source_uid=BusinessDriverId;target_uid=BusinessDriverId' AS nvarchar(4000)) AS [BusinessDriver],
    [s].[x_BusinessDriverId] AS [BusinessDriverId]
FROM tbx.[vw_BusinessDriverDepartments_src] AS [s];
GO

CREATE   VIEW tbx.[vw_BusinessDrivers_alias]
AS
SELECT
    [s].[x_BusinessDriverCreatedDate] AS [BusinessDriverCreatedDate],
    [s].[BusinessDriverDescription] AS [BusinessDriverDescription],
    [s].[BusinessDriverIsActive] AS [BusinessDriverIsActive],
    [s].[x_BusinessDriverModifiedDate] AS [BusinessDriverModifiedDate],
    [s].[BusinessDriverName] AS [BusinessDriverName],
    [s].[x_CreatedByResourceId] AS [CreatedByResourceId],
    [s].[CreatedByResourceName] AS [CreatedByResourceName],
    [s].[ImpactDescriptionExtreme] AS [ImpactDescriptionExtreme],
    [s].[ImpactDescriptionLow] AS [ImpactDescriptionLow],
    [s].[ImpactDescriptionModerate] AS [ImpactDescriptionModerate],
    [s].[ImpactDescriptionNone] AS [ImpactDescriptionNone],
    [s].[ImpactDescriptionStrong] AS [ImpactDescriptionStrong],
    [s].[x_ModifiedByResourceId] AS [ModifiedByResourceId],
    [s].[ModifiedByResourceName] AS [ModifiedByResourceName],
    CAST(N'view=tbx.vw_Resources;source_uid=CreatedByResourceId;target_uid=ResourceId' AS nvarchar(4000)) AS [CreatedByResource],
    CAST(N'view=tbx.vw_BusinessDriverDepartments;source_uid=BusinessDriverId;target_uid=BusinessDriverId' AS nvarchar(4000)) AS [Departments],
    CAST(N'view=tbx.vw_Resources;source_uid=ModifiedByResourceId;target_uid=ResourceId' AS nvarchar(4000)) AS [ModifiedByResource],
    [s].[x_BusinessDriverId] AS [BusinessDriverId]
FROM tbx.[vw_BusinessDrivers_src] AS [s];
GO

CREATE   VIEW tbx.[vw_CostConstraintScenarios_alias]
AS
SELECT
    [s].[x_AnalysisId] AS [AnalysisId],
    [s].[AnalysisName] AS [AnalysisName],
    [s].[x_CreatedByResourceId] AS [CreatedByResourceId],
    [s].[CreatedByResourceName] AS [CreatedByResourceName],
    [s].[CreatedDate] AS [CreatedDate],
    [s].[x_ModifiedByResourceId] AS [ModifiedByResourceId],
    [s].[ModifiedByResourceName] AS [ModifiedByResourceName],
    [s].[ModifiedDate] AS [ModifiedDate],
    [s].[ScenarioDescription] AS [ScenarioDescription],
    [s].[ScenarioName] AS [ScenarioName],
    [s].[SelectedProjectsCost] AS [SelectedProjectsCost],
    [s].[SelectedProjectsPriority] AS [SelectedProjectsPriority],
    [s].[UnselectedProjectsCost] AS [UnselectedProjectsCost],
    [s].[UnselectedProjectsPriority] AS [UnselectedProjectsPriority],
    [s].[UseDependencies] AS [UseDependencies],
    CAST(N'view=tbx.vw_Resources;source_uid=CreatedByResourceId;target_uid=ResourceId' AS nvarchar(4000)) AS [CreatedByResource],
    CAST(N'view=tbx.vw_Resources;source_uid=ModifiedByResourceId;target_uid=ResourceId' AS nvarchar(4000)) AS [ModifiedByResource],
    CAST(N'view=tbx.vw_PortfolioAnalyses;source_uid=AnalysisId;target_uid=AnalysisId' AS nvarchar(4000)) AS [Analysis],
    CAST(N'view=tbx.vw_ResourceConstraintScenarios;source_uid=ScenarioId;target_uid=CostConstraintScenarioId' AS nvarchar(4000)) AS [ResourceConstraintScenarios],
    CAST(N'view=tbx.vw_CostScenarioProjects;source_uid=ScenarioId;target_uid=ScenarioId' AS nvarchar(4000)) AS [CostScenarioProjects],
    [s].[x_ScenarioId] AS [ScenarioId]
FROM tbx.[vw_CostConstraintScenarios_src] AS [s];
GO

CREATE   VIEW tbx.[vw_CostScenarioProjects_alias]
AS
SELECT
    [s].[x_ProjectId] AS [ProjectId],
    [s].[AbsolutePriority] AS [AbsolutePriority],
    [s].[x_AnalysisId] AS [AnalysisId],
    [s].[AnalysisName] AS [AnalysisName],
    [s].[x_ForceAliasLookupTableId] AS [ForceAliasLookupTableId],
    [s].[ForceAliasLookupTableName] AS [ForceAliasLookupTableName],
    [s].[ForceStatus] AS [ForceStatus],
    [s].[HardConstraintValue] AS [HardConstraintValue],
    [s].[Priority] AS [Priority],
    [s].[ProjectName] AS [ProjectName],
    [s].[ScenarioName] AS [ScenarioName],
    [s].[Status] AS [Status],
    CAST(N'view=tbx.vw_Projects;source_uid=ProjectId;target_uid=ProjectId' AS nvarchar(4000)) AS [Project],
    CAST(N'view=tbx.vw_PortfolioAnalyses;source_uid=AnalysisId;target_uid=AnalysisId' AS nvarchar(4000)) AS [Analysis],
    CAST(N'view=tbx.vw_CostConstraintScenarios;source_uid=ScenarioId;target_uid=ScenarioId' AS nvarchar(4000)) AS [CostConstraintScenario],
    [s].[x_ScenarioId] AS [ScenarioId]
FROM tbx.[vw_CostScenarioProjects_src] AS [s];
GO

CREATE   VIEW tbx.[vw_Deliverables_alias]
AS
SELECT
    [s].[x_DeliverableId] AS [DeliverableId],
    [s].[x_CreateByResource] AS [CreateByResource],
    [s].[x_CreatedDate] AS [CreatedDate],
    [s].[x_Description] AS [Description],
    [s].[x_FinishDate] AS [FinishDate],
    [s].[x_IsFolder] AS [IsFolder],
    [s].[x_ItemRelativeUrlPath] AS [ItemRelativeUrlPath],
    [s].[x_ModifiedByResource] AS [ModifiedByResource],
    [s].[x_ModifiedDate] AS [ModifiedDate],
    [s].[x_ProjectName] AS [ProjectName],
    [s].[x_StartDate] AS [StartDate],
    [s].[x_Title] AS [Title],
    CAST(NULL AS nvarchar(4000)) AS [DependentProjects],
    CAST(NULL AS nvarchar(4000)) AS [DependentTasks],
    CAST(NULL AS nvarchar(4000)) AS [ParentProjects],
    CAST(NULL AS nvarchar(4000)) AS [ParentTasks],
    CAST(N'view=tbx.vw_Projects;source_uid=ProjectId;target_uid=ProjectId' AS nvarchar(4000)) AS [Project],
    [s].[x_ProjectId] AS [ProjectId]
FROM tbx.[vw_Deliverables_src] AS [s];
GO

CREATE   VIEW tbx.[vw_Engagements_alias]
AS
SELECT
    [s].[CommittedFinishDate] AS [CommittedFinishDate],
    [s].[CommittedMaxUnits] AS [CommittedMaxUnits],
    [s].[CommittedStartDate] AS [CommittedStartDate],
    [s].[CommittedWork] AS [CommittedWork],
    [s].[x_EngagementCreatedDate] AS [EngagementCreatedDate],
    [s].[x_EngagementModifiedDate] AS [EngagementModifiedDate],
    [s].[EngagementName] AS [EngagementName],
    [s].[x_EngagementReviewedDate] AS [EngagementReviewedDate],
    [s].[x_EngagementStatus] AS [EngagementStatus],
    [s].[x_EngagementSubmittedDate] AS [EngagementSubmittedDate],
    [s].[x_ModifiedByResourceId] AS [ModifiedByResourceId],
    [s].[ModifiedByResourceName] AS [ModifiedByResourceName],
    [s].[x_ProjectId] AS [ProjectId],
    [s].[ProjectName] AS [ProjectName],
    [s].[ProposedFinishDate] AS [ProposedFinishDate],
    [s].[ProposedMaxUnits] AS [ProposedMaxUnits],
    [s].[ProposedStartDate] AS [ProposedStartDate],
    [s].[ProposedWork] AS [ProposedWork],
    [s].[x_ResourceId] AS [ResourceId],
    [s].[ResourceName] AS [ResourceName],
    [s].[x_ReviewedByResourceId] AS [ReviewedByResourceId],
    [s].[ReviewedByResourceName] AS [ReviewedByResourceName],
    [s].[x_SubmittedByResourceId] AS [SubmittedByResourceId],
    [s].[SubmittedByResourceName] AS [SubmittedByResourceName],
    CAST(N'view=tbx.vw_EngagementsTimephasedDataSet;source_uid=EngagementId;target_uid=EngagementId' AS nvarchar(4000)) AS [TimephasedInfo],
    CAST(N'view=tbx.vw_EngagementsComments;source_uid=EngagementId;target_uid=EngagementId' AS nvarchar(4000)) AS [Comment],
    [s].[x_EngagementId] AS [EngagementId]
FROM tbx.[vw_Engagements_src] AS [s];
GO

CREATE   VIEW tbx.[vw_EngagementsComments_alias]
AS
SELECT
    [s].[x_EngagementId] AS [EngagementId],
    [s].[EngagementName] AS [EngagementName],
    [s].[CommentMessage] AS [CommentMessage],
    [s].[x_CommentCreatedDate] AS [CommentCreatedDate],
    [s].[x_AuthorId] AS [AuthorId],
    [s].[AuthorName] AS [AuthorName],
    CAST(N'view=tbx.vw_Engagements;source_uid=EngagementId;target_uid=EngagementId' AS nvarchar(4000)) AS [Engagement],
    [s].[x_CommentId] AS [CommentId]
FROM tbx.[vw_EngagementsComments_src] AS [s];
GO

CREATE   VIEW tbx.[vw_EngagementsTimephasedDataSet_alias]
AS
SELECT
    [s].[x_TimeByDay] AS [TimeByDay],
    [s].[x_CommittedMaxUnits] AS [CommittedMaxUnits],
    [s].[x_CommittedWork] AS [CommittedWork],
    [s].[x_EngagementModifiedDate] AS [EngagementModifiedDate],
    [s].[x_EngagementName] AS [EngagementName],
    [s].[x_ProjectId] AS [ProjectId],
    [s].[x_ProjectName] AS [ProjectName],
    [s].[x_ProposedMaxUnits] AS [ProposedMaxUnits],
    [s].[x_ProposedWork] AS [ProposedWork],
    [s].[x_ResourceId] AS [ResourceId],
    [s].[x_ResourceName] AS [ResourceName],
    CAST(N'view=tbx.vw_Engagements;source_uid=EngagementId;target_uid=EngagementId' AS nvarchar(4000)) AS [Engagement],
    [s].[x_EngagementId] AS [EngagementId]
FROM tbx.[vw_EngagementsTimephasedDataSet_src] AS [s];
GO

CREATE   VIEW tbx.[vw_FiscalPeriods_alias]
AS
SELECT
    [s].[x_FiscalPeriodName] AS [FiscalPeriodName],
    [s].[x_FiscalPeriodStart] AS [FiscalPeriodStart],
    [s].[x_FiscalPeriodFinish] AS [FiscalPeriodFinish],
    [s].[x_FiscalPeriodQuarter] AS [FiscalPeriodQuarter],
    [s].[x_FiscalPeriodYear] AS [FiscalPeriodYear],
    [s].[x_CreatedDate] AS [CreatedDate],
    [s].[x_FiscalPeriodModifiedDate] AS [FiscalPeriodModifiedDate],
    [s].[x_FiscalPeriodId] AS [FiscalPeriodId]
FROM tbx.[vw_FiscalPeriods_src] AS [s];
GO

CREATE   VIEW tbx.[vw_Issues_alias]
AS
SELECT
    [s].[x_IssueId] AS [IssueId],
    [s].[x_AssignedToResource] AS [AssignedToResource],
    [s].[x_Category] AS [Category],
    [s].[x_CreateByResource] AS [CreateByResource],
    [s].[x_CreatedDate] AS [CreatedDate],
    [s].[x_Discussion] AS [Discussion],
    [s].[x_DueDate] AS [DueDate],
    [s].[x_IsFolder] AS [IsFolder],
    [s].[x_ItemRelativeUrlPath] AS [ItemRelativeUrlPath],
    [s].[x_ModifiedByResource] AS [ModifiedByResource],
    [s].[x_ModifiedDate] AS [ModifiedDate],
    [s].[x_NumberOfAttachments] AS [NumberOfAttachments],
    [s].[x_Owner] AS [Owner],
    [s].[x_Priority] AS [Priority],
    [s].[x_ProjectName] AS [ProjectName],
    [s].[x_Resolution] AS [Resolution],
    [s].[x_Status] AS [Status],
    [s].[x_Title] AS [Title],
    CAST(N'view=tbx.vw_Projects;source_uid=ProjectId;target_uid=ProjectId' AS nvarchar(4000)) AS [Project],
    CAST(NULL AS nvarchar(4000)) AS [RelatedRisks],
    CAST(N'view=tbx.vw_IssueTaskAssociations;source_uid=IssueId;target_uid=IssueId' AS nvarchar(4000)) AS [Tasks],
    CAST(NULL AS nvarchar(4000)) AS [SubIssues],
    [s].[x_ProjectId] AS [ProjectId]
FROM tbx.[vw_Issues_src] AS [s];
GO

CREATE   VIEW tbx.[vw_IssueTaskAssociations_alias]
AS
SELECT
    [s].[IssueId] AS [IssueId],
    [s].[TaskId] AS [TaskId],
    [s].[RelationshipType] AS [RelationshipType],
    [s].[ProjectName] AS [ProjectName],
    [s].[RelatedProjectId] AS [RelatedProjectId],
    [s].[RelatedProjectName] AS [RelatedProjectName],
    [s].[TaskName] AS [TaskName],
    [s].[Title] AS [Title],
    CAST(N'view=tbx.vw_Issues;source_uid=IssueId;target_uid=IssueId' AS nvarchar(4000)) AS [Issue],
    CAST(N'view=tbx.vw_Tasks;source_uid=TaskId;target_uid=TaskId' AS nvarchar(4000)) AS [Task],
    CAST(N'view=tbx.vw_Projects;source_uid=ProjectId;target_uid=ProjectId' AS nvarchar(4000)) AS [Project],
    CAST(N'view=tbx.vw_Projects;source_uid=RelatedProjectId;target_uid=ProjectId' AS nvarchar(4000)) AS [RelatedProject],
    [s].[ProjectId] AS [ProjectId]
FROM tbx.[vw_IssueTaskAssociations_src] AS [s];
GO

CREATE   VIEW tbx.[vw_PortfolioAnalyses_alias]
AS
SELECT
    [s].[x_AlternateProjectEndDateCustomFieldId] AS [AlternateProjectEndDateCustomFieldId],
    [s].[AlternateProjectEndDateCustomFieldName] AS [AlternateProjectEndDateCustomFieldName],
    [s].[x_AlternateProjectStartDateCustomFieldId] AS [AlternateProjectStartDateCustomFieldId],
    [s].[AlternateProjectStartDateCustomFieldName] AS [AlternateProjectStartDateCustomFieldName],
    [s].[AnalysisDescription] AS [AnalysisDescription],
    [s].[AnalysisName] AS [AnalysisName],
    [s].[AnalysisType] AS [AnalysisType],
    [s].[BookingType] AS [BookingType],
    [s].[x_CreatedByResourceId] AS [CreatedByResourceId],
    [s].[CreatedByResourceName] AS [CreatedByResourceName],
    [s].[CreatedDate] AS [CreatedDate],
    [s].[x_DepartmentId] AS [DepartmentId],
    [s].[DepartmentName] AS [DepartmentName],
    [s].[FilterResourcesByDepartment] AS [FilterResourcesByDepartment],
    [s].[FilterResourcesByRBS] AS [FilterResourcesByRBS],
    [s].[x_FilterResourcesByRBSValueId] AS [FilterResourcesByRBSValueId],
    [s].[FilterResourcesByRBSValueText] AS [FilterResourcesByRBSValueText],
    [s].[x_ForcedInAliasLookupTableId] AS [ForcedInAliasLookupTableId],
    [s].[ForcedInAliasLookupTableName] AS [ForcedInAliasLookupTableName],
    [s].[x_ForcedOutAliasLookupTableId] AS [ForcedOutAliasLookupTableId],
    [s].[ForcedOutAliasLookupTableName] AS [ForcedOutAliasLookupTableName],
    [s].[x_HardConstraintCustomFieldId] AS [HardConstraintCustomFieldId],
    [s].[HardConstraintCustomFieldName] AS [HardConstraintCustomFieldName],
    [s].[x_ModifiedByResourceId] AS [ModifiedByResourceId],
    [s].[ModifiedByResourceName] AS [ModifiedByResourceName],
    [s].[ModifiedDate] AS [ModifiedDate],
    [s].[PlanningHorizonEndDate] AS [PlanningHorizonEndDate],
    [s].[PlanningHorizonStartDate] AS [PlanningHorizonStartDate],
    [s].[x_PrioritizationId] AS [PrioritizationId],
    [s].[PrioritizationName] AS [PrioritizationName],
    [s].[PrioritizationType] AS [PrioritizationType],
    [s].[x_RoleCustomFieldId] AS [RoleCustomFieldId],
    [s].[RoleCustomFieldName] AS [RoleCustomFieldName],
    [s].[TimeScale] AS [TimeScale],
    [s].[UseAlternateProjectDatesForResourcePlans] AS [UseAlternateProjectDatesForResourcePlans],
    CAST(N'view=tbx.vw_Resources;source_uid=CreatedByResourceId;target_uid=ResourceId' AS nvarchar(4000)) AS [CreatedByResource],
    CAST(N'view=tbx.vw_Resources;source_uid=ModifiedByResourceId;target_uid=ResourceId' AS nvarchar(4000)) AS [ModifiedByResource],
    CAST(N'view=tbx.vw_Prioritizations;source_uid=PrioritizationId;target_uid=PrioritizationId' AS nvarchar(4000)) AS [Prioritization],
    CAST(N'view=tbx.vw_PortfolioAnalysisProjects;source_uid=AnalysisId;target_uid=AnalysisId' AS nvarchar(4000)) AS [AnalysisProjects],
    CAST(N'view=tbx.vw_CostConstraintScenarios;source_uid=AnalysisId;target_uid=AnalysisId' AS nvarchar(4000)) AS [CostConstraintScenarios],
    CAST(N'view=tbx.vw_ResourceConstraintScenarios;source_uid=AnalysisId;target_uid=AnalysisId' AS nvarchar(4000)) AS [ResourceConstraintScenarios],
    [s].[x_AnalysisId] AS [AnalysisId]
FROM tbx.[vw_PortfolioAnalyses_src] AS [s];
GO

CREATE   VIEW tbx.[vw_PortfolioAnalysisProjects_alias]
AS
SELECT
    [s].[x_ProjectId] AS [ProjectId],
    [s].[AbsolutePriority] AS [AbsolutePriority],
    [s].[AnalysisName] AS [AnalysisName],
    [s].[Duration] AS [Duration],
    [s].[FinishNoLaterThan] AS [FinishNoLaterThan],
    [s].[Locked] AS [Locked],
    [s].[OriginalEndDate] AS [OriginalEndDate],
    [s].[OriginalStartDate] AS [OriginalStartDate],
    [s].[Priority] AS [Priority],
    [s].[ProjectName] AS [ProjectName],
    [s].[StartDate] AS [StartDate],
    [s].[StartNoEarlierThan] AS [StartNoEarlierThan],
    CAST(N'view=tbx.vw_PortfolioAnalyses;source_uid=AnalysisId;target_uid=AnalysisId' AS nvarchar(4000)) AS [Analysis],
    CAST(N'view=tbx.vw_Projects;source_uid=ProjectId;target_uid=ProjectId' AS nvarchar(4000)) AS [Project],
    [s].[x_AnalysisId] AS [AnalysisId]
FROM tbx.[vw_PortfolioAnalysisProjects_src] AS [s];
GO

CREATE   VIEW tbx.[vw_PrioritizationDriverRelations_alias]
AS
SELECT
    [s].[x_BusinessDriver1Id] AS [BusinessDriver1Id],
    [s].[x_BusinessDriver2Id] AS [BusinessDriver2Id],
    [s].[BusinessDriver1Name] AS [BusinessDriver1Name],
    [s].[BusinessDriver2Name] AS [BusinessDriver2Name],
    [s].[PrioritizationName] AS [PrioritizationName],
    [s].[RelationValue] AS [RelationValue],
    CAST(N'view=tbx.vw_Prioritizations;source_uid=PrioritizationId;target_uid=PrioritizationId' AS nvarchar(4000)) AS [Prioritization],
    CAST(N'view=tbx.vw_BusinessDrivers;source_uid=BusinessDriver1Id;target_uid=BusinessDriverId' AS nvarchar(4000)) AS [BusinessDriver1],
    CAST(N'view=tbx.vw_BusinessDrivers;source_uid=BusinessDriver2Id;target_uid=BusinessDriverId' AS nvarchar(4000)) AS [BusinessDriver2],
    [s].[x_PrioritizationId] AS [PrioritizationId]
FROM tbx.[vw_PrioritizationDriverRelations_src] AS [s];
GO

CREATE   VIEW tbx.[vw_PrioritizationDrivers_alias]
AS
SELECT
    [s].[x_BusinessDriverId] AS [BusinessDriverId],
    [s].[BusinessDriverName] AS [BusinessDriverName],
    [s].[BusinessDriverPriority] AS [BusinessDriverPriority],
    [s].[PrioritizationName] AS [PrioritizationName],
    CAST(N'view=tbx.vw_Prioritizations;source_uid=PrioritizationId;target_uid=PrioritizationId' AS nvarchar(4000)) AS [Prioritization],
    CAST(N'view=tbx.vw_BusinessDrivers;source_uid=BusinessDriverId;target_uid=BusinessDriverId' AS nvarchar(4000)) AS [BusinessDriver],
    [s].[x_PrioritizationId] AS [PrioritizationId]
FROM tbx.[vw_PrioritizationDrivers_src] AS [s];
GO

CREATE   VIEW tbx.[vw_Prioritizations_alias]
AS
SELECT
    [s].[ConsistencyRatio] AS [ConsistencyRatio],
    [s].[x_CreatedByResourceId] AS [CreatedByResourceId],
    [s].[CreatedByResourceName] AS [CreatedByResourceName],
    [s].[x_DepartmentId] AS [DepartmentId],
    [s].[DepartmentName] AS [DepartmentName],
    [s].[x_ModifiedByResourceId] AS [ModifiedByResourceId],
    [s].[ModifiedByResourceName] AS [ModifiedByResourceName],
    [s].[x_PrioritizationCreatedDate] AS [PrioritizationCreatedDate],
    [s].[PrioritizationDescription] AS [PrioritizationDescription],
    [s].[PrioritizationIsManual] AS [PrioritizationIsManual],
    [s].[x_PrioritizationModifiedDate] AS [PrioritizationModifiedDate],
    [s].[PrioritizationName] AS [PrioritizationName],
    CAST(N'view=tbx.vw_Resources;source_uid=CreatedByResourceId;target_uid=ResourceId' AS nvarchar(4000)) AS [CreatedByResource],
    CAST(N'view=tbx.vw_Resources;source_uid=ModifiedByResourceId;target_uid=ResourceId' AS nvarchar(4000)) AS [ModifiedByResource],
    CAST(N'view=tbx.vw_PrioritizationDrivers;source_uid=PrioritizationId;target_uid=PrioritizationId' AS nvarchar(4000)) AS [PrioritizationDrivers],
    CAST(N'view=tbx.vw_PrioritizationDriverRelations;source_uid=PrioritizationId;target_uid=PrioritizationId' AS nvarchar(4000)) AS [PrioritizationDriverRelations],
    [s].[x_PrioritizationId] AS [PrioritizationId]
FROM tbx.[vw_Prioritizations_src] AS [s];
GO

CREATE   VIEW tbx.[vw_ProjectBaselines_alias]
AS
SELECT
    [s].[x_BaselineNumber] AS [BaselineNumber],
    [s].[x_ProjectBaselineBudgetCost] AS [ProjectBaselineBudgetCost],
    [s].[x_ProjectBaselineBudgetWork] AS [ProjectBaselineBudgetWork],
    [s].[x_ProjectBaselineCost] AS [ProjectBaselineCost],
    [s].[x_ProjectBaselineDeliverableFinishDate] AS [ProjectBaselineDeliverableFinishDate],
    [s].[x_ProjectBaselineDeliverableStartDate] AS [ProjectBaselineDeliverableStartDate],
    [s].[x_ProjectBaselineDuration] AS [ProjectBaselineDuration],
    [s].[x_ProjectBaselineDurationString] AS [ProjectBaselineDurationString],
    [s].[x_ProjectBaselineFinishDate] AS [ProjectBaselineFinishDate],
    [s].[x_ProjectBaselineFinishDateString] AS [ProjectBaselineFinishDateString],
    [s].[x_ProjectBaselineFixedCost] AS [ProjectBaselineFixedCost],
    [s].[x_ProjectBaselineModifiedDate] AS [ProjectBaselineModifiedDate],
    [s].[x_ProjectBaselineStartDate] AS [ProjectBaselineStartDate],
    [s].[x_ProjectBaselineStartDateString] AS [ProjectBaselineStartDateString],
    [s].[x_ProjectBaselineWork] AS [ProjectBaselineWork],
    [s].[x_ProjectName] AS [ProjectName],
    [s].[x_TaskId] AS [TaskId],
    CAST(N'view=tbx.vw_Projects;source_uid=ProjectId;target_uid=ProjectId' AS nvarchar(4000)) AS [Project],
    [s].[x_ProjectId] AS [ProjectId]
FROM tbx.[vw_ProjectBaselines_src] AS [s];
GO

CREATE   VIEW tbx.[vw_Projects_alias]
AS
SELECT
    [s].[x_EnterpriseProjectTypeDescription] AS [EnterpriseProjectTypeDescription],
    [s].[x_EnterpriseProjectTypeId] AS [EnterpriseProjectTypeId],
    [s].[x_EnterpriseProjectTypeIsDefault] AS [EnterpriseProjectTypeIsDefault],
    [s].[x_EnterpriseProjectTypeName] AS [EnterpriseProjectTypeName],
    [s].[x_OptimizerCommitDate] AS [OptimizerCommitDate],
    [s].[x_OptimizerDecisionAliasLookupTableId] AS [OptimizerDecisionAliasLookupTableId],
    [s].[x_OptimizerDecisionAliasLookupTableValueId] AS [OptimizerDecisionAliasLookupTableValueId],
    [s].[x_OptimizerDecisionID] AS [OptimizerDecisionID],
    [s].[x_OptimizerDecisionName] AS [OptimizerDecisionName],
    [s].[x_OptimizerSolutionName] AS [OptimizerSolutionName],
    [s].[x_ParentProjectId] AS [ParentProjectId],
    [s].[x_PlannerCommitDate] AS [PlannerCommitDate],
    [s].[x_PlannerDecisionAliasLookupTableId] AS [PlannerDecisionAliasLookupTableId],
    [s].[x_PlannerDecisionAliasLookupTableValueId] AS [PlannerDecisionAliasLookupTableValueId],
    [s].[x_PlannerDecisionID] AS [PlannerDecisionID],
    [s].[x_PlannerDecisionName] AS [PlannerDecisionName],
    [s].[x_PlannerEndDate] AS [PlannerEndDate],
    [s].[x_PlannerSolutionName] AS [PlannerSolutionName],
    [s].[x_PlannerStartDate] AS [PlannerStartDate],
    [s].[ProjectActualCost] AS [ProjectActualCost],
    [s].[ProjectActualDuration] AS [ProjectActualDuration],
    [s].[ProjectActualFinishDate] AS [ProjectActualFinishDate],
    [s].[ProjectActualOvertimeCost] AS [ProjectActualOvertimeCost],
    [s].[ProjectActualOvertimeWork] AS [ProjectActualOvertimeWork],
    [s].[ProjectActualRegularCost] AS [ProjectActualRegularCost],
    [s].[ProjectActualRegularWork] AS [ProjectActualRegularWork],
    [s].[ProjectActualStartDate] AS [ProjectActualStartDate],
    [s].[ProjectActualWork] AS [ProjectActualWork],
    [s].[ProjectACWP] AS [ProjectACWP],
    [s].[ProjectAuthorName] AS [ProjectAuthorName],
    [s].[ProjectBCWP] AS [ProjectBCWP],
    [s].[ProjectBCWS] AS [ProjectBCWS],
    [s].[ProjectBudgetCost] AS [ProjectBudgetCost],
    [s].[ProjectBudgetWork] AS [ProjectBudgetWork],
    [s].[ProjectCalculationsAreStale] AS [ProjectCalculationsAreStale],
    [s].[ProjectCalendarDuration] AS [ProjectCalendarDuration],
    [s].[ProjectCategoryName] AS [ProjectCategoryName],
    [s].[ProjectCompanyName] AS [ProjectCompanyName],
    [s].[ProjectCost] AS [ProjectCost],
    [s].[ProjectCostVariance] AS [ProjectCostVariance],
    [s].[ProjectCPI] AS [ProjectCPI],
    [s].[ProjectCreatedDate] AS [ProjectCreatedDate],
    [s].[ProjectCurrency] AS [ProjectCurrency],
    [s].[ProjectCV] AS [ProjectCV],
    [s].[ProjectCVP] AS [ProjectCVP],
    [s].[ProjectDescription] AS [ProjectDescription],
    [s].[ProjectDuration] AS [ProjectDuration],
    [s].[ProjectDurationVariance] AS [ProjectDurationVariance],
    [s].[ProjectEAC] AS [ProjectEAC],
    [s].[ProjectEarlyFinish] AS [ProjectEarlyFinish],
    [s].[ProjectEarlyStart] AS [ProjectEarlyStart],
    [s].[ProjectEarnedValueIsStale] AS [ProjectEarnedValueIsStale],
    CAST(NULL AS bit) AS [ProjectEnterpriseFeatures],
    [s].[ProjectFinishDate] AS [ProjectFinishDate],
    [s].[ProjectFinishVariance] AS [ProjectFinishVariance],
    [s].[ProjectFixedCost] AS [ProjectFixedCost],
    [s].[x_ProjectIdentifier] AS [ProjectIdentifier],
    [s].[ProjectKeywords] AS [ProjectKeywords],
    [s].[ProjectLateFinish] AS [ProjectLateFinish],
    [s].[ProjectLateStart] AS [ProjectLateStart],
    [s].[x_ProjectLastPublishedDate] AS [ProjectLastPublishedDate],
    [s].[ProjectManagerName] AS [ProjectManagerName],
    [s].[ProjectModifiedDate] AS [ProjectModifiedDate],
    [s].[ProjectName] AS [ProjectName],
    [s].[ProjectOvertimeCost] AS [ProjectOvertimeCost],
    [s].[ProjectOvertimeWork] AS [ProjectOvertimeWork],
    [s].[x_ProjectOwnerId] AS [ProjectOwnerId],
    [s].[ProjectOwnerName] AS [ProjectOwnerName],
    [s].[ProjectPercentCompleted] AS [ProjectPercentCompleted],
    [s].[ProjectPercentWorkCompleted] AS [ProjectPercentWorkCompleted],
    [s].[ProjectRegularCost] AS [ProjectRegularCost],
    [s].[ProjectRegularWork] AS [ProjectRegularWork],
    [s].[ProjectRemainingCost] AS [ProjectRemainingCost],
    [s].[ProjectRemainingDuration] AS [ProjectRemainingDuration],
    [s].[ProjectRemainingOvertimeCost] AS [ProjectRemainingOvertimeCost],
    [s].[ProjectRemainingOvertimeWork] AS [ProjectRemainingOvertimeWork],
    [s].[ProjectRemainingRegularCost] AS [ProjectRemainingRegularCost],
    [s].[ProjectRemainingRegularWork] AS [ProjectRemainingRegularWork],
    [s].[ProjectRemainingWork] AS [ProjectRemainingWork],
    [s].[ProjectResourcePlanWork] AS [ProjectResourcePlanWork],
    [s].[ProjectSPI] AS [ProjectSPI],
    [s].[ProjectStartDate] AS [ProjectStartDate],
    [s].[ProjectStartVariance] AS [ProjectStartVariance],
    [s].[ProjectStatusDate] AS [ProjectStatusDate],
    [s].[ProjectSubject] AS [ProjectSubject],
    [s].[ProjectSV] AS [ProjectSV],
    [s].[ProjectSVP] AS [ProjectSVP],
    [s].[ProjectTCPI] AS [ProjectTCPI],
    [s].[x_ProjectTimephased] AS [ProjectTimephased],
    [s].[x_ProjectTitle] AS [ProjectTitle],
    [s].[ProjectType] AS [ProjectType],
    [s].[ProjectVAC] AS [ProjectVAC],
    [s].[ProjectWork] AS [ProjectWork],
    [s].[x_ProjectWorkspaceInternalUrl] AS [ProjectWorkspaceInternalUrl],
    [s].[ProjectWorkVariance] AS [ProjectWorkVariance],
    [s].[ResourcePlanUtilizationDate] AS [ResourcePlanUtilizationDate],
    [s].[ResourcePlanUtilizationType] AS [ResourcePlanUtilizationType],
    [s].[x_WorkflowCreatedDate] AS [WorkflowCreatedDate],
    [s].[x_WorkflowError] AS [WorkflowError],
    [s].[x_WorkflowErrorResponseCode] AS [WorkflowErrorResponseCode],
    [s].[x_WorkflowInstanceId] AS [WorkflowInstanceId],
    [s].[x_WorkflowOwnerId] AS [WorkflowOwnerId],
    [s].[x_WorkflowOwnerName] AS [WorkflowOwnerName],
    CAST(NULL AS nvarchar(4000)) AS [ProjectDepartments],
    CAST(NULL AS nvarchar(4000)) AS [Statutduprojet],
    CAST(NULL AS nvarchar(4000)) AS [Typedebudget],
    CAST(NULL AS nvarchar(4000)) AS [PBS],
    CAST(NULL AS nvarchar(4000)) AS [Annéedubudget],
    CAST(NULL AS decimal(38,6)) AS [Montantdubudget],
    CAST(N'view=tbx.vw_AssignmentBaselines;source_uid=ProjectId;target_uid=ProjectId' AS nvarchar(4000)) AS [AssignmentBaselines],
    CAST(N'view=tbx.vw_Assignments;source_uid=ProjectId;target_uid=ProjectId' AS nvarchar(4000)) AS [Assignments],
    CAST(N'view=tbx.vw_Deliverables;source_uid=ProjectId;target_uid=ProjectId' AS nvarchar(4000)) AS [Deliverables],
    CAST(NULL AS nvarchar(4000)) AS [Dependencies],
    CAST(N'view=tbx.vw_Issues;source_uid=ProjectId;target_uid=ProjectId' AS nvarchar(4000)) AS [Issues],
    CAST(N'view=tbx.vw_Risks;source_uid=ProjectId;target_uid=ProjectId' AS nvarchar(4000)) AS [Risks],
    CAST(N'view=tbx.vw_ProjectWorkflowStageDataSet;source_uid=ProjectId;target_uid=ProjectId' AS nvarchar(4000)) AS [StagesInfo],
    CAST(N'view=tbx.vw_Tasks;source_uid=ProjectId;target_uid=ProjectId' AS nvarchar(4000)) AS [Tasks],
    [s].[x_ProjectId] AS [ProjectId],
    CAST(NULL AS nvarchar(4000)) AS [CF_Etat],
    CAST(NULL AS nvarchar(4000)) AS [CF_Priorite_P],
    CAST(NULL AS nvarchar(4000)) AS [CF_TypeProjet]
FROM tbx.[vw_Projects_src] AS [s];
GO

CREATE   VIEW tbx.[vw_ProjectWorkflowStageDataSet_alias]
AS
SELECT
    [s].[StageId] AS [StageId],
    [s].[LastModifiedDate] AS [LastModifiedDate],
    [s].[LCID] AS [LCID],
    [s].[PhaseDescription] AS [PhaseDescription],
    [s].[PhaseName] AS [PhaseName],
    [s].[ProjectName] AS [ProjectName],
    [s].[StageCompletionDate] AS [StageCompletionDate],
    [s].[StageDescription] AS [StageDescription],
    [s].[StageEntryDate] AS [StageEntryDate],
    [s].[StageInformation] AS [StageInformation],
    [s].[x_StageLastSubmittedDate] AS [StageLastSubmittedDate],
    [s].[StageName] AS [StageName],
    [s].[StageOrder] AS [StageOrder],
    [s].[StageStateDescription] AS [StageStateDescription],
    [s].[StageStatus] AS [StageStatus],
    CAST(N'view=tbx.vw_Projects;source_uid=ProjectId;target_uid=ProjectId' AS nvarchar(4000)) AS [Project],
    [s].[ProjectId] AS [ProjectId]
FROM tbx.[vw_ProjectWorkflowStageDataSet_src] AS [s];
GO

CREATE   VIEW tbx.[vw_ResourceConstraintScenarios_alias]
AS
SELECT
    [s].[AllocationThreshold] AS [AllocationThreshold],
    [s].[x_AnalysisId] AS [AnalysisId],
    [s].[AnalysisName] AS [AnalysisName],
    [s].[ConstraintType] AS [ConstraintType],
    [s].[ConstraintValue] AS [ConstraintValue],
    [s].[x_CostConstraintScenarioId] AS [CostConstraintScenarioId],
    [s].[CostConstraintScenarioName] AS [CostConstraintScenarioName],
    [s].[x_CreatedByResourceId] AS [CreatedByResourceId],
    [s].[CreatedByResourceName] AS [CreatedByResourceName],
    [s].[CreatedDate] AS [CreatedDate],
    [s].[EnforceProjectDependencies] AS [EnforceProjectDependencies],
    [s].[EnforceSchedulingConstraints] AS [EnforceSchedulingConstraints],
    [s].[HiringType] AS [HiringType],
    [s].[x_ModifiedByResourceId] AS [ModifiedByResourceId],
    [s].[ModifiedByResourceName] AS [ModifiedByResourceName],
    [s].[ModifiedDate] AS [ModifiedDate],
    [s].[RateTable] AS [RateTable],
    [s].[ScenarioDescription] AS [ScenarioDescription],
    [s].[ScenarioName] AS [ScenarioName],
    CAST(N'view=tbx.vw_Resources;source_uid=CreatedByResourceId;target_uid=ResourceId' AS nvarchar(4000)) AS [CreatedByResource],
    CAST(N'view=tbx.vw_Resources;source_uid=ModifiedByResourceId;target_uid=ResourceId' AS nvarchar(4000)) AS [ModifiedByResource],
    CAST(N'view=tbx.vw_PortfolioAnalyses;source_uid=AnalysisId;target_uid=AnalysisId' AS nvarchar(4000)) AS [Analysis],
    CAST(N'view=tbx.vw_CostConstraintScenarios;source_uid=CostConstraintScenarioId;target_uid=ScenarioId' AS nvarchar(4000)) AS [CostConstraintScenario],
    CAST(N'view=tbx.vw_ResourceScenarioProjects;source_uid=ScenarioId;target_uid=ScenarioId' AS nvarchar(4000)) AS [ResourceScenarioProjects],
    [s].[x_ScenarioId] AS [ScenarioId]
FROM tbx.[vw_ResourceConstraintScenarios_src] AS [s];
GO

CREATE   VIEW tbx.[vw_ResourceDemandTimephasedDataSet_alias]
AS
SELECT
    [s].[x_ResourceId] AS [ResourceId],
    [s].[x_TimeByDay] AS [TimeByDay],
    [s].[x_FiscalPeriodId] AS [FiscalPeriodId],
    [s].[x_ProjectName] AS [ProjectName],
    [s].[ResourceDemand] AS [ResourceDemand],
    [s].[ResourceDemandModifiedDate] AS [ResourceDemandModifiedDate],
    [s].[x_ResourceName] AS [ResourceName],
    [s].[x_ResourcePlanUtilizationDate] AS [ResourcePlanUtilizationDate],
    [s].[x_ResourcePlanUtilizationType] AS [ResourcePlanUtilizationType],
    CAST(N'view=tbx.vw_Resources;source_uid=ResourceId;target_uid=ResourceId' AS nvarchar(4000)) AS [Resource],
    CAST(N'view=tbx.vw_Projects;source_uid=ProjectId;target_uid=ProjectId' AS nvarchar(4000)) AS [Project],
    CAST(N'view=tbx.vw_TimeSet;source_uid=TimeByDay;target_uid=TimeByDay' AS nvarchar(4000)) AS [Time],
    [s].[x_ProjectId] AS [ProjectId]
FROM tbx.[vw_ResourceDemandTimephasedDataSet_src] AS [s];
GO

CREATE   VIEW tbx.[vw_Resources_alias]
AS
SELECT
    [s].[ResourceBaseCalendar] AS [ResourceBaseCalendar],
    [s].[ResourceBookingType] AS [ResourceBookingType],
    [s].[ResourceCanLevel] AS [ResourceCanLevel],
    [s].[ResourceCode] AS [ResourceCode],
    [s].[ResourceCostCenter] AS [ResourceCostCenter],
    [s].[ResourceCostPerUse] AS [ResourceCostPerUse],
    [s].[ResourceCreatedDate] AS [ResourceCreatedDate],
    [s].[ResourceEarliestAvailableFrom] AS [ResourceEarliestAvailableFrom],
    [s].[ResourceEmailAddress] AS [ResourceEmailAddress],
    [s].[ResourceGroup] AS [ResourceGroup],
    [s].[ResourceHyperlink] AS [ResourceHyperlink],
    [s].[ResourceHyperlinkHref] AS [ResourceHyperlinkHref],
    [s].[ResourceInitials] AS [ResourceInitials],
    [s].[ResourceIsActive] AS [ResourceIsActive],
    [s].[ResourceIsGeneric] AS [ResourceIsGeneric],
    [s].[ResourceIsTeam] AS [ResourceIsTeam],
    [s].[ResourceLatestAvailableTo] AS [ResourceLatestAvailableTo],
    [s].[ResourceMaterialLabel] AS [ResourceMaterialLabel],
    [s].[ResourceMaxUnits] AS [ResourceMaxUnits],
    [s].[ResourceModifiedDate] AS [ResourceModifiedDate],
    [s].[ResourceName] AS [ResourceName],
    [s].[ResourceNTAccount] AS [ResourceNTAccount],
    [s].[ResourceOvertimeRate] AS [ResourceOvertimeRate],
    [s].[ResourceStandardRate] AS [ResourceStandardRate],
    [s].[x_ResourceStatusId] AS [ResourceStatusId],
    [s].[x_ResourceStatusName] AS [ResourceStatusName],
    [s].[x_ResourceTimesheetManageId] AS [ResourceTimesheetManageId],
    [s].[ResourceType] AS [ResourceType],
    [s].[ResourceWorkgroup] AS [ResourceWorkgroup],
    [s].[x_TypeDescription] AS [TypeDescription],
    [s].[x_TypeName] AS [TypeName],
    CAST(NULL AS nvarchar(4000)) AS [RBS],
    CAST(NULL AS nvarchar(4000)) AS [ResourceDepartments],
    CAST(NULL AS nvarchar(4000)) AS [TeamName],
    CAST(NULL AS nvarchar(4000)) AS [CostType],
    CAST(NULL AS nvarchar(4000)) AS [Profilderessource],
    CAST(NULL AS bit) AS [CongédeFdT],
    CAST(NULL AS nvarchar(4000)) AS [Courrielsupérieurhiérarchique],
    CAST(NULL AS nvarchar(4000)) AS [Notedepilotage],
    CAST(NULL AS nvarchar(4000)) AS [OBS],
    CAST(NULL AS bit) AS [RappelFdTavisersupérieur],
    CAST(NULL AS nvarchar(4000)) AS [Typedecoût],
    CAST(N'view=tbx.vw_Assignments;source_uid=ResourceId;target_uid=ResourceId' AS nvarchar(4000)) AS [Assignments],
    CAST(N'view=tbx.vw_ResourceTimephasedDataSet;source_uid=ResourceId;target_uid=ResourceId' AS nvarchar(4000)) AS [TimephasedInfoDataSet],
    CAST(N'view=tbx.vw_ResourceDemandTimephasedDataSet;source_uid=ResourceId;target_uid=ResourceId' AS nvarchar(4000)) AS [ResourceDemandTimephasedInfo],
    [s].[x_ResourceId] AS [ResourceId],
    CAST(NULL AS nvarchar(4000)) AS [CF_UA]
FROM tbx.[vw_Resources_src] AS [s];
GO

CREATE   VIEW tbx.[vw_ResourceScenarioProjects_alias]
AS
SELECT
    [s].[x_ProjectId] AS [ProjectId],
    [s].[AbsolutePriority] AS [AbsolutePriority],
    [s].[x_AnalysisId] AS [AnalysisId],
    [s].[AnalysisName] AS [AnalysisName],
    [s].[x_CostConstraintScenarioId] AS [CostConstraintScenarioId],
    [s].[CostConstraintScenarioName] AS [CostConstraintScenarioName],
    [s].[x_ForceAliasLookupTableId] AS [ForceAliasLookupTableId],
    [s].[ForceAliasLookupTableName] AS [ForceAliasLookupTableName],
    [s].[ForceStatus] AS [ForceStatus],
    [s].[HardConstraintValue] AS [HardConstraintValue],
    [s].[NewStartDate] AS [NewStartDate],
    [s].[Priority] AS [Priority],
    [s].[ProjectName] AS [ProjectName],
    [s].[ResourceCost] AS [ResourceCost],
    [s].[ResourceWork] AS [ResourceWork],
    [s].[ScenarioName] AS [ScenarioName],
    [s].[Status] AS [Status],
    CAST(N'view=tbx.vw_Projects;source_uid=ProjectId;target_uid=ProjectId' AS nvarchar(4000)) AS [Project],
    CAST(N'view=tbx.vw_PortfolioAnalyses;source_uid=AnalysisId;target_uid=AnalysisId' AS nvarchar(4000)) AS [Analysis],
    CAST(N'view=tbx.vw_CostConstraintScenarios;source_uid=CostConstraintScenarioId;target_uid=ScenarioId' AS nvarchar(4000)) AS [CostConstraintScenario],
    CAST(N'view=tbx.vw_ResourceConstraintScenarios;source_uid=ScenarioId;target_uid=ScenarioId' AS nvarchar(4000)) AS [ResourceConstraintScenario],
    [s].[x_ScenarioId] AS [ScenarioId]
FROM tbx.[vw_ResourceScenarioProjects_src] AS [s];
GO

CREATE   VIEW tbx.[vw_ResourceTimephasedDataSet_alias]
AS
SELECT
    [s].[x_TimeByDay] AS [TimeByDay],
    [s].[x_BaseCapacity] AS [BaseCapacity],
    [s].[x_Capacity] AS [Capacity],
    [s].[x_FiscalPeriodId] AS [FiscalPeriodId],
    [s].[x_ResourceModifiedDate] AS [ResourceModifiedDate],
    [s].[x_ResourceName] AS [ResourceName],
    CAST(N'view=tbx.vw_Resources;source_uid=ResourceId;target_uid=ResourceId' AS nvarchar(4000)) AS [Resource],
    CAST(N'view=tbx.vw_TimeSet;source_uid=TimeByDay;target_uid=TimeByDay' AS nvarchar(4000)) AS [Time],
    [s].[x_ResourceId] AS [ResourceId]
FROM tbx.[vw_ResourceTimephasedDataSet_src] AS [s];
GO

CREATE   VIEW tbx.[vw_Risks_alias]
AS
SELECT
    [s].[x_RiskId] AS [RiskId],
    [s].[x_AssignedToResource] AS [AssignedToResource],
    [s].[x_Category] AS [Category],
    [s].[x_ContingencyPlan] AS [ContingencyPlan],
    [s].[x_Cost] AS [Cost],
    [s].[x_CostExposure] AS [CostExposure],
    [s].[x_CreateByResource] AS [CreateByResource],
    [s].[x_CreatedDate] AS [CreatedDate],
    [s].[x_Description] AS [Description],
    [s].[x_DueDate] AS [DueDate],
    [s].[x_Exposure] AS [Exposure],
    [s].[x_Impact] AS [Impact],
    [s].[x_IsFolder] AS [IsFolder],
    [s].[x_ItemRelativeUrlPath] AS [ItemRelativeUrlPath],
    [s].[x_MitigationPlan] AS [MitigationPlan],
    [s].[x_ModifiedByResource] AS [ModifiedByResource],
    [s].[x_ModifiedDate] AS [ModifiedDate],
    [s].[x_NumberOfAttachments] AS [NumberOfAttachments],
    [s].[x_Owner] AS [Owner],
    [s].[x_Probability] AS [Probability],
    [s].[x_ProjectName] AS [ProjectName],
    [s].[x_Status] AS [Status],
    [s].[x_Title] AS [Title],
    [s].[x_TriggerDescription] AS [TriggerDescription],
    [s].[x_TriggerTask] AS [TriggerTask],
    CAST(N'view=tbx.vw_Projects;source_uid=ProjectId;target_uid=ProjectId' AS nvarchar(4000)) AS [Project],
    CAST(NULL AS nvarchar(4000)) AS [RelatedIssues],
    CAST(NULL AS nvarchar(4000)) AS [SubRisks],
    CAST(N'view=tbx.vw_RiskTaskAssociations;source_uid=RiskId;target_uid=RiskId' AS nvarchar(4000)) AS [Tasks],
    [s].[x_ProjectId] AS [ProjectId]
FROM tbx.[vw_Risks_src] AS [s];
GO

CREATE   VIEW tbx.[vw_RiskTaskAssociations_alias]
AS
SELECT
    [s].[RiskId] AS [RiskId],
    [s].[TaskId] AS [TaskId],
    [s].[RelationshipType] AS [RelationshipType],
    [s].[ProjectName] AS [ProjectName],
    [s].[RelatedProjectId] AS [RelatedProjectId],
    [s].[RelatedProjectName] AS [RelatedProjectName],
    [s].[TaskName] AS [TaskName],
    [s].[Title] AS [Title],
    CAST(N'view=tbx.vw_Risks;source_uid=RiskId;target_uid=RiskId' AS nvarchar(4000)) AS [Risk],
    CAST(N'view=tbx.vw_Tasks;source_uid=TaskId;target_uid=TaskId' AS nvarchar(4000)) AS [Task],
    CAST(N'view=tbx.vw_Projects;source_uid=ProjectId;target_uid=ProjectId' AS nvarchar(4000)) AS [Project],
    CAST(N'view=tbx.vw_Projects;source_uid=RelatedProjectId;target_uid=ProjectId' AS nvarchar(4000)) AS [RelatedProject],
    [s].[ProjectId] AS [ProjectId]
FROM tbx.[vw_RiskTaskAssociations_src] AS [s];
GO

CREATE   VIEW tbx.[vw_TaskBaselines_alias]
AS
SELECT
    [s].[x_TaskId] AS [TaskId],
    [s].[x_BaselineNumber] AS [BaselineNumber],
    [s].[x_ProjectName] AS [ProjectName],
    [s].[x_TaskBaselineBudgetCost] AS [TaskBaselineBudgetCost],
    [s].[x_TaskBaselineBudgetWork] AS [TaskBaselineBudgetWork],
    [s].[x_TaskBaselineCost] AS [TaskBaselineCost],
    [s].[x_TaskBaselineDeliverableFinishDate] AS [TaskBaselineDeliverableFinishDate],
    [s].[x_TaskBaselineDeliverableStartDate] AS [TaskBaselineDeliverableStartDate],
    [s].[x_TaskBaselineDuration] AS [TaskBaselineDuration],
    [s].[x_TaskBaselineDurationString] AS [TaskBaselineDurationString],
    [s].[x_TaskBaselineFinishDate] AS [TaskBaselineFinishDate],
    [s].[x_TaskBaselineFinishDateString] AS [TaskBaselineFinishDateString],
    [s].[x_TaskBaselineFixedCost] AS [TaskBaselineFixedCost],
    [s].[x_TaskBaselineModifiedDate] AS [TaskBaselineModifiedDate],
    [s].[x_TaskBaselineStartDate] AS [TaskBaselineStartDate],
    [s].[x_TaskBaselineStartDateString] AS [TaskBaselineStartDateString],
    [s].[x_TaskBaselineWork] AS [TaskBaselineWork],
    [s].[x_TaskName] AS [TaskName],
    CAST(N'view=tbx.vw_Projects;source_uid=ProjectId;target_uid=ProjectId' AS nvarchar(4000)) AS [Project],
    CAST(N'view=tbx.vw_Tasks;source_uid=TaskId;target_uid=TaskId' AS nvarchar(4000)) AS [Task],
    CAST(N'view=tbx.vw_TaskBaselineTimephasedDataSet;source_uid=TaskId;target_uid=TaskId' AS nvarchar(4000)) AS [TaskBaselineTimephasedDataSet],
    [s].[x_ProjectId] AS [ProjectId]
FROM tbx.[vw_TaskBaselines_src] AS [s];
GO

CREATE   VIEW tbx.[vw_TaskBaselineTimephasedDataSet_alias]
AS
SELECT
    [s].[x_TaskId] AS [TaskId],
    [s].[x_TimeByDay] AS [TimeByDay],
    [s].[x_BaselineNumber] AS [BaselineNumber],
    [s].[x_FiscalPeriodId] AS [FiscalPeriodId],
    [s].[x_ProjectName] AS [ProjectName],
    [s].[x_TaskBaselineBudgetCost] AS [TaskBaselineBudgetCost],
    [s].[x_TaskBaselineBudgetWork] AS [TaskBaselineBudgetWork],
    [s].[x_TaskBaselineCost] AS [TaskBaselineCost],
    [s].[x_TaskBaselineFixedCost] AS [TaskBaselineFixedCost],
    [s].[x_TaskBaselineModifiedDate] AS [TaskBaselineModifiedDate],
    [s].[x_TaskBaselineWork] AS [TaskBaselineWork],
    [s].[x_TaskName] AS [TaskName],
    CAST(N'view=tbx.vw_Projects;source_uid=ProjectId;target_uid=ProjectId' AS nvarchar(4000)) AS [Project],
    CAST(N'view=tbx.vw_Tasks;source_uid=TaskId;target_uid=TaskId' AS nvarchar(4000)) AS [Task],
    CAST(N'view=tbx.vw_TaskBaselines;source_uid=TaskId;target_uid=TaskId' AS nvarchar(4000)) AS [TaskBaselines],
    CAST(N'view=tbx.vw_TimeSet;source_uid=TimeByDay;target_uid=TimeByDay' AS nvarchar(4000)) AS [Time],
    [s].[x_ProjectId] AS [ProjectId]
FROM tbx.[vw_TaskBaselineTimephasedDataSet_src] AS [s];
GO

CREATE   VIEW tbx.[vw_Tasks_alias]
AS
SELECT
    [s].[x_TaskId] AS [TaskId],
    [s].[x_ParentTaskId] AS [ParentTaskId],
    [s].[x_ParentTaskName] AS [ParentTaskName],
    [s].[x_ProjectName] AS [ProjectName],
    [s].[TaskActualCost] AS [TaskActualCost],
    [s].[TaskActualDuration] AS [TaskActualDuration],
    [s].[TaskActualFinishDate] AS [TaskActualFinishDate],
    [s].[TaskActualFixedCost] AS [TaskActualFixedCost],
    [s].[TaskActualOvertimeCost] AS [TaskActualOvertimeCost],
    [s].[TaskActualOvertimeWork] AS [TaskActualOvertimeWork],
    [s].[TaskActualRegularCost] AS [TaskActualRegularCost],
    [s].[TaskActualRegularWork] AS [TaskActualRegularWork],
    [s].[TaskActualStartDate] AS [TaskActualStartDate],
    [s].[TaskActualWork] AS [TaskActualWork],
    [s].[TaskACWP] AS [TaskACWP],
    [s].[TaskBCWP] AS [TaskBCWP],
    [s].[TaskBCWS] AS [TaskBCWS],
    [s].[TaskBudgetCost] AS [TaskBudgetCost],
    [s].[TaskBudgetWork] AS [TaskBudgetWork],
    [s].[TaskClientUniqueId] AS [TaskClientUniqueId],
    [s].[TaskCost] AS [TaskCost],
    [s].[TaskCostVariance] AS [TaskCostVariance],
    [s].[TaskCPI] AS [TaskCPI],
    [s].[TaskCreatedDate] AS [TaskCreatedDate],
    [s].[TaskCreatedRevisionCounter] AS [TaskCreatedRevisionCounter],
    [s].[TaskCV] AS [TaskCV],
    [s].[TaskCVP] AS [TaskCVP],
    [s].[TaskDeadline] AS [TaskDeadline],
    [s].[TaskDeliverableFinishDate] AS [TaskDeliverableFinishDate],
    [s].[TaskDeliverableStartDate] AS [TaskDeliverableStartDate],
    [s].[TaskDuration] AS [TaskDuration],
    [s].[TaskDurationIsEstimated] AS [TaskDurationIsEstimated],
    [s].[TaskDurationString] AS [TaskDurationString],
    [s].[TaskDurationVariance] AS [TaskDurationVariance],
    [s].[TaskEAC] AS [TaskEAC],
    [s].[TaskEarlyFinish] AS [TaskEarlyFinish],
    [s].[TaskEarlyStart] AS [TaskEarlyStart],
    [s].[TaskFinishDate] AS [TaskFinishDate],
    [s].[TaskFinishDateString] AS [TaskFinishDateString],
    [s].[TaskFinishVariance] AS [TaskFinishVariance],
    [s].[TaskFixedCost] AS [TaskFixedCost],
    [s].[x_TaskFixedCostAssignmentId] AS [TaskFixedCostAssignmentId],
    [s].[TaskFreeSlack] AS [TaskFreeSlack],
    [s].[TaskHyperLinkAddress] AS [TaskHyperLinkAddress],
    [s].[TaskHyperLinkFriendlyName] AS [TaskHyperLinkFriendlyName],
    [s].[TaskHyperLinkSubAddress] AS [TaskHyperLinkSubAddress],
    [s].[TaskIgnoresResourceCalendar] AS [TaskIgnoresResourceCalendar],
    [s].[TaskIndex] AS [TaskIndex],
    [s].[TaskIsActive] AS [TaskIsActive],
    [s].[TaskIsCritical] AS [TaskIsCritical],
    [s].[TaskIsEffortDriven] AS [TaskIsEffortDriven],
    [s].[TaskIsExternal] AS [TaskIsExternal],
    [s].[TaskIsManuallyScheduled] AS [TaskIsManuallyScheduled],
    [s].[TaskIsMarked] AS [TaskIsMarked],
    [s].[TaskIsMilestone] AS [TaskIsMilestone],
    [s].[TaskIsOverallocated] AS [TaskIsOverallocated],
    [s].[TaskIsProjectSummary] AS [TaskIsProjectSummary],
    [s].[TaskIsRecurring] AS [TaskIsRecurring],
    [s].[TaskIsSummary] AS [TaskIsSummary],
    [s].[TaskLateFinish] AS [TaskLateFinish],
    [s].[TaskLateStart] AS [TaskLateStart],
    [s].[TaskLevelingDelay] AS [TaskLevelingDelay],
    [s].[TaskModifiedDate] AS [TaskModifiedDate],
    [s].[TaskModifiedRevisionCounter] AS [TaskModifiedRevisionCounter],
    [s].[TaskName] AS [TaskName],
    [s].[TaskOutlineLevel] AS [TaskOutlineLevel],
    [s].[TaskOutlineNumber] AS [TaskOutlineNumber],
    [s].[TaskOvertimeCost] AS [TaskOvertimeCost],
    [s].[TaskOvertimeWork] AS [TaskOvertimeWork],
    [s].[TaskPercentCompleted] AS [TaskPercentCompleted],
    [s].[TaskPercentWorkCompleted] AS [TaskPercentWorkCompleted],
    [s].[TaskPhysicalPercentCompleted] AS [TaskPhysicalPercentCompleted],
    [s].[TaskPriority] AS [TaskPriority],
    [s].[TaskRegularCost] AS [TaskRegularCost],
    [s].[TaskRegularWork] AS [TaskRegularWork],
    [s].[TaskRemainingCost] AS [TaskRemainingCost],
    [s].[TaskRemainingDuration] AS [TaskRemainingDuration],
    [s].[TaskRemainingOvertimeCost] AS [TaskRemainingOvertimeCost],
    [s].[TaskRemainingOvertimeWork] AS [TaskRemainingOvertimeWork],
    [s].[TaskRemainingRegularCost] AS [TaskRemainingRegularCost],
    [s].[TaskRemainingRegularWork] AS [TaskRemainingRegularWork],
    [s].[TaskRemainingWork] AS [TaskRemainingWork],
    [s].[TaskResourcePlanWork] AS [TaskResourcePlanWork],
    [s].[TaskSPI] AS [TaskSPI],
    [s].[TaskStartDate] AS [TaskStartDate],
    [s].[TaskStartDateString] AS [TaskStartDateString],
    [s].[TaskStartVariance] AS [TaskStartVariance],
    [s].[TaskStatusManagerUID] AS [TaskStatusManagerUID],
    [s].[TaskSV] AS [TaskSV],
    [s].[TaskSVP] AS [TaskSVP],
    [s].[TaskTCPI] AS [TaskTCPI],
    [s].[TaskTotalSlack] AS [TaskTotalSlack],
    [s].[TaskVAC] AS [TaskVAC],
    [s].[TaskWBS] AS [TaskWBS],
    [s].[TaskWork] AS [TaskWork],
    [s].[TaskWorkVariance] AS [TaskWorkVariance],
    CAST(NULL AS nvarchar(4000)) AS [FlagStatus],
    CAST(NULL AS nvarchar(4000)) AS [Health],
    CAST(NULL AS nvarchar(4000)) AS [Contexte],
    CAST(NULL AS bit) AS [Verrouilléeentreprise],
    CAST(NULL AS bit) AS [IgnorerRàF],
    CAST(NULL AS bit) AS [Capitalisable],
    CAST(NULL AS nvarchar(4000)) AS [CompteComptableExterne],
    CAST(NULL AS nvarchar(4000)) AS [CodeDeProjet],
    CAST(NULL AS nvarchar(4000)) AS [zzUnitéAdministrative],
    CAST(NULL AS nvarchar(4000)) AS [UnitéAdministrative],
    CAST(NULL AS nvarchar(4000)) AS [NoContrat],
    CAST(NULL AS nvarchar(4000)) AS [NoDemande],
    CAST(NULL AS nvarchar(4000)) AS [NoItem],
    CAST(NULL AS nvarchar(4000)) AS [DescItem],
    CAST(NULL AS decimal(38,6)) AS [NoEpic],
    CAST(NULL AS nvarchar(4000)) AS [NoRéférence],
    CAST(N'view=tbx.vw_Assignments;source_uid=TaskId;target_uid=TaskId' AS nvarchar(4000)) AS [Assignments],
    CAST(N'view=tbx.vw_AssignmentBaselines;source_uid=TaskId;target_uid=TaskId' AS nvarchar(4000)) AS [AssignmentsBaselines],
    CAST(N'view=tbx.vw_AssignmentBaselineTimephasedDataSet;source_uid=TaskId;target_uid=TaskId' AS nvarchar(4000)) AS [AssignmentsBaselineTimephasedData],
    CAST(N'view=tbx.vw_TaskBaselines;source_uid=TaskId;target_uid=TaskId' AS nvarchar(4000)) AS [Baselines],
    CAST(N'view=tbx.vw_TaskBaselineTimephasedDataSet;source_uid=TaskId;target_uid=TaskId' AS nvarchar(4000)) AS [BaselinesTimephasedDataSet],
    CAST(N'view=tbx.vw_IssueTaskAssociations;source_uid=TaskId;target_uid=TaskId' AS nvarchar(4000)) AS [Issues],
    CAST(N'view=tbx.vw_Projects;source_uid=ProjectId;target_uid=ProjectId' AS nvarchar(4000)) AS [Project],
    CAST(N'view=tbx.vw_RiskTaskAssociations;source_uid=TaskId;target_uid=TaskId' AS nvarchar(4000)) AS [Risks],
    CAST(N'view=tbx.vw_TaskTimephasedDataSet;source_uid=TaskId;target_uid=TaskId' AS nvarchar(4000)) AS [TimephasedInfo],
    [s].[x_ProjectId] AS [ProjectId],
    CAST(NULL AS nvarchar(4000)) AS [CF_CentreCout],
    CAST(NULL AS nvarchar(4000)) AS [CF_Fin],
    CAST(NULL AS nvarchar(4000)) AS [CF_Priorite_T],
    CAST(NULL AS nvarchar(4000)) AS [CF_UAC]
FROM tbx.[vw_Tasks_src] AS [s];
GO

CREATE   VIEW tbx.[vw_TaskTimephasedDataSet_alias]
AS
SELECT
    [s].[x_TaskId] AS [TaskId],
    [s].[x_TimeByDay] AS [TimeByDay],
    [s].[x_FiscalPeriodId] AS [FiscalPeriodId],
    [s].[x_ProjectName] AS [ProjectName],
    [s].[x_TaskActualCost] AS [TaskActualCost],
    [s].[x_TaskActualWork] AS [TaskActualWork],
    [s].[x_TaskBudgetCost] AS [TaskBudgetCost],
    [s].[x_TaskBudgetWork] AS [TaskBudgetWork],
    [s].[x_TaskCost] AS [TaskCost],
    [s].[x_TaskIsActive] AS [TaskIsActive],
    [s].[x_TaskIsProjectSummary] AS [TaskIsProjectSummary],
    [s].[x_TaskModifiedDate] AS [TaskModifiedDate],
    [s].[x_TaskName] AS [TaskName],
    [s].[x_TaskOvertimeWork] AS [TaskOvertimeWork],
    [s].[x_TaskResourcePlanWork] AS [TaskResourcePlanWork],
    [s].[x_TaskWork] AS [TaskWork],
    CAST(N'view=tbx.vw_Projects;source_uid=ProjectId;target_uid=ProjectId' AS nvarchar(4000)) AS [Project],
    CAST(N'view=tbx.vw_Tasks;source_uid=TaskId;target_uid=TaskId' AS nvarchar(4000)) AS [Task],
    CAST(N'view=tbx.vw_TimeSet;source_uid=TimeByDay;target_uid=TimeByDay' AS nvarchar(4000)) AS [Time],
    [s].[x_ProjectId] AS [ProjectId]
FROM tbx.[vw_TaskTimephasedDataSet_src] AS [s];
GO

CREATE   VIEW tbx.[vw_TimeSet_alias]
AS
SELECT
    [s].[x_TimeDayOfTheMonth] AS [TimeDayOfTheMonth],
    [s].[x_TimeDayOfTheWeek] AS [TimeDayOfTheWeek],
    [s].[x_TimeMonthOfTheYear] AS [TimeMonthOfTheYear],
    [s].[x_TimeQuarter] AS [TimeQuarter],
    [s].[x_TimeWeekOfTheYear] AS [TimeWeekOfTheYear],
    [s].[x_FiscalPeriodId] AS [FiscalPeriodId],
    [s].[x_FiscalPeriodName] AS [FiscalPeriodName],
    [s].[x_FiscalPeriodStart] AS [FiscalPeriodStart],
    [s].[x_FiscalQuarter] AS [FiscalQuarter],
    [s].[x_FiscalPeriodYear] AS [FiscalPeriodYear],
    [s].[x_FiscalPeriodModifiedDate] AS [FiscalPeriodModifiedDate],
    [s].[x_TimeByDay] AS [TimeByDay]
FROM tbx.[vw_TimeSet_src] AS [s];
GO

CREATE   VIEW tbx.[vw_TimesheetClasses_alias]
AS
SELECT
    [s].[x_DepartmentId] AS [DepartmentId],
    [s].[x_DepartmentName] AS [DepartmentName],
    [s].[x_Description] AS [Description],
    [s].[x_LCID] AS [LCID],
    [s].[x_TimesheetClassName] AS [TimesheetClassName],
    [s].[x_TimesheetClassType] AS [TimesheetClassType],
    [s].[x_TimesheetClassId] AS [TimesheetClassId]
FROM tbx.[vw_TimesheetClasses_src] AS [s];
GO

CREATE   VIEW tbx.[vw_TimesheetLineActualDataSet_alias]
AS
SELECT
    [s].[x_AdjustmentIndex] AS [AdjustmentIndex],
    [s].[x_TimeByDay] AS [TimeByDay],
    [s].[x_ActualOvertimeWorkBillable] AS [ActualOvertimeWorkBillable],
    [s].[x_ActualOvertimeWorkNonBillable] AS [ActualOvertimeWorkNonBillable],
    [s].[x_ActualWorkBillable] AS [ActualWorkBillable],
    [s].[x_ActualWorkNonBillable] AS [ActualWorkNonBillable],
    [s].[x_Comment] AS [Comment],
    [s].[x_CreatedDate] AS [CreatedDate],
    [s].[x_LastChangedResourceName] AS [LastChangedResourceName],
    [s].[x_PlannedWork] AS [PlannedWork],
    [s].[x_ResourceName] AS [ResourceName],
    [s].[x_TimeByDay_DayOfMonth] AS [TimeByDay_DayOfMonth],
    [s].[x_TimeByDay_DayOfWeek] AS [TimeByDay_DayOfWeek],
    [s].[x_TimesheetLineModifiedDate] AS [TimesheetLineModifiedDate],
    CAST(N'view=tbx.vw_Resources;source_uid=LastChangedResourceNameUID;target_uid=ResourceId' AS nvarchar(4000)) AS [LastChangedByResource],
    CAST(N'view=tbx.vw_TimeSet;source_uid=TimeByDay;target_uid=TimeByDay' AS nvarchar(4000)) AS [Time],
    CAST(N'view=tbx.vw_TimesheetLines;source_uid=TimesheetLineId;target_uid=TimesheetLineId' AS nvarchar(4000)) AS [TimesheetLine],
    [s].[x_TimesheetLineId] AS [TimesheetLineId]
FROM tbx.[vw_TimesheetLineActualDataSet_src] AS [s];
GO

CREATE   VIEW tbx.[vw_TimesheetLines_alias]
AS
SELECT
    [s].[x_ActualOvertimeWorkBillable] AS [ActualOvertimeWorkBillable],
    [s].[x_ActualOvertimeWorkNonBillable] AS [ActualOvertimeWorkNonBillable],
    [s].[x_ActualWorkBillable] AS [ActualWorkBillable],
    [s].[x_ActualWorkNonBillable] AS [ActualWorkNonBillable],
    [s].[x_AssignmentId] AS [AssignmentId],
    [s].[x_CreatedDate] AS [CreatedDate],
    [s].[x_LastSavedWork] AS [LastSavedWork],
    [s].[x_LCID] AS [LCID],
    [s].[x_ModifiedDate] AS [ModifiedDate],
    [s].[x_PeriodEndDate] AS [PeriodEndDate],
    [s].[x_PeriodStartDate] AS [PeriodStartDate],
    [s].[x_PlannedWork] AS [PlannedWork],
    [s].[x_ProjectId] AS [ProjectId],
    [s].[x_ProjectName] AS [ProjectName],
    [s].[x_TaskHierarchy] AS [TaskHierarchy],
    [s].[x_TaskId] AS [TaskId],
    [s].[x_TaskName] AS [TaskName],
    [s].[x_TimesheetApproverResourceId] AS [TimesheetApproverResourceId],
    [s].[x_TimesheetApproverResourceName] AS [TimesheetApproverResourceName],
    [s].[x_TimesheetClassDescription] AS [TimesheetClassDescription],
    [s].[x_TimesheetClassId] AS [TimesheetClassId],
    [s].[x_TimesheetClassName] AS [TimesheetClassName],
    [s].[x_TimesheetClassType] AS [TimesheetClassType],
    [s].[x_TimesheetId] AS [TimesheetId],
    [s].[x_TimesheetLineComment] AS [TimesheetLineComment],
    [s].[x_TimesheetLineStatus] AS [TimesheetLineStatus],
    [s].[x_TimesheetLineStatusId] AS [TimesheetLineStatusId],
    [s].[x_TimesheetName] AS [TimesheetName],
    [s].[x_TimesheetOwner] AS [TimesheetOwner],
    [s].[x_TimesheetOwnerId] AS [TimesheetOwnerId],
    [s].[x_TimesheetPeriodId] AS [TimesheetPeriodId],
    [s].[x_TimesheetPeriodName] AS [TimesheetPeriodName],
    [s].[x_TimesheetPeriodStatus] AS [TimesheetPeriodStatus],
    [s].[x_TimesheetPeriodStatusId] AS [TimesheetPeriodStatusId],
    [s].[x_TimesheetStatus] AS [TimesheetStatus],
    [s].[x_TimesheetStatusId] AS [TimesheetStatusId],
    CAST(N'view=tbx.vw_TimesheetLineActualDataSet;source_uid=TimesheetLineId;target_uid=TimesheetLineId' AS nvarchar(4000)) AS [Actuals],
    CAST(N'view=tbx.vw_Resources;source_uid=TimesheetApproverResourceId;target_uid=ResourceId' AS nvarchar(4000)) AS [ApproverResource],
    CAST(N'view=tbx.vw_Timesheets;source_uid=TimesheetId;target_uid=TimesheetId' AS nvarchar(4000)) AS [Timesheet],
    CAST(N'view=tbx.vw_TimesheetClasses;source_uid=TimesheetClassId;target_uid=TimesheetClassId' AS nvarchar(4000)) AS [TimesheetClass],
    [s].[x_TimesheetLineId] AS [TimesheetLineId]
FROM tbx.[vw_TimesheetLines_src] AS [s];
GO

CREATE   VIEW tbx.[vw_TimesheetPeriods_alias]
AS
SELECT
    [s].[x_Description] AS [Description],
    [s].[x_EndDate] AS [EndDate],
    [s].[x_LCID] AS [LCID],
    [s].[x_PeriodName] AS [PeriodName],
    [s].[x_PeriodStatusId] AS [PeriodStatusId],
    [s].[x_StartDate] AS [StartDate],
    [s].[x_PeriodId] AS [PeriodId]
FROM tbx.[vw_TimesheetPeriods_src] AS [s];
GO

CREATE   VIEW tbx.[vw_Timesheets_alias]
AS
SELECT
    [s].[x_Comment] AS [Comment],
    CAST(NULL AS nvarchar(4000)) AS [Description],
    [s].[x_EndDate] AS [EndDate],
    [s].[x_ModifiedDate] AS [ModifiedDate],
    [s].[x_PeriodId] AS [PeriodId],
    [s].[x_PeriodName] AS [PeriodName],
    [s].[x_PeriodStatusId] AS [PeriodStatusId],
    [s].[x_StartDate] AS [StartDate],
    [s].[x_StatusDescription] AS [StatusDescription],
    [s].[x_TimesheetName] AS [TimesheetName],
    [s].[x_TimesheetOwner] AS [TimesheetOwner],
    [s].[x_TimesheetOwnerId] AS [TimesheetOwnerId],
    [s].[x_TimesheetStatusId] AS [TimesheetStatusId],
    CAST(N'view=tbx.vw_TimesheetLines;source_uid=TimesheetId;target_uid=TimesheetId' AS nvarchar(4000)) AS [Lines],
    CAST(N'view=tbx.vw_TimesheetPeriods;source_uid=PeriodId;target_uid=PeriodId' AS nvarchar(4000)) AS [Periods],
    [s].[x_TimesheetId] AS [TimesheetId]
FROM tbx.[vw_Timesheets_src] AS [s];
GO

CREATE   VIEW tbx.[vw_AssignmentBaselines]
AS
SELECT *
FROM tbx.[vw_AssignmentBaselines_alias];
GO

CREATE   VIEW tbx.[vw_AssignmentBaselineTimephasedDataSet]
AS
SELECT *
FROM tbx.[vw_AssignmentBaselineTimephasedDataSet_alias];
GO

CREATE   VIEW tbx.[vw_Assignments]
AS
SELECT *
FROM tbx.[vw_Assignments_alias];
GO

CREATE   VIEW tbx.[vw_AssignmentTimephasedDataSet]
AS
SELECT *
FROM tbx.[vw_AssignmentTimephasedDataSet_alias];
GO

CREATE   VIEW tbx.[vw_BusinessDriverDepartments]
AS
SELECT *
FROM tbx.[vw_BusinessDriverDepartments_alias];
GO

CREATE   VIEW tbx.[vw_BusinessDrivers]
AS
SELECT *
FROM tbx.[vw_BusinessDrivers_alias];
GO

CREATE   VIEW tbx.[vw_CostConstraintScenarios]
AS
SELECT *
FROM tbx.[vw_CostConstraintScenarios_alias];
GO

CREATE   VIEW tbx.[vw_CostScenarioProjects]
AS
SELECT *
FROM tbx.[vw_CostScenarioProjects_alias];
GO

CREATE   VIEW tbx.[vw_Deliverables]
AS
SELECT *
FROM tbx.[vw_Deliverables_alias];
GO

CREATE   VIEW tbx.[vw_Engagements]
AS
SELECT *
FROM tbx.[vw_Engagements_alias];
GO

CREATE   VIEW tbx.[vw_EngagementsComments]
AS
SELECT *
FROM tbx.[vw_EngagementsComments_alias];
GO

CREATE   VIEW tbx.[vw_EngagementsTimephasedDataSet]
AS
SELECT *
FROM tbx.[vw_EngagementsTimephasedDataSet_alias];
GO

CREATE   VIEW tbx.[vw_FiscalPeriods]
AS
SELECT *
FROM tbx.[vw_FiscalPeriods_alias];
GO

CREATE   VIEW tbx.[vw_Issues]
AS
SELECT *
FROM tbx.[vw_Issues_alias];
GO

CREATE   VIEW tbx.[vw_IssueTaskAssociations]
AS
SELECT *
FROM tbx.[vw_IssueTaskAssociations_alias];
GO

CREATE   VIEW tbx.[vw_PortfolioAnalyses]
AS
SELECT *
FROM tbx.[vw_PortfolioAnalyses_alias];
GO

CREATE   VIEW tbx.[vw_PortfolioAnalysisProjects]
AS
SELECT *
FROM tbx.[vw_PortfolioAnalysisProjects_alias];
GO

CREATE   VIEW tbx.[vw_PrioritizationDriverRelations]
AS
SELECT *
FROM tbx.[vw_PrioritizationDriverRelations_alias];
GO

CREATE   VIEW tbx.[vw_PrioritizationDrivers]
AS
SELECT *
FROM tbx.[vw_PrioritizationDrivers_alias];
GO

CREATE   VIEW tbx.[vw_Prioritizations]
AS
SELECT *
FROM tbx.[vw_Prioritizations_alias];
GO

CREATE   VIEW tbx.[vw_ProjectBaselines]
AS
SELECT *
FROM tbx.[vw_ProjectBaselines_alias];
GO

CREATE   VIEW tbx.[vw_Projects]
AS
SELECT *
FROM tbx.[vw_Projects_alias];
GO

CREATE   VIEW tbx.[vw_ProjectWorkflowStageDataSet]
AS
SELECT *
FROM tbx.[vw_ProjectWorkflowStageDataSet_alias];
GO

CREATE   VIEW tbx.[vw_ResourceConstraintScenarios]
AS
SELECT *
FROM tbx.[vw_ResourceConstraintScenarios_alias];
GO

CREATE   VIEW tbx.[vw_ResourceDemandTimephasedDataSet]
AS
SELECT *
FROM tbx.[vw_ResourceDemandTimephasedDataSet_alias];
GO

CREATE   VIEW tbx.[vw_Resources]
AS
SELECT *
FROM tbx.[vw_Resources_alias];
GO

CREATE   VIEW tbx.[vw_ResourceScenarioProjects]
AS
SELECT *
FROM tbx.[vw_ResourceScenarioProjects_alias];
GO

CREATE   VIEW tbx.[vw_ResourceTimephasedDataSet]
AS
SELECT *
FROM tbx.[vw_ResourceTimephasedDataSet_alias];
GO

CREATE   VIEW tbx.[vw_Risks]
AS
SELECT *
FROM tbx.[vw_Risks_alias];
GO

CREATE   VIEW tbx.[vw_RiskTaskAssociations]
AS
SELECT *
FROM tbx.[vw_RiskTaskAssociations_alias];
GO

CREATE   VIEW tbx.[vw_TaskBaselines]
AS
SELECT *
FROM tbx.[vw_TaskBaselines_alias];
GO

CREATE   VIEW tbx.[vw_TaskBaselineTimephasedDataSet]
AS
SELECT *
FROM tbx.[vw_TaskBaselineTimephasedDataSet_alias];
GO

CREATE   VIEW tbx.[vw_Tasks]
AS
SELECT *
FROM tbx.[vw_Tasks_alias];
GO

CREATE   VIEW tbx.[vw_TaskTimephasedDataSet]
AS
SELECT *
FROM tbx.[vw_TaskTimephasedDataSet_alias];
GO

CREATE   VIEW tbx.[vw_TimeSet]
AS
SELECT *
FROM tbx.[vw_TimeSet_alias];
GO

CREATE   VIEW tbx.[vw_TimesheetClasses]
AS
SELECT *
FROM tbx.[vw_TimesheetClasses_alias];
GO

CREATE   VIEW tbx.[vw_TimesheetLineActualDataSet]
AS
SELECT *
FROM tbx.[vw_TimesheetLineActualDataSet_alias];
GO

CREATE   VIEW tbx.[vw_TimesheetLines]
AS
SELECT *
FROM tbx.[vw_TimesheetLines_alias];
GO

CREATE   VIEW tbx.[vw_TimesheetPeriods]
AS
SELECT *
FROM tbx.[vw_TimesheetPeriods_alias];
GO

CREATE   VIEW tbx.[vw_Timesheets]
AS
SELECT *
FROM tbx.[vw_Timesheets_alias];
GO

CREATE   VIEW tbx_fr.[vw_AssignmentBaselines]
AS
SELECT
    [AssignmentId] AS [IdAffectation],
    [BaselineNumber] AS [NuméroPlanningDeRéférence],
    [AssignmentBaselineBudgetCost] AS [CoûtBudgétaireRéférenceAffectation],
    [AssignmentBaselineBudgetMaterialWork] AS [TravailMatériauBudgétaireRéférenceAffectation],
    [AssignmentBaselineBudgetWork] AS [TravailBudgétaireRéférenceAffectation],
    [AssignmentBaselineCost] AS [CoûtRéférenceAffectation],
    [AssignmentBaselineFinishDate] AS [DateFinRéférenceAffectation],
    [AssignmentBaselineMaterialWork] AS [TravailMatériauRéférenceAffectation],
    [AssignmentBaselineModifiedDate] AS [AssignmentBaselineModifiedDate],
    [AssignmentBaselineStartDate] AS [DateDébutRéférenceAffectation],
    [AssignmentBaselineWork] AS [TravailRéférenceAffectation],
    [AssignmentType] AS [AffectationType],
    [ProjectName] AS [NomProjet],
    [TaskId] AS [IdTâche],
    [TaskName] AS [NomTâche],
    [Assignment] AS [Affectation],
    [AssignmentBaselineTimephasedDataSet] AS [JeuDonnéesChronologiquesRéférenceAffectation],
    [Project] AS [Projet],
    [Task] AS [Tâche],
    [ProjectId] AS [IdProjet]
FROM tbx.[vw_AssignmentBaselines];
GO

CREATE   VIEW tbx_fr.[vw_AssignmentBaselineTimephasedDataSet]
AS
SELECT
    [AssignmentId] AS [IdAffectation],
    [TimeByDay] AS [HeureParJour],
    [BaselineNumber] AS [NuméroPlanningDeRéférence],
    [AssignmentBaselineBudgetCost] AS [CoûtBudgétaireRéférenceAffectation],
    [AssignmentBaselineBudgetMaterialWork] AS [TravailMatériauBudgétaireRéférenceAffectation],
    [AssignmentBaselineBudgetWork] AS [TravailBudgétaireRéférenceAffectation],
    [AssignmentBaselineCost] AS [CoûtRéférenceAffectation],
    [AssignmentBaselineMaterialWork] AS [TravailMatériauRéférenceAffectation],
    [AssignmentBaselineModifiedDate] AS [AssignmentBaselineModifiedDate],
    [AssignmentBaselineWork] AS [TravailRéférenceAffectation],
    [FiscalPeriodId] AS [IDPériodeFiscale],
    [ProjectName] AS [NomProjet],
    [ResourceId] AS [IdRessource],
    [TaskId] AS [IdTâche],
    [TaskName] AS [NomTâche],
    [Assignment] AS [Affectation],
    [Baseline] AS [DébutRéférenceFinRéférence],
    [Project] AS [Projet],
    [Tasks] AS [Tâches],
    [Time] AS [Heure],
    [ProjectId] AS [IdProjet]
FROM tbx.[vw_AssignmentBaselineTimephasedDataSet];
GO

CREATE   VIEW tbx_fr.[vw_Assignments]
AS
SELECT
    [AssignmentId] AS [IdAffectation],
    [AssignmentActualCost] AS [CoûtRéelAffectation],
    [AssignmentActualFinishDate] AS [AffectationDateFinRéelle],
    [AssignmentActualOvertimeCost] AS [CoûtHeuresSupplémentairesRéellesAffectation],
    [AssignmentActualOvertimeWork] AS [HeuresSupplémentairesRéellesAffectation],
    [AssignmentActualRegularCost] AS [CoûtNormalRéelAffectation],
    [AssignmentActualRegularWork] AS [TravailNormalRéelAffectation],
    [AssignmentActualStartDate] AS [AffectationDateDébutRéelle],
    [AssignmentActualWork] AS [AffectationTravailRéel],
    [AssignmentACWP] AS [CRTEAffectation],
    [AssignmentAllUpdatesApplied] AS [AssignmentAllUpdatesApplied],
    [AssignmentBCWP] AS [VAAffectation],
    [AssignmentBCWS] AS [VPAffectation],
    [AssignmentBookingDescription] AS [DescriptionRéservationAffectation],
    [AssignmentBookingId] AS [IdRéservationAffectation],
    [AssignmentBookingName] AS [NomRéservationAffectation],
    [AssignmentBudgetCost] AS [CoûtBudgétaireAffectation],
    [AssignmentBudgetMaterialWork] AS [TravailMatériauBudgétaireAffectation],
    [AssignmentBudgetWork] AS [TravailBudgétaireAffectation],
    [AssignmentCost] AS [AffectationCoût],
    [AssignmentCostVariance] AS [VarianceCoûtAffectation],
    [AssignmentCreatedDate] AS [DateCréationAffectation],
    [AssignmentCreatedRevisionCounter] AS [CompteurRévisionsCrééAffectation],
    [AssignmentCV] AS [VCAffectation],
    [AssignmentDelay] AS [RetardAffectation],
    [AssignmentFinishDate] AS [AffectationDateFin],
    [AssignmentFinishVariance] AS [VarianceFinAffectation],
    [AssignmentIsOverallocated] AS [AffectationEstSurutilisée],
    [AssignmentIsPublished] AS [AffectationEstPubliée],
    [AssignmentMaterialActualWork] AS [TravailRéelMatériauAffectation],
    [AssignmentMaterialWork] AS [TravailMatériauAffectation],
    [AssignmentModifiedDate] AS [AffectationDateModification],
    [AssignmentModifiedRevisionCounter] AS [CompteurRévisionsModifiéAffectation],
    [AssignmentOvertimeCost] AS [CoûtHeuresSupplémentairesAffectation],
    [AssignmentOvertimeWork] AS [HeuresSupplémentairesAffectation],
    [AssignmentPeakUnits] AS [UnitésPicAffectation],
    [AssignmentPercentWorkCompleted] AS [AffectationPourcentageTravailEffectué],
    [AssignmentRegularCost] AS [CoûtNormalAffectation],
    [AssignmentRegularWork] AS [TravailNormalAffectation],
    [AssignmentRemainingCost] AS [AffectationCoûtRestant],
    [AssignmentRemainingOvertimeCost] AS [CoûtHeuresSupplémentairesRestantes],
    [AssignmentRemainingOvertimeWork] AS [HeuresSupplémentairesRestantesAffectation],
    [AssignmentRemainingRegularCost] AS [CoûtNormalRestantAffectation],
    [AssignmentRemainingRegularWork] AS [TravailNormalRestantAffectation],
    [AssignmentRemainingWork] AS [AffectationTravailRestant],
    [AssignmentResourcePlanWork] AS [AffectationRessourcePlanTravail],
    [AssignmentResourceType] AS [AffectationTypeRessource],
    [AssignmentStartDate] AS [AffectationDateDébut],
    [AssignmentStartVariance] AS [VarianceDébutAffectation],
    [AssignmentSV] AS [EDAffectation],
    [AssignmentType] AS [AffectationType],
    [AssignmentUpdatesAppliedDate] AS [AssignmentUpdatesAppliedDate],
    [AssignmentVAC] AS [VAAAffectation],
    [AssignmentWork] AS [AffectationTravail],
    [AssignmentWorkVariance] AS [VarianceTravailAffectation],
    [IsPublic] AS [EstPublic],
    [ProjectName] AS [NomProjet],
    [ResourceId] AS [IdRessource],
    [ResourceName] AS [NomRessource],
    [TaskId] AS [IdTâche],
    [TaskIsActive] AS [TâcheEstActive],
    [TaskName] AS [NomTâche],
    [TimesheetClassId] AS [IdClasseFeuilleDeTemps],
    [TypeDescription] AS [DescriptionType],
    [TypeName] AS [NomType],
    [RBS_R] AS [RBS_R],
    [CostType_R] AS [CostType_R],
    [FlagStatus_T] AS [FlagStatus_T],
    [TeamName_R] AS [TeamName_R],
    [ResourceDepartments_R] AS [ResourceDepartments_R],
    [Health_T] AS [Health_T],
    [Profilderessource_R] AS [Profilderessource_R],
    [Contexte_T] AS [Contexte_T],
    [CongédeFdT_R] AS [CongédeFdT_R],
    [Courrielsupérieurhiérarchique_R] AS [Courrielsupérieurhiérarchique_R],
    [Notedepilotage_R] AS [Notedepilotage_R],
    [OBS_R] AS [OBS_R],
    [RappelFdTavisersupérieur_R] AS [RappelFdTavisersupérieur_R],
    [Verrouilléeentreprise_T] AS [Verrouilléeentreprise_T],
    [Typedecoût_R] AS [Typedecoût_R],
    [IgnorerRàF_T] AS [IgnorerRàF_T],
    [Capitalisable_T] AS [Capitalisable_T],
    [CompteComptableExterne_T] AS [CompteComptableExterne_T],
    [CodeDeProjet_T] AS [CodeDeProjet_T],
    [zzUnitéAdministrative_T] AS [zzUnitéAdministrative_T],
    [UnitéAdministrative_T] AS [UnitéAdministrative_T],
    [NoContrat_T] AS [NoContrat_T],
    [NoDemande_T] AS [NoDemande_T],
    [NoItem_T] AS [NoItem_T],
    [DescItem_T] AS [DescItem_T],
    [NoEpic_T] AS [NoEpic_T],
    [NoRéférence_T] AS [NoRéférence_T],
    [Baseline] AS [DébutRéférenceFinRéférence],
    [Project] AS [Projet],
    [Resource] AS [Ressource],
    [Task] AS [Tâche],
    [TimephasedData] AS [DonnéesChronologiques],
    [ProjectId] AS [IdProjet]
FROM tbx.[vw_Assignments];
GO

CREATE   VIEW tbx_fr.[vw_AssignmentTimephasedDataSet]
AS
SELECT
    [AssignmentId] AS [IdAffectation],
    [TimeByDay] AS [HeureParJour],
    [AssignmentActualCost] AS [CoûtRéelAffectation],
    [AssignmentActualOvertimeCost] AS [CoûtHeuresSupplémentairesRéellesAffectation],
    [AssignmentActualOvertimeWork] AS [HeuresSupplémentairesRéellesAffectation],
    [AssignmentActualRegularCost] AS [CoûtNormalRéelAffectation],
    [AssignmentActualRegularWork] AS [TravailNormalRéelAffectation],
    [AssignmentActualWork] AS [AffectationTravailRéel],
    [AssignmentBudgetCost] AS [CoûtBudgétaireAffectation],
    [AssignmentBudgetMaterialWork] AS [TravailMatériauBudgétaireAffectation],
    [AssignmentBudgetWork] AS [TravailBudgétaireAffectation],
    [AssignmentCombinedWork] AS [TravailCombinéAffectation],
    [AssignmentCost] AS [AffectationCoût],
    [AssignmentMaterialActualWork] AS [TravailRéelMatériauAffectation],
    [AssignmentMaterialWork] AS [TravailMatériauAffectation],
    [AssignmentModifiedDate] AS [AffectationDateModification],
    [AssignmentOvertimeCost] AS [CoûtHeuresSupplémentairesAffectation],
    [AssignmentOvertimeWork] AS [HeuresSupplémentairesAffectation],
    [AssignmentRegularCost] AS [CoûtNormalAffectation],
    [AssignmentRegularWork] AS [TravailNormalAffectation],
    [AssignmentRemainingCost] AS [AffectationCoûtRestant],
    [AssignmentRemainingOvertimeCost] AS [CoûtHeuresSupplémentairesRestantes],
    [AssignmentRemainingOvertimeWork] AS [HeuresSupplémentairesRestantesAffectation],
    [AssignmentRemainingRegularCost] AS [CoûtNormalRestantAffectation],
    [AssignmentRemainingRegularWork] AS [TravailNormalRestantAffectation],
    [AssignmentRemainingWork] AS [AffectationTravailRestant],
    [AssignmentResourcePlanWork] AS [AffectationRessourcePlanTravail],
    [AssignmentWork] AS [AffectationTravail],
    [FiscalPeriodId] AS [IDPériodeFiscale],
    [ProjectName] AS [NomProjet],
    [ResourceId] AS [IdRessource],
    [TaskId] AS [IdTâche],
    [TaskIsActive] AS [TâcheEstActive],
    [TaskName] AS [NomTâche],
    [Assignment] AS [Affectation],
    [Project] AS [Projet],
    [Task] AS [Tâche],
    [Time] AS [Heure],
    [ProjectId] AS [IdProjet]
FROM tbx.[vw_AssignmentTimephasedDataSet];
GO

CREATE   VIEW tbx_fr.[vw_BusinessDriverDepartments]
AS
SELECT
    [DepartmentId] AS [IdService],
    [BusinessDriverName] AS [NomAxeStratégiqueEntreprise],
    [DepartmentName] AS [NomService],
    [BusinessDriver] AS [AxeStratégique],
    [BusinessDriverId] AS [IdAxeStratégiqueEntreprise]
FROM tbx.[vw_BusinessDriverDepartments];
GO

CREATE   VIEW tbx_fr.[vw_BusinessDrivers]
AS
SELECT
    [BusinessDriverCreatedDate] AS [DateCréationAxeStratégiqueEntreprise],
    [BusinessDriverDescription] AS [DescriptionAxeStratégiqueEntreprise],
    [BusinessDriverIsActive] AS [AxeStratégiqueEntrepriseEstActif],
    [BusinessDriverModifiedDate] AS [DateModificationAxeStratégiqueEntreprise],
    [BusinessDriverName] AS [NomAxeStratégiqueEntreprise],
    [CreatedByResourceId] AS [IdRessourceCréation],
    [CreatedByResourceName] AS [NomRessourceCréation],
    [ImpactDescriptionExtreme] AS [DescriptionImpactExtrême],
    [ImpactDescriptionLow] AS [DescriptionImpactFaible],
    [ImpactDescriptionModerate] AS [DescriptionImpactModéré],
    [ImpactDescriptionNone] AS [DescriptionImpactAucun],
    [ImpactDescriptionStrong] AS [DescriptionImpactFort],
    [ModifiedByResourceId] AS [IdRessourceModification],
    [ModifiedByResourceName] AS [NomRessourceModification],
    [CreatedByResource] AS [RessourceCréation],
    [Departments] AS [Services],
    [ModifiedByResource] AS [ModifiéParRessource],
    [BusinessDriverId] AS [IdAxeStratégiqueEntreprise]
FROM tbx.[vw_BusinessDrivers];
GO

CREATE   VIEW tbx_fr.[vw_CostConstraintScenarios]
AS
SELECT
    [AnalysisId] AS [IdAnalyse],
    [AnalysisName] AS [NomAnalyse],
    [CreatedByResourceId] AS [IdRessourceCréation],
    [CreatedByResourceName] AS [NomRessourceCréation],
    [CreatedDate] AS [DateCréation],
    [ModifiedByResourceId] AS [IdRessourceModification],
    [ModifiedByResourceName] AS [NomRessourceModification],
    [ModifiedDate] AS [DateModification],
    [ScenarioDescription] AS [DescriptionScénario],
    [ScenarioName] AS [NomScénario],
    [SelectedProjectsCost] AS [CoûtProjetsSélectionnés],
    [SelectedProjectsPriority] AS [PrioritéProjetSélectionnée],
    [UnselectedProjectsCost] AS [CoûtProjetsNonSélectionné],
    [UnselectedProjectsPriority] AS [PrioritéProjetNonSélectionnée],
    [UseDependencies] AS [UtiliserDépendances],
    [CreatedByResource] AS [RessourceCréation],
    [ModifiedByResource] AS [ModifiéParRessource],
    [Analysis] AS [Analyse],
    [ResourceConstraintScenarios] AS [ScénariosContrainteRessource],
    [CostScenarioProjects] AS [ProjetsScénarioCoût],
    [ScenarioId] AS [IdScénario]
FROM tbx.[vw_CostConstraintScenarios];
GO

CREATE   VIEW tbx_fr.[vw_CostScenarioProjects]
AS
SELECT
    [ProjectId] AS [IdProjet],
    [AbsolutePriority] AS [PrioritéAbsolue],
    [AnalysisId] AS [IdAnalyse],
    [AnalysisName] AS [NomAnalyse],
    [ForceAliasLookupTableId] AS [IdTableChoixAliasForcé],
    [ForceAliasLookupTableName] AS [NomTableChoixAliasForcé],
    [ForceStatus] AS [ÉtatForcé],
    [HardConstraintValue] AS [ValeurContrainteImpérative],
    [Priority] AS [Priorité],
    [ProjectName] AS [NomProjet],
    [ScenarioName] AS [NomScénario],
    [Status] AS [Statut],
    [Project] AS [Projet],
    [Analysis] AS [Analyse],
    [CostConstraintScenario] AS [ScénarioContrainteCoût],
    [ScenarioId] AS [IdScénario]
FROM tbx.[vw_CostScenarioProjects];
GO

CREATE   VIEW tbx_fr.[vw_Deliverables]
AS
SELECT
    [DeliverableId] AS [IdLivrable],
    [CreateByResource] AS [CréerParRessource],
    [CreatedDate] AS [DateCréation],
    [Description] AS [Description],
    [FinishDate] AS [FinishDate],
    [IsFolder] AS [EstUnDossier],
    [ItemRelativeUrlPath] AS [CheminURLRelativeÉlément],
    [ModifiedByResource] AS [ModifiéParRessource],
    [ModifiedDate] AS [DateModification],
    [ProjectName] AS [NomProjet],
    [StartDate] AS [DateDébut],
    [Title] AS [Titre],
    [DependentProjects] AS [ProjetsDépendants],
    [DependentTasks] AS [DependantTasks],
    [ParentProjects] AS [ProjetsParents],
    [ParentTasks] AS [TâchesParentes],
    [Project] AS [Projet],
    [ProjectId] AS [IdProjet]
FROM tbx.[vw_Deliverables];
GO

CREATE   VIEW tbx_fr.[vw_Engagements]
AS
SELECT
    [CommittedFinishDate] AS [DateFinValidée],
    [CommittedMaxUnits] AS [NbMaxUnitésValidées],
    [CommittedStartDate] AS [DateDébutValidée],
    [CommittedWork] AS [TravailValidé],
    [EngagementCreatedDate] AS [DateCréationEngagement],
    [EngagementModifiedDate] AS [DateModificationEngagement],
    [EngagementName] AS [NomEngagement],
    [EngagementReviewedDate] AS [DateRévisionEngagement],
    [EngagementStatus] AS [ÉtatEngagement],
    [EngagementSubmittedDate] AS [DateSoumissionEngagement],
    [ModifiedByResourceId] AS [IdRessourceModification],
    [ModifiedByResourceName] AS [NomRessourceModification],
    [ProjectId] AS [IdProjet],
    [ProjectName] AS [NomProjet],
    [ProposedFinishDate] AS [DateFinProposée],
    [ProposedMaxUnits] AS [NbMaxUnitésProposées],
    [ProposedStartDate] AS [DateDébutProposée],
    [ProposedWork] AS [TravailProposé],
    [ResourceId] AS [IdRessource],
    [ResourceName] AS [NomRessource],
    [ReviewedByResourceId] AS [RévisionParIDRessource],
    [ReviewedByResourceName] AS [RévisionParNomRessource],
    [SubmittedByResourceId] AS [SoumisParIDRessource],
    [SubmittedByResourceName] AS [SoumisParNomRessource],
    [TimephasedInfo] AS [InfosChronologiques],
    [Comment] AS [Commentaire],
    [EngagementId] AS [IDEngagement]
FROM tbx.[vw_Engagements];
GO

CREATE   VIEW tbx_fr.[vw_EngagementsComments]
AS
SELECT
    [EngagementId] AS [IDEngagement],
    [EngagementName] AS [NomEngagement],
    [CommentMessage] AS [MessageCommentaire],
    [CommentCreatedDate] AS [DateCréationCommentaire],
    [AuthorId] AS [IDAuteur],
    [AuthorName] AS [NomAuteur],
    [Engagement] AS [Engagement],
    [CommentId] AS [IDCommentaire]
FROM tbx.[vw_EngagementsComments];
GO

CREATE   VIEW tbx_fr.[vw_EngagementsTimephasedDataSet]
AS
SELECT
    [TimeByDay] AS [HeureParJour],
    [CommittedMaxUnits] AS [NbMaxUnitésValidées],
    [CommittedWork] AS [TravailValidé],
    [EngagementModifiedDate] AS [DateModificationEngagement],
    [EngagementName] AS [NomEngagement],
    [ProjectId] AS [IdProjet],
    [ProjectName] AS [NomProjet],
    [ProposedMaxUnits] AS [NbMaxUnitésProposées],
    [ProposedWork] AS [TravailProposé],
    [ResourceId] AS [IdRessource],
    [ResourceName] AS [NomRessource],
    [Engagement] AS [Engagement],
    [EngagementId] AS [IDEngagement]
FROM tbx.[vw_EngagementsTimephasedDataSet];
GO

CREATE   VIEW tbx_fr.[vw_FiscalPeriods]
AS
SELECT
    [FiscalPeriodName] AS [NomPériodeFiscale],
    [FiscalPeriodStart] AS [DébutPériodeFiscale],
    [FiscalPeriodFinish] AS [FinPériodeFiscale],
    [FiscalPeriodQuarter] AS [PériodeFiscaleTrimestre],
    [FiscalPeriodYear] AS [AnnéePériodeFiscale],
    [CreatedDate] AS [DateCréation],
    [FiscalPeriodModifiedDate] AS [DateModificationPériodeFiscale],
    [FiscalPeriodId] AS [IDPériodeFiscale]
FROM tbx.[vw_FiscalPeriods];
GO

CREATE   VIEW tbx_fr.[vw_Issues]
AS
SELECT
    [IssueId] AS [IdProblème],
    [AssignedToResource] AS [AssignéÀRessource],
    [Category] AS [Catégorie],
    [CreateByResource] AS [CréerParRessource],
    [CreatedDate] AS [DateCréation],
    [Discussion] AS [Discussion],
    [DueDate] AS [Échéance],
    [IsFolder] AS [EstUnDossier],
    [ItemRelativeUrlPath] AS [CheminURLRelativeÉlément],
    [ModifiedByResource] AS [ModifiéParRessource],
    [ModifiedDate] AS [DateModification],
    [NumberOfAttachments] AS [NombreDePiècesjointes],
    [Owner] AS [Propriétaire],
    [Priority] AS [Priorité],
    [ProjectName] AS [NomProjet],
    [Resolution] AS [Résolution],
    [Status] AS [Statut],
    [Title] AS [Titre],
    [Project] AS [Projet],
    [RelatedRisks] AS [RisquesAssociés],
    [Tasks] AS [Tâches],
    [SubIssues] AS [SousProblèmes],
    [ProjectId] AS [IdProjet]
FROM tbx.[vw_Issues];
GO

CREATE   VIEW tbx_fr.[vw_IssueTaskAssociations]
AS
SELECT
    [IssueId] AS [IdProblème],
    [TaskId] AS [IdTâche],
    [RelationshipType] AS [TypeRelation],
    [ProjectName] AS [NomProjet],
    [RelatedProjectId] AS [IDProjetApparenté],
    [RelatedProjectName] AS [NomProjetApparenté],
    [TaskName] AS [NomTâche],
    [Title] AS [Titre],
    [Issue] AS [Problème],
    [Task] AS [Tâche],
    [Project] AS [Projet],
    [RelatedProject] AS [ProjetApparenté],
    [ProjectId] AS [IdProjet]
FROM tbx.[vw_IssueTaskAssociations];
GO

CREATE   VIEW tbx_fr.[vw_PortfolioAnalyses]
AS
SELECT
    [AlternateProjectEndDateCustomFieldId] AS [IdChampPersonnaliséAutreDateFinProjet],
    [AlternateProjectEndDateCustomFieldName] AS [NomChampPersonnaliséAutreDateFinProjet],
    [AlternateProjectStartDateCustomFieldId] AS [IdChampPersonnaliséAutreDateDébutProjet],
    [AlternateProjectStartDateCustomFieldName] AS [NomChampPersonnaliséAutreDateDébutProjet],
    [AnalysisDescription] AS [DescriptionAnalyse],
    [AnalysisName] AS [NomAnalyse],
    [AnalysisType] AS [TypeAnalyse],
    [BookingType] AS [TypeRéservation],
    [CreatedByResourceId] AS [IdRessourceCréation],
    [CreatedByResourceName] AS [NomRessourceCréation],
    [CreatedDate] AS [DateCréation],
    [DepartmentId] AS [IdService],
    [DepartmentName] AS [NomService],
    [FilterResourcesByDepartment] AS [FiltrerRessourcesParService],
    [FilterResourcesByRBS] AS [FiltrerRessourcesParRBS],
    [FilterResourcesByRBSValueId] AS [IdValeurFiltrerRessourcesParRBS],
    [FilterResourcesByRBSValueText] AS [TexteValeurFiltrerRessourcesParRBS],
    [ForcedInAliasLookupTableId] AS [IdTableChoixAliasInclusDeForce],
    [ForcedInAliasLookupTableName] AS [NomTableChoixAliasInclusForce],
    [ForcedOutAliasLookupTableId] AS [IdTableChoixAliasExcluDeForce],
    [ForcedOutAliasLookupTableName] AS [NomTableChoixAliasExcluDeForce],
    [HardConstraintCustomFieldId] AS [IdChampPersonnaliséContrainteImpérative],
    [HardConstraintCustomFieldName] AS [NomChampPersonnaliséContrainteImpérative],
    [ModifiedByResourceId] AS [IdRessourceModification],
    [ModifiedByResourceName] AS [NomRessourceModification],
    [ModifiedDate] AS [DateModification],
    [PlanningHorizonEndDate] AS [DateFinHorizonPlanification],
    [PlanningHorizonStartDate] AS [DateDébutHorizonPlanification],
    [PrioritizationId] AS [IdDéfinitionPriorités],
    [PrioritizationName] AS [NomDéfinitionPriorités],
    [PrioritizationType] AS [TypeDéfinitionPriorités],
    [RoleCustomFieldId] AS [IdChampPersonnaliséRôle],
    [RoleCustomFieldName] AS [NomChampPersonnaliséRôle],
    [TimeScale] AS [ÉchelleTemps],
    [UseAlternateProjectDatesForResourcePlans] AS [UtiliserDatesProjetAlternativesPourPlansRessources],
    [CreatedByResource] AS [RessourceCréation],
    [ModifiedByResource] AS [ModifiéParRessource],
    [Prioritization] AS [DéfinitionDePriorités],
    [AnalysisProjects] AS [ProjetsAnalyse],
    [CostConstraintScenarios] AS [ScénariosContrainteCoût],
    [ResourceConstraintScenarios] AS [ScénariosContrainteRessource],
    [AnalysisId] AS [IdAnalyse]
FROM tbx.[vw_PortfolioAnalyses];
GO

CREATE   VIEW tbx_fr.[vw_PortfolioAnalysisProjects]
AS
SELECT
    [ProjectId] AS [IdProjet],
    [AbsolutePriority] AS [PrioritéAbsolue],
    [AnalysisName] AS [NomAnalyse],
    [Duration] AS [Durée],
    [FinishNoLaterThan] AS [FinAuPlusTardLe],
    [Locked] AS [Verrouillé],
    [OriginalEndDate] AS [DateFinOrigine],
    [OriginalStartDate] AS [DateDébutOrigine],
    [Priority] AS [Priorité],
    [ProjectName] AS [NomProjet],
    [StartDate] AS [DateDébut],
    [StartNoEarlierThan] AS [DébutAuPlusTôtLe],
    [Analysis] AS [Analyse],
    [Project] AS [Projet],
    [AnalysisId] AS [IdAnalyse]
FROM tbx.[vw_PortfolioAnalysisProjects];
GO

CREATE   VIEW tbx_fr.[vw_PrioritizationDriverRelations]
AS
SELECT
    [BusinessDriver1Id] AS [IdAxeStratégiqueEntreprise1],
    [BusinessDriver2Id] AS [IdAxeStratégiqueEntreprise2],
    [BusinessDriver1Name] AS [NomAxeStratégiqueEntreprise1],
    [BusinessDriver2Name] AS [NomAxeStratégiqueEntreprise2],
    [PrioritizationName] AS [NomDéfinitionPriorités],
    [RelationValue] AS [ValeurRelation],
    [Prioritization] AS [DéfinitionDePriorités],
    [BusinessDriver1] AS [AxeStratégique1],
    [BusinessDriver2] AS [AxeStratégique2],
    [PrioritizationId] AS [IdDéfinitionPriorités]
FROM tbx.[vw_PrioritizationDriverRelations];
GO

CREATE   VIEW tbx_fr.[vw_PrioritizationDrivers]
AS
SELECT
    [BusinessDriverId] AS [IdAxeStratégiqueEntreprise],
    [BusinessDriverName] AS [NomAxeStratégiqueEntreprise],
    [BusinessDriverPriority] AS [PrioritéAxeStratégiqueEntreprise],
    [PrioritizationName] AS [NomDéfinitionPriorités],
    [Prioritization] AS [DéfinitionDePriorités],
    [BusinessDriver] AS [AxeStratégique],
    [PrioritizationId] AS [IdDéfinitionPriorités]
FROM tbx.[vw_PrioritizationDrivers];
GO

CREATE   VIEW tbx_fr.[vw_Prioritizations]
AS
SELECT
    [ConsistencyRatio] AS [TauxCohérence],
    [CreatedByResourceId] AS [IdRessourceCréation],
    [CreatedByResourceName] AS [NomRessourceCréation],
    [DepartmentId] AS [IdService],
    [DepartmentName] AS [NomService],
    [ModifiedByResourceId] AS [IdRessourceModification],
    [ModifiedByResourceName] AS [NomRessourceModification],
    [PrioritizationCreatedDate] AS [DateCréationDéfinitionPriorités],
    [PrioritizationDescription] AS [DescriptionDéfinitionPriorités],
    [PrioritizationIsManual] AS [DéfinitionPrioritésEstManuelle],
    [PrioritizationModifiedDate] AS [DateModificationDéfinitionPriorités],
    [PrioritizationName] AS [NomDéfinitionPriorités],
    [CreatedByResource] AS [RessourceCréation],
    [ModifiedByResource] AS [ModifiéParRessource],
    [PrioritizationDrivers] AS [AxesStratégiquesDéfinitionPriorités],
    [PrioritizationDriverRelations] AS [RelationsAxeStratégiqueDéfinitionPriorités],
    [PrioritizationId] AS [IdDéfinitionPriorités]
FROM tbx.[vw_Prioritizations];
GO

CREATE   VIEW tbx_fr.[vw_ProjectBaselines]
AS
SELECT
    [BaselineNumber] AS [NuméroPlanningDeRéférence],
    [ProjectBaselineBudgetCost] AS [CoûtBudgétaireRéférenceProjet],
    [ProjectBaselineBudgetWork] AS [TravailBudgétaireRéférenceProjet],
    [ProjectBaselineCost] AS [CoûtRéférenceProjet],
    [ProjectBaselineDeliverableFinishDate] AS [DateFinLivrableRéférenceProjet],
    [ProjectBaselineDeliverableStartDate] AS [DateDébutLivrableRéférenceProjet],
    [ProjectBaselineDuration] AS [DuréeRéférenceProjet],
    [ProjectBaselineDurationString] AS [ChaîneDuréeRéférenceProjet],
    [ProjectBaselineFinishDate] AS [DateFinRéférenceProjet],
    [ProjectBaselineFinishDateString] AS [ChaîneDateFinRéférenceProjet],
    [ProjectBaselineFixedCost] AS [CoûtFixeRéférenceProjet],
    [ProjectBaselineModifiedDate] AS [ProjectBaselineModifiedDate],
    [ProjectBaselineStartDate] AS [DateDébutRéférenceProjet],
    [ProjectBaselineStartDateString] AS [ChaîneDateDébutRéférenceProjet],
    [ProjectBaselineWork] AS [TravailRéférenceProjet],
    [ProjectName] AS [NomProjet],
    [TaskId] AS [IdTâche],
    [Project] AS [Projet],
    [ProjectId] AS [IdProjet]
FROM tbx.[vw_ProjectBaselines];
GO

CREATE   VIEW tbx_fr.[vw_Projects]
AS
SELECT
    [EnterpriseProjectTypeDescription] AS [DescriptionTypeProjetEntreprise],
    [EnterpriseProjectTypeId] AS [IdTypeProjetEntreprise],
    [EnterpriseProjectTypeIsDefault] AS [TypeProjetEntrepriseParDéfaut],
    [EnterpriseProjectTypeName] AS [NomTypeProjetEntreprise],
    [OptimizerCommitDate] AS [DateValidationOptimiseur],
    [OptimizerDecisionAliasLookupTableId] AS [IdTableChoixAliasDécisionOptimiseur],
    [OptimizerDecisionAliasLookupTableValueId] AS [IdValeurTableChoixAliasDécisionOptimiseur],
    [OptimizerDecisionID] AS [IdDécisionOptimiseur],
    [OptimizerDecisionName] AS [NomDécisionOptimiseur],
    [OptimizerSolutionName] AS [NomSolutionOptimiseur],
    [ParentProjectId] AS [IdProjetParent],
    [PlannerCommitDate] AS [DateValidationPlanificateur],
    [PlannerDecisionAliasLookupTableId] AS [IdTableChoixAliasDécisionPlanificateur],
    [PlannerDecisionAliasLookupTableValueId] AS [IdValeurTableChoixAliasDécisionPlanificateur],
    [PlannerDecisionID] AS [IdDécisionPlanificateur],
    [PlannerDecisionName] AS [NomDécisionPlanificateur],
    [PlannerEndDate] AS [DateFinPlanificateur],
    [PlannerSolutionName] AS [NomSolutionPlanificateur],
    [PlannerStartDate] AS [DateDébutPlanificateur],
    [ProjectActualCost] AS [CoûtRéelProjet],
    [ProjectActualDuration] AS [DuréeRéelleProjet],
    [ProjectActualFinishDate] AS [DateFinRéelleProjet],
    [ProjectActualOvertimeCost] AS [CoûtsHeuresSupplémentairesRéellesProjet],
    [ProjectActualOvertimeWork] AS [TravailHeuresSupplémentairesRéellesProjet],
    [ProjectActualRegularCost] AS [CoûtNormaRéelProjet],
    [ProjectActualRegularWork] AS [TravailNormalRéelProjet],
    [ProjectActualStartDate] AS [DateDébutRéelProjet],
    [ProjectActualWork] AS [TravailRéelProjet],
    [ProjectACWP] AS [CRTEProjet],
    [ProjectAuthorName] AS [NomAuteurProjet],
    [ProjectBCWP] AS [VAProjet],
    [ProjectBCWS] AS [VPProjet],
    [ProjectBudgetCost] AS [CoûtBudgétaireProjet],
    [ProjectBudgetWork] AS [TravailBudgétaireProjet],
    [ProjectCalculationsAreStale] AS [CalculsProjetPérimés],
    [ProjectCalendarDuration] AS [DuréeCalendrierProjet],
    [ProjectCategoryName] AS [NomCatégorieProjet],
    [ProjectCompanyName] AS [NomSociétéProjet],
    [ProjectCost] AS [CoûtProjet],
    [ProjectCostVariance] AS [VariationCoûtProjet],
    [ProjectCPI] AS [IPCProjet],
    [ProjectCreatedDate] AS [DateCréationProjet],
    [ProjectCurrency] AS [DeviseProjet],
    [ProjectCV] AS [VCProjet],
    [ProjectCVP] AS [PVCProjet],
    [ProjectDescription] AS [DescriptionProjet],
    [ProjectDuration] AS [DuréeProjet],
    [ProjectDurationVariance] AS [VariationDuréeProjet],
    [ProjectEAC] AS [EAAProjet],
    [ProjectEarlyFinish] AS [FinAuPlusTôtProjet],
    [ProjectEarlyStart] AS [DébutAuPlusTôtProjet],
    [ProjectEarnedValueIsStale] AS [AuditCoûtProjetEstPérimé],
    [ProjectEnterpriseFeatures] AS [ProjectEnterpriseFeatures],
    [ProjectFinishDate] AS [DateFinProjet],
    [ProjectFinishVariance] AS [VariationFinProjet],
    [ProjectFixedCost] AS [CoûtFixeProjet],
    [ProjectIdentifier] AS [IdentificateurProjet],
    [ProjectKeywords] AS [MotsClésProjet],
    [ProjectLateFinish] AS [FinAuPlusTardProjet],
    [ProjectLateStart] AS [DébutAuPlusTardProjet],
    [ProjectLastPublishedDate] AS [ProjectLastPublishedDate],
    [ProjectManagerName] AS [NomResponsableProjet],
    [ProjectModifiedDate] AS [DateModificationProjet],
    [ProjectName] AS [NomProjet],
    [ProjectOvertimeCost] AS [CoûtHeuresSupplémentairesProjet],
    [ProjectOvertimeWork] AS [TravailHeuresSupplémentairesProjet],
    [ProjectOwnerId] AS [IdPropriétaireProjet],
    [ProjectOwnerName] AS [NomPropriétaireProjet],
    [ProjectPercentCompleted] AS [PourcentageTerminéProjet],
    [ProjectPercentWorkCompleted] AS [PourcentageTravailTerminéProjet],
    [ProjectRegularCost] AS [CoûtNormalProjet],
    [ProjectRegularWork] AS [TravailNormalProjet],
    [ProjectRemainingCost] AS [CoûtRestantProjet],
    [ProjectRemainingDuration] AS [DuréeRestanteProjet],
    [ProjectRemainingOvertimeCost] AS [CoûtHeuresSupplémentairesRestantesProjet],
    [ProjectRemainingOvertimeWork] AS [TravailHeuresSupplémentairesRestantesProjet],
    [ProjectRemainingRegularCost] AS [CoûtNormalRestantProjet],
    [ProjectRemainingRegularWork] AS [TravailNormalRestantProjet],
    [ProjectRemainingWork] AS [TravailRestantProjet],
    [ProjectResourcePlanWork] AS [TravailPlanRessourcesProjet],
    [ProjectSPI] AS [SPIProjet],
    [ProjectStartDate] AS [DateDébutProjet],
    [ProjectStartVariance] AS [VariationDébutProjet],
    [ProjectStatusDate] AS [DateÉtatProjet],
    [ProjectSubject] AS [ObjetProjet],
    [ProjectSV] AS [VSProjet],
    [ProjectSVP] AS [SVPProjet],
    [ProjectTCPI] AS [TCPIProjet],
    [ProjectTimephased] AS [ProjetChronologique],
    [ProjectTitle] AS [TitreProjet],
    [ProjectType] AS [TypeProjet],
    [ProjectVAC] AS [VAAProjet],
    [ProjectWork] AS [TravailProjet],
    [ProjectWorkspaceInternalUrl] AS [UrlInterneEspaceDeTravailProjet],
    [ProjectWorkVariance] AS [VariationTravailProjet],
    [ResourcePlanUtilizationDate] AS [DatePlanUtilisationRessource],
    [ResourcePlanUtilizationType] AS [TypePlanUtilisationRessource],
    [WorkflowCreatedDate] AS [DateCréationFluxDeTravail],
    [WorkflowError] AS [ErreurFluxDeTravail],
    [WorkflowErrorResponseCode] AS [CodeRéponseErreurFluxDeTravail],
    [WorkflowInstanceId] AS [IdInstanceFluxDeTravail],
    [WorkflowOwnerId] AS [IdPropriétaireFluxDeTravail],
    [WorkflowOwnerName] AS [NomPropriétaireFluxDeTravail],
    [ProjectDepartments] AS [ProjectDepartments],
    [Statutduprojet] AS [Statutduprojet],
    [Typedebudget] AS [Typedebudget],
    [PBS] AS [PBS],
    [Annéedubudget] AS [Annéedubudget],
    [Montantdubudget] AS [Montantdubudget],
    [AssignmentBaselines] AS [PlanningsRéférenceAffectation],
    [Assignments] AS [Affectations],
    [Deliverables] AS [Livrables],
    [Dependencies] AS [Interdépendances],
    [Issues] AS [Problèmes],
    [Risks] AS [Risques],
    [StagesInfo] AS [InformationsÉtapes],
    [Tasks] AS [Tâches],
    [ProjectId] AS [IdProjet]
FROM tbx.[vw_Projects];
GO

CREATE   VIEW tbx_fr.[vw_ProjectWorkflowStageDataSet]
AS
SELECT
    [StageId] AS [IdÉtape],
    [LastModifiedDate] AS [DateDernièreModification],
    [LCID] AS [LCID],
    [PhaseDescription] AS [DescriptionPhase],
    [PhaseName] AS [NomPhase],
    [ProjectName] AS [NomProjet],
    [StageCompletionDate] AS [DateFinÉtape],
    [StageDescription] AS [DescriptionÉtape],
    [StageEntryDate] AS [DateEntréeÉtape],
    [StageInformation] AS [InformationsÉtape],
    [StageLastSubmittedDate] AS [DateDernierEnvoiÉtape],
    [StageName] AS [NomÉtape],
    [StageOrder] AS [OrdreÉtape],
    [StageStateDescription] AS [DescriptionÉtatÉtape],
    [StageStatus] AS [ÉtatÉtape],
    [Project] AS [Projet],
    [ProjectId] AS [IdProjet]
FROM tbx.[vw_ProjectWorkflowStageDataSet];
GO

CREATE   VIEW tbx_fr.[vw_ResourceConstraintScenarios]
AS
SELECT
    [AllocationThreshold] AS [SeuilRépartition],
    [AnalysisId] AS [IdAnalyse],
    [AnalysisName] AS [NomAnalyse],
    [ConstraintType] AS [TypeContrainte],
    [ConstraintValue] AS [ValeurContrainte],
    [CostConstraintScenarioId] AS [IdScénarioContrainteCoût],
    [CostConstraintScenarioName] AS [NomScénarioContrainteCoût],
    [CreatedByResourceId] AS [IdRessourceCréation],
    [CreatedByResourceName] AS [NomRessourceCréation],
    [CreatedDate] AS [DateCréation],
    [EnforceProjectDependencies] AS [AppliquerDépendancesProjet],
    [EnforceSchedulingConstraints] AS [AppliquerContraintesPlanification],
    [HiringType] AS [TypeEmbauche],
    [ModifiedByResourceId] AS [IdRessourceModification],
    [ModifiedByResourceName] AS [NomRessourceModification],
    [ModifiedDate] AS [DateModification],
    [RateTable] AS [TableTaux],
    [ScenarioDescription] AS [DescriptionScénario],
    [ScenarioName] AS [NomScénario],
    [CreatedByResource] AS [RessourceCréation],
    [ModifiedByResource] AS [ModifiéParRessource],
    [Analysis] AS [Analyse],
    [CostConstraintScenario] AS [ScénarioContrainteCoût],
    [ResourceScenarioProjects] AS [ProjetsScénarioRessource],
    [ScenarioId] AS [IdScénario]
FROM tbx.[vw_ResourceConstraintScenarios];
GO

CREATE   VIEW tbx_fr.[vw_ResourceDemandTimephasedDataSet]
AS
SELECT
    [ResourceId] AS [IdRessource],
    [TimeByDay] AS [HeureParJour],
    [FiscalPeriodId] AS [IDPériodeFiscale],
    [ProjectName] AS [NomProjet],
    [ResourceDemand] AS [ResourceDemand],
    [ResourceDemandModifiedDate] AS [ResourceDemandModifiedDate],
    [ResourceName] AS [NomRessource],
    [ResourcePlanUtilizationDate] AS [DatePlanUtilisationRessource],
    [ResourcePlanUtilizationType] AS [TypePlanUtilisationRessource],
    [Resource] AS [Ressource],
    [Project] AS [Projet],
    [Time] AS [Heure],
    [ProjectId] AS [IdProjet]
FROM tbx.[vw_ResourceDemandTimephasedDataSet];
GO

CREATE   VIEW tbx_fr.[vw_Resources]
AS
SELECT
    [ResourceBaseCalendar] AS [CalendrierBaseRessource],
    [ResourceBookingType] AS [TypeRéservationRessource],
    [ResourceCanLevel] AS [RessourceÀniveler],
    [ResourceCode] AS [CodeRessource],
    [ResourceCostCenter] AS [CentreCoûtRessource],
    [ResourceCostPerUse] AS [CoûtRessourceParUtilisation],
    [ResourceCreatedDate] AS [DateCréationRessource],
    [ResourceEarliestAvailableFrom] AS [RessourceDisponibleAuPlusTôtDu],
    [ResourceEmailAddress] AS [AdresseMessagerieRessource],
    [ResourceGroup] AS [GroupeRessources],
    [ResourceHyperlink] AS [LienHypertexteRessource],
    [ResourceHyperlinkHref] AS [RéfÉlevéeLienHypertexteRessource],
    [ResourceInitials] AS [InitialesRessource],
    [ResourceIsActive] AS [RessourceEstActive],
    [ResourceIsGeneric] AS [RessourceEstGénérique],
    [ResourceIsTeam] AS [RessourceÉquipe],
    [ResourceLatestAvailableTo] AS [RessourceDisponibleAuPlusTardAu],
    [ResourceMaterialLabel] AS [ÉtiquetteMatériauRessource],
    [ResourceMaxUnits] AS [UnitésMaxRessource],
    [ResourceModifiedDate] AS [DateModificationRessource],
    [ResourceName] AS [NomRessource],
    [ResourceNTAccount] AS [CompteNTRessource],
    [ResourceOvertimeRate] AS [TauxHeuresSupplémentairesRessource],
    [ResourceStandardRate] AS [TauxStandardRessource],
    [ResourceStatusId] AS [IdÉtatRessource],
    [ResourceStatusName] AS [NomÉtatRessource],
    [ResourceTimesheetManageId] AS [IdGestionFeuilleDeTempsRessource],
    [ResourceType] AS [TypeRessource],
    [ResourceWorkgroup] AS [GroupeTravailRessource],
    [TypeDescription] AS [DescriptionType],
    [TypeName] AS [NomType],
    [RBS] AS [RBS],
    [ResourceDepartments] AS [ResourceDepartments],
    [TeamName] AS [TeamName],
    [CostType] AS [CostType],
    [Profilderessource] AS [Profilderessource],
    [CongédeFdT] AS [CongédeFdT],
    [Courrielsupérieurhiérarchique] AS [Courrielsupérieurhiérarchique],
    [Notedepilotage] AS [Notedepilotage],
    [OBS] AS [OBS],
    [RappelFdTavisersupérieur] AS [RappelFdTavisersupérieur],
    [Typedecoût] AS [Typedecoût],
    [Assignments] AS [Affectations],
    [TimephasedInfoDataSet] AS [JeuDonnéesInformationsChronologiques],
    [ResourceDemandTimephasedInfo] AS [ResourceDemandTimephasedInfo],
    [ResourceId] AS [IdRessource]
FROM tbx.[vw_Resources];
GO

CREATE   VIEW tbx_fr.[vw_ResourceScenarioProjects]
AS
SELECT
    [ProjectId] AS [IdProjet],
    [AbsolutePriority] AS [PrioritéAbsolue],
    [AnalysisId] AS [IdAnalyse],
    [AnalysisName] AS [NomAnalyse],
    [CostConstraintScenarioId] AS [IdScénarioContrainteCoût],
    [CostConstraintScenarioName] AS [NomScénarioContrainteCoût],
    [ForceAliasLookupTableId] AS [IdTableChoixAliasForcé],
    [ForceAliasLookupTableName] AS [NomTableChoixAliasForcé],
    [ForceStatus] AS [ÉtatForcé],
    [HardConstraintValue] AS [ValeurContrainteImpérative],
    [NewStartDate] AS [NouvelleDateDébut],
    [Priority] AS [Priorité],
    [ProjectName] AS [NomProjet],
    [ResourceCost] AS [CoûtRessource],
    [ResourceWork] AS [TravailRessource],
    [ScenarioName] AS [NomScénario],
    [Status] AS [Statut],
    [Project] AS [Projet],
    [Analysis] AS [Analyse],
    [CostConstraintScenario] AS [ScénarioContrainteCoût],
    [ResourceConstraintScenario] AS [ScénarioContrainteRessource],
    [ScenarioId] AS [IdScénario]
FROM tbx.[vw_ResourceScenarioProjects];
GO

CREATE   VIEW tbx_fr.[vw_ResourceTimephasedDataSet]
AS
SELECT
    [TimeByDay] AS [HeureParJour],
    [BaseCapacity] AS [CapacitéBase],
    [Capacity] AS [Capacité],
    [FiscalPeriodId] AS [IDPériodeFiscale],
    [ResourceModifiedDate] AS [DateModificationRessource],
    [ResourceName] AS [NomRessource],
    [Resource] AS [Ressource],
    [Time] AS [Heure],
    [ResourceId] AS [IdRessource]
FROM tbx.[vw_ResourceTimephasedDataSet];
GO

CREATE   VIEW tbx_fr.[vw_Risks]
AS
SELECT
    [RiskId] AS [IdRisque],
    [AssignedToResource] AS [AssignéÀRessource],
    [Category] AS [Catégorie],
    [ContingencyPlan] AS [PlanUrgence],
    [Cost] AS [Coût],
    [CostExposure] AS [ExpositionCoût],
    [CreateByResource] AS [CréerParRessource],
    [CreatedDate] AS [DateCréation],
    [Description] AS [Description],
    [DueDate] AS [Échéance],
    [Exposure] AS [Exposition],
    [Impact] AS [ÀPercussion],
    [IsFolder] AS [EstUnDossier],
    [ItemRelativeUrlPath] AS [CheminURLRelativeÉlément],
    [MitigationPlan] AS [PlanAtténuation],
    [ModifiedByResource] AS [ModifiéParRessource],
    [ModifiedDate] AS [DateModification],
    [NumberOfAttachments] AS [NombreDePiècesjointes],
    [Owner] AS [Propriétaire],
    [Probability] AS [Probabilité],
    [ProjectName] AS [NomProjet],
    [Status] AS [Statut],
    [Title] AS [Titre],
    [TriggerDescription] AS [DescriptionDéclencheur],
    [TriggerTask] AS [TâcheDéclencheur],
    [Project] AS [Projet],
    [RelatedIssues] AS [ProblèmesConnexes],
    [SubRisks] AS [SousRisques],
    [Tasks] AS [Tâches],
    [ProjectId] AS [IdProjet]
FROM tbx.[vw_Risks];
GO

CREATE   VIEW tbx_fr.[vw_RiskTaskAssociations]
AS
SELECT
    [RiskId] AS [IdRisque],
    [TaskId] AS [IdTâche],
    [RelationshipType] AS [TypeRelation],
    [ProjectName] AS [NomProjet],
    [RelatedProjectId] AS [IDProjetApparenté],
    [RelatedProjectName] AS [NomProjetApparenté],
    [TaskName] AS [NomTâche],
    [Title] AS [Titre],
    [Risk] AS [Risque],
    [Task] AS [Tâche],
    [Project] AS [Projet],
    [RelatedProject] AS [ProjetApparenté],
    [ProjectId] AS [IdProjet]
FROM tbx.[vw_RiskTaskAssociations];
GO

CREATE   VIEW tbx_fr.[vw_TaskBaselines]
AS
SELECT
    [TaskId] AS [IdTâche],
    [BaselineNumber] AS [NuméroPlanningDeRéférence],
    [ProjectName] AS [NomProjet],
    [TaskBaselineBudgetCost] AS [CoûtBudgétaireRéférenceTâche],
    [TaskBaselineBudgetWork] AS [TravailBudgétaireRéférenceTâche],
    [TaskBaselineCost] AS [CoûtRéférenceTâche],
    [TaskBaselineDeliverableFinishDate] AS [DateFinLivrableRéférenceTâche],
    [TaskBaselineDeliverableStartDate] AS [DateDébutLivrableRéférenceTâche],
    [TaskBaselineDuration] AS [DuréeRéférenceTâche],
    [TaskBaselineDurationString] AS [ChaîneDuréeRéférenceTâche],
    [TaskBaselineFinishDate] AS [DateFinRéférenceTâche],
    [TaskBaselineFinishDateString] AS [ChaîneDateFinRéférenceTâche],
    [TaskBaselineFixedCost] AS [CoûtFixeRéférenceTâche],
    [TaskBaselineModifiedDate] AS [TaskBaselineModifiedDate],
    [TaskBaselineStartDate] AS [DateDébutRéférenceTâche],
    [TaskBaselineStartDateString] AS [ChaîneDateDébutRéférenceTâche],
    [TaskBaselineWork] AS [TravailRéférenceTâche],
    [TaskName] AS [NomTâche],
    [Project] AS [Projet],
    [Task] AS [Tâche],
    [TaskBaselineTimephasedDataSet] AS [JeuDonnéesChronologiqueRéférenceTâche],
    [ProjectId] AS [IdProjet]
FROM tbx.[vw_TaskBaselines];
GO

CREATE   VIEW tbx_fr.[vw_TaskBaselineTimephasedDataSet]
AS
SELECT
    [TaskId] AS [IdTâche],
    [TimeByDay] AS [HeureParJour],
    [BaselineNumber] AS [NuméroPlanningDeRéférence],
    [FiscalPeriodId] AS [IDPériodeFiscale],
    [ProjectName] AS [NomProjet],
    [TaskBaselineBudgetCost] AS [CoûtBudgétaireRéférenceTâche],
    [TaskBaselineBudgetWork] AS [TravailBudgétaireRéférenceTâche],
    [TaskBaselineCost] AS [CoûtRéférenceTâche],
    [TaskBaselineFixedCost] AS [CoûtFixeRéférenceTâche],
    [TaskBaselineModifiedDate] AS [TaskBaselineModifiedDate],
    [TaskBaselineWork] AS [TravailRéférenceTâche],
    [TaskName] AS [NomTâche],
    [Project] AS [Projet],
    [Task] AS [Tâche],
    [TaskBaselines] AS [PlanningsDeRéférenceTâche],
    [Time] AS [Heure],
    [ProjectId] AS [IdProjet]
FROM tbx.[vw_TaskBaselineTimephasedDataSet];
GO

CREATE   VIEW tbx_fr.[vw_Tasks]
AS
SELECT
    [TaskId] AS [IdTâche],
    [ParentTaskId] AS [IdTâcheParente],
    [ParentTaskName] AS [NomTâcheParente],
    [ProjectName] AS [NomProjet],
    [TaskActualCost] AS [CoûtRéelTâche],
    [TaskActualDuration] AS [DuréeRéelleTâche],
    [TaskActualFinishDate] AS [DateFinRéelleTâche],
    [TaskActualFixedCost] AS [CoûtFixeRéelTâche],
    [TaskActualOvertimeCost] AS [CoûtHeuresSupplémentairesRéelTâche],
    [TaskActualOvertimeWork] AS [TravailHeuresSupplémentairesRéellesTâche],
    [TaskActualRegularCost] AS [CoûtNormalRéelTâche],
    [TaskActualRegularWork] AS [TravailNormalRéelTâche],
    [TaskActualStartDate] AS [DateDébutRéelleTâche],
    [TaskActualWork] AS [TravailRéelTâche],
    [TaskACWP] AS [CRTETâche],
    [TaskBCWP] AS [VATâche],
    [TaskBCWS] AS [VPTâche],
    [TaskBudgetCost] AS [CoûtBudgétaireTâche],
    [TaskBudgetWork] AS [TravailBudgétaireTâche],
    [TaskClientUniqueId] AS [IDUniqueClientTâche],
    [TaskCost] AS [CoûtTâche],
    [TaskCostVariance] AS [VariationCoûtTâche],
    [TaskCPI] AS [IPCTâche],
    [TaskCreatedDate] AS [DateCréationTâche],
    [TaskCreatedRevisionCounter] AS [NombreRévisionsCrééesTâche],
    [TaskCV] AS [VCTâche],
    [TaskCVP] AS [PVCTâche],
    [TaskDeadline] AS [ÉchéanceTâche],
    [TaskDeliverableFinishDate] AS [DateFinLivrableTâche],
    [TaskDeliverableStartDate] AS [DateDébutLivrableTâche],
    [TaskDuration] AS [DuréeTâche],
    [TaskDurationIsEstimated] AS [DuréeEstiméeTâche],
    [TaskDurationString] AS [ChaîneDuréeTâche],
    [TaskDurationVariance] AS [VariationDuréeTâche],
    [TaskEAC] AS [EAATâche],
    [TaskEarlyFinish] AS [FinAuPlusTôtTâche],
    [TaskEarlyStart] AS [DébutAuPlusTôtTâche],
    [TaskFinishDate] AS [DateFinTâche],
    [TaskFinishDateString] AS [ChaîneDateFinTâche],
    [TaskFinishVariance] AS [VariationFinTâche],
    [TaskFixedCost] AS [CoûtFixeTâche],
    [TaskFixedCostAssignmentId] AS [IdAffectationCoûtFixeTâche],
    [TaskFreeSlack] AS [MargeLibreTâche],
    [TaskHyperLinkAddress] AS [AdresseLienHypertexteTâche],
    [TaskHyperLinkFriendlyName] AS [LienHypertexteNomConvivialTâche],
    [TaskHyperLinkSubAddress] AS [SousAdresseLienHypertexteTâche],
    [TaskIgnoresResourceCalendar] AS [TâcheIgnoreCalendrierRessources],
    [TaskIndex] AS [IndexTâche],
    [TaskIsActive] AS [TâcheEstActive],
    [TaskIsCritical] AS [TâcheEstCritique],
    [TaskIsEffortDriven] AS [TâchePilotéeParEffort],
    [TaskIsExternal] AS [TâcheExterne],
    [TaskIsManuallyScheduled] AS [TâchePlanifiéeManuellement],
    [TaskIsMarked] AS [TâcheEstMarquée],
    [TaskIsMilestone] AS [TâcheEstUnJalon],
    [TaskIsOverallocated] AS [TâcheEstEnSurutilisation],
    [TaskIsProjectSummary] AS [TâcheRécapitulativeProjet],
    [TaskIsRecurring] AS [TâcheRécurrente],
    [TaskIsSummary] AS [TâcheRécapitulative],
    [TaskLateFinish] AS [FinAuPlusTardTâche],
    [TaskLateStart] AS [DébutAuPlusTardTâche],
    [TaskLevelingDelay] AS [RetardNivellementTâche],
    [TaskModifiedDate] AS [DateModificationTâche],
    [TaskModifiedRevisionCounter] AS [NombreRévisionsModifiéesTâche],
    [TaskName] AS [NomTâche],
    [TaskOutlineLevel] AS [NiveauHiérarchiqueTâche],
    [TaskOutlineNumber] AS [NuméroHiérarchiqueTâche],
    [TaskOvertimeCost] AS [CoûtHeuresSupplémentairesTâche],
    [TaskOvertimeWork] AS [TravailHeuresSupplémentairesTâche],
    [TaskPercentCompleted] AS [PourcentageAchevéTâche],
    [TaskPercentWorkCompleted] AS [PourcentageTravailAchevéTâche],
    [TaskPhysicalPercentCompleted] AS [PourcentagePhysiqueAchevéTâche],
    [TaskPriority] AS [PrioritéTâche],
    [TaskRegularCost] AS [CoûtNormalTâche],
    [TaskRegularWork] AS [TravailNormalTâche],
    [TaskRemainingCost] AS [CoûtRestantTâche],
    [TaskRemainingDuration] AS [DuréeRestanteTâche],
    [TaskRemainingOvertimeCost] AS [CoûtHeuresSupplémentairesRestantesTâche],
    [TaskRemainingOvertimeWork] AS [TravailHeuresSupplémentairesRestantesTâche],
    [TaskRemainingRegularCost] AS [CoûtNormalRestantTâche],
    [TaskRemainingRegularWork] AS [TravailNormalRestantTâche],
    [TaskRemainingWork] AS [TravailRestantTâche],
    [TaskResourcePlanWork] AS [TravailPlanRessourcesTâche],
    [TaskSPI] AS [SPITâche],
    [TaskStartDate] AS [DateDébutTâche],
    [TaskStartDateString] AS [ChaîneDateDébutTâche],
    [TaskStartVariance] AS [VariationDébutTâche],
    [TaskStatusManagerUID] AS [UIDGestionnaireÉtatTâche],
    [TaskSV] AS [VSTâche],
    [TaskSVP] AS [PVPTâche],
    [TaskTCPI] AS [TCPITâche],
    [TaskTotalSlack] AS [MargeTotaleTâche],
    [TaskVAC] AS [VAATâche],
    [TaskWBS] AS [WBSTâche],
    [TaskWork] AS [TravailTâche],
    [TaskWorkVariance] AS [VariationTravailTâche],
    [FlagStatus] AS [FlagStatus],
    [Health] AS [Health],
    [Contexte] AS [Contexte],
    [Verrouilléeentreprise] AS [Verrouilléeentreprise],
    [IgnorerRàF] AS [IgnorerRàF],
    [Capitalisable] AS [Capitalisable],
    [CompteComptableExterne] AS [CompteComptableExterne],
    [CodeDeProjet] AS [CodeDeProjet],
    [zzUnitéAdministrative] AS [zzUnitéAdministrative],
    [UnitéAdministrative] AS [UnitéAdministrative],
    [NoContrat] AS [NoContrat],
    [NoDemande] AS [NoDemande],
    [NoItem] AS [NoItem],
    [DescItem] AS [DescItem],
    [NoEpic] AS [NoEpic],
    [NoRéférence] AS [NoRéférence],
    [Assignments] AS [Affectations],
    [AssignmentsBaselines] AS [PlanningsDeRéférenceAffectations],
    [AssignmentsBaselineTimephasedData] AS [DonnéesChronologiquesRéférenceAffectations],
    [Baselines] AS [PlanningsDeRéférence],
    [BaselinesTimephasedDataSet] AS [JeuDonnéesChronologiquesPlanningsDeRéférence],
    [Issues] AS [Problèmes],
    [Project] AS [Projet],
    [Risks] AS [Risques],
    [TimephasedInfo] AS [InfosChronologiques],
    [ProjectId] AS [IdProjet]
FROM tbx.[vw_Tasks];
GO

CREATE   VIEW tbx_fr.[vw_TaskTimephasedDataSet]
AS
SELECT
    [TaskId] AS [IdTâche],
    [TimeByDay] AS [HeureParJour],
    [FiscalPeriodId] AS [IDPériodeFiscale],
    [ProjectName] AS [NomProjet],
    [TaskActualCost] AS [CoûtRéelTâche],
    [TaskActualWork] AS [TravailRéelTâche],
    [TaskBudgetCost] AS [CoûtBudgétaireTâche],
    [TaskBudgetWork] AS [TravailBudgétaireTâche],
    [TaskCost] AS [CoûtTâche],
    [TaskIsActive] AS [TâcheEstActive],
    [TaskIsProjectSummary] AS [TâcheRécapitulativeProjet],
    [TaskModifiedDate] AS [DateModificationTâche],
    [TaskName] AS [NomTâche],
    [TaskOvertimeWork] AS [TravailHeuresSupplémentairesTâche],
    [TaskResourcePlanWork] AS [TravailPlanRessourcesTâche],
    [TaskWork] AS [TravailTâche],
    [Project] AS [Projet],
    [Task] AS [Tâche],
    [Time] AS [Heure],
    [ProjectId] AS [IdProjet]
FROM tbx.[vw_TaskTimephasedDataSet];
GO

CREATE   VIEW tbx_fr.[vw_TimeSet]
AS
SELECT
    [TimeDayOfTheMonth] AS [HeureJourDuMois],
    [TimeDayOfTheWeek] AS [HeureJourDeLaSemaine],
    [TimeMonthOfTheYear] AS [HeureMoisDeLAnnée],
    [TimeQuarter] AS [TempsTrimestre],
    [TimeWeekOfTheYear] AS [HeureSemaineDeLAnnée],
    [FiscalPeriodId] AS [IDPériodeFiscale],
    [FiscalPeriodName] AS [NomPériodeFiscale],
    [FiscalPeriodStart] AS [DébutPériodeFiscale],
    [FiscalQuarter] AS [TrimestreFiscal],
    [FiscalPeriodYear] AS [AnnéePériodeFiscale],
    [FiscalPeriodModifiedDate] AS [DateModificationPériodeFiscale],
    [TimeByDay] AS [HeureParJour]
FROM tbx.[vw_TimeSet];
GO

CREATE   VIEW tbx_fr.[vw_TimesheetClasses]
AS
SELECT
    [DepartmentId] AS [IdService],
    [DepartmentName] AS [NomService],
    [Description] AS [Description],
    [LCID] AS [LCID],
    [TimesheetClassName] AS [NomClasseFeuilleDeTemps],
    [TimesheetClassType] AS [TypeClasseFeuilleDeTemps],
    [TimesheetClassId] AS [IdClasseFeuilleDeTemps]
FROM tbx.[vw_TimesheetClasses];
GO

CREATE   VIEW tbx_fr.[vw_TimesheetLineActualDataSet]
AS
SELECT
    [AdjustmentIndex] AS [IndexAjustement],
    [TimeByDay] AS [HeureParJour],
    [ActualOvertimeWorkBillable] AS [TravailHeuresSupplémentairesRéelFacturable],
    [ActualOvertimeWorkNonBillable] AS [TravailHeuresSupplémentairesRéelNonFacturable],
    [ActualWorkBillable] AS [TravailRéelFacturable],
    [ActualWorkNonBillable] AS [TravailRéelNonFacturable],
    [Comment] AS [Commentaire],
    [CreatedDate] AS [DateCréation],
    [LastChangedResourceName] AS [NomRessourceDernièreModification],
    [PlannedWork] AS [TravailPrévu],
    [ResourceName] AS [NomRessource],
    [TimeByDay_DayOfMonth] AS [HeureParJour_JourDuMois],
    [TimeByDay_DayOfWeek] AS [HeureParJour_JourDeLaSemaine],
    [TimesheetLineModifiedDate] AS [TimesheetLineModifiedDate],
    [LastChangedByResource] AS [DernièreModificationParRessource],
    [Time] AS [Heure],
    [TimesheetLine] AS [LigneFeuilleDeTemps],
    [TimesheetLineId] AS [IdLigneFeuilleDeTemps]
FROM tbx.[vw_TimesheetLineActualDataSet];
GO

CREATE   VIEW tbx_fr.[vw_TimesheetLines]
AS
SELECT
    [ActualOvertimeWorkBillable] AS [TravailHeuresSupplémentairesRéelFacturable],
    [ActualOvertimeWorkNonBillable] AS [TravailHeuresSupplémentairesRéelNonFacturable],
    [ActualWorkBillable] AS [TravailRéelFacturable],
    [ActualWorkNonBillable] AS [TravailRéelNonFacturable],
    [AssignmentId] AS [IdAffectation],
    [CreatedDate] AS [DateCréation],
    [LastSavedWork] AS [DernierTravailEnregistré],
    [LCID] AS [LCID],
    [ModifiedDate] AS [DateModification],
    [PeriodEndDate] AS [DateFinPériode],
    [PeriodStartDate] AS [DateDébutPériode],
    [PlannedWork] AS [TravailPrévu],
    [ProjectId] AS [IdProjet],
    [ProjectName] AS [NomProjet],
    [TaskHierarchy] AS [HiérarchieTâches],
    [TaskId] AS [IdTâche],
    [TaskName] AS [NomTâche],
    [TimesheetApproverResourceId] AS [IdRessourceApprobateurFeuilleDeTemps],
    [TimesheetApproverResourceName] AS [NomRessourceApprobateurFeuilleDeTemps],
    [TimesheetClassDescription] AS [DescriptionClasseFeuilleDeTemps],
    [TimesheetClassId] AS [IdClasseFeuilleDeTemps],
    [TimesheetClassName] AS [NomClasseFeuilleDeTemps],
    [TimesheetClassType] AS [TypeClasseFeuilleDeTemps],
    [TimesheetId] AS [IdFeuilleDeTemps],
    [TimesheetLineComment] AS [CommentaireLigneFeuilleDeTemps],
    [TimesheetLineStatus] AS [ÉtatLigneFeuilleDeTemps],
    [TimesheetLineStatusId] AS [IdÉtatLigneFeuilleDeTemps],
    [TimesheetName] AS [NomFeuilleTemps],
    [TimesheetOwner] AS [PropriétaireFeuilleDeTemps],
    [TimesheetOwnerId] AS [IdPropriétaireFeuilleDeTemps],
    [TimesheetPeriodId] AS [IdPériodeFeuilleDeTemps],
    [TimesheetPeriodName] AS [NomPériodeFeuilleDeTemps],
    [TimesheetPeriodStatus] AS [ÉtatPériodeFeuilleDeTemps],
    [TimesheetPeriodStatusId] AS [IdÉtatPériodeFeuilleDeTemps],
    [TimesheetStatus] AS [ÉtatFeuilleDeTemps],
    [TimesheetStatusId] AS [IdÉtatFeuilleDeTemps],
    [Actuals] AS [ChiffresRéels],
    [ApproverResource] AS [RessourceApprobateur],
    [Timesheet] AS [FeuilleDeTemps],
    [TimesheetClass] AS [ClasseFeuilleDeTemps],
    [TimesheetLineId] AS [IdLigneFeuilleDeTemps]
FROM tbx.[vw_TimesheetLines];
GO

CREATE   VIEW tbx_fr.[vw_TimesheetPeriods]
AS
SELECT
    [Description] AS [Description],
    [EndDate] AS [DateFin],
    [LCID] AS [LCID],
    [PeriodName] AS [NomPériode],
    [PeriodStatusId] AS [IdÉtatPériode],
    [StartDate] AS [DateDébut],
    [PeriodId] AS [IdPériode]
FROM tbx.[vw_TimesheetPeriods];
GO

CREATE   VIEW tbx_fr.[vw_Timesheets]
AS
SELECT
    [Comment] AS [Commentaire],
    [Description] AS [Description],
    [EndDate] AS [DateFin],
    [ModifiedDate] AS [DateModification],
    [PeriodId] AS [IdPériode],
    [PeriodName] AS [NomPériode],
    [PeriodStatusId] AS [IdÉtatPériode],
    [StartDate] AS [DateDébut],
    [StatusDescription] AS [DescriptionÉtat],
    [TimesheetName] AS [NomFeuilleTemps],
    [TimesheetOwner] AS [PropriétaireFeuilleDeTemps],
    [TimesheetOwnerId] AS [IdPropriétaireFeuilleDeTemps],
    [TimesheetStatusId] AS [IdÉtatFeuilleDeTemps],
    [Lines] AS [Lignes],
    [Periods] AS [Périodes],
    [TimesheetId] AS [IdFeuilleDeTemps]
FROM tbx.[vw_Timesheets];
GO
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @RunId uniqueidentifier = (SELECT RunId FROM #V6ScriptContext);
DECLARE @ScriptName sysname = (SELECT ScriptName FROM #V6ScriptContext);
DECLARE @Sql nvarchar(max);
DECLARE @SchemaName sysname;
DECLARE @ViewName sysname;
DECLARE @SourceViewName sysname;
DECLARE @ColumnList nvarchar(max);
DECLARE @ProjectDataViewCount int = 0;
DECLARE @InternalViewCount int = 0;
DECLARE @InvalidViewCount int = 0;
DECLARE @BlockedColumnCount int = 0;
DECLARE @ProjectDataCustomColumnCount int = 0;
DECLARE @LookupViewSynonymCount int = 0;
DECLARE @RowsAffected bigint = 0;
DECLARE @EndMessage nvarchar(max);
DECLARE @ViewDefinitionMode nvarchar(100);
DECLARE @ExcludePsseContentCustomFields bit;

IF OBJECT_ID(N'tempdb..#PsseContentCustomFieldBlocklist') IS NOT NULL DROP TABLE #PsseContentCustomFieldBlocklist;
IF OBJECT_ID(N'tempdb..#ProjectDataSourceViews') IS NOT NULL DROP TABLE #ProjectDataSourceViews;
IF OBJECT_ID(N'tempdb..#ViewValidation') IS NOT NULL DROP TABLE #ViewValidation;

SELECT @ViewDefinitionMode = NULLIF(LTRIM(RTRIM(SettingValue)), N'')
FROM cfg.Settings
WHERE SettingKey = N'ViewDefinitionMode';

SELECT @ExcludePsseContentCustomFields =
    CASE
        WHEN UPPER(NULLIF(LTRIM(RTRIM(SettingValue)), N'')) IN (N'1', N'TRUE', N'YES', N'OUI') THEN 1
        ELSE 0
    END
FROM cfg.Settings
WHERE SettingKey = N'ExcludePsseContentCustomFields';

SET @ViewDefinitionMode = ISNULL(@ViewDefinitionMode, N'FROZEN_SNAPSHOT');
SET @ExcludePsseContentCustomFields = ISNULL(@ExcludePsseContentCustomFields, 1);

IF @ViewDefinitionMode <> N'FROZEN_SNAPSHOT'
    THROW 66010, N'v6_04a supporte actuellement seulement cfg.Settings.ViewDefinitionMode = FROZEN_SNAPSHOT.', 1;

CREATE TABLE #PsseContentCustomFieldBlocklist
(
    ViewName sysname NULL,
    ColumnName sysname NOT NULL
);

INSERT INTO #PsseContentCustomFieldBlocklist (ViewName, ColumnName)
VALUES
    (N'Assignments', N'RBS_R'),
    (N'Assignments', N'CostType_R'),
    (N'Assignments', N'FlagStatus_T'),
    (N'Assignments', N'TeamName_R'),
    (N'Assignments', N'ResourceDepartments_R'),
    (N'Assignments', N'Health_T'),
    (N'Assignments', N'Profilderessource_R'),
    (N'Assignments', N'Contexte_T'),
    (N'Assignments', N'Notedepilotage_R'),
    (N'Assignments', N'OBS_R'),
    (N'Assignments', N'Capitalisable_T'),
    (N'Assignments', N'CompteComptableExterne_T'),
    (N'Assignments', N'CodeDeProjet_T'),
    (N'Assignments', N'NoContrat_T'),
    (N'Assignments', N'NoDemande_T'),
    (N'Assignments', N'NoItem_T'),
    (N'Assignments', N'DescItem_T'),
    (N'Assignments', N'NoEpic_T'),
    (N'Assignments', N'CF_CentreCout_T'),
    (N'Assignments', N'CF_Fin_T'),
    (N'Assignments', N'CF_Priorite_T_T'),
    (N'Assignments', N'CF_UA_R'),
    (N'Assignments', N'CF_UAC_T'),
    (N'Projects', N'ProjectDepartments'),
    (N'Projects', N'Statutduprojet'),
    (N'Projects', N'Typedebudget'),
    (N'Projects', N'PBS'),
    (N'Projects', N'Montantdubudget'),
    (N'Projects', N'CF_Etat'),
    (N'Projects', N'CF_Priorite_P'),
    (N'Projects', N'CF_TypeProjet'),
    (N'Resources', N'RBS'),
    (N'Resources', N'ResourceDepartments'),
    (N'Resources', N'TeamName'),
    (N'Resources', N'CostType'),
    (N'Resources', N'Profilderessource'),
    (N'Resources', N'Notedepilotage'),
    (N'Resources', N'OBS'),
    (N'Resources', N'CF_UA'),
    (N'Tasks', N'FlagStatus'),
    (N'Tasks', N'Health'),
    (N'Tasks', N'Contexte'),
    (N'Tasks', N'Capitalisable'),
    (N'Tasks', N'CompteComptableExterne'),
    (N'Tasks', N'CodeDeProjet'),
    (N'Tasks', N'NoContrat'),
    (N'Tasks', N'NoDemande'),
    (N'Tasks', N'NoItem'),
    (N'Tasks', N'DescItem'),
    (N'Tasks', N'NoEpic'),
    (N'Tasks', N'CF_CentreCout'),
    (N'Tasks', N'CF_Fin'),
    (N'Tasks', N'CF_Priorite_T'),
    (N'Tasks', N'CF_UAC'),
    (N'TimesheetLines', N'RBS');

CREATE TABLE #ProjectDataSourceViews
(
    ViewName sysname NOT NULL PRIMARY KEY,
    SourceViewName sysname NOT NULL
);

INSERT INTO #ProjectDataSourceViews (ViewName, SourceViewName)
SELECT SUBSTRING(target_view.name, 4, 128) AS ViewName, target_view.name AS SourceViewName
FROM sys.views AS target_view
JOIN sys.schemas AS target_schema
    ON target_schema.schema_id = target_view.schema_id
WHERE target_schema.name = N'tbx'
  AND target_view.name LIKE N'vw[_]%'
  AND target_view.name NOT LIKE N'%[_]src'
  AND target_view.name NOT LIKE N'%[_]alias'
  AND target_view.name NOT LIKE N'vw[_]ProjectData[_]%';

DECLARE projectdata_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT ViewName, SourceViewName
    FROM #ProjectDataSourceViews
    ORDER BY ViewName;

OPEN projectdata_cursor;
FETCH NEXT FROM projectdata_cursor INTO @ViewName, @SourceViewName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SELECT @ColumnList = STRING_AGG(CONVERT(nvarchar(max), QUOTENAME(source_column.name)), N',' + CHAR(13) + CHAR(10) + N'    ')
        WITHIN GROUP (ORDER BY source_column.column_id)
    FROM sys.views AS source_view
    JOIN sys.schemas AS source_schema
        ON source_schema.schema_id = source_view.schema_id
    JOIN sys.columns AS source_column
        ON source_column.object_id = source_view.object_id
    WHERE source_schema.name = N'tbx'
      AND source_view.name = @SourceViewName
      AND source_column.name COLLATE Latin1_General_100_BIN2 NOT LIKE N'%[^ -~]%'
      AND (@ExcludePsseContentCustomFields = 0 OR source_column.name NOT LIKE N'CF[_]%')
      AND NOT EXISTS
      (
          SELECT 1
          FROM #PsseContentCustomFieldBlocklist AS blocklist
          WHERE @ExcludePsseContentCustomFields = 1
            AND (blocklist.ViewName IS NULL OR blocklist.ViewName = @ViewName)
            AND blocklist.ColumnName = source_column.name
      );

    IF @ColumnList IS NULL
        THROW 66005, N'Aucune colonne admissible pour une vue ProjectData.', 1;

    SET @Sql = N'CREATE VIEW ProjectData.' + QUOTENAME(@ViewName) + N'
AS
SELECT
    ' + @ColumnList + N'
FROM tbx.' + QUOTENAME(@SourceViewName) + N';';

    EXEC sys.sp_executesql @Sql;
    SET @ProjectDataViewCount += 1;

    FETCH NEXT FROM projectdata_cursor INTO @ViewName, @SourceViewName;
END;

CLOSE projectdata_cursor;
DEALLOCATE projectdata_cursor;

SELECT @InternalViewCount = COUNT(*)
FROM sys.views AS target_view
JOIN sys.schemas AS target_schema
    ON target_schema.schema_id = target_view.schema_id
WHERE target_schema.name IN (N'tbx', N'tbx_fr', N'tbx_master');

CREATE TABLE #ViewValidation
(
    SchemaName sysname NOT NULL,
    ViewName sysname NOT NULL,
    IsOk bit NOT NULL,
    ErrorMessage nvarchar(4000) NULL
);

DECLARE validation_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT target_schema.name, target_view.name
    FROM sys.views AS target_view
    JOIN sys.schemas AS target_schema
        ON target_schema.schema_id = target_view.schema_id
    WHERE target_schema.name IN (N'ProjectData', N'tbx', N'tbx_fr', N'tbx_master')
    ORDER BY target_schema.name, target_view.name;

OPEN validation_cursor;
FETCH NEXT FROM validation_cursor INTO @SchemaName, @ViewName;

WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        SET @Sql = N'DECLARE @RowCount bigint; SELECT @RowCount = COUNT_BIG(*) FROM (SELECT TOP (0) * FROM '
            + QUOTENAME(@SchemaName) + N'.' + QUOTENAME(@ViewName) + N') AS view_probe;';
        EXEC sys.sp_executesql @Sql;

        INSERT INTO #ViewValidation (SchemaName, ViewName, IsOk, ErrorMessage)
        VALUES (@SchemaName, @ViewName, 1, NULL);
    END TRY
    BEGIN CATCH
        INSERT INTO #ViewValidation (SchemaName, ViewName, IsOk, ErrorMessage)
        VALUES (@SchemaName, @ViewName, 0, ERROR_MESSAGE());
    END CATCH;

    FETCH NEXT FROM validation_cursor INTO @SchemaName, @ViewName;
END;

CLOSE validation_cursor;
DEALLOCATE validation_cursor;

SELECT @InvalidViewCount = COUNT(*)
FROM #ViewValidation
WHERE IsOk = 0;

SELECT @BlockedColumnCount = COUNT(*)
FROM #ProjectDataSourceViews AS projectdata_view
JOIN sys.views AS source_view
    ON source_view.name = projectdata_view.SourceViewName
JOIN sys.schemas AS source_schema
    ON source_schema.schema_id = source_view.schema_id
   AND source_schema.name = N'tbx'
JOIN sys.columns AS source_column
    ON source_column.object_id = source_view.object_id
WHERE source_column.name COLLATE Latin1_General_100_BIN2 LIKE N'%[^ -~]%'
   OR (@ExcludePsseContentCustomFields = 1 AND source_column.name LIKE N'CF[_]%')
   OR EXISTS
      (
          SELECT 1
          FROM #PsseContentCustomFieldBlocklist AS blocklist
          WHERE @ExcludePsseContentCustomFields = 1
            AND (blocklist.ViewName IS NULL OR blocklist.ViewName = projectdata_view.ViewName)
            AND blocklist.ColumnName = source_column.name
      );

SELECT @ProjectDataCustomColumnCount = COUNT(*)
FROM sys.views AS target_view
JOIN sys.schemas AS target_schema
    ON target_schema.schema_id = target_view.schema_id
JOIN sys.columns AS target_column
    ON target_column.object_id = target_view.object_id
JOIN #ProjectDataSourceViews AS projectdata_view
    ON projectdata_view.ViewName = target_view.name
WHERE target_schema.name = N'ProjectData'
  AND
  (
      target_column.name COLLATE Latin1_General_100_BIN2 LIKE N'%[^ -~]%'
      OR (@ExcludePsseContentCustomFields = 1 AND target_column.name LIKE N'CF[_]%')
      OR EXISTS
         (
             SELECT 1
             FROM #PsseContentCustomFieldBlocklist AS blocklist
             WHERE @ExcludePsseContentCustomFields = 1
               AND (blocklist.ViewName IS NULL OR blocklist.ViewName = projectdata_view.ViewName)
               AND blocklist.ColumnName = target_column.name
         )
  );

SELECT @LookupViewSynonymCount = COUNT(*)
FROM sys.synonyms AS target_synonym
JOIN sys.schemas AS target_schema
    ON target_schema.schema_id = target_synonym.schema_id
WHERE target_schema.name = N'src_pjrep'
  AND target_synonym.name LIKE N'MSPLT[_]LK%[_]UserView';

SET @EndMessage = CONCAT
(
    N'Création des vues natives terminée. ViewDefinitionMode=',
    @ViewDefinitionMode,
    N'; ExcludePsseContentCustomFields=',
    @ExcludePsseContentCustomFields,
    N'; InternalViews=',
    @InternalViewCount,
    N'; ProjectDataViews=',
    @ProjectDataViewCount,
    N'; InvalidViews=',
    @InvalidViewCount,
    N'; BlockedPsseCustomColumns=',
    @BlockedColumnCount,
    N'; ProjectDataPsseCustomColumns=',
    @ProjectDataCustomColumnCount,
    N'; LookupViewSynonyms=',
    @LookupViewSynonymCount
);

SET @RowsAffected = @InternalViewCount + @ProjectDataViewCount;

EXEC log.usp_WriteScriptLog
    @RunId = @RunId,
    @ScriptName = @ScriptName,
    @ScriptVersion = N'V6-DRAFT',
    @Phase = N'END',
    @Severity = N'INFO',
    @Status = N'COMPLETED',
    @Message = @EndMessage,
    @RowsAffected = @RowsAffected;

IF @InvalidViewCount > 0
BEGIN
    SELECT SchemaName, ViewName, ErrorMessage
    FROM #ViewValidation
    WHERE IsOk = 0
    ORDER BY SchemaName, ViewName;

    THROW 66006, N'Une ou plusieurs vues natives ne compilent pas dans la base cible.', 1;
END;

IF @ProjectDataCustomColumnCount > 0
    THROW 66007, N'Des champs personnalisés PSSE sont encore exposés dans ProjectData.', 1;

SELECT
    @ViewDefinitionMode AS ViewDefinitionMode,
    @ExcludePsseContentCustomFields AS ExcludePsseContentCustomFields,
    @InternalViewCount AS InternalViewCount,
    @ProjectDataViewCount AS ProjectDataViewCount,
    @InvalidViewCount AS InvalidViewCount,
    @BlockedColumnCount AS BlockedPsseCustomColumnCount,
    @ProjectDataCustomColumnCount AS ProjectDataPsseCustomColumnCount,
    @LookupViewSynonymCount AS LookupViewSynonymCount;

DROP TABLE #V6ScriptContext;
GO