$conn = New-Object System.Data.SqlClient.SqlConnection(
    "Server=sdevl01-sd2215\sd2215;Database=SPR;Integrated Security=SSPI;TrustServerCertificate=True;")
$conn.Open()

function Query($sql) {
    $cmd = $conn.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = 60
    $dt  = New-Object System.Data.DataTable
    $dt.Load($cmd.ExecuteReader())
    return $dt
}

# 1. Distribution MapStatus / IsPublished
Write-Host "=== Distribution dic.EntityColumnPublication ===" -ForegroundColor Cyan
Query @"
SELECT MapStatus, IsPublished, COUNT(*) AS Nb
FROM dic.EntityColumnPublication
GROUP BY MapStatus, IsPublished
ORDER BY MapStatus, IsPublished;
"@ | Format-Table -AutoSize

# 2. SourceExpression NULL pour des colonnes MAPPED
Write-Host "=== MAPPED avec SourceExpression NULL ===" -ForegroundColor Cyan
Query @"
SELECT TOP 20 EntityName_EN, Column_EN, MapStatus, SourceExpression, FallbackExpression
FROM dic.EntityColumnPublication
WHERE MapStatus = 'MAPPED' AND (SourceExpression IS NULL OR SourceExpression = '');
"@ | Format-Table -AutoSize

# 3. FallbackExpression suspecte
Write-Host "=== FallbackExpression non NULL et non CAST ===" -ForegroundColor Cyan
Query @"
SELECT TOP 20 EntityName_EN, Column_EN, MapStatus, FallbackExpression
FROM dic.EntityColumnPublication
WHERE FallbackExpression IS NOT NULL
  AND FallbackExpression NOT LIKE 'CAST(NULL AS%';
"@ | Format-Table -AutoSize

# 4. Colonnes avec = dans SourceExpression ou FallbackExpression
Write-Host "=== Expressions contenant '=' ===" -ForegroundColor Cyan
Query @"
SELECT TOP 20 EntityName_EN, Column_EN, MapStatus, SourceExpression, FallbackExpression
FROM dic.EntityColumnPublication
WHERE SourceExpression LIKE '%=%'
   OR FallbackExpression LIKE '%=%';
"@ | Format-Table -AutoSize

# 5. SQL généré pour Projects (entité en erreur)
Write-Host "=== SQL genere pour Projects (apercu colonnes) ===" -ForegroundColor Cyan
Query @"
SELECT
    ecp.ColumnPosition,
    ecp.Column_EN,
    ecp.Column_FR,
    ecp.MapStatus,
    ecp.IsPublished,
    ecp.SourceExpression,
    ecp.FallbackExpression,
    CASE
        WHEN ecp.MapStatus = 'MAPPED' AND ecp.SourceExpression IS NOT NULL
            THEN ecp.SourceExpression + ' AS ' + QUOTENAME(ecp.Column_EN)
        WHEN ecp.MapStatus = 'UNMAPPED' AND ecp.FallbackExpression IS NOT NULL
            THEN ecp.FallbackExpression + ' AS ' + QUOTENAME(ecp.Column_EN)
        ELSE
            'CAST(NULL AS nvarchar(255)) AS ' + QUOTENAME(ecp.Column_EN)
    END AS ColExpr
FROM dic.EntityColumnPublication ecp
WHERE ecp.EntityName_EN = 'Projects'
  AND ecp.IsPublished = 1
ORDER BY ecp.ColumnPosition;
"@ | Format-Table -AutoSize

# 6. BindingAlias dans dic.EntityBinding pour les entités en erreur
Write-Host "=== dic.EntityBinding pour les entites en erreur ===" -ForegroundColor Cyan
Query @"
SELECT EntityName_EN, PsseSchemaName, PsseObjectName, SmartBoxSchemaName, BindingAlias, ConfidenceLevel
FROM dic.EntityBinding
WHERE EntityName_EN IN ('Assignments','Projects','Resources','Tasks','Risks','AssignmentTimephasedDataSet')
ORDER BY EntityName_EN;
"@ | Format-Table -AutoSize

# 7. Erreur 206 sur Risks : chercher colonnes uniqueidentifier/int en conflit
Write-Host "=== Risks : colonnes MAPPED avec type suspect ===" -ForegroundColor Cyan
Query @"
SELECT ecp.Column_EN, ecp.MapStatus, ecp.SourceExpression, ecp.FallbackExpression,
       ecm.TypeName_EN
FROM dic.EntityColumnPublication ecp
JOIN dic.EntityColumnMap ecm
    ON ecm.EntityName_EN = ecp.EntityName_EN AND ecm.Column_EN = ecp.Column_EN
WHERE ecp.EntityName_EN = 'Risks'
  AND ecp.IsPublished = 1
  AND (ecm.TypeName_EN LIKE '%Guid%' OR ecm.TypeName_EN LIKE '%Int%')
ORDER BY ecp.ColumnPosition;
"@ | Format-Table -AutoSize

$conn.Close()
