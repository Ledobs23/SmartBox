/*
    Diagnostic v6_07a — Affiche le SQL genere pour chaque entite en erreur.
    Executer dans VS Code connecte a SPR.
    Le SQL genere apparait dans l'onglet Messages (PRINT).
    Tenter aussi une execution reelle et capturer l'erreur exacte.
*/
SET NOCOUNT ON;

DECLARE @EntityName  nvarchar(256);
DECLARE @ColList     nvarchar(max);
DECLARE @eb_schema   sysname;
DECLARE @eb_obj      nvarchar(256);
DECLARE @eb_alias    nvarchar(60);
DECLARE @ViewSql     nvarchar(max);
DECLARE @ErrMsg      nvarchar(4000);
DECLARE @Lang        nvarchar(10) = N'FR';

DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT EntityName_EN FROM (VALUES
        (N'Projects'),
        (N'Assignments'),
        (N'Tasks'),
        (N'Resources'),
        (N'Risks'),
        (N'AssignmentTimephasedDataSet')
    ) AS e(EntityName_EN);

OPEN cur;
FETCH NEXT FROM cur INTO @EntityName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SELECT @eb_schema = SmartBoxSchemaName,
           @eb_obj    = PsseObjectName,
           @eb_alias  = BindingAlias
    FROM dic.EntityBinding
    WHERE EntityName_EN = @EntityName AND IsActive = 1;

    SELECT @ColList = STRING_AGG(
        CONVERT(nvarchar(max),
            CASE
                WHEN ecp.MapStatus = N'MAPPED' AND ecp.SourceExpression IS NOT NULL
                    THEN ecp.SourceExpression + N' AS '
                         + QUOTENAME(ISNULL(ecp.Column_FR, ecp.Column_EN))
                WHEN ecp.MapStatus = N'UNMAPPED' AND ecp.FallbackExpression IS NOT NULL
                    THEN ecp.FallbackExpression + N' AS '
                         + QUOTENAME(ISNULL(ecp.Column_FR, ecp.Column_EN))
                ELSE N'CAST(NULL AS nvarchar(255)) AS '
                     + QUOTENAME(ISNULL(ecp.Column_FR, ecp.Column_EN))
            END
        ),
        N',' + CHAR(10) + N'    '
    ) WITHIN GROUP (ORDER BY ecp.ColumnPosition)
    FROM dic.EntityColumnPublication ecp
    WHERE ecp.EntityName_EN = @EntityName
      AND ecp.IsPublished = 1;

    SET @ViewSql =
        N'CREATE OR ALTER VIEW [ProjectData].[' + @EntityName + N'] AS' + CHAR(10)
        + N'SELECT' + CHAR(10)
        + N'    ' + ISNULL(@ColList, N'/* ColList NULL */') + CHAR(10)
        + N'FROM ' + QUOTENAME(@eb_schema) + N'.' + QUOTENAME(@eb_obj)
                   + N' AS ' + QUOTENAME(@eb_alias) + N';';

    PRINT N'';
    PRINT N'===== ' + @EntityName + N' (' + ISNULL(@eb_obj, N'NO BINDING') + N') =====';
    PRINT @ViewSql;

    /* Tenter l execution et capturer l erreur */
    BEGIN TRY
        EXEC sys.sp_executesql @ViewSql;
        PRINT N'>>> OK';
    END TRY
    BEGIN CATCH
        SET @ErrMsg = ERROR_MESSAGE();
        PRINT N'>>> ERREUR ' + CAST(ERROR_NUMBER() AS nvarchar) + N': ' + @ErrMsg;
        /* Afficher les colonnes potentiellement problematiques pour cette entite */
        SELECT
            ecp.ColumnPosition,
            ecp.Column_EN,
            ecp.Column_FR,
            ecp.MapStatus,
            ecp.SourceExpression,
            ecp.FallbackExpression,
            QUOTENAME(ISNULL(ecp.Column_FR, ecp.Column_EN)) AS AliasQuoted
        FROM dic.EntityColumnPublication ecp
        WHERE ecp.EntityName_EN = @EntityName
          AND ecp.IsPublished = 1
          AND (
                QUOTENAME(ISNULL(ecp.Column_FR, ecp.Column_EN)) IS NULL
             OR ecp.SourceExpression LIKE N'%=%'
             OR ecp.FallbackExpression LIKE N'%=%'
             OR (ecp.MapStatus = N'MAPPED' AND ecp.SourceExpression IS NULL)
          )
        ORDER BY ecp.ColumnPosition;
    END CATCH;

    FETCH NEXT FROM cur INTO @EntityName;
END;

CLOSE cur;
DEALLOCATE cur;
