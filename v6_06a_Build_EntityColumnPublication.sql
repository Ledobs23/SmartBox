/*=====================================================================================================================
    v6_06a_Build_EntityColumnPublication.sql
    Projet      : SmartBox
    Phase       : 06a - Publication canonique
    Role        : Construire dic.EntityBinding, dic.EntityJoin, dic.EntityColumnPublication
                  et les brouillons stg.EntityJoin_Draft, stg.ODataPsseMap_Draft.
                  Cette couche est la source de vérité pour la génération de vues FR/EN (v6_07a).

    Notes V6
    - Prérequis : v6_05a exécuté (dic.EntityColumnMap, stg.EntitySource_Draft peuplées).
    - Idempotent : rejouable. Les overrides manuels (MapStatus/BindingStatus = MANUAL) sont préservés.
    - dic.EntityBinding    : source PSSE primaire par entité (clause FROM des vues).
    - dic.EntityJoin       : jointures secondaires détectées.
    - dic.EntityColumnPublication : mapping colonne-par-colonne avec expression SQL et fallback.
    - MapStatus : MAPPED | MAPPED_NEEDS_JOIN | UNMAPPED | NAVIGATION
      MAPPED           = PsseColumnName connu, alias de source résolu -> SourceExpression utilisable
      MAPPED_NEEDS_JOIN = PsseColumnName connu mais source secondaire sans jointure définie -> IsPublished=0
      UNMAPPED         = Aucune colonne PSSE correspondante -> FallbackExpression CAST(NULL AS type)
      NAVIGATION       = Colonne non-PRIMITIVE (lien navigationnel OData) -> expression non auto-résolue
    - Langue ciblée par cfg.PWA.Language (FR ou EN) : les deux alias (Column_FR, Column_EN) sont stockés.
    - Journalisation dans log.ScriptExecutionLog et stg.EntityDraftBuildLog.

    Étapes post-publication (après MERGE dic.EntityColumnPublication)
    - ETAPE E2 : Match normalisé (champs custom sans espaces OData vs avec espaces PSSE)
    - ETAPE E3 : Correction jointures TypeName/TypeDescription (Resources j1, Assignments j3)
    - ETAPE E4 : Jointures dérivées complètes (Tasks/Assignments/Projects/Timesheet/TimeSet)
                  Group A  : prefix OData stripping (BusinessDrivers, Engagements, Prioritizations, etc.)
                  Group B  : TimesheetLines jTSLine/jTSLineAppr/jTSClass + renames src
                  Group C  : TimesheetLineActualDataSet jLastChanged
                  Phase G  : Timesheets jTP/jTST (ref externe) + colonnes EndDate/StartDate/Description/StatusDescription
                  Phase H  : TimeSet FiscalPeriodStart/Year → jFP (existant)
                  Phase I  : TimesheetClasses TimesheetClassId → src.ClassUID
                  Phase J  : jProject/jTask pour AssignmentBaselines, TaskBaselines, TaskTimephased, Deliverables, Issues, Risks, ProjectBaselines
                  Phase K  : jResource pour ResourceTimephasedDataSet, ResourceDemandTimephasedDataSet, EngagementsTimephasedDataSet
                  Phase L  : EngagementsTimephasedDataSet renommages OData/PSSE (src direct)
                  Phase M  : Engagements EngagementModifiedDate → src.ModifiedDate
                  Phase N  : ResourceTimephasedDataSet/ResourceDemandTimephasedDataSet jTBD (MSP_TimeByDay → FiscalPeriodId) + ResourceModifiedDate via jResource
                  Projects jPTRI/jWFI/jWFOwner, Assignments jResource/jAssignApplied
    - ETAPE E5 : Marquage jointures SiteId croisées (SITEID_CROSS -> MANUAL_REQUIRED)
                  Fix : [[] pour échapper les crochets dans LIKE (bug SQL Server)
    - ETAPE E6 : Sync retour dic.EntityColumnMap ← dic.EntityColumnPublication
                  RESOLVED_V06A | CONFIRMED_UNMAPPED | NAVIGATION
=====================================================================================================================*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* ===========================================================================================
   LOT 1 : Création des tables si absentes (DDL pur, rejouable)
   =========================================================================================== */

IF OBJECT_ID(N'dic.EntityBinding', N'U') IS NULL
BEGIN
    CREATE TABLE dic.EntityBinding
    (
        EntityBindingId     bigint IDENTITY(1,1) NOT NULL,
        EntityName_EN       nvarchar(256) NOT NULL,
        EntityName_FR       nvarchar(256) NULL,
        PsseSchemaName      sysname NULL,
        PsseObjectName      nvarchar(256) NULL,
        SmartBoxSchemaName  sysname NULL,
        BindingAlias        nvarchar(60)  NOT NULL CONSTRAINT DF_dic_EntityBinding_Alias   DEFAULT(N'src'),
        CoverageScore       decimal(5,2)  NULL,
        ConfidenceLevel     nvarchar(20)  NULL,
        BindingStatus       nvarchar(30)  NOT NULL CONSTRAINT DF_dic_EntityBinding_Status  DEFAULT(N'AUTO_HIGH'),
        IsActive            bit           NOT NULL CONSTRAINT DF_dic_EntityBinding_IsActive DEFAULT(1),
        UpdatedOn           datetime2(0)  NOT NULL CONSTRAINT DF_dic_EntityBinding_Upd     DEFAULT(sysdatetime()),
        UpdatedBy           sysname       NOT NULL CONSTRAINT DF_dic_EntityBinding_UpdBy   DEFAULT(suser_sname()),
        CONSTRAINT PK_dic_EntityBinding PRIMARY KEY (EntityBindingId),
        CONSTRAINT UQ_dic_EntityBinding UNIQUE (EntityName_EN)
    );
END;

IF OBJECT_ID(N'dic.EntityJoin', N'U') IS NULL
BEGIN
    CREATE TABLE dic.EntityJoin
    (
        EntityJoinId        bigint IDENTITY(1,1) NOT NULL,
        EntityName_EN       nvarchar(256) NOT NULL,
        JoinTag             nvarchar(60)  NOT NULL,
        PsseSchemaName      sysname NULL,
        PsseObjectName      nvarchar(256) NULL,
        SmartBoxSchemaName  sysname NULL,
        JoinAlias           nvarchar(60)  NOT NULL,
        JoinType            nvarchar(20)  NOT NULL CONSTRAINT DF_dic_EntityJoin_JoinType  DEFAULT(N'LEFT'),
        JoinExpression      nvarchar(2000) NULL,
        ColumnCoverage      int NULL,
        JoinStatus          nvarchar(30)  NOT NULL CONSTRAINT DF_dic_EntityJoin_Status    DEFAULT(N'PROPOSED'),
        IsActive            bit           NOT NULL CONSTRAINT DF_dic_EntityJoin_IsActive  DEFAULT(1),
        UpdatedOn           datetime2(0)  NOT NULL CONSTRAINT DF_dic_EntityJoin_Upd       DEFAULT(sysdatetime()),
        UpdatedBy           sysname       NOT NULL CONSTRAINT DF_dic_EntityJoin_UpdBy     DEFAULT(suser_sname()),
        CONSTRAINT PK_dic_EntityJoin PRIMARY KEY (EntityJoinId),
        CONSTRAINT UQ_dic_EntityJoin UNIQUE (EntityName_EN, JoinTag)
    );
END;

IF OBJECT_ID(N'dic.EntityColumnPublication', N'U') IS NULL
BEGIN
    CREATE TABLE dic.EntityColumnPublication
    (
        PublicationId           bigint IDENTITY(1,1) NOT NULL,
        EntityName_EN           nvarchar(256) NOT NULL,
        EntityName_FR           nvarchar(256) NULL,
        ColumnPosition          int           NOT NULL CONSTRAINT DF_dic_ECP_Pos         DEFAULT(0),
        Column_EN               nvarchar(256) NOT NULL,
        Column_FR               nvarchar(256) NULL,
        ColumnClassification    nvarchar(30)  NULL,
        TypeName_EN             nvarchar(128) NULL,
        IsNullable_EN           bit NULL,
        TypeName_FR             nvarchar(128) NULL,
        IsNullable_FR           bit NULL,
        PsseSourceSchema        nvarchar(128) NULL,
        PsseSourceObject        nvarchar(256) NULL,
        PsseColumnName          nvarchar(256) NULL,
        SourceAlias             nvarchar(60)  NULL,
        SourceExpression        nvarchar(2000) NULL,
        FallbackExpression      nvarchar(2000) NULL,
        MapStatus               nvarchar(30)  NOT NULL CONSTRAINT DF_dic_ECP_MapStatus   DEFAULT(N'UNMAPPED'),
        IsPublished             bit           NOT NULL CONSTRAINT DF_dic_ECP_IsPublished  DEFAULT(1),
        PublishedOn             datetime2(0)  NULL,
        UpdatedOn               datetime2(0)  NOT NULL CONSTRAINT DF_dic_ECP_Upd         DEFAULT(sysdatetime()),
        UpdatedBy               sysname       NOT NULL CONSTRAINT DF_dic_ECP_UpdBy       DEFAULT(suser_sname()),
        CONSTRAINT PK_dic_EntityColumnPublication PRIMARY KEY (PublicationId),
        CONSTRAINT UQ_dic_EntityColumnPublication UNIQUE (EntityName_EN, Column_EN)
    );

    CREATE INDEX IX_dic_ECP_Entity    ON dic.EntityColumnPublication (EntityName_EN, ColumnPosition, IsPublished);
    CREATE INDEX IX_dic_ECP_MapStatus ON dic.EntityColumnPublication (MapStatus, EntityName_EN);
END;

IF OBJECT_ID(N'stg.EntityJoin_Draft', N'U') IS NULL
BEGIN
    CREATE TABLE stg.EntityJoin_Draft
    (
        EntityJoinDraftId   bigint IDENTITY(1,1) NOT NULL,
        RunId               uniqueidentifier NOT NULL,
        EntityName_EN       nvarchar(256) NOT NULL,
        JoinTag             nvarchar(60)  NULL,
        PsseSchemaName      sysname NULL,
        PsseObjectName      nvarchar(256) NULL,
        SmartBoxSchemaName  sysname NULL,
        JoinAlias           nvarchar(60)  NULL,
        JoinType            nvarchar(20)  NULL,
        JoinExpression      nvarchar(2000) NULL,
        ColumnCoverage      int NULL,
        JoinStatus          nvarchar(30)  NULL,
        Notes               nvarchar(4000) NULL,
        ProposedAt          datetime2(0)  NOT NULL CONSTRAINT DF_stg_EJD_At DEFAULT(sysdatetime()),
        CONSTRAINT PK_stg_EntityJoin_Draft PRIMARY KEY (EntityJoinDraftId)
    );
    CREATE INDEX IX_stg_EntityJoin_Draft_Entity ON stg.EntityJoin_Draft (EntityName_EN, RunId);
END;

IF OBJECT_ID(N'stg.ODataPsseMap_Draft', N'U') IS NULL
BEGIN
    CREATE TABLE stg.ODataPsseMap_Draft
    (
        ODataPsseMapDraftId bigint IDENTITY(1,1) NOT NULL,
        RunId               uniqueidentifier NOT NULL,
        EntityName_EN       nvarchar(256) NOT NULL,
        Column_EN           nvarchar(256) NOT NULL,
        Column_FR           nvarchar(256) NULL,
        ColumnPosition      int NULL,
        ColumnClassification nvarchar(30) NULL,
        PsseSourceSchema    nvarchar(128) NULL,
        PsseSourceObject    nvarchar(256) NULL,
        PsseColumnName      nvarchar(256) NULL,
        SourceAlias         nvarchar(60)  NULL,
        SourceExpression    nvarchar(2000) NULL,
        FallbackExpression  nvarchar(2000) NULL,
        MapStatus           nvarchar(30)  NULL,
        MapScore            tinyint NULL,
        Notes               nvarchar(4000) NULL,
        ProposedAt          datetime2(0)  NOT NULL CONSTRAINT DF_stg_OPMD_At DEFAULT(sysdatetime()),
        CONSTRAINT PK_stg_ODataPsseMap_Draft PRIMARY KEY (ODataPsseMapDraftId)
    );
    CREATE INDEX IX_stg_OPMD_Entity ON stg.ODataPsseMap_Draft (EntityName_EN, Column_EN, RunId);
END;

IF OBJECT_ID(N'stg.EntityDraftBuildLog', N'U') IS NULL
BEGIN
    CREATE TABLE stg.EntityDraftBuildLog
    (
        DraftBuildLogId bigint IDENTITY(1,1) NOT NULL,
        RunId           uniqueidentifier NOT NULL,
        EntityName_EN   nvarchar(256) NULL,
        Phase           nvarchar(60)  NOT NULL,
        Severity        nvarchar(20)  NOT NULL CONSTRAINT DF_stg_EDBL_Sev DEFAULT(N'INFO'),
        Message         nvarchar(4000) NOT NULL,
        LoggedAt        datetime2(0)  NOT NULL CONSTRAINT DF_stg_EDBL_At  DEFAULT(sysdatetime()),
        CONSTRAINT PK_stg_EntityDraftBuildLog PRIMARY KEY (DraftBuildLogId)
    );
    CREATE INDEX IX_stg_EDBL_Run ON stg.EntityDraftBuildLog (RunId, EntityName_EN);
END;
GO

/* ===========================================================================================
   LOT 2 : Construction de la couche canonique de publication
   =========================================================================================== */
DECLARE @RunId          uniqueidentifier = newid();
DECLARE @ScriptName     sysname          = N'v6_06a_Build_EntityColumnPublication.sql';
DECLARE @PwaId          int;
DECLARE @PwaLanguage    nvarchar(10);
DECLARE @ContentDbName  sysname;
DECLARE @Msg            nvarchar(max);

DECLARE @EntityBindingCount  int = 0;
DECLARE @JoinDraftCount      int = 0;
DECLARE @JoinPublishedCount  int = 0;
DECLARE @MapDraftCount       int = 0;
DECLARE @PublicationCount    int = 0;
DECLARE @MappedCount         int = 0;
DECLARE @MappedNeedsJoinCount int = 0;
DECLARE @UnmappedCount       int = 0;
DECLARE @NavigationCount     int = 0;
DECLARE @WarnCount           int = 0;

SELECT @PwaId = TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(SettingValue)), N''))
FROM cfg.Settings WHERE SettingKey = N'PwaId';
SET @PwaId = ISNULL(@PwaId, 1);

SELECT @PwaLanguage = NULLIF(LTRIM(RTRIM(Language)), N'')
FROM cfg.PWA WHERE PWAId = @PwaId;
IF @PwaLanguage IS NULL
    SELECT @PwaLanguage = NULLIF(LTRIM(RTRIM(SettingValue)), N'')
    FROM cfg.Settings WHERE SettingKey = N'PwaLanguage';
SET @PwaLanguage = ISNULL(@PwaLanguage, N'FR');

SELECT @ContentDbName = NULLIF(LTRIM(RTRIM(SettingValue)), N'')
FROM cfg.Settings WHERE SettingKey = N'ContentDbName';

IF OBJECT_ID(N'dic.Entity', N'U') IS NULL
    THROW 66101, N'dic.Entity absente. Exécuter v6_05a avant v6_06a.', 1;
IF OBJECT_ID(N'dic.EntityColumnMap', N'U') IS NULL
    THROW 66102, N'dic.EntityColumnMap absente. Exécuter v6_05a avant v6_06a.', 1;
IF NOT EXISTS (SELECT 1 FROM dic.EntityColumnMap)
    THROW 66103, N'dic.EntityColumnMap est vide. Exécuter v6_05a avant v6_06a.', 1;
IF NOT EXISTS (SELECT 1 FROM stg.EntitySource_Draft)
    THROW 66104, N'stg.EntitySource_Draft est vide. Exécuter v6_05a avant v6_06a.', 1;

/* Nettoyage complet des tables de travail (idempotence) */
TRUNCATE TABLE stg.EntityDraftBuildLog;
TRUNCATE TABLE stg.EntityJoin_Draft;
TRUNCATE TABLE stg.ODataPsseMap_Draft;

EXEC log.usp_WriteScriptLog
    @RunId=@RunId, @ScriptName=@ScriptName, @ScriptVersion=N'V6-DRAFT',
    @Phase=N'START', @Severity=N'INFO', @Status=N'STARTED',
    @Message=N'Début construction publication canonique V6.';

/* ===========================================================================================
   ETAPE A : dic.EntityBinding
   Source primaire PSSE par entité. Utilise la dernière entrée par entité de stg.EntitySource_Draft
   (la plus récente par ProposedAt, puis la mieux couverte).
   Protection : BindingStatus = MANUAL n'est pas ecrase.
   =========================================================================================== */
MERGE dic.EntityBinding AS T
USING
(
    SELECT
        src.EntityName_EN,
        e.EntityName_FR,
        src.ProposedSchema                              AS PsseSchemaName,
        src.ProposedObject                              AS PsseObjectName,
        CONVERT(sysname, N'src_' + src.ProposedSchema) AS SmartBoxSchemaName,
        N'src'                                          AS BindingAlias,
        src.CoverageScore,
        src.ConfidenceLevel,
        CASE src.ConfidenceLevel
            WHEN N'HIGH'   THEN N'AUTO_HIGH'
            WHEN N'MEDIUM' THEN N'AUTO_MEDIUM'
            WHEN N'LOW'    THEN N'AUTO_LOW'
            ELSE                N'UNRESOLVED'
        END AS BindingStatus
    FROM
    (
        SELECT
            EntityName_EN, ProposedSchema, ProposedObject, CoverageScore, ConfidenceLevel,
            ROW_NUMBER() OVER (PARTITION BY EntityName_EN ORDER BY ProposedAt DESC, CoverageScore DESC) AS rn
        FROM stg.EntitySource_Draft
    ) AS src
    JOIN dic.Entity e ON e.EntityName_EN = src.EntityName_EN
    WHERE src.rn = 1
) AS S
    ON S.EntityName_EN = T.EntityName_EN
WHEN MATCHED AND T.BindingStatus <> N'MANUAL' THEN
    UPDATE SET
        T.EntityName_FR      = S.EntityName_FR,
        T.PsseSchemaName     = S.PsseSchemaName,
        T.PsseObjectName     = S.PsseObjectName,
        T.SmartBoxSchemaName = S.SmartBoxSchemaName,
        T.BindingAlias       = S.BindingAlias,
        T.CoverageScore      = S.CoverageScore,
        T.ConfidenceLevel    = S.ConfidenceLevel,
        T.BindingStatus      = S.BindingStatus,
        T.IsActive           = 1,
        T.UpdatedOn          = sysdatetime(),
        T.UpdatedBy          = suser_sname()
WHEN NOT MATCHED THEN
    INSERT (EntityName_EN, EntityName_FR, PsseSchemaName, PsseObjectName, SmartBoxSchemaName,
            BindingAlias, CoverageScore, ConfidenceLevel, BindingStatus, IsActive)
    VALUES (S.EntityName_EN, S.EntityName_FR, S.PsseSchemaName, S.PsseObjectName, S.SmartBoxSchemaName,
            S.BindingAlias, S.CoverageScore, S.ConfidenceLevel, S.BindingStatus, 1);

SET @EntityBindingCount = @@ROWCOUNT;

SET @Msg = CONCAT(N'dic.EntityBinding synchronise: ', @EntityBindingCount, N' entités.');
EXEC log.usp_WriteScriptLog
    @RunId=@RunId, @ScriptName=@ScriptName, @ScriptVersion=N'V6-DRAFT',
    @Phase=N'ENTITY_BINDING', @Severity=N'INFO', @Status=N'COMPLETED',
    @Message=@Msg,
    @RowsAffected=@EntityBindingCount;

/* ===========================================================================================
   ETAPE A2 : Résolution des bindings partagés
   Quand 2+ entités sont liées au même objet PSSE, conserver celle dont le nom est le plus
   proche du nom noyau de l'objet (affinité nominale), puis rechercher un objet alternatif
   pour les perdants dans stg.ODataPsseExactColumnMatch.
   Protection : BindingStatus = MANUAL n'est jamais écrasé.
   =========================================================================================== */
DECLARE @ConflictCount int = 0;

;WITH

core_names AS (
    SELECT EntityName_EN, PsseObjectName, PsseSchemaName, CoverageScore, BindingStatus,
           REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
               PsseObjectName,
               N'MSP_Epm', N''), N'MSP_Wss', N''), N'MSP_', N''),
               N'_UserView', N''), N'_ODATAView', N''), N'_OData', N'') AS PsseCoreObject
    FROM dic.EntityBinding
    WHERE IsActive = 1 AND PsseObjectName IS NOT NULL AND BindingStatus <> N'MANUAL'
),

shared_objects AS (
    SELECT PsseObjectName FROM core_names GROUP BY PsseObjectName HAVING COUNT(*) > 1
),

conflict_ranked AS (
    SELECT cn.EntityName_EN, cn.PsseObjectName, cn.PsseSchemaName, cn.CoverageScore,
           ROW_NUMBER() OVER (
               PARTITION BY cn.PsseObjectName
               ORDER BY
                   CASE
                       WHEN cn.PsseCoreObject = cn.EntityName_EN                   THEN 0
                       WHEN cn.EntityName_EN LIKE cn.PsseCoreObject + N'%'        THEN 1
                       WHEN cn.PsseCoreObject LIKE N'%' + cn.EntityName_EN + N'%' THEN 2
                       ELSE 3
                   END,
                   cn.CoverageScore DESC,
                   cn.EntityName_EN
           ) AS rn
    FROM core_names cn
    WHERE cn.PsseObjectName IN (SELECT PsseObjectName FROM shared_objects)
),

alt_bindings AS (
    SELECT m.EntityName_EN,
           m.PsseSchemaName AS AltSchema,
           m.PsseObjectName AS AltObject,
           ROUND(CAST(COUNT(*) AS decimal(10,2)) / NULLIF(tot.TotalPrimitiveCols, 0) * 100, 2) AS AltScore,
           ROW_NUMBER() OVER (PARTITION BY m.EntityName_EN ORDER BY COUNT(*) DESC, m.PsseObjectName) AS alt_rn
    FROM stg.ODataPsseExactColumnMatch m
    JOIN (
        SELECT EntityName_EN, COUNT(*) AS TotalPrimitiveCols
        FROM dic.EntityColumnMap WHERE ColumnClassification = N'PRIMITIVE'
        GROUP BY EntityName_EN
    ) tot ON tot.EntityName_EN = m.EntityName_EN
    WHERE m.MatchType = N'EXACT'
      AND m.PsseObjectName NOT IN (SELECT PsseObjectName FROM conflict_ranked WHERE rn = 1)
      AND m.EntityName_EN IN (SELECT EntityName_EN FROM conflict_ranked WHERE rn > 1)
    GROUP BY m.EntityName_EN, m.PsseSchemaName, m.PsseObjectName, tot.TotalPrimitiveCols
)

UPDATE dic.EntityBinding
SET PsseObjectName     = CASE WHEN ab.AltObject IS NOT NULL THEN ab.AltObject    ELSE NULL END,
    PsseSchemaName     = CASE WHEN ab.AltObject IS NOT NULL THEN ab.AltSchema    ELSE NULL END,
    SmartBoxSchemaName = CASE WHEN ab.AltObject IS NOT NULL THEN CONVERT(sysname, N'src_' + ab.AltSchema) ELSE NULL END,
    CoverageScore      = CASE WHEN ab.AltObject IS NOT NULL THEN ab.AltScore     ELSE 0 END,
    ConfidenceLevel    = CASE WHEN ab.AltObject IS NOT NULL THEN N'LOW'          ELSE N'NONE' END,
    BindingStatus      = CASE WHEN ab.AltObject IS NOT NULL THEN N'AUTO_LOW_ALT' ELSE N'SHARED_CONFLICT' END,
    IsActive           = CASE WHEN ab.AltObject IS NOT NULL THEN 1               ELSE 0 END,
    UpdatedOn          = sysdatetime(),
    UpdatedBy          = suser_sname()
FROM dic.EntityBinding eb
JOIN conflict_ranked cr ON cr.EntityName_EN = eb.EntityName_EN AND cr.rn > 1
LEFT JOIN alt_bindings ab ON ab.EntityName_EN = eb.EntityName_EN AND ab.alt_rn = 1
WHERE eb.BindingStatus <> N'MANUAL';

SET @ConflictCount = @@ROWCOUNT;

IF @ConflictCount > 0
BEGIN
    SET @Msg = CONCAT(N'Conflits de binding résolus: ', @ConflictCount,
                      N' entités relocalises (AUTO_LOW_ALT) ou marquees SHARED_CONFLICT.',
                      N' Verifier dic.EntityBinding WHERE BindingStatus IN (''SHARED_CONFLICT'',''AUTO_LOW_ALT'').');
    EXEC log.usp_WriteScriptLog
        @RunId=@RunId, @ScriptName=@ScriptName, @ScriptVersion=N'V6-DRAFT',
        @Phase=N'BINDING_CONFLICT', @Severity=N'WARNING', @Status=N'WARNING',
        @Message=@Msg,
        @RowsAffected=@ConflictCount;
END;

/* ===========================================================================================
   ETAPE B : stg.EntityJoin_Draft
   Detecter les colonnes PSSE provenant d'une source secondaire (differente de dic.EntityBinding).
   Pour chaque source secondaire par entité, proposer une expression de jointure en cherchant
   la premiere colonne en commun se terminant par UID ou Id dans stg.ColumnInventory.
   =========================================================================================== */
INSERT INTO stg.EntityJoin_Draft
(
    RunId, EntityName_EN, JoinTag, PsseSchemaName, PsseObjectName, SmartBoxSchemaName,
    JoinAlias, JoinType, JoinExpression, ColumnCoverage, JoinStatus, Notes
)
SELECT
    @RunId,
    sec.EntityName_EN,
    CONVERT(nvarchar(60), CONCAT(N'j', sec.JoinIdx))          AS JoinTag,
    sec.SecondarySchema,
    sec.SecondaryObject,
    CONVERT(sysname, N'src_' + sec.SecondarySchema)           AS SmartBoxSchemaName,
    CONVERT(nvarchar(60), CONCAT(N'j', sec.JoinIdx))          AS JoinAlias,
    N'LEFT'                                                    AS JoinType,
    CASE
        WHEN key_col.ColumnName IS NOT NULL
            THEN CONCAT(N'j', sec.JoinIdx, N'.', QUOTENAME(key_col.ColumnName), N' = src.', QUOTENAME(key_col.ColumnName))
        ELSE N'/* TODO: spécifier la condition de jointure */'
    END                                                        AS JoinExpression,
    sec.ColCount                                               AS ColumnCoverage,
    CASE WHEN key_col.ColumnName IS NOT NULL THEN N'PROPOSED' ELSE N'MANUAL_REQUIRED' END AS JoinStatus,
    CONCAT(
        N'Source secondaire: ', sec.SecondaryObject,
        N' (', sec.ColCount, N' col(s))',
        CASE WHEN key_col.ColumnName IS NOT NULL
             THEN CONCAT(N'; cle candidate: ', key_col.ColumnName)
             ELSE N'; aucune cle commune UID/Id détectée'
        END
    )                                                          AS Notes
FROM
(
    SELECT
        ecm.EntityName_EN,
        ecm.PsseSourceSchema AS SecondarySchema,
        ecm.PsseSourceObject AS SecondaryObject,
        COUNT(*)             AS ColCount,
        ROW_NUMBER() OVER (PARTITION BY ecm.EntityName_EN ORDER BY COUNT(*) DESC, ecm.PsseSourceObject) AS JoinIdx
    FROM dic.EntityColumnMap ecm
    JOIN dic.EntityBinding eb
        ON eb.EntityName_EN = ecm.EntityName_EN
       AND eb.IsActive = 1
    WHERE ecm.PsseSourceObject IS NOT NULL
      AND ecm.PsseSourceObject <> eb.PsseObjectName
      AND ecm.ColumnClassification = N'PRIMITIVE'
    GROUP BY ecm.EntityName_EN, ecm.PsseSourceSchema, ecm.PsseSourceObject
) AS sec
OUTER APPLY
(
    SELECT TOP 1 ci_sec.ColumnName
    FROM stg.ColumnInventory ci_sec
    JOIN dic.EntityBinding eb_k
        ON eb_k.EntityName_EN = sec.EntityName_EN
       AND eb_k.IsActive = 1
    JOIN stg.ColumnInventory ci_pri
        ON ci_pri.ColumnName         = ci_sec.ColumnName
       AND ci_pri.SourceSchemaName   = eb_k.PsseSchemaName
       AND ci_pri.SourceObjectName   = eb_k.PsseObjectName
       AND ci_pri.PWAId              = @PwaId
       AND ci_pri.DataType           = ci_sec.DataType    /* exclure les cles avec types incompatibles */
    WHERE ci_sec.SourceSchemaName = sec.SecondarySchema
      AND ci_sec.SourceObjectName = sec.SecondaryObject
      AND ci_sec.PWAId = @PwaId
      AND (ci_sec.ColumnName LIKE N'%UID' OR ci_sec.ColumnName LIKE N'%Id')
    ORDER BY LEN(ci_sec.ColumnName), ci_sec.ColumnName
) AS key_col(ColumnName);

SET @JoinDraftCount = @@ROWCOUNT;

SET @Msg = CONCAT(N'stg.EntityJoin_Draft: ', @JoinDraftCount, N' jointures secondaires détectées.');
EXEC log.usp_WriteScriptLog
    @RunId=@RunId, @ScriptName=@ScriptName, @ScriptVersion=N'V6-DRAFT',
    @Phase=N'JOIN_DRAFT', @Severity=N'INFO', @Status=N'COMPLETED',
    @Message=@Msg,
    @RowsAffected=@JoinDraftCount;

/* ===========================================================================================
   ETAPE C : dic.EntityJoin
   Publier les jointures proposees. Protection : JoinStatus = MANUAL non ecrase.
   =========================================================================================== */
MERGE dic.EntityJoin AS T
USING
(
    SELECT JoinTag, EntityName_EN, PsseSchemaName, PsseObjectName, SmartBoxSchemaName,
           JoinAlias, JoinType, JoinExpression, ColumnCoverage, JoinStatus
    FROM stg.EntityJoin_Draft
    WHERE RunId = @RunId
) AS S
    ON S.EntityName_EN = T.EntityName_EN
   AND S.JoinTag = T.JoinTag
WHEN MATCHED AND T.JoinStatus <> N'MANUAL' THEN
    UPDATE SET
        T.PsseSchemaName     = S.PsseSchemaName,
        T.PsseObjectName     = S.PsseObjectName,
        T.SmartBoxSchemaName = S.SmartBoxSchemaName,
        T.JoinAlias          = S.JoinAlias,
        T.JoinType           = S.JoinType,
        T.JoinExpression     = S.JoinExpression,
        T.ColumnCoverage     = S.ColumnCoverage,
        T.JoinStatus         = S.JoinStatus,
        T.IsActive           = 1,
        T.UpdatedOn          = sysdatetime(),
        T.UpdatedBy          = suser_sname()
WHEN NOT MATCHED THEN
    INSERT (EntityName_EN, JoinTag, PsseSchemaName, PsseObjectName, SmartBoxSchemaName,
            JoinAlias, JoinType, JoinExpression, ColumnCoverage, JoinStatus, IsActive)
    VALUES (S.EntityName_EN, S.JoinTag, S.PsseSchemaName, S.PsseObjectName, S.SmartBoxSchemaName,
            S.JoinAlias, S.JoinType, S.JoinExpression, S.ColumnCoverage, S.JoinStatus, 1);

SET @JoinPublishedCount = @@ROWCOUNT;

SET @Msg = CONCAT(N'dic.EntityJoin synchronise: ', @JoinPublishedCount, N' jointures.');
EXEC log.usp_WriteScriptLog
    @RunId=@RunId, @ScriptName=@ScriptName, @ScriptVersion=N'V6-DRAFT',
    @Phase=N'JOIN_PUBLISH', @Severity=N'INFO', @Status=N'COMPLETED',
    @Message=@Msg,
    @RowsAffected=@JoinPublishedCount;

/* ===========================================================================================
   ETAPE D : stg.ODataPsseMap_Draft
   Brouillon du mapping colonne par colonne. Calculer SourceAlias, SourceExpression,
   FallbackExpression et MapStatus pour chaque (EntityName_EN, Column_EN).
   =========================================================================================== */
INSERT INTO stg.ODataPsseMap_Draft
(
    RunId, EntityName_EN, Column_EN, Column_FR, ColumnPosition, ColumnClassification,
    PsseSourceSchema, PsseSourceObject, PsseColumnName,
    SourceAlias, SourceExpression, FallbackExpression, MapStatus, MapScore
)
SELECT
    @RunId,
    ecm.EntityName_EN,
    ecm.Column_EN,
    ecm.Column_FR,
    ecm.ColumnPosition,
    ecm.ColumnClassification,
    ecm.PsseSourceSchema,
    ecm.PsseSourceObject,
    ecm.PsseColumnName,
    /* SourceAlias */
    CASE
        WHEN ecm.PsseColumnName IS NULL THEN NULL
        WHEN ecm.PsseSourceObject = eb.PsseObjectName THEN N'src'
        WHEN ej.JoinAlias IS NOT NULL THEN ej.JoinAlias
        ELSE NULL  /* source connue mais jointure non définie -> MAPPED_NEEDS_JOIN */
    END,
    /* SourceExpression */
    CASE
        WHEN ecm.PsseColumnName IS NULL THEN NULL
        WHEN ecm.PsseSourceObject = eb.PsseObjectName
            THEN CONCAT(N'src.', QUOTENAME(ecm.PsseColumnName))
        WHEN ej.JoinAlias IS NOT NULL
            THEN CONCAT(ej.JoinAlias, N'.', QUOTENAME(ecm.PsseColumnName))
        ELSE NULL
    END,
    /* FallbackExpression : CAST(NULL AS type) pour PRIMITIVE sans source PSSE */
    CASE
        WHEN ecm.PsseColumnName IS NULL AND ecm.ColumnClassification = N'PRIMITIVE'
        THEN CONCAT(
            N'CAST(NULL AS ',
            CASE ecm.TypeName_EN
                WHEN N'Edm.Int32'          THEN N'int'
                WHEN N'Edm.Int64'          THEN N'bigint'
                WHEN N'Edm.Int16'          THEN N'smallint'
                WHEN N'Edm.Byte'           THEN N'tinyint'
                WHEN N'Edm.String'         THEN N'nvarchar(255)'
                WHEN N'Edm.DateTime'       THEN N'datetime'
                WHEN N'Edm.DateTimeOffset' THEN N'datetimeoffset(7)'
                WHEN N'Edm.Boolean'        THEN N'bit'
                WHEN N'Edm.Decimal'        THEN N'decimal(19,4)'
                WHEN N'Edm.Guid'           THEN N'uniqueidentifier'
                WHEN N'Edm.Binary'         THEN N'varbinary(max)'
                WHEN N'Edm.Single'         THEN N'real'
                WHEN N'Edm.Double'         THEN N'float'
                ELSE                            N'nvarchar(255)'
            END,
            N')'
        )
        ELSE NULL
    END,
    /* MapStatus */
    CASE
        WHEN ecm.PsseColumnName IS NOT NULL
             AND (ecm.PsseSourceObject = eb.PsseObjectName OR ej.JoinAlias IS NOT NULL)
            THEN N'MAPPED'
        WHEN ecm.PsseColumnName IS NOT NULL
            THEN N'MAPPED_NEEDS_JOIN'
        WHEN ecm.ColumnClassification = N'PRIMITIVE'
            THEN N'UNMAPPED'
        ELSE N'NAVIGATION'
    END,
    /* MapScore : 2=MAPPED, 1=MAPPED_NEEDS_JOIN ou NAVIGATION, 0=UNMAPPED */
    CASE
        WHEN ecm.PsseColumnName IS NOT NULL
             AND (ecm.PsseSourceObject = eb.PsseObjectName OR ej.JoinAlias IS NOT NULL)
            THEN CONVERT(tinyint, 2)
        WHEN ecm.PsseColumnName IS NOT NULL OR ecm.ColumnClassification <> N'PRIMITIVE'
            THEN CONVERT(tinyint, 1)
        ELSE CONVERT(tinyint, 0)
    END
FROM dic.EntityColumnMap ecm
LEFT JOIN dic.EntityBinding eb
    ON eb.EntityName_EN = ecm.EntityName_EN
   AND eb.IsActive = 1
LEFT JOIN
(
    SELECT
        EntityName_EN,
        PsseObjectName,
        JoinAlias,
        JoinStatus,
        ROW_NUMBER() OVER
        (
            PARTITION BY EntityName_EN, PsseObjectName
            ORDER BY ColumnCoverage DESC, JoinTag
        ) AS rn
    FROM dic.EntityJoin
    WHERE IsActive = 1
      AND JoinStatus NOT IN (N'MANUAL_REQUIRED')
) ej
    ON ej.EntityName_EN  = ecm.EntityName_EN
   AND ej.PsseObjectName = ecm.PsseSourceObject
   AND ej.rn = 1; /* retenir une seule jointure active par objet secondaire */

SET @MapDraftCount = @@ROWCOUNT;

SET @Msg = CONCAT(N'stg.ODataPsseMap_Draft: ', @MapDraftCount, N' colonnes proposees.');
EXEC log.usp_WriteScriptLog
    @RunId=@RunId, @ScriptName=@ScriptName, @ScriptVersion=N'V6-DRAFT',
    @Phase=N'MAP_DRAFT', @Severity=N'INFO', @Status=N'COMPLETED',
    @Message=@Msg,
    @RowsAffected=@MapDraftCount;

/* ===========================================================================================
   ETAPE E : dic.EntityColumnPublication
   Publier depuis stg.ODataPsseMap_Draft.
   IsPublished = 0 uniquement pour MAPPED_NEEDS_JOIN (jointure non résolue).
   Les overrides manuels (MapStatus = MANUAL) ne sont pas ecrases.
   =========================================================================================== */
MERGE dic.EntityColumnPublication AS T
USING
(
    SELECT
        md.EntityName_EN,
        e.EntityName_FR,
        md.ColumnPosition,
        md.Column_EN,
        md.Column_FR,
        md.ColumnClassification,
        ecm.TypeName_EN,
        ecm.IsNullable_EN,
        ecm.TypeName_FR,
        ecm.IsNullable_FR,
        md.PsseSourceSchema,
        md.PsseSourceObject,
        md.PsseColumnName,
        md.SourceAlias,
        md.SourceExpression,
        md.FallbackExpression,
        md.MapStatus,
        CASE md.MapStatus
            WHEN N'MAPPED_NEEDS_JOIN' THEN CONVERT(bit, 0)
            ELSE                           CONVERT(bit, 1)
        END AS IsPublished
    FROM stg.ODataPsseMap_Draft md
    JOIN dic.Entity e
        ON e.EntityName_EN = md.EntityName_EN
    JOIN dic.EntityColumnMap ecm
        ON ecm.EntityName_EN = md.EntityName_EN
       AND ecm.Column_EN     = md.Column_EN
    WHERE md.RunId = @RunId
) AS S
    ON S.EntityName_EN = T.EntityName_EN
   AND S.Column_EN     = T.Column_EN
WHEN MATCHED AND T.MapStatus <> N'MANUAL' THEN
    UPDATE SET
        T.EntityName_FR        = S.EntityName_FR,
        T.ColumnPosition       = S.ColumnPosition,
        T.Column_FR            = S.Column_FR,
        T.ColumnClassification = S.ColumnClassification,
        T.TypeName_EN          = S.TypeName_EN,
        T.IsNullable_EN        = S.IsNullable_EN,
        T.TypeName_FR          = S.TypeName_FR,
        T.IsNullable_FR        = S.IsNullable_FR,
        T.PsseSourceSchema     = S.PsseSourceSchema,
        T.PsseSourceObject     = S.PsseSourceObject,
        T.PsseColumnName       = S.PsseColumnName,
        T.SourceAlias          = S.SourceAlias,
        T.SourceExpression     = S.SourceExpression,
        T.FallbackExpression   = S.FallbackExpression,
        T.MapStatus            = S.MapStatus,
        T.IsPublished          = S.IsPublished,
        T.PublishedOn          = sysdatetime(),
        T.UpdatedOn            = sysdatetime(),
        T.UpdatedBy            = suser_sname()
WHEN NOT MATCHED THEN
    INSERT (EntityName_EN, EntityName_FR, ColumnPosition, Column_EN, Column_FR, ColumnClassification,
            TypeName_EN, IsNullable_EN, TypeName_FR, IsNullable_FR,
            PsseSourceSchema, PsseSourceObject, PsseColumnName,
            SourceAlias, SourceExpression, FallbackExpression,
            MapStatus, IsPublished, PublishedOn)
    VALUES (S.EntityName_EN, S.EntityName_FR, S.ColumnPosition, S.Column_EN, S.Column_FR, S.ColumnClassification,
            S.TypeName_EN, S.IsNullable_EN, S.TypeName_FR, S.IsNullable_FR,
            S.PsseSourceSchema, S.PsseSourceObject, S.PsseColumnName,
            S.SourceAlias, S.SourceExpression, S.FallbackExpression,
            S.MapStatus, S.IsPublished, sysdatetime());

SET @PublicationCount = @@ROWCOUNT;

SELECT
    @MappedCount          = SUM(CASE WHEN MapStatus = N'MAPPED'            THEN 1 ELSE 0 END),
    @MappedNeedsJoinCount = SUM(CASE WHEN MapStatus = N'MAPPED_NEEDS_JOIN' THEN 1 ELSE 0 END),
    @UnmappedCount        = SUM(CASE WHEN MapStatus = N'UNMAPPED'          THEN 1 ELSE 0 END),
    @NavigationCount      = SUM(CASE WHEN MapStatus = N'NAVIGATION'        THEN 1 ELSE 0 END)
FROM dic.EntityColumnPublication;

SET @Msg = CONCAT(
    N'dic.EntityColumnPublication synchronise. ',
    N'MAPPED=', @MappedCount,
    N'; MAPPED_NEEDS_JOIN=', @MappedNeedsJoinCount,
    N'; UNMAPPED=', @UnmappedCount,
    N'; NAVIGATION=', @NavigationCount
);
EXEC log.usp_WriteScriptLog
    @RunId=@RunId, @ScriptName=@ScriptName, @ScriptVersion=N'V6-DRAFT',
    @Phase=N'PUBLICATION', @Severity=N'INFO', @Status=N'COMPLETED',
    @Message=@Msg,
    @RowsAffected=@PublicationCount;

/* ===========================================================================================
   ETAPE E2 : Résolution normalisée des colonnes UNMAPPED (champs personnalisés)
   L'API OData normalise les noms de champs en supprimant les espaces et certains caractères
   spéciaux ("Cat de proj" -> "Catdeproj", "Afficher rapport_T" -> "Afficherrapport_T").
   La Phase F de v6_05a fait un match exact qui échoue pour ces colonnes. Ce bloc applique
   un match normalisé (suppression espaces + tirets + parenthèses, COLLATE Latin1_General_CI_AI
   pour l'insensibilité aux accents) sur stg.ColumnInventory depuis la table primaire du binding.
   Les noms OData (Column_EN) sont PRÉSERVÉS comme alias de vue — seul SourceExpression change.
   Applicable à toutes instances PWA. Overrides MANUAL préservés.
   =========================================================================================== */
DECLARE @NormMatchCount int = 0;

UPDATE ecp
SET
    ecp.PsseSourceSchema = eb.PsseSchemaName,
    ecp.PsseSourceObject = eb.PsseObjectName,
    ecp.PsseColumnName   = ci.ColumnName,
    ecp.SourceAlias      = eb.BindingAlias,
    ecp.SourceExpression = QUOTENAME(eb.BindingAlias) + N'.' + QUOTENAME(ci.ColumnName),
    ecp.MapStatus        = N'MAPPED',
    ecp.IsPublished      = 1,
    ecp.PublishedOn      = sysdatetime(),
    ecp.UpdatedOn        = sysdatetime(),
    ecp.UpdatedBy        = suser_sname()
FROM dic.EntityColumnPublication ecp
JOIN dic.EntityBinding eb
    ON  eb.EntityName_EN  = ecp.EntityName_EN
    AND eb.IsActive       = 1
    AND eb.PsseObjectName IS NOT NULL
JOIN (SELECT DISTINCT PWAId, SourceSchemaName, SourceObjectName, ColumnName
      FROM stg.ColumnInventory) ci
    ON  ci.PWAId            = @PwaId
    AND ci.SourceSchemaName = eb.PsseSchemaName
    AND ci.SourceObjectName = eb.PsseObjectName
    AND LOWER(REPLACE(REPLACE(REPLACE(REPLACE(
            ci.ColumnName  COLLATE Latin1_General_CI_AI,
            N' ', N''), N'-', N''), N'(', N''), N')', N''))
      = LOWER(REPLACE(REPLACE(REPLACE(REPLACE(
            ecp.Column_EN COLLATE Latin1_General_CI_AI,
            N' ', N''), N'-', N''), N'(', N''), N')', N''))
WHERE ecp.MapStatus    = N'UNMAPPED'
  AND ecp.PsseColumnName IS NULL
  AND ecp.MapStatus   <> N'MANUAL';

SET @NormMatchCount = @@ROWCOUNT;

/* Cas particulier : ResourceTimesheetManageId -> ResourceTimesheetManagerUID
   Le nom OData (sans "r", "Id" au lieu de "UID") diffère même après normalisation.
   On mappe directement vers la colonne PSSE connue, en vérifiant son existence. */
UPDATE ecp
SET ecp.PsseSourceSchema = eb.PsseSchemaName,
    ecp.PsseSourceObject = eb.PsseObjectName,
    ecp.PsseColumnName   = N'ResourceTimesheetManagerUID',
    ecp.SourceAlias      = eb.BindingAlias,
    ecp.SourceExpression = QUOTENAME(eb.BindingAlias) + N'.[ResourceTimesheetManagerUID]',
    ecp.MapStatus        = N'MAPPED',
    ecp.IsPublished      = 1,
    ecp.PublishedOn      = sysdatetime(),
    ecp.UpdatedOn        = sysdatetime(),
    ecp.UpdatedBy        = suser_sname()
FROM dic.EntityColumnPublication ecp
JOIN dic.EntityBinding eb
    ON eb.EntityName_EN = ecp.EntityName_EN AND eb.IsActive = 1
WHERE ecp.EntityName_EN = N'Resources'
  AND ecp.Column_EN     = N'ResourceTimesheetManageId'
  AND ecp.MapStatus     = N'UNMAPPED'
  AND ecp.MapStatus    <> N'MANUAL'
  AND EXISTS (
      SELECT 1 FROM stg.ColumnInventory ci2
      WHERE ci2.SourceObjectName = eb.PsseObjectName
        AND ci2.ColumnName       = N'ResourceTimesheetManagerUID'
        AND ci2.PWAId            = @PwaId
  );

SET @NormMatchCount += @@ROWCOUNT;

SET @Msg = CONCAT(N'ETAPE E2 : ', @NormMatchCount,
    N' colonne(s) UNMAPPED résolues par match normalisé (champs personnalisés avec espaces).');
EXEC log.usp_WriteScriptLog
    @RunId=@RunId, @ScriptName=@ScriptName, @ScriptVersion=N'V6-DRAFT',
    @Phase=N'NORM_MATCH', @Severity=N'INFO', @Status=N'COMPLETED',
    @Message=@Msg, @RowsAffected=@NormMatchCount;

/* ===========================================================================================
   ETAPE E3 : Correction des jointures de type (TypeName, TypeDescription)
   Resources j1 (MSP_EpmResourceType) et Assignments j3 (MSP_EpmAssignmentType) avaient
   une condition TODO. On fixe la condition (clé métier + SiteId + LCID depuis cfg.PWA)
   et on active les colonnes correspondantes dans dic.EntityColumnPublication.
   Overrides MANUAL préservés.
   =========================================================================================== */

/* Resources j1 : MSP_EpmResourceType -> ResourceType + LCID (MSP_EpmResourceType n'a pas de SiteId) */
UPDATE dic.EntityJoin
SET JoinExpression = N'j1.ResourceType = src.ResourceType'
    + N' AND j1.LCID = (SELECT TOP 1 CASE WHEN Language = N''FR'' THEN 1036 ELSE 1033 END FROM cfg.PWA)',
    JoinStatus     = N'PROPOSED',
    UpdatedOn      = sysdatetime(),
    UpdatedBy      = suser_sname()
WHERE EntityName_EN = N'Resources'
  AND JoinTag       = N'j1'
  AND JoinStatus   <> N'MANUAL';

/* Assignments j3 : MSP_EpmAssignmentType -> AssignmentType + LCID (MSP_EpmAssignmentType n'a pas de SiteId) */
UPDATE dic.EntityJoin
SET JoinExpression = N'j3.AssignmentType = src.AssignmentType'
    + N' AND j3.LCID = (SELECT TOP 1 CASE WHEN Language = N''FR'' THEN 1036 ELSE 1033 END FROM cfg.PWA)',
    JoinStatus     = N'PROPOSED',
    UpdatedOn      = sysdatetime(),
    UpdatedBy      = suser_sname()
WHERE EntityName_EN = N'Assignments'
  AND JoinTag       = N'j3'
  AND JoinStatus   <> N'MANUAL';

/* Activer TypeName et TypeDescription dans dic.EntityColumnPublication */
UPDATE dic.EntityColumnPublication
SET SourceAlias      = N'j1',
    SourceExpression = N'j1.' + QUOTENAME(Column_EN),
    MapStatus        = N'MAPPED',
    IsPublished      = 1,
    PublishedOn      = sysdatetime(),
    UpdatedOn        = sysdatetime(),
    UpdatedBy        = suser_sname()
WHERE EntityName_EN = N'Resources'
  AND Column_EN IN (N'TypeName', N'TypeDescription')
  AND MapStatus    <> N'MANUAL';

UPDATE dic.EntityColumnPublication
SET SourceAlias      = N'j3',
    SourceExpression = N'j3.' + QUOTENAME(Column_EN),
    MapStatus        = N'MAPPED',
    IsPublished      = 1,
    PublishedOn      = sysdatetime(),
    UpdatedOn        = sysdatetime(),
    UpdatedBy        = suser_sname()
WHERE EntityName_EN = N'Assignments'
  AND Column_EN IN (N'TypeName', N'TypeDescription')
  AND MapStatus    <> N'MANUAL';

SET @Msg = N'ETAPE E3 : jointures TypeName/TypeDescription résolues pour Resources (j1) et Assignments (j3). 4 colonnes activées.';
EXEC log.usp_WriteScriptLog
    @RunId=@RunId, @ScriptName=@ScriptName, @ScriptVersion=N'V6-DRAFT',
    @Phase=N'TYPE_JOIN_FIX', @Severity=N'INFO', @Status=N'COMPLETED',
    @Message=@Msg, @RowsAffected=4;

/* ===========================================================================================
   ETAPE E4 : Jointures dérivées — ProjectName, TaskName, ParentTaskName, ResourceName,
              Workflow + Timephased Projects, AssignmentAllUpdatesApplied
   Ces colonnes existent dans l'endpoint OData mais nécessitent des jointures supplémentaires
   non auto-détectées. MERGE idempotent — JoinStatus MANUAL protège des futures exécutions.
   Jointures imbriquées (jWFOwner dépend de jWFI) : valides car STRING_AGG de v6_07a ordonne
   par JoinTag alphabétique — jWFI est émis avant jWFOwner dans la clause FROM.
   =========================================================================================== */
MERGE dic.EntityJoin AS T
USING
(
    VALUES
        /* Tasks : ProjectName depuis MSP_EpmProject_UserView */
        (N'Tasks', N'jProject', N'pjrep', N'MSP_EpmProject_UserView', N'src_pjrep',
         N'jProject', N'LEFT', N'jProject.ProjectUID = src.ProjectUID', 1, N'MANUAL'),
        /* Tasks : ParentTaskName via auto-jointure (tâche parente de la tâche courante) */
        (N'Tasks', N'jParent', N'pjrep', N'MSP_EpmTask_UserView', N'src_pjrep',
         N'jParent', N'LEFT', N'jParent.TaskUID = src.TaskParentUID', 1, N'MANUAL'),
        /* Assignments : ProjectName */
        (N'Assignments', N'jProject', N'pjrep', N'MSP_EpmProject_UserView', N'src_pjrep',
         N'jProject', N'LEFT', N'jProject.ProjectUID = src.ProjectUID', 1, N'MANUAL'),
        /* Assignments : TaskName */
        (N'Assignments', N'jTask', N'pjrep', N'MSP_EpmTask_UserView', N'src_pjrep',
         N'jTask', N'LEFT', N'jTask.TaskUID = src.TaskUID', 1, N'MANUAL'),
        /* Assignments : ResourceName (ResourceUID direct dans MSP_EpmAssignment_UserView) */
        (N'Assignments', N'jResource', N'pjrep', N'MSP_EpmResource_UserView', N'src_pjrep',
         N'jResource', N'LEFT', N'jResource.ResourceUID = src.ResourceUID', 1, N'MANUAL'),
        /* Assignments : AssignmentAllUpdatesApplied / AssignmentUpdatesAppliedDate (j4=TODO) */
        (N'Assignments', N'jAssignApplied', N'pjrep', N'MSP_EpmAssignmentsApplied_UserView', N'src_pjrep',
         N'jAssignApplied', N'LEFT', N'jAssignApplied.AssignmentUID = src.AssignmentUID', 1, N'MANUAL'),
        /* AssignmentTimephasedDataSet : ProjectName via j1.ProjectUID (j1 = MSP_EpmAssignment_UserView) */
        (N'AssignmentTimephasedDataSet', N'jProject', N'pjrep', N'MSP_EpmProject_UserView', N'src_pjrep',
         N'jProject', N'LEFT', N'jProject.ProjectUID = j1.ProjectUID', 1, N'MANUAL'),
        /* AssignmentTimephasedDataSet : TaskName via j1.TaskUID */
        (N'AssignmentTimephasedDataSet', N'jTask', N'pjrep', N'MSP_EpmTask_UserView', N'src_pjrep',
         N'jTask', N'LEFT', N'jTask.TaskUID = j1.TaskUID', 1, N'MANUAL'),
        /* Projects : ProjectTimephased (PSSE colonne = TimePhased, clé = ProjectId != ProjectUID) */
        (N'Projects', N'jPTRI', N'pjrep', N'MSP_ProjectTimephasedRollupInfo_ODATAView', N'src_pjrep',
         N'jPTRI', N'LEFT', N'jPTRI.ProjectId = src.ProjectUID', 1, N'MANUAL'),
        /* Projects : WorkflowCreatedDate, WorkflowOwnerId (clé = ProjectId != ProjectUID) */
        (N'Projects', N'jWFI', N'pjrep', N'MSP_EpmWorkflowInstance_UserView', N'src_pjrep',
         N'jWFI', N'LEFT', N'jWFI.ProjectId = src.ProjectUID', 1, N'MANUAL'),
        /* Projects : WorkflowOwnerName — jointure imbriquée sur jWFI.WorkflowOwner (ResourceUID) */
        (N'Projects', N'jWFOwner', N'pjrep', N'MSP_EpmResource_UserView', N'src_pjrep',
         N'jWFOwner', N'LEFT', N'jWFOwner.ResourceUID = jWFI.WorkflowOwner', 1, N'MANUAL')
) AS S (EntityName_EN, JoinTag, PsseSchemaName, PsseObjectName, SmartBoxSchemaName,
        JoinAlias, JoinType, JoinExpression, IsActive, JoinStatus)
ON  T.EntityName_EN = S.EntityName_EN
AND T.JoinTag       = S.JoinTag
WHEN MATCHED AND T.JoinStatus <> N'MANUAL' THEN
    UPDATE SET
        T.PsseSchemaName     = S.PsseSchemaName,
        T.PsseObjectName     = S.PsseObjectName,
        T.SmartBoxSchemaName = S.SmartBoxSchemaName,
        T.JoinAlias          = S.JoinAlias,
        T.JoinType           = S.JoinType,
        T.JoinExpression     = S.JoinExpression,
        T.IsActive           = S.IsActive,
        T.JoinStatus         = S.JoinStatus,
        T.UpdatedOn          = sysdatetime(),
        T.UpdatedBy          = suser_sname()
WHEN NOT MATCHED THEN
    INSERT (EntityName_EN, JoinTag, PsseSchemaName, PsseObjectName, SmartBoxSchemaName,
            JoinAlias, JoinType, JoinExpression, IsActive, JoinStatus)
    VALUES (S.EntityName_EN, S.JoinTag, S.PsseSchemaName, S.PsseObjectName, S.SmartBoxSchemaName,
            S.JoinAlias, S.JoinType, S.JoinExpression, S.IsActive, S.JoinStatus);

/* Activer les colonnes correspondantes dans dic.EntityColumnPublication */
UPDATE dic.EntityColumnPublication
SET SourceAlias      = N'jProject',
    SourceExpression = N'jProject.[ProjectName]',
    MapStatus        = N'MAPPED',
    IsPublished      = 1,
    PublishedOn      = sysdatetime(),
    UpdatedOn        = sysdatetime(),
    UpdatedBy        = suser_sname()
WHERE EntityName_EN IN (N'Tasks', N'Assignments', N'AssignmentTimephasedDataSet')
  AND Column_EN    = N'ProjectName'
  AND MapStatus   <> N'MANUAL';

UPDATE dic.EntityColumnPublication
SET SourceAlias      = N'jTask',
    SourceExpression = N'jTask.[TaskName]',
    MapStatus        = N'MAPPED',
    IsPublished      = 1,
    PublishedOn      = sysdatetime(),
    UpdatedOn        = sysdatetime(),
    UpdatedBy        = suser_sname()
WHERE EntityName_EN IN (N'Assignments', N'AssignmentTimephasedDataSet')
  AND Column_EN    = N'TaskName'
  AND MapStatus   <> N'MANUAL';

/* ParentTaskName : colonne dérivée de l'auto-jointure jParent (jParent.TaskUID = src.TaskParentUID) */
UPDATE dic.EntityColumnPublication
SET PsseSourceSchema = N'pjrep',
    PsseSourceObject = N'MSP_EpmTask_UserView',
    PsseColumnName   = N'TaskName',
    SourceAlias      = N'jParent',
    SourceExpression = N'jParent.[TaskName]',
    MapStatus        = N'MAPPED',
    IsPublished      = 1,
    PublishedOn      = sysdatetime(),
    UpdatedOn        = sysdatetime(),
    UpdatedBy        = suser_sname()
WHERE EntityName_EN = N'Tasks'
  AND Column_EN     = N'ParentTaskName'
  AND MapStatus    <> N'MANUAL';

/* Assignments : ResourceName via jResource */
UPDATE dic.EntityColumnPublication
SET PsseSourceSchema = N'pjrep',
    PsseSourceObject = N'MSP_EpmResource_UserView',
    PsseColumnName   = N'ResourceName',
    SourceAlias      = N'jResource',
    SourceExpression = N'jResource.[ResourceName]',
    MapStatus        = N'MAPPED',
    IsPublished      = 1,
    PublishedOn      = sysdatetime(),
    UpdatedOn        = sysdatetime(),
    UpdatedBy        = suser_sname()
WHERE EntityName_EN = N'Assignments'
  AND Column_EN     = N'ResourceName'
  AND MapStatus    <> N'MANUAL';

/* Assignments : AllUpdatesApplied + UpdatesAppliedDate via jAssignApplied */
UPDATE dic.EntityColumnPublication
SET PsseSourceSchema = N'pjrep',
    PsseSourceObject = N'MSP_EpmAssignmentsApplied_UserView',
    PsseColumnName   = ecp.Column_EN,
    SourceAlias      = N'jAssignApplied',
    SourceExpression = N'jAssignApplied.' + QUOTENAME(ecp.Column_EN),
    MapStatus        = N'MAPPED',
    IsPublished      = 1,
    PublishedOn      = sysdatetime(),
    UpdatedOn        = sysdatetime(),
    UpdatedBy        = suser_sname()
FROM dic.EntityColumnPublication ecp
WHERE ecp.EntityName_EN = N'Assignments'
  AND ecp.Column_EN IN (N'AssignmentAllUpdatesApplied', N'AssignmentUpdatesAppliedDate')
  AND ecp.MapStatus    <> N'MANUAL';

/* Projects : ProjectTimephased (PSSE : TimePhased dans MSP_ProjectTimephasedRollupInfo_ODATAView) */
UPDATE dic.EntityColumnPublication
SET PsseSourceSchema = N'pjrep',
    PsseSourceObject = N'MSP_ProjectTimephasedRollupInfo_ODATAView',
    PsseColumnName   = N'TimePhased',
    SourceAlias      = N'jPTRI',
    SourceExpression = N'jPTRI.[TimePhased]',
    MapStatus        = N'MAPPED',
    IsPublished      = 1,
    PublishedOn      = sysdatetime(),
    UpdatedOn        = sysdatetime(),
    UpdatedBy        = suser_sname()
WHERE EntityName_EN = N'Projects'
  AND Column_EN     = N'ProjectTimephased'
  AND MapStatus    <> N'MANUAL';

/* Projects : WorkflowCreatedDate (PSSE : WorkflowCreated) + WorkflowOwnerId (PSSE : WorkflowOwner) */
UPDATE dic.EntityColumnPublication
SET PsseSourceSchema = N'pjrep',
    PsseSourceObject = N'MSP_EpmWorkflowInstance_UserView',
    PsseColumnName   = CASE ecp.Column_EN
                           WHEN N'WorkflowCreatedDate' THEN N'WorkflowCreated'
                           WHEN N'WorkflowOwnerId'     THEN N'WorkflowOwner'
                       END,
    SourceAlias      = N'jWFI',
    SourceExpression = CASE ecp.Column_EN
                           WHEN N'WorkflowCreatedDate' THEN N'jWFI.[WorkflowCreated]'
                           WHEN N'WorkflowOwnerId'     THEN N'jWFI.[WorkflowOwner]'
                       END,
    MapStatus        = N'MAPPED',
    IsPublished      = 1,
    PublishedOn      = sysdatetime(),
    UpdatedOn        = sysdatetime(),
    UpdatedBy        = suser_sname()
FROM dic.EntityColumnPublication ecp
WHERE ecp.EntityName_EN = N'Projects'
  AND ecp.Column_EN IN (N'WorkflowCreatedDate', N'WorkflowOwnerId')
  AND ecp.MapStatus    <> N'MANUAL';

/* Projects : WorkflowOwnerName (PSSE : ResourceName dans jWFOwner — jointure imbriquée) */
UPDATE dic.EntityColumnPublication
SET PsseSourceSchema = N'pjrep',
    PsseSourceObject = N'MSP_EpmResource_UserView',
    PsseColumnName   = N'ResourceName',
    SourceAlias      = N'jWFOwner',
    SourceExpression = N'jWFOwner.[ResourceName]',
    MapStatus        = N'MAPPED',
    IsPublished      = 1,
    PublishedOn      = sysdatetime(),
    UpdatedOn        = sysdatetime(),
    UpdatedBy        = suser_sname()
WHERE EntityName_EN = N'Projects'
  AND Column_EN     = N'WorkflowOwnerName'
  AND MapStatus    <> N'MANUAL';

/* Projects : EnterpriseProjectTypeIsDefault (PSSE : IsDefault dans le join EPT auto-détecté) */
UPDATE ecp
SET ecp.PsseColumnName   = N'IsDefault',
    ecp.SourceAlias      = ej.JoinAlias,
    ecp.SourceExpression = QUOTENAME(ej.JoinAlias) + N'.[IsDefault]',
    ecp.MapStatus        = N'MAPPED',
    ecp.IsPublished      = 1,
    ecp.PublishedOn      = sysdatetime(),
    ecp.UpdatedOn        = sysdatetime(),
    ecp.UpdatedBy        = suser_sname()
FROM dic.EntityColumnPublication ecp
JOIN dic.EntityJoin ej
    ON  ej.EntityName_EN = N'Projects'
    AND ej.PsseObjectName = N'MSP_EpmEnterpriseProjectType'
    AND ej.IsActive = 1
WHERE ecp.EntityName_EN = N'Projects'
  AND ecp.Column_EN     = N'EnterpriseProjectTypeIsDefault'
  AND ecp.MapStatus    <> N'MANUAL';

/* Projects : ProjectWorkspaceInternalUrl (PSSE : ProjectWorkspaceInternalHRef dans src primaire) */
UPDATE dic.EntityColumnPublication
SET PsseSourceSchema = N'pjrep',
    PsseSourceObject = N'MSP_EpmProject_UserView',
    PsseColumnName   = N'ProjectWorkspaceInternalHRef',
    SourceAlias      = N'src',
    SourceExpression = N'src.[ProjectWorkspaceInternalHRef]',
    MapStatus        = N'MAPPED',
    IsPublished      = 1,
    PublishedOn      = sysdatetime(),
    UpdatedOn        = sysdatetime(),
    UpdatedBy        = suser_sname()
WHERE EntityName_EN = N'Projects'
  AND Column_EN     = N'ProjectWorkspaceInternalUrl'
  AND MapStatus    <> N'MANUAL';

/* --- E4 suite : jointures supplémentaires (TimeSet, TimesheetLines, TimesheetLineActualDataSet) --- */
MERGE dic.EntityJoin AS T
USING
(
    VALUES
        /* TimeSet : FiscalPeriodModifiedDate via FiscalPeriodUID (j1 auto-détecté utilise SiteId — incorrect) */
        (N'TimeSet', N'jFP', N'pjrep', N'MSP_FiscalPeriods_ODATAView', N'src_pjrep',
         N'jFP', N'LEFT', N'jFP.FiscalPeriodUID = src.FiscalPeriodUID', 1, N'MANUAL'),
        /* TimesheetLines : MSP_TimesheetLine (non-UserView) via TimesheetLineUID pour Comment + ApproverUID */
        (N'TimesheetLines', N'jTSLine', N'pjrep', N'MSP_TimesheetLine', N'src_pjrep',
         N'jTSLine', N'LEFT', N'jTSLine.TimesheetLineUID = src.TimesheetLineUID', 1, N'MANUAL'),
        /* TimesheetLines : approuveur — jointure imbriquée (jTSLineAppr < jTSLine alphabétiquement)  */
        /* IMPORTANT : jTSLine doit précéder jTSLineAppr dans la clause FROM.                        */
        /* L'ordre alphabétique de STRING_AGG garantit jTSLine avant jTSLineAppr. ✓                 */
        (N'TimesheetLines', N'jTSLineAppr', N'pjrep', N'MSP_EpmResource_UserView', N'src_pjrep',
         N'jTSLineAppr', N'LEFT', N'jTSLineAppr.ResourceUID = jTSLine.ApproverResourceNameUID', 1, N'MANUAL'),
        /* TimesheetLines : classe feuille de temps (description) */
        (N'TimesheetLines', N'jTSClass', N'pjrep', N'MSP_TimesheetClass_UserView', N'src_pjrep',
         N'jTSClass', N'LEFT', N'jTSClass.ClassUID = src.TimesheetLineClassUID', 1, N'MANUAL'),
        /* TimesheetLineActualDataSet : dernière ressource modificatrice */
        (N'TimesheetLineActualDataSet', N'jLastChanged', N'pjrep', N'MSP_EpmResource_UserView', N'src_pjrep',
         N'jLastChanged', N'LEFT', N'jLastChanged.ResourceUID = src.LastChangedResourceNameUID', 1, N'MANUAL')
) AS S (EntityName_EN, JoinTag, PsseSchemaName, PsseObjectName, SmartBoxSchemaName,
        JoinAlias, JoinType, JoinExpression, IsActive, JoinStatus)
ON  T.EntityName_EN = S.EntityName_EN
AND T.JoinTag       = S.JoinTag
WHEN MATCHED AND T.JoinStatus <> N'MANUAL' THEN
    UPDATE SET T.PsseSchemaName=S.PsseSchemaName, T.PsseObjectName=S.PsseObjectName,
               T.SmartBoxSchemaName=S.SmartBoxSchemaName, T.JoinAlias=S.JoinAlias,
               T.JoinType=S.JoinType, T.JoinExpression=S.JoinExpression,
               T.IsActive=S.IsActive, T.JoinStatus=S.JoinStatus,
               T.UpdatedOn=sysdatetime(), T.UpdatedBy=suser_sname()
WHEN NOT MATCHED THEN
    INSERT (EntityName_EN, JoinTag, PsseSchemaName, PsseObjectName, SmartBoxSchemaName,
            JoinAlias, JoinType, JoinExpression, IsActive, JoinStatus)
    VALUES (S.EntityName_EN, S.JoinTag, S.PsseSchemaName, S.PsseObjectName, S.SmartBoxSchemaName,
            S.JoinAlias, S.JoinType, S.JoinExpression, S.IsActive, S.JoinStatus);

/* --- E4 : Group A — Colonnes dont OData ajoute un préfixe d'entité absent dans PSSE (src primaire) --- */
UPDATE dic.EntityColumnPublication
SET PsseColumnName   = CASE Column_EN
        WHEN N'BusinessDriverCreatedDate'   THEN N'CreatedDate'
        WHEN N'BusinessDriverModifiedDate'  THEN N'ModifiedDate'
        WHEN N'EngagementCreatedDate'       THEN N'CreatedDate'
        WHEN N'EngagementReviewedDate'      THEN N'ReviewedDate'
        WHEN N'EngagementStatus'            THEN N'Status'
        WHEN N'EngagementSubmittedDate'     THEN N'SubmittedDate'
        WHEN N'CommentCreatedDate'          THEN N'CreatedDate'
        WHEN N'FiscalPeriodModifiedDate'    THEN N'ModifiedDate'
        WHEN N'PrioritizationCreatedDate'   THEN N'CreatedDate'
        WHEN N'PrioritizationModifiedDate'  THEN N'ModifiedDate'
        WHEN N'StageLastSubmittedDate'      THEN N'StageLastSubmitted'
        WHEN N'TimesheetClassName'          THEN N'ClassName'
        WHEN N'TimesheetClassType'          THEN N'Type'
    END,
    SourceAlias      = N'src',
    SourceExpression = N'src.' + QUOTENAME(CASE Column_EN
        WHEN N'BusinessDriverCreatedDate'   THEN N'CreatedDate'
        WHEN N'BusinessDriverModifiedDate'  THEN N'ModifiedDate'
        WHEN N'EngagementCreatedDate'       THEN N'CreatedDate'
        WHEN N'EngagementReviewedDate'      THEN N'ReviewedDate'
        WHEN N'EngagementStatus'            THEN N'Status'
        WHEN N'EngagementSubmittedDate'     THEN N'SubmittedDate'
        WHEN N'CommentCreatedDate'          THEN N'CreatedDate'
        WHEN N'FiscalPeriodModifiedDate'    THEN N'ModifiedDate'
        WHEN N'PrioritizationCreatedDate'   THEN N'CreatedDate'
        WHEN N'PrioritizationModifiedDate'  THEN N'ModifiedDate'
        WHEN N'StageLastSubmittedDate'      THEN N'StageLastSubmitted'
        WHEN N'TimesheetClassName'          THEN N'ClassName'
        WHEN N'TimesheetClassType'          THEN N'Type'
    END),
    MapStatus        = N'MAPPED',
    IsPublished      = 1,
    PublishedOn      = sysdatetime(),
    UpdatedOn        = sysdatetime(),
    UpdatedBy        = suser_sname()
WHERE EntityName_EN IN (N'BusinessDrivers', N'Engagements', N'EngagementsComments',
                        N'FiscalPeriods', N'Prioritizations', N'ProjectWorkflowStageDataSet',
                        N'TimesheetClasses')
  AND Column_EN IN (N'BusinessDriverCreatedDate', N'BusinessDriverModifiedDate',
                    N'EngagementCreatedDate', N'EngagementReviewedDate',
                    N'EngagementStatus', N'EngagementSubmittedDate',
                    N'CommentCreatedDate', N'FiscalPeriodModifiedDate',
                    N'PrioritizationCreatedDate', N'PrioritizationModifiedDate',
                    N'StageLastSubmittedDate', N'TimesheetClassName', N'TimesheetClassType')
  AND MapStatus <> N'MANUAL';

/* TimeSet.FiscalPeriodModifiedDate : via jFP (FiscalPeriodUID, pas SiteId) */
UPDATE dic.EntityColumnPublication
SET PsseColumnName   = N'ModifiedDate',
    SourceAlias      = N'jFP',
    SourceExpression = N'jFP.[ModifiedDate]',
    MapStatus        = N'MAPPED',
    IsPublished      = 1,
    PublishedOn      = sysdatetime(),
    UpdatedOn        = sysdatetime(),
    UpdatedBy        = suser_sname()
WHERE EntityName_EN = N'TimeSet'
  AND Column_EN     = N'FiscalPeriodModifiedDate'
  AND MapStatus    <> N'MANUAL';

/* --- E4 : Group B — TimesheetLines : renames source primaire + nouvelles jointures --- */
/* Colonnes dans src (MSP_TimesheetLine_UserView) avec nom PSSE différent d'OData */
UPDATE dic.EntityColumnPublication
SET PsseColumnName   = CASE Column_EN
        WHEN N'TimesheetClassName'     THEN N'TimesheetLineClass'
        WHEN N'TimesheetClassType'     THEN N'TimesheetLineClassType'
        WHEN N'TimesheetPeriodId'      THEN N'PeriodUID'
        WHEN N'TimesheetPeriodName'    THEN N'PeriodName'
        WHEN N'TimesheetPeriodStatus'  THEN N'PeriodStatus'
        WHEN N'TimesheetPeriodStatusId'THEN N'PeriodStatusID'
    END,
    SourceAlias      = N'src',
    SourceExpression = N'src.' + QUOTENAME(CASE Column_EN
        WHEN N'TimesheetClassName'     THEN N'TimesheetLineClass'
        WHEN N'TimesheetClassType'     THEN N'TimesheetLineClassType'
        WHEN N'TimesheetPeriodId'      THEN N'PeriodUID'
        WHEN N'TimesheetPeriodName'    THEN N'PeriodName'
        WHEN N'TimesheetPeriodStatus'  THEN N'PeriodStatus'
        WHEN N'TimesheetPeriodStatusId'THEN N'PeriodStatusID'
    END),
    MapStatus        = N'MAPPED',
    IsPublished      = 1,
    PublishedOn      = sysdatetime(),
    UpdatedOn        = sysdatetime(),
    UpdatedBy        = suser_sname()
WHERE EntityName_EN = N'TimesheetLines'
  AND Column_EN IN (N'TimesheetClassName', N'TimesheetClassType',
                    N'TimesheetPeriodId', N'TimesheetPeriodName',
                    N'TimesheetPeriodStatus', N'TimesheetPeriodStatusId')
  AND MapStatus <> N'MANUAL';

/* TimesheetLines : colonnes depuis jTSLine (MSP_TimesheetLine non-UserView) */
UPDATE dic.EntityColumnPublication
SET PsseColumnName   = CASE Column_EN
        WHEN N'TimesheetApproverResourceId'  THEN N'ApproverResourceNameUID'
        WHEN N'TimesheetLineComment'          THEN N'Comment'
    END,
    SourceAlias      = N'jTSLine',
    SourceExpression = N'jTSLine.' + QUOTENAME(CASE Column_EN
        WHEN N'TimesheetApproverResourceId'  THEN N'ApproverResourceNameUID'
        WHEN N'TimesheetLineComment'          THEN N'Comment'
    END),
    MapStatus        = N'MAPPED',
    IsPublished      = 1,
    PublishedOn      = sysdatetime(),
    UpdatedOn        = sysdatetime(),
    UpdatedBy        = suser_sname()
WHERE EntityName_EN = N'TimesheetLines'
  AND Column_EN IN (N'TimesheetApproverResourceId', N'TimesheetLineComment')
  AND MapStatus <> N'MANUAL';

/* TimesheetLines : ApproverResourceName depuis jTSLineAppr (jointure imbriquée) */
UPDATE dic.EntityColumnPublication
SET PsseSourceSchema = N'pjrep',
    PsseSourceObject = N'MSP_EpmResource_UserView',
    PsseColumnName   = N'ResourceName',
    SourceAlias      = N'jTSLineAppr',
    SourceExpression = N'jTSLineAppr.[ResourceName]',
    MapStatus        = N'MAPPED',
    IsPublished      = 1,
    PublishedOn      = sysdatetime(),
    UpdatedOn        = sysdatetime(),
    UpdatedBy        = suser_sname()
WHERE EntityName_EN = N'TimesheetLines'
  AND Column_EN     = N'TimesheetApproverResourceName'
  AND MapStatus    <> N'MANUAL';

/* TimesheetLines : ClassDescription depuis jTSClass */
UPDATE dic.EntityColumnPublication
SET PsseSourceSchema = N'pjrep',
    PsseSourceObject = N'MSP_TimesheetClass_UserView',
    PsseColumnName   = N'Description',
    SourceAlias      = N'jTSClass',
    SourceExpression = N'jTSClass.[Description]',
    MapStatus        = N'MAPPED',
    IsPublished      = 1,
    PublishedOn      = sysdatetime(),
    UpdatedOn        = sysdatetime(),
    UpdatedBy        = suser_sname()
WHERE EntityName_EN = N'TimesheetLines'
  AND Column_EN     = N'TimesheetClassDescription'
  AND MapStatus    <> N'MANUAL';

/* --- E4 : Group C — TimesheetLineActualDataSet : LastChangedResourceName via jLastChanged --- */
UPDATE dic.EntityColumnPublication
SET PsseSourceSchema = N'pjrep',
    PsseSourceObject = N'MSP_EpmResource_UserView',
    PsseColumnName   = N'ResourceName',
    SourceAlias      = N'jLastChanged',
    SourceExpression = N'jLastChanged.[ResourceName]',
    MapStatus        = N'MAPPED',
    IsPublished      = 1,
    PublishedOn      = sysdatetime(),
    UpdatedOn        = sysdatetime(),
    UpdatedBy        = suser_sname()
WHERE EntityName_EN = N'TimesheetLineActualDataSet'
  AND Column_EN     = N'LastChangedResourceName'
  AND MapStatus    <> N'MANUAL';

/* --- E4 : Phase G – Timesheets : jointures depuis script de référence externe validé ---
   src primaire = MSP_Timesheet (PeriodUID, TimesheetStatusID disponibles)
   Référence : MSP_TimesheetLine_UserView ← MSP_TimesheetPeriod, MSP_TimesheetStatus
*/
MERGE dic.EntityJoin AS tgt
USING (VALUES
    (N'Timesheets', N'jTP',  N'pjrep', N'MSP_TimesheetPeriod',  N'src_pjrep', N'jTP',  N'LEFT',
     N'jTP.PeriodUID = src.PeriodUID',                1, N'MANUAL'),
    (N'Timesheets', N'jTST', N'pjrep', N'MSP_TimesheetStatus',  N'src_pjrep', N'jTST', N'LEFT',
     N'jTST.TimesheetStatusID = src.TimesheetStatusID', 1, N'MANUAL')
) AS src (EntityName_EN, JoinTag, PsseSchemaName, PsseObjectName, SmartBoxSchemaName,
          JoinAlias, JoinType, JoinExpression, IsActive, JoinStatus)
ON  tgt.EntityName_EN = src.EntityName_EN
AND tgt.JoinTag       = src.JoinTag
WHEN NOT MATCHED THEN
    INSERT (EntityName_EN, JoinTag, PsseSchemaName, PsseObjectName, SmartBoxSchemaName,
            JoinAlias, JoinType, JoinExpression, IsActive, JoinStatus)
    VALUES (src.EntityName_EN, src.JoinTag, src.PsseSchemaName, src.PsseObjectName,
            src.SmartBoxSchemaName, src.JoinAlias, src.JoinType, src.JoinExpression,
            src.IsActive, src.JoinStatus)
WHEN MATCHED AND tgt.JoinStatus <> N'MANUAL' THEN
    UPDATE SET JoinExpression = src.JoinExpression, JoinStatus = src.JoinStatus,
               UpdatedOn = sysdatetime(), UpdatedBy = suser_sname();

/* Timesheets — Description = src.Comment (MSP_Timesheet.Comment) */
UPDATE dic.EntityColumnPublication
SET PsseColumnName   = N'Comment',
    SourceAlias      = N'src',
    SourceExpression = N'src.[Comment]',
    MapStatus        = N'MAPPED',
    IsPublished      = 1,
    PublishedOn      = sysdatetime(),
    UpdatedOn        = sysdatetime(),
    UpdatedBy        = suser_sname()
WHERE EntityName_EN = N'Timesheets' AND Column_EN = N'Description' AND MapStatus <> N'MANUAL';

/* Timesheets — EndDate + StartDate → jTP */
UPDATE dic.EntityColumnPublication
SET SourceAlias      = N'jTP',
    SourceExpression = N'jTP.' + QUOTENAME(PsseColumnName),
    MapStatus        = N'MAPPED',
    IsPublished      = 1,
    PublishedOn      = sysdatetime(),
    UpdatedOn        = sysdatetime(),
    UpdatedBy        = suser_sname()
WHERE EntityName_EN = N'Timesheets'
  AND Column_EN IN (N'EndDate', N'StartDate')
  AND MapStatus    <> N'MANUAL';

/* Timesheets — StatusDescription = jTST.Description */
UPDATE dic.EntityColumnPublication
SET PsseColumnName   = N'Description',
    SourceAlias      = N'jTST',
    SourceExpression = N'jTST.[Description]',
    MapStatus        = N'MAPPED',
    IsPublished      = 1,
    PublishedOn      = sysdatetime(),
    UpdatedOn        = sysdatetime(),
    UpdatedBy        = suser_sname()
WHERE EntityName_EN = N'Timesheets' AND Column_EN = N'StatusDescription' AND MapStatus <> N'MANUAL';

/* --- E4 : Phase H – TimeSet : FiscalPeriodStart/Year via jFP (jointure déjà existante) ---
   jFP.FiscalPeriodUID = src.FiscalPeriodUID (MSP_TimeByDay a FiscalPeriodUID)
*/
UPDATE dic.EntityColumnPublication
SET SourceAlias      = N'jFP',
    SourceExpression = N'jFP.' + QUOTENAME(PsseColumnName),
    MapStatus        = N'MAPPED',
    IsPublished      = 1,
    PublishedOn      = sysdatetime(),
    UpdatedOn        = sysdatetime(),
    UpdatedBy        = suser_sname()
WHERE EntityName_EN = N'TimeSet'
  AND Column_EN IN (N'FiscalPeriodStart', N'FiscalPeriodYear')
  AND MapStatus    <> N'MANUAL';

/* --- E4 : Phase I – TimesheetClasses : TimesheetClassId → src.ClassUID ---
   MSP_TimesheetClass_UserView expose ClassUID (pas TimesheetClassUID)
*/
UPDATE dic.EntityColumnPublication
SET PsseColumnName   = N'ClassUID',
    SourceAlias      = N'src',
    SourceExpression = N'src.[ClassUID]',
    MapStatus        = N'MAPPED',
    IsPublished      = 1,
    PublishedOn      = sysdatetime(),
    UpdatedOn        = sysdatetime(),
    UpdatedBy        = suser_sname()
WHERE EntityName_EN = N'TimesheetClasses' AND Column_EN = N'TimesheetClassId' AND MapStatus <> N'MANUAL';

/* --- E4 : Phase J – jProject / jTask pour entités baseline/timephased ---
   Entités avec ProjectUID direct → jProject.ProjectName
   Entités avec TaskUID direct    → jTask.TaskName
*/
MERGE dic.EntityJoin AS tgt
USING (VALUES
    /* jProject — MSP_EpmProject_UserView */
    (N'AssignmentBaselines',              N'jProject', N'pjrep', N'MSP_EpmProject_UserView',
     N'src_pjrep', N'jProject', N'LEFT', N'jProject.ProjectUID = src.ProjectUID', 1, N'MANUAL'),
    (N'AssignmentBaselineTimephasedDataSet', N'jProject', N'pjrep', N'MSP_EpmProject_UserView',
     N'src_pjrep', N'jProject', N'LEFT', N'jProject.ProjectUID = src.ProjectUID', 1, N'MANUAL'),
    (N'Deliverables',                     N'jProject', N'pjrep', N'MSP_EpmProject_UserView',
     N'src_pjrep', N'jProject', N'LEFT', N'jProject.ProjectUID = src.ProjectUID', 1, N'MANUAL'),
    (N'Issues',                           N'jProject', N'pjrep', N'MSP_EpmProject_UserView',
     N'src_pjrep', N'jProject', N'LEFT', N'jProject.ProjectUID = src.ProjectUID', 1, N'MANUAL'),
    (N'Risks',                            N'jProject', N'pjrep', N'MSP_EpmProject_UserView',
     N'src_pjrep', N'jProject', N'LEFT', N'jProject.ProjectUID = src.ProjectUID', 1, N'MANUAL'),
    (N'ProjectBaselines',                 N'jProject', N'pjrep', N'MSP_EpmProject_UserView',
     N'src_pjrep', N'jProject', N'LEFT', N'jProject.ProjectUID = src.ProjectUID', 1, N'MANUAL'),
    (N'TaskBaselines',                    N'jProject', N'pjrep', N'MSP_EpmProject_UserView',
     N'src_pjrep', N'jProject', N'LEFT', N'jProject.ProjectUID = src.ProjectUID', 1, N'MANUAL'),
    (N'TaskBaselineTimephasedDataSet',    N'jProject', N'pjrep', N'MSP_EpmProject_UserView',
     N'src_pjrep', N'jProject', N'LEFT', N'jProject.ProjectUID = src.ProjectUID', 1, N'MANUAL'),
    (N'TaskTimephasedDataSet',            N'jProject', N'pjrep', N'MSP_EpmProject_UserView',
     N'src_pjrep', N'jProject', N'LEFT', N'jProject.ProjectUID = src.ProjectUID', 1, N'MANUAL'),
    (N'EngagementsTimephasedDataSet',     N'jProject', N'pjrep', N'MSP_EpmProject_UserView',
     N'src_pjrep', N'jProject', N'LEFT', N'jProject.ProjectUID = src.ProjectUID', 1, N'MANUAL'),
    /* jTask — MSP_EpmTask_UserView */
    (N'AssignmentBaselines',              N'jTask', N'pjrep', N'MSP_EpmTask_UserView',
     N'src_pjrep', N'jTask', N'LEFT', N'jTask.TaskUID = src.TaskUID', 1, N'MANUAL'),
    (N'AssignmentBaselineTimephasedDataSet', N'jTask', N'pjrep', N'MSP_EpmTask_UserView',
     N'src_pjrep', N'jTask', N'LEFT', N'jTask.TaskUID = src.TaskUID', 1, N'MANUAL'),
    (N'TaskBaselines',                    N'jTask', N'pjrep', N'MSP_EpmTask_UserView',
     N'src_pjrep', N'jTask', N'LEFT', N'jTask.TaskUID = src.TaskUID', 1, N'MANUAL'),
    (N'TaskBaselineTimephasedDataSet',    N'jTask', N'pjrep', N'MSP_EpmTask_UserView',
     N'src_pjrep', N'jTask', N'LEFT', N'jTask.TaskUID = src.TaskUID', 1, N'MANUAL'),
    (N'TaskTimephasedDataSet',            N'jTask', N'pjrep', N'MSP_EpmTask_UserView',
     N'src_pjrep', N'jTask', N'LEFT', N'jTask.TaskUID = src.TaskUID', 1, N'MANUAL')
) AS src (EntityName_EN, JoinTag, PsseSchemaName, PsseObjectName, SmartBoxSchemaName,
          JoinAlias, JoinType, JoinExpression, IsActive, JoinStatus)
ON  tgt.EntityName_EN = src.EntityName_EN
AND tgt.JoinTag       = src.JoinTag
WHEN NOT MATCHED THEN
    INSERT (EntityName_EN, JoinTag, PsseSchemaName, PsseObjectName, SmartBoxSchemaName,
            JoinAlias, JoinType, JoinExpression, IsActive, JoinStatus)
    VALUES (src.EntityName_EN, src.JoinTag, src.PsseSchemaName, src.PsseObjectName,
            src.SmartBoxSchemaName, src.JoinAlias, src.JoinType, src.JoinExpression,
            src.IsActive, src.JoinStatus)
WHEN MATCHED AND tgt.JoinStatus <> N'MANUAL' THEN
    UPDATE SET JoinExpression = src.JoinExpression, JoinStatus = src.JoinStatus,
               UpdatedOn = sysdatetime(), UpdatedBy = suser_sname();

/* Phase J — ProjectName → jProject.ProjectName pour toutes les entités ci-dessus */
UPDATE dic.EntityColumnPublication
SET SourceAlias      = N'jProject',
    SourceExpression = N'jProject.[ProjectName]',
    MapStatus        = N'MAPPED',
    IsPublished      = 1,
    PublishedOn      = sysdatetime(),
    UpdatedOn        = sysdatetime(),
    UpdatedBy        = suser_sname()
WHERE EntityName_EN IN (N'AssignmentBaselines', N'AssignmentBaselineTimephasedDataSet',
                        N'Deliverables', N'Issues', N'Risks', N'ProjectBaselines',
                        N'TaskBaselines', N'TaskBaselineTimephasedDataSet',
                        N'TaskTimephasedDataSet', N'EngagementsTimephasedDataSet')
  AND Column_EN    = N'ProjectName'
  AND MapStatus   <> N'MANUAL';

/* Phase J — TaskName → jTask.TaskName */
UPDATE dic.EntityColumnPublication
SET SourceAlias      = N'jTask',
    SourceExpression = N'jTask.[TaskName]',
    MapStatus        = N'MAPPED',
    IsPublished      = 1,
    PublishedOn      = sysdatetime(),
    UpdatedOn        = sysdatetime(),
    UpdatedBy        = suser_sname()
WHERE EntityName_EN IN (N'AssignmentBaselines', N'AssignmentBaselineTimephasedDataSet',
                        N'TaskBaselines', N'TaskBaselineTimephasedDataSet',
                        N'TaskTimephasedDataSet')
  AND Column_EN  = N'TaskName'
  AND MapStatus <> N'MANUAL';

/* --- E4 : Phase K – jResource pour ResourceTimephasedDataSet, ResourceDemandTimephasedDataSet,
                      EngagementsTimephasedDataSet
*/
MERGE dic.EntityJoin AS tgt
USING (VALUES
    (N'ResourceTimephasedDataSet',        N'jResource', N'pjrep', N'MSP_EpmResource_UserView',
     N'src_pjrep', N'jResource', N'LEFT', N'jResource.ResourceUID = src.ResourceUID', 1, N'MANUAL'),
    (N'ResourceDemandTimephasedDataSet',  N'jResource', N'pjrep', N'MSP_EpmResource_UserView',
     N'src_pjrep', N'jResource', N'LEFT', N'jResource.ResourceUID = src.ResourceUID', 1, N'MANUAL'),
    (N'EngagementsTimephasedDataSet',     N'jResource', N'pjrep', N'MSP_EpmResource_UserView',
     N'src_pjrep', N'jResource', N'LEFT', N'jResource.ResourceUID = src.ResourceUID', 1, N'MANUAL')
) AS src (EntityName_EN, JoinTag, PsseSchemaName, PsseObjectName, SmartBoxSchemaName,
          JoinAlias, JoinType, JoinExpression, IsActive, JoinStatus)
ON  tgt.EntityName_EN = src.EntityName_EN
AND tgt.JoinTag       = src.JoinTag
WHEN NOT MATCHED THEN
    INSERT (EntityName_EN, JoinTag, PsseSchemaName, PsseObjectName, SmartBoxSchemaName,
            JoinAlias, JoinType, JoinExpression, IsActive, JoinStatus)
    VALUES (src.EntityName_EN, src.JoinTag, src.PsseSchemaName, src.PsseObjectName,
            src.SmartBoxSchemaName, src.JoinAlias, src.JoinType, src.JoinExpression,
            src.IsActive, src.JoinStatus)
WHEN MATCHED AND tgt.JoinStatus <> N'MANUAL' THEN
    UPDATE SET JoinExpression = src.JoinExpression, JoinStatus = src.JoinStatus,
               UpdatedOn = sysdatetime(), UpdatedBy = suser_sname();

/* Phase K — ResourceName → jResource.ResourceName */
UPDATE dic.EntityColumnPublication
SET SourceAlias      = N'jResource',
    SourceExpression = N'jResource.[ResourceName]',
    MapStatus        = N'MAPPED',
    IsPublished      = 1,
    PublishedOn      = sysdatetime(),
    UpdatedOn        = sysdatetime(),
    UpdatedBy        = suser_sname()
WHERE EntityName_EN IN (N'ResourceTimephasedDataSet', N'ResourceDemandTimephasedDataSet',
                        N'EngagementsTimephasedDataSet')
  AND Column_EN  = N'ResourceName'
  AND MapStatus <> N'MANUAL';

/* Phase K — ResourceDemandTimephasedDataSet : renommages src (colonnes nommées différemment dans PSSE) */
UPDATE dic.EntityColumnPublication
SET PsseColumnName   = N'ProjectUtilizationDate',
    SourceAlias      = N'src',
    SourceExpression = N'src.[ProjectUtilizationDate]',
    MapStatus        = N'MAPPED',
    IsPublished      = 1,
    PublishedOn      = sysdatetime(),
    UpdatedOn        = sysdatetime(),
    UpdatedBy        = suser_sname()
WHERE EntityName_EN = N'ResourceDemandTimephasedDataSet'
  AND Column_EN     = N'ResourcePlanUtilizationDate'
  AND MapStatus    <> N'MANUAL';

UPDATE dic.EntityColumnPublication
SET PsseColumnName   = N'ProjectUtilizationSetting',
    SourceAlias      = N'src',
    SourceExpression = N'src.[ProjectUtilizationSetting]',
    MapStatus        = N'MAPPED',
    IsPublished      = 1,
    PublishedOn      = sysdatetime(),
    UpdatedOn        = sysdatetime(),
    UpdatedBy        = suser_sname()
WHERE EntityName_EN = N'ResourceDemandTimephasedDataSet'
  AND Column_EN     = N'ResourcePlanUtilizationType'
  AND MapStatus    <> N'MANUAL';

/* --- E4 : Phase L – EngagementsTimephasedDataSet : colonnes src directes (renommages OData/PSSE) ---
   MSP_EpmEngagementByDay_UserView : CommittedUnits, ProposedUnits, EngagementDate (≠ noms OData)
*/
UPDATE dic.EntityColumnPublication
SET PsseColumnName   = CASE Column_EN
        WHEN N'CommittedMaxUnits' THEN N'CommittedUnits'
        WHEN N'EngagementId'      THEN N'EngagementUID'
        WHEN N'EngagementName'    THEN N'EngagementName'
        WHEN N'ProjectId'         THEN N'ProjectUID'
        WHEN N'ProposedMaxUnits'  THEN N'ProposedUnits'
        WHEN N'ProposedWork'      THEN N'ProposedWork'
        WHEN N'CommittedWork'     THEN N'CommittedWork'
        WHEN N'ResourceId'        THEN N'ResourceUID'
        WHEN N'TimeByDay'         THEN N'EngagementDate'
    END,
    SourceAlias      = N'src',
    SourceExpression = N'src.' + QUOTENAME(CASE Column_EN
        WHEN N'CommittedMaxUnits' THEN N'CommittedUnits'
        WHEN N'EngagementId'      THEN N'EngagementUID'
        WHEN N'EngagementName'    THEN N'EngagementName'
        WHEN N'ProjectId'         THEN N'ProjectUID'
        WHEN N'ProposedMaxUnits'  THEN N'ProposedUnits'
        WHEN N'ProposedWork'      THEN N'ProposedWork'
        WHEN N'CommittedWork'     THEN N'CommittedWork'
        WHEN N'ResourceId'        THEN N'ResourceUID'
        WHEN N'TimeByDay'         THEN N'EngagementDate'
    END),
    MapStatus        = N'MAPPED',
    IsPublished      = 1,
    PublishedOn      = sysdatetime(),
    UpdatedOn        = sysdatetime(),
    UpdatedBy        = suser_sname()
WHERE EntityName_EN = N'EngagementsTimephasedDataSet'
  AND Column_EN IN (N'CommittedMaxUnits', N'EngagementId', N'EngagementName',
                   N'ProjectId', N'ProposedMaxUnits', N'ProposedWork',
                   N'CommittedWork', N'ResourceId', N'TimeByDay')
  AND MapStatus    <> N'MANUAL';

/* --- E4 : Phase M – Engagements : EngagementModifiedDate → src.ModifiedDate ---
   MSP_EpmEngagements_UserView expose ModifiedDate (préfixe OData "Engagement" strippé)
*/
UPDATE dic.EntityColumnPublication
SET PsseColumnName   = N'ModifiedDate',
    SourceAlias      = N'src',
    SourceExpression = N'src.[ModifiedDate]',
    MapStatus        = N'MAPPED',
    IsPublished      = 1,
    PublishedOn      = sysdatetime(),
    UpdatedOn        = sysdatetime(),
    UpdatedBy        = suser_sname()
WHERE EntityName_EN = N'Engagements'
  AND Column_EN     = N'EngagementModifiedDate'
  AND MapStatus    <> N'MANUAL';

/* --- E4 : Phase N – FiscalPeriodId via MSP_TimeByDay + ResourceModifiedDate via jResource ---
   MSP_EpmResourceByDay et MSP_EpmResourceDemandByDay_UserView n'ont pas FiscalPeriodUID direct.
   MSP_TimeByDay est la table calendrier PSSE : chaque jour a un FiscalPeriodUID.
   ResourceModifiedDate est dans MSP_EpmResource_UserView → jResource déjà créé en Phase K.
*/
MERGE dic.EntityJoin AS tgt
USING (VALUES
    (N'ResourceTimephasedDataSet',       N'jTBD', N'pjrep', N'MSP_TimeByDay', N'src_pjrep',
     N'jTBD', N'LEFT', N'jTBD.TimeByDay = src.TimeByDay', 1, N'MANUAL'),
    (N'ResourceDemandTimephasedDataSet', N'jTBD', N'pjrep', N'MSP_TimeByDay', N'src_pjrep',
     N'jTBD', N'LEFT', N'jTBD.TimeByDay = src.TimeByDay', 1, N'MANUAL')
) AS src (EntityName_EN, JoinTag, PsseSchemaName, PsseObjectName, SmartBoxSchemaName,
          JoinAlias, JoinType, JoinExpression, IsActive, JoinStatus)
ON  tgt.EntityName_EN = src.EntityName_EN
AND tgt.JoinTag       = src.JoinTag
WHEN NOT MATCHED THEN
    INSERT (EntityName_EN, JoinTag, PsseSchemaName, PsseObjectName, SmartBoxSchemaName,
            JoinAlias, JoinType, JoinExpression, IsActive, JoinStatus)
    VALUES (src.EntityName_EN, src.JoinTag, src.PsseSchemaName, src.PsseObjectName,
            src.SmartBoxSchemaName, src.JoinAlias, src.JoinType, src.JoinExpression,
            src.IsActive, src.JoinStatus)
WHEN MATCHED AND tgt.JoinStatus <> N'MANUAL' THEN
    UPDATE SET JoinExpression = src.JoinExpression, JoinStatus = src.JoinStatus,
               UpdatedOn = sysdatetime(), UpdatedBy = suser_sname();

/* Phase N — FiscalPeriodId → jTBD.FiscalPeriodUID */
UPDATE dic.EntityColumnPublication
SET PsseColumnName   = N'FiscalPeriodUID',
    SourceAlias      = N'jTBD',
    SourceExpression = N'jTBD.[FiscalPeriodUID]',
    MapStatus        = N'MAPPED',
    IsPublished      = 1,
    PublishedOn      = sysdatetime(),
    UpdatedOn        = sysdatetime(),
    UpdatedBy        = suser_sname()
WHERE EntityName_EN IN (N'ResourceTimephasedDataSet', N'ResourceDemandTimephasedDataSet')
  AND Column_EN     = N'FiscalPeriodId'
  AND MapStatus    <> N'MANUAL';

/* Phase N — ResourceModifiedDate → jResource.ResourceModifiedDate (jResource déjà créé Phase K) */
UPDATE dic.EntityColumnPublication
SET SourceAlias      = N'jResource',
    SourceExpression = N'jResource.[ResourceModifiedDate]',
    MapStatus        = N'MAPPED',
    IsPublished      = 1,
    PublishedOn      = sysdatetime(),
    UpdatedOn        = sysdatetime(),
    UpdatedBy        = suser_sname()
WHERE EntityName_EN = N'ResourceTimephasedDataSet'
  AND Column_EN     = N'ResourceModifiedDate'
  AND MapStatus    <> N'MANUAL';

DECLARE @E4Count int = @@ROWCOUNT;
SET @Msg = N'ETAPE E4 : toutes jointures dérivées insérées. Groups A/B/C + Phases G/H/I/J/K/L/M/N résolus.';
EXEC log.usp_WriteScriptLog
    @RunId=@RunId, @ScriptName=@ScriptName, @ScriptVersion=N'V6-DRAFT',
    @Phase=N'DERIVED_JOIN', @Severity=N'INFO', @Status=N'COMPLETED',
    @Message=@Msg, @RowsAffected=@E4Count;

/* ===========================================================================================
   ETAPE E5 : Marquage des jointures SiteId croisées (SITEID_CROSS)
   Certaines jointures auto-détectées utilisent uniquement [SiteId] = src.[SiteId] comme clé.
   SiteId est identique pour toutes les lignes d'un même tenant PWA : c'est un produit
   cartésien. On les marque MANUAL_REQUIRED pour les exclure de la génération de vues.
   Les colonnes dépendantes sont remises à UNMAPPED (CAST NULL) pour éviter des erreurs SQL
   à la compilation de la vue (référence à un alias non joint).
   Overrides MANUAL préservés. Les jointures E3/E4 utilisent SiteId COMBINÉ avec une clé
   métier (sans crochets) et ne sont pas affectées par ce filtre.
   =========================================================================================== */
DECLARE @SiteIdCrossCount int = 0;

UPDATE dic.EntityJoin
SET JoinExpression = N'/* TODO: SITEID_CROSS - remplacer par la vraie clé de jointure.'
    + N' SiteId est identique pour toutes les lignes PWA : produit cartésien garanti. */',
    JoinStatus     = N'MANUAL_REQUIRED',
    UpdatedOn      = sysdatetime(),
    UpdatedBy      = suser_sname()
WHERE JoinExpression LIKE N'%.[[]SiteId] = src.[[]SiteId]%'  /* [[] échappe [ dans SQL Server LIKE */
  AND JoinStatus  <> N'MANUAL';

SET @SiteIdCrossCount = @@ROWCOUNT;

/* Remettre à UNMAPPED (CAST NULL) les colonnes dont la source pointait vers une jointure croisée */
UPDATE ecp
SET ecp.SourceAlias      = NULL,
    ecp.SourceExpression = NULL,
    ecp.MapStatus        = N'UNMAPPED',
    ecp.IsPublished      = 1,
    ecp.UpdatedOn        = sysdatetime(),
    ecp.UpdatedBy        = suser_sname()
FROM dic.EntityColumnPublication ecp
JOIN dic.EntityJoin ej
    ON  ej.EntityName_EN = ecp.EntityName_EN
    AND ej.JoinAlias     = ecp.SourceAlias
    AND ej.JoinStatus    = N'MANUAL_REQUIRED'
    AND ej.JoinExpression LIKE N'%TODO: SITEID_CROSS%'
WHERE ecp.MapStatus <> N'MANUAL'
  AND ecp.SourceAlias IS NOT NULL;

SET @Msg = CONCAT(N'ETAPE E5 : ', @SiteIdCrossCount,
    N' jointure(s) SiteId croisée(s) marquées TODO (SITEID_CROSS).',
    N' Colonnes dépendantes remises à UNMAPPED (CAST NULL).',
    N' Mettre à jour dic.EntityJoin avec la vraie clé FK, puis rejouer v6_06a.');
EXEC log.usp_WriteScriptLog
    @RunId=@RunId, @ScriptName=@ScriptName, @ScriptVersion=N'V6-DRAFT',
    @Phase=N'SITEID_CROSS', @Severity=N'WARNING', @Status=N'WARNING',
    @Message=@Msg, @RowsAffected=@SiteIdCrossCount;

/* E5 – Cleanup : désactivation des joins MANUAL_REQUIRED sans référence colonne
   Ces joins auto-détectés (ETAPE E1) sont orphelins : aucune colonne publiée ne les utilise.
   Ils sont remplacés par des joins nommés explicitement (jProject, jTask, jTP, jTST,
   jWFI, jFP, jResource, jTBD, etc.) ajoutés en ETAPE E4 Phases G-N.
   MANUAL + IsActive=0 = protégé contre re-détection, exclu des vues et des warnings. */
DECLARE @OrphanDeactivatedCount int = 0;

UPDATE dic.EntityJoin
SET JoinStatus     = N'MANUAL',
    IsActive       = 0,
    JoinExpression = N'/* DEACTIVATED: join auto-détecté orphelin — remplacé par un join nommé explicite en ETAPE E4 */',
    UpdatedOn      = sysdatetime(),
    UpdatedBy      = suser_sname()
WHERE JoinStatus = N'MANUAL_REQUIRED'
  AND NOT EXISTS (
      SELECT 1 FROM dic.EntityColumnPublication ecp
      WHERE ecp.EntityName_EN = dic.EntityJoin.EntityName_EN
        AND ecp.SourceAlias   = dic.EntityJoin.JoinAlias
  );

SET @OrphanDeactivatedCount = @@ROWCOUNT;

SET @Msg = CONCAT(N'ETAPE E5 cleanup : ', @OrphanDeactivatedCount,
    N' join(s) MANUAL_REQUIRED orphelin(s) désactivé(s) (IsActive=0, MANUAL).',
    N' Aucune colonne publiée ne les référençait.');
EXEC log.usp_WriteScriptLog
    @RunId=@RunId, @ScriptName=@ScriptName, @ScriptVersion=N'V6-DRAFT',
    @Phase=N'ORPHAN_DEACTIVATE', @Severity=N'INFO', @Status=N'COMPLETED',
    @Message=@Msg, @RowsAffected=@OrphanDeactivatedCount;

/* Recompte après corrections E2-E5 */
SELECT
    @MappedCount          = SUM(CASE WHEN MapStatus = N'MAPPED'            THEN 1 ELSE 0 END),
    @MappedNeedsJoinCount = SUM(CASE WHEN MapStatus = N'MAPPED_NEEDS_JOIN' THEN 1 ELSE 0 END),
    @UnmappedCount        = SUM(CASE WHEN MapStatus = N'UNMAPPED'          THEN 1 ELSE 0 END),
    @NavigationCount      = SUM(CASE WHEN MapStatus = N'NAVIGATION'        THEN 1 ELSE 0 END)
FROM dic.EntityColumnPublication;

/* ===========================================================================================
   ETAPE E6 : Synchronisation dic.EntityColumnMap ← dic.EntityColumnPublication
   Écrit dans EntityColumnMap les résolutions effectuées par les étapes E2→E5.
   EntityColumnMap devient ainsi une documentation fidèle de l'état final.

   ColumnMatchStatus après sync :
     RESOLVED_V06A      = résolu par v6_06a (E2 normalisé, E3 correction, E4 jointure explicite)
     CONFIRMED_UNMAPPED = confirmé sans source PSSE identifiable (CAST NULL dans les vues)
     NAVIGATION         = lien navigationnel OData — pas une colonne de données
     MANUAL             = override manuel, jamais touché automatiquement
   =========================================================================================== */
DECLARE @SyncResolvedCount  int = 0;
DECLARE @SyncUnmappedCount  int = 0;
DECLARE @SyncNavCount       int = 0;

/* Sync 1 : Colonnes résolues dans ECP mais encore NULL dans ECM */
UPDATE ecm
SET ecm.PsseSourceSchema  = COALESCE(eb.PsseSchemaName, ej.PsseSchemaName),
    ecm.PsseSourceObject  = COALESCE(eb.PsseObjectName, ej.PsseObjectName),
    ecm.PsseColumnName    = ecp.PsseColumnName,
    ecm.PsseMatchScore    = 100,
    ecm.ColumnMatchStatus = N'RESOLVED_V06A',
    ecm.UpdatedOn         = sysdatetime(),
    ecm.UpdatedBy         = suser_sname()
FROM dic.EntityColumnMap ecm
JOIN dic.EntityColumnPublication ecp
    ON  ecp.EntityName_EN = ecm.EntityName_EN
    AND ecp.Column_EN     = ecm.Column_EN
LEFT JOIN dic.EntityBinding eb
    ON  eb.EntityName_EN = ecp.EntityName_EN
    AND ecp.SourceAlias  = N'src'
LEFT JOIN dic.EntityJoin ej
    ON  ej.EntityName_EN = ecp.EntityName_EN
    AND ej.JoinAlias     = ecp.SourceAlias
    AND ecp.SourceAlias <> N'src'
WHERE ecm.PsseColumnName   IS NULL
  AND ecp.MapStatus         = N'MAPPED'
  AND ecp.PsseColumnName    IS NOT NULL
  AND ecm.ColumnMatchStatus <> N'MANUAL';

SET @SyncResolvedCount = @@ROWCOUNT;

/* Sync 2 : Colonnes confirmées UNMAPPED (CAST NULL dans les vues) */
UPDATE ecm
SET ecm.ColumnMatchStatus = N'CONFIRMED_UNMAPPED',
    ecm.UpdatedOn         = sysdatetime(),
    ecm.UpdatedBy         = suser_sname()
FROM dic.EntityColumnMap ecm
JOIN dic.EntityColumnPublication ecp
    ON  ecp.EntityName_EN = ecm.EntityName_EN
    AND ecp.Column_EN     = ecm.Column_EN
WHERE ecp.MapStatus        = N'UNMAPPED'
  AND ecm.ColumnMatchStatus NOT IN (N'MANUAL', N'CONFIRMED_UNMAPPED');

SET @SyncUnmappedCount = @@ROWCOUNT;

/* Sync 3 : Colonnes NAVIGATION (liens OData, absentes des vues de données) */
UPDATE ecm
SET ecm.ColumnMatchStatus = N'NAVIGATION',
    ecm.UpdatedOn         = sysdatetime(),
    ecm.UpdatedBy         = suser_sname()
FROM dic.EntityColumnMap ecm
JOIN dic.EntityColumnPublication ecp
    ON  ecp.EntityName_EN = ecm.EntityName_EN
    AND ecp.Column_EN     = ecm.Column_EN
WHERE ecp.MapStatus        = N'NAVIGATION'
  AND ecm.ColumnMatchStatus NOT IN (N'MANUAL', N'NAVIGATION');

SET @SyncNavCount = @@ROWCOUNT;

SET @Msg = CONCAT(
    N'ETAPE E6 : sync EntityColumnMap terminé. RESOLVED_V06A=', @SyncResolvedCount,
    N'; CONFIRMED_UNMAPPED=', @SyncUnmappedCount,
    N'; NAVIGATION=', @SyncNavCount, N'.'
);
EXEC log.usp_WriteScriptLog
    @RunId=@RunId, @ScriptName=@ScriptName, @ScriptVersion=N'V6-DRAFT',
    @Phase=N'SYNC_ECM', @Severity=N'INFO', @Status=N'COMPLETED',
    @Message=@Msg, @RowsAffected=@SyncResolvedCount;

/* ===========================================================================================
   ETAPE F : Journal de construction (stg.EntityDraftBuildLog)
   =========================================================================================== */

/* Entites sans binding résolu */
INSERT INTO stg.EntityDraftBuildLog (RunId, EntityName_EN, Phase, Severity, Message)
SELECT
    @RunId,
    e.EntityName_EN,
    N'BINDING_QUALITY',
    N'WARN',
    CONCAT(
        N'Entite [', e.EntityName_EN, N'] : binding non résolu',
        N' (ConfidenceLevel=', ISNULL(eb.ConfidenceLevel, N'ABSENT'), N').',
        N' Definir un binding manuel dans dic.EntityBinding.'
    )
FROM dic.Entity e
LEFT JOIN dic.EntityBinding eb
    ON eb.EntityName_EN = e.EntityName_EN
   AND eb.IsActive = 1
WHERE e.IsActive = 1
  AND (eb.EntityBindingId IS NULL
       OR eb.PsseObjectName IS NULL
       OR eb.ConfidenceLevel IN (N'LOW', N'NONE'));

/* Jointures MANUAL_REQUIRED */
INSERT INTO stg.EntityDraftBuildLog (RunId, EntityName_EN, Phase, Severity, Message)
SELECT
    @RunId,
    EntityName_EN,
    N'JOIN_QUALITY',
    N'WARN',
    CONCAT(
        N'Entite [', EntityName_EN, N'] jointure [', JoinTag, N'] vers [', PsseObjectName, N'] : ',
        N'expression manuelle requise. Mettre à jour dic.EntityJoin.JoinExpression.'
    )
FROM dic.EntityJoin
WHERE JoinStatus = N'MANUAL_REQUIRED'
  AND IsActive = 1;

/* Colonnes MAPPED_NEEDS_JOIN */
IF @MappedNeedsJoinCount > 0
BEGIN
    INSERT INTO stg.EntityDraftBuildLog (RunId, Phase, Severity, Message)
    VALUES (
        @RunId,
        N'MAP_QUALITY',
        N'WARN',
        CONCAT(
            @MappedNeedsJoinCount,
            N' colonne(s) MAPPED_NEEDS_JOIN dans dic.EntityColumnPublication. ',
            N'Ces colonnes ont une source PSSE connue mais la jointure n''est pas définie. ',
            N'Resoudre dic.EntityJoin.JoinExpression correspondant, puis rejouer v6_06a.'
        )
    );
END;

/* Colonnes UNMAPPED */
IF @UnmappedCount > 0
BEGIN
    INSERT INTO stg.EntityDraftBuildLog (RunId, Phase, Severity, Message)
    VALUES (
        @RunId,
        N'MAP_QUALITY',
        N'INFO',
        CONCAT(
            @UnmappedCount,
            N' colonne(s) UNMAPPED utilisént CAST(NULL AS type) dans les vues générées.',
            N' Consulter stg.DictionaryQualityIssue pour le detail.'
        )
    );
END;

SELECT @WarnCount = COUNT(*)
FROM stg.EntityDraftBuildLog
WHERE RunId = @RunId AND Severity = N'WARN';

SET @Msg = CONCAT(N'Rapport qualité: WARN=', @WarnCount, N'. Voir stg.EntityDraftBuildLog.');
EXEC log.usp_WriteScriptLog
    @RunId=@RunId, @ScriptName=@ScriptName, @ScriptVersion=N'V6-DRAFT',
    @Phase=N'QUALITY', @Severity=N'INFO', @Status=N'COMPLETED',
    @Message=@Msg,
    @RowsAffected=@WarnCount;

/* ===========================================================================================
   ETAPE G : Rapport final
   =========================================================================================== */
SET @Msg = CONCAT(
    N'Publication canonique V6 terminée. PwaLanguage=', @PwaLanguage,
    N'; dic.EntityBinding=', @EntityBindingCount,
    N'; dic.EntityJoin=', @JoinPublishedCount,
    N'; dic.EntityColumnPublication=', (SELECT COUNT(*) FROM dic.EntityColumnPublication),
    N' (MAPPED=', @MappedCount,
    N'; MAPPED_NEEDS_JOIN=', @MappedNeedsJoinCount,
    N'; UNMAPPED=', @UnmappedCount,
    N'; NAVIGATION=', @NavigationCount, N')',
    N'; WARN=', @WarnCount
);

EXEC log.usp_WriteScriptLog
    @RunId=@RunId, @ScriptName=@ScriptName, @ScriptVersion=N'V6-DRAFT',
    @Phase=N'COMPLETED', @Severity=N'INFO', @Status=N'COMPLETED', @Message=@Msg;

/* Rapport console */
SELECT N'dic.EntityBinding'                        AS Metrique, CONVERT(nvarchar(50), @EntityBindingCount)  AS Valeur
UNION ALL SELECT N'dic.EntityJoin',                              CONVERT(nvarchar(50), @JoinPublishedCount)
UNION ALL SELECT N'dic.EntityColumnPublication',                 CONVERT(nvarchar(50), (SELECT COUNT(*) FROM dic.EntityColumnPublication))
UNION ALL SELECT N'  -> MAPPED',                                 CONVERT(nvarchar(50), @MappedCount)
UNION ALL SELECT N'  -> MAPPED_NEEDS_JOIN',                      CONVERT(nvarchar(50), @MappedNeedsJoinCount)
UNION ALL SELECT N'  -> UNMAPPED (CAST NULL)',                   CONVERT(nvarchar(50), @UnmappedCount)
UNION ALL SELECT N'  -> NAVIGATION',                             CONVERT(nvarchar(50), @NavigationCount)
UNION ALL SELECT N'stg.EntityDraftBuildLog (WARN)',              CONVERT(nvarchar(50), @WarnCount)
ORDER BY Metrique;

/* Jointures avec expression manuelle requise */
IF EXISTS (SELECT 1 FROM dic.EntityJoin WHERE JoinStatus IN (N'MANUAL_REQUIRED', N'PROPOSED') AND IsActive = 1)
    SELECT
        EntityName_EN, JoinTag, PsseObjectName, JoinAlias, JoinExpression, ColumnCoverage, JoinStatus
    FROM dic.EntityJoin
    WHERE IsActive = 1
    ORDER BY EntityName_EN, JoinTag;

/* Avertissements de construction */
IF @WarnCount > 0
    SELECT EntityName_EN, Phase, Severity, Message, LoggedAt
    FROM stg.EntityDraftBuildLog
    WHERE RunId = @RunId AND Severity IN (N'WARN', N'ERROR')
    ORDER BY Severity DESC, LoggedAt;

/* Vue d'ensemble par entité : couverture finale */
SELECT
    eb.EntityName_EN,
    eb.EntityName_FR,
    eb.PsseObjectName       AS PrimarySource,
    eb.CoverageScore,
    eb.ConfidenceLevel,
    eb.BindingStatus,
    SUM(CASE WHEN ecp.MapStatus = N'MAPPED'            THEN 1 ELSE 0 END) AS ColMapped,
    SUM(CASE WHEN ecp.MapStatus = N'MAPPED_NEEDS_JOIN' THEN 1 ELSE 0 END) AS ColNeedsJoin,
    SUM(CASE WHEN ecp.MapStatus = N'UNMAPPED'          THEN 1 ELSE 0 END) AS ColUnmapped,
    SUM(CASE WHEN ecp.MapStatus = N'NAVIGATION'        THEN 1 ELSE 0 END) AS ColNavigation
FROM dic.EntityBinding eb
LEFT JOIN dic.EntityColumnPublication ecp ON ecp.EntityName_EN = eb.EntityName_EN
WHERE eb.IsActive = 1
GROUP BY
    eb.EntityName_EN, eb.EntityName_FR, eb.PsseObjectName,
    eb.CoverageScore, eb.ConfidenceLevel, eb.BindingStatus
ORDER BY eb.ConfidenceLevel, eb.CoverageScore DESC;
GO
