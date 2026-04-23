<#
.SYNOPSIS
    Charge les 3 CSV du dictionnaire SmartBox V6 dans stg.import_dictionary_*.
    Exécution côté client : aucun accès fichier requis du service SQL Server.
    Utilise SqlBulkCopy (protocole TDS) avec l'authentification Windows du DBA.

.PARAMETER Server
    Instance SQL Server (ex: MTMD-SQL01  ou  MTMD-SQL01\INST2019)

.PARAMETER Database
    Base SmartBox cible (ex: SP_SPR_SmartBox)

.PARAMETER CsvPath
    Dossier contenant les 3 CSV.
    Défaut : dossier du script.

.PARAMETER Truncate
    Force la troncature des tables stg.import_* avant chargement,
    indépendamment du paramètre TruncateLoadTablesBeforeCsvImport dans cfg.Settings.

.EXAMPLE
    .\Load-DictionaryCSV.ps1 -Server MTMD-SQL01 -Database SP_SPR_SmartBox
    .\Load-DictionaryCSV.ps1 -Server MTMD-SQL01 -Database SP_SPR_SmartBox -CsvPath "C:\Users\franbreton\Downloads\SPR SmartBox" -Truncate
#>
param(
    [Parameter(Mandatory)][string]$Server,
    [Parameter(Mandatory)][string]$Database,
    [string]$CsvPath  = $PSScriptRoot,
    [switch]$Truncate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Connexion
# ---------------------------------------------------------------------------
$connStr = "Server=$Server;Database=$Database;Integrated Security=SSPI;TrustServerCertificate=True;"
$conn    = New-Object System.Data.SqlClient.SqlConnection($connStr)
try { $conn.Open() }
catch {
    Write-Error "Impossible de se connecter à $Server.$Database : $_"
    exit 1
}
Write-Host "Connecté à $Server / $Database" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Lecture de cfg.Settings
# ---------------------------------------------------------------------------
$cmd = $conn.CreateCommand()
$cmd.CommandText = @"
SELECT SettingKey, ISNULL(SettingValue, N'') AS SettingValue
FROM   cfg.Settings
WHERE  SettingKey IN (
           N'DictionaryFile_ProjectData',
           N'DictionaryFile_Lookups',
           N'DictionaryFile_ProjectDataAlias',
           N'TruncateLoadTablesBeforeCsvImport'
       );
"@
$reader   = $cmd.ExecuteReader()
$settings = @{}
while ($reader.Read()) { $settings[$reader['SettingKey']] = $reader['SettingValue'] }
$reader.Close()

$filePD = if ($settings['DictionaryFile_ProjectData'])        { $settings['DictionaryFile_ProjectData'] }        else { 'Fields_ProjectData_Export.csv' }
$fileLK = if ($settings['DictionaryFile_Lookups'])             { $settings['DictionaryFile_Lookups'] }             else { 'Lookups_ProjectServer_Export.csv' }
$fileAL = if ($settings['DictionaryFile_ProjectDataAlias'])    { $settings['DictionaryFile_ProjectDataAlias'] }    else { 'ProjectData_Alias.csv' }

$doTruncate = $Truncate.IsPresent -or ($settings['TruncateLoadTablesBeforeCsvImport'] -eq '1')

Write-Host "Fichiers attendus :"
Write-Host "  od_fields  : $filePD"
Write-Host "  lookups    : $fileLK"
Write-Host "  alias      : $fileAL"
Write-Host "Troncature   : $doTruncate"
Write-Host "Dossier CSV  : $CsvPath"
Write-Host ""

# ---------------------------------------------------------------------------
# Colonnes SQL cibles (sans LoadedOn qui a un DEFAULT)
# ---------------------------------------------------------------------------
$sqlCols = @{
    'stg.import_dictionary_od_fields'         = @('SourceSystem','EntityName','FieldName','LogicalType','TypeName','IsNullableRaw')
    'stg.import_dictionary_lookup_entries'    = @('LookupTableId','LookupTableName','EntryId','EntryCode','EntryLabel','ParentEntryId','EntityType','CustomFieldId','CustomFieldName','FieldType','SourceSystem')
    'stg.import_dictionary_projectdata_alias' = @('Endpoint_EN','Endpoint_FR','EndpointMatchCountRaw','EndPointMatchStatus','PrimitiveColumnCount_ENRaw','PrimitiveColumnCount_FRRaw','ColumnPositionRaw','Column_EN','Column_FR','ColumnClassification','Kind_EN','TypeName_EN','IsNullable_ENRaw','Kind_FR','TypeName_FR','IsNullable_FRRaw','PositionMatchRaw','TypeMatchRaw','NullabilityMatchRaw','ColumnMatchStatus')
}

# ---------------------------------------------------------------------------
# Fonction : résout le nom de colonne CSV qui correspond à une colonne SQL.
# Essaie dans l'ordre :
#   1. Nom exact
#   2. Nom insensible à la casse
#   3. Nom SQL sans suffixe "Raw" (insensible à la casse)
# ---------------------------------------------------------------------------
function Resolve-CsvHeader {
    param([string[]]$CsvHeaders, [string]$SqlColumn)
    # 1. Exact
    $m = $CsvHeaders | Where-Object { $_ -ceq $SqlColumn }           | Select-Object -First 1
    if ($m) { return $m }
    # 2. Insensible casse
    $m = $CsvHeaders | Where-Object { $_ -ieq $SqlColumn }           | Select-Object -First 1
    if ($m) { return $m }
    # 3. Sans suffixe Raw
    if ($SqlColumn -match 'Raw$') {
        $bare = $SqlColumn -replace 'Raw$', ''
        $m = $CsvHeaders | Where-Object { $_ -ieq $bare }            | Select-Object -First 1
        if ($m) { return $m }
    }
    return $null
}

# ---------------------------------------------------------------------------
# Fonction principale de chargement
# ---------------------------------------------------------------------------
function Load-CsvTable {
    param(
        [System.Data.SqlClient.SqlConnection]$Connection,
        [string]$CsvFile,
        [string]$TableName,
        [string[]]$SqlColumns,
        [bool]$DoTruncate
    )

    if (-not (Test-Path $CsvFile)) {
        Write-Warning "$TableName : fichier introuvable => $CsvFile  (ignore)"
        return 0
    }

    # Troncature
    if ($DoTruncate) {
        $cmdT = $Connection.CreateCommand()
        $cmdT.CommandText = "TRUNCATE TABLE $TableName;"
        $cmdT.ExecuteNonQuery() | Out-Null
    }

    # Lecture CSV (UTF-8 avec ou sans BOM)
    $rows = Import-Csv -Path $CsvFile -Encoding UTF8
    if ($rows.Count -eq 0) {
        Write-Host "$TableName : CSV vide, rien charge." -ForegroundColor Yellow
        return 0
    }

    $csvHeaders = $rows[0].PSObject.Properties.Name

    # Construire le mapping : colSQL -> colCSV
    $resolved = [ordered]@{}
    $missing  = @()
    foreach ($sqlCol in $SqlColumns) {
        $csvHeader = Resolve-CsvHeader -CsvHeaders $csvHeaders -SqlColumn $sqlCol
        if ($csvHeader) {
            $resolved[$sqlCol] = $csvHeader
        } else {
            $missing += $sqlCol
        }
    }

    if ($missing.Count -gt 0) {
        Write-Warning "$TableName : colonnes SQL sans équivalent CSV (seront NULL) : $($missing -join ', ')"
    }

    # Construire DataTable
    $dt = New-Object System.Data.DataTable
    foreach ($sqlCol in $SqlColumns) { $dt.Columns.Add($sqlCol, [string]) | Out-Null }

    foreach ($row in $rows) {
        $dr = $dt.NewRow()
        foreach ($sqlCol in $SqlColumns) {
            if ($resolved.Contains($sqlCol)) {
                $val = $row.($resolved[$sqlCol])
                $dr[$sqlCol] = if ([string]::IsNullOrEmpty($val)) { [DBNull]::Value } else { $val }
            } else {
                $dr[$sqlCol] = [DBNull]::Value
            }
        }
        $dt.Rows.Add($dr) | Out-Null
    }

    # SqlBulkCopy
    $bulk = New-Object System.Data.SqlClient.SqlBulkCopy($Connection)
    $bulk.DestinationTableName = $TableName
    $bulk.BatchSize            = 1000
    $bulk.BulkCopyTimeout      = 300
    foreach ($sqlCol in $SqlColumns) {
        $bulk.ColumnMappings.Add($sqlCol, $sqlCol) | Out-Null
    }

    try {
        $bulk.WriteToServer($dt)
        Write-Host "$TableName : $($dt.Rows.Count) lignes chargees." -ForegroundColor Green
        return $dt.Rows.Count
    } catch {
        Write-Error "$TableName : erreur SqlBulkCopy => $_"
        return 0
    } finally {
        $bulk.Close()
    }
}

# ---------------------------------------------------------------------------
# Chargement des 3 tables
# ---------------------------------------------------------------------------
$totalRows = 0

$totalRows += Load-CsvTable `
    -Connection $conn `
    -CsvFile    (Join-Path $CsvPath $filePD) `
    -TableName  'stg.import_dictionary_od_fields' `
    -SqlColumns $sqlCols['stg.import_dictionary_od_fields'] `
    -DoTruncate $doTruncate

$totalRows += Load-CsvTable `
    -Connection $conn `
    -CsvFile    (Join-Path $CsvPath $fileLK) `
    -TableName  'stg.import_dictionary_lookup_entries' `
    -SqlColumns $sqlCols['stg.import_dictionary_lookup_entries'] `
    -DoTruncate $doTruncate

$totalRows += Load-CsvTable `
    -Connection $conn `
    -CsvFile    (Join-Path $CsvPath $fileAL) `
    -TableName  'stg.import_dictionary_projectdata_alias' `
    -SqlColumns $sqlCols['stg.import_dictionary_projectdata_alias'] `
    -DoTruncate $doTruncate

$conn.Close()

Write-Host ""
Write-Host "Chargement terminé. Total lignes inserees : $totalRows" -ForegroundColor Cyan
Write-Host "Prochaine etape : exécuter v6_05a_Load_Dictionary_From_LoadTables.sql dans SSMS."
