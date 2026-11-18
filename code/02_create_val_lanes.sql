/* ============================================================
   SCM_500_HW09_002_Create_VAL_Lanes.sql
   Purpose : Build VAL_Lanes = one row per lane (origin, destination,
             destination ZIP, mode) from the non-excluded WIP records.
   Needs   : SCM_500_HW09_001_Create_WIP_Shiphist.sql run first.
   Re-run  : Safe. Drops and rebuilds the table every time.
   Run     : Execute the whole file with nothing highlighted.
   Result  : 3,480 lanes covering 53,632 shipments.
   ============================================================ */
USE [SCM500_1];
GO

/* ------------------------------------------------------------
   4.a  Create the VAL table (22 fields).
        Primary key: Orig_ID + Dest_ID + Dest_Zip + Mode
   ------------------------------------------------------------ */
IF OBJECT_ID('dbo.VAL_Lanes', 'U') IS NOT NULL
    DROP TABLE [dbo].[VAL_Lanes];
GO

CREATE TABLE [dbo].[VAL_Lanes] (
    [Orig_ID]        VARCHAR(50) NOT NULL,
    [Orig_City]      VARCHAR(50) NOT NULL,
    [Orig_State]     VARCHAR(50) NOT NULL,
    [Orig_Country]   VARCHAR(50) NOT NULL,
    [Orig_Zip]       VARCHAR(50) NULL,      -- Mexico plant 1724 has no ZIP
    [Orig_Type]      VARCHAR(50) NULL,      -- PLT, RDC
    [Dest_ID]        VARCHAR(50) NOT NULL,
    [Dest_City]      VARCHAR(50) NULL,
    [Dest_State]     VARCHAR(50) NOT NULL,
    [Dest_Zip]       VARCHAR(50) NOT NULL,
    [Dest_Type]      VARCHAR(50) NULL,      -- RDC, CUS
    [Dest_Cost_Zone] VARCHAR(50) NULL,
    [Dest_Pop_Dense] VARCHAR(50) NULL,
    [Lane_Type]      VARCHAR(50) NULL,      -- IB, OB
    [Mode]           VARCHAR(50) NOT NULL,  -- TL, IM, LTL
    [Distance]       INT         NULL,      -- OD_miles
    [Miles_Source]   VARCHAR(50) NULL,      -- ZIP5, ZIP3, MEXM
    [Num_Shipments]  INT         NOT NULL,
    [Num_Stops]      INT         NOT NULL,
    [Total_Units]    INT         NOT NULL,
    [Total_Weight]   INT         NOT NULL,
    [Total_Cost]     MONEY       NOT NULL,
    CONSTRAINT [PK_VAL_Lanes]
        PRIMARY KEY ([Orig_ID], [Dest_ID], [Dest_Zip], [Mode])
);
GO

/* ------------------------------------------------------------
   4.a.i  Fill from WIP: non-excluded records only, grouped into lanes.
          - City is aggregated (MAX of upper-case) because the same
            destination appears with different spellings (Laredo / LAREDO).
          - Distance is truncated to a whole number (decimals dropped),
            which matches the instructor's sample output.
          Expect: 3,480 rows
   ------------------------------------------------------------ */
INSERT INTO [dbo].[VAL_Lanes] (
    [Orig_ID], [Orig_City], [Orig_State], [Orig_Country], [Orig_Zip], [Orig_Type],
    [Dest_ID], [Dest_City], [Dest_State], [Dest_Zip], [Dest_Type],
    [Dest_Cost_Zone], [Dest_Pop_Dense], [Lane_Type], [Mode],
    [Distance], [Miles_Source],
    [Num_Shipments], [Num_Stops], [Total_Units], [Total_Weight], [Total_Cost]
)
SELECT
    [SHIP_FROM], [KU_OrigCity], [KU_OrigState], [KU_OrigCountry], [KU_OrigZip], [KU_OrigType],
    [SHIP_TO], MAX(UPPER([SHIP_TO_CITY])), [SHIP_TO_STE], [KU_DestZip], [KU_DestType],
    [KU_CostZone], [KU_PopDense], [KU_LaneType], [MODE],
    CAST([KU_Distance] AS INT), [KU_MilesSource],
    COUNT([BOL]), SUM([STOPS]), SUM([SHIP_QTY]), SUM([SHIP_WEIGHT]), SUM([FREIGHT_COST])
FROM [dbo].[WIP_ShipmentHistory]
WHERE [EXCLUDE] IS NULL
GROUP BY
    [SHIP_FROM], [KU_OrigCity], [KU_OrigState], [KU_OrigCountry], [KU_OrigZip], [KU_OrigType],
    [SHIP_TO], [SHIP_TO_STE], [KU_DestZip], [KU_DestType],
    [KU_CostZone], [KU_PopDense], [KU_LaneType], [MODE],
    CAST([KU_Distance] AS INT), [KU_MilesSource];
PRINT '4.a.i  Lanes created: ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + '   (expect 3480)';
GO

/* ------------------------------------------------------------
   4.c  Summary of lanes (second table for the hand-in workbook)
   Expect: 9 rows plus TOTAL = 3,480 lanes / 53,632 shipments /
           32,412,317 units / 52,097,857 cost
   ------------------------------------------------------------ */
SELECT [Lane_Type], [Mode], [Orig_Type], [Dest_Type],
       Lanes, TotalShipments, TotalUnits, TotalCost
FROM (
    SELECT [Lane_Type], [Mode], [Orig_Type], [Dest_Type],
           COUNT(*)             AS Lanes,
           SUM([Num_Shipments]) AS TotalShipments,
           SUM([Total_Units])   AS TotalUnits,
           SUM([Total_Cost])    AS TotalCost,
           0                    AS SortKey
    FROM [dbo].[VAL_Lanes]
    GROUP BY [Lane_Type], [Mode], [Orig_Type], [Dest_Type]

    UNION ALL

    SELECT 'TOTAL', NULL, NULL, NULL,
           COUNT(*), SUM([Num_Shipments]), SUM([Total_Units]), SUM([Total_Cost]),
           1
    FROM [dbo].[VAL_Lanes]
) x
ORDER BY SortKey, [Lane_Type], [Mode], [Orig_Type], [Dest_Type];
GO
