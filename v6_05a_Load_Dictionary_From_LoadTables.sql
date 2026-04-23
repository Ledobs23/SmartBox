/*=====================================================================================================================
    v6_05a_Load_Dictionary_From_LoadTables.sql
    Projet      : SmartBox
    Phase       : 05a - Dictionnaire et mapping OData/PSSE
    Role        : Creer les tables cfg.dictionary_*, dic.*, stg.quality et alimenter le pipeline
                  de mapping OData <-> PSSE depuis stg.import_dictionary_* ou load.*.

    Notes V6
    - Aucune dependance a xp_cmdshell.
    - Chargement CSV possible via BULK INSERT (si DictionarySourcePath configure) ou pre-chargement externe.
    - Pipeline idempotent : rejouable sans perte de donnees.
    - Logs dans log.ScriptExecutionLog. Pas de stg.RunLog.
    - Langue pilotee par cfg.PWA.Language (FR ou EN).
    - dic.EntityColumnPublication est la source de verite consommable (phase ulterieure).

    Prerequis
    - v6_02a execute (cfg.Settings, log.ScriptExecutionLog)
    - v6_03a execute (stg.ObjectInventory, stg.ColumnInventory, synonymes src_*)
    - stg.import_dictionary_od_fields          peuple (voir note chargement ci-bas)
    - stg.import_dictionary_lookup_entries     peuple
    - stg.import_dictionary_projectdata_alias  peuple

    Chargement des CSV (jour 1)
    Si AllowFileSystemAccess = 0 (valeur par defaut MTMD) :
      - Utiliser SqlBulkCopy depuis PowerShell, SSIS ou outil externe
      - Les colonnes cibles sont definies dans stg.import_dictionary_*
      - Une fois les tables peuplees, rejouer ce script
    Si AllowFileSystemAccess = 1 et DictionarySourcePath configure :
      - Ce script tentera BULK INSERT automatiquement (voir Phase B)

    PARAMETRES CLIENT - SECTION A MODIFIER PAR LE DBA
    Aucun parametre client obligatoire dans ce script.
    Le comportement est pilote par cfg.Settings.
=====================================================================================================================*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb')
    THROW 65001, N'Executer ce script dans la base SmartBox cible.', 1;

IF OBJECT_ID(N'cfg.Settings', N'U') IS NULL
    THROW 65002, N'cfg.Settings absente. Executer v6_02a avant v6_05a.', 1;

IF OBJECT_ID(N'log.ScriptExecutionLog', N'U') IS NULL
    THROW 65003, N'log.ScriptExecutionLog absente. Executer v6_02a avant v6_05a.', 1;

IF OBJECT_ID(N'stg.ObjectInventory', N'U') IS NULL
    THROW 65004, N'stg.ObjectInventory absente. Executer v6_03a avant v6_05a.', 1;

IF OBJECT_ID(N'stg.import_dictionary_od_fields', N'U') IS NULL
    THROW 65005, N'stg.import_dictionary_od_fields absente. Executer v6_03a avant v6_05a.', 1;

/* ===========================================================================================
   PHASE A : CREATION DES TABLES SI ABSENTES
   =========================================================================================== */

/* cfg.dictionary_od_fields - Contrat OData (champs, types, nullabilite) */
IF OBJECT_ID(N'cfg.dictionary_od_fields', N'U') IS NULL
BEGIN
    CREATE TABLE cfg.dictionary_od_fields
    (
        OdFieldId       bigint IDENTITY(1,1) NOT NULL,
        SourceSystem    nvarchar(128) NOT NULL CONSTRAINT DF_cfg_dictionary_od_fields_Src DEFAULT(N'ProjectData'),
        EntityName_FR   nvarchar(256) NOT NULL,
        FieldName_FR    nvarchar(256) NOT NULL,
        LogicalType     nvarchar(128) NULL,
        TypeName        nvarchar(128) NULL,
        IsNullable      bit NULL,
        EntityName_EN   nvarchar(256) NULL,
        FieldName_EN    nvarchar(256) NULL,
        LoadedFrom      nvarchar(60) NULL,
        UpdatedOn       datetime2(0) NOT NULL CONSTRAINT DF_cfg_dictionary_od_fields_Upd DEFAULT(sysdatetime()),
        UpdatedBy       sysname NOT NULL CONSTRAINT DF_cfg_dictionary_od_fields_UpdBy DEFAULT(suser_sname()),
        CONSTRAINT PK_cfg_dictionary_od_fields PRIMARY KEY (OdFieldId),
        CONSTRAINT UQ_cfg_dictionary_od_fields UNIQUE (EntityName_FR, FieldName_FR)
    );
END;

/* cfg.dictionary_lookup_entries - Table de lookup client */
IF OBJECT_ID(N'cfg.dictionary_lookup_entries', N'U') IS NULL
BEGIN
    CREATE TABLE cfg.dictionary_lookup_entries
    (
        LookupEntryId   bigint IDENTITY(1,1) NOT NULL,
        LookupTableId   nvarchar(64) NULL,
        LookupTableName nvarchar(256) NOT NULL,
        EntryId         nvarchar(64) NULL,
        EntryCode       nvarchar(256) NULL,
        EntryLabel      nvarchar(512) NULL,
        ParentEntryId   nvarchar(64) NULL,
        EntityType      nvarchar(128) NULL,
        CustomFieldId   nvarchar(64) NULL,
        CustomFieldName nvarchar(256) NULL,
        FieldType       nvarchar(128) NULL,
        SourceSystem    nvarchar(128) NULL,
        UpdatedOn       datetime2(0) NOT NULL CONSTRAINT DF_cfg_dictionary_lookup_entries_Upd DEFAULT(sysdatetime()),
        UpdatedBy       sysname NOT NULL CONSTRAINT DF_cfg_dictionary_lookup_entries_UpdBy DEFAULT(suser_sname()),
        CONSTRAINT PK_cfg_dictionary_lookup_entries PRIMARY KEY (LookupEntryId),
        CONSTRAINT UQ_cfg_dictionary_lookup_entries UNIQUE (LookupTableName, EntryCode)
    );
END;

/* cfg.dictionary_projectdata_alias - Table de correspondance bilingue EN/FR */
IF OBJECT_ID(N'cfg.dictionary_projectdata_alias', N'U') IS NULL
BEGIN
    CREATE TABLE cfg.dictionary_projectdata_alias
    (
        AliasId                     bigint IDENTITY(1,1) NOT NULL,
        Endpoint_EN                 nvarchar(256) NOT NULL,
        Endpoint_FR                 nvarchar(256) NULL,
        EndpointMatchCount          int NULL,
        EndpointMatchStatus         nvarchar(50) NULL,
        PrimitiveColumnCount_EN     int NULL,
        PrimitiveColumnCount_FR     int NULL,
        ColumnPosition              int NULL,
        Column_EN                   nvarchar(256) NOT NULL,
        Column_FR                   nvarchar(256) NULL,
        ColumnClassification        nvarchar(30) NULL,
        Kind_EN                     nvarchar(128) NULL,
        TypeName_EN                 nvarchar(128) NULL,
        IsNullable_EN               bit NULL,
        Kind_FR                     nvarchar(128) NULL,
        TypeName_FR                 nvarchar(128) NULL,
        IsNullable_FR               bit NULL,
        PositionMatch               bit NULL,
        TypeMatch                   bit NULL,
        NullabilityMatch            bit NULL,
        ColumnMatchStatus           nvarchar(50) NULL,
        UpdatedOn                   datetime2(0) NOT NULL CONSTRAINT DF_cfg_dictionary_projectdata_alias_Upd DEFAULT(sysdatetime()),
        UpdatedBy                   sysname NOT NULL CONSTRAINT DF_cfg_dictionary_projectdata_alias_UpdBy DEFAULT(suser_sname()),
        CONSTRAINT PK_cfg_dictionary_projectdata_alias PRIMARY KEY (AliasId),
        CONSTRAINT UQ_cfg_dictionary_projectdata_alias UNIQUE (Endpoint_EN, Column_EN)
    );

    CREATE INDEX IX_cfg_dictionary_projectdata_alias_FR
        ON cfg.dictionary_projectdata_alias (Endpoint_FR, Column_FR);
END;

/* dic.Entity - Entites canoniques */
IF OBJECT_ID(N'dic.Entity', N'U') IS NULL
BEGIN
    CREATE TABLE dic.Entity
    (
        EntityId                bigint IDENTITY(1,1) NOT NULL,
        EntityName_EN           nvarchar(256) NOT NULL,
        EntityName_FR           nvarchar(256) NULL,
        EndpointMatchCount      int NULL,
        EndpointMatchStatus     nvarchar(50) NULL,
        PrimitiveColumnCount_EN int NULL,
        PrimitiveColumnCount_FR int NULL,
        IsActive                bit NOT NULL CONSTRAINT DF_dic_Entity_IsActive DEFAULT(1),
        UpdatedOn               datetime2(0) NOT NULL CONSTRAINT DF_dic_Entity_Upd DEFAULT(sysdatetime()),
        UpdatedBy               sysname NOT NULL CONSTRAINT DF_dic_Entity_UpdBy DEFAULT(suser_sname()),
        CONSTRAINT PK_dic_Entity PRIMARY KEY (EntityId),
        CONSTRAINT UQ_dic_Entity UNIQUE (EntityName_EN)
    );
END;

/* dic.EntityColumnMap - Mapping colonne OData <-> PSSE */
IF OBJECT_ID(N'dic.EntityColumnMap', N'U') IS NULL
BEGIN
    CREATE TABLE dic.EntityColumnMap
    (
        EntityColumnMapId       bigint IDENTITY(1,1) NOT NULL,
        EntityName_EN           nvarchar(256) NOT NULL,
        ColumnPosition          int NOT NULL CONSTRAINT DF_dic_EntityColumnMap_Pos DEFAULT(0),
        Column_EN               nvarchar(256) NOT NULL,
        Column_FR               nvarchar(256) NULL,
        ColumnClassification    nvarchar(30) NULL,
        Kind_EN                 nvarchar(128) NULL,
        TypeName_EN             nvarchar(128) NULL,
        IsNullable_EN           bit NULL,
        Kind_FR                 nvarchar(128) NULL,
        TypeName_FR             nvarchar(128) NULL,
        IsNullable_FR           bit NULL,
        ColumnMatchStatus       nvarchar(50) NULL,
        PsseSourceSchema        nvarchar(128) NULL,
        PsseSourceObject        nvarchar(256) NULL,
        PsseColumnName          nvarchar(256) NULL,
        PsseMatchScore          tinyint NULL,
        UpdatedOn               datetime2(0) NOT NULL CONSTRAINT DF_dic_EntityColumnMap_Upd DEFAULT(sysdatetime()),
        UpdatedBy               sysname NOT NULL CONSTRAINT DF_dic_EntityColumnMap_UpdBy DEFAULT(suser_sname()),
        CONSTRAINT PK_dic_EntityColumnMap PRIMARY KEY (EntityColumnMapId),
        CONSTRAINT UQ_dic_EntityColumnMap UNIQUE (EntityName_EN, Column_EN)
    );

    CREATE INDEX IX_dic_EntityColumnMap_Entity
        ON dic.EntityColumnMap (EntityName_EN, ColumnClassification, ColumnPosition);
END;

/* dic.LookupMap - Entrees de lookup canoniques */
IF OBJECT_ID(N'dic.LookupMap', N'U') IS NULL
BEGIN
    CREATE TABLE dic.LookupMap
    (
        LookupMapId     bigint IDENTITY(1,1) NOT NULL,
        LookupTableId   nvarchar(64) NULL,
        LookupTableName nvarchar(256) NOT NULL,
        EntryId         nvarchar(64) NULL,
        EntryCode       nvarchar(256) NULL,
        EntryLabel      nvarchar(512) NULL,
        ParentEntryId   nvarchar(64) NULL,
        EntityType      nvarchar(128) NULL,
        CustomFieldId   nvarchar(64) NULL,
        CustomFieldName nvarchar(256) NULL,
        FieldType       nvarchar(128) NULL,
        SourceSystem    nvarchar(128) NULL,
        UpdatedOn       datetime2(0) NOT NULL CONSTRAINT DF_dic_LookupMap_Upd DEFAULT(sysdatetime()),
        UpdatedBy       sysname NOT NULL CONSTRAINT DF_dic_LookupMap_UpdBy DEFAULT(suser_sname()),
        CONSTRAINT PK_dic_LookupMap PRIMARY KEY (LookupMapId),
        CONSTRAINT UQ_dic_LookupMap UNIQUE (LookupTableName, EntryCode)
    );

    CREATE INDEX IX_dic_LookupMap_Table
        ON dic.LookupMap (LookupTableName, EntryCode);
END;

/* stg.ODataPsseExactColumnMatch - Correspondances OData <-> colonnes PSSE physiques */
IF OBJECT_ID(N'stg.ODataPsseExactColumnMatch', N'U') IS NULL
BEGIN
    CREATE TABLE stg.ODataPsseExactColumnMatch
    (
        MatchId                 bigint IDENTITY(1,1) NOT NULL,
        RunId                   uniqueidentifier NOT NULL,
        EntityName_EN           nvarchar(256) NOT NULL,
        Column_EN               nvarchar(256) NOT NULL,
        Column_FR               nvarchar(256) NULL,
        ColumnClassification    nvarchar(30) NULL,
        PsseDatabaseName        sysname NULL,
        PsseSchemaName          sysname NULL,
        PsseObjectName          nvarchar(256) NULL,
        PsseColumnName          nvarchar(256) NULL,
        MatchType               nvarchar(30) NOT NULL,
        ObjectMatchCount        int NULL,
        MatchedAt               datetime2(0) NOT NULL CONSTRAINT DF_stg_ODataPsseExactColumnMatch_At DEFAULT(sysdatetime()),
        CONSTRAINT PK_stg_ODataPsseExactColumnMatch PRIMARY KEY (MatchId)
    );

    CREATE INDEX IX_stg_ODataPsseExactColumnMatch_Entity
        ON stg.ODataPsseExactColumnMatch (EntityName_EN, Column_EN, MatchType);
END;

/* stg.DictionaryQualityIssue - Anomalies detectees dans le dictionnaire */
IF OBJECT_ID(N'stg.DictionaryQualityIssue', N'U') IS NULL
BEGIN
    CREATE TABLE stg.DictionaryQualityIssue
    (
        IssueId         bigint IDENTITY(1,1) NOT NULL,
        RunId           uniqueidentifier NOT NULL,
        IssueSeverity   nvarchar(20) NOT NULL,
        IssueCode       nvarchar(100) NOT NULL,
        EntityName_EN   nvarchar(256) NULL,
        ColumnName      nvarchar(256) NULL,
        IssueMessage    nvarchar(4000) NOT NULL,
        ReportedAt      datetime2(0) NOT NULL CONSTRAINT DF_stg_DictionaryQualityIssue_At DEFAULT(sysdatetime()),
        CONSTRAINT PK_stg_DictionaryQualityIssue PRIMARY KEY (IssueId)
    );
END;

/* stg.EntitySource_Draft - Sources PSSE proposees par entite */
IF OBJECT_ID(N'stg.EntitySource_Draft', N'U') IS NULL
BEGIN
    CREATE TABLE stg.EntitySource_Draft
    (
        EntitySourceDraftId bigint IDENTITY(1,1) NOT NULL,
        RunId               uniqueidentifier NOT NULL,
        EntityName_EN       nvarchar(256) NOT NULL,
        ProposedSchema      sysname NULL,
        ProposedObject      nvarchar(256) NULL,
        ColumnMatchCount    int NULL,
        TotalPrimitiveCols  int NULL,
        CoverageScore       decimal(5,2) NULL,
        ConfidenceLevel     nvarchar(20) NULL,
        Notes               nvarchar(4000) NULL,
        ProposedAt          datetime2(0) NOT NULL CONSTRAINT DF_stg_EntitySource_Draft_At DEFAULT(sysdatetime()),
        CONSTRAINT PK_stg_EntitySource_Draft PRIMARY KEY (EntitySourceDraftId)
    );

    CREATE INDEX IX_stg_EntitySource_Draft_Entity
        ON stg.EntitySource_Draft (EntityName_EN, CoverageScore DESC);
END;
GO

/* ===========================================================================================
   PHASE B : BULK INSERT CONDITIONNEL (si DictionarySourcePath configure et acces permis)
   =========================================================================================== */
DECLARE @RunId                  uniqueidentifier = newid();
DECLARE @ScriptName             sysname          = N'v6_05a_Load_Dictionary_From_LoadTables.sql';
DECLARE @ContentDbName          sysname;
DECLARE @PwaId                  int;
DECLARE @AllowFileSystemAccess  bit;
DECLARE @AllowCsvDay1Import     nvarchar(20);
DECLARE @DictionarySourcePath   nvarchar(500);
DECLARE @DictionaryFile_PD      nvarchar(260);
DECLARE @DictionaryFile_LK      nvarchar(260);
DECLARE @DictionaryFile_AL      nvarchar(260);
DECLARE @OdFieldsCount          int = 0;
DECLARE @LookupCount            int = 0;
DECLARE @AliasCount             int = 0;
DECLARE @Msg                    nvarchar(max);
DECLARE @Sql                    nvarchar(max);
DECLARE @CatchErrMsg            nvarchar(4000);

SELECT @ContentDbName = NULLIF(LTRIM(RTRIM(SettingValue)), N'')
FROM cfg.Settings WHERE SettingKey = N'ContentDbName';

SELECT @PwaId = TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(SettingValue)), N''))
FROM cfg.Settings WHERE SettingKey = N'PwaId';

SELECT @AllowFileSystemAccess = TRY_CONVERT(bit, NULLIF(LTRIM(RTRIM(SettingValue)), N''))
FROM cfg.Settings WHERE SettingKey = N'AllowFileSystemAccess';

SELECT @AllowCsvDay1Import = NULLIF(LTRIM(RTRIM(SettingValue)), N'')
FROM cfg.Settings WHERE SettingKey = N'AllowCsvDay1Import';

/* DictionarySourcePath : ajouter dans cfg.Settings si BULK INSERT sera utilise. */
SELECT @DictionarySourcePath = NULLIF(LTRIM(RTRIM(SettingValue)), N'')
FROM cfg.Settings WHERE SettingKey = N'DictionarySourcePath';

SELECT @DictionaryFile_PD = NULLIF(LTRIM(RTRIM(SettingValue)), N'')
FROM cfg.Settings WHERE SettingKey = N'DictionaryFile_ProjectData';

SELECT @DictionaryFile_LK = NULLIF(LTRIM(RTRIM(SettingValue)), N'')
FROM cfg.Settings WHERE SettingKey = N'DictionaryFile_Lookups';

SELECT @DictionaryFile_AL = NULLIF(LTRIM(RTRIM(SettingValue)), N'')
FROM cfg.Settings WHERE SettingKey = N'DictionaryFile_ProjectDataAlias';

SET @PwaId = ISNULL(@PwaId, 1);

EXEC log.usp_WriteScriptLog
    @RunId = @RunId, @ScriptName = @ScriptName, @ScriptVersion = N'V6-DRAFT',
    @Phase = N'START', @Severity = N'INFO', @Status = N'STARTED',
    @Message = N'Debut construction dictionnaire V6.';

/* Compter ce qui est deja dans stg.import */
SELECT @OdFieldsCount = COUNT(*) FROM stg.import_dictionary_od_fields;
SELECT @LookupCount   = COUNT(*) FROM stg.import_dictionary_lookup_entries;
SELECT @AliasCount    = COUNT(*) FROM stg.import_dictionary_projectdata_alias;

IF @AllowFileSystemAccess = 1
    AND @AllowCsvDay1Import IN (N'OPTIONAL', N'YES')
    AND @DictionarySourcePath IS NOT NULL
    AND (@OdFieldsCount = 0 OR @LookupCount = 0 OR @AliasCount = 0)
BEGIN
    /* Tenter BULK INSERT depuis DictionarySourcePath */
    DECLARE @PathPD nvarchar(800) = @DictionarySourcePath + N'\' + ISNULL(@DictionaryFile_PD, N'Fields_ProjectData_Export.csv');
    DECLARE @PathLK nvarchar(800) = @DictionarySourcePath + N'\' + ISNULL(@DictionaryFile_LK, N'Lookups_ProjectServer_Export.csv');
    DECLARE @PathAL nvarchar(800) = @DictionarySourcePath + N'\' + ISNULL(@DictionaryFile_AL, N'ProjectData_Alias.csv');

    IF @OdFieldsCount = 0
    BEGIN
        SET @Sql = N'
DELETE FROM stg.import_dictionary_od_fields;
BULK INSERT stg.import_dictionary_od_fields
FROM ''' + REPLACE(@PathPD, N'''', N'''''') + N'''
WITH (FIRSTROW=2, FIELDTERMINATOR='','', ROWTERMINATOR=''\n'', CODEPAGE=''65001'', MAXERRORS=10, TABLOCK);';
        BEGIN TRY
            EXEC sys.sp_executesql @Sql;
            SELECT @OdFieldsCount = COUNT(*) FROM stg.import_dictionary_od_fields;
            EXEC log.usp_WriteScriptLog @RunId=@RunId,@ScriptName=@ScriptName,@ScriptVersion=N'V6-DRAFT',
                @Phase=N'BULK_INSERT',@Severity=N'INFO',@Status=N'COMPLETED',
                @Message=N'BULK INSERT Fields_ProjectData_Export.csv OK.',@RowsAffected=@OdFieldsCount;
        END TRY
        BEGIN CATCH
            SET @CatchErrMsg = ERROR_MESSAGE();
            EXEC log.usp_WriteScriptLog @RunId=@RunId,@ScriptName=@ScriptName,@ScriptVersion=N'V6-DRAFT',
                @Phase=N'BULK_INSERT',@Severity=N'WARN',@Status=N'WARNING',
                @Message=N'BULK INSERT Fields_ProjectData_Export.csv echoue. Pre-charger stg.import_dictionary_od_fields manuellement.',
                @ErrorMessage=@CatchErrMsg;
        END CATCH;
    END;

    IF @LookupCount = 0
    BEGIN
        SET @Sql = N'
DELETE FROM stg.import_dictionary_lookup_entries;
BULK INSERT stg.import_dictionary_lookup_entries
FROM ''' + REPLACE(@PathLK, N'''', N'''''') + N'''
WITH (FIRSTROW=2, FIELDTERMINATOR='','', ROWTERMINATOR=''\n'', CODEPAGE=''65001'', MAXERRORS=10, TABLOCK);';
        BEGIN TRY
            EXEC sys.sp_executesql @Sql;
            SELECT @LookupCount = COUNT(*) FROM stg.import_dictionary_lookup_entries;
        END TRY
        BEGIN CATCH
            SET @CatchErrMsg = ERROR_MESSAGE();
            EXEC log.usp_WriteScriptLog @RunId=@RunId,@ScriptName=@ScriptName,@ScriptVersion=N'V6-DRAFT',
                @Phase=N'BULK_INSERT',@Severity=N'WARN',@Status=N'WARNING',
                @Message=N'BULK INSERT Lookups_ProjectServer_Export.csv echoue.',
                @ErrorMessage=@CatchErrMsg;
        END CATCH;
    END;

    IF @AliasCount = 0
    BEGIN
        SET @Sql = N'
DELETE FROM stg.import_dictionary_projectdata_alias;
BULK INSERT stg.import_dictionary_projectdata_alias
FROM ''' + REPLACE(@PathAL, N'''', N'''''') + N'''
WITH (FIRSTROW=2, FIELDTERMINATOR='','', ROWTERMINATOR=''\n'', CODEPAGE=''65001'', MAXERRORS=10, TABLOCK);';
        BEGIN TRY
            EXEC sys.sp_executesql @Sql;
            SELECT @AliasCount = COUNT(*) FROM stg.import_dictionary_projectdata_alias;
        END TRY
        BEGIN CATCH
            SET @CatchErrMsg = ERROR_MESSAGE();
            EXEC log.usp_WriteScriptLog @RunId=@RunId,@ScriptName=@ScriptName,@ScriptVersion=N'V6-DRAFT',
                @Phase=N'BULK_INSERT',@Severity=N'WARN',@Status=N'WARNING',
                @Message=N'BULK INSERT ProjectData_Alias.csv echoue.',
                @ErrorMessage=@CatchErrMsg;
        END CATCH;
    END;
END;
ELSE IF @OdFieldsCount = 0 OR @LookupCount = 0 OR @AliasCount = 0
BEGIN
    SET @Msg = CONCAT(
        N'Tables stg.import_dictionary_* partiellement vides. ',
        N'od_fields=', @OdFieldsCount, N'; lookups=', @LookupCount, N'; alias=', @AliasCount,
        N'. Pre-charger via SqlBulkCopy (PowerShell), SSIS ou outil externe avant de rejouer ce script. ',
        N'Consult la procedure de chargement dans la documentation V6.');
    EXEC log.usp_WriteScriptLog @RunId=@RunId,@ScriptName=@ScriptName,@ScriptVersion=N'V6-DRAFT',
        @Phase=N'LOAD_CHECK',@Severity=N'WARN',@Status=N'WARNING',@Message=@Msg;
    PRINT @Msg;
END;

IF @OdFieldsCount = 0 AND @LookupCount = 0 AND @AliasCount = 0
BEGIN
    EXEC log.usp_WriteScriptLog @RunId=@RunId,@ScriptName=@ScriptName,@ScriptVersion=N'V6-DRAFT',
        @Phase=N'LOAD_CHECK',@Severity=N'ERROR',@Status=N'ABORTED',
        @Message=N'Aucune donnee dans les tables stg.import_dictionary_*. Script interrompu.';
    THROW 65010, N'Les tables stg.import_dictionary_* sont toutes vides. Charger les donnees CSV avant de rejouer v6_05a.', 1;
END;

/* ===========================================================================================
   PHASE C : NORMALISATION stg.import_* -> cfg.dictionary_*
   =========================================================================================== */

/* C1 : cfg.dictionary_od_fields */
IF @OdFieldsCount > 0
BEGIN
    MERGE cfg.dictionary_od_fields AS T
    USING
    (
        SELECT
            ISNULL(src.SourceSystem, N'ProjectData')     AS SourceSystem,
            LTRIM(RTRIM(src.EntityName))                 AS EntityName_FR,
            LTRIM(RTRIM(src.FieldName))                  AS FieldName_FR,
            NULLIF(LTRIM(RTRIM(src.LogicalType)), N'')   AS LogicalType,
            NULLIF(LTRIM(RTRIM(src.TypeName)), N'')      AS TypeName,
            CASE
                WHEN UPPER(LTRIM(RTRIM(src.IsNullableRaw))) IN (N'1', N'VRAI', N'TRUE', N'YES', N'OUI') THEN CONVERT(bit, 1)
                WHEN UPPER(LTRIM(RTRIM(src.IsNullableRaw))) IN (N'0', N'FAUX', N'FALSE', N'NO', N'NON') THEN CONVERT(bit, 0)
                ELSE NULL
            END                                          AS IsNullable,
            N'LOAD_TABLE'                                AS LoadedFrom
        FROM stg.import_dictionary_od_fields src
        WHERE LTRIM(RTRIM(ISNULL(src.EntityName, N''))) <> N''
          AND LTRIM(RTRIM(ISNULL(src.FieldName, N''))) <> N''
    ) AS S
        ON S.EntityName_FR = T.EntityName_FR
       AND S.FieldName_FR = T.FieldName_FR
    WHEN MATCHED THEN
        UPDATE SET
            T.SourceSystem = S.SourceSystem,
            T.LogicalType  = S.LogicalType,
            T.TypeName     = S.TypeName,
            T.IsNullable   = S.IsNullable,
            T.LoadedFrom   = S.LoadedFrom,
            T.UpdatedOn    = sysdatetime(),
            T.UpdatedBy    = suser_sname()
    WHEN NOT MATCHED THEN
        INSERT (SourceSystem, EntityName_FR, FieldName_FR, LogicalType, TypeName, IsNullable, LoadedFrom)
        VALUES (S.SourceSystem, S.EntityName_FR, S.FieldName_FR, S.LogicalType, S.TypeName, S.IsNullable, S.LoadedFrom);

    EXEC log.usp_WriteScriptLog @RunId=@RunId,@ScriptName=@ScriptName,@ScriptVersion=N'V6-DRAFT',
        @Phase=N'CFG_ODFIELDS',@Severity=N'INFO',@Status=N'COMPLETED',
        @Message=N'cfg.dictionary_od_fields synchronise depuis stg.import_dictionary_od_fields.',
        @RowsAffected=@OdFieldsCount;
END;

/* C2 : cfg.dictionary_lookup_entries */
IF @LookupCount > 0
BEGIN
    MERGE cfg.dictionary_lookup_entries AS T
    USING
    (
        SELECT
            LookupTableId, LookupTableName, EntryId, EntryCode, EntryLabel,
            ParentEntryId, EntityType, CustomFieldId, CustomFieldName, FieldType, SourceSystem
        FROM
        (
            SELECT
                NULLIF(LTRIM(RTRIM(src.LookupTableId)), N'')   AS LookupTableId,
                LTRIM(RTRIM(src.LookupTableName))              AS LookupTableName,
                NULLIF(LTRIM(RTRIM(src.EntryId)), N'')         AS EntryId,
                NULLIF(LTRIM(RTRIM(src.EntryCode)), N'')       AS EntryCode,
                NULLIF(LTRIM(RTRIM(src.EntryLabel)), N'')      AS EntryLabel,
                NULLIF(LTRIM(RTRIM(src.ParentEntryId)), N'')   AS ParentEntryId,
                NULLIF(LTRIM(RTRIM(src.EntityType)), N'')      AS EntityType,
                NULLIF(LTRIM(RTRIM(src.CustomFieldId)), N'')   AS CustomFieldId,
                NULLIF(LTRIM(RTRIM(src.CustomFieldName)), N'') AS CustomFieldName,
                NULLIF(LTRIM(RTRIM(src.FieldType)), N'')       AS FieldType,
                NULLIF(LTRIM(RTRIM(src.SourceSystem)), N'')    AS SourceSystem,
                ROW_NUMBER() OVER (PARTITION BY LTRIM(RTRIM(src.LookupTableName)), LTRIM(RTRIM(src.EntryCode)) ORDER BY (SELECT NULL)) AS rn
            FROM stg.import_dictionary_lookup_entries src
            WHERE LTRIM(RTRIM(ISNULL(src.LookupTableName, N''))) <> N''
              AND LTRIM(RTRIM(ISNULL(src.EntryCode, N''))) <> N''
        ) AS dedup
        WHERE rn = 1
    ) AS S
        ON S.LookupTableName = T.LookupTableName
       AND S.EntryCode = T.EntryCode
    WHEN MATCHED THEN
        UPDATE SET
            T.LookupTableId = S.LookupTableId,
            T.EntryId       = S.EntryId,
            T.EntryLabel    = S.EntryLabel,
            T.ParentEntryId = S.ParentEntryId,
            T.EntityType    = S.EntityType,
            T.CustomFieldId = S.CustomFieldId,
            T.CustomFieldName = S.CustomFieldName,
            T.FieldType     = S.FieldType,
            T.SourceSystem  = S.SourceSystem,
            T.UpdatedOn     = sysdatetime(),
            T.UpdatedBy     = suser_sname()
    WHEN NOT MATCHED THEN
        INSERT (LookupTableId, LookupTableName, EntryId, EntryCode, EntryLabel, ParentEntryId,
                EntityType, CustomFieldId, CustomFieldName, FieldType, SourceSystem)
        VALUES (S.LookupTableId, S.LookupTableName, S.EntryId, S.EntryCode, S.EntryLabel,
                S.ParentEntryId, S.EntityType, S.CustomFieldId, S.CustomFieldName, S.FieldType, S.SourceSystem);

    EXEC log.usp_WriteScriptLog @RunId=@RunId,@ScriptName=@ScriptName,@ScriptVersion=N'V6-DRAFT',
        @Phase=N'CFG_LOOKUPS',@Severity=N'INFO',@Status=N'COMPLETED',
        @Message=N'cfg.dictionary_lookup_entries synchronise depuis stg.import_dictionary_lookup_entries.',
        @RowsAffected=@LookupCount;
END;

/* C3 : cfg.dictionary_projectdata_alias */
IF @AliasCount > 0
BEGIN
    MERGE cfg.dictionary_projectdata_alias AS T
    USING
    (
        SELECT
            LTRIM(RTRIM(src.Endpoint_EN))                          AS Endpoint_EN,
            NULLIF(LTRIM(RTRIM(src.Endpoint_FR)), N'')             AS Endpoint_FR,
            TRY_CONVERT(int, src.EndpointMatchCountRaw)            AS EndpointMatchCount,
            NULLIF(LTRIM(RTRIM(src.EndPointMatchStatus)), N'')     AS EndpointMatchStatus,
            TRY_CONVERT(int, src.PrimitiveColumnCount_ENRaw)       AS PrimitiveColumnCount_EN,
            TRY_CONVERT(int, src.PrimitiveColumnCount_FRRaw)       AS PrimitiveColumnCount_FR,
            TRY_CONVERT(int, src.ColumnPositionRaw)                AS ColumnPosition,
            LTRIM(RTRIM(src.Column_EN))                            AS Column_EN,
            NULLIF(LTRIM(RTRIM(src.Column_FR)), N'')               AS Column_FR,
            NULLIF(LTRIM(RTRIM(src.ColumnClassification)), N'')    AS ColumnClassification,
            NULLIF(LTRIM(RTRIM(src.Kind_EN)), N'')                 AS Kind_EN,
            NULLIF(LTRIM(RTRIM(src.TypeName_EN)), N'')             AS TypeName_EN,
            CASE
                WHEN UPPER(LTRIM(RTRIM(src.IsNullable_ENRaw))) IN (N'TRUE', N'1') THEN CONVERT(bit, 1)
                WHEN UPPER(LTRIM(RTRIM(src.IsNullable_ENRaw))) IN (N'FALSE', N'0') THEN CONVERT(bit, 0)
                ELSE NULL
            END                                                    AS IsNullable_EN,
            NULLIF(LTRIM(RTRIM(src.Kind_FR)), N'')                 AS Kind_FR,
            NULLIF(LTRIM(RTRIM(src.TypeName_FR)), N'')             AS TypeName_FR,
            CASE
                WHEN UPPER(LTRIM(RTRIM(src.IsNullable_FRRaw))) IN (N'TRUE', N'1') THEN CONVERT(bit, 1)
                WHEN UPPER(LTRIM(RTRIM(src.IsNullable_FRRaw))) IN (N'FALSE', N'0') THEN CONVERT(bit, 0)
                ELSE NULL
            END                                                    AS IsNullable_FR,
            CASE WHEN UPPER(LTRIM(RTRIM(src.PositionMatchRaw))) = N'TRUE' THEN CONVERT(bit,1) ELSE CONVERT(bit,0) END AS PositionMatch,
            CASE WHEN UPPER(LTRIM(RTRIM(src.TypeMatchRaw))) = N'TRUE' THEN CONVERT(bit,1) ELSE CONVERT(bit,0) END     AS TypeMatch,
            CASE WHEN UPPER(LTRIM(RTRIM(src.NullabilityMatchRaw))) = N'TRUE' THEN CONVERT(bit,1) ELSE CONVERT(bit,0) END AS NullabilityMatch,
            NULLIF(LTRIM(RTRIM(src.ColumnMatchStatus)), N'')       AS ColumnMatchStatus
        FROM stg.import_dictionary_projectdata_alias src
        WHERE LTRIM(RTRIM(ISNULL(src.Endpoint_EN, N''))) <> N''
          AND LTRIM(RTRIM(ISNULL(src.Column_EN, N''))) <> N''
    ) AS S
        ON S.Endpoint_EN = T.Endpoint_EN
       AND S.Column_EN = T.Column_EN
    WHEN MATCHED THEN
        UPDATE SET
            T.Endpoint_FR             = S.Endpoint_FR,
            T.EndpointMatchCount      = S.EndpointMatchCount,
            T.EndpointMatchStatus     = S.EndpointMatchStatus,
            T.PrimitiveColumnCount_EN = S.PrimitiveColumnCount_EN,
            T.PrimitiveColumnCount_FR = S.PrimitiveColumnCount_FR,
            T.ColumnPosition          = S.ColumnPosition,
            T.Column_FR               = S.Column_FR,
            T.ColumnClassification    = S.ColumnClassification,
            T.Kind_EN                 = S.Kind_EN,
            T.TypeName_EN             = S.TypeName_EN,
            T.IsNullable_EN           = S.IsNullable_EN,
            T.Kind_FR                 = S.Kind_FR,
            T.TypeName_FR             = S.TypeName_FR,
            T.IsNullable_FR           = S.IsNullable_FR,
            T.PositionMatch           = S.PositionMatch,
            T.TypeMatch               = S.TypeMatch,
            T.NullabilityMatch        = S.NullabilityMatch,
            T.ColumnMatchStatus       = S.ColumnMatchStatus,
            T.UpdatedOn               = sysdatetime(),
            T.UpdatedBy               = suser_sname()
    WHEN NOT MATCHED THEN
        INSERT (Endpoint_EN, Endpoint_FR, EndpointMatchCount, EndpointMatchStatus,
                PrimitiveColumnCount_EN, PrimitiveColumnCount_FR, ColumnPosition,
                Column_EN, Column_FR, ColumnClassification,
                Kind_EN, TypeName_EN, IsNullable_EN, Kind_FR, TypeName_FR, IsNullable_FR,
                PositionMatch, TypeMatch, NullabilityMatch, ColumnMatchStatus)
        VALUES (S.Endpoint_EN, S.Endpoint_FR, S.EndpointMatchCount, S.EndpointMatchStatus,
                S.PrimitiveColumnCount_EN, S.PrimitiveColumnCount_FR, S.ColumnPosition,
                S.Column_EN, S.Column_FR, S.ColumnClassification,
                S.Kind_EN, S.TypeName_EN, S.IsNullable_EN, S.Kind_FR, S.TypeName_FR, S.IsNullable_FR,
                S.PositionMatch, S.TypeMatch, S.NullabilityMatch, S.ColumnMatchStatus);

    /* Enrichir cfg.dictionary_od_fields.FieldName_EN depuis l'alias */
    UPDATE f
    SET
        f.EntityName_EN = a.Endpoint_EN,
        f.FieldName_EN  = a.Column_EN,
        f.UpdatedOn     = sysdatetime(),
        f.UpdatedBy     = suser_sname()
    FROM cfg.dictionary_od_fields f
    JOIN cfg.dictionary_projectdata_alias a
        ON a.Endpoint_FR = f.EntityName_FR
       AND a.Column_FR   = f.FieldName_FR
    WHERE f.FieldName_EN IS NULL
       OR f.EntityName_EN IS NULL;

    EXEC log.usp_WriteScriptLog @RunId=@RunId,@ScriptName=@ScriptName,@ScriptVersion=N'V6-DRAFT',
        @Phase=N'CFG_ALIAS',@Severity=N'INFO',@Status=N'COMPLETED',
        @Message=N'cfg.dictionary_projectdata_alias synchronise et cfg.dictionary_od_fields enrichi (EN/FR).',
        @RowsAffected=@AliasCount;
END;

/* ===========================================================================================
   PHASE D : CONSTRUCTION dic.Entity + dic.EntityColumnMap
   =========================================================================================== */

/* D1 : dic.Entity depuis cfg.dictionary_projectdata_alias */
MERGE dic.Entity AS T
USING
(
    SELECT
        Endpoint_EN,
        MAX(Endpoint_FR)                AS Endpoint_FR,
        MAX(EndpointMatchCount)         AS EndpointMatchCount,
        MAX(EndpointMatchStatus)        AS EndpointMatchStatus,
        MAX(PrimitiveColumnCount_EN)    AS PrimitiveColumnCount_EN,
        MAX(PrimitiveColumnCount_FR)    AS PrimitiveColumnCount_FR
    FROM cfg.dictionary_projectdata_alias
    WHERE ISNULL(Endpoint_EN, N'') <> N''
    GROUP BY Endpoint_EN
) AS S
    ON S.Endpoint_EN = T.EntityName_EN
WHEN MATCHED THEN
    UPDATE SET
        T.EntityName_FR         = S.Endpoint_FR,
        T.EndpointMatchCount    = S.EndpointMatchCount,
        T.EndpointMatchStatus   = S.EndpointMatchStatus,
        T.PrimitiveColumnCount_EN = S.PrimitiveColumnCount_EN,
        T.PrimitiveColumnCount_FR = S.PrimitiveColumnCount_FR,
        T.IsActive              = 1,
        T.UpdatedOn             = sysdatetime(),
        T.UpdatedBy             = suser_sname()
WHEN NOT MATCHED THEN
    INSERT (EntityName_EN, EntityName_FR, EndpointMatchCount, EndpointMatchStatus,
            PrimitiveColumnCount_EN, PrimitiveColumnCount_FR, IsActive)
    VALUES (S.Endpoint_EN, S.Endpoint_FR, S.EndpointMatchCount, S.EndpointMatchStatus,
            S.PrimitiveColumnCount_EN, S.PrimitiveColumnCount_FR, 1);

/* D2 : dic.EntityColumnMap depuis cfg.dictionary_projectdata_alias */
MERGE dic.EntityColumnMap AS T
USING
(
    SELECT
        Endpoint_EN         AS EntityName_EN,
        ISNULL(ColumnPosition, 0) AS ColumnPosition,
        Column_EN,
        Column_FR,
        ColumnClassification,
        Kind_EN,
        TypeName_EN,
        IsNullable_EN,
        Kind_FR,
        TypeName_FR,
        IsNullable_FR,
        ColumnMatchStatus
    FROM cfg.dictionary_projectdata_alias
    WHERE ISNULL(Endpoint_EN, N'') <> N''
      AND ISNULL(Column_EN, N'') <> N''
) AS S
    ON S.EntityName_EN = T.EntityName_EN
   AND S.Column_EN = T.Column_EN
WHEN MATCHED THEN
    UPDATE SET
        T.ColumnPosition        = S.ColumnPosition,
        T.Column_FR             = S.Column_FR,
        T.ColumnClassification  = S.ColumnClassification,
        T.Kind_EN               = S.Kind_EN,
        T.TypeName_EN           = S.TypeName_EN,
        T.IsNullable_EN         = S.IsNullable_EN,
        T.Kind_FR               = S.Kind_FR,
        T.TypeName_FR           = S.TypeName_FR,
        T.IsNullable_FR         = S.IsNullable_FR,
        T.ColumnMatchStatus     = S.ColumnMatchStatus,
        T.UpdatedOn             = sysdatetime(),
        T.UpdatedBy             = suser_sname()
WHEN NOT MATCHED THEN
    INSERT (EntityName_EN, ColumnPosition, Column_EN, Column_FR, ColumnClassification,
            Kind_EN, TypeName_EN, IsNullable_EN, Kind_FR, TypeName_FR, IsNullable_FR, ColumnMatchStatus)
    VALUES (S.EntityName_EN, S.ColumnPosition, S.Column_EN, S.Column_FR, S.ColumnClassification,
            S.Kind_EN, S.TypeName_EN, S.IsNullable_EN, S.Kind_FR, S.TypeName_FR, S.IsNullable_FR, S.ColumnMatchStatus);

EXEC log.usp_WriteScriptLog @RunId=@RunId,@ScriptName=@ScriptName,@ScriptVersion=N'V6-DRAFT',
    @Phase=N'DIC_ENTITY',@Severity=N'INFO',@Status=N'COMPLETED',
    @Message=N'dic.Entity et dic.EntityColumnMap synchronises depuis cfg.dictionary_projectdata_alias.';

/* ===========================================================================================
   PHASE E : dic.LookupMap depuis cfg.dictionary_lookup_entries
   =========================================================================================== */
IF @LookupCount > 0
BEGIN
    MERGE dic.LookupMap AS T
    USING
    (
        SELECT
            LookupTableId,
            LookupTableName,
            EntryId,
            EntryCode,
            EntryLabel,
            ParentEntryId,
            EntityType,
            CustomFieldId,
            CustomFieldName,
            FieldType,
            SourceSystem
        FROM cfg.dictionary_lookup_entries
        WHERE ISNULL(LookupTableName, N'') <> N''
          AND ISNULL(EntryCode, N'') <> N''
    ) AS S
        ON S.LookupTableName = T.LookupTableName
       AND S.EntryCode = T.EntryCode
    WHEN MATCHED THEN
        UPDATE SET
            T.LookupTableId  = S.LookupTableId,
            T.EntryId        = S.EntryId,
            T.EntryLabel     = S.EntryLabel,
            T.ParentEntryId  = S.ParentEntryId,
            T.EntityType     = S.EntityType,
            T.CustomFieldId  = S.CustomFieldId,
            T.CustomFieldName = S.CustomFieldName,
            T.FieldType      = S.FieldType,
            T.SourceSystem   = S.SourceSystem,
            T.UpdatedOn      = sysdatetime(),
            T.UpdatedBy      = suser_sname()
    WHEN NOT MATCHED THEN
        INSERT (LookupTableId, LookupTableName, EntryId, EntryCode, EntryLabel, ParentEntryId,
                EntityType, CustomFieldId, CustomFieldName, FieldType, SourceSystem)
        VALUES (S.LookupTableId, S.LookupTableName, S.EntryId, S.EntryCode, S.EntryLabel,
                S.ParentEntryId, S.EntityType, S.CustomFieldId, S.CustomFieldName, S.FieldType, S.SourceSystem);

    EXEC log.usp_WriteScriptLog @RunId=@RunId,@ScriptName=@ScriptName,@ScriptVersion=N'V6-DRAFT',
        @Phase=N'DIC_LOOKUP',@Severity=N'INFO',@Status=N'COMPLETED',
        @Message=N'dic.LookupMap synchronise depuis cfg.dictionary_lookup_entries.',
        @RowsAffected=@LookupCount;
END;

/* ===========================================================================================
   PHASE F : OData <-> PSSE MATCHING (stg.ODataPsseExactColumnMatch)
   Recherche les colonnes OData (PRIMITIVE) dans stg.ColumnInventory de la Content DB.
   =========================================================================================== */
TRUNCATE TABLE stg.ODataPsseExactColumnMatch;

/* Correspondances exactes : Column_EN trouve dans ColumnInventory */
INSERT INTO stg.ODataPsseExactColumnMatch
(
    RunId, EntityName_EN, Column_EN, Column_FR, ColumnClassification,
    PsseDatabaseName, PsseSchemaName, PsseObjectName, PsseColumnName,
    MatchType, ObjectMatchCount
)
SELECT
    @RunId,
    ecm.EntityName_EN,
    ecm.Column_EN,
    ecm.Column_FR,
    ecm.ColumnClassification,
    ci.SourceDatabaseName,
    ci.SourceSchemaName,
    ci.SourceObjectName,
    ci.ColumnName,
    N'EXACT',
    COUNT(ci.ColumnInventoryId) OVER (PARTITION BY ecm.Column_EN)
FROM dic.EntityColumnMap ecm
JOIN stg.ColumnInventory ci
    ON ci.ColumnName = ecm.Column_EN
   AND ci.PWAId = @PwaId
WHERE ecm.ColumnClassification = N'PRIMITIVE';

/* Colonnes OData sans correspondance dans PSSE */
INSERT INTO stg.ODataPsseExactColumnMatch
(
    RunId, EntityName_EN, Column_EN, Column_FR, ColumnClassification,
    PsseDatabaseName, PsseSchemaName, PsseObjectName, PsseColumnName,
    MatchType, ObjectMatchCount
)
SELECT
    @RunId,
    ecm.EntityName_EN,
    ecm.Column_EN,
    ecm.Column_FR,
    ecm.ColumnClassification,
    NULL, NULL, NULL, NULL,
    N'NO_MATCH',
    0
FROM dic.EntityColumnMap ecm
WHERE ecm.ColumnClassification = N'PRIMITIVE'
  AND NOT EXISTS
  (
      SELECT 1
      FROM stg.ColumnInventory ci
      WHERE ci.ColumnName = ecm.Column_EN
        AND ci.PWAId = @PwaId
  );

DECLARE @ExactCount int = (SELECT COUNT(*) FROM stg.ODataPsseExactColumnMatch WHERE RunId=@RunId AND MatchType=N'EXACT');
DECLARE @NoMatchCount int = (SELECT COUNT(*) FROM stg.ODataPsseExactColumnMatch WHERE RunId=@RunId AND MatchType=N'NO_MATCH');

SET @Msg = CONCAT(N'Matching OData/PSSE termine. EXACT=',@ExactCount,N'; NO_MATCH=',@NoMatchCount,N'.');
EXEC log.usp_WriteScriptLog @RunId=@RunId,@ScriptName=@ScriptName,@ScriptVersion=N'V6-DRAFT',
    @Phase=N'COLUMN_MATCH',@Severity=N'INFO',@Status=N'COMPLETED',
    @Message=@Msg,@RowsAffected=@ExactCount;

/* ===========================================================================================
   PHASE G : ENRICHISSEMENT dic.EntityColumnMap avec source PSSE dominante par entite
   Pour chaque (EntityName_EN, Column_EN), choisir le SourceObject le plus representatif.
   =========================================================================================== */
;WITH ranked_sources AS
(
    SELECT
        m.EntityName_EN,
        m.Column_EN,
        m.PsseSchemaName,
        m.PsseObjectName,
        m.PsseColumnName,
        obj_score.obj_col_count,
        ROW_NUMBER() OVER
        (
            PARTITION BY m.EntityName_EN, m.Column_EN
            ORDER BY obj_score.obj_col_count DESC, m.PsseObjectName
        ) AS rn
    FROM stg.ODataPsseExactColumnMatch m
    JOIN
    (
        SELECT EntityName_EN, PsseObjectName, COUNT(*) AS obj_col_count
        FROM stg.ODataPsseExactColumnMatch
        WHERE RunId = @RunId AND MatchType = N'EXACT'
        GROUP BY EntityName_EN, PsseObjectName
    ) AS obj_score
        ON obj_score.EntityName_EN = m.EntityName_EN
       AND obj_score.PsseObjectName = m.PsseObjectName
    WHERE m.RunId = @RunId
      AND m.MatchType = N'EXACT'
)
UPDATE ecm
SET
    ecm.PsseSourceSchema = rs.PsseSchemaName,
    ecm.PsseSourceObject = rs.PsseObjectName,
    ecm.PsseColumnName   = rs.PsseColumnName,
    ecm.PsseMatchScore   = 2,
    ecm.UpdatedOn        = sysdatetime(),
    ecm.UpdatedBy        = suser_sname()
FROM dic.EntityColumnMap ecm
JOIN ranked_sources rs
    ON rs.EntityName_EN = ecm.EntityName_EN
   AND rs.Column_EN = ecm.Column_EN
   AND rs.rn = 1;

/* Marquer les colonnes sans correspondance PSSE */
UPDATE dic.EntityColumnMap
SET
    PsseMatchScore = 0,
    UpdatedOn      = sysdatetime(),
    UpdatedBy      = suser_sname()
WHERE PsseMatchScore IS NULL
  AND ColumnClassification = N'PRIMITIVE';

/* ===========================================================================================
   PHASE H : SOURCE DRAFT PAR ENTITE (stg.EntitySource_Draft)
   Propose le meilleur objet PSSE pour servir de FROM principal par entite.
   =========================================================================================== */
TRUNCATE TABLE stg.EntitySource_Draft;

;WITH entity_object_score AS
(
    SELECT
        EntityName_EN,
        PsseSchemaName,
        PsseObjectName,
        COUNT(*) AS ColumnMatchCount
    FROM stg.ODataPsseExactColumnMatch
    WHERE RunId = @RunId
      AND MatchType = N'EXACT'
    GROUP BY EntityName_EN, PsseSchemaName, PsseObjectName
),
entity_totals AS
(
    SELECT EntityName_EN, COUNT(*) AS TotalPrimitiveCols
    FROM dic.EntityColumnMap
    WHERE ColumnClassification = N'PRIMITIVE'
    GROUP BY EntityName_EN
),
ranked AS
(
    SELECT
        eos.EntityName_EN,
        eos.PsseSchemaName,
        eos.PsseObjectName,
        eos.ColumnMatchCount,
        et.TotalPrimitiveCols,
        CASE WHEN et.TotalPrimitiveCols > 0
             THEN CAST(eos.ColumnMatchCount AS decimal(10,2)) / et.TotalPrimitiveCols * 100
             ELSE 0
        END AS CoverageScore,
        ROW_NUMBER() OVER
        (
            PARTITION BY eos.EntityName_EN
            ORDER BY eos.ColumnMatchCount DESC, eos.PsseObjectName
        ) AS rn
    FROM entity_object_score eos
    JOIN entity_totals et ON et.EntityName_EN = eos.EntityName_EN
)
INSERT INTO stg.EntitySource_Draft
(
    RunId, EntityName_EN, ProposedSchema, ProposedObject,
    ColumnMatchCount, TotalPrimitiveCols, CoverageScore, ConfidenceLevel
)
SELECT
    @RunId,
    EntityName_EN,
    PsseSchemaName,
    PsseObjectName,
    ColumnMatchCount,
    TotalPrimitiveCols,
    ROUND(CoverageScore, 2),
    CASE
        WHEN CoverageScore >= 80 THEN N'HIGH'
        WHEN CoverageScore >= 50 THEN N'MEDIUM'
        ELSE N'LOW'
    END
FROM ranked
WHERE rn = 1;

/* Entites sans aucun match PSSE */
INSERT INTO stg.EntitySource_Draft (RunId, EntityName_EN, ColumnMatchCount, TotalPrimitiveCols, CoverageScore, ConfidenceLevel, Notes)
SELECT
    @RunId,
    e.EntityName_EN,
    0,
    ISNULL(et.TotalPrimitiveCols, 0),
    0,
    N'NONE',
    N'Aucune colonne primitive trouvee dans stg.ColumnInventory.'
FROM dic.Entity e
LEFT JOIN stg.EntitySource_Draft esd ON esd.EntityName_EN = e.EntityName_EN AND esd.RunId = @RunId
LEFT JOIN (SELECT EntityName_EN, COUNT(*) AS TotalPrimitiveCols FROM dic.EntityColumnMap WHERE ColumnClassification='PRIMITIVE' GROUP BY EntityName_EN) et
    ON et.EntityName_EN = e.EntityName_EN
WHERE esd.EntitySourceDraftId IS NULL;

EXEC log.usp_WriteScriptLog @RunId=@RunId,@ScriptName=@ScriptName,@ScriptVersion=N'V6-DRAFT',
    @Phase=N'SOURCE_DRAFT',@Severity=N'INFO',@Status=N'COMPLETED',
    @Message=N'stg.EntitySource_Draft alimentee. Utiliser SELECT * FROM stg.EntitySource_Draft pour revue.';

/* ===========================================================================================
   PHASE I : RAPPORT DE QUALITE (stg.DictionaryQualityIssue)
   =========================================================================================== */
TRUNCATE TABLE stg.DictionaryQualityIssue;

/* I1 : Colonnes OData sans correspondance PSSE */
INSERT INTO stg.DictionaryQualityIssue (RunId, IssueSeverity, IssueCode, EntityName_EN, ColumnName, IssueMessage)
SELECT
    @RunId,
    N'WARN',
    N'PSSE_COL_MISSING',
    EntityName_EN,
    Column_EN,
    CONCAT(N'Colonne OData [', EntityName_EN, N'].', Column_EN, N' non trouvee dans stg.ColumnInventory (', @ContentDbName, N').')
FROM stg.ODataPsseExactColumnMatch
WHERE RunId = @RunId
  AND MatchType = N'NO_MATCH';

/* I2 : Entites sans source PSSE proposee */
INSERT INTO stg.DictionaryQualityIssue (RunId, IssueSeverity, IssueCode, EntityName_EN, ColumnName, IssueMessage)
SELECT
    @RunId,
    N'WARN',
    N'ENTITY_NO_SOURCE',
    esd.EntityName_EN,
    NULL,
    CONCAT(N'Entite [', esd.EntityName_EN, N'] : aucun objet PSSE proposeAvec score suffisant (CoverageScore=', ISNULL(CAST(esd.CoverageScore AS nvarchar(10)), N'NULL'), N'%).')
FROM stg.EntitySource_Draft esd
WHERE RunId = @RunId
  AND ConfidenceLevel IN (N'LOW', N'NONE');

/* I3 : Entites dans Fields CSV sans correspondance dans alias */
INSERT INTO stg.DictionaryQualityIssue (RunId, IssueSeverity, IssueCode, EntityName_EN, ColumnName, IssueMessage)
SELECT DISTINCT
    @RunId,
    N'INFO',
    N'FR_ENTITY_NO_ALIAS',
    f.EntityName_FR,
    NULL,
    CONCAT(N'Entite FR [', f.EntityName_FR, N'] du fichier Fields_ProjectData_Export.csv sans correspondance EN dans l''alias.')
FROM cfg.dictionary_od_fields f
WHERE f.EntityName_EN IS NULL;

/* I4 : Colonnes FR sans correspondance EN */
INSERT INTO stg.DictionaryQualityIssue (RunId, IssueSeverity, IssueCode, EntityName_EN, ColumnName, IssueMessage)
SELECT
    @RunId,
    N'INFO',
    N'FR_FIELD_NO_ALIAS',
    f.EntityName_FR,
    f.FieldName_FR,
    CONCAT(N'Champ FR [', f.EntityName_FR, N'].', f.FieldName_FR, N' sans correspondance EN dans l''alias.')
FROM cfg.dictionary_od_fields f
WHERE f.FieldName_EN IS NULL;

DECLARE @QualityErrorCount int   = (SELECT COUNT(*) FROM stg.DictionaryQualityIssue WHERE RunId=@RunId AND IssueSeverity=N'ERROR');
DECLARE @QualityWarnCount  int   = (SELECT COUNT(*) FROM stg.DictionaryQualityIssue WHERE RunId=@RunId AND IssueSeverity=N'WARN');
DECLARE @QualityInfoCount  int   = (SELECT COUNT(*) FROM stg.DictionaryQualityIssue WHERE RunId=@RunId AND IssueSeverity=N'INFO');

DECLARE @QualityRowsAffected int = @QualityErrorCount + @QualityWarnCount;
SET @Msg = CONCAT(N'Rapport qualite: ERROR=',@QualityErrorCount,N'; WARN=',@QualityWarnCount,N'; INFO=',@QualityInfoCount,N'.');
EXEC log.usp_WriteScriptLog @RunId=@RunId,@ScriptName=@ScriptName,@ScriptVersion=N'V6-DRAFT',
    @Phase=N'QUALITY',@Severity=N'INFO',@Status=N'COMPLETED',
    @Message=@Msg,@RowsAffected=@QualityRowsAffected;

/* ===========================================================================================
   PHASE J : RAPPORT FINAL
   =========================================================================================== */
DECLARE @EntityCount        int = (SELECT COUNT(*) FROM dic.Entity);
DECLARE @ColumnMapCount     int = (SELECT COUNT(*) FROM dic.EntityColumnMap);
DECLARE @PrimCount          int = (SELECT COUNT(*) FROM dic.EntityColumnMap WHERE ColumnClassification=N'PRIMITIVE');
DECLARE @LookupMapCount     int = (SELECT COUNT(*) FROM dic.LookupMap);
DECLARE @LookupTableCount   int = (SELECT COUNT(DISTINCT LookupTableName) FROM dic.LookupMap);
DECLARE @OdFieldsNorm       int = (SELECT COUNT(*) FROM cfg.dictionary_od_fields);
DECLARE @AliasNorm          int = (SELECT COUNT(*) FROM cfg.dictionary_projectdata_alias);
DECLARE @SourceHighCount    int = (SELECT COUNT(*) FROM stg.EntitySource_Draft WHERE RunId=@RunId AND ConfidenceLevel=N'HIGH');

SET @Msg = CONCAT(
    N'Pipeline dictionnaire V6 termine. ',
    N'dic.Entity=', @EntityCount,
    N'; dic.EntityColumnMap=', @ColumnMapCount, N' (PRIMITIVE=', @PrimCount, N')',
    N'; dic.LookupMap=', @LookupMapCount, N' entrees / ', @LookupTableCount, N' tables',
    N'; cfg.dictionary_od_fields=', @OdFieldsNorm,
    N'; cfg.dictionary_projectdata_alias=', @AliasNorm,
    N'; PSSE_EXACT=', @ExactCount, N'; PSSE_NO_MATCH=', @NoMatchCount,
    N'; Sources HIGH=', @SourceHighCount,
    N'; Qualite WARN=', @QualityWarnCount, N'; INFO=', @QualityInfoCount
);

EXEC log.usp_WriteScriptLog @RunId=@RunId,@ScriptName=@ScriptName,@ScriptVersion=N'V6-DRAFT',
    @Phase=N'COMPLETED',@Severity=N'INFO',@Status=N'COMPLETED',@Message=@Msg;

/* Rapport console pour le DBA */
SELECT N'dic.Entity'                AS TableName, @EntityCount       AS Cnt UNION ALL
SELECT N'dic.EntityColumnMap',                    @ColumnMapCount              UNION ALL
SELECT N'dic.EntityColumnMap (PRIMITIVE)',         @PrimCount                   UNION ALL
SELECT N'dic.LookupMap',                          @LookupMapCount              UNION ALL
SELECT N'cfg.dictionary_od_fields',               @OdFieldsNorm                UNION ALL
SELECT N'cfg.dictionary_projectdata_alias',        @AliasNorm                   UNION ALL
SELECT N'stg.ODataPsseExactColumnMatch (EXACT)',  @ExactCount                  UNION ALL
SELECT N'stg.ODataPsseExactColumnMatch (NOMATCH)', @NoMatchCount               UNION ALL
SELECT N'stg.EntitySource_Draft (HIGH)',           @SourceHighCount             UNION ALL
SELECT N'stg.DictionaryQualityIssue (WARN)',       @QualityWarnCount            UNION ALL
SELECT N'stg.DictionaryQualityIssue (INFO)',       @QualityInfoCount;

/* Top 10 entites par couverture PSSE */
SELECT TOP 10
    EntityName_EN,
    ProposedSchema,
    ProposedObject,
    ColumnMatchCount,
    TotalPrimitiveCols,
    CoverageScore,
    ConfidenceLevel
FROM stg.EntitySource_Draft
WHERE RunId = @RunId
ORDER BY CoverageScore DESC;

/* Issues bloquantes (WARN non resolus) */
SELECT TOP 20
    IssueSeverity,
    IssueCode,
    EntityName_EN,
    ColumnName,
    IssueMessage
FROM stg.DictionaryQualityIssue
WHERE RunId = @RunId
  AND IssueSeverity IN (N'ERROR', N'WARN')
ORDER BY IssueSeverity, EntityName_EN, ColumnName;
GO
