$connStr = 'Server=sdevl01-sd2215\sd2215;Database=SPR;Integrated Security=SSPI;TrustServerCertificate=True;'
$sqlFile = 'C:\Users\franbreton\Downloads\SPR SmartBox\_diag_save_viewsql.sql'
$outDir  = 'C:\Users\franbreton\Downloads\SPR SmartBox'

$conn = [System.Data.SqlClient.SqlConnection]::new($connStr)
$conn.Open()

$sql = [IO.File]::ReadAllText($sqlFile, [Text.Encoding]::UTF8)
$cmd = $conn.CreateCommand()
$cmd.CommandText = $sql
$cmd.CommandTimeout = 120

$sb = [System.Text.StringBuilder]::new()
$reader = $cmd.ExecuteReader()

$resultIdx = 0
do {
    $resultIdx++
    if (-not $reader.HasRows) {
        [void]$sb.AppendLine("=== Result set $resultIdx : (empty) ===")
        continue
    }

    $cols = @(0..($reader.FieldCount - 1) | ForEach-Object { $reader.GetName($_) })

    if ($resultIdx -eq 3) {
        # Result set 3 : save each entity SQL to a separate file
        [void]$sb.AppendLine('=== Result set 3 : Generated SQL (saved per entity) ===')
        while ($reader.Read()) {
            $entity  = $reader.GetString(0)
            $viewSql = if ($reader.IsDBNull(1)) { '<NULL>' } else { $reader.GetString(1) }
            $file = "$outDir\_debug_${entity}_view.sql"
            [IO.File]::WriteAllText($file, $viewSql, [Text.Encoding]::UTF8)
            [void]$sb.AppendLine("  Saved: $file  ($($viewSql.Length) chars)")
        }
    } else {
        # Result sets 1 and 2 : tabular output
        [void]$sb.AppendLine("=== Result set $resultIdx : $($cols -join ' | ') ===")
        while ($reader.Read()) {
            $row = @(0..($reader.FieldCount - 1) | ForEach-Object {
                if ($reader.IsDBNull($_)) { 'NULL' } else { $reader.GetValue($_).ToString() }
            })
            [void]$sb.AppendLine($row -join ' | ')
        }
    }
    [void]$sb.AppendLine('')
} while ($reader.NextResult())

$reader.Close()
$conn.Close()

$summaryFile = "$outDir\_debug_diag_summary.txt"
[IO.File]::WriteAllText($summaryFile, $sb.ToString(), [Text.Encoding]::UTF8)
Write-Host "Summary : $summaryFile" -ForegroundColor Cyan
Write-Host 'Ouvrir les fichiers _debug_*_view.sql pour inspecter le SQL genere.' -ForegroundColor Green
