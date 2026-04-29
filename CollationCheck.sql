SET NOCOUNT ON;
GO

/* ======================================================================================
   CollationCheck.sql — Audit de collation complet SmartBox / PSSE
   ---------------------------------------------------------------------------------------
   Périmètre :
     1. Instance SQL (server, tempdb, model, msdb)
     2. Bases impliquées : SPR (SmartBox) + ContentDb (SP_SPR_POC_Contenu)
     3. Colonnes texte ContentDb  — schémas pjpub + pjrep (tables + vues)
     4. Colonnes texte SPR        — toutes les tables SmartBox (dic/cfg/stg/load/log/report)
     5. Vues SmartBox générées    — schémas tbx, tbx_fr, tbx_master, ProjectData
     6. Synonymes SPR             — cibles cross-DB et leur collation
     7. Résumé / matrice de conflits
   ---------------------------------------------------------------------------------------
   Prérequis : exécuter depuis la base SPR.
   cfg.Settings doit contenir ContentDbName.
   ====================================================================================== */

DECLARE @ContentDbName    sysname = NULL;
DECLARE @SmartBoxDb       sysname = DB_NAME();
DECLARE @ExpectedCollation sysname = N'Latin1_General_CI_AS_KS_WS';   /* collation standard SharePoint/PSSE */

SELECT @ContentDbName = NULLIF(LTRIM(RTRIM(SettingValue)), N'')
FROM cfg.Settings WHERE SettingKey = N'ContentDbName';

IF @ContentDbName IS NULL
BEGIN
    RAISERROR(N'cfg.Settings.ContentDbName introuvable — exécuter depuis SPR après v6_03a.', 16, 1);
    RETURN;
END;

DECLARE @DbCollation      sysname = CAST(DATABASEPROPERTYEX(@SmartBoxDb,    N'Collation') AS sysname);
DECLARE @ContentCollation sysname = CAST(DATABASEPROPERTYEX(@ContentDbName, N'Collation') AS sysname);
DECLARE @ServerCollation  sysname = CAST(SERVERPROPERTY(N'Collation')                     AS sysname);
DECLARE @TempDbCollation  sysname = CAST(DATABASEPROPERTYEX(N'tempdb',      N'Collation') AS sysname);
DECLARE @ModelCollation   sysname = CAST(DATABASEPROPERTYEX(N'model',       N'Collation') AS sysname);
DECLARE @MsdbCollation    sysname = CAST(DATABASEPROPERTYEX(N'msdb',        N'Collation') AS sysname);

DECLARE @sql nvarchar(max);

/* ======================================================================================
   SECTION 1 — Collation niveau instance SQL
   ====================================================================================== */
RAISERROR(N'', 0,1) WITH NOWAIT;
RAISERROR(N'══════════════════════════════════════════════════════════', 0,1) WITH NOWAIT;
RAISERROR(N' SECTION 1 : Collation instance SQL + bases système',       0,1) WITH NOWAIT;
RAISERROR(N'══════════════════════════════════════════════════════════', 0,1) WITH NOWAIT;

SELECT
    N'SERVER'  AS Scope, N'(instance)'  AS DatabaseName, @ServerCollation  AS Collation,
    @ExpectedCollation AS Expected,
    CASE WHEN @ServerCollation = @ExpectedCollation THEN N'OK' ELSE N'DIFF' END AS Status
UNION ALL SELECT N'tempdb', N'tempdb', @TempDbCollation, @ExpectedCollation,
    CASE WHEN @TempDbCollation = @ExpectedCollation THEN N'OK' ELSE N'DIFF' END
UNION ALL SELECT N'model',  N'model',  @ModelCollation,  @ExpectedCollation,
    CASE WHEN @ModelCollation  = @ExpectedCollation THEN N'OK' ELSE N'DIFF' END
UNION ALL SELECT N'msdb',   N'msdb',   @MsdbCollation,   @ExpectedCollation,
    CASE WHEN @MsdbCollation   = @ExpectedCollation THEN N'OK' ELSE N'DIFF' END
ORDER BY Scope;

/* ======================================================================================
   SECTION 2 — Collation des bases PSSE + SmartBox impliquées
   ====================================================================================== */
RAISERROR(N'', 0,1) WITH NOWAIT;
RAISERROR(N'══════════════════════════════════════════════════════════', 0,1) WITH NOWAIT;
RAISERROR(N' SECTION 2 : Collation bases SPR et ContentDb',              0,1) WITH NOWAIT;
RAISERROR(N'══════════════════════════════════════════════════════════', 0,1) WITH NOWAIT;

SELECT
    Role,
    DatabaseName,
    Collation,
    @ExpectedCollation                                                     AS Expected,
    CASE WHEN Collation = @ExpectedCollation THEN N'OK' ELSE N'DIFF'  END AS VsExpected,
    CASE WHEN Collation = @ServerCollation   THEN N'OUI' ELSE N'NON' END  AS SameAsServer,
    CASE WHEN Collation = @TempDbCollation   THEN N'OUI' ELSE N'NON' END  AS SameAsTempdb
FROM (VALUES
    (N'SmartBox (SPR)',  @SmartBoxDb,    @DbCollation),
    (N'ContentDb (PSSE)',@ContentDbName, @ContentCollation)
) AS t (Role, DatabaseName, Collation);

/* Alerte conflit entre les deux bases — risque de collation conflict dans les jointures cross-DB */
IF @DbCollation <> @ContentCollation
BEGIN
    DECLARE @ConflictMsg nvarchar(500) =
        N'AVERTISSEMENT : SPR (' + @DbCollation + N') ≠ ContentDb (' + @ContentCollation +
        N'). Les jointures cross-DB sur colonnes texte lèveront des erreurs de collation conflict.';
    RAISERROR(@ConflictMsg, 0, 1) WITH NOWAIT;
END
ELSE
    RAISERROR(N'OK : SPR et ContentDb ont la même collation — pas de risque de conflit cross-DB.', 0, 1) WITH NOWAIT;

/* ======================================================================================
   SECTION 3 — Colonnes texte dans ContentDb (pjpub + pjrep) — tables et vues
   Objectif : détecter les colonnes avec collation explicite ≠ BD ou ≠ attendue
   ====================================================================================== */
RAISERROR(N'', 0,1) WITH NOWAIT;
RAISERROR(N'══════════════════════════════════════════════════════════', 0,1) WITH NOWAIT;
RAISERROR(N' SECTION 3 : Colonnes ContentDb (pjpub/pjrep) — conflits',  0,1) WITH NOWAIT;
RAISERROR(N'══════════════════════════════════════════════════════════', 0,1) WITH NOWAIT;

SET @sql = N'
SELECT
    s.name                   AS SchemaName,
    o.name                   AS ObjectName,
    CASE WHEN o.type = ''U'' THEN ''TABLE'' WHEN o.type = ''V'' THEN ''VUE'' ELSE o.type END AS ObjectType,
    c.name                   AS ColumnName,
    ty.name                  AS DataType,
    c.max_length             AS MaxLength,
    c.collation_name         AS ColumnCollation,
    N''' + @ContentCollation + N'''  AS DbCollation,
    N''' + @ExpectedCollation + N''' AS Expected,
    CASE
        WHEN c.collation_name = N''' + @ExpectedCollation + N''' THEN N''OK''
        WHEN c.collation_name = N''' + @ContentCollation  + N''' THEN N''OK (hérite BD)''
        ELSE N''DIFF''
    END                      AS Status
FROM [' + @ContentDbName + N'].sys.all_columns c
JOIN [' + @ContentDbName + N'].sys.all_objects o
    ON  o.object_id     = c.object_id
    AND o.type          IN (N''U'', N''V'')
JOIN [' + @ContentDbName + N'].sys.schemas s
    ON  s.schema_id     = o.schema_id
    AND s.name          IN (N''pjpub'', N''pjrep'')
JOIN [' + @ContentDbName + N'].sys.types ty
    ON  ty.user_type_id = c.user_type_id
WHERE c.collation_name IS NOT NULL
  AND c.collation_name <> N''' + @ContentCollation  + N'''
ORDER BY s.name, o.type DESC, o.name, c.column_id;';

EXEC sp_executesql @sql;

/* Comptage */
SET @sql = N'
SELECT COUNT(*) AS NbColonnesHorsCollation_ContentDb
FROM [' + @ContentDbName + N'].sys.all_columns c
JOIN [' + @ContentDbName + N'].sys.all_objects o  ON o.object_id = c.object_id AND o.type IN (N''U'',N''V'')
JOIN [' + @ContentDbName + N'].sys.schemas    s   ON s.schema_id = o.schema_id AND s.name IN (N''pjpub'',N''pjrep'')
WHERE c.collation_name IS NOT NULL
  AND c.collation_name <> N''' + @ContentCollation + N''';';
EXEC sp_executesql @sql;

/* ======================================================================================
   SECTION 4 — Colonnes texte dans SPR (toutes les tables SmartBox)
   ====================================================================================== */
RAISERROR(N'', 0,1) WITH NOWAIT;
RAISERROR(N'══════════════════════════════════════════════════════════', 0,1) WITH NOWAIT;
RAISERROR(N' SECTION 4 : Colonnes SPR (tables SmartBox) — conflits',    0,1) WITH NOWAIT;
RAISERROR(N'══════════════════════════════════════════════════════════', 0,1) WITH NOWAIT;

SELECT
    s.name                   AS SchemaName,
    t.name                   AS TableName,
    c.name                   AS ColumnName,
    ty.name                  AS DataType,
    c.max_length             AS MaxLength,
    c.collation_name         AS ColumnCollation,
    @DbCollation             AS DbCollation,
    @ExpectedCollation       AS Expected,
    CASE
        WHEN c.collation_name = @ExpectedCollation THEN N'OK'
        WHEN c.collation_name = @DbCollation       THEN N'OK (hérite BD)'
        ELSE N'DIFF'
    END                      AS Status
FROM sys.columns c
JOIN sys.tables  t  ON t.object_id    = c.object_id
JOIN sys.schemas s  ON s.schema_id    = t.schema_id
JOIN sys.types   ty ON ty.user_type_id = c.user_type_id
WHERE c.collation_name IS NOT NULL
  AND c.collation_name <> @DbCollation
ORDER BY s.name, t.name, c.column_id;

SELECT COUNT(*) AS NbColonnesHorsCollation_SPR
FROM sys.columns c
JOIN sys.tables  t ON t.object_id = c.object_id
WHERE c.collation_name IS NOT NULL
  AND c.collation_name <> @DbCollation;

/* ======================================================================================
   SECTION 5 — Vues générées SmartBox (tbx, tbx_fr, tbx_master, ProjectData)
               Détection des clauses COLLATE explicites dans les définitions SQL
   ====================================================================================== */
RAISERROR(N'', 0,1) WITH NOWAIT;
RAISERROR(N'══════════════════════════════════════════════════════════', 0,1) WITH NOWAIT;
RAISERROR(N' SECTION 5 : Vues SmartBox — clauses COLLATE explicites',   0,1) WITH NOWAIT;
RAISERROR(N'══════════════════════════════════════════════════════════', 0,1) WITH NOWAIT;

/* Vues avec COLLATE dans leur définition SQL (indique un workaround existant ou une anomalie) */
SELECT
    s.name                   AS SchemaName,
    v.name                   AS ViewName,
    CASE
        WHEN sm.definition LIKE N'%COLLATE ' + @ExpectedCollation + N'%'
            THEN N'COLLATE attendu présent'
        WHEN sm.definition LIKE N'%COLLATE%'
            THEN N'COLLATE présent (autre)'
        ELSE N'Pas de COLLATE explicite'
    END                      AS CollateStatus,
    OBJECT_NAME(v.object_id) AS ObjectName
FROM sys.views v
JOIN sys.schemas s
    ON  s.schema_id = v.schema_id
    AND s.name      IN (N'tbx', N'tbx_fr', N'tbx_master', N'ProjectData')
JOIN sys.sql_modules sm
    ON  sm.object_id = v.object_id
ORDER BY s.name, v.name;

SELECT
    s.name                              AS SchemaName,
    COUNT(*)                            AS NbVues,
    SUM(CASE WHEN sm.definition LIKE N'%COLLATE%' THEN 1 ELSE 0 END) AS NbVuesAvecCollate,
    SUM(CASE WHEN sm.definition NOT LIKE N'%COLLATE%' THEN 1 ELSE 0 END) AS NbVuesSansCollate
FROM sys.views v
JOIN sys.schemas s   ON s.schema_id = v.schema_id AND s.name IN (N'tbx',N'tbx_fr',N'tbx_master',N'ProjectData')
JOIN sys.sql_modules sm ON sm.object_id = v.object_id
GROUP BY s.name
ORDER BY s.name;

/* ======================================================================================
   SECTION 6 — Synonymes SPR : cibles cross-DB et collation de la BD cible
   ====================================================================================== */
RAISERROR(N'', 0,1) WITH NOWAIT;
RAISERROR(N'══════════════════════════════════════════════════════════', 0,1) WITH NOWAIT;
RAISERROR(N' SECTION 6 : Synonymes SPR — cibles cross-DB',              0,1) WITH NOWAIT;
RAISERROR(N'══════════════════════════════════════════════════════════', 0,1) WITH NOWAIT;

/* Inventaire des synonymes avec la collation de la BD cible */
SELECT
    s.name                   AS SchemaName,
    sy.name                  AS SynonymName,
    sy.base_object_name      AS TargetFullName,
    /* Extraire le nom de la BD cible (segment entre les premiers crochets) */
    CASE
        WHEN sy.base_object_name LIKE N'[[]%'
            THEN REPLACE(SUBSTRING(sy.base_object_name, 2,
                         CHARINDEX(N']', sy.base_object_name, 2) - 2), N']', N'')
        ELSE PARSENAME(sy.base_object_name, 4)
    END                      AS TargetDatabase,
    CAST(DATABASEPROPERTYEX(
        CASE
            WHEN sy.base_object_name LIKE N'[[]%'
                THEN REPLACE(SUBSTRING(sy.base_object_name, 2,
                             CHARINDEX(N']', sy.base_object_name, 2) - 2), N']', N'')
            ELSE PARSENAME(sy.base_object_name, 4)
        END, N'Collation') AS sysname)     AS TargetCollation,
    @DbCollation             AS SprCollation,
    CASE
        WHEN CAST(DATABASEPROPERTYEX(
                CASE WHEN sy.base_object_name LIKE N'[[]%'
                     THEN REPLACE(SUBSTRING(sy.base_object_name,2,
                          CHARINDEX(N']',sy.base_object_name,2)-2),N']',N'')
                     ELSE PARSENAME(sy.base_object_name,4) END,
             N'Collation') AS sysname) = @DbCollation
        THEN N'OK'
        WHEN CAST(DATABASEPROPERTYEX(
                CASE WHEN sy.base_object_name LIKE N'[[]%'
                     THEN REPLACE(SUBSTRING(sy.base_object_name,2,
                          CHARINDEX(N']',sy.base_object_name,2)-2),N']',N'')
                     ELSE PARSENAME(sy.base_object_name,4) END,
             N'Collation') AS sysname) IS NULL
        THEN N'BD INACCESSIBLE'
        ELSE N'DIFF'
    END                      AS ConflictStatus
FROM sys.synonyms sy
JOIN sys.schemas  s   ON s.schema_id = sy.schema_id
ORDER BY ConflictStatus DESC, s.name, sy.name;

/* Résumé par BD cible */
SELECT
    CASE
        WHEN sy.base_object_name LIKE N'[[]%'
            THEN REPLACE(SUBSTRING(sy.base_object_name, 2,
                         CHARINDEX(N']', sy.base_object_name, 2) - 2), N']', N'')
        ELSE PARSENAME(sy.base_object_name, 4)
    END                  AS TargetDatabase,
    CAST(DATABASEPROPERTYEX(
        CASE WHEN sy.base_object_name LIKE N'[[]%'
             THEN REPLACE(SUBSTRING(sy.base_object_name,2,
                  CHARINDEX(N']',sy.base_object_name,2)-2),N']',N'')
             ELSE PARSENAME(sy.base_object_name,4) END,
        N'Collation') AS sysname)  AS TargetCollation,
    COUNT(*)             AS NbSynonymes,
    CASE
        WHEN CAST(DATABASEPROPERTYEX(
                CASE WHEN sy.base_object_name LIKE N'[[]%'
                     THEN REPLACE(SUBSTRING(sy.base_object_name,2,
                          CHARINDEX(N']',sy.base_object_name,2)-2),N']',N'')
                     ELSE PARSENAME(sy.base_object_name,4) END,
             N'Collation') AS sysname) = @DbCollation
        THEN N'OK'
        ELSE N'DIFF — risque collation conflict'
    END                  AS Status
FROM sys.synonyms sy
GROUP BY
    CASE WHEN sy.base_object_name LIKE N'[[]%'
         THEN REPLACE(SUBSTRING(sy.base_object_name,2,
              CHARINDEX(N']',sy.base_object_name,2)-2),N']',N'')
         ELSE PARSENAME(sy.base_object_name,4) END
ORDER BY Status DESC;

/* ======================================================================================
   SECTION 7 — Résumé général / matrice de conformité
   ====================================================================================== */
RAISERROR(N'', 0,1) WITH NOWAIT;
RAISERROR(N'══════════════════════════════════════════════════════════', 0,1) WITH NOWAIT;
RAISERROR(N' SECTION 7 : Résumé — matrice de conformité',               0,1) WITH NOWAIT;
RAISERROR(N'══════════════════════════════════════════════════════════', 0,1) WITH NOWAIT;

SELECT
    Scope,
    Collation,
    VsExpected,
    VsSPR,
    VsContentDb,
    VsServer,
    VsTempdb,
    Risque
FROM (VALUES
    (N'SPR (SmartBox)',   @DbCollation,
        CASE WHEN @DbCollation = @ExpectedCollation THEN N'OK' ELSE N'DIFF' END,
        N'—',
        CASE WHEN @DbCollation = @ContentCollation  THEN N'OK' ELSE N'DIFF ⚠' END,
        CASE WHEN @DbCollation = @ServerCollation   THEN N'OK' ELSE N'DIFF' END,
        CASE WHEN @DbCollation = @TempDbCollation   THEN N'OK' ELSE N'DIFF' END,
        CASE WHEN @DbCollation <> @ContentCollation
             THEN N'CRITIQUE — cross-DB joins sur texte échoueront'
             WHEN @DbCollation <> @TempDbCollation
             THEN N'MOYEN — tables temporaires peuvent conflictuer'
             ELSE N'Aucun' END),
    (N'ContentDb (PSSE)', @ContentCollation,
        CASE WHEN @ContentCollation = @ExpectedCollation THEN N'OK' ELSE N'DIFF' END,
        CASE WHEN @ContentCollation = @DbCollation       THEN N'OK' ELSE N'DIFF ⚠' END,
        N'—',
        CASE WHEN @ContentCollation = @ServerCollation   THEN N'OK' ELSE N'DIFF' END,
        CASE WHEN @ContentCollation = @TempDbCollation   THEN N'OK' ELSE N'DIFF' END,
        CASE WHEN @ContentCollation <> @ExpectedCollation
             THEN N'MOYEN — collation non standard PSSE'
             ELSE N'Aucun' END),
    (N'Server',  @ServerCollation,
        CASE WHEN @ServerCollation = @ExpectedCollation THEN N'OK' ELSE N'DIFF' END,
        CASE WHEN @ServerCollation = @DbCollation       THEN N'OK' ELSE N'DIFF' END,
        CASE WHEN @ServerCollation = @ContentCollation  THEN N'OK' ELSE N'DIFF' END,
        N'—',
        CASE WHEN @ServerCollation = @TempDbCollation   THEN N'OK' ELSE N'DIFF' END,
        CASE WHEN @ServerCollation <> @ExpectedCollation
             THEN N'INFO — nouvelles BDs héritent d''une collation non standard'
             ELSE N'Aucun' END),
    (N'tempdb',  @TempDbCollation,
        CASE WHEN @TempDbCollation = @ExpectedCollation THEN N'OK' ELSE N'DIFF' END,
        CASE WHEN @TempDbCollation = @DbCollation       THEN N'OK' ELSE N'DIFF' END,
        CASE WHEN @TempDbCollation = @ContentCollation  THEN N'OK' ELSE N'DIFF' END,
        CASE WHEN @TempDbCollation = @ServerCollation   THEN N'OK' ELSE N'DIFF' END,
        N'—',
        CASE WHEN @TempDbCollation <> @DbCollation
             THEN N'MOYEN — #tables temporaires peuvent conflictuer avec SPR'
             ELSE N'Aucun' END),
    (N'model',   @ModelCollation,
        CASE WHEN @ModelCollation = @ExpectedCollation THEN N'OK' ELSE N'DIFF' END,
        CASE WHEN @ModelCollation = @DbCollation       THEN N'OK' ELSE N'DIFF' END,
        CASE WHEN @ModelCollation = @ContentCollation  THEN N'OK' ELSE N'DIFF' END,
        CASE WHEN @ModelCollation = @ServerCollation   THEN N'OK' ELSE N'DIFF' END,
        CASE WHEN @ModelCollation = @TempDbCollation   THEN N'OK' ELSE N'DIFF' END,
        CASE WHEN @ModelCollation <> @ExpectedCollation
             THEN N'INFO — futures bases héritent d''une collation non standard'
             ELSE N'Aucun' END)
) AS t (Scope, Collation, VsExpected, VsSPR, VsContentDb, VsServer, VsTempdb, Risque)
ORDER BY
    CASE
        WHEN Risque = N'Aucun'       THEN 3
        WHEN Risque LIKE N'INFO%'    THEN 2
        ELSE 1
    END;
GO
