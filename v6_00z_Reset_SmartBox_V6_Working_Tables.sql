/*=====================================================================================================================
    v6_00z_Reset_SmartBox_V6_Working_Tables.sql
    Projet      : SmartBox
    Phase       : 00z - Outil de reprise / nettoyage V6
    Role        : Remettre la base a zero avant de rejouer le pipeline 02a -> 07a.

    Modes disponibles (modifier les parametres ci-dessous) :
    -------------------------------------------------------
    Mode SOFT (defaut) : vide les donnees, conserve la structure des tables.
        -> Rejouer 03a -> 07a suffit apres un soft reset.

    Mode HARD (@DropWorkingTables = 1) : supprime les tables de travail V6 en entier.
        -> Necessaire quand la structure des tables a change (evolution de schema).
        -> Rejouer 02a -> 07a apres un hard reset.

    Dans les deux modes : cfg.Settings et cfg.PWA sont TOUJOURS preserves.
    Les synonymes src_* et les vues ProjectData/tbx/tbx_fr/tbx_master sont toujours supprimes.

    Protection double-securite
    -------------------------------------------------------
    @ClearSettings = 1  ET  @AllowClearProtectedConfig = 1  pour vider cfg.Settings/cfg.PWA.
    Ne jamais mettre ces flags sans etre certain de vouloir resaisir toute la configuration.
=====================================================================================================================*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb')
    THROW 60001, N'Executer ce script dans la base SmartBox cible, normalement SPR.', 1;
GO

/*=====================================================================================================================
    PARAMETRES DBA - SECTION A MODIFIER AU BESOIN
=====================================================================================================================*/
DECLARE @ExpectedDatabaseName    sysname = N'SPR';

/* --- Objets generes --- */
DECLARE @DropGeneratedViews      bit = 1;   -- Supprime vues ProjectData/tbx/tbx_fr/tbx_master

DECLARE @DropSourceSynonyms      bit = 1;   -- Supprime synonymes src_*

/* --- Mode de nettoyage --- */
DECLARE @DropWorkingTables       bit = 0;   -- 0=TRUNCATE (soft), 1=DROP TABLE (hard - resaisir v02a->v07a)

/* --- Zones protegees (double confirmation requise) --- */
DECLARE @ClearExecutionLog       bit = 0;   -- 1 = vide log.ScriptExecutionLog
DECLARE @ClearSettings           bit = 0;   -- 1 = vide cfg.Settings, cfg.PWA, cfg.PwaSchemaScope
DECLARE @AllowClearProtectedConfig bit = 0; -- Mettre a 1 pour confirmer les deux lignes ci-dessus

/* =====================================================================================================================
   NE PAS MODIFIER EN DESSOUS DE CETTE LIGNE
   =================================================================================================================== */
DECLARE @Sql  nvarchar(max);
DECLARE @Msg  nvarchar(500);

IF DB_NAME() <> @ExpectedDatabaseName
    THROW 60002, N'La base courante ne correspond pas a @ExpectedDatabaseName. Modifier le parametre.', 1;

IF (@ClearExecutionLog = 1 OR @ClearSettings = 1) AND @AllowClearProtectedConfig = 0
    THROW 60003, N'ClearExecutionLog/ClearSettings demande. Mettre @AllowClearProtectedConfig = 1 pour confirmer.', 1;

PRINT N'=== SmartBox V6 reset START === Mode=' + CASE WHEN @DropWorkingTables = 1 THEN N'HARD (DROP)' ELSE N'SOFT (TRUNCATE)' END;
PRINT N'Database=' + DB_NAME();

/* ===========================================================================================
   1. Vues generees (ProjectData / tbx / tbx_fr / tbx_master)
   =========================================================================================== */
IF @DropGeneratedViews = 1
BEGIN
    SELECT @Sql = STRING_AGG(
        CONVERT(nvarchar(max),
            N'DROP VIEW IF EXISTS ' + QUOTENAME(s.name) + N'.' + QUOTENAME(v.name) + N';'),
        CHAR(10)
    ) WITHIN GROUP (ORDER BY
        CASE s.name WHEN N'ProjectData' THEN 1 WHEN N'tbx_fr' THEN 2 WHEN N'tbx' THEN 3 ELSE 4 END,
        v.name)
    FROM sys.views v
    JOIN sys.schemas s ON s.schema_id = v.schema_id
    WHERE s.name IN (N'ProjectData', N'tbx', N'tbx_fr', N'tbx_master');

    IF @Sql IS NOT NULL
        EXEC sys.sp_executesql @Sql;
    PRINT N'[1] Views dropped: ' + ISNULL(CAST(LEN(@Sql) - LEN(REPLACE(@Sql, N'DROP VIEW', N'')) AS nvarchar) + N'/9', N'0');
    SET @Sql = NULL;
END;

/* ===========================================================================================
   2. Synonymes src_*
   =========================================================================================== */
IF @DropSourceSynonyms = 1
BEGIN
    SELECT @Sql = STRING_AGG(
        CONVERT(nvarchar(max),
            N'DROP SYNONYM IF EXISTS ' + QUOTENAME(s.name) + N'.' + QUOTENAME(sy.name) + N';'),
        CHAR(10)
    ) WITHIN GROUP (ORDER BY s.name, sy.name)
    FROM sys.synonyms sy
    JOIN sys.schemas s ON s.schema_id = sy.schema_id
    WHERE s.name LIKE N'src[_]%';

    IF @Sql IS NOT NULL
        EXEC sys.sp_executesql @Sql;
    PRINT N'[2] Synonyms dropped.';
    SET @Sql = NULL;
END;

/* ===========================================================================================
   3. Tables de travail V6
   Toutes les tables sauf cfg.Settings, cfg.PWA et (optionnel) log.ScriptExecutionLog.
   =========================================================================================== */

/* Helper inline : TRUNCATE ou DROP selon le mode */

/* --- stg.* --- */
DECLARE @stgTables TABLE (TableName nvarchar(256));
INSERT INTO @stgTables VALUES
    (N'stg.ColumnInventory'),
    (N'stg.ObjectInventory'),
    (N'stg.import_dictionary_od_fields'),
    (N'stg.import_dictionary_lookup_entries'),
    (N'stg.import_dictionary_projectdata_alias'),
    (N'stg.ODataPsseExactColumnMatch'),
    (N'stg.EntitySource_Draft'),
    (N'stg.DictionaryQualityIssue'),
    (N'stg.EntityJoin_Draft'),
    (N'stg.ODataPsseMap_Draft'),
    (N'stg.EntityDraftBuildLog'),
    (N'stg.RunLog');

/* --- cfg.* (hors Settings et PWA) --- */
DECLARE @cfgTables TABLE (TableName nvarchar(256));
INSERT INTO @cfgTables VALUES
    (N'cfg.PwaObjectScope'),
    (N'cfg.PwaSchemaScope'),
    (N'cfg.dictionary_od_fields'),
    (N'cfg.dictionary_lookup_entries'),
    (N'cfg.dictionary_projectdata_alias');

/* --- dic.* --- */
DECLARE @dicTables TABLE (TableName nvarchar(256));
INSERT INTO @dicTables VALUES
    (N'dic.EntityColumnPublication'),
    (N'dic.EntityJoin'),
    (N'dic.EntityBinding'),
    (N'dic.EntityColumnMap'),
    (N'dic.Entity'),
    (N'dic.LookupMap');

/* --- load.* --- */
DECLARE @loadTables TABLE (TableName nvarchar(256));
INSERT INTO @loadTables VALUES
    (N'load.ProjectDataFields'),
    (N'load.ProjectServerLookupEntries'),
    (N'load.ProjectDataAlias'),
    (N'load.LoadBatch');

/* --- review.* --- */
DECLARE @reviewTables TABLE (TableName nvarchar(256));
INSERT INTO @reviewTables VALUES
    (N'review.ManualJoinOverride'),
    (N'review.ManualColumnOverride'),
    (N'review.ReconstructionDecision');

/* --- report.* --- */
DECLARE @reportTables TABLE (TableName nvarchar(256));
INSERT INTO @reportTables VALUES
    (N'report.ViewStackValidation'),
    (N'report.BlockingErrorReport'),
    (N'report.DictionaryQualityReport'),
    (N'report.FoundationCheckResult');

/* Construire et executer le SQL de nettoyage pour un groupe */
DECLARE @GroupName nvarchar(50);

DECLARE table_group CURSOR LOCAL FAST_FORWARD FOR
    SELECT N'stg.*',    TableName FROM @stgTables
    UNION ALL
    SELECT N'cfg.*',    TableName FROM @cfgTables
    UNION ALL
    SELECT N'dic.*',    TableName FROM @dicTables
    UNION ALL
    SELECT N'load.*',   TableName FROM @loadTables
    UNION ALL
    SELECT N'review.*', TableName FROM @reviewTables
    UNION ALL
    SELECT N'report.*', TableName FROM @reportTables;

DECLARE @CurrentGroup nvarchar(50);
DECLARE @TableName    nvarchar(256);
DECLARE @LastGroup    nvarchar(50) = N'';
DECLARE @ActionCount  int = 0;

OPEN table_group;
FETCH NEXT FROM table_group INTO @CurrentGroup, @TableName;

WHILE @@FETCH_STATUS = 0
BEGIN
    IF @CurrentGroup <> @LastGroup AND @LastGroup <> N''
    BEGIN
        PRINT N'[3] ' + @LastGroup + N' : ' + CAST(@ActionCount AS nvarchar) + N' tables traitees.';
        SET @ActionCount = 0;
    END;
    SET @LastGroup = @CurrentGroup;

    IF OBJECT_ID(@TableName, N'U') IS NOT NULL
    BEGIN
        IF @DropWorkingTables = 1
            SET @Sql = N'DROP TABLE ' + @TableName + N';';
        ELSE
            SET @Sql = N'TRUNCATE TABLE ' + @TableName + N';';

        EXEC sys.sp_executesql @Sql;
        SET @ActionCount += 1;
    END;

    FETCH NEXT FROM table_group INTO @CurrentGroup, @TableName;
END;

IF @LastGroup <> N''
    PRINT N'[3] ' + @LastGroup + N' : ' + CAST(@ActionCount AS nvarchar) + N' tables traitees.';

CLOSE table_group;
DEALLOCATE table_group;

/* ===========================================================================================
   4. Zones protegees (log + config)
   =========================================================================================== */
IF @ClearExecutionLog = 1 AND @AllowClearProtectedConfig = 1
BEGIN
    IF OBJECT_ID(N'log.ScriptExecutionLog', N'U') IS NOT NULL
    BEGIN
        IF @DropWorkingTables = 1
            DROP TABLE log.ScriptExecutionLog;
        ELSE
            TRUNCATE TABLE log.ScriptExecutionLog;
        PRINT N'[4] log.ScriptExecutionLog cleared.';
    END;
END;

IF @ClearSettings = 1 AND @AllowClearProtectedConfig = 1
BEGIN
    IF OBJECT_ID(N'cfg.PwaSchemaScope', N'U') IS NOT NULL DELETE FROM cfg.PwaSchemaScope;
    IF OBJECT_ID(N'cfg.PWA', N'U') IS NOT NULL
    BEGIN
        IF @DropWorkingTables = 1
            DROP TABLE cfg.PWA;
        ELSE
            DELETE FROM cfg.PWA;
    END;
    IF OBJECT_ID(N'cfg.Settings', N'U') IS NOT NULL
    BEGIN
        IF @DropWorkingTables = 1
            DROP TABLE cfg.Settings;
        ELSE
            DELETE FROM cfg.Settings;
    END;
    PRINT N'[4] cfg.Settings, cfg.PWA, cfg.PwaSchemaScope cleared.';
END;

/* ===========================================================================================
   5. Rapport final
   =========================================================================================== */
PRINT N'=== SmartBox V6 reset COMPLETED ===';

SELECT
    N'Views remaining'     AS Item, COUNT(*) AS Remaining
FROM sys.views v
JOIN sys.schemas s ON s.schema_id = v.schema_id
WHERE s.name IN (N'ProjectData', N'tbx', N'tbx_fr', N'tbx_master')
UNION ALL
SELECT N'Synonyms remaining', COUNT(*)
FROM sys.synonyms sy
JOIN sys.schemas s ON s.schema_id = sy.schema_id
WHERE s.name LIKE N'src[_]%'
UNION ALL
SELECT N'cfg.Settings rows',
    CASE WHEN OBJECT_ID(N'cfg.Settings',N'U') IS NOT NULL
         THEN (SELECT COUNT(*) FROM cfg.Settings) ELSE -1 END
UNION ALL
SELECT N'cfg.PWA rows',
    CASE WHEN OBJECT_ID(N'cfg.PWA',N'U') IS NOT NULL
         THEN (SELECT COUNT(*) FROM cfg.PWA) ELSE -1 END
UNION ALL
SELECT N'dic.EntityColumnPublication rows',
    CASE WHEN OBJECT_ID(N'dic.EntityColumnPublication',N'U') IS NOT NULL
         THEN (SELECT COUNT(*) FROM dic.EntityColumnPublication) ELSE -1 END
UNION ALL
SELECT N'stg.ColumnInventory rows',
    CASE WHEN OBJECT_ID(N'stg.ColumnInventory',N'U') IS NOT NULL
         THEN (SELECT COUNT(*) FROM stg.ColumnInventory) ELSE -1 END;
GO
