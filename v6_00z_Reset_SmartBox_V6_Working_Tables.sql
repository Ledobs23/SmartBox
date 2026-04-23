/*=====================================================================================================================
    v6_00z_Reset_SmartBox_V6_Working_Tables.sql
    Projet      : SmartBox
    Phase       : 00z - Remise à zéro avant de rejouer le pipeline

    Contexte
    -------------------------------------------------------
    S'il fallait reprendre la création suite à une mauvaise 
    manipulation ou pour rejouter le pipeline complet.

    Comportement par défaut
    -------------------------------------------------------
    DROP TABLE de TOUTES les tables de la base, sauf cfg.PWA et cfg.Settings.
    Cela permet de rejouer le pipeline complet 02a -> 07a sur une base propre.

    cfg.PWA et cfg.Settings contiennent la configuration du tenant : ils sont
    TOUJOURS préservés afin que v6_02a puisse appliquer ses MERGE sans ressaisie.

    Vues ProjectData / tbx / tbx_fr / tbx_master        : toujours supprimées.
    Synonymes src_*                                     : toujours supprimés.
    log.ScriptExecutionLog et toutes les autres tables  : supprimées.

    Schémas touchés par le nettoyage
    -------------------------------------------------------
    stg | dic | review | report | log | cfg (hors PWA et Settings)

    Pour vider aussi cfg.PWA et cfg.Settings (réinstallation complète)
    -------------------------------------------------------
    Mettre @ClearSettings = 1  ET  @AllowClearProtectedConfig = 1.

    Ne jamais activer ces flags sans être certain de vouloir ressaisir
    TOUTE la configuration avec v6_02a.
=====================================================================================================================*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb')
    THROW 60001, N'Exécuter ce script dans la base SmartBox cible, normalement SPR.', 1;
GO

/*=====================================================================================================================
    PARAMÈTRES DBA - Nom de la BD à cibler
=====================================================================================================================*/
DECLARE @ExpectedDatabaseName      sysname = N'SPR';

/* --- Zones protégées (double confirmation requise) --- */
DECLARE @ClearSettings             bit = 0;   -- 1 = supprime aussi cfg.Settings et cfg.PWA
DECLARE @AllowClearProtectedConfig bit = 0;   -- Mettre à 1 pour confirmer @ClearSettings

/* =====================================================================================================================
   NE PAS MODIFIER EN DESSOUS DE CETTE LIGNE
   =================================================================================================================== */
DECLARE @Sql  nvarchar(max);
DECLARE @Cnt  int;

IF DB_NAME() <> @ExpectedDatabaseName
    THROW 60002, N'La base courante ne correspond pas à @ExpectedDatabaseName. Modifier le paramètre.', 1;

IF @ClearSettings = 1 AND @AllowClearProtectedConfig = 0
    THROW 60003, N'ClearSettings demande. Mettre @AllowClearProtectedConfig = 1 pour confirmer.', 1;

PRINT N'=== SmartBox V6 reset START ===';
PRINT N'Database=' + DB_NAME();

/* ===========================================================================================
   1. Vues générées (ProjectData / tbx / tbx_fr / tbx_master)
   =========================================================================================== */
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

SET @Cnt = 0;
IF @Sql IS NOT NULL
BEGIN
    SELECT @Cnt = (LEN(@Sql) - LEN(REPLACE(@Sql, N'DROP VIEW', N''))) / LEN(N'DROP VIEW');
    EXEC sys.sp_executesql @Sql;
END;
PRINT N'[1] Vues supprimées : ' + CAST(@Cnt AS nvarchar) + N'.';
SET @Sql = NULL;

/* ===========================================================================================
   2. Synonymes src_*
   =========================================================================================== */
SELECT @Sql = STRING_AGG(
    CONVERT(nvarchar(max),
        N'DROP SYNONYM IF EXISTS ' + QUOTENAME(s.name) + N'.' + QUOTENAME(sy.name) + N';'),
    CHAR(10)
) WITHIN GROUP (ORDER BY s.name, sy.name)
FROM sys.synonyms sy
JOIN sys.schemas s ON s.schema_id = sy.schema_id
WHERE s.name LIKE N'src[_]%';

SET @Cnt = 0;
IF @Sql IS NOT NULL
BEGIN
    SELECT @Cnt = (LEN(@Sql) - LEN(REPLACE(@Sql, N'DROP SYNONYM', N''))) / LEN(N'DROP SYNONYM');
    EXEC sys.sp_executesql @Sql;
END;
PRINT N'[2] Synonymes supprimés : ' + CAST(@Cnt AS nvarchar) + N'.';
SET @Sql = NULL;

/* ===========================================================================================
   3. Toutes les tables de travail
   Schémas : stg | dic | review | report | log
             cfg  (toutes sauf cfg.PWA et cfg.Settings)

   Approche dynamique : interroge sys.tables -> aucune liste à maintenir.
   Ordre : les tables avec FK enfants en premier (cfg.PwaSchemaScope avant cfg.PWA).
   =========================================================================================== */

/* 3a. Tables avec FK potentielles vers cfg.PWA — à supprimer en premier */
SELECT @Sql = STRING_AGG(
    CONVERT(nvarchar(max),
        N'DROP TABLE IF EXISTS ' + QUOTENAME(s.name) + N'.' + QUOTENAME(t.name) + N';'),
    CHAR(10)
) WITHIN GROUP (ORDER BY t.name)
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE s.name = N'cfg'
  AND t.name NOT IN (N'PWA', N'Settings');

IF @Sql IS NOT NULL EXEC sys.sp_executesql @Sql;
SET @Sql = NULL;

/* 3b. Toutes les autres tables de travail */
SELECT @Sql = STRING_AGG(
    CONVERT(nvarchar(max),
        N'DROP TABLE IF EXISTS ' + QUOTENAME(s.name) + N'.' + QUOTENAME(t.name) + N';'),
    CHAR(10)
) WITHIN GROUP (ORDER BY s.name, t.name)
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE s.name IN (N'stg', N'dic', N'load', N'review', N'report', N'log');

SET @Cnt = 0;
IF @Sql IS NOT NULL
BEGIN
    SELECT @Cnt = (LEN(@Sql) - LEN(REPLACE(@Sql, N'DROP TABLE', N''))) / LEN(N'DROP TABLE');
    EXEC sys.sp_executesql @Sql;
END;
PRINT N'[3] Tables de travail supprimées (stg/dic/load/review/report/log/cfg hors PWA+Settings) : '
      + CAST(@Cnt AS nvarchar) + N'.';
SET @Sql = NULL;

/* ===========================================================================================
   4. cfg.Settings et cfg.PWA (double sécurité uniquement)
   =========================================================================================== */
IF @ClearSettings = 1 AND @AllowClearProtectedConfig = 1
BEGIN
    IF OBJECT_ID(N'cfg.PWA',      N'U') IS NOT NULL DROP TABLE cfg.PWA;
    IF OBJECT_ID(N'cfg.Settings', N'U') IS NOT NULL DROP TABLE cfg.Settings;
    PRINT N'[4] cfg.Settings et cfg.PWA supprimés (réinstallation complète).';
END
ELSE
    PRINT N'[4] cfg.Settings et cfg.PWA préservés.';

/* ===========================================================================================
   5. Rapport final
   =========================================================================================== */
PRINT N'=== SmartBox V6 reset COMPLETED. Rejouer 02a -> 07a. ===';

SELECT
    N'cfg.Settings lignes preservees' AS Item,
    CASE WHEN OBJECT_ID(N'cfg.Settings', N'U') IS NOT NULL
         THEN (SELECT COUNT(*) FROM cfg.Settings) ELSE 0 END AS Valeur
UNION ALL
SELECT N'cfg.PWA lignes preservees',
    CASE WHEN OBJECT_ID(N'cfg.PWA', N'U') IS NOT NULL
         THEN (SELECT COUNT(*) FROM cfg.PWA) ELSE 0 END
UNION ALL
SELECT N'Tables restantes dans dic/stg/load/review/report/log',
    (SELECT COUNT(*) FROM sys.tables t
     JOIN sys.schemas s ON s.schema_id = t.schema_id
     WHERE s.name IN (N'stg', N'dic', N'load', N'review', N'report', N'log'))
UNION ALL
SELECT N'Tables cfg restantes (hors PWA+Settings)',
    (SELECT COUNT(*) FROM sys.tables t
     JOIN sys.schemas s ON s.schema_id = t.schema_id
     WHERE s.name = N'cfg' AND t.name NOT IN (N'PWA', N'Settings'))
UNION ALL
SELECT N'Vues restantes (ProjectData/tbx/tbx_fr/tbx_master)',
    (SELECT COUNT(*) FROM sys.views v
     JOIN sys.schemas s ON s.schema_id = v.schema_id
     WHERE s.name IN (N'ProjectData', N'tbx', N'tbx_fr', N'tbx_master'))
UNION ALL
SELECT N'Synonymes src_* restants',
    (SELECT COUNT(*) FROM sys.synonyms sy
     JOIN sys.schemas s ON s.schema_id = sy.schema_id
     WHERE s.name LIKE N'src[_]%');
GO
