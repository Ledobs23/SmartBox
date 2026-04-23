/*
    Diagnostic v6_07a — Sauvegarde le SQL génère pour les 6 entités en erreur.
    Retourne 3 result sets :
      1. Bindings + JoinExpressions
      2. Colonnes suspectes (QUOTENAME NULL, SourceExpression avec '=', alias long)
      3. SQL complet de chaque vue (ColListFR + FROM + JOINs)
    Exécuter dans VS Code connecté à SPR. Partager les résultats.
*/
SET NOCOUNT ON;

/* ===== 1. Bindings et JoinExpressions ===== */
SELECT
    eb.EntityName_EN,
    eb.SmartBoxSchemaName,
    eb.PsseObjectName,
    eb.BindingAlias,
    ej.JoinTag,
    ej.JoinExpression,
    ej.JoinStatus,
    ej.PsseObjectName AS JoinTarget
FROM dic.EntityBinding eb
LEFT JOIN dic.EntityJoin ej
    ON ej.EntityName_EN = eb.EntityName_EN
   AND ej.IsActive = 1
WHERE eb.EntityName_EN IN (
    N'Projects', N'Assignments', N'Tasks',
    N'Resources', N'Risks', N'AssignmentTimephasedDataSet')
  AND eb.IsActive = 1
ORDER BY eb.EntityName_EN, ej.JoinTag;

/* ===== 2. Colonnes potentiellement problematiques ===== */
SELECT
    EntityName_EN,
    ColumnPosition,
    Column_EN,
    Column_FR,
    MapStatus,
    SourceExpression,
    FallbackExpression,
    QUOTENAME(ISNULL(Column_FR, Column_EN))             AS AliasQuoted,
    LEN(ISNULL(Column_FR, Column_EN))                   AS AliasLen,
    CASE
        WHEN QUOTENAME(ISNULL(Column_FR, Column_EN)) IS NULL       THEN 'QUOTENAME_NULL'
        WHEN LEN(ISNULL(Column_FR, Column_EN)) > 128               THEN 'ALIAS_TOO_LONG'
        WHEN SourceExpression LIKE N'%=%'                          THEN 'EXPR_HAS_EQUALS'
        WHEN FallbackExpression LIKE N'%=%'                        THEN 'FALLBACK_HAS_EQUALS'
        WHEN MapStatus = N'MAPPED' AND SourceExpression IS NULL     THEN 'MAPPED_NULL_EXPR'
        ELSE 'OK'
    END AS Issue
FROM dic.EntityColumnPublication
WHERE EntityName_EN IN (
    N'Projects', N'Assignments', N'Tasks',
    N'Resources', N'Risks', N'AssignmentTimephasedDataSet')
  AND IsPublished = 1
  AND (
    QUOTENAME(ISNULL(Column_FR, Column_EN)) IS NULL
    OR LEN(ISNULL(Column_FR, Column_EN)) > 128
    OR SourceExpression LIKE N'%=%'
    OR FallbackExpression LIKE N'%=%'
    OR (MapStatus = N'MAPPED' AND SourceExpression IS NULL)
  )
ORDER BY EntityName_EN, ColumnPosition;

/* ===== 3. SQL génère par entité ===== */
SELECT
    eb.EntityName_EN,
    ISNULL(
        N'CREATE OR ALTER VIEW [ProjectData].[' + eb.EntityName_EN + N'] AS' + CHAR(10)
        + N'SELECT' + CHAR(10)
        + N'    ' + ISNULL(col_agg.ColListFR, N'/* ColListFR IS NULL */') + CHAR(10)
        + N'FROM ' + QUOTENAME(eb.SmartBoxSchemaName) + N'.' + QUOTENAME(eb.PsseObjectName)
                   + N' AS ' + QUOTENAME(eb.BindingAlias)
        + ISNULL(CHAR(10) + N'    ' + join_agg.JoinClauses, N'')
        + N';',
        N'<CONCAT_RETURNED_NULL>'
    ) AS GeneratedSQL,
    col_agg.ColListFR,
    join_agg.JoinClauses
FROM dic.EntityBinding eb
CROSS APPLY
(
    SELECT STRING_AGG(
        CONVERT(nvarchar(max),
            CASE
                WHEN ecp.MapStatus IN (N'MAPPED') AND ecp.SourceExpression IS NOT NULL
                    THEN ecp.SourceExpression + N' AS '
                         + ISNULL(QUOTENAME(ISNULL(ecp.Column_FR, ecp.Column_EN)), N'/*QUOTENAME_NULL*/')
                WHEN ecp.MapStatus = N'UNMAPPED' AND ecp.FallbackExpression IS NOT NULL
                    THEN ecp.FallbackExpression + N' AS '
                         + ISNULL(QUOTENAME(ISNULL(ecp.Column_FR, ecp.Column_EN)), N'/*QUOTENAME_NULL*/')
                ELSE
                    N'CAST(NULL AS nvarchar(255)) AS '
                    + ISNULL(QUOTENAME(ISNULL(ecp.Column_FR, ecp.Column_EN)), N'/*QUOTENAME_NULL*/')
            END
        ),
        N',' + CHAR(10) + N'    '
    ) WITHIN GROUP (ORDER BY ecp.ColumnPosition) AS ColListFR
    FROM dic.EntityColumnPublication ecp
    WHERE ecp.EntityName_EN = eb.EntityName_EN
      AND ecp.IsPublished = 1
) AS col_agg
CROSS APPLY
(
    SELECT STRING_AGG(
        CONVERT(nvarchar(max),
            CONCAT(
                ej.JoinType, N' JOIN ',
                QUOTENAME(ej.SmartBoxSchemaName), N'.', QUOTENAME(ej.PsseObjectName),
                N' AS ', QUOTENAME(ej.JoinAlias),
                N' ON ', ISNULL(ej.JoinExpression, N'/* TODO */')
            )
        ),
        CHAR(10) + N'    '
    ) WITHIN GROUP (ORDER BY ej.JoinTag) AS JoinClauses
    FROM dic.EntityJoin ej
    WHERE ej.EntityName_EN = eb.EntityName_EN
      AND ej.IsActive = 1
      AND ej.JoinExpression NOT LIKE N'/* TODO%'
) AS join_agg
WHERE eb.EntityName_EN IN (
    N'Projects', N'Assignments', N'Tasks',
    N'Resources', N'Risks', N'AssignmentTimephasedDataSet')
  AND eb.IsActive = 1
ORDER BY eb.EntityName_EN;
