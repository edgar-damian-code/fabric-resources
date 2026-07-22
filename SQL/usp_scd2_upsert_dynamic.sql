/**
-----------------------------------------------------------------------------------------------------------
Author:         Edgar Damian
Organization:   
ALTERd:         2025-08-11

Purpose:        Dynamic Stored Procedure that takes silver data and performs scd type 2 update + insert
-----------------------------------------------------------------------------------------------------------
Notes:   
-----------------------------------------------------------------------------------------------------------
Change Audit:
	
				Change Date:		Changed By:			Change Description:
				------------		-------------		---------------------------------------------------
				08/11/2025			Edgar Damian		Initial script creation

-----------------------------------------------------------------------------------------------------------
**/

CREATE OR ALTER   PROCEDURE Utility.usp_scd2_upsert_dynamic
    @TargetDatabase   sysname,
    @TargetSchema     sysname,
    @TargetTable      sysname,           
    @StagingSchema    sysname,
    @StagingTable     sysname,            
    @NaturalKeys      nvarchar(max),      
    @ValidFromCol     sysname = 'ELT_VALID_FROM',
    @ValidToCol       sysname = 'ELT_VALID_TO',
    @IsCurrentCol     sysname = 'Current_Record_Flag',
    @HashCol          sysname = 'ELT_SCD_HASH',
    @Debug            bit = 0
AS
BEGIN
  SET NOCOUNT ON;

  /* --- Logging vars --- */
  DECLARE @RunIdStr        varchar(36) = CONVERT(varchar(36), NEWID());
  DECLARE @StartTime       datetime2(6) = SYSUTCDATETIME();
  DECLARE @EndTime         datetime2(6);
  DECLARE @Status          varchar(50) = 'Success';
  DECLARE @ErrorMessage    nvarchar(max) = NULL;
  DECLARE @ErrorNumber     int = NULL;
  DECLARE @ErrorSeverity   int = NULL;
  DECLARE @ErrorState      int = NULL;
  DECLARE @ErrorLine       int = NULL;   -- Not supported in Fabric
  DECLARE @ErrorProcedure  nvarchar(max) = NULL;

  DECLARE @RowsClosed      int = 0;
  DECLARE @RowsInserted    int = 0;
  DECLARE @FirstRunCTAS    bit = 0;

  DECLARE @SQL_CTAS   nvarchar(max) = NULL;
  DECLARE @SQL_Close  nvarchar(max) = NULL;
  DECLARE @SQL_Insert nvarchar(max) = NULL;

  /* --- Inputs / setup --- */
  IF (SELECT COUNT(*) FROM STRING_SPLIT(@NaturalKeys, ',') WHERE LTRIM(RTRIM(value)) <> '') = 0
  BEGIN
    RAISERROR('Natural keys list is empty or invalid.', 16, 1);
    RETURN;
  END;

  DECLARE
    @tgt3  nvarchar(512) = QUOTENAME(@TargetDatabase)+'.'+QUOTENAME(@TargetSchema)+'.'+QUOTENAME(@TargetTable),
    @stg3  nvarchar(512) = QUOTENAME(@TargetDatabase)+'.'+QUOTENAME(@StagingSchema)+'.'+QUOTENAME(@StagingTable),
    @join  nvarchar(max),
    @sql   nvarchar(max);

  BEGIN TRY
    /* 1) First run: if target doesn't exist, CTAS from staging and exit */
    IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(@tgt3) AND type = 'U')
    BEGIN
        SET @SQL_CTAS = N'CREATE TABLE ' + @tgt3 + N' AS SELECT * FROM ' + @stg3 + N';';
        IF @Debug = 1 PRINT @SQL_CTAS;
        EXEC sys.sp_executesql @SQL_CTAS;

        SET @FirstRunCTAS = 1;
        GOTO _FinalizeLogAndExit;
    END;

    /* 2) Lightweight schema guard (counts + ordinal mismatch) */
    DECLARE @MismatchCnt int = 0, @CntTgt int = 0, @CntStg int = 0;

    SET @sql = N'
    ;WITH tgt AS (
        SELECT COLUMN_NAME, ORDINAL_POSITION
        FROM ' + QUOTENAME(@TargetDatabase) + N'.INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = @TargetSchema AND TABLE_NAME = @TargetTable
    ),
    stg AS (
        SELECT COLUMN_NAME, ORDINAL_POSITION
        FROM ' + QUOTENAME(@TargetDatabase) + N'.INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = @StagingSchema AND TABLE_NAME = @StagingTable
    ),
    cmp AS (
        SELECT COALESCE(t.ORDINAL_POSITION, s.ORDINAL_POSITION) AS ord,
               t.COLUMN_NAME AS tgt_col,
               s.COLUMN_NAME AS stg_col
        FROM tgt t
        FULL JOIN stg s
          ON s.ORDINAL_POSITION = t.ORDINAL_POSITION
    )
    SELECT
        @CntTgtOut = (SELECT COUNT(*) FROM tgt),
        @CntStgOut = (SELECT COUNT(*) FROM stg),
        @MismatchOut = SUM(CASE WHEN tgt_col IS NULL OR stg_col IS NULL OR tgt_col <> stg_col THEN 1 ELSE 0 END)
    FROM cmp;';
    EXEC sys.sp_executesql @sql,
         N'@TargetSchema sysname,@TargetTable sysname,@StagingSchema sysname,@StagingTable sysname,
           @CntTgtOut int OUTPUT,@CntStgOut int OUTPUT,@MismatchOut int OUTPUT',
         @TargetSchema,@TargetTable,@StagingSchema,@StagingTable,
         @CntTgt OUTPUT,@CntStg OUTPUT,@MismatchCnt OUTPUT;

    IF (@CntTgt <> @CntStg OR @MismatchCnt > 0)
    BEGIN
        RAISERROR('Staging/Target schema mismatch by ordinal. Create staging as SELECT TOP 0 * FROM target and reload.', 16, 1);
    END;

    /* 3) Build NK join once */
    SELECT @join =
      STRING_AGG(N't.'+QUOTENAME(LTRIM(RTRIM(value)))+N'=r.'+QUOTENAME(LTRIM(RTRIM(value))), N' AND ')
    FROM STRING_SPLIT(@NaturalKeys, ',');

    /* 4) CLOSE only rows whose hash changed */
    SET @SQL_Close = N'
      UPDATE t
         SET t.'+QUOTENAME(@ValidToCol)+N'   = r.'+QUOTENAME(@ValidFromCol)+N',
             t.'+QUOTENAME(@IsCurrentCol)+N' = 0
      FROM '+@tgt3+N' AS t
      JOIN '+@stg3+N' AS r
        ON '+@join+N'
      WHERE t.'+QUOTENAME(@IsCurrentCol)+N' = 1
        AND ISNULL(t.'+QUOTENAME(@HashCol)+N','''') <> ISNULL(r.'+QUOTENAME(@HashCol)+N','''');';
    IF @Debug=1 PRINT @SQL_Close;
    EXEC sys.sp_executesql @SQL_Close;
    SET @RowsClosed = @@ROWCOUNT;

    /* 5) INSERT new + changed (schemas identical → SELECT r.*) */
    SET @SQL_Insert = N'
      INSERT INTO '+@tgt3+N'
      SELECT r.*
      FROM '+@stg3+N' AS r
      LEFT JOIN '+@tgt3+N' AS t
        ON '+@join+N'
       AND t.'+QUOTENAME(@IsCurrentCol)+N' = 1
      WHERE t.'+QUOTENAME(@HashCol)+N' IS NULL
         OR ISNULL(t.'+QUOTENAME(@HashCol)+N','''') <> ISNULL(r.'+QUOTENAME(@HashCol)+N','''');';
    IF @Debug=1 PRINT @SQL_Insert;
    EXEC sys.sp_executesql @SQL_Insert;
    SET @RowsInserted = @@ROWCOUNT;

    GOTO _FinalizeLogAndExit;
  END TRY
  BEGIN CATCH
    SET @Status         = 'Failure';
    SET @ErrorMessage   = ERROR_MESSAGE();
    SET @ErrorNumber    = ERROR_NUMBER();
    SET @ErrorSeverity  = ERROR_SEVERITY();
    SET @ErrorState     = ERROR_STATE();
    SET @ErrorProcedure = ERROR_PROCEDURE();

    PRINT 'Error occurred: ' + ISNULL(@ErrorMessage,'(null)');
    -- Fall through to logging
  END CATCH

  _FinalizeLogAndExit:
  SET @EndTime = SYSUTCDATETIME();

  /* 6) Ensure log table exists (Fabric-safe: no IDENTITY/PK/defaults) */
  IF OBJECT_ID('Utility.gold_scd_finalize_log','U') IS NULL
  BEGIN
    EXEC sys.sp_executesql N'
      CREATE TABLE Utility.gold_scd_finalize_log
      (
        RunId            varchar(36),
        ProcessName      varchar(128),
        TargetObject     varchar(512),
        StagingObject    varchar(512),
        StartTime        datetime2(6),
        EndTime          datetime2(6),
        CloseCount       int,
        InsertCount      int,
        FirstRunCTAS     bit,
        Status           varchar(50),
        ErrorMessage     varchar(4000),
        ErrorNumber      int,
        ErrorSeverity    int,
        ErrorState       int,
        ErrorLine        int,
        ErrorProcedure   varchar(4000),
        SQL_CTAS         varchar(4000),
        SQL_Close        varchar(4000),
        SQL_Insert       varchar(4000)
      );';
  END;

  /* 7) Write log row */
  INSERT INTO Utility.gold_scd_finalize_log
  (
    RunId, ProcessName, TargetObject, StagingObject,
    StartTime, EndTime,
    CloseCount, InsertCount, FirstRunCTAS,
    Status, ErrorMessage, ErrorNumber, ErrorSeverity, ErrorState, ErrorLine, ErrorProcedure,
    SQL_CTAS, SQL_Close, SQL_Insert
  )
  VALUES
  (
    @RunIdStr,
    'usp_finalize_scd_from_staging',
    CONVERT(varchar(512), @tgt3),
    CONVERT(varchar(512), @stg3),
    @StartTime, @EndTime,
    @RowsClosed, @RowsInserted, @FirstRunCTAS,
    @Status,
    LEFT(CONVERT(varchar(4000), @ErrorMessage), 4000),
    @ErrorNumber, @ErrorSeverity, @ErrorState, @ErrorLine,
    LEFT(CONVERT(varchar(4000), @ErrorProcedure), 4000),
    LEFT(CONVERT(varchar(4000), @SQL_CTAS), 4000),
    LEFT(CONVERT(varchar(4000), @SQL_Close), 4000),
    LEFT(CONVERT(varchar(4000), @SQL_Insert), 4000)
  );
END