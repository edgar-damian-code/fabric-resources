/**
------------------------------------------------------------
Author:   Edgar Damian
Organization: Wipfli LLP
ALTERd:  2025-06-02

Purpose:  Dynamic Stored Procedure that takes silver data and populates a table from the results
------------------------------------------------------------
Notes:   
------------------------------------------------------------
Change Audit:
 
    Change Date:    Changed By:     Change Description:
    ------------  -------------     ---------------------------------------------------
    06/02/2025      Edgar Damian    Initial script creation
    06/04/2025      Edgar Damian    Modified logic to log to a warehouse log table 
    06/05/2025      Edgar Damian    Removed filers for Current_Record_Flag

------------------------------------------------------------
**/

CREATE PROCEDURE [Utility].[usp_merge_fact_tables]
    @SourceDatabase NVARCHAR(128),
    @SourceSchema NVARCHAR(128),
    @SourceTable NVARCHAR(128),
    @TargetDatabase NVARCHAR(128),
    @TargetSchema NVARCHAR(128),
    @TargetTable NVARCHAR(128),
    @LoadDateColumn NVARCHAR(128)
AS
BEGIN
    DECLARE @merge_sql NVARCHAR(MAX);
    DECLARE @StartTime DATETIME2 = GETDATE();
    DECLARE @EndTime DATETIME2;
    DECLARE @InsertedCount INT = 0;
    DECLARE @Status NVARCHAR(50) = 'Success';
    DECLARE @ErrorMessage NVARCHAR(MAX);
    DECLARE @ErrorNumber INT;
    DECLARE @ErrorSeverity INT;
    DECLARE @ErrorState INT;
    DECLARE @ErrorLine INT = NULL; -- Not supported in Fabric
    DECLARE @ErrorProcedure NVARCHAR(MAX); 

    BEGIN TRY
        -- If the target table doesn't exist, create it using CTAS
        SET @merge_sql = '
        IF NOT EXISTS (
            SELECT * FROM ' + QUOTENAME(@TargetDatabase) + '.sys.objects 
            WHERE object_id = OBJECT_ID(N''' + QUOTENAME(@TargetDatabase) + '.' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable) + ''') 
            AND type in (N''U'')
        )
        BEGIN
            CREATE TABLE ' + QUOTENAME(@TargetDatabase) + '.' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable) + '
            AS
            SELECT *
            FROM ' + QUOTENAME(@SourceDatabase) + '.' + QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable) + '
            ;
        END
        ELSE
        BEGIN
            INSERT INTO ' + QUOTENAME(@TargetDatabase) + '.' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable) + '
            SELECT *
            FROM ' + QUOTENAME(@SourceDatabase) + '.' + QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable) + ' AS src
            WHERE NOT EXISTS (
                SELECT 1
                FROM ' + QUOTENAME(@TargetDatabase) + '.' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable) + ' AS tgt
                WHERE tgt.ELT_SCD_HASH = src.ELT_SCD_HASH
              );
        END';

        PRINT 'Merge SQL: ' + @merge_sql;
        EXEC sp_executesql @merge_sql;

        SET @InsertedCount = @@ROWCOUNT;
    END TRY
    BEGIN CATCH
        SET @ErrorMessage = ERROR_MESSAGE();
        SET @ErrorNumber = ERROR_NUMBER();
        SET @ErrorSeverity = ERROR_SEVERITY();
        SET @ErrorState = ERROR_STATE();
        SET @ErrorProcedure = ERROR_PROCEDURE();
        SET @Status = 'Failure';

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
        'usp_merge_fact_tables',
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
        @merge_sql
    );
END