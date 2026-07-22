CREATE PROCEDURE [Gold].[usp_gold_control_table_update]
AS
BEGIN
    MERGE Gold.ELT_silver_to_gold_control AS target
    USING Gold.UTIL_ELT_SILVER_TO_GOLD_CONTROL AS src
    ON target.ELT_PIPELINE_DK = src.ELT_PIPELINE_DK
    WHEN MATCHED THEN
        UPDATE SET 
            target.[CTRL_GROUP]              = src.[CTRL_GROUP], 
            target.[CTRL_TASK_GROUP]         = src.[CTRL_TASK_GROUP], 
            target.[CTRL_PIPELINE_GROUP]     = src.[CTRL_PIPELINE_GROUP], 
            target.[ELT_PIPELINE_ACTIVE_IND] = src.[ELT_PIPELINE_ACTIVE_IND],
            target.[SRC_SYSTEM_ABBR]         = src.[SRC_SYSTEM_ABBR], 
            target.[SRC_DB_NAME]             = src.[SRC_DB_NAME], 
            target.[SRC_SCHEMA_NAME]         = src.[SRC_SCHEMA_NAME], 
            target.[SRC_TABLE_NAME]          = src.[SRC_TABLE_NAME], 
            target.[STG_DB_NAME]             = src.[STG_DB_NAME], 
            target.[STG_SCHEMA_NAME]         = src.[STG_SCHEMA_NAME], 
            target.[STG_TABLE_NAME]          = src.[STG_TABLE_NAME], 
            target.[FIN_DB_NAME]             = src.[FIN_DB_NAME], 
            target.[FIN_SCHEMA_NAME]         = src.[FIN_SCHEMA_NAME], 
            target.[FIN_TABLE_NAME]          = src.[FIN_TABLE_NAME], 
            target.[NATURAL_KEYS]            = src.[NATURAL_KEYS], 
            target.[VALID_FROM_COL]          = src.[VALID_FROM_COL], 
            target.[VALID_TO_COL]            = src.[VALID_TO_COL], 
            target.[IS_CURRENT_COL]          = src.[IS_CURRENT_COL], 
            target.[HASH_COL]                = src.[HASH_COL], 
            target.[SK_COL]                  = src.[SK_COL], 
            target.[SQL_PROC_SCHEMA_NAME]    = src.[SQL_PROC_SCHEMA_NAME], 
            target.[SQL_PROCEDURE_NAME]      = src.[SQL_PROCEDURE_NAME], 
            target.[FIN_SQL_PROC_NAME]       = src.[FIN_SQL_PROC_NAME]
    WHEN NOT MATCHED THEN
        INSERT (
            [ELT_PIPELINE_DK],
            [CTRL_GROUP], 
            [CTRL_TASK_GROUP], 
            [CTRL_PIPELINE_GROUP], 
            [ELT_PIPELINE_ACTIVE_IND],
            [SRC_SYSTEM_ABBR], 
            [SRC_DB_NAME], 
            [SRC_SCHEMA_NAME], 
            [SRC_TABLE_NAME], 
            [STG_DB_NAME], 
            [STG_SCHEMA_NAME], 
            [STG_TABLE_NAME], 
            [FIN_DB_NAME], 
            [FIN_SCHEMA_NAME], 
            [FIN_TABLE_NAME], 
            [NATURAL_KEYS], 
            [VALID_FROM_COL], 
            [VALID_TO_COL], 
            [IS_CURRENT_COL], 
            [HASH_COL], 
            [SK_COL], 
            [SQL_PROC_SCHEMA_NAME], 
            [SQL_PROCEDURE_NAME], 
            [FIN_SQL_PROC_NAME]
        )
        VALUES (
            src.[ELT_PIPELINE_DK],
            src.[CTRL_GROUP], 
            src.[CTRL_TASK_GROUP], 
            src.[CTRL_PIPELINE_GROUP], 
            src.[ELT_PIPELINE_ACTIVE_IND],
            src.[SRC_SYSTEM_ABBR], 
            src.[SRC_DB_NAME], 
            src.[SRC_SCHEMA_NAME], 
            src.[SRC_TABLE_NAME], 
            src.[STG_DB_NAME], 
            src.[STG_SCHEMA_NAME], 
            src.[STG_TABLE_NAME], 
            src.[FIN_DB_NAME], 
            src.[FIN_SCHEMA_NAME], 
            src.[FIN_TABLE_NAME], 
            src.[NATURAL_KEYS], 
            src.[VALID_FROM_COL], 
            src.[VALID_TO_COL], 
            src.[IS_CURRENT_COL], 
            src.[HASH_COL], 
            src.[SK_COL], 
            src.[SQL_PROC_SCHEMA_NAME], 
            src.[SQL_PROCEDURE_NAME], 
            src.[FIN_SQL_PROC_NAME]
        );
END;
GO