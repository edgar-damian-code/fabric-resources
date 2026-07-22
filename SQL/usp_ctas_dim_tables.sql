/**
-----------------------------------------------------------------------------------------------------------
Author:			Edgar Damian
Organization:	Wipfli LLP
ALTERd:		    2025-06-03

Purpose:		CTAS Procedure to load BIX dimension tables from SilverData
-----------------------------------------------------------------------------------------------------------
Notes:			
-----------------------------------------------------------------------------------------------------------
Change Audit:
	
				Change Date:		Changed By:			Change Description:
				------------		-------------		---------------------------------------------------
				06/03/2025			Edgar Damian		Initial script creation
                06/05/2025          Edgar Damian        Modified to write to Utility log table

-----------------------------------------------------------------------------------------------------------
**/

CREATE PROCEDURE [Utility].[usp_ctas_dim_tables]
    @SourceDatabase NVARCHAR(128),
    @SourceSchema NVARCHAR(128),
    @SourceTable NVARCHAR(128),
    @TargetDatabase NVARCHAR(128),
    @TargetSchema NVARCHAR(128),
    @TargetTable NVARCHAR(128),
    @LoadDateColumn NVARCHAR(128)
AS
BEGIN
    DECLARE @sql NVARCHAR(MAX);
    DECLARE @StartTime DATETIME = GETDATE();
    DECLARE @EndTime DATETIME;
    DECLARE @InsertedCount INT = 0;
    DECLARE @Status NVARCHAR(50) = 'Success';
    DECLARE @ErrorMessage NVARCHAR(MAX);
    DECLARE @ErrorNumber INT;
    DECLARE @ErrorSeverity INT;
    DECLARE @ErrorState INT;
    DECLARE @ErrorLine INT = NULL; -- Not supported in Fabric
    DECLARE @ErrorProcedure NVARCHAR(MAX)

    BEGIN TRY
        SET @sql = '
        IF EXISTS (
            SELECT * FROM ' + QUOTENAME(@TargetDatabase) + '.sys.objects 
            WHERE object_id = OBJECT_ID(N''' + QUOTENAME(@TargetDatabase) + '.' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable) + ''') 
            AND type = ''U''
        )
        DROP TABLE ' + QUOTENAME(@TargetDatabase) + '.' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable) + ';' 
        + ' 
        CREATE TABLE ' + QUOTENAME(@TargetDatabase) + '.' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable) + '
        AS
        SELECT *
        FROM ' + QUOTENAME(@SourceDatabase) + '.' + QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable) + '
        WHERE ' + @LoadDateColumn + ' = (
            SELECT MAX(' + @LoadDateColumn + ')
            FROM ' + QUOTENAME(@SourceDatabase) + '.' + QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable) + '
        );'
        ;

        PRINT 'Executing SQL: ' + @sql;
        EXEC sp_executesql @sql;

        SET @InsertedCount = @@ROWCOUNT;
    END TRY
    BEGIN CATCH
        SET @ErrorMessage = ERROR_MESSAGE();
        SET @ErrorNumber = ERROR_NUMBER();
        SET @ErrorSeverity = ERROR_SEVERITY();
        SET @ErrorState = ERROR_STATE();
        SET @Status = 'Failure';
        SET @ErrorProcedure = ERROR_PROCEDURE();

        PRINT 'Error occurred: ' + @ErrorMessage;
    END CATCH

    SET @EndTime = GETDATE();

    INSERT INTO Utility.etl_log (
        ProcessName,
        SourceObject,
        TargetObject,
        StartTime,
        EndTime,
        InsertCount,
        ErrorMessage,
        ErrorNumber,
        ErrorSeverity,
        ErrorState,
        ErrorLine,
        ErrorProcedure,
        Status,
        SQL_Query
    )
    VALUES (
        'usp_ctas_dim_tables',
        @SourceDatabase + '.' + @SourceSchema + '.' + @SourceTable,
        @TargetSchema + '.' + @TargetTable,
        @StartTime,
        @EndTime,
        @InsertedCount,
        @ErrorMessage,
        @ErrorNumber,
        @ErrorSeverity,
        @ErrorState,
        @ErrorLine,
        @ErrorProcedure,
        @Status,
        @sql
    );
END