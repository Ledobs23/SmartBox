$conn = New-Object System.Data.SqlClient.SqlConnection(
    "Server=sdevl01-sd2215\sd2215;Database=SPR;Integrated Security=SSPI;TrustServerCertificate=True;")
$conn.Open()

$sql = [IO.File]::ReadAllText(
    "C:\Users\franbreton\Downloads\SPR SmartBox\_diag_gen_projects.sql",
    [Text.Encoding]::UTF8)

$cmd = $conn.CreateCommand()
$cmd.CommandText  = $sql
$cmd.CommandTimeout = 60

$result = $cmd.ExecuteScalar()
$conn.Close()

if ($result -ne $null) {
    $generatedSql = $result.ToString()
    $outFile = "C:\Users\franbreton\Downloads\SPR SmartBox\_debug_projects_view.sql"
    [IO.File]::WriteAllText($outFile, $generatedSql, [Text.Encoding]::UTF8)
    Write-Host "Sauvegarde: $outFile  ($($generatedSql.Length) chars)" -ForegroundColor Green

    # Analyser chaque ligne pour trouver '=' hors brackets
    $n = 0; $found = $false
    foreach ($line in ($generatedSql -split "`n")) {
        $n++
        $stripped = [regex]::Replace($line, '\[[^\]]*\]', 'BRACKET')
        if ($stripped -match '(?<![<>!:A-Za-z])=(?!=)') {
            Write-Host "L$n : $($line.Trim())" -ForegroundColor Yellow
            $found = $true
        }
    }
    if (-not $found) { Write-Host "Aucun '=' suspect detecte." -ForegroundColor Green }
} else {
    Write-Host "ExecuteScalar a retourne NULL — verifier connexion ou requete." -ForegroundColor Red

    # Fallback : tester une requete simple
    $conn2 = New-Object System.Data.SqlClient.SqlConnection(
        "Server=sdevl01-sd2215\sd2215;Database=SPR;Integrated Security=SSPI;TrustServerCertificate=True;")
    $conn2.Open()
    $cmd2 = $conn2.CreateCommand()
    $cmd2.CommandText = "SELECT COUNT(*) FROM dic.EntityBinding WHERE EntityName_EN=N'Projects' AND IsActive=1;"
    $cnt = $cmd2.ExecuteScalar()
    Write-Host "Rows dans dic.EntityBinding pour Projects (IsActive=1): $cnt"
    $cmd3 = $conn2.CreateCommand()
    $cmd3.CommandText = "SELECT COUNT(*) FROM dic.EntityColumnPublication WHERE EntityName_EN=N'Projects' AND IsPublished=1;"
    $cnt2 = $cmd3.ExecuteScalar()
    Write-Host "Rows dans dic.EntityColumnPublication pour Projects (IsPublished=1): $cnt2"
    $conn2.Close()
}
