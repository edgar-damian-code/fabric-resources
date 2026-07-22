
-- Configure your assumptions
DECLARE @ChangePercent FLOAT = 1.0; -- % of rows expected to change daily
DECLARE @AvgRowSizeBytes INT = 200; -- Average row size in bytes
DECLARE @CDCOverheadFactor FLOAT = 2.0; -- CDC overhead multiplier (1.5–2x typical)

-- Table to store results
IF OBJECT_ID('tempdb..#CDC_LogEstimate') IS NOT NULL DROP TABLE #CDC_LogEstimate;
CREATE TABLE #CDC_LogEstimate (
    TableName SYSNAME,
    Row_Count BIGINT,
    DailyChangeRows BIGINT,
    EstimatedLogGrowthMB FLOAT
);

-- Calculate estimates for all user tables
INSERT INTO #CDC_LogEstimate (TableName, Row_Count, DailyChangeRows, EstimatedLogGrowthMB)
SELECT
    t.name AS TableName,
    SUM(p.rows) AS Row_Count,
    CAST(SUM(p.rows) * (@ChangePercent / 100.0) AS BIGINT) AS DailyChangeRows,
    ((SUM(p.rows) * (@ChangePercent / 100.0) * @AvgRowSizeBytes * @CDCOverheadFactor) / (1024.0 * 1024.0)) AS EstimatedLogGrowthMB
FROM sys.tables t
JOIN sys.partitions p ON t.object_id = p.object_id
WHERE t.type = 'U' AND p.index_id IN (0,1)
GROUP BY t.name
ORDER BY EstimatedLogGrowthMB DESC;

-- Show results
SELECT * FROM #CDC_LogEstimate ORDER BY EstimatedLogGrowthMB DESC;

-- Summary for database
SELECT
    SUM(EstimatedLogGrowthMB) AS TotalEstimatedLogGrowthMB,
    SUM(DailyChangeRows) AS TotalDailyChangeRows
FROM #CDC_LogEstimate;
