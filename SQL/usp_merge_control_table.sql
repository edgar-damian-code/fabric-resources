CREATE PROCEDURE [Enriched].[usp_merge_control_table_from_stage]
AS
BEGIN
    MERGE INTO Enriched.etl_stage_to_enriched_control AS target
    USING Stage.etl_source_to_stage_control AS src
    ON target.ETL_PIPELINE_SK = src.ETL_PIPELINE_DK
    WHEN MATCHED THEN
        UPDATE SET 
            ETL_PIPELINE_ACTIVE_IND = src.ETL_PIPELINE_ACTIVE_IND
    WHEN NOT MATCHED THEN
        INSERT (
            ETL_PIPELINE_SK,
            SRC_SYSTEM_ABBR,
            CTRL_GROUP,
            CTRL_TASK_GROUP,
            ETL_PIPELINE_ACTIVE_IND,
            CTRL_SRC_PATH,
            CTRL_SRC_SCHEMA_NAME,
            CTRL_SRC_DB_NAME,
            CTRL_TGT_DB_NAME,
            CTRL_SRC_ENTITY,
            CTRL_TGT_ENTITY,
            CTRL_MERGE_KEY_COLS,
            CTRL_TGT_SCHEMA_NAME,
            CTRL_SRC_MODIFIED_FIELD,
            CTRL_TGT_MODIFIED_FIELD,
            INCREMENTAL_IND,
            CTRL_ETL_TABLE_NAME
        )
        VALUES (
            src.ETL_PIPELINE_DK,
            src.SRC_SYSTEM_ABBR,
            'ELT_BRONZE_TO_SILVER',
            CASE 
                WHEN src.SRC_SYSTEM_ABBR = 'sf' THEN 'SF_TABLES'
                WHEN src.SRC_SYSTEM_ABBR = 'ns' THEN 'NS_TABLES'
                ELSE src.SRC_SYSTEM_ABBR 
            END,
            src.ETL_PIPELINE_ACTIVE_IND,
            NULL,
            src.SRC_SCHEMA_NAME,
            src.TGT_DB_NAME,
            'Enriched_Lakehouse',
            src.TGT_TABLE_NAME,
            src.TGT_TABLE_NAME,
            src.KEY_FIELD1,
            src.TGT_SCHEMA_NAME,
            src.SRC_LAST_EXTRACT_DTM,
            NULL,
            0,
            'etl_pipeline_control'
        );
END;
GO
