/* Genere le SQL de la vue Projects en un seul SELECT — aucun DECLARE */
SELECT
    N'CREATE OR ALTER VIEW [ProjectData].[Projects] AS' + CHAR(10)
    + N'SELECT' + CHAR(10)
    + N'    ' + col_agg.ColList + CHAR(10)
    + N'FROM ' + QUOTENAME(eb.SmartBoxSchemaName)
               + N'.' + QUOTENAME(eb.PsseObjectName)
               + N' AS ' + QUOTENAME(eb.BindingAlias) + N';'
    AS GeneratedSQL
FROM dic.EntityBinding AS eb
CROSS APPLY
(
    SELECT STRING_AGG(
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
    ) WITHIN GROUP (ORDER BY ecp.ColumnPosition) AS ColList
    FROM dic.EntityColumnPublication ecp
    WHERE ecp.EntityName_EN = eb.EntityName_EN
      AND ecp.IsPublished = 1
) AS col_agg
WHERE eb.EntityName_EN = N'Projects'
  AND eb.IsActive = 1;
