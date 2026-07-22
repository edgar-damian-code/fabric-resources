/****** Object:  StoredProcedure [Utility].[usp_ctas_all_tables]    Script Date: 2/26/2025 3:17:06 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/**
------------------------------------------------------------
Author:			Scotty O'Leary
Organization:	Wipfli LLP
Created:		2025-01-07

Purpose:		Dynamic procedure that populates a target from a source
------------------------------------------------------------
Notes:			Takes a view definition
------------------------------------------------------------
Change Audit:
	
				Change Date:		Changed By:			Change Description:
				------------		-------------		---------------------------------------------------
				01/07/2025			Scotty O'Leary		Initial script creation

------------------------------------------------------------
**/
ALTER   PROCEDURE [Utility].[usp_ctas_all_tables]
        @SOURCE_SCHEMA VARCHAR(255)
    ,   @TARGET_SCHEMA VARCHAR(255)
    ,   @SOURCE_OBJECT VARCHAR(255)
    ,   @TARGET_TABLE VARCHAR(255)
AS

BEGIN TRY 
--Declare variables for dynamic sql queries
DECLARE @v_ctas_sql VARCHAR(8000)
DECLARE @v_schema_name varchar(255)
DECLARE @v_table_name varchar(255)
--
SELECT   @v_schema_name = sch.name, @v_table_name = obj.name
FROM    sys.objects obj
INNER JOIN sys.schemas sch ON sch.schema_id = obj.schema_id
where obj.name = @SOURCE_OBJECT
 ;
IF @@ROWCOUNT >= 1
BEGIN
    --Set dynamic CTAS table variable
    SET @v_ctas_sql = 'IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''' + @TARGET_SCHEMA + '.' + @TARGET_TABLE + '''' + ') AND type in (N''U'')) DROP TABLE ' + @TARGET_SCHEMA + '.' + @TARGET_TABLE + ';' + ' CREATE TABLE ' + @TARGET_SCHEMA + '.' + @TARGET_TABLE + ' AS SELECT * FROM ' + @SOURCE_SCHEMA + '.' + @SOURCE_OBJECT + ';'

    --Create the table
    EXECUTE (@v_ctas_sql)
END
ELSE 
BEGIN
    PRINT('Likely the source table doesn''t exist. Check UTIL file for parameter values.')
END


END TRY 

BEGIN CATCH 

DECLARE  @MESSAGE VARCHAR(8000) = ERROR_MESSAGE(), 
        @SEVERITY INT = ERROR_SEVERITY(), @STATE INT = ERROR_STATE() 

IF @@TRANCOUNT > 0 

BEGIN ROLLBACK TRAN; 

END 

RAISERROR(@MESSAGE,@SEVERITY,@STATE); 

SELECT @MESSAGE AS ERRORMESSAGE END CATCH; 

IF @@TRANCOUNT > 0 

BEGIN COMMIT TRAN 

END
GO


