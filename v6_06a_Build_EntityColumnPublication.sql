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
    - Langue ciblee par cfg.PWA.Language (FR ou EN) : les deux alias (Column_FR, Column_EN) sont stockes.
    - Journalisation dans log.ScriptExecutionLog et stg.EntityDraftBuildLog.
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
   Source primaire PSSE par entité. Utilise la derniere entree par entité de stg.EntitySource_Draft
   (la plus recente par ProposedAt, puis la mieux couverte).
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
        ELSE N'/* TODO: specifier la condition de jointure */'
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
LEFT JOIN dic.EntityJoin ej
    ON ej.EntityName_EN  = ecm.EntityName_EN
   AND ej.PsseObjectName = ecm.PsseSourceObject
   AND ej.IsActive = 1
   AND ej.JoinStatus NOT IN (N'MANUAL_REQUIRED'); /* colonnes dont la jointure est invalide -> MAPPED_NEEDS_JOIN */

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
