/**
-----------------------------------------------------------------------------------------------------------
Author:			Edgar Damian
Organization:	
ALTERd:		    2025-08-10

Purpose:		CTAS Procedure to load tables from SilverData
-----------------------------------------------------------------------------------------------------------
Notes:			
-----------------------------------------------------------------------------------------------------------
Change Audit:
	
				Change Date:		Changed By:			Change Description:
				------------		-------------		---------------------------------------------------
				07/23/2025			Edgar Damian		Initial script creation

-----------------------------------------------------------------------------------------------------------
**/

CREATE OR ALTER   PROCEDURE [Utility].[usp_ctas_tables]
    @SourceDatabase   sysname,
    @SourceSchema     sysname,
    @SourceTable      sysname,
    @TargetDatabase   sysname,
    @TargetSchema     sysname,
    @TargetTable      sysname,         
    @NaturalKeys      nvarchar(max),    -- e.g., N'BranchID' or N'CompanyID,LocationID'
    @ValidFromCol     sysname = 'ELT_VALID_FROM',
    @IsCurrentCol     sysname = 'Current_Record_Flag',
    @SurrogateKeyCol  sysname = 'SurrogateKey'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @sql NVARCHAR(MAX);
    DECLARE @StartTime DATETIME2(6) = SYSUTCDATETIME();
    DECLARE @EndTime   DATETIME2(6);
    DECLARE @InsertedCount INT = 0;
    DECLARE @Status VARCHAR(50) = 'Success';
    DECLARE @ErrorMessage VARCHAR(MAX) = NULL;
    DECLARE @ErrorNumber INT = NULL;
    DECLARE @ErrorSeverity INT = NULL;
    DECLARE @ErrorState INT = NULL;
    DECLARE @ErrorLine INT = NULL; -- Not supported in Fabric
    DECLARE @ErrorProcedure VARCHAR(MAX) = NULL;

    DECLARE @tgt3 nvarchar(512) =
        QUOTENAME(@TargetDatabase)+'.'+QUOTENAME(@TargetSchema)+'.'+QUOTENAME(@TargetTable);
    DECLARE @src3 nvarchar(512) =
        QUOTENAME(@SourceDatabase)+'.'+QUOTENAME(@SourceSchema)+'.'+QUOTENAME(@SourceTable);

    BEGIN TRY
        /* 1) Recreate staging from Silver “current” rows */
        SET @sql = N'
        IF EXISTS (
            SELECT 1
            FROM ' + QUOTENAME(@TargetDatabase) + N'.sys.objects 
            WHERE object_id = OBJECT_ID(N''' + @tgt3 + N''') AND type = N''U''
        )
            DROP TABLE ' + @tgt3 + N';

        CREATE TABLE ' + @tgt3 + N'
        AS
        SELECT *
        FROM ' + @src3 + N'
        WHERE ' + QUOTENAME(@IsCurrentCol) + N' = 1;';

        PRINT N'[CTAS] ' + @sql;
        EXEC sys.sp_executesql @sql;
        SET @InsertedCount = @@ROWCOUNT;

        /* 2) Ensure SurrogateKey column exists on staging */
        SET @sql = N'
        IF NOT EXISTS (
            SELECT 1
            FROM ' + QUOTENAME(@TargetDatabase) + N'.INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = @S AND TABLE_NAME = @T AND COLUMN_NAME = @C
        )
        BEGIN
            ALTER TABLE ' + @tgt3 + N' ADD ' + QUOTENAME(@SurrogateKeyCol) + N' BIGINT NULL;
        END;';
        EXEC sys.sp_executesql @sql,
             N'@S sysname,@T sysname,@C sysname',
             @TargetSchema,@TargetTable,@SurrogateKeyCol;

        /* 3) Build NK concatenation for deterministic SK:  ISNULL(CONVERT(varchar(4000), r.[K]),'''') + '|' + ... */
        DECLARE @nkConcat nvarchar(max);
        SELECT @nkConcat =
          STRING_AGG(N'ISNULL(CONVERT(varchar(4000), r.['+LTRIM(RTRIM(value))+N']), '''')', N' + ''|'' + ')
        FROM STRING_SPLIT(@NaturalKeys, ',');

        IF (@nkConcat IS NULL OR LTRIM(RTRIM(@nkConcat)) = N'')
        BEGIN
            RAISERROR('Natural keys list is empty or invalid.', 16, 1);
            RETURN;
        END;

        /* 4) Compute SK in staging (NKs + ValidFrom → first 8 bytes of SHA-256 as BIGINT, positive) */
        SET @sql = N'
        UPDATE r
           SET r.'+QUOTENAME(@SurrogateKeyCol)+N' =
               ABS(CONVERT(BIGINT, SUBSTRING(
                   HASHBYTES(''SHA2_256'', (' + @nkConcat + N') + ''|'' + CONVERT(varchar(33), r.'+QUOTENAME(@ValidFromCol)+N', 126)), 1, 8)))
        FROM ' + @tgt3 + N' AS r;';
        PRINT N'[SK UPDATE] ' + @sql;
        EXEC sys.sp_executesql @sql;

    END TRY
    BEGIN CATCH
        SET @ErrorMessage   = ERROR_MESSAGE();
        SET @ErrorNumber    = ERROR_NUMBER();
        SET @ErrorSeverity  = ERROR_SEVERITY();
        SET @ErrorState     = ERROR_STATE();
        SET @ErrorProcedure = ERROR_PROCEDURE();
        SET @Status         = 'Failure';

        PRINT 'Error occurred: ' + ISNULL(@ErrorMessage,'(null)');
    END CATCH;

    SET @EndTime = SYSUTCDATETIME();

    INSERT INTO Utility.silver_to_gold_elt_log (
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
        'usp_ctas_tables',
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
