/*=====================================================================================================================
    v6_02a_Attach_Existing_SmartBox_Database.sql
    Projet      : SmartBox
    Phase       : 02a - Attacher SmartBox a une base existante
    Role        : Créer la configuration minimale V6 sans créer ni déplacer la base.

    Notes V6
    - Remplace la portion applicative de v5_02a.
    - Ne contient aucun CREATE DATABASE, ALTER DATABASE fichier, xp_cmdshell ou accès NTFS.
    - Créé la table de log dans le schema log.
    - Paramètres déclaratifs dans le bloc PARAMETRES CLIENT (CTRL+F)     
=====================================================================================================================*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb')
BEGIN
    THROW 62001, N'Exécuter ce script dans la base SmartBox cible existante.', 1;
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'cfg')
    EXEC(N'CREATE SCHEMA cfg AUTHORIZATION dbo;');

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'log')
    EXEC(N'CREATE SCHEMA log AUTHORIZATION dbo;');

IF OBJECT_ID(N'cfg.Settings', N'U') IS NULL
BEGIN
    CREATE TABLE cfg.Settings
    (
        SettingKey      sysname         NOT NULL,
        SettingValue    nvarchar(4000)  NOT NULL,
        SettingGroup    nvarchar(60)    NOT NULL CONSTRAINT DF_cfg_Settings_SettingGroup DEFAULT(N'GENERAL'),
        SettingType     nvarchar(60)    NOT NULL CONSTRAINT DF_cfg_Settings_SettingType DEFAULT(N'nvarchar'),
        IsRequired      bit             NOT NULL CONSTRAINT DF_cfg_Settings_IsRequired DEFAULT(0),
        IsSecret        bit             NOT NULL CONSTRAINT DF_cfg_Settings_IsSecret DEFAULT(0),
        IsDeprecated    bit             NOT NULL CONSTRAINT DF_cfg_Settings_IsDeprecated DEFAULT(0),
        Description     nvarchar(4000)  NULL,
        UpdatedOn       datetime2(0)    NOT NULL CONSTRAINT DF_cfg_Settings_UpdatedOn DEFAULT(sysdatetime()),
        UpdatedBy       sysname         NOT NULL CONSTRAINT DF_cfg_Settings_UpdatedBy DEFAULT(suser_sname()),
        CONSTRAINT PK_cfg_Settings PRIMARY KEY (SettingKey)
    );
END;

IF COL_LENGTH(N'cfg.Settings', N'SettingGroup') IS NULL
    ALTER TABLE cfg.Settings ADD SettingGroup nvarchar(60) NOT NULL CONSTRAINT DF_cfg_Settings_SettingGroup DEFAULT(N'GENERAL');

IF COL_LENGTH(N'cfg.Settings', N'SettingType') IS NULL
    ALTER TABLE cfg.Settings ADD SettingType nvarchar(60) NOT NULL CONSTRAINT DF_cfg_Settings_SettingType DEFAULT(N'nvarchar');

IF COL_LENGTH(N'cfg.Settings', N'IsRequired') IS NULL
    ALTER TABLE cfg.Settings ADD IsRequired bit NOT NULL CONSTRAINT DF_cfg_Settings_IsRequired DEFAULT(0);

IF COL_LENGTH(N'cfg.Settings', N'IsSecret') IS NULL
    ALTER TABLE cfg.Settings ADD IsSecret bit NOT NULL CONSTRAINT DF_cfg_Settings_IsSecret DEFAULT(0);

IF COL_LENGTH(N'cfg.Settings', N'IsDeprecated') IS NULL
    ALTER TABLE cfg.Settings ADD IsDeprecated bit NOT NULL CONSTRAINT DF_cfg_Settings_IsDeprecated DEFAULT(0);

IF OBJECT_ID(N'cfg.PWA', N'U') IS NULL
BEGIN
    CREATE TABLE cfg.PWA
    (
        PWAId               int             NOT NULL CONSTRAINT DF_cfg_PWA_PWAId DEFAULT(1),
        ContentDatabaseName sysname         NOT NULL,
        Notes               nvarchar(4000)  NULL,
        Language            nvarchar(10)    NULL,
        UpdatedOn           datetime2(0)    NOT NULL CONSTRAINT DF_cfg_PWA_UpdatedOn DEFAULT(sysdatetime()),
        UpdatedBy           sysname         NOT NULL CONSTRAINT DF_cfg_PWA_UpdatedBy DEFAULT(suser_sname()),
        CONSTRAINT PK_cfg_PWA PRIMARY KEY (PWAId),
        CONSTRAINT CK_cfg_PWA_OnlyOne CHECK (PWAId = 1)
    );
END;

IF COL_LENGTH(N'cfg.PWA', N'Language') IS NULL
    ALTER TABLE cfg.PWA ADD Language nvarchar(10) NULL;

IF OBJECT_ID(N'cfg.PwaSchemaScope', N'U') IS NULL
BEGIN
    CREATE TABLE cfg.PwaSchemaScope
    (
        PWAId       int          NOT NULL,
        SchemaName  sysname      NOT NULL,
        UpdatedOn   datetime2(0) NOT NULL CONSTRAINT DF_cfg_PwaSchemaScope_UpdatedOn DEFAULT(sysdatetime()),
        UpdatedBy   sysname      NOT NULL CONSTRAINT DF_cfg_PwaSchemaScope_UpdatedBy DEFAULT(suser_sname()),
        CONSTRAINT PK_cfg_PwaSchemaScope PRIMARY KEY (PWAId, SchemaName),
        CONSTRAINT FK_cfg_PwaSchemaScope_PWA FOREIGN KEY (PWAId) REFERENCES cfg.PWA(PWAId)
    );
END;

IF OBJECT_ID(N'log.ScriptExecutionLog', N'U') IS NULL
BEGIN
    CREATE TABLE log.ScriptExecutionLog
    (
        ExecutionLogId bigint IDENTITY(1,1) NOT NULL,
        RunId uniqueidentifier NOT NULL CONSTRAINT DF_log_ScriptExecutionLog_RunId DEFAULT(newid()),
        ScriptName sysname NOT NULL,
        ScriptVersion nvarchar(30) NULL,
        Phase nvarchar(100) NOT NULL,
        Severity nvarchar(20) NOT NULL CONSTRAINT DF_log_ScriptExecutionLog_Severity DEFAULT(N'INFO'),
        Status nvarchar(30) NOT NULL CONSTRAINT DF_log_ScriptExecutionLog_Status DEFAULT(N'INFO'),
        Message nvarchar(max) NULL,
        RowsAffected bigint NULL,
        ErrorNumber int NULL,
        ErrorLine int NULL,
        ErrorProcedure sysname NULL,
        ErrorMessage nvarchar(4000) NULL,
        DatabaseName sysname NOT NULL CONSTRAINT DF_log_ScriptExecutionLog_DatabaseName DEFAULT(DB_NAME()),
        HostName sysname NULL CONSTRAINT DF_log_ScriptExecutionLog_HostName DEFAULT(HOST_NAME()),
        AppName nvarchar(128) NULL CONSTRAINT DF_log_ScriptExecutionLog_AppName DEFAULT(APP_NAME()),
        LoginName sysname NOT NULL CONSTRAINT DF_log_ScriptExecutionLog_LoginName DEFAULT(suser_sname()),
        LoggedAt datetime2(0) NOT NULL CONSTRAINT DF_log_ScriptExecutionLog_LoggedAt DEFAULT(sysdatetime()),
        CONSTRAINT PK_log_ScriptExecutionLog PRIMARY KEY (ExecutionLogId)
    );

    CREATE INDEX IX_log_ScriptExecutionLog_Run ON log.ScriptExecutionLog (RunId, ExecutionLogId);
    CREATE INDEX IX_log_ScriptExecutionLog_Script_Phase ON log.ScriptExecutionLog (ScriptName, Phase, LoggedAt);
    CREATE INDEX IX_log_ScriptExecutionLog_Status ON log.ScriptExecutionLog (Status, Severity, LoggedAt);
END;
GO

CREATE OR ALTER PROCEDURE log.usp_WriteScriptLog
    @RunId uniqueidentifier = NULL,
    @ScriptName sysname,
    @ScriptVersion nvarchar(30) = NULL,
    @Phase nvarchar(100),
    @Severity nvarchar(20) = N'INFO',
    @Status nvarchar(30) = N'INFO',
    @Message nvarchar(max) = NULL,
    @RowsAffected bigint = NULL,
    @ErrorNumber int = NULL,
    @ErrorLine int = NULL,
    @ErrorProcedure sysname = NULL,
    @ErrorMessage nvarchar(4000) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO log.ScriptExecutionLog
    (
        RunId, ScriptName, ScriptVersion, Phase, Severity, Status, Message,
        RowsAffected, ErrorNumber, ErrorLine, ErrorProcedure, ErrorMessage
    )
    VALUES
    (
        ISNULL(@RunId, newid()), @ScriptName, @ScriptVersion, @Phase,
        ISNULL(@Severity, N'INFO'), ISNULL(@Status, N'INFO'), @Message,
        @RowsAffected, @ErrorNumber, @ErrorLine, @ErrorProcedure, @ErrorMessage
    );
END;
GO

/*=====================================================================================================================
    PARAMETRES CLIENT - SECTION A MODIFIER PAR LE DBA

    Pour adapter ce script a un autre client/environnement, modifiér les valeurs ci-dessous seulement.
    Le reste du script lit ces variables et alimente cfg.Settings, cfg.PWA et cfg.PwaSchemaScope.

    Valeurs MTMD confirmees pour ce déploiement:
      - Base SmartBox cible        : SPR, soit la base dans laquelle ce script est exécuté.
      - BD contenu PWA source      : SP_SPR_POC_Contenu.
      - Compte de déploiement vise : MTQ\franbreton.
=====================================================================================================================*/
DECLARE @ClientName nvarchar(128) = N'MTMD';                     -- Nom du client ou ministere.
DECLARE @EnvironmentName nvarchar(30) = N'PROD';                 -- DEV, TEST, QA, PROD, etc.
DECLARE @ExpectedDeploymentLogin sysname = N'MTQ\franbreton';    -- Mettre NULL pour ne pas produire d'avertissement de login.
DECLARE @DesignDatabaseName sysname = N'SPR';                    -- Nom attendu de la base SmartBox cible.
DECLARE @ContentDbName sysname = N'SP_SPR_POC_Contenu';          -- Nom de la BD contenu PWA source du client.
DECLARE @PwaId int = 1;                                          -- V6 supporte une PWA active dans cette trousse.
DECLARE @PwaLanguage nvarchar(10) = N'FR';                       -- Langue principale: FR ou EN.
DECLARE @ProjectSchemasCsv nvarchar(200) = N'pjrep,pjpub';       -- Schémas natifs PSSE a inventorier.

/* Paramètres de comportement V6 - modifiér seulement si le mode de déploiement change. */
DECLARE @ViewDefinitionMode nvarchar(40) = N'FROZEN_SNAPSHOT';
DECLARE @FrozenViewSnapshotName nvarchar(260) = N'v6_04a_Frozen_SP_SPR_POC_Contenu_Internal_Views.sql';
DECLARE @ExcludePsseContentCustomFields bit = 1;                 -- 1 = ne pas publier les champs personnalisés du content PSSE.
DECLARE @LoadMode nvarchar(40) = N'STG_IMPORT_TABLES';           -- Les imports dictionnaire passent par stg.import_*.
DECLARE @Day1LoadSourceMode nvarchar(30) = N'TOOL';              -- TOOL ou DBA_CSV pour le chargement initial vers stg.import_*.
DECLARE @AllowCsvDay1Import nvarchar(20) = N'OPTIONAL';          -- CSV permis seulement au jour 1 si le DBA le choisit.
DECLARE @ReviewMode nvarchar(30) = N'TABLES';                    -- Les corrections passent par review.*.
DECLARE @ReportMode nvarchar(30) = N'TABLES';                    -- Les rapports sont persistés dans report.*.

/*=====================================================================================================================
    VARIABLES TECHNIQUES - NE PAS MODIFIER
=====================================================================================================================*/
DECLARE @RunId uniqueidentifier = newid();
DECLARE @ScriptName sysname = N'v6_02a_Attach_Existing_SmartBox_Database.sql';
DECLARE @ToolboxDbName sysname;
DECLARE @ActualDeploymentLogin sysname = suser_sname();
DECLARE @LoginWarning nvarchar(4000);

IF @ExpectedDeploymentLogin IS NOT NULL AND @ActualDeploymentLogin <> @ExpectedDeploymentLogin
BEGIN
    SET @LoginWarning = CONCAT(N'Login courant ', @ActualDeploymentLogin, N' different du login attendu ', @ExpectedDeploymentLogin, N'. A valider avec le DBA.');
END;

EXEC log.usp_WriteScriptLog
    @RunId = @RunId,
    @ScriptName = @ScriptName,
    @ScriptVersion = N'V6-DRAFT',
    @Phase = N'START',
    @Severity = N'INFO',
    @Status = N'STARTED',
    @Message = N'Début attachement SmartBox V6 a une base existante.';

IF @LoginWarning IS NOT NULL
BEGIN
    EXEC log.usp_WriteScriptLog
        @RunId = @RunId,
        @ScriptName = @ScriptName,
        @ScriptVersion = N'V6-DRAFT',
        @Phase = N'PARAMETERS',
        @Severity = N'WARN',
        @Status = N'WARNING',
        @Message = @LoginWarning;
END;

MERGE cfg.Settings AS T
USING
(
    SELECT N'PackageVersion' AS SettingKey, N'V6-DRAFT' AS SettingValue, N'IDENTITY' AS SettingGroup, N'nvarchar(30)' AS SettingType, CONVERT(bit, 1) AS IsRequired, CONVERT(bit, 0) AS IsSecret, CONVERT(bit, 0) AS IsDeprecated, N'Version logique de la trousse appliquee.' AS Description
    UNION ALL SELECT N'ToolboxDbName', CONVERT(nvarchar(4000), DB_NAME()), N'IDENTITY', N'sysname', 1, 0, 0, N'Nom de la base SmartBox cible existante. Pour la conception courante: SPR.'
    UNION ALL SELECT N'DesignDatabaseName', CONVERT(nvarchar(4000), @DesignDatabaseName), N'IDENTITY', N'sysname', 1, 0, 0, N'Base de conception SmartBox V6.'
    UNION ALL SELECT N'EnvironmentName', CONVERT(nvarchar(4000), @EnvironmentName), N'IDENTITY', N'nvarchar(30)', 0, 0, 0, N'Nom logique de l''environnement.'
    UNION ALL SELECT N'DeploymentMode', N'EXISTING_DATABASE', N'IDENTITY', N'nvarchar(40)', 1, 0, 0, N'La base existe déjà; la trousse applicative ne créé pas la base.'
    UNION ALL SELECT N'ClientName', CONVERT(nvarchar(4000), @ClientName), N'IDENTITY', N'nvarchar(128)', 0, 0, 0, N'Client ou contexte de déploiement.'
    UNION ALL SELECT N'ExpectedDeploymentLogin', ISNULL(CONVERT(nvarchar(4000), @ExpectedDeploymentLogin), N''), N'SECURITY', N'sysname_nullable', 0, 0, 0, N'Login Windows/SQL attendu pour le déploiement. Vide = validation non bloquante.'
    UNION ALL SELECT N'ContentDbName', CONVERT(nvarchar(4000), @ContentDbName), N'PWA', N'sysname', 1, 0, 0, N'Content DB PSSE native source.'
    UNION ALL SELECT N'PwaId', CONVERT(nvarchar(4000), @PwaId), N'PWA', N'int', 1, 0, 0, N'Identifiant PWA logique. La trousse courante supporte une PWA active.'
    UNION ALL SELECT N'PwaLanguage', CONVERT(nvarchar(4000), @PwaLanguage), N'PWA', N'nvarchar(10)', 1, 0, 0, N'Langue principale de publication.'
    UNION ALL SELECT N'ProjectSchemasCsv', CONVERT(nvarchar(4000), @ProjectSchemasCsv), N'PWA', N'csv(sysname)', 1, 0, 0, N'Schémas PSSE sources séparés par virgule.'
    UNION ALL SELECT N'LoadMode', CONVERT(nvarchar(4000), @LoadMode), N'MODE', N'nvarchar(40)', 1, 0, 0, N'Mode V6: les imports dictionnaire transitent par stg.import_dictionary_*.'
    UNION ALL SELECT N'AllowCsvDay1Import', CONVERT(nvarchar(4000), @AllowCsvDay1Import), N'MODE', N'nvarchar(20)', 0, 0, 0, N'Autorise un chargement CSV initial par DBA vers stg.import_dictionary_*, hors pipeline courant.'
    UNION ALL SELECT N'Day1LoadSourceMode', CONVERT(nvarchar(4000), @Day1LoadSourceMode), N'LOAD', N'nvarchar(30)', 0, 0, 0, N'Source attendue pour les tables stg.import_dictionary_*: TOOL ou DBA_CSV.'
    UNION ALL SELECT N'ActiveLoadBatchId', N'', N'LOAD', N'bigint_nullable', 0, 0, 1, N'Legacy V5/V6 initial: lot load.* à consommer. Non utilisé dans la filière stg.import_dictionary_*.'
    UNION ALL SELECT N'RequireLoadBatchValidation', N'1', N'LOAD', N'bit', 1, 0, 1, N'Legacy V5/V6 initial: validation du lot load.*. Non utilisé dans la filière stg.import_dictionary_*.'
    UNION ALL SELECT N'ReviewMode', CONVERT(nvarchar(4000), @ReviewMode), N'MODE', N'nvarchar(30)', 1, 0, 0, N'Les corrections passent par review.*, pas par CSV.'
    UNION ALL SELECT N'ReportMode', CONVERT(nvarchar(4000), @ReportMode), N'MODE', N'nvarchar(30)', 1, 0, 0, N'Les rapports sont persistés dans report.*.'
    UNION ALL SELECT N'LogMode', N'LOG_SCHEMA', N'MODE', N'nvarchar(30)', 1, 0, 0, N'Les logs sont écrits dans log.ScriptExecutionLog.'
    UNION ALL SELECT N'ViewGenerationMode', N'NATIVE_STACKS', N'MODE', N'nvarchar(40)', 1, 0, 0, N'Generation principale via les piles natives.'
    UNION ALL SELECT N'ViewDefinitionMode', CONVERT(nvarchar(4000), @ViewDefinitionMode), N'VIEW', N'nvarchar(40)', 1, 0, 0, N'Definitions de vues figees dans la trousse V6; pas de dépendance runtime a SP_SPR_POC_Contenu.'
    UNION ALL SELECT N'FrozenViewSnapshotName', CONVERT(nvarchar(4000), @FrozenViewSnapshotName), N'VIEW', N'nvarchar(260)', 1, 0, 0, N'Fichier snapshot contenant les définitions internes tbx/tbx_fr/tbx_master.'
    UNION ALL SELECT N'ExcludePsseContentCustomFields', CONVERT(nvarchar(4000), @ExcludePsseContentCustomFields), N'VIEW', N'bit', 1, 0, 0, N'Les champs personnalisés provenant de la BD content PSSE ne sont pas publies dans ProjectData.'
    UNION ALL SELECT N'ReferenceViewDbName', N'SP_SPR_POC_Contenu', N'VIEW', N'sysname', 0, 0, 1, N'Ancienne base de reference utilisée pour générer le snapshot; non requise au runtime V6.'
    UNION ALL SELECT N'CsvExportMode', N'DISABLED', N'MODE', N'nvarchar(20)', 1, 0, 0, N'Exports CSV depuis SQL Server desactives.'
    UNION ALL SELECT N'UseXpCmdShell', N'0', N'SECURITY', N'bit', 1, 0, 0, N'xp_cmdshell non requis par la trousse applicative V6.'
    UNION ALL SELECT N'RequireExistingDatabase', N'1', N'SECURITY', N'bit', 1, 0, 0, N'La base cible doit exister avant la trousse applicative.'
    UNION ALL SELECT N'AllowCreateDatabase', N'0', N'SECURITY', N'bit', 1, 0, 0, N'La trousse applicative ne créé pas de base.'
    UNION ALL SELECT N'AllowMoveDatabaseFiles', N'0', N'SECURITY', N'bit', 1, 0, 0, N'La trousse applicative ne déplace pas les fichiers MDF/LDF.'
    UNION ALL SELECT N'AllowFileSystemAccèss', N'0', N'SECURITY', N'bit', 1, 0, 0, N'La trousse applicative ne depend pas du systeme de fichiers.'
    UNION ALL SELECT N'DefaultRunFailPolicy', N'STOP_ON_ERROR', N'VALIDATION', N'nvarchar(40)', 1, 0, 0, N'Comportement standard en cas d''erreur bloquante.'
    UNION ALL SELECT N'ValidationLookbackDays', N'3', N'VALIDATION', N'int', 0, 0, 0, N'Fenêtre de rapport des erreurs recentes.'
    UNION ALL SELECT N'MaxBlockingErrorsToReport', N'500', N'VALIDATION', N'int', 0, 0, 0, N'Nombre maximal d''erreurs bloquantes a rapporter.'
    UNION ALL SELECT N'IncludeWarningsInBlockingReport', N'0', N'VALIDATION', N'bit', 0, 0, 0, N'Inclure les avertissements dans le rapport bloquant.'
    UNION ALL SELECT N'PersistReports', N'1', N'VALIDATION', N'bit', 1, 0, 0, N'Persister les rapports dans report.*.'
    UNION ALL SELECT N'SmartBoxSourcePath', N'', N'LEGACY', N'nvarchar(4000)', 0, 0, 1, N'Legacy V5: chemin CSV source. Non requis par V6 normal.'
    UNION ALL SELECT N'SmartBoxValueImportPath', N'', N'LEGACY', N'nvarchar(4000)', 0, 0, 1, N'Legacy V5: chemin CSV de correction. Remplace par review.*.'
    UNION ALL SELECT N'SmartBoxImportPath', N'', N'LEGACY', N'nvarchar(4000)', 0, 0, 1, N'Legacy V5: alias de chemin import. Non requis par V6 normal.'
    UNION ALL SELECT N'SmartBoxErrorPath', N'', N'LEGACY', N'nvarchar(4000)', 0, 0, 1, N'Legacy V5: chemin des exports. Remplace par log.* et report.*.'
    UNION ALL SELECT N'DictionarySourcePath', N'', N'LOAD', N'nvarchar(4000)', 0, 0, 0, N'Chemin local (client) contenant les fichiers CSV du dictionnaire pour chargement SqlBulkCopy.'
    UNION ALL SELECT N'DictionaryFile_ProjectData', N'Fields_ProjectData_Export.csv', N'LOAD', N'nvarchar(260)', 0, 0, 0, N'Nom du fichier CSV export OData ProjectData. Charge dans stg.import_dictionary_od_fields.'
    UNION ALL SELECT N'DictionaryFile_Lookups', N'Lookups_ProjectServer_Export.csv', N'LOAD', N'nvarchar(260)', 0, 0, 0, N'Nom du fichier CSV export lookups. Charge dans stg.import_dictionary_lookup_entries.'
    UNION ALL SELECT N'DictionaryFile_ProjectDataAlias', N'ProjectData_Alias.csv', N'LOAD', N'nvarchar(260)', 0, 0, 0, N'Nom du fichier CSV alias bilingue OData. Charge dans stg.import_dictionary_projectdata_alias.'
    UNION ALL SELECT N'ImportCsvToLoadTables', N'1', N'LOAD', N'bit', 0, 0, 1, N'Legacy libelle: 1 = utilisér SqlBulkCopy pour charger les CSV dans stg.import_dictionary_*.'
    UNION ALL SELECT N'TruncateLoadTablesBeforeCsvImport', N'1', N'LOAD', N'bit', 0, 0, 0, N'1 = tronquer les tables stg.import_dictionary_* avant chargement CSV.'
    UNION ALL SELECT N'Language', CONVERT(nvarchar(4000), @PwaLanguage), N'LEGACY', N'nvarchar(10)', 0, 0, 1, N'Legacy V5: utilisér PwaLanguage en V6.'
) AS S
    ON S.SettingKey = T.SettingKey
WHEN MATCHED THEN
    UPDATE SET
        T.SettingGroup = S.SettingGroup,
        T.SettingType = S.SettingType,
        T.IsRequired = S.IsRequired,
        T.IsSecret = S.IsSecret,
        T.IsDeprecated = S.IsDeprecated,
        T.Description = S.Description,
        T.SettingValue = CASE
            WHEN T.SettingKey IN
            (
                N'ContentDbName', N'ClientName', N'EnvironmentName', N'DesignDatabaseName',
                N'ExpectedDeploymentLogin', N'PwaId', N'PwaLanguage', N'ProjectSchemasCsv',
                N'LoadMode', N'AllowCsvDay1Import', N'Day1LoadSourceMode',
                N'ReviewMode', N'ReportMode', N'ViewDefinitionMode',
                N'FrozenViewSnapshotName', N'ExcludePsseContentCustomFields', N'Language',
                N'ReferenceViewDbName'
            )
            THEN S.SettingValue
            ELSE T.SettingValue
        END,
        T.UpdatedOn = sysdatetime(),
        T.UpdatedBy = suser_sname()
WHEN NOT MATCHED THEN
    INSERT (SettingKey, SettingValue, SettingGroup, SettingType, IsRequired, IsSecret, IsDeprecated, Description)
    VALUES (S.SettingKey, S.SettingValue, S.SettingGroup, S.SettingType, S.IsRequired, S.IsSecret, S.IsDeprecated, S.Description);

SELECT @ToolboxDbName = NULLIF(LTRIM(RTRIM(SettingValue)), N'')
FROM cfg.Settings
WHERE SettingKey = N'ToolboxDbName';

SELECT @ContentDbName = NULLIF(LTRIM(RTRIM(SettingValue)), N'')
FROM cfg.Settings
WHERE SettingKey = N'ContentDbName';

SELECT @ProjectSchemasCsv = NULLIF(LTRIM(RTRIM(SettingValue)), N'')
FROM cfg.Settings
WHERE SettingKey = N'ProjectSchemasCsv';

SELECT @PwaLanguage = NULLIF(LTRIM(RTRIM(SettingValue)), N'')
FROM cfg.Settings
WHERE SettingKey = N'PwaLanguage';

SELECT @PwaId = TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(SettingValue)), N''))
FROM cfg.Settings
WHERE SettingKey = N'PwaId';

IF @ToolboxDbName IS NULL OR @ToolboxDbName <> DB_NAME()
BEGIN
    THROW 62002, N'cfg.Settings.ToolboxDbName doit correspondre a la base courante.', 1;
END;

IF @ContentDbName IS NULL
    THROW 62003, N'cfg.Settings.ContentDbName est requis.', 1;

IF @ProjectSchemasCsv IS NULL
    THROW 62004, N'cfg.Settings.ProjectSchemasCsv est requis.', 1;

IF @PwaLanguage IS NULL
    SET @PwaLanguage = N'EN';

IF ISNULL(@PwaId, 0) <> 1
    THROW 62005, N'cfg.Settings.PwaId doit valoir 1 dans la trousse V6 courante.', 1;

MERGE cfg.PWA AS T
USING
(
    SELECT @PwaId AS PWAId, @ContentDbName AS ContentDatabaseName, N'1 SmartBox = 1 PWA - base existante attachee par V6' AS Notes, @PwaLanguage AS Language
) AS S
    ON S.PWAId = T.PWAId
WHEN MATCHED THEN
    UPDATE SET T.ContentDatabaseName = S.ContentDatabaseName, T.Notes = S.Notes, T.Language = S.Language, T.UpdatedOn = sysdatetime(), T.UpdatedBy = suser_sname()
WHEN NOT MATCHED THEN
    INSERT (PWAId, ContentDatabaseName, Notes, Language)
    VALUES (S.PWAId, S.ContentDatabaseName, S.Notes, S.Language);

DELETE FROM cfg.PwaSchemaScope WHERE PWAId = @PwaId;

INSERT INTO cfg.PwaSchemaScope (PWAId, SchemaName)
SELECT @PwaId, LTRIM(RTRIM(value))
FROM STRING_SPLIT(@ProjectSchemasCsv, N',')
WHERE LTRIM(RTRIM(value)) <> N'';

EXEC log.usp_WriteScriptLog
    @RunId = @RunId,
    @ScriptName = @ScriptName,
    @ScriptVersion = N'V6-DRAFT',
    @Phase = N'COMPLETED',
    @Severity = N'INFO',
    @Status = N'COMPLETED',
    @Message = N'Attachement SmartBox V6 terminé.';

SELECT
    SettingGroup,
    SettingKey,
    SettingValue,
    SettingType,
    IsRequired,
    IsDeprecated,
    Description,
    UpdatedOn,
    UpdatedBy
FROM cfg.Settings
ORDER BY
    CASE SettingGroup
        WHEN N'IDENTITY' THEN 1
        WHEN N'PWA' THEN 2
        WHEN N'MODE' THEN 3
        WHEN N'LOAD' THEN 4
        WHEN N'SECURITY' THEN 5
        WHEN N'VALIDATION' THEN 6
        WHEN N'LEGACY' THEN 99
        ELSE 90
    END,
    SettingKey;
GO
