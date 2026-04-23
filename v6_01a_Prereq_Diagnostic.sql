/*=====================================================================================================================
    v6_01a_Prereq_Diagnostic.sql
    Projet      : SmartBox
    Phase       : 01a - Diagnostic V6 pour base existante
    Role        : Vérifier les prérequis applicatifs sans exiger CREATE DATABASE, xp_cmdshell ou accès fichiers.

    Notes V6
    - La base SmartBox est supposée déjà créée par le client.
    - xp_cmdshell est diagnostique mais non requis.
    - BULK INSERT est diagnostique seulement pour le chargement DBA optionnel du jour 1.
=====================================================================================================================*/
SET NOCOUNT ON;
GO

IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb')
BEGIN
    THROW 61001, N'Exécuter ce diagnostic dans la base SmartBox cible existante, pas dans une base système.', 1;
END;

DECLARE @MinCompatibilityLevel int = 140;
DECLARE @DbCompatibilityLevel int;
DECLARE @XpCmdShellEnabled bit = 0;
DECLARE @HasBulkPermission bit = 0;

SELECT @DbCompatibilityLevel = compatibility_level
FROM sys.databases
WHERE name = DB_NAME();

SELECT @XpCmdShellEnabled =
    CASE WHEN TRY_CONVERT(int, value_in_use) = 1 THEN 1 ELSE 0 END
FROM sys.configurations
WHERE name = N'xp_cmdshell';

SET @HasBulkPermission =
    CASE
        WHEN IS_SRVROLEMEMBER(N'sysadmin') = 1
          OR HAS_PERMS_BY_NAME(NULL, NULL, N'ADMINISTER BULK OPERATIONS') = 1
        THEN 1 ELSE 0
    END;

DECLARE @Result TABLE
(
    CheckOrder      int             NOT NULL,
    Category        nvarchar(60)    NOT NULL,
    CheckName       nvarchar(128)   NOT NULL,
    Status          nvarchar(20)    NOT NULL,
    Details         nvarchar(4000)  NULL,
    Recommendation  nvarchar(4000)  NULL,
    IsBlocking      bit             NOT NULL
);

INSERT INTO @Result
(
    CheckOrder,
    Category,
    CheckName,
    Status,
    Details,
    Recommendation,
    IsBlocking
)
VALUES
(
    10,
    N'DATABASE',
    N'Contexte base cible',
    N'OK',
    CONCAT(N'Database=', DB_NAME()),
    N'Aucune.',
    0
),
(
    20,
    N'DATABASE',
    N'Compatibility level',
    CASE WHEN @DbCompatibilityLevel >= @MinCompatibilityLevel THEN N'OK' ELSE N'BLOCKING' END,
    CONCAT(N'CompatibilityLevel=', @DbCompatibilityLevel, N' | Minimum=', @MinCompatibilityLevel),
    CASE WHEN @DbCompatibilityLevel >= @MinCompatibilityLevel
         THEN N'Aucune.'
         ELSE N'Augmenter le compatibility level avant exécution de la trousse V6.' END,
    CASE WHEN @DbCompatibilityLevel >= @MinCompatibilityLevel THEN 0 ELSE 1 END
),
(
    30,
    N'SECURITY',
    N'CREATE/ALTER objets applicatifs',
    CASE WHEN HAS_PERMS_BY_NAME(DB_NAME(), N'DATABASE', N'CREATE TABLE') = 1 THEN N'OK' ELSE N'BLOCKING' END,
    CONCAT(N'Login=', SUSER_SNAME()),
    N'Le compte de déploiement doit pouvoir créer schémas, tables, vues et procédures dans la base cible.',
    CASE WHEN HAS_PERMS_BY_NAME(DB_NAME(), N'DATABASE', N'CREATE TABLE') = 1 THEN 0 ELSE 1 END
),
(
    40,
    N'SECURITY',
    N'BULK INSERT',
    CASE WHEN @HasBulkPermission = 1 THEN N'OK' ELSE N'INFO' END,
    CONCAT(N'Permission ADMINISTER BULK OPERATIONS ou sysadmin=', @HasBulkPermission),
    N'Optionnel en V6. Requis seulement si le DBA charge les CSV jour 1 avec BULK INSERT.',
    0
),
(
    50,
    N'SECURITY',
    N'xp_cmdshell',
    CASE WHEN @XpCmdShellEnabled = 1 THEN N'INFO' ELSE N'OK' END,
    CONCAT(N'xp_cmdshell actif=', @XpCmdShellEnabled),
    N'Non requis par le pipeline V6 applicatif. Garder desactive sauf besoin DBA hors trousse.',
    0
),
(
    60,
    N'OBJECTS',
    N'cfg.Settings',
    CASE WHEN OBJECT_ID(N'cfg.Settings', N'U') IS NOT NULL THEN N'OK' ELSE N'INFO' END,
    N'Configuration SmartBox.',
    N'Si absent, exécuter v6_02a_Attach_Existing_SmartBox_Database.sql.',
    0
),
(
    70,
    N'OBJECTS',
    N'log.ScriptExecutionLog',
    CASE WHEN OBJECT_ID(N'log.ScriptExecutionLog', N'U') IS NOT NULL THEN N'OK' ELSE N'INFO' END,
    N'Journal applicatif V6.',
    N'Si absent, exécuter v6_02a puis v6_03a.',
    0
),
(
    80,
    N'OBJECTS',
    N'stg.import_dictionary_*',
    CASE
        WHEN OBJECT_ID(N'stg.import_dictionary_od_fields', N'U') IS NOT NULL
         AND OBJECT_ID(N'stg.import_dictionary_lookup_entries', N'U') IS NOT NULL
         AND OBJECT_ID(N'stg.import_dictionary_projectdata_alias', N'U') IS NOT NULL
        THEN N'OK' ELSE N'INFO'
    END,
    N'Tables de staging pour l''import du dictionnaire jour 1.',
    N'Si absent, exécuter v6_03a_Create_Foundations.sql.',
    0
);

SELECT
    Category,
    CheckName,
    Status,
    Details,
    Recommendation,
    IsBlocking
FROM @Result
ORDER BY CheckOrder;

IF EXISTS (SELECT 1 FROM @Result WHERE IsBlocking = 1)
BEGIN
    THROW 61002, N'Diagnostic V6 bloque. Corriger les contrôles BLOCKING avant de poursuivre.', 1;
END;

PRINT N'Diagnostic V6 terminé sans blocage.';
GO
