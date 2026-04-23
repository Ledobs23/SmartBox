$conn = New-Object System.Data.SqlClient.SqlConnection(
    "Server=sdevl01-sd2215\sd2215;Database=SPR;Integrated Security=SSPI;TrustServerCertificate=True;")
$conn.Open()
function Q($sql) {
    $cmd = $conn.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = 60
    $dt = New-Object System.Data.DataTable; $dt.Load($cmd.ExecuteReader()); return $dt
}

# 1. Etat IsActive dans dic.EntityBinding
Write-Host "=== dic.EntityBinding IsActive ===" -ForegroundColor Cyan
Q "SELECT EntityName_EN, IsActive, PsseObjectName, SmartBoxSchemaName, BindingAlias, ConfidenceLevel
   FROM dic.EntityBinding ORDER BY EntityName_EN;" | Format-Table -AutoSize

# 2. SQL genere pour Projects — version simple sans filtre IsActive
Write-Host "`n=== ColList brut pour Projects (15 premieres colonnes) ===" -ForegroundColor Cyan
Q "SELECT TOP 15
    ecp.ColumnPosition,
    ecp.Column_EN,
    ecp.Column_FR,
    ecp.MapStatus,
    ecp.IsPublished,
    ecp.SourceExpression,
    LEFT(ecp.FallbackExpression, 40) AS FallbackExpr,
    CASE
        WHEN ecp.MapStatus = 'MAPPED' AND ecp.SourceExpression IS NOT NULL
            THEN ecp.SourceExpression + ' AS ' + QUOTENAME(ISNULL(ecp.Column_FR, ecp.Column_EN))
        WHEN ecp.MapStatus = 'UNMAPPED' AND ecp.FallbackExpression IS NOT NULL
            THEN LEFT(ecp.FallbackExpression,30) + ' AS ' + QUOTENAME(ISNULL(ecp.Column_FR, ecp.Column_EN))
        ELSE 'CAST(NULL AS nvarchar(255)) AS ' + QUOTENAME(ISNULL(ecp.Column_FR, ecp.Column_EN))
    END AS ColExpr
FROM dic.EntityColumnPublication ecp
WHERE ecp.EntityName_EN = 'Projects' AND ecp.IsPublished = 1
ORDER BY ecp.ColumnPosition;" | Format-Table -AutoSize

# 3. PwaLanguage
Write-Host "`n=== PwaLanguage ===" -ForegroundColor Cyan
Q "SELECT SettingKey, SettingValue FROM cfg.Settings WHERE SettingKey = 'PwaLanguage';" | Format-Table

# 4. Generer le SQL complet de la vue Projects et l'afficher
Write-Host "`n=== SQL genere pour ProjectData.Projects ===" -ForegroundColor Cyan
$viewSqlRow = Q "
DECLARE @PwaLanguage nvarchar(10);
SELECT @PwaLanguage = ISNULL(NULLIF(LTRIM(RTRIM(SettingValue)),N''),N'FR')
FROM cfg.Settings WHERE SettingKey = N'PwaLanguage';

DECLARE @ColList nvarchar(max);
SELECT @ColList = STRING_AGG(
    CONVERT(nvarchar(max),
        CASE
            WHEN ecp.MapStatus = 'MAPPED' AND ecp.SourceExpression IS NOT NULL
                THEN ecp.SourceExpression + N' AS ' + QUOTENAME(CASE WHEN @PwaLanguage = N'FR' THEN ISNULL(ecp.Column_FR, ecp.Column_EN) ELSE ecp.Column_EN END)
            WHEN ecp.MapStatus = 'UNMAPPED' AND ecp.FallbackExpression IS NOT NULL
                THEN ecp.FallbackExpression + N' AS ' + QUOTENAME(CASE WHEN @PwaLanguage = N'FR' THEN ISNULL(ecp.Column_FR, ecp.Column_EN) ELSE ecp.Column_EN END)
            ELSE
                N'CAST(NULL AS nvarchar(255)) AS ' + QUOTENAME(CASE WHEN @PwaLanguage = N'FR' THEN ISNULL(ecp.Column_FR, ecp.Column_EN) ELSE ecp.Column_EN END)
        END
    ), N',' + CHAR(10) + N'    '
) WITHIN GROUP (ORDER BY ecp.ColumnPosition)
FROM dic.EntityColumnPublication ecp
WHERE ecp.EntityName_EN = N'Projects' AND ecp.IsPublished = 1;

DECLARE @eb_schema sysname, @eb_obj nvarchar(256), @eb_alias nvarchar(60);
SELECT @eb_schema = SmartBoxSchemaName, @eb_obj = PsseObjectName, @eb_alias = BindingAlias
FROM dic.EntityBinding WHERE EntityName_EN = N'Projects';

SELECT
    N'CREATE OR ALTER VIEW [ProjectData].[Projects] AS' + CHAR(10) +
    N'SELECT' + CHAR(10) +
    N'    ' + @ColList + CHAR(10) +
    N'FROM ' + QUOTENAME(@eb_schema) + N'.' + QUOTENAME(@eb_obj) + N' AS ' + QUOTENAME(@eb_alias) + N';'
    AS GeneratedSQL;"

if ($viewSqlRow.Rows.Count -gt 0) {
    $sql = $viewSqlRow.Rows[0]['GeneratedSQL']
    Write-Host $sql
    # Chercher le signe = hors contexte de bracket
    $eqMatches = [regex]::Matches($sql, '=')
    Write-Host ("`nNombre de '=' dans le SQL genere : " + $eqMatches.Count) -ForegroundColor Yellow
}

$conn.Close()
