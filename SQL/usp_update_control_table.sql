CREATE PROCEDURE [util_silver].[UpdateControlTable]
@ELTLoadTime DATETIME,
@TgtTable NVARCHAR(255)
AS
BEGIN
    -- Step 1: Update the SRC_LAST_EXTRACT_DTM column in the control table
    UPDATE etl_bronze_to_silver_control
    SET SRC_LAST_EXTRACT_DTM = @ELTLoadTime
    WHERE TGT_TABLE_NAME = @TgtTable;
END;
GO