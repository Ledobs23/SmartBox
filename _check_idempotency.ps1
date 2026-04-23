$base  = 'C:\Users\franbreton\Downloads\SPR SmartBox'
$files = @(
    'v6_02a_Attach_Existing_SmartBox_Database.sql',
    'v6_03a_Create_Foundations.sql',
    'v6_04a_Create_Native_ProjectData_Views.sql',
    'v6_05a_Load_Dictionary_From_LoadTables.sql',
    'v6_06a_Build_EntityColumnPublication.sql',
    'v6_07a_Generate_Views_From_Publication.sql'
)
foreach ($f in $files) {
    $txt  = [IO.File]::ReadAllText("$base\$f", [Text.Encoding]::UTF8)
    $merge   = ([regex]::Matches($txt, '(?i)\bMERGE\b')).Count
    $delete  = ([regex]::Matches($txt, '(?i)\bDELETE\s+FROM\b')).Count
    $corAlt  = ([regex]::Matches($txt, '(?i)CREATE\s+OR\s+ALTER')).Count
    $ifNot   = ([regex]::Matches($txt, '(?i)IF\s+(OBJECT_ID|NOT\s+EXISTS)')).Count
    $drop    = ([regex]::Matches($txt, '(?i)\bDROP\b')).Count
    $truncate= ([regex]::Matches($txt, '(?i)\bTRUNCATE\b')).Count
    Write-Host "$f"
    Write-Host "  MERGE=$merge  DELETE_FROM=$delete  CREATE_OR_ALTER=$corAlt  IF_NOT_EXISTS=$ifNot  DROP=$drop  TRUNCATE=$truncate"

    # Chercher accumulation stg sans nettoyage par RunId
    $runidClean = ([regex]::Matches($txt, '(?i)DELETE.*WHERE.*RunId\s*=\s*@RunId')).Count
    $newid      = ([regex]::Matches($txt, '(?i)\bnewid\(\)')).Count
    Write-Host "  RunId=NEWID()=$newid  DELETE_by_RunId=$runidClean"
    Write-Host ""
}
