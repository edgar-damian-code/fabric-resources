CREATE PROCEDURE [Stage].[usp_raw_control_table_update]
AS
BEGIN
    MERGE Stage.etl_source_to_stage_control AS target
    USING Stage.UTIL_ETL_SOURCE_TO_STAGE_CONTROL AS src
    ON LTRIM(RTRIM(target.ETL_PIPELINE_DK)) = LTRIM(RTRIM(src.ETL_PIPELINE_DK))
    WHEN MATCHED THEN
        UPDATE SET 
            target.ETL_PIPELINE_DK = src.ETL_PIPELINE_DK,
            target.ETL_PIPELINE_GROUP = src.ETL_PIPELINE_GROUP,
            target.ETL_PIPELINE_ACTIVE_IND = src.ETL_PIPELINE_ACTIVE_IND,
            target.ETL_PIPELINE_TASK_GROUP = src.ETL_PIPELINE_TASK_GROUP,
            target.SRC_SYSTEM_ABBR = src.SRC_SYSTEM_ABBR,
            target.SRC_SERVER_NAME = src.SRC_SERVER_NAME,
            target.SRC_TYPE = src.SRC_TYPE,
            target.SRC_DB_NAME = src.SRC_DB_NAME,
            target.SRC_AKV_SECRET_NAME = src.SRC_AKV_SECRET_NAME,
            target.SRC_SCHEMA_NAME = src.SRC_SCHEMA_NAME,
            target.SRC_TABLE_NAME = src.SRC_TABLE_NAME,
            target.SRC_COLUMN_LIST1 = src.SRC_COLUMN_LIST1,
            target.SRC_COLUMN_LIST2 = src.SRC_COLUMN_LIST2,
            target.TGT_TYPE = src.TGT_TYPE,
            target.TGT_DB_NAME = src.TGT_DB_NAME,
            target.TGT_LH_ID = src.TGT_LH_ID,
            target.TGT_SCHEMA_NAME = src.TGT_SCHEMA_NAME,
            target.TGT_TABLE_NAME = src.TGT_TABLE_NAME,
            target.TGT_STORAGE_PATH = src.TGT_STORAGE_PATH,
            target.INCREMENTAL_IND = src.INCREMENTAL_IND,
            target.KEY_FIELD1 = src.KEY_FIELD1,
            target.INCREMENTAL_FIELD1 = src.INCREMENTAL_FIELD1,
            target.SRC_LAST_EXTRACT_STAMP = src.SRC_LAST_EXTRACT_STAMP,
            target.SRC_FULL_REFRESH_DTM = src.SRC_FULL_REFRESH_DTM,
            target.ETL_PIPELINE_SK = src.ETL_PIPELINE_SK
    WHEN NOT MATCHED THEN
        INSERT (
            ETL_PIPELINE_DK,
            ETL_PIPELINE_GROUP,
            ETL_PIPELINE_ACTIVE_IND,
            ETL_PIPELINE_TASK_GROUP,
            SRC_SYSTEM_ABBR,
            SRC_SERVER_NAME,
            SRC_TYPE,
            SRC_DB_NAME,
            SRC_AKV_SECRET_NAME,
            SRC_SCHEMA_NAME,
            SRC_TABLE_NAME,
            SRC_COLUMN_LIST1,
            SRC_COLUMN_LIST2,
            TGT_TYPE,
            TGT_DB_NAME,
            TGT_LH_ID,
            TGT_SCHEMA_NAME,
            TGT_TABLE_NAME,
            TGT_STORAGE_PATH,
            INCREMENTAL_IND,
            KEY_FIELD1,
            INCREMENTAL_FIELD1,
            SRC_LAST_EXTRACT_DTM,
            SRC_LAST_EXTRACT_STAMP,
            SRC_FULL_REFRESH_DTM,
            ETL_PIPELINE_SK
        )
        VALUES (
            src.ETL_PIPELINE_DK,
            src.ETL_PIPELINE_GROUP,
            src.ETL_PIPELINE_ACTIVE_IND,
            src.ETL_PIPELINE_TASK_GROUP,
            src.SRC_SYSTEM_ABBR,
            src.SRC_SERVER_NAME,
            src.SRC_TYPE,
            src.SRC_DB_NAME,
            src.SRC_AKV_SECRET_NAME,
            src.SRC_SCHEMA_NAME,
            src.SRC_TABLE_NAME,
            src.SRC_COLUMN_LIST1,
            src.SRC_COLUMN_LIST2,
            src.TGT_TYPE,
            src.TGT_DB_NAME,
            src.TGT_LH_ID,
            src.TGT_SCHEMA_NAME,
            src.TGT_TABLE_NAME,
            src.TGT_STORAGE_PATH,
            src.INCREMENTAL_IND,
            src.KEY_FIELD1,
            src.INCREMENTAL_FIELD1,
            src.SRC_LAST_EXTRACT_DTM,
            src.SRC_LAST_EXTRACT_STAMP,
            src.SRC_FULL_REFRESH_DTM,
            src.ETL_PIPELINE_SK
        );
END;
GO
