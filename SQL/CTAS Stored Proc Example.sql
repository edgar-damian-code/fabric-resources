/****** Object:  StoredProcedure [Transform].[usp_copy_salesforce_tables]    Script Date: 2/26/2025 3:14:45 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [Transform].[usp_copy_salesforce_tables]
AS
BEGIN
    DECLARE @tableName NVARCHAR(255)
    DECLARE @createTableSQL NVARCHAR(MAX)
    DECLARE @insertDataSQL NVARCHAR(MAX)
    DECLARE @sql NVARCHAR(MAX)
    DECLARE @rowCount INT
    DECLARE @currentRow INT

    -- Temporary table to store the list of tables
    CREATE TABLE #TableList (RowNum INT IDENTITY(1,1), TableName NVARCHAR(255))

    -- Insert the list of tables from the lakehouse into the temporary table
    INSERT INTO #TableList (TableName)
    SELECT table_name
    FROM Enriched_Lakehouse.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'dbo' AND table_name LIKE 'sf_%'

    -- Get the number of rows in the temporary table
    SELECT @rowCount = COUNT(*) FROM #TableList
    SET @currentRow = 1

    WHILE @currentRow <= @rowCount
    BEGIN
        -- Get the table name for the current row
        SELECT @tableName = TableName FROM #TableList WHERE RowNum = @currentRow

        -- Check if the table exists in the warehouse
        IF OBJECT_ID('Salesforce.' + SUBSTRING(@tableName, 4, LEN(@tableName) - 3), 'U') IS NOT NULL
        BEGIN
            -- Truncate the existing table
            SET @sql = 'TRUNCATE TABLE Salesforce.' + SUBSTRING(@tableName, 4, LEN(@tableName) - 3)
            PRINT 'Truncate SQL: ' + @sql
            EXEC sp_executesql @sql

            -- Insert data from the lakehouse table into the warehouse table
            SET @insertDataSQL = 'INSERT INTO Salesforce.' + SUBSTRING(@tableName, 4, LEN(@tableName) - 3) + ' SELECT * FROM Enriched_Lakehouse.dbo.' + @tableName + ' WHERE Current_Record_Flag = 1'
            PRINT 'Insert Data SQL: ' + @insertDataSQL
            EXEC sp_executesql @insertDataSQL
        END
        ELSE
        BEGIN
            -- Create the table in the warehouse using CTAS
            SET @createTableSQL = 'CREATE TABLE Salesforce.' + SUBSTRING(@tableName, 4, LEN(@tableName) - 3) + ' AS SELECT * FROM Enriched_Lakehouse.dbo.' + @tableName + ' WHERE Current_Record_Flag = 1'
            PRINT 'Create Table SQL: ' + @createTableSQL
            EXEC sp_executesql @createTableSQL
        END

        -- Move to the next row
        SET @currentRow = @currentRow + 1
    END

    -- Clean up the temporary table
    DROP TABLE #TableList
END
GO


