/*=====================================================================================================================
    v6_03a_Create_Foundations.sql
    Projet      : SmartBox
    Phase       : 03a - Fondations V6
    Role        : Créer les schémas, tables, inventaire PSSE et synonymes source requis par V6.

    Contrat de schémas
    - stg    : données brutes temporaires (inventaire PSSE, import CSV via Load-DictionaryCSV.ps1)
    - dic    : dictionnaire normalisé exploitable (après v6_05a)
    - cfg    : configuration du tenant (PWA, Settings, scopes)
    - review : décisions et corrections manuelles
    - report : résultats de contrôle qualité
    - log    : journal d'exécution des scripts

    Notes V6
    - Le chargement des CSV du dictionnaire est fait par Load-DictionaryCSV.ps1 (SqlBulkCopy -> stg.import_dictionary_*).
    - Le schema `load` est obsolète et n'est pas créé.
    - Lit cfg.Settings et cfg.PwaSchemaScope pour inventorier la BD content PSSE et créer les synonymes.

    Structure en 4 lots GO:
      Lot 1 : prérequis et schémas.
      Lot 2 : création des tables si absentes (DDL pur, rejouable).
      Lot 3 : migration — ajouter SourceDatabaseName a cfg.PwaObjectScope (lot séparé requis).
      Lot 4 : inventaire PSSE, mise à jour cfg.PwaObjectScope, synonymes src_*, rapport.
=====================================================================================================================*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* ===== LOT 1 : Prérequis et création des schémas ===== */

IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb')
BEGIN
    THROW 63001, N'Exécuter ce script dans la base SmartBox cible.', 1;
END;

IF OBJECT_ID(N'cfg.Settings', N'U') IS NULL
    THROW 63002, N'cfg.Settings absente. Exécuter v6_02a avant v6_03a.', 1;

IF OBJECT_ID(N'log.ScriptExecutionLog', N'U') IS NULL
    THROW 63003, N'log.ScriptExecutionLog absente. Exécuter v6_02a avant v6_03a.', 1;

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'src') EXEC(N'CREATE SCHEMA src AUTHORIZATION dbo;');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'stg') EXEC(N'CREATE SCHEMA stg AUTHORIZATION dbo;');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'dic') EXEC(N'CREATE SCHEMA dic AUTHORIZATION dbo;');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'tbx') EXEC(N'CREATE SCHEMA tbx AUTHORIZATION dbo;');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'tbx_fr') EXEC(N'CREATE SCHEMA tbx_fr AUTHORIZATION dbo;');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'tbx_master') EXEC(N'CREATE SCHEMA tbx_master AUTHORIZATION dbo;');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'ProjectData') EXEC(N'CREATE SCHEMA ProjectData AUTHORIZATION dbo;');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'review') EXEC(N'CREATE SCHEMA review AUTHORIZATION dbo;');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'report') EXEC(N'CREATE SCHEMA report AUTHORIZATION dbo;');
GO

/* ===== LOT 2 : Création des tables si absentes (DDL pur, rejouable) ===== */

IF OBJECT_ID(N'cfg.PwaObjectScope', N'U') IS NULL
BEGIN
    CREATE TABLE cfg.PwaObjectScope
    (
        PWAId               int            NOT NULL,
        SourceSchemaName    sysname        NOT NULL,
        SourceObjectName    sysname        NOT NULL,
        ObjectType          nvarchar(60)   NULL,
        SmartBoxSchemaName  sysname        NULL,
        SmartBoxObjectName  sysname        NULL,
        SourceDatabaseName  sysname        NULL,
        IsActive            bit            NOT NULL CONSTRAINT DF_cfg_PwaObjectScope_IsActive DEFAULT(1),
        IsSelected          bit            NOT NULL CONSTRAINT DF_cfg_PwaObjectScope_IsSelected DEFAULT(1),
        UpdatedOn           datetime2(0)   NOT NULL CONSTRAINT DF_cfg_PwaObjectScope_UpdatedOn DEFAULT(sysdatetime()),
        UpdatedBy           sysname        NOT NULL CONSTRAINT DF_cfg_PwaObjectScope_UpdatedBy DEFAULT(suser_sname()),
        CONSTRAINT PK_cfg_PwaObjectScope PRIMARY KEY (PWAId, SourceSchemaName, SourceObjectName)
    );
END;

IF OBJECT_ID(N'stg.ObjectInventory', N'U') IS NULL
BEGIN
    CREATE TABLE stg.ObjectInventory
    (
        ObjectInventoryId bigint IDENTITY(1,1) NOT NULL,
        RunId uniqueidentifier NOT NULL,
        PWAId int NOT NULL,
        SourceDatabaseName sysname NOT NULL,
        SourceSchemaName sysname NOT NULL,
        SourceObjectName sysname NOT NULL,
        ObjectType nvarchar(60) NOT NULL,
        CreateDate datetime NULL,
        ModifyDate datetime NULL,
        RowEstimate bigint NULL,
        InventoriedAt datetime2(0) NOT NULL CONSTRAINT DF_stg_ObjectInventory_InventoriedAt DEFAULT(sysdatetime()),
        CONSTRAINT PK_stg_ObjectInventory PRIMARY KEY (ObjectInventoryId)
    );

    CREATE INDEX IX_stg_ObjectInventory_Object
        ON stg.ObjectInventory (PWAId, SourceDatabaseName, SourceSchemaName, SourceObjectName);
END;

IF OBJECT_ID(N'stg.ColumnInventory', N'U') IS NULL
BEGIN
    CREATE TABLE stg.ColumnInventory
    (
        ColumnInventoryId bigint IDENTITY(1,1) NOT NULL,
        RunId uniqueidentifier NOT NULL,
        PWAId int NOT NULL,
        SourceDatabaseName sysname NOT NULL,
        SourceSchemaName sysname NOT NULL,
        SourceObjectName sysname NOT NULL,
        ColumnId int NOT NULL,
        ColumnName sysname NOT NULL,
        DataType sysname NOT NULL,
        MaxLength smallint NOT NULL,
        PrecisionValue tinyint NOT NULL,
        ScaleValue tinyint NOT NULL,
        IsNullable bit NOT NULL,
        InventoriedAt datetime2(0) NOT NULL CONSTRAINT DF_stg_ColumnInventory_InventoriedAt DEFAULT(sysdatetime()),
        CONSTRAINT PK_stg_ColumnInventory PRIMARY KEY (ColumnInventoryId)
    );

    CREATE INDEX IX_stg_ColumnInventory_Column
        ON stg.ColumnInventory (PWAId, SourceDatabaseName, SourceSchemaName, SourceObjectName, ColumnName);
END;

IF OBJECT_ID(N'stg.import_dictionary_od_fields', N'U') IS NULL
BEGIN
    CREATE TABLE stg.import_dictionary_od_fields
    (
        SourceSystem nvarchar(128) NULL,
        EntityName nvarchar(256) NULL,
        FieldName nvarchar(256) NULL,
        LogicalType nvarchar(128) NULL,
        TypeName nvarchar(128) NULL,
        IsNullableRaw nvarchar(20) NULL,
        LoadedOn datetime2(0) NOT NULL CONSTRAINT DF_stg_import_dictionary_od_fields_LoadedOn DEFAULT(sysdatetime())
    );
END;

IF OBJECT_ID(N'stg.import_dictionary_lookup_entries', N'U') IS NULL
BEGIN
    CREATE TABLE stg.import_dictionary_lookup_entries
    (
        LookupTableId nvarchar(64) NULL,
        LookupTableName nvarchar(256) NULL,
        EntryId nvarchar(64) NULL,
        EntryCode nvarchar(256) NULL,
        EntryLabel nvarchar(512) NULL,
        ParentEntryId nvarchar(64) NULL,
        EntityType nvarchar(128) NULL,
        CustomFieldId nvarchar(64) NULL,
        CustomFieldName nvarchar(256) NULL,
        FieldType nvarchar(128) NULL,
        SourceSystem nvarchar(128) NULL,
        LoadedOn datetime2(0) NOT NULL CONSTRAINT DF_stg_import_dictionary_lookup_entries_LoadedOn DEFAULT(sysdatetime())
    );
END;

IF OBJECT_ID(N'stg.import_dictionary_projectdata_alias', N'U') IS NULL
BEGIN
    CREATE TABLE stg.import_dictionary_projectdata_alias
    (
        Endpoint_EN nvarchar(256) NULL,
        Endpoint_FR nvarchar(256) NULL,
        EndpointMatchCountRaw nvarchar(30) NULL,
        EndPointMatchStatus nvarchar(50) NULL,
        PrimitiveColumnCount_ENRaw nvarchar(30) NULL,
        PrimitiveColumnCount_FRRaw nvarchar(30) NULL,
        ColumnPositionRaw nvarchar(30) NULL,
        Column_EN nvarchar(256) NULL,
        Column_FR nvarchar(256) NULL,
        ColumnClassification nvarchar(30) NULL,
        Kind_EN nvarchar(128) NULL,
        TypeName_EN nvarchar(128) NULL,
        IsNullable_ENRaw nvarchar(20) NULL,
        Kind_FR nvarchar(128) NULL,
        TypeName_FR nvarchar(128) NULL,
        IsNullable_FRRaw nvarchar(20) NULL,
        PositionMatchRaw nvarchar(20) NULL,
        TypeMatchRaw nvarchar(20) NULL,
        NullabilityMatchRaw nvarchar(20) NULL,
        ColumnMatchStatus nvarchar(50) NULL,
        LoadedOn datetime2(0) NOT NULL CONSTRAINT DF_stg_import_dictionary_projectdata_alias_LoadedOn DEFAULT(sysdatetime())
    );
END;

IF OBJECT_ID(N'review.ReconstructionDecision', N'U') IS NULL
BEGIN
    CREATE TABLE review.ReconstructionDecision
    (
        ReconstructionDecisionId bigint IDENTITY(1,1) NOT NULL,
        EntityName sysname NOT NULL,
        ODataColumnName sysname NULL,
        DecisionScope nvarchar(40) NOT NULL,
        DecisionStatus nvarchar(30) NOT NULL,
        SourceExpression nvarchar(2000) NULL,
        JoinExpression nvarchar(2000) NULL,
        ReviewerComment nvarchar(4000) NULL,
        AppliedOn datetime2(0) NULL,
        AppliedBy sysname NULL,
        CreatedOn datetime2(0) NOT NULL CONSTRAINT DF_review_ReconstructionDecision_CreatedOn DEFAULT(sysdatetime()),
        CreatedBy sysname NOT NULL CONSTRAINT DF_review_ReconstructionDecision_CreatedBy DEFAULT(suser_sname()),
        CONSTRAINT PK_review_ReconstructionDecision PRIMARY KEY (ReconstructionDecisionId)
    );

    CREATE INDEX IX_review_ReconstructionDecision_Entity
        ON review.ReconstructionDecision (EntityName, ODataColumnName, DecisionStatus);
END;

IF OBJECT_ID(N'report.FoundationCheckResult', N'U') IS NULL
BEGIN
    CREATE TABLE report.FoundationCheckResult
    (
        FoundationCheckResultId bigint IDENTITY(1,1) NOT NULL,
        RunId uniqueidentifier NOT NULL,
        Category nvarchar(60) NOT NULL,
        Metric nvarchar(128) NOT NULL,
        MetricValue nvarchar(4000) NULL,
        IsOk bit NOT NULL,
        Notes nvarchar(4000) NULL,
        ReportedAt datetime2(0) NOT NULL CONSTRAINT DF_report_FoundationCheckResult_ReportedAt DEFAULT(sysdatetime()),
        CONSTRAINT PK_report_FoundationCheckResult PRIMARY KEY (FoundationCheckResultId)
    );
END;

IF OBJECT_ID(N'report.DictionaryQualityReport', N'U') IS NULL
BEGIN
    CREATE TABLE report.DictionaryQualityReport
    (
        DictionaryQualityReportId bigint IDENTITY(1,1) NOT NULL,
        RunId uniqueidentifier NOT NULL,
        IssueSeverity nvarchar(20) NOT NULL,
        IssueCode nvarchar(100) NOT NULL,
        EntityName sysname NULL,
        ColumnName sysname NULL,
        IssueMessage nvarchar(4000) NOT NULL,
        ReportedAt datetime2(0) NOT NULL CONSTRAINT DF_report_DictionaryQualityReport_ReportedAt DEFAULT(sysdatetime()),
        CONSTRAINT PK_report_DictionaryQualityReport PRIMARY KEY (DictionaryQualityReportId)
    );
END;

IF OBJECT_ID(N'report.ViewStackValidation', N'U') IS NULL
BEGIN
    CREATE TABLE report.ViewStackValidation
    (
        ViewStackValidationId bigint IDENTITY(1,1) NOT NULL,
        RunId uniqueidentifier NOT NULL,
        ViewSchema sysname NOT NULL,
        ViewName sysname NOT NULL,
        ValidationStatus nvarchar(30) NOT NULL,
        Message nvarchar(4000) NULL,
        ReportedAt datetime2(0) NOT NULL CONSTRAINT DF_report_ViewStackValidation_ReportedAt DEFAULT(sysdatetime()),
        CONSTRAINT PK_report_ViewStackValidation PRIMARY KEY (ViewStackValidationId)
    );
END;

IF OBJECT_ID(N'report.BlockingErrorReport', N'U') IS NULL
BEGIN
    CREATE TABLE report.BlockingErrorReport
    (
        BlockingErrorReportId bigint IDENTITY(1,1) NOT NULL,
        RunId uniqueidentifier NOT NULL,
        ExecutionLogId bigint NULL,
        ScriptName sysname NULL,
        Phase nvarchar(100) NULL,
        ErrorCategory nvarchar(100) NULL,
        TechnicalMessage nvarchar(4000) NULL,
        RecommendedAction nvarchar(4000) NULL,
        ReportedAt datetime2(0) NOT NULL CONSTRAINT DF_report_BlockingErrorReport_ReportedAt DEFAULT(sysdatetime()),
        CONSTRAINT PK_report_BlockingErrorReport PRIMARY KEY (BlockingErrorReportId)
    );
END;
GO

/* ===== LOT 3 : Migration — ajouter SourceDatabaseName a cfg.PwaObjectScope (lot séparé requis) ===== */
/* Correctif 2: idempotent pour les installations existantes sans cette colonne. */
IF COL_LENGTH(N'cfg.PwaObjectScope', N'SourceDatabaseName') IS NULL
    ALTER TABLE cfg.PwaObjectScope ADD SourceDatabaseName sysname NULL;
GO

/* ===== LOT 4 : Inventaire PSSE natif, synonymes source et rapport de fondations ===== */

DECLARE @RunId uniqueidentifier = newid();
DECLARE @ScriptName sysname = N'v6_03a_Create_Foundations.sql';
DECLARE @ContentDbName sysname;
DECLARE @ProjectSchemasCsv nvarchar(200);
DECLARE @PwaId int;
DECLARE @Sql nvarchar(max);
DECLARE @ObjectCount int = 0;
DECLARE @ColumnCount int = 0;
DECLARE @SynonymCount int = 0;
DECLARE @SchemaName sysname;
DECLARE @SourceSchemaName sysname;
DECLARE @SourceObjectName sysname;
DECLARE @SmartBoxSchemaName sysname;
DECLARE @SmartBoxObjectName sysname;
DECLARE @DropAllSynonymsSql nvarchar(max);
DECLARE @EndMessage nvarchar(max);

EXEC log.usp_WriteScriptLog
    @RunId = @RunId,
    @ScriptName = @ScriptName,
    @ScriptVersion = N'V6-DRAFT',
    @Phase = N'START',
    @Severity = N'INFO',
    @Status = N'STARTED',
    @Message = N'Début création des fondations V6.';

SELECT @ContentDbName = NULLIF(LTRIM(RTRIM(SettingValue)), N'')
FROM cfg.Settings
WHERE SettingKey = N'ContentDbName';

SELECT @PwaId = TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(SettingValue)), N''))
FROM cfg.Settings
WHERE SettingKey = N'PwaId';

SELECT @ProjectSchemasCsv = STRING_AGG(CONVERT(nvarchar(max), SchemaName), N',')
FROM cfg.PwaSchemaScope
WHERE PWAId = ISNULL(@PwaId, 1);

IF @ProjectSchemasCsv IS NULL
BEGIN
    SELECT @ProjectSchemasCsv = NULLIF(LTRIM(RTRIM(SettingValue)), N'')
    FROM cfg.Settings
    WHERE SettingKey = N'ProjectSchemasCsv';
END;

IF @ContentDbName IS NULL
    THROW 63004, N'cfg.Settings.ContentDbName est requis avant v6_03a.', 1;

IF DB_ID(@ContentDbName) IS NULL
    THROW 63005, N'La base source declaree dans cfg.Settings.ContentDbName est introuvable.', 1;

IF @ProjectSchemasCsv IS NULL
    THROW 63006, N'cfg.PwaSchemaScope ou cfg.Settings.ProjectSchemasCsv est requis avant v6_03a.', 1;

IF @PwaId IS NULL
    SET @PwaId = 1;

/* Correctif 1: nettoyage complet par PWAId — elimine les artefacts d'une ancienne ContentDbName. */
DELETE FROM stg.ColumnInventory WHERE PWAId = @PwaId;
DELETE FROM stg.ObjectInventory WHERE PWAId = @PwaId;
DELETE FROM cfg.PwaObjectScope WHERE PWAId = @PwaId;

/* Inventaire PSSE natif depuis la BD content. */
SET @Sql = N'
INSERT INTO stg.ObjectInventory
(
    RunId,
    PWAId,
    SourceDatabaseName,
    SourceSchemaName,
    SourceObjectName,
    ObjectType,
    CreateDate,
    ModifyDate,
    RowEstimate
)
SELECT
    @RunId,
    @PwaId,
    @SourceDatabaseName,
    src_schema.name,
    src_object.name,
    src_object.type_desc,
    src_object.create_date,
    src_object.modify_date,
    SUM(CASE WHEN src_partition.index_id IN (0, 1) THEN src_partition.rows ELSE 0 END)
FROM ' + QUOTENAME(@ContentDbName) + N'.sys.objects AS src_object
JOIN ' + QUOTENAME(@ContentDbName) + N'.sys.schemas AS src_schema
    ON src_schema.schema_id = src_object.schema_id
LEFT JOIN ' + QUOTENAME(@ContentDbName) + N'.sys.partitions AS src_partition
    ON src_partition.object_id = src_object.object_id
WHERE src_object.type IN (N''U'', N''V'')
  AND EXISTS
  (
      SELECT 1
      FROM STRING_SPLIT(@ProjectSchemasCsv, N'','') AS schema_filter
      WHERE LTRIM(RTRIM(schema_filter.value)) = src_schema.name
  )
GROUP BY
    src_schema.name,
    src_object.name,
    src_object.type_desc,
    src_object.create_date,
    src_object.modify_date;

INSERT INTO stg.ColumnInventory
(
    RunId,
    PWAId,
    SourceDatabaseName,
    SourceSchemaName,
    SourceObjectName,
    ColumnId,
    ColumnName,
    DataType,
    MaxLength,
    PrecisionValue,
    ScaleValue,
    IsNullable
)
SELECT
    @RunId,
    @PwaId,
    @SourceDatabaseName,
    src_schema.name,
    src_object.name,
    src_column.column_id,
    src_column.name,
    src_type.name,
    src_column.max_length,
    src_column.precision,
    src_column.scale,
    src_column.is_nullable
FROM ' + QUOTENAME(@ContentDbName) + N'.sys.objects AS src_object
JOIN ' + QUOTENAME(@ContentDbName) + N'.sys.schemas AS src_schema
    ON src_schema.schema_id = src_object.schema_id
JOIN ' + QUOTENAME(@ContentDbName) + N'.sys.columns AS src_column
    ON src_column.object_id = src_object.object_id
JOIN ' + QUOTENAME(@ContentDbName) + N'.sys.types AS src_type
    ON src_type.user_type_id = src_column.user_type_id
WHERE src_object.type IN (N''U'', N''V'')
  AND EXISTS
  (
      SELECT 1
      FROM STRING_SPLIT(@ProjectSchemasCsv, N'','') AS schema_filter
      WHERE LTRIM(RTRIM(schema_filter.value)) = src_schema.name
  );';

EXEC sys.sp_executesql
    @Sql,
    N'@RunId uniqueidentifier, @PwaId int, @SourceDatabaseName sysname, @ProjectSchemasCsv nvarchar(200)',
    @RunId = @RunId,
    @PwaId = @PwaId,
    @SourceDatabaseName = @ContentDbName,
    @ProjectSchemasCsv = @ProjectSchemasCsv;

/* Correctif 3: MERGE inclut SourceDatabaseName. */
MERGE cfg.PwaObjectScope AS target_scope
USING
(
    SELECT
        PWAId,
        SourceSchemaName,
        SourceObjectName,
        ObjectType,
        CONVERT(sysname, N'src_' + SourceSchemaName) AS SmartBoxSchemaName,
        SourceObjectName AS SmartBoxObjectName,
        @ContentDbName AS SourceDatabaseName
    FROM stg.ObjectInventory
    WHERE RunId = @RunId
) AS source_scope
    ON target_scope.PWAId = source_scope.PWAId
   AND target_scope.SourceSchemaName = source_scope.SourceSchemaName
   AND target_scope.SourceObjectName = source_scope.SourceObjectName
WHEN MATCHED THEN
    UPDATE SET
        target_scope.ObjectType = source_scope.ObjectType,
        target_scope.SmartBoxSchemaName = source_scope.SmartBoxSchemaName,
        target_scope.SmartBoxObjectName = source_scope.SmartBoxObjectName,
        target_scope.SourceDatabaseName = source_scope.SourceDatabaseName,
        target_scope.IsActive = 1,
        target_scope.IsSelected = 1,
        target_scope.UpdatedOn = sysdatetime(),
        target_scope.UpdatedBy = suser_sname()
WHEN NOT MATCHED THEN
    INSERT
    (
        PWAId,
        SourceSchemaName,
        SourceObjectName,
        ObjectType,
        SmartBoxSchemaName,
        SmartBoxObjectName,
        SourceDatabaseName,
        IsActive,
        IsSelected
    )
    VALUES
    (
        source_scope.PWAId,
        source_scope.SourceSchemaName,
        source_scope.SourceObjectName,
        source_scope.ObjectType,
        source_scope.SmartBoxSchemaName,
        source_scope.SmartBoxObjectName,
        source_scope.SourceDatabaseName,
        1,
        1
    );

SELECT @ObjectCount = COUNT(*)
FROM stg.ObjectInventory
WHERE RunId = @RunId;

SELECT @ColumnCount = COUNT(*)
FROM stg.ColumnInventory
WHERE RunId = @RunId;

EXEC log.usp_WriteScriptLog
    @RunId = @RunId,
    @ScriptName = @ScriptName,
    @ScriptVersion = N'V6-DRAFT',
    @Phase = N'INVENTORY',
    @Severity = N'INFO',
    @Status = N'COMPLETED',
    @Message = N'Inventaire PSSE natif et cfg.PwaObjectScope synchronises.',
    @RowsAffected = @ObjectCount;

/* Création des schémas src_* depuis cfg.PwaObjectScope. */
DECLARE schema_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT SmartBoxSchemaName
    FROM cfg.PwaObjectScope
    WHERE PWAId = @PwaId
      AND IsActive = 1
      AND IsSelected = 1
      AND SmartBoxSchemaName IS NOT NULL;

OPEN schema_cursor;
FETCH NEXT FROM schema_cursor INTO @SchemaName;

WHILE @@FETCH_STATUS = 0
BEGIN
    IF SCHEMA_ID(@SchemaName) IS NULL
    BEGIN
        SET @Sql = N'CREATE SCHEMA ' + QUOTENAME(@SchemaName) + N' AUTHORIZATION dbo;';
        EXEC sys.sp_executesql @Sql;
    END;

    FETCH NEXT FROM schema_cursor INTO @SchemaName;
END;

CLOSE schema_cursor;
DEALLOCATE schema_cursor;

/* Correctif 4: supprimer tous les synonymes existants dans les schémas src_* avant reconstruction. */
SELECT @DropAllSynonymsSql = STRING_AGG(
    N'DROP SYNONYM ' + QUOTENAME(SCHEMA_NAME(schema_id)) + N'.' + QUOTENAME(name) + N';',
    N' '
) WITHIN GROUP (ORDER BY SCHEMA_NAME(schema_id), name)
FROM sys.synonyms
WHERE SCHEMA_NAME(schema_id) LIKE N'src_%';

IF @DropAllSynonymsSql IS NOT NULL
    EXEC sys.sp_executesql @DropAllSynonymsSql;

/* Création des synonymes source depuis cfg.PwaObjectScope. */
DECLARE synonym_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT
        SourceSchemaName,
        SourceObjectName,
        SmartBoxSchemaName,
        SmartBoxObjectName
    FROM cfg.PwaObjectScope
    WHERE PWAId = @PwaId
      AND IsActive = 1
      AND IsSelected = 1
      AND SmartBoxSchemaName IS NOT NULL
      AND SmartBoxObjectName IS NOT NULL
    ORDER BY SourceSchemaName, SourceObjectName;

OPEN synonym_cursor;
FETCH NEXT FROM synonym_cursor
INTO @SourceSchemaName, @SourceObjectName, @SmartBoxSchemaName, @SmartBoxObjectName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @Sql =
        N'CREATE SYNONYM ' + QUOTENAME(@SmartBoxSchemaName) + N'.' + QUOTENAME(@SmartBoxObjectName) +
        N' FOR ' + QUOTENAME(@ContentDbName) + N'.' + QUOTENAME(@SourceSchemaName) + N'.' + QUOTENAME(@SourceObjectName) + N';';
    EXEC sys.sp_executesql @Sql;

    SET @SynonymCount += 1;

    FETCH NEXT FROM synonym_cursor
    INTO @SourceSchemaName, @SourceObjectName, @SmartBoxSchemaName, @SmartBoxObjectName;
END;

CLOSE synonym_cursor;
DEALLOCATE synonym_cursor;

EXEC log.usp_WriteScriptLog
    @RunId = @RunId,
    @ScriptName = @ScriptName,
    @ScriptVersion = N'V6-DRAFT',
    @Phase = N'SYNONYMS',
    @Severity = N'INFO',
    @Status = N'COMPLETED',
    @Message = N'Synonymes source créés depuis cfg.PwaObjectScope.',
    @RowsAffected = @SynonymCount;

SET @EndMessage = CONCAT
(
    N'Fondations V6 créées ou validees. ContentDbName=',
    @ContentDbName,
    N'; Objects=',
    @ObjectCount,
    N'; Columns=',
    @ColumnCount,
    N'; Synonyms=',
    @SynonymCount
);

EXEC log.usp_WriteScriptLog
    @RunId = @RunId,
    @ScriptName = @ScriptName,
    @ScriptVersion = N'V6-DRAFT',
    @Phase = N'COMPLETED',
    @Severity = N'INFO',
    @Status = N'COMPLETED',
    @Message = @EndMessage,
    @RowsAffected = @SynonymCount;

SELECT
    SchemaName = s.name,
    ObjectName = o.name,
    ObjectType = o.type_desc
FROM sys.objects AS o
INNER JOIN sys.schemas AS s
    ON s.schema_id = o.schema_id
WHERE s.name IN (N'cfg', N'log', N'review', N'report', N'stg', N'dic', N'src_pjrep', N'src_pjpub')
ORDER BY s.name, o.name;

SELECT
    ContentDbName = @ContentDbName,
    PwaId = @PwaId,
    ProjectSchemasCsv = @ProjectSchemasCsv,
    ObjectCount = @ObjectCount,
    ColumnCount = @ColumnCount,
    SynonymCount = @SynonymCount;
GO
