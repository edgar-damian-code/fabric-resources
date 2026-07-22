/****** Object:  StoredProcedure [HelloData].[usp_CreateUnitHistory]    Script Date: 2/26/2025 3:09:27 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-------------------------------------------------------------------------------
-- Author       Wipfli\Edgar Damian
-- ALTERd       Feb-03-2025
-- Purpose      ALTERs Fact_Unit_History table
--				
-------------------------------------------------------------------------------
-- Modification History
--
-- 01/06/2025 Edgar Damian  
--      Joined on Dim_Units to bring in Property Type and ID
--      Filtered for max load_date
-- 01/13/2025 Edgar Damian
--      Added join to subject comp table to bring in subject_id
-- 01/30/2025 Edgar Damian
--      Added logic to assign Alliance properties as their own subject_id
--      Joined Dim Properties to bring in Building Name
--      ALTERd price per sqft calcs
-------------------------------------------------------------------------------

ALTER PROC [HelloData].[usp_CreateUnitHistory]
AS
BEGIN
    -- Drop the existing table if it exists
    DROP TABLE IF EXISTS [HelloData].[Fact_Unit_History];

    -- Create the new table with joins and transformation
    SELECT 
        a.building_availability_id AS UnitID
        , u."Property ID"
        , p.[Building Name]
        , p.lat AS "Latitude"
        , p.lon AS "Longitude"
        , p.[Street Address]
        , p.[City]
        , p.[State]
        , p.[Zip]
        , CASE 
            WHEN u.[Property Type] = 'Comp' THEN comps.subject_id
            ELSE u."Property ID"
          END AS subject_id
        , a.deposit
        , COALESCE(a.enter_market, MIN(from_date) OVER (PARTITION BY b.building_availability_id, b.period_id)) AS "Enter Market"
        , a.exit_market AS "Exit Market"
        , COALESCE(
            a.days_on_market, 
            DATEDIFF(
                DAY, 
                COALESCE(
                    a.enter_market, 
                    MIN(from_date) OVER (PARTITION BY b.building_availability_id, b.period_id)
                    ), 
                COALESCE(
                    a.exit_market, 
                    MAX(to_date) OVER (PARTITION BY b.building_availability_id, b.period_id)
                    )
                )
            ) AS "Days On Market"
        , COALESCE(effective_price, max_effective_price) AS "Effective Price"
        , CAST(COALESCE(effective_price, max_effective_price) / CAST(u.sqft AS DECIMAL(10,2)) AS DECIMAL(10,2)) AS "Effective Price per sqft"
        , COALESCE(price, max_price) AS Price
        , CAST(COALESCE(price, max_price) / CAST(u.sqft AS DECIMAL(10,2)) AS DECIMAL(10,2)) AS "Price per sqft"
        , u.sqft
        , CASE
            WHEN DATEDIFF(DAY, a.exit_market, a.load_date) <= 30 THEN 1 ELSE 0
            END AS "Leased Up"
        , CASE 
            WHEN a.exit_market IS NULL THEN 1 
            WHEN b.to_date < a.exit_market THEN 1
            ELSE 0 
            END AS "Vacant"
        , from_date AS "From Date"
        , to_date AS "To Date"
        , b.period_id AS PeriodID
        , u.[Property Type]
        , b.load_date AS LoadDate
    INTO [HelloData].[Fact_Unit_History]
    FROM Staging.building_availability_periods a
    LEFT JOIN Staging.building_availability_history b
        ON a.building_availability_id = b.building_availability_id 
        AND a.period_id = b.period_id
        AND a.load_date = b.load_date
    LEFT JOIN HelloData.v_Dim_Units u
        ON a.building_availability_id = u.UnitID
        AND a.load_date = u.[Load Date]
    LEFT JOIN (
        SELECT DISTINCT comp_id, subject_id, load_date
        FROM Staging.subject_comparison_portfolio 
        ) comps 
        ON u.[Property ID] = comps.comp_id
        AND u.[Load Date] = comps.load_date
    LEFT JOIN HelloData.v_Dim_Properties p
        ON u.[Property ID] = p.PropertyID
        AND u.[Load Date] = p."Load Date"
    WHERE a.load_date = (SELECT MAX(load_date) FROM Staging.building_availability_periods);
END
GO


