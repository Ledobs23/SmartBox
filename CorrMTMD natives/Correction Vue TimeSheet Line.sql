SELECT        ta.*, ROW_NUMBER() OVER (PARTITION BY ta.[SiteId], ta.[TimesheetLineUID], ta.[TimeByDay]
ORDER BY ta.[AdjustmentIndex] DESC, ta.[CreatedDate] DESC) AS rn
FROM            [SP_BPRI_POC_Contenu].[pjrep].[MSP_TimesheetActual] ta), TimesheetStatusOneRow AS
    (SELECT        ts .[SiteId], ts .[TimesheetStatusID], ts .[Description], ROW_NUMBER() OVER (PARTITION BY ts .[SiteId], ts .[TimesheetStatusID]
      ORDER BY ts .[LCID]) AS rn
FROM            [SP_BPRI_POC_Contenu].[pjrep].[MSP_TimesheetStatus] ts), TimesheetLineStatusOneRow AS
    (SELECT        tls.[SiteId], tls.[TimesheetLineStatusID], tls.[Description], ROW_NUMBER() OVER (PARTITION BY tls.[SiteId], tls.[TimesheetLineStatusID]
      ORDER BY tls.[LCID]) AS rn
FROM            [SP_BPRI_POC_Contenu].[pjrep].[MSP_TimesheetLineStatus] tls)
    SELECT        tl.[TimesheetLineUID] AS [IdLigneFeuilleDeTemps], tpj.[ProjectUID] AS [IdProjet], tr.[ResourceUID] AS [IdRessource], tr.[ResourceUID] AS [IdPropriétaireFeuilleDeTemps], ta.[TimeByDay] AS [HeureParJour], 
                              tl.[TimesheetUID] AS [IdFeuilleDeTemps], tp.[StartDate] AS [DateDébutPériode], tp.[EndDate] AS [DateFinPériode], ts .[Description] AS [ÉtatFeuilleDeTemps], tls.[Description] AS [ÉtatLigneFeuilleDeTemps]
     FROM            TimesheetActualLatest ta INNER JOIN
                              [SP_BPRI_POC_Contenu].[pjrep].[MSP_TimesheetLine] tl ON tl.[SiteId] = ta.[SiteId] AND tl.[TimesheetLineUID] = ta.[TimesheetLineUID] INNER JOIN
                              [SP_BPRI_POC_Contenu].[pjrep].[MSP_Timesheet] t ON t .[SiteId] = tl.[SiteId] AND t .[TimesheetUID] = tl.[TimesheetUID] INNER JOIN
                              [SP_BPRI_POC_Contenu].[pjrep].[MSP_TimesheetPeriod] tp ON tp.[SiteId] = t .[SiteId] AND tp.[PeriodUID] = t .[PeriodUID] LEFT JOIN
                              [SP_BPRI_POC_Contenu].[pjrep].[MSP_TimesheetProject] tpj ON tpj.[SiteId] = tl.[SiteId] AND tpj.[ProjectNameUID] = tl.[ProjectNameUID] LEFT JOIN
                              [SP_BPRI_POC_Contenu].[pjrep].[MSP_TimesheetResource] tr ON tr.[SiteId] = t .[SiteId] AND tr.[ResourceNameUID] = t .[OwnerResourceNameUID] LEFT JOIN
                              TimesheetStatusOneRow ts ON ts .[SiteId] = t .[SiteId] AND ts .[TimesheetStatusID] = t .[TimesheetStatusID] AND ts .[rn] = 1 LEFT JOIN
                              TimesheetLineStatusOneRow tls ON tls.[SiteId] = tl.[SiteId] AND tls.[TimesheetLineStatusID] = tl.[TimesheetLineStatus] AND tls.[rn] = 1
     WHERE        ta.[rn] = 1;