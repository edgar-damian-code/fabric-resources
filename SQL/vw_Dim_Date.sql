CREATE VIEW Common.vw_Dim_Date 
AS
SELECT *
    , CASE WHEN [Date] <= GETDATE() THEN 'No' ELSE 'Yes' END AS [FutureDateFlag]
	, DATEDIFF(DAY,GETDATE(),[Date]) AS [RelativeDays]
    , CASE 
        WHEN MONTH(Date) = MONTH(GETDATE())
            AND YEAR(Date) = YEAR(GETDATE())
        THEN 'Current Month'
        ELSE MonthYear
      END AS Month_Display
    , CASE 
        WHEN  YEAR(Date) = YEAR(GETDATE())
        THEN 'Current Year'
        ELSE CAST([Year] AS VARCHAR)
      END AS Year_Display
FROM Common.Dim_Date