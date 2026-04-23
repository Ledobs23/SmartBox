/*=====================================================================================================================
    v6_07a_Generate_Views_From_Publication.sql
    Projet      : SmartBox
    Phase       : 07a - Generation dynamique des vues ProjectData depuis dic.EntityColumnPublication
    Role        : Generer les vues ProjectData.* et tbx_fr.* a partir de la couche de publication
                  canonique. Remplace le snapshot fige de v6_04a pour les régénérations futures.

    Notes V6
    - Prérequis : v6_06a exécuté (dic.EntityBinding, dic.EntityJoin, dic.EntityColumnPublication).
    - Ne touche pas aux vues déjà générées par v6_04a sauf si l'entité est dans dic.EntityBinding.
    - Langue des alias dans ProjectData.* pilotée par cfg.PWA.Language (FR ou EN).
    - tbx_fr.* génère toujours les alias FR (pour les clients FR). tbx.* génère toujours EN.
    - Colonnes MAPPED     : SourceExpression AS alias
    - Colonnes UNMAPPED   : FallbackExpression (CAST NULL) AS alias
    - Colonnes NAVIGATION sans source : CAST(NULL AS nvarchar(255)) AS alias
    - Colonnes MAPPED_NEEDS_JOIN (IsPublished=0) : exclues de la vue jusqu'a résolution.
    - ProjectData : nom de vue = EntityName_FR si PwaLanguage=FR (ex. Projets), EntityName_EN sinon (ex. Projects).
                   Aliases colonnes = Column_FR si PwaLanguage=FR, Column_EN sinon.
    - tbx_fr     : nom de vue = vw_EntityName_FR (ex. vw_Projets), aliases Column_FR (toujours FR).
    - tbx        : nom de vue = vw_EntityName_EN, aliases Column_EN (toujours EN, couche interne).
    - En cas d'erreur sur une entité : log + continuation sur les entités suivantes.
    - Journalisation dans log.ScriptExecutionLog et report.ViewStackValidation.
=====================================================================================================================*/
SET NOCOUNT ON;
SET XACT_ABORT OFF;  /* OFF pour continuer en cas d'erreur sur une entité */
GO

IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb')
    THROW 67001, N'Exécuter ce script dans la base SmartBox cible.', 1;

IF OBJECT_ID(N'dic.EntityColumnPublication', N'U') IS NULL
    THROW 67002, N'dic.EntityColumnPublication absente. Exécuter v6_06a avant v6_07a.', 1;

IF OBJECT_ID(N'dic.EntityBinding', N'U') IS NULL
    THROW 67003, N'dic.EntityBinding absente. Exécuter v6_06a avant v6_07a.', 1;

IF NOT EXISTS (SELECT 1 FROM dic.EntityColumnPublication)
    THROW 67004, N'dic.EntityColumnPublication est vide. Exécuter v6_06a avant v6_07a.', 1;

IF NOT EXISTS (SELECT 1 FROM dic.EntityBinding WHERE IsActive = 1 AND PsseObjectName IS NOT NULL)
    THROW 67005, N'Aucun binding actif dans dic.EntityBinding. Exécuter v6_06a avant v6_07a.', 1;

/* Créer report.ViewStackValidation si absente */
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
        ReportedAt datetime2(0) NOT NULL CONSTRAINT DF_report_VSV_At DEFAULT(sysdatetime()),
        CONSTRAINT PK_report_ViewStackValidation PRIMARY KEY (ViewStackValidationId)
    );
END;
GO

/* ===========================================================================================
   LOT 2 : Generation des vues
   =========================================================================================== */
DECLARE @RunId         uniqueidentifier = newid();
DECLARE @ScriptName    sysname          = N'v6_07a_Generate_Views_From_Publication.sql';
DECLARE @PwaLanguage   nvarchar(10);
DECLARE @TargetSchémas nvarchar(200);

/* Schémas cibles à générer: ProjectData (alias langue cible), tbx (EN), tbx_fr (FR) */
/* Modifiable ici si besoin de restreindre la génération */
DECLARE @GenProjectData bit = 1;
DECLARE @GenTbx         bit = 1;
DECLARE @GenTbxFr       bit = 1;

DECLARE @EntityName_EN    nvarchar(256);
DECLARE @EntityName_FR    nvarchar(256);
DECLARE @PsseSchema       sysname;
DECLARE @PsseObject       nvarchar(256);
DECLARE @SmartBoxSchema   sysname;
DECLARE @BindingAlias     nvarchar(60);
DECLARE @ConfidenceLevel  nvarchar(20);

DECLARE @ColListEN        nvarchar(max);
DECLARE @ColListFR        nvarchar(max);
DECLARE @JoinClauses      nvarchar(max);
DECLARE @FromClause       nvarchar(500);
DECLARE @ViewSql          nvarchar(max);
DECLARE @ViewSchema       sysname;
DECLARE @ViewName         sysname;
DECLARE @ErrMsg           nvarchar(4000);
DECLARE @ErrNum           int;

DECLARE @ViewCreated      int = 0;
DECLARE @ViewFailed       int = 0;
DECLARE @ViewSkipped      int = 0;
DECLARE @Msg              nvarchar(max);

SELECT @PwaLanguage = NULLIF(LTRIM(RTRIM(Language)), N'')
FROM cfg.PWA;
IF @PwaLanguage IS NULL
    SELECT @PwaLanguage = NULLIF(LTRIM(RTRIM(SettingValue)), N'')
    FROM cfg.Settings WHERE SettingKey = N'PwaLanguage';
SET @PwaLanguage = ISNULL(@PwaLanguage, N'FR');

SET @Msg = CONCAT(N'Generation vues depuis dic.EntityColumnPublication. PwaLanguage=', @PwaLanguage);
EXEC log.usp_WriteScriptLog
    @RunId=@RunId, @ScriptName=@ScriptName, @ScriptVersion=N'V6-DRAFT',
    @Phase=N'START', @Severity=N'INFO', @Status=N'STARTED',
    @Message=@Msg;

/* ===========================================================================================
   Curseur sur chaque entité avec un binding actif et résolu
   =========================================================================================== */
DECLARE entity_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT
        eb.EntityName_EN,
        eb.EntityName_FR,
        eb.PsseSchemaName,
        eb.PsseObjectName,
        eb.SmartBoxSchemaName,
        eb.BindingAlias,
        eb.ConfidenceLevel
    FROM dic.EntityBinding eb
    WHERE eb.IsActive = 1
      AND eb.PsseObjectName IS NOT NULL
      AND eb.ConfidenceLevel IN (N'HIGH', N'MEDIUM', N'AUTO_HIGH', N'AUTO_MEDIUM', N'MANUAL')
    ORDER BY eb.EntityName_EN;

OPEN entity_cursor;
FETCH NEXT FROM entity_cursor
INTO @EntityName_EN, @EntityName_FR, @PsseSchema, @PsseObject, @SmartBoxSchema, @BindingAlias, @ConfidenceLevel;

WHILE @@FETCH_STATUS = 0
BEGIN
    /* Verifier qu'il y a au moins une colonne publiable pour cette entité */
    IF NOT EXISTS (
        SELECT 1 FROM dic.EntityColumnPublication
        WHERE EntityName_EN = @EntityName_EN
          AND IsPublished = 1
    )
    BEGIN
        SET @ViewSkipped += 1;
        INSERT INTO report.ViewStackValidation (RunId, ViewSchema, ViewName, ValidationStatus, Message)
        VALUES (@RunId, N'ProjectData', @EntityName_EN, N'SKIPPED',
                CONCAT(N'Aucune colonne IsPublished=1 pour [', @EntityName_EN, N']. Resoudre dic.EntityColumnPublication.'));

        FETCH NEXT FROM entity_cursor
        INTO @EntityName_EN, @EntityName_FR, @PsseSchema, @PsseObject, @SmartBoxSchema, @BindingAlias, @ConfidenceLevel;
        CONTINUE;
    END;

    /* Construire la clause FROM */
    SET @FromClause = QUOTENAME(@SmartBoxSchema) + N'.' + QUOTENAME(@PsseObject) + N' AS ' + QUOTENAME(@BindingAlias);

    /* Construire les clauses JOIN depuis dic.EntityJoin */
    SELECT @JoinClauses = STRING_AGG(
        CONVERT(nvarchar(max),
            CONCAT(
                ej.JoinType, N' JOIN ',
                QUOTENAME(ej.SmartBoxSchemaName), N'.', QUOTENAME(ej.PsseObjectName),
                N' AS ', QUOTENAME(ej.JoinAlias),
                N' ON ', ISNULL(ej.JoinExpression, N'/* TODO */')
            )
        ),
        N'
    '
    ) WITHIN GROUP (ORDER BY ej.JoinTag)
    FROM dic.EntityJoin ej
    WHERE ej.EntityName_EN = @EntityName_EN
      AND ej.IsActive = 1
      AND ej.JoinExpression NOT LIKE N'/* TODO%';

    /* Construire la liste de colonnes EN */
    SELECT @ColListEN = STRING_AGG(
        CONVERT(nvarchar(max),
            CASE
                WHEN ecp.MapStatus IN (N'MAPPED') AND ecp.SourceExpression IS NOT NULL
                    THEN ecp.SourceExpression + N' AS ' + QUOTENAME(ecp.Column_EN)
                WHEN ecp.MapStatus = N'UNMAPPED' AND ecp.FallbackExpression IS NOT NULL
                    THEN ecp.FallbackExpression + N' AS ' + QUOTENAME(ecp.Column_EN)
                ELSE
                    N'CAST(NULL AS nvarchar(255)) AS ' + QUOTENAME(ecp.Column_EN)
            END
        ),
        N',
    '
    ) WITHIN GROUP (ORDER BY ecp.ColumnPosition)
    FROM dic.EntityColumnPublication ecp
    WHERE ecp.EntityName_EN = @EntityName_EN
      AND ecp.IsPublished = 1;

    /* Construire la liste de colonnes FR (alias FR si disponible, sinon EN) */
    SELECT @ColListFR = STRING_AGG(
        CONVERT(nvarchar(max),
            CASE
                WHEN ecp.MapStatus IN (N'MAPPED') AND ecp.SourceExpression IS NOT NULL
                    THEN ecp.SourceExpression + N' AS ' + QUOTENAME(ISNULL(ecp.Column_FR, ecp.Column_EN))
                WHEN ecp.MapStatus = N'UNMAPPED' AND ecp.FallbackExpression IS NOT NULL
                    THEN ecp.FallbackExpression + N' AS ' + QUOTENAME(ISNULL(ecp.Column_FR, ecp.Column_EN))
                ELSE
                    N'CAST(NULL AS nvarchar(255)) AS ' + QUOTENAME(ISNULL(ecp.Column_FR, ecp.Column_EN))
            END
        ),
        N',
    '
    ) WITHIN GROUP (ORDER BY ecp.ColumnPosition)
    FROM dic.EntityColumnPublication ecp
    WHERE ecp.EntityName_EN = @EntityName_EN
      AND ecp.IsPublished = 1;

    /* ---------------------------------------------------------------------------------
       Generer ProjectData.<EntityName_FR ou EN selon PwaLanguage> avec alias selon PwaLanguage
       Le nom de vue suit la langue du tenant : si FR -> EntityName_FR (ex. Projets),
       si EN -> EntityName_EN (ex. Projects).
       --------------------------------------------------------------------------------- */
    IF @GenProjectData = 1 AND @ColListEN IS NOT NULL
    BEGIN
        SET @ViewSchema = N'ProjectData';
        SET @ViewName   = CASE WHEN @PwaLanguage = N'FR'
                               THEN ISNULL(@EntityName_FR, @EntityName_EN)
                               ELSE @EntityName_EN
                          END;

        SET @ViewSql = CONCAT(
            N'CREATE OR ALTER VIEW ', QUOTENAME(@ViewSchema), N'.', QUOTENAME(@ViewName), N' AS',
            N'
/* SmartBox V6 - Generated from dic.EntityColumnPublication - PwaLanguage=', @PwaLanguage, N' */',
            N'
SELECT
    ',
            CASE WHEN @PwaLanguage = N'FR' THEN @ColListFR ELSE @ColListEN END,
            N'
FROM ', @FromClause,
            CASE WHEN @JoinClauses IS NOT NULL THEN N'
    ' + @JoinClauses ELSE N'' END,
            N';'
        );

        BEGIN TRY
            EXEC sys.sp_executesql @ViewSql;
            SET @ViewCreated += 1;
            INSERT INTO report.ViewStackValidation (RunId, ViewSchema, ViewName, ValidationStatus, Message)
            VALUES (@RunId, @ViewSchema, @ViewName, N'CREATED',
                    CONCAT(N'Vue générée depuis dic.EntityColumnPublication. Source: ', @PsseObject));
        END TRY
        BEGIN CATCH
            SET @ErrMsg = ERROR_MESSAGE();
            SET @ErrNum = ERROR_NUMBER();
            SET @ViewFailed += 1;
            INSERT INTO report.ViewStackValidation (RunId, ViewSchema, ViewName, ValidationStatus, Message)
            VALUES (@RunId, @ViewSchema, @ViewName, N'ERROR',
                    CONCAT(N'Erreur ', @ErrNum, N': ', @ErrMsg));
            SET @Msg = CONCAT(N'Echec vue ', @ViewSchema, N'.', @ViewName, N': ', @ErrMsg);
            EXEC log.usp_WriteScriptLog
                @RunId=@RunId, @ScriptName=@ScriptName, @ScriptVersion=N'V6-DRAFT',
                @Phase=N'VIEW_ERROR', @Severity=N'WARN', @Status=N'WARNING',
                @Message=@Msg,
                @ErrorNumber=@ErrNum, @ErrorMessage=@ErrMsg;
        END CATCH;
    END;

    /* ---------------------------------------------------------------------------------
       Generer tbx.<EntityName_EN> avec alias EN (couche interne anglaise)
       --------------------------------------------------------------------------------- */
    IF @GenTbx = 1 AND @ColListEN IS NOT NULL
    BEGIN
        SET @ViewSchema = N'tbx';
        SET @ViewName   = CONCAT(N'vw_', @EntityName_EN);

        SET @ViewSql = CONCAT(
            N'CREATE OR ALTER VIEW ', QUOTENAME(@ViewSchema), N'.', QUOTENAME(@ViewName), N' AS',
            N'
/* SmartBox V6 - tbx layer EN - Generated from dic.EntityColumnPublication */',
            N'
SELECT
    ', @ColListEN,
            N'
FROM ', @FromClause,
            CASE WHEN @JoinClauses IS NOT NULL THEN N'
    ' + @JoinClauses ELSE N'' END,
            N';'
        );

        BEGIN TRY
            EXEC sys.sp_executesql @ViewSql;
            SET @ViewCreated += 1;
            INSERT INTO report.ViewStackValidation (RunId, ViewSchema, ViewName, ValidationStatus, Message)
            VALUES (@RunId, @ViewSchema, @ViewName, N'CREATED', N'Vue tbx EN générée.');
        END TRY
        BEGIN CATCH
            SET @ErrMsg = ERROR_MESSAGE();
            SET @ErrNum = ERROR_NUMBER();
            SET @ViewFailed += 1;
            INSERT INTO report.ViewStackValidation (RunId, ViewSchema, ViewName, ValidationStatus, Message)
            VALUES (@RunId, @ViewSchema, @ViewName, N'ERROR', CONCAT(N'Erreur ', @ErrNum, N': ', @ErrMsg));
        END CATCH;
    END;

    /* ---------------------------------------------------------------------------------
       Generer tbx_fr.<EntityName_FR ou EntityName_EN> avec alias FR
       --------------------------------------------------------------------------------- */
    IF @GenTbxFr = 1 AND @ColListFR IS NOT NULL
    BEGIN
        SET @ViewSchema = N'tbx_fr';
        SET @ViewName   = CONCAT(N'vw_', ISNULL(@EntityName_FR, @EntityName_EN));

        SET @ViewSql = CONCAT(
            N'CREATE OR ALTER VIEW ', QUOTENAME(@ViewSchema), N'.', QUOTENAME(@ViewName), N' AS',
            N'
/* SmartBox V6 - tbx_fr layer FR - Generated from dic.EntityColumnPublication */',
            N'
SELECT
    ', @ColListFR,
            N'
FROM ', @FromClause,
            CASE WHEN @JoinClauses IS NOT NULL THEN N'
    ' + @JoinClauses ELSE N'' END,
            N';'
        );

        BEGIN TRY
            EXEC sys.sp_executesql @ViewSql;
            SET @ViewCreated += 1;
            INSERT INTO report.ViewStackValidation (RunId, ViewSchema, ViewName, ValidationStatus, Message)
            VALUES (@RunId, @ViewSchema, @ViewName, N'CREATED', N'Vue tbx_fr FR générée.');
        END TRY
        BEGIN CATCH
            SET @ErrMsg = ERROR_MESSAGE();
            SET @ErrNum = ERROR_NUMBER();
            SET @ViewFailed += 1;
            INSERT INTO report.ViewStackValidation (RunId, ViewSchema, ViewName, ValidationStatus, Message)
            VALUES (@RunId, @ViewSchema, @ViewName, N'ERROR', CONCAT(N'Erreur ', @ErrNum, N': ', @ErrMsg));
        END CATCH;
    END;

    FETCH NEXT FROM entity_cursor
    INTO @EntityName_EN, @EntityName_FR, @PsseSchema, @PsseObject, @SmartBoxSchema, @BindingAlias, @ConfidenceLevel;
END;

CLOSE entity_cursor;
DEALLOCATE entity_cursor;

/* ===========================================================================================
   Rapport final
   =========================================================================================== */
SET @Msg = CONCAT(
    N'Generation vues terminée. ',
    N'Créées=', @ViewCreated,
    N'; Echouees=', @ViewFailed,
    N'; Ignorees=', @ViewSkipped,
    N'. PwaLanguage=', @PwaLanguage
);

DECLARE @FinalSeverity nvarchar(20) = CASE WHEN @ViewFailed > 0 THEN N'WARN' ELSE N'INFO' END;
EXEC log.usp_WriteScriptLog
    @RunId=@RunId, @ScriptName=@ScriptName, @ScriptVersion=N'V6-DRAFT',
    @Phase=N'COMPLETED',
    @Severity=@FinalSeverity,
    @Status=N'COMPLETED',
    @Message=@Msg,
    @RowsAffected=@ViewCreated;

/* Rapport console */
SELECT N'Vues créées'  AS Metrique, CONVERT(nvarchar(30), @ViewCreated)  AS Valeur
UNION ALL SELECT N'Vues echouees', CONVERT(nvarchar(30), @ViewFailed)
UNION ALL SELECT N'Entites ignorees', CONVERT(nvarchar(30), @ViewSkipped);

/* Detail par vue */
SELECT ViewSchema, ViewName, ValidationStatus, Message, ReportedAt
FROM report.ViewStackValidation
WHERE RunId = @RunId
ORDER BY ValidationStatus DESC, ViewSchema, ViewName;

/* Pour valider les vues générées, exécuter après ce script :
   SELECT v.name, s.name AS schema_name, m.is_schema_bound
   FROM sys.views v
   JOIN sys.schemas s ON s.schema_id = v.schema_id
   WHERE s.name IN (N'ProjectData', N'tbx', N'tbx_fr')
   ORDER BY s.name, v.name;

   Et pour détectér les vues invalides :
   SELECT OBJECT_SCHEMA_NAME(object_id) AS schm, name
   FROM sys.objects o
   WHERE type = N'V'
     AND OBJECT_SCHEMA_NAME(object_id) IN (N'ProjectData', N'tbx', N'tbx_fr')
     AND NOT EXISTS (
         SELECT 1 FROM sys.sql_expression_dependencies d
         WHERE d.referencing_id = o.object_id
     );
*/
GO
