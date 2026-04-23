$conn = New-Object System.Data.SqlClient.SqlConnection(
    "Server=sdevl01-sd2215\sd2215;Database=SPR;Integrated Security=SSPI;TrustServerCertificate=True;")
$conn.Open()

$sqlFile = "C:\Users\franbreton\Downloads\SPR SmartBox\_diag_gen_projects.sql"
$sqlText = [IO.File]::ReadAllText($sqlFile, [Text.Encoding]::UTF8)

# Splitter sur GO (au cas ou)
$batches = $sqlText -split '(?im)^\s*GO\s*$'

$allResults = @()
foreach ($batch in $batches) {
    $b = $batch.Trim()
    if ($b -eq '') { continue }
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $b
    $cmd.CommandTimeout = 60
    try {
        $reader = $cmd.ExecuteReader()
        do {
            if ($reader.FieldCount -gt 0) {
                $dt = New-Object System.Data.DataTable
                $dt.Load($reader)
                $allResults += $dt
            }
        } while (-not $reader.IsClosed -and $reader.NextResult())
        if (-not $reader.IsClosed) { $reader.Close() }
    } catch {
        Write-Host "Erreur batch: $_" -ForegroundColor Red
    }
}

$conn.Close()

# Resultat 1 : SQL genere
if ($allResults.Count -ge 1 -and $allResults[0].Rows.Count -gt 0) {
    $generatedSql = $allResults[0].Rows[0]['GeneratedSQL'].ToString()
    $outFile = "C:\Users\franbreton\Downloads\SPR SmartBox\_debug_projects_view.sql"
    [IO.File]::WriteAllText($outFile, $generatedSql, [Text.Encoding]::UTF8)
    Write-Host "SQL genere ($($generatedSql.Length) chars) sauvegarde : $outFile" -ForegroundColor Green

    # Chercher '=' hors brackets dans chaque ligne
    Write-Host "`nLignes suspectes (= hors brackets) :" -ForegroundColor Yellow
    $found = $false
    $n = 0
    foreach ($line in ($generatedSql -split "`n")) {
        $n++
        $stripped = [regex]::Replace($line, '\[[^\]]*\]', '')
        if ($stripped -match '(?<![<>!])=') {
            Write-Host "  L${n}: $line"
            $found = $true
        }
    }
    if (-not $found) { Write-Host "  Aucune." -ForegroundColor Green }
} else {
    Write-Host "Resultset GeneratedSQL vide ou absent." -ForegroundColor Red
}

# Resultat 2 : colonnes problematiques
if ($allResults.Count -ge 2 -and $allResults[1].Rows.Count -gt 0) {
    Write-Host "`nColonnes problematiques :" -ForegroundColor Red
    $allResults[1] | Format-Table -AutoSize
} else {
    Write-Host "`nAucune colonne problematique detectee par le filtre SQL." -ForegroundColor Green
}
