$conn = New-Object System.Data.SqlClient.SqlConnection(
    "Server=sdevl01-sd2215\sd2215;Database=SPR;Integrated Security=SSPI;TrustServerCertificate=True;")
$conn.Open()

function Query($sql) {
    $cmd = $conn.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = 60
    $dt  = New-Object System.Data.DataTable
    $dt.Load($cmd.ExecuteReader())
    return $dt
}

# Reproduire exactement la logique de v6_07a pour Projects et Assignments
$entities = @('Projects', 'Assignments', 'Risks')

foreach ($entity in $entities) {
    Write-Host "`n=== $entity ===" -ForegroundColor Cyan

    # Binding
    $bind = Query "
        SELECT PsseObjectName, SmartBoxSchemaName, BindingAlias
        FROM dic.EntityBinding WHERE EntityName_EN = '$entity' AND IsActive = 1;"
    if ($bind.Rows.Count -eq 0) { Write-Host "Pas de binding."; continue }
    $psseObj   = $bind.Rows[0]['PsseObjectName']
    $smSchema  = $bind.Rows[0]['SmartBoxSchemaName']
    $alias     = $bind.Rows[0]['BindingAlias']
    $fromClause = "[$smSchema].[$psseObj] AS [$alias]"

    # ColList FR (meme logique que v6_07a)
    $colRows = Query "
        SELECT
            ecp.ColumnPosition,
            ecp.Column_EN,
            ecp.Column_FR,
            ecp.MapStatus,
            ecp.SourceExpression,
            ecp.FallbackExpression,
            CASE
                WHEN ecp.MapStatus = 'MAPPED' AND ecp.SourceExpression IS NOT NULL
                    THEN ecp.SourceExpression + ' AS ' + QUOTENAME(ISNULL(ecp.Column_FR, ecp.Column_EN))
                WHEN ecp.MapStatus = 'UNMAPPED' AND ecp.FallbackExpression IS NOT NULL
                    THEN ecp.FallbackExpression + ' AS ' + QUOTENAME(ISNULL(ecp.Column_FR, ecp.Column_EN))
                ELSE
                    'CAST(NULL AS nvarchar(255)) AS ' + QUOTENAME(ISNULL(ecp.Column_FR, ecp.Column_EN))
            END AS ColExpr
        FROM dic.EntityColumnPublication ecp
        WHERE ecp.EntityName_EN = '$entity' AND ecp.IsPublished = 1
        ORDER BY ecp.ColumnPosition;"

    # Chercher les ColExpr problematiques (NULL ou contenant '=')
    $bad = $colRows | Where-Object { $_.ColExpr -eq [DBNull]::Value -or ($_.ColExpr -ne [DBNull]::Value -and $_.ColExpr.ToString() -match '(?<!\[)[=](?![^\[]*\])') }
    if ($bad) {
        Write-Host "COLONNES PROBLEMATIQUES :" -ForegroundColor Red
        $bad | Select-Object ColumnPosition, Column_EN, MapStatus, SourceExpression, FallbackExpression, ColExpr | Format-Table -AutoSize
    }

    # Montrer les 3 premieres et 3 dernieres colonnes du ColList
    $colExprs = $colRows | Where-Object { $_.ColExpr -ne [DBNull]::Value } | ForEach-Object { $_.ColExpr }
    $sample = ($colExprs | Select-Object -First 3) + @('    ...') + ($colExprs | Select-Object -Last 3)
    Write-Host "Extrait ColList FR :"
    $sample | ForEach-Object { Write-Host "  $_" }

    # Generer le SQL complet et afficher les 30 premiers caracteres autour d'un '='
    $colList = $colExprs -join ",`n    "
    $viewSql = "CREATE OR ALTER VIEW [ProjectData].[$entity] AS`nSELECT`n    $colList`nFROM $fromClause;"

    # Chercher '=' hors brackets dans le SQL
    $matches = [regex]::Matches($viewSql, '(?<![<>!])=(?!=)')
    $suspicious = $matches | Where-Object {
        $pos = $_.Index
        # verifier si c'est dans un bracket [...]
        $before = $viewSql.Substring([Math]::Max(0, $pos-50), [Math]::Min(50,$pos))
        $openBracket  = ($before.ToCharArray() | Where-Object { $_ -eq '[' }).Count
        $closeBracket = ($before.ToCharArray() | Where-Object { $_ -eq ']' }).Count
        $openBracket -gt $closeBracket  # inside brackets — skip
    }
    if ($suspicious.Count -gt 0) {
        Write-Host "`nSigne '=' suspect hors brackets :" -ForegroundColor Yellow
        foreach ($m in $suspicious | Select-Object -First 5) {
            $ctx = $viewSql.Substring([Math]::Max(0,$m.Index-40), [Math]::Min(80, $viewSql.Length-[Math]::Max(0,$m.Index-40)))
            Write-Host "  ...${ctx}..."
        }
    } else {
        Write-Host "`nAucun '=' suspect hors brackets detecte dans le SQL genere." -ForegroundColor Green
    }

    # Pour Risks : montrer les JoinClauses
    if ($entity -eq 'Risks') {
        $joins = Query "SELECT JoinTag, JoinType, PsseObjectName, JoinAlias, JoinExpression FROM dic.EntityJoin WHERE EntityName_EN = 'Risks' AND IsActive = 1;"
        Write-Host "`nJoins pour Risks :"
        $joins | Format-Table -AutoSize
    }
}

$conn.Close()
