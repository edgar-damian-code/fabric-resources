-------------------------------------------------------------------------------
-- Author       Wipfli\Edgar Damian
-- Created      04-Dec-2024
-- Purpose      Populates Date Dimension based on Start & End Date parameters
--				
-------------------------------------------------------------------------------
-- Modification History
--
-- 01/01/0000  developer full name  
--      A comprehensive description of the changes. The description may use as 
--      many lines as needed.
-------------------------------------------------------------------------------

DROP TABLE IF EXISTS dbo.Dim_Date;
GO
CREATE TABLE dbo.Dim_Date
(
    DateKey varchar(10),
    [Date] date,
	[Year] int,
	[MonthSort] int,
	[MonthNum] int,
	[Month] varchar(15),
	[MonthYear] varchar(10),
	[EOMonth] date,
    [QuarterNum] int,
    [Quarter] varchar(7),
	[QuarterYear] varchar(10),
	[QuarterSort] int,
	[EOQuarter] date,
    [WeekDaySort] int,
    [WeekDay] varchar(15),
	[EndofWeek] date,
	[WeekNum] int,
	[WeekSort] int,
	[FutureDateFlag] varchar(4),
	[RelativeDays] int
);
GO

DECLARE
    @StartDate DateTime = '1/1/2024',
    @EndDate DateTime = '12/31/2040',
    @StartInt int,
    @EndInt int

SELECT
    @StartInt = CAST(@StartDate AS INT),
    @EndInt = CAST(@EndDate AS INT) ;

WITH Days
AS
(
    SELECT 
        CAST(CAST(value as datetime) AS DATE) AS [Date]
    FROM GENERATE_SERIES(@StartInt, @EndInt, 1)
)

INSERT INTO Dim_Date
SELECT 
    YEAR([Date]) * 10000 + MONTH([Date]) * 100 + DAY([Date]) AS [DateKey]
    , [Date]
    , YEAR([Date]) AS [Year]
	, YEAR([Date]) * 100 + MONTH([Date]) AS [MonthSort]
	, MONTH([Date]) AS [MonthNum]
	, DATENAME(MONTH, [Date]) AS [Month]
	, FORMAT([Date], 'MMM') + ' ' + CAST(YEAR([Date]) AS VARCHAR) AS [MonthYear] 
	, EOMONTH([Date]) AS [EOMonth] 
    , DATEPART(QUARTER, [Date]) AS [QuarterNum]
    , 'Q' + CAST(DATEPART(QUARTER, [Date]) AS VARCHAR) AS [Quarter]
	, 'Q' + CAST(DATEPART(QUARTER, [Date]) AS VARCHAR) + ' ' + CAST(DATEPART(YEAR, [Date]) AS VARCHAR) AS [QuarterYear] 
	, YEAR([Date]) * 100 + DATEPART(QUARTER, [Date]) AS [QuarterSort] 
	, CAST(DATEADD(DAY, -1, DATEADD(QUARTER, DATEDIFF(QUARTER, 0, [Date]) + 1, 0)) AS DATE) AS [EOQuarter] 
	, (DATEPART(dw, [Date]) + @@DATEFIRST - 2) % 7 + 1 AS [WeekDaySort]
	, DATENAME(dw, [Date]) AS [WeekDay]
	, DATEADD(DAY, 6 - DATEPART(dw, [Date]), [Date]) AS [EndofWeek]  
    , DATEPART(wk, [Date]) AS [WeekNum]
	, YEAR([Date]) * 100 + DATEPART(wk, [Date]) AS [WeekSort]
	-- , CASE WHEN [Date] <= GETDATE() THEN 'No' ELSE 'Yes' END AS [FutureDateFlag]
	-- , DATEDIFF(DAY,GETDATE(),[Date]) AS [RelativeDays]
FROM Days;
GO
