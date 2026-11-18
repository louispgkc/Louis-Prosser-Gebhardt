/* ============================================================
   SCM_500_HW09_001_Create_WIP_Shiphist.sql
   Purpose : Build WIP_ShipmentHistory = all raw shipment fields
             (unchanged) + new KU fields, then flag records to exclude.
   Re-run  : Safe. Drops and rebuilds the table every time.
   Run     : Execute the whole file with nothing highlighted.
             Row counts for each step appear on the Messages tab.
   Result  : 56,134 records; 53,632 not excluded (EXCLUDE is NULL).
   ============================================================ */
USE [SCM500_1];
GO

/* ------------------------------------------------------------
   3.a  Create the WIP table (drop any previous version first)
   ------------------------------------------------------------ */
IF OBJECT_ID('dbo.WIP_ShipmentHistory', 'U') IS NOT NULL
    DROP TABLE [dbo].[WIP_ShipmentHistory];
GO

CREATE TABLE [dbo].[WIP_ShipmentHistory] (
    -- Raw fields (copied unchanged from RAW_ShipmentHistory)
    [BOL]            NVARCHAR(50)  NOT NULL PRIMARY KEY,
    [SHIP_TO]        NVARCHAR(50)  NOT NULL,
    [SHIP_TO_CITY]   NVARCHAR(50)  NULL,
    [SHIP_TO_STE]    NVARCHAR(50)  NULL,
    [SHIP_TO_ZIP5]   NVARCHAR(50)  NULL,
    [SHIP_TO_TYPE]   NVARCHAR(50)  NOT NULL,
    [DEMAND_REGION]  NVARCHAR(50)  NULL,
    [SHIP_FROM]      NVARCHAR(50)  NOT NULL,
    [SHIP_FROM_CITY] NVARCHAR(50)  NULL,
    [SHIP_FROM_STE]  NVARCHAR(50)  NULL,
    [SOURCE_TYPE]    NVARCHAR(50)  NULL,
    [SHIP_DATE]      DATETIME2(7)  NULL,
    [MODE]           NVARCHAR(50)  NOT NULL,
    [STOPS]          INT           NULL,
    [SHIP_QTY]       INT           NULL,
    [SHIP_WEIGHT]    INT           NULL,
    [FREIGHT_COST]   MONEY         NULL,

    -- New fields (filled in below)
    [KU_OrigCity]    VARCHAR(50)   NULL,
    [KU_OrigState]   VARCHAR(50)   NULL,
    [KU_OrigCountry] VARCHAR(50)   NULL,
    [KU_OrigZip]     VARCHAR(50)   NULL,
    [KU_OrigType]    VARCHAR(50)   NULL,
    [KU_DestZip]     VARCHAR(50)   NULL,
    [KU_DestType]    VARCHAR(50)   NULL,
    [KU_CostZone]    VARCHAR(50)   NULL,
    [KU_PopDense]    VARCHAR(50)   NULL,
    [KU_LaneType]    VARCHAR(50)   NULL,
    [KU_Distance]    FLOAT         NULL,
    [KU_MilesSource] VARCHAR(50)   NULL,
    [EXCLUDE]        VARCHAR(50)   NULL,
    [EXCLUDE_REASON] VARCHAR(50)   NULL
);
GO

/* ------------------------------------------------------------
   3.b  Copy every record from the raw table (new fields stay empty)
        Expect: 56,134 rows
   ------------------------------------------------------------ */
INSERT INTO [dbo].[WIP_ShipmentHistory] (
    [BOL], [SHIP_TO], [SHIP_TO_CITY], [SHIP_TO_STE], [SHIP_TO_ZIP5],
    [SHIP_TO_TYPE], [DEMAND_REGION], [SHIP_FROM], [SHIP_FROM_CITY],
    [SHIP_FROM_STE], [SOURCE_TYPE], [SHIP_DATE], [MODE], [STOPS],
    [SHIP_QTY], [SHIP_WEIGHT], [FREIGHT_COST]
)
SELECT
    [BOL], [SHIP_TO], [SHIP_TO_CITY], [SHIP_TO_STE], [SHIP_TO_ZIP5],
    [SHIP_TO_TYPE], [DEMAND_REGION], [SHIP_FROM], [SHIP_FROM_CITY],
    [SHIP_FROM_STE], [SOURCE_TYPE], [SHIP_DATE], [MODE], [STOPS],
    [SHIP_QTY], [SHIP_WEIGHT], [FREIGHT_COST]
FROM [dbo].[RAW_ShipmentHistory];
PRINT '3.b  Records copied from RAW_ShipmentHistory: ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + '   (expect 56134)';
GO

/* ------------------------------------------------------------
   4.a  Origin fields from RAW_Facility (matched on SHIP_FROM = Facility)
        Origin type comes from the facility table, NOT from SOURCE_TYPE,
        because SOURCE_TYPE is blank on many plant shipments.
        Expect: PLT 3,374 / RDC 52,760
   ------------------------------------------------------------ */
UPDATE w
SET w.[KU_OrigType]    = CASE RTRIM(f.[Facilitytype])
                             WHEN 'PLANT'  THEN 'PLT'
                             WHEN 'DC-RDC' THEN 'RDC'
                         END,
    w.[KU_OrigCity]    = CAST(f.[City] AS VARCHAR(50)),
    w.[KU_OrigState]   = NULLIF(RTRIM(f.[State]), ''),
    w.[KU_OrigCountry] = NULLIF(RTRIM(f.[Country]), ''),
    w.[KU_OrigZip]     = NULLIF(RTRIM(f.[PostalCode]), '')
FROM [dbo].[WIP_ShipmentHistory] w
JOIN [dbo].[RAW_Facility] f
  ON w.[SHIP_FROM] = f.[Facility];
PRINT '4.a  Origin fields set: ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + '   (expect 56134)';
GO

/* ------------------------------------------------------------
   4.b  Destination type: DC-RDC -> RDC, every customer flavor -> CUS
        Uses SHIP_TO_TYPE (not facility-table membership) so the Laredo
        and Findlay cross-docks (227583, 227584, 218236) count as RDCs.
        Expect: RDC 17,493 / CUS 38,641
   ------------------------------------------------------------ */
UPDATE [dbo].[WIP_ShipmentHistory]
SET [KU_DestType] = CASE WHEN RTRIM([SHIP_TO_TYPE]) = 'DC-RDC'
                         THEN 'RDC' ELSE 'CUS' END;
PRINT '4.b  Destination type set: ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + '   (expect 56134)';
GO

/* ------------------------------------------------------------
   4.c  Lane type: RDC destination = inbound (IB), customer = outbound (OB)
        Must run after 4.b.
   ------------------------------------------------------------ */
UPDATE [dbo].[WIP_ShipmentHistory]
SET [KU_LaneType] = CASE [KU_DestType]
                        WHEN 'RDC' THEN 'IB'
                        WHEN 'CUS' THEN 'OB'
                    END;
PRINT '4.c  Lane type set: ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + '   (expect 56134)';
GO

/* ------------------------------------------------------------
   4.d  Destination ZIP: use SHIP_TO_ZIP5; where it is blank, fall back to
        the facility postal code. Four-digit ZIPs are left as they are.
        Expect: 31 records stay NULL (all Ocean, excluded in 5.2)
   ------------------------------------------------------------ */
UPDATE w
SET w.[KU_DestZip] = COALESCE(NULLIF(LTRIM(RTRIM(w.[SHIP_TO_ZIP5])), ''),
                              NULLIF(RTRIM(f.[PostalCode]), ''))
FROM [dbo].[WIP_ShipmentHistory] w
LEFT JOIN [dbo].[RAW_Facility] f
  ON w.[SHIP_TO] = f.[Facility];
PRINT '4.d  Destination ZIP set: ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + '   (expect 56134)';
GO

/* ------------------------------------------------------------
   4.e  Destination cost zone and population density
        (first 3 digits of destination ZIP -> AUX_CostPopulationZones)
        Must run after 4.d. Expect: 56,103 matched, 31 stay NULL.
   ------------------------------------------------------------ */
UPDATE w
SET w.[KU_CostZone] = RTRIM(z.[Costzone]),
    w.[KU_PopDense] = RTRIM(z.[Popdensity])
FROM [dbo].[WIP_ShipmentHistory] w
LEFT JOIN [dbo].[AUX_CostPopulationZones] z
  ON LEFT(w.[KU_DestZip], 3) = RTRIM(z.[3DZ]);
PRINT '4.e  Cost zone / density set: ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + '   (expect 56134)';
GO

/* ------------------------------------------------------------
   4.f  Distance step 1: Mexico plant to destination (MEXM)
        Expect: 1,540
   ------------------------------------------------------------ */
UPDATE w
SET w.[KU_Distance]    = m.[Distance],
    w.[KU_MilesSource] = 'MEXM'
FROM [dbo].[WIP_ShipmentHistory] w
JOIN [dbo].[AUX_MexicoOriginMiles] m
  ON w.[SHIP_FROM] = RTRIM(m.[Originfacility])
 AND w.[SHIP_TO]   = RTRIM(m.[Destfacility])
WHERE w.[KU_Distance] IS NULL;
PRINT '4.f  Mexico distances: ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + '   (expect 1540)';
GO

/* ------------------------------------------------------------
   4.g  Distance step 2: ZIP5 to ZIP5 (most accurate US source)
        Note: the distance column in this table is spelled [Milies].
        Only fills records that still have no distance.
        Expect: 40,252
   ------------------------------------------------------------ */
UPDATE w
SET w.[KU_Distance]    = z.[Milies],
    w.[KU_MilesSource] = 'ZIP5'
FROM [dbo].[WIP_ShipmentHistory] w
JOIN [dbo].[AUX_Zip5_Zip5_US] z
  ON w.[KU_OrigZip] = RTRIM(z.[OrigZip5])
 AND w.[KU_DestZip] = RTRIM(z.[DestZip5])
WHERE w.[KU_Distance] IS NULL;
PRINT '4.g  ZIP5 distances: ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + '   (expect 40252)';
GO

/* ------------------------------------------------------------
   4.h  Distance step 3: ZIP3 to ZIP3 (less precise, so used last)
        Only fills records that still have no distance.
        Expect: 12,043. Records still empty afterwards: 2,299
        (1,834 Ocean + 465 Canadian destinations).
   ------------------------------------------------------------ */
UPDATE w
SET w.[KU_Distance]    = z.[Miles],
    w.[KU_MilesSource] = 'ZIP3'
FROM [dbo].[WIP_ShipmentHistory] w
JOIN [dbo].[AUX_Zip3_Zip3_US] z
  ON LEFT(w.[KU_OrigZip], 3) = RTRIM(z.[OZip3])
 AND LEFT(w.[KU_DestZip], 3) = RTRIM(z.[DZip3])
WHERE w.[KU_Distance] IS NULL;
PRINT '4.h  ZIP3 distances: ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + '   (expect 12043)';
GO

/* ------------------------------------------------------------
   5   Exclusions: one UPDATE per rule, in this order. Each only touches
       records not already excluded, so the first rule to catch a record
       keeps it. Kept records stay NULL in EXCLUDE and EXCLUDE_REASON.
   ------------------------------------------------------------ */

-- 5.1  Weight under 1 lb (not a real shipment, probably an invoicing record)
UPDATE [dbo].[WIP_ShipmentHistory]
SET [EXCLUDE] = 'YES', [EXCLUDE_REASON] = 'WGT < 1 > 45000'
WHERE [EXCLUDE] IS NULL AND [SHIP_WEIGHT] < 1;
PRINT '5.1  Weight under 1 lb: ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + '   (expect 7)';
GO

-- 5.2  Ocean shipments (the analysis covers TL, LTL and IM only)
UPDATE [dbo].[WIP_ShipmentHistory]
SET [EXCLUDE] = 'YES', [EXCLUDE_REASON] = 'OCEAN'
WHERE [EXCLUDE] IS NULL AND [MODE] = 'Ocean';
PRINT '5.2  Ocean: ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + '   (expect 1827)';
GO

-- 5.3  LTL with more than 1 stop (LTL has one pickup and one delivery)
UPDATE [dbo].[WIP_ShipmentHistory]
SET [EXCLUDE] = 'YES', [EXCLUDE_REASON] = 'LTL-IM 2Stop'
WHERE [EXCLUDE] IS NULL AND [MODE] = 'LTL' AND [STOPS] > 1;
PRINT '5.3  LTL with 2+ stops: ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + '   (expect 2)';
GO

-- 5.4  No distance found (Canadian destinations have no mileage data)
UPDATE [dbo].[WIP_ShipmentHistory]
SET [EXCLUDE] = 'YES', [EXCLUDE_REASON] = 'MILES (No)'
WHERE [EXCLUDE] IS NULL AND [KU_Distance] IS NULL;
PRINT '5.4  No miles: ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + '   (expect 465)';
GO

-- 5.5  Ship quantity of 0
UPDATE [dbo].[WIP_ShipmentHistory]
SET [EXCLUDE] = 'YES', [EXCLUDE_REASON] = 'SHIPQ = 0'
WHERE [EXCLUDE] IS NULL AND [SHIP_QTY] = 0;
PRINT '5.5  Ship quantity 0: ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + '   (expect 189)';
GO

-- 5.6  Weight over 45,000 lb (more than one truckload, so probably combined loads)
UPDATE [dbo].[WIP_ShipmentHistory]
SET [EXCLUDE] = 'YES', [EXCLUDE_REASON] = 'WGT < 1 > 45000'
WHERE [EXCLUDE] IS NULL AND [SHIP_WEIGHT] > 45000;
PRINT '5.6  Weight over 45,000 lb: ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + '   (expect 12)';
GO

/* ------------------------------------------------------------
   3.d.2  Exclude summary (first table for the hand-in workbook)
   Expect: OCEAN 1,827 / WGT 19 / LTL-IM 2Stop 2 / MILES (No) 465 /
           SHIPQ = 0 189 / NULL 53,632 / TOTAL 56,134
   ------------------------------------------------------------ */
SELECT [EXCLUDE], [EXCLUDE_REASON], BOLs, QTY, WGT, COST
FROM (
    SELECT [EXCLUDE],
           [EXCLUDE_REASON],
           COUNT(*)                           AS BOLs,
           SUM([SHIP_QTY])                    AS QTY,
           SUM(CAST([SHIP_WEIGHT] AS BIGINT)) AS WGT,
           SUM([FREIGHT_COST])                AS COST,
           CASE [EXCLUDE_REASON]
                WHEN 'OCEAN'           THEN 1
                WHEN 'WGT < 1 > 45000' THEN 2
                WHEN 'LTL-IM 2Stop'    THEN 3
                WHEN 'MILES (No)'      THEN 4
                WHEN 'SHIPQ = 0'       THEN 5
                ELSE 6 END             AS SortKey
    FROM [dbo].[WIP_ShipmentHistory]
    GROUP BY [EXCLUDE], [EXCLUDE_REASON]

    UNION ALL

    SELECT 'TOTAL', NULL,
           COUNT(*), SUM([SHIP_QTY]), SUM(CAST([SHIP_WEIGHT] AS BIGINT)), SUM([FREIGHT_COST]),
           7
    FROM [dbo].[WIP_ShipmentHistory]
) x
ORDER BY SortKey;
GO

-- 3.d.2  Exclude summary as percent of total
SELECT [EXCLUDE], [EXCLUDE_REASON],
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,1)) AS Pct_BOLs,
       CAST(100.0 * SUM([SHIP_QTY]) / SUM(SUM([SHIP_QTY])) OVER () AS DECIMAL(5,1)) AS Pct_QTY,
       CAST(100.0 * SUM(CAST([SHIP_WEIGHT] AS BIGINT))
                  / SUM(SUM(CAST([SHIP_WEIGHT] AS BIGINT))) OVER () AS DECIMAL(5,1)) AS Pct_WGT,
       CAST(100.0 * SUM(CAST([FREIGHT_COST] AS DECIMAL(18,2)))
                  / SUM(SUM(CAST([FREIGHT_COST] AS DECIMAL(18,2)))) OVER () AS DECIMAL(5,1)) AS Pct_COST
FROM [dbo].[WIP_ShipmentHistory]
GROUP BY [EXCLUDE], [EXCLUDE_REASON]
ORDER BY CASE [EXCLUDE_REASON]
              WHEN 'OCEAN' THEN 1 WHEN 'WGT < 1 > 45000' THEN 2
              WHEN 'LTL-IM 2Stop' THEN 3 WHEN 'MILES (No)' THEN 4
              WHEN 'SHIPQ = 0' THEN 5 ELSE 6 END;
GO
