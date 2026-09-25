-- =============================================================================
-- ADIB MPM PROPERTIES -- CRM xRM INTEGRATION
-- FILE : SIT_DDL.sql
-- DESC : DDL -- Sequences, Tables, Indexes (Package handled separately)
-- Author  : Tajudeen Jalaudin -- Senior Solution Architect, ADIB
-- Date    : 24 September 2026
-- =============================================================================
-- HOW TO USE:
--   Step 1 : Run this file on DEV in SQL*Plus  -->  @SIT_DDL.sql
--   Step 2 : Copy Script Output and save as SIT_DDL_output.sql
--   Step 3 : Run SIT_DDL_output.sql on SIT
-- =============================================================================

SET LONG          2000000
SET LONGCHUNKSIZE 32767
SET PAGESIZE      0
SET LINESIZE      32767
SET FEEDBACK      OFF
SET VERIFY        OFF
SET HEADING       OFF
SET ECHO          OFF
SET TRIMSPOOL     ON

-- =============================================================================
-- PART 1: SEQUENCES
-- =============================================================================
PROMPT -- =============================================
PROMPT -- PART 1: SEQUENCES
PROMPT -- =============================================

SELECT
    REPLACE(DBMS_METADATA.GET_DDL('SEQUENCE', SEQUENCE_NAME), '"APPS".', '')
    || CHR(10) || '/'
FROM USER_SEQUENCES
WHERE SEQUENCE_NAME LIKE 'CRM_MPM%'
ORDER BY SEQUENCE_NAME;

-- =============================================================================
-- PART 2: TABLES -- one by one so we can identify which table has error
-- =============================================================================
PROMPT -- =============================================
PROMPT -- PART 2: TABLES
PROMPT -- =============================================

-- Set transform params (no PL/SQL block -- just plain calls)
SELECT DBMS_METADATA.SET_TRANSFORM_PARAM(
    DBMS_METADATA.SESSION_TRANSFORM,'STORAGE',FALSE) FROM DUAL;
SELECT DBMS_METADATA.SET_TRANSFORM_PARAM(
    DBMS_METADATA.SESSION_TRANSFORM,'TABLESPACE',FALSE) FROM DUAL;
SELECT DBMS_METADATA.SET_TRANSFORM_PARAM(
    DBMS_METADATA.SESSION_TRANSFORM,'SEGMENT_ATTRIBUTES',FALSE) FROM DUAL;
SELECT DBMS_METADATA.SET_TRANSFORM_PARAM(
    DBMS_METADATA.SESSION_TRANSFORM,'SQLTERMINATOR',TRUE) FROM DUAL;

PROMPT -- TABLE: CRM_MPM_API_CREDENTIALS
SELECT REPLACE(DBMS_METADATA.GET_DDL('TABLE','CRM_MPM_API_CREDENTIALS'),'"APPS".','') || '/' FROM DUAL;

PROMPT -- TABLE: CRM_MPM_API_FIELD_MAPPING
SELECT REPLACE(DBMS_METADATA.GET_DDL('TABLE','CRM_MPM_API_FIELD_MAPPING'),'"APPS".','') || '/' FROM DUAL;

PROMPT -- TABLE: CRM_MPM_API_REGISTRY
SELECT REPLACE(DBMS_METADATA.GET_DDL('TABLE','CRM_MPM_API_REGISTRY'),'"APPS".','') || '/' FROM DUAL;

PROMPT -- TABLE: CRM_MPM_API_WATERMARK
SELECT REPLACE(DBMS_METADATA.GET_DDL('TABLE','CRM_MPM_API_WATERMARK'),'"APPS".','') || '/' FROM DUAL;

PROMPT -- TABLE: CRM_MPM_CALLBACK_AUDIT_LOG
SELECT REPLACE(DBMS_METADATA.GET_DDL('TABLE','CRM_MPM_CALLBACK_AUDIT_LOG'),'"APPS".','') || '/' FROM DUAL;

PROMPT -- TABLE: CRM_MPM_CONFIG_AUDIT
SELECT REPLACE(DBMS_METADATA.GET_DDL('TABLE','CRM_MPM_CONFIG_AUDIT'),'"APPS".','') || '/' FROM DUAL;

PROMPT -- TABLE: CRM_MPM_CONFIG_STORE
SELECT REPLACE(DBMS_METADATA.GET_DDL('TABLE','CRM_MPM_CONFIG_STORE'),'"APPS".','') || '/' FROM DUAL;

PROMPT -- TABLE: CRM_MPM_CRM_INTEGRATION_LOG
SELECT REPLACE(DBMS_METADATA.GET_DDL('TABLE','CRM_MPM_CRM_INTEGRATION_LOG'),'"APPS".','') || '/' FROM DUAL;

PROMPT -- TABLE: CRM_MPM_CRM_INTEGRATION_LOG_DETAIL
SELECT REPLACE(DBMS_METADATA.GET_DDL('TABLE','CRM_MPM_CRM_INTEGRATION_LOG_DETAIL'),'"APPS".','') || '/' FROM DUAL;

PROMPT -- TABLE: CRM_MPM_ENCRYPT_CONFIG
SELECT REPLACE(DBMS_METADATA.GET_DDL('TABLE','CRM_MPM_ENCRYPT_CONFIG'),'"APPS".','') || '/' FROM DUAL;

PROMPT -- TABLE: CRM_MPM_ERROR_CODE_MASTER
SELECT REPLACE(DBMS_METADATA.GET_DDL('TABLE','CRM_MPM_ERROR_CODE_MASTER'),'"APPS".','') || '/' FROM DUAL;

PROMPT -- TABLE: CRM_MPM_JOB_RUN_HISTORY
SELECT REPLACE(DBMS_METADATA.GET_DDL('TABLE','CRM_MPM_JOB_RUN_HISTORY'),'"APPS".','') || '/' FROM DUAL;

PROMPT -- TABLE: CRM_MPM_OUTBOUND_STAGING
SELECT REPLACE(DBMS_METADATA.GET_DDL('TABLE','CRM_MPM_OUTBOUND_STAGING'),'"APPS".','') || '/' FROM DUAL;

PROMPT -- TABLE: CRM_MPM_UNIQUE_ID_CONFIG
SELECT REPLACE(DBMS_METADATA.GET_DDL('TABLE','CRM_MPM_UNIQUE_ID_CONFIG'),'"APPS".','') || '/' FROM DUAL;

-- =============================================================================
-- PART 3: INDEXES
-- =============================================================================
PROMPT -- =============================================
PROMPT -- PART 3: INDEXES
PROMPT -- =============================================

SELECT
    REPLACE(DBMS_METADATA.GET_DDL('INDEX', INDEX_NAME), '"APPS".', '')
    || CHR(10) || '/'
FROM USER_INDEXES
WHERE TABLE_NAME LIKE 'CRM_MPM%'
AND   INDEX_TYPE != 'LOB'
AND   INDEX_NAME NOT LIKE 'SYS_%'
ORDER BY TABLE_NAME, INDEX_NAME;

PROMPT -- END OF DDL SCRIPT
