$conn = New-Object System.Data.SqlClient.SqlConnection(
    "Server=sdevl01-sd2215\sd2215;Database=SPR;Integrated Security=SSPI;TrustServerCertificate=True;")
$conn.Open()

# Generer le SQL via sp_executesql qui retourne la valeur dans un resultset
$cmd = $conn.CreateCommand()
$cmd.CommandTimeout = 60
$cmd.CommandText = @"
/* Genere et retourne le SQL de la vue Projects sans l'executer */
DECLARE @PwaLanguage   nvarchar(10) = N'FR';
DECLARE @EntityName_EN nvarchar(256)= N'Projects';
DECLARE @ColList       nvarchar(max);
DECLARE @eb_schema     sysname;
DECLARE @eb_obj        nvarchar(256);
DECLARE @eb_alias      nvarchar(60);

SELECT @eb_schema = SmartBoxSchemaName,
       @eb_obj    = PsseObjectName,
       @eb_alias  = BindingAlias
FROM dic.EntityBinding
WHERE EntityName_EN = @EntityName_EN AND IsActive = 1;

SELECT @ColList = STRING_AGG(
    CONVERT(nvarchar(max),
        CASE
            WHEN ecp.MapStatus = N'MAPPED' AND ecp.SourceExpression IS NOT NULL
                THEN ecp.SourceExpression + N' AS '
                     + QUOTENAME(CASE WHEN @PwaLanguage = N'FR'
                                      THEN ISNULL(ecp.Column_FR, ecp.Column_EN)
                                      ELSE ecp.Column_EN END)
            WHEN ecp.MapStatus = N'UNMAPPED' AND ecp.FallbackExpression IS NOT NULL
                THEN ecp.FallbackExpression + N' AS '
                     + QUOTENAME(CASE WHEN @PwaLanguage = N'FR'
                                      THEN ISNULL(ecp.Column_FR, ecp.Column_EN)
                                      ELSE ecp.Column_EN END)
            ELSE N'CAST(NULL AS nvarchar(255)) AS '
                 + QUOTENAME(CASE WHEN @PwaLanguage = N'FR'
                                  THEN ISNULL(ecp.Column_FR, ecp.Column_EN)
                                  ELSE ecp.Column_EN END)
        END
    ),
    N',' + CHAR(10) + N'    '
) WITHIN GROUP (ORDER BY ecp.ColumnPosition)
FROM dic.EntityColumnPublication ecp
WHERE ecp.EntityName_EN = @EntityName_EN AND ecp.IsPublished = 1;

SELECT
    N'CREATE OR ALTER VIEW [ProjectData].[' + @EntityName_EN + N'] AS' + CHAR(10)
    + N'SELECT' + CHAR(10)
    + N'    ' + ISNULL(@ColList, N'/* ColList NULL */') + CHAR(10)
    + N'FROM '
    + ISNULL(QUOTENAME(@eb_schema) + N'.' + QUOTENAME(@eb_obj) + N' AS ' + QUOTENAME(@eb_alias),
             N'/* FROM NULL */') + N';'
    AS GeneratedSQL;
"@

$reader = $cmd.ExecuteReader()
if ($reader.Read()) {
    $sql = $reader.GetValue(0).ToString()
    $reader.Close()

    # Sauvegarder dans un fichier pour inspection
    $outFile = "C:\Users\franbreton\Downloads\SPR SmartBox\_debug_projects_view.sql"
    [System.IO.File]::WriteAllText($outFile, $sql, [System.Text.Encoding]::UTF8)
    Write-Host "SQL genere sauvegarde dans : $outFile" -ForegroundColor Green
    Write-Host "Longueur : $($sql.Length) caracteres"

    # Chercher les '=' suspects (hors contexte CAST, commentaires, brackets)
    # Un '=' valide dans ce contexte est uniquement dans CAST(NULL AS type)
    # Un '=' invalide serait hors bracket et hors CAST...AS
    $lines = $sql -split "`n"
    $lineNum = 0
    foreach ($line in $lines) {
        $lineNum++
        if ($line -match '=') {
            # Verifier si c'est dans CAST...AS (normal) ou dans un bracket (normal)
            # Signaler si '=' est visible hors brackets
            $stripped = $line -replace '\[[^\]]*\]', ''  # retire le contenu des brackets
            if ($stripped -match '=') {
                Write-Host "Ligne $lineNum contient '=' hors brackets : $line" -ForegroundColor Yellow
            }
        }
    }
} else {
    $reader.Close()
    Write-Host "Aucun resultset retourne — verifier les donnees." -ForegroundColor Red
}

# Idem pour Assignments
$cmd2 = $conn.CreateCommand()
$cmd2.CommandTimeout = 60
$cmd2.CommandText = @"
DECLARE @PwaLanguage   nvarchar(10)  = N'FR';
DECLARE @EntityName_EN nvarchar(256) = N'Assignments';
DECLARE @ColList       nvarchar(max);
DECLARE @eb_schema     sysname;
DECLARE @eb_obj        nvarchar(256);
DECLARE @eb_alias      nvarchar(60);

SELECT @eb_schema = SmartBoxSchemaName, @eb_obj = PsseObjectName, @eb_alias = BindingAlias
FROM dic.EntityBinding WHERE EntityName_EN = @EntityName_EN AND IsActive = 1;

SELECT @ColList = STRING_AGG(
    CONVERT(nvarchar(max),
        CASE
            WHEN ecp.MapStatus = N'MAPPED' AND ecp.SourceExpression IS NOT NULL
                THEN ecp.SourceExpression + N' AS '
                     + QUOTENAME(CASE WHEN @PwaLanguage = N'FR' THEN ISNULL(ecp.Column_FR, ecp.Column_EN) ELSE ecp.Column_EN END)
            WHEN ecp.MapStatus = N'UNMAPPED' AND ecp.FallbackExpression IS NOT NULL
                THEN ecp.FallbackExpression + N' AS '
                     + QUOTENAME(CASE WHEN @PwaLanguage = N'FR' THEN ISNULL(ecp.Column_FR, ecp.Column_EN) ELSE ecp.Column_EN END)
            ELSE N'CAST(NULL AS nvarchar(255)) AS '
                 + QUOTENAME(CASE WHEN @PwaLanguage = N'FR' THEN ISNULL(ecp.Column_FR, ecp.Column_EN) ELSE ecp.Column_EN END)
        END
    ),
    N',' + CHAR(10) + N'    '
) WITHIN GROUP (ORDER BY ecp.ColumnPosition)
FROM dic.EntityColumnPublication ecp
WHERE ecp.EntityName_EN = @EntityName_EN AND ecp.IsPublished = 1;

SELECT N'CREATE OR ALTER VIEW [ProjectData].[Assignments] AS' + CHAR(10)
    + N'SELECT' + CHAR(10) + N'    ' + ISNULL(@ColList, N'/* NULL */') + CHAR(10)
    + N'FROM ' + ISNULL(QUOTENAME(@eb_schema)+N'.'+QUOTENAME(@eb_obj)+N' AS '+QUOTENAME(@eb_alias), N'/* NULL */') + N';'
    AS GeneratedSQL;
"@
$r2 = $cmd2.ExecuteReader()
if ($r2.Read()) {
    $sql2 = $r2.GetValue(0).ToString()
    $r2.Close()
    $out2 = "C:\Users\franbreton\Downloads\SPR SmartBox\_debug_assignments_view.sql"
    [System.IO.File]::WriteAllText($out2, $sql2, [System.Text.Encoding]::UTF8)
    Write-Host "`nSQL Assignments sauvegarde dans : $out2 ($($sql2.Length) chars)" -ForegroundColor Green
    $lines2 = $sql2 -split "`n"
    $n = 0
    foreach ($line in $lines2) {
        $n++
        if ($line -match '=') {
            $stripped = $line -replace '\[[^\]]*\]', ''
            if ($stripped -match '=') {
                Write-Host "Ligne $n '=' hors brackets : $line" -ForegroundColor Yellow
            }
        }
    }
} else { $r2.Close(); Write-Host "Assignments: aucun resultset." -ForegroundColor Red }

$conn.Close()
Write-Host "`nFait. Ouvrir les fichiers _debug_*_view.sql dans VS Code pour inspection complete." -ForegroundColor Cyan
