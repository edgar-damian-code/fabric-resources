CREATE PROCEDURE [util_silver].[usp_merge_control_table_from_bronze]
AS
BEGIN
    MERGE INTO util_silver.etl_bronze_to_silver_control AS target
    USING util_bronze.etl_source_to_bronze_control AS src
    ON target.ETL_PIPELINE_DK = src.ETL_PIPELINE_DK
    WHEN MATCHED THEN
        UPDATE SET 
            ETL_PIPELINE_ACTIVE_IND = src.ETL_PIPELINE_ACTIVE_IND
    WHEN NOT MATCHED THEN
        INSERT (
            ETL_PIPELINE_DK,
            ETL_PIPELINE_GROUP,
            ETL_PIPELINE_ACTIVE_IND,
            SRC_SYSTEM_ABBR,
            SRC_SERVER_NAME,
            SRC_TYPE,
            SRC_DB_NAME,
            SRC_AKV_SECRET_NAME,
            SRC_SCHEMA_NAME,
            SRC_TABLE_NAME,
            SRC_COLUMN_LIST1,
            TGT_TYPE,
            TGT_DB_NAME,
            TGT_SCHEMA_NAME,
            TGT_TABLE_NAME,
            INCREMENTAL_IND,
            KEY_FIELD,
            INCREMENTAL_FIELD,
            SRC_LAST_EXTRACT_DTM
        )
        VALUES (
            src.ETL_PIPELINE_DK,
            src.ETL_PIPELINE_GROUP,
            src.ETL_PIPELINE_ACTIVE_IND,
            src.SRC_SYSTEM_ABBR,
            src.SRC_SERVER_NAME,
            src.TGT_TYPE,
            src.TGT_DB_NAME,
            src.SRC_AKV_SECRET_NAME,
            src.TGT_SCHEMA_NAME,
            src.TGT_TABLE_NAME,
            src.SRC_COLUMN_LIST1,
            src.TGT_TYPE,
            'SilverData',
            'dbo',
            CASE
                WHEN src.SRC_SYSTEM_ABBR = 'HD' THEN src.TGT_TABLE_NAME
                WHEN src.TGT_TABLE_NAME LIKE '%BIX_Fact%' THEN REPLACE(src.TGT_TABLE_NAME, 'BIX_fact', 'bix_fact_')
                WHEN src.TGT_TABLE_NAME LIKE '%BIX_Dim%' THEN REPLACE(src.TGT_TABLE_NAME, 'BIX_dim', 'bix_dim_')
                ELSE src.TGT_TABLE_NAME
            END,
            src.INCREMENTAL_IND,
            src.KEY_FIELD,
            src.INCREMENTAL_FIELD,
            src.SRC_LAST_EXTRACT_DTM
        );
END;
GO
