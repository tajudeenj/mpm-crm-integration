-- =============================================================================
-- ADIB MPM PROPERTIES -- CRM xRM INTEGRATION
-- GENERATE COMPLETE SIT SCRIPT FROM DEV DATABASE
-- Author  : Tajudeen Jalaudin -- Senior Solution Architect, ADIB
-- Date    : 24 September 2026
-- Run on  : DEV database as schema owner
-- Output  : Copy the spool file and run on SIT
-- =============================================================================
-- HOW TO USE:
--   1. Open SQL Developer on DEV database
--   2. Run this entire script
--   3. Copy the output (or spool to file)
--   4. Save as SIT_FROM_DEV.sql
--   5. Run SIT_FROM_DEV.sql on SIT database
-- =============================================================================

SET LONG          2000000
SET LONGCHUNKSIZE 2000000
SET PAGESIZE      0
SET LINESIZE      32767
SET FEEDBACK      OFF
SET VERIFY        OFF
SET HEADING       OFF
SET ECHO          OFF
SET TRIMSPOOL     ON
SET SERVEROUTPUT  ON SIZE UNLIMITED

-- Spool to file (update path as needed)
-- SPOOL /tmp/SIT_FROM_DEV.sql

PROMPT -- =================================================================
PROMPT -- ADIB MPM CRM INTEGRATION -- GENERATED FROM DEV
PROMPT -- Generated : SYS_DATE_HERE
PROMPT -- Source    : DEV Database
PROMPT -- Target    : SIT Database
PROMPT -- =================================================================
PROMPT SET DEFINE OFF
PROMPT SET FEEDBACK OFF
PROMPT WHENEVER SQLERROR CONTINUE
PROMPT

-- =============================================================================
-- PART 1: DDL -- SEQUENCES
-- =============================================================================
PROMPT PROMPT --- SEQUENCES ---
PROMPT

BEGIN
    DBMS_METADATA.SET_TRANSFORM_PARAM(
        DBMS_METADATA.SESSION_TRANSFORM,'STORAGE',FALSE);
    DBMS_METADATA.SET_TRANSFORM_PARAM(
        DBMS_METADATA.SESSION_TRANSFORM,'TABLESPACE',FALSE);
    DBMS_METADATA.SET_TRANSFORM_PARAM(
        DBMS_METADATA.SESSION_TRANSFORM,'SEGMENT_ATTRIBUTES',FALSE);
    DBMS_METADATA.SET_TRANSFORM_PARAM(
        DBMS_METADATA.SESSION_TRANSFORM,'SQLTERMINATOR',TRUE);
END;
/

SELECT
    'BEGIN EXECUTE IMMEDIATE '''
    || REPLACE(
        REPLACE(DBMS_METADATA.GET_DDL('SEQUENCE', SEQUENCE_NAME), CHR(10), ' '),
        '''', ''''''
       )
    || '''; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -955 THEN RAISE; END IF; END;'
    || CHR(10) || '/'
FROM USER_SEQUENCES
WHERE SEQUENCE_NAME LIKE 'CRM_MPM%'
ORDER BY SEQUENCE_NAME;


-- =============================================================================
-- PART 2: DDL -- TABLES (exact structure from DEV)
-- =============================================================================
PROMPT PROMPT --- TABLES ---
PROMPT

SELECT
    'BEGIN EXECUTE IMMEDIATE '''
    || REPLACE(
        REPLACE(DBMS_METADATA.GET_DDL('TABLE', TABLE_NAME), CHR(10), ' '),
        '''', ''''''
       )
    || '''; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -955 THEN RAISE; END IF; END;'
    || CHR(10) || '/'
FROM USER_TABLES
WHERE TABLE_NAME LIKE 'CRM_MPM%'
ORDER BY TABLE_NAME;


-- =============================================================================
-- PART 3: DDL -- INDEXES
-- =============================================================================
PROMPT PROMPT --- INDEXES ---
PROMPT

SELECT
    'BEGIN EXECUTE IMMEDIATE '''
    || REPLACE(
        REPLACE(DBMS_METADATA.GET_DDL('INDEX', INDEX_NAME), CHR(10), ' '),
        '''', ''''''
       )
    || '''; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -955 THEN RAISE; END IF; END;'
    || CHR(10) || '/'
FROM USER_INDEXES
WHERE TABLE_NAME LIKE 'CRM_MPM%'
AND   INDEX_TYPE  != 'LOB'
AND   INDEX_NAME  NOT LIKE 'SYS_%'
ORDER BY TABLE_NAME, INDEX_NAME;


-- =============================================================================
-- PART 4: DDL -- PACKAGE SPEC
-- =============================================================================
PROMPT PROMPT --- PACKAGE SPEC ---
PROMPT

SELECT DBMS_METADATA.GET_DDL('PACKAGE_SPEC','PKG_CRM_INTEGRATION')
    || CHR(10) || '/'
FROM DUAL;


-- =============================================================================
-- PART 5: DDL -- PACKAGE BODY
-- =============================================================================
PROMPT PROMPT --- PACKAGE BODY ---
PROMPT

SELECT DBMS_METADATA.GET_DDL('PACKAGE_BODY','PKG_CRM_INTEGRATION')
    || CHR(10) || '/'
FROM DUAL;


-- =============================================================================
-- PART 6: DATA -- ALL CRM_MPM TABLES
-- Generated as MERGE statements -- safe to re-run
-- =============================================================================
PROMPT PROMPT --- DATA: CRM_MPM_ENCRYPT_CONFIG ---
PROMPT

SELECT
    'MERGE INTO CRM_MPM_ENCRYPT_CONFIG T '
    || 'USING (SELECT ' || CONFIG_ID || ' AS ID FROM DUAL) S '
    || 'ON (T.CONFIG_ID=S.ID) '
    || 'WHEN NOT MATCHED THEN INSERT '
    || '(CONFIG_ID,KEY_NAME,ENCRYPT_KEY,IS_ACTIVE) VALUES ('
    || CONFIG_ID || ','
    || '''' || KEY_NAME || ''','
    || 'HEXTORAW(''' || RAWTOHEX(ENCRYPT_KEY) || '''),'
    || '''' || IS_ACTIVE || ''');'
FROM CRM_MPM_ENCRYPT_CONFIG;

PROMPT COMMIT;
PROMPT

-- =============================================================================
PROMPT PROMPT --- DATA: CRM_MPM_UNIQUE_ID_CONFIG ---
PROMPT

SELECT
    'MERGE INTO CRM_MPM_UNIQUE_ID_CONFIG T '
    || 'USING (SELECT 1 AS ID FROM DUAL) S ON (T.CONFIG_ID=S.ID) '
    || 'WHEN NOT MATCHED THEN INSERT '
    || '(CONFIG_ID,CHANNEL_ID,TIMESTAMP_FORMAT,SEQUENCE_DIGITS,IS_ACTIVE) VALUES ('
    || CONFIG_ID || ','
    || '''' || CHANNEL_ID || ''','
    || '''' || TIMESTAMP_FORMAT || ''','
    || SEQUENCE_DIGITS || ','
    || '''' || IS_ACTIVE || ''');'
FROM CRM_MPM_UNIQUE_ID_CONFIG;

PROMPT COMMIT;
PROMPT

-- =============================================================================
PROMPT PROMPT --- DATA: CRM_MPM_ERROR_CODE_MASTER ---
PROMPT

SELECT
    'MERGE INTO CRM_MPM_ERROR_CODE_MASTER T '
    || 'USING (SELECT ''' || ERROR_CODE || ''' AS C FROM DUAL) S '
    || 'ON (T.ERROR_CODE=S.C) '
    || 'WHEN NOT MATCHED THEN INSERT '
    || '(ERROR_CODE,ERROR_DESCRIPTION,IS_RETRYABLE,IS_ACTIVE) VALUES ('
    || '''' || ERROR_CODE || ''','
    || '''' || REPLACE(ERROR_DESCRIPTION,'''','''''') || ''','
    || '''' || NVL(IS_RETRYABLE,'N') || ''','
    || '''' || NVL(IS_ACTIVE,'Y') || ''');'
FROM CRM_MPM_ERROR_CODE_MASTER
ORDER BY ERROR_CODE;

PROMPT COMMIT;
PROMPT

-- =============================================================================
PROMPT PROMPT --- DATA: CRM_MPM_API_CREDENTIALS ---
PROMPT

SELECT
    'MERGE INTO CRM_MPM_API_CREDENTIALS T '
    || 'USING (SELECT ''' || CRED_CODE || ''' AS C FROM DUAL) S '
    || 'ON (T.CRED_CODE=S.C) '
    || 'WHEN NOT MATCHED THEN INSERT '
    || '(CRED_CODE,TOKEN_URL,CLIENT_ID,CLIENT_SECRET_REF,'
    || 'GRANT_TYPE,SCOPE,WALLET_PATH,WALLET_PASSWORD,'
    || 'CLIENT_SECRET_ENCRYPTED,ENCRYPT_KEY_REF,IS_ACTIVE) VALUES ('
    || '''' || CRED_CODE         || ''','
    || '''' || TOKEN_URL         || ''','
    || '''' || CLIENT_ID         || ''','
    || '''' || NVL(CLIENT_SECRET_REF,'') || ''','
    || '''' || NVL(GRANT_TYPE,'client_credentials') || ''','
    || '''' || NVL(SCOPE,'')     || ''','
    || '''' || NVL(WALLET_PATH,'') || ''','
    || '''' || NVL(WALLET_PASSWORD,'') || ''','
    || CASE WHEN CLIENT_SECRET_ENCRYPTED IS NOT NULL
            THEN 'HEXTORAW(''' || RAWTOHEX(CLIENT_SECRET_ENCRYPTED) || ''')'
            ELSE 'NULL' END || ','
    || '''' || NVL(ENCRYPT_KEY_REF,'') || ''','
    || '''' || NVL(IS_ACTIVE,'Y') || ''') '
    || 'WHEN MATCHED THEN UPDATE SET '
    || 'TOKEN_URL=''' || TOKEN_URL || ''','
    || 'UPDATED_DATE=SYSTIMESTAMP;'
FROM CRM_MPM_API_CREDENTIALS;

PROMPT COMMIT;
PROMPT

-- =============================================================================
PROMPT PROMPT --- DATA: CRM_MPM_API_REGISTRY ---
PROMPT

SELECT
    'MERGE INTO CRM_MPM_API_REGISTRY T '
    || 'USING (SELECT ''' || SERVICE_NAME || ''' AS S FROM DUAL) X '
    || 'ON (T.SERVICE_NAME=X.S) '
    || 'WHEN NOT MATCHED THEN INSERT ('
    || 'SERVICE_NAME,ENTITY_NAME,OPERATION_TYPE,SOURCE_TYPE,'
    || 'SOURCE_VIEW,SOURCE_PROC,SOURCE_FILTER_COL,SOURCE_KEY_COL,'
    || 'JSON_MAPPING_NAME,RECORD_TYPE_HDR,EVENT_CODE_HDR,'
    || 'APIC_ENDPOINT_URL,HTTP_METHOD,APIC_API_VERSION,'
    || 'CALLBACK_TARGET_TABLE,CALLBACK_KEY_COL,CALLBACK_STATUS_COL,'
    || 'CALLBACK_REF_COL,POST_CALLBACK_PROC,'
    || 'CRED_CODE,EXECUTION_ORDER,BATCH_SIZE,'
    || 'MAX_RETRY_COUNT,RETRY_INTERVAL_MINUTES,TIMEOUT_MINUTES,IS_ACTIVE) '
    || 'VALUES ('
    || '''' || SERVICE_NAME                         || ''','
    || '''' || NVL(ENTITY_NAME,'')                  || ''','
    || '''' || NVL(OPERATION_TYPE,'')               || ''','
    || '''' || NVL(SOURCE_TYPE,'VIEW')               || ''','
    || '''' || NVL(SOURCE_VIEW,'')                   || ''','
    || '''' || NVL(SOURCE_PROC,'')                   || ''','
    || '''' || NVL(SOURCE_FILTER_COL,'')             || ''','
    || '''' || NVL(SOURCE_KEY_COL,'')                || ''','
    || '''' || NVL(JSON_MAPPING_NAME,'')             || ''','
    || '''' || NVL(RECORD_TYPE_HDR,'')               || ''','
    || '''' || NVL(EVENT_CODE_HDR,'')                || ''','
    || '''' || NVL(APIC_ENDPOINT_URL,'')             || ''','
    || '''' || NVL(HTTP_METHOD,'POST')               || ''','
    || '''' || NVL(APIC_API_VERSION,'1')             || ''','
    || '''' || NVL(CALLBACK_TARGET_TABLE,'')         || ''','
    || '''' || NVL(CALLBACK_KEY_COL,'')              || ''','
    || '''' || NVL(CALLBACK_STATUS_COL,'')           || ''','
    || '''' || NVL(CALLBACK_REF_COL,'')              || ''','
    || '''' || NVL(POST_CALLBACK_PROC,'')            || ''','
    || '''' || NVL(CRED_CODE,'')                     || ''','
    || NVL(EXECUTION_ORDER,10)                       || ','
    || NVL(BATCH_SIZE,100)                           || ','
    || NVL(MAX_RETRY_COUNT,3)                        || ','
    || NVL(RETRY_INTERVAL_MINUTES,30)               || ','
    || NVL(TIMEOUT_MINUTES,60)                      || ','
    || '''' || NVL(IS_ACTIVE,'Y')                    || ''') '
    || 'WHEN MATCHED THEN UPDATE SET '
    || 'UPDATED_DATE=SYSTIMESTAMP;'
FROM CRM_MPM_API_REGISTRY
ORDER BY EXECUTION_ORDER;

PROMPT COMMIT;
PROMPT

-- =============================================================================
PROMPT PROMPT --- DATA: CRM_MPM_API_FIELD_MAPPING ---
PROMPT

SELECT
    'MERGE INTO CRM_MPM_API_FIELD_MAPPING T '
    || 'USING (SELECT ''' || JSON_MAPPING_NAME || ''' AS M,'
    || '''' || SOURCE_COLUMN || ''' AS C FROM DUAL) X '
    || 'ON (T.JSON_MAPPING_NAME=X.M AND T.SOURCE_COLUMN=X.C) '
    || 'WHEN NOT MATCHED THEN INSERT ('
    || 'MAPPING_ID,JSON_MAPPING_NAME,SOURCE_COLUMN,JSON_PATH,'
    || 'DATA_TYPE,DATE_FORMAT,IS_MANDATORY,DISPLAY_ORDER,IS_ACTIVE) VALUES ('
    || 'CRM_MPM_MAPPING_SEQ.NEXTVAL,'
    || '''' || JSON_MAPPING_NAME                    || ''','
    || '''' || SOURCE_COLUMN                        || ''','
    || '''' || NVL(JSON_PATH,'')                    || ''','
    || '''' || NVL(DATA_TYPE,'VARCHAR2')             || ''','
    || '''' || NVL(DATE_FORMAT,'')                   || ''','
    || '''' || NVL(IS_MANDATORY,'N')                 || ''','
    || NVL(DISPLAY_ORDER,10)                        || ','
    || '''' || NVL(IS_ACTIVE,'Y')                    || ''');'
FROM CRM_MPM_API_FIELD_MAPPING
WHERE IS_ACTIVE = 'Y'
ORDER BY JSON_MAPPING_NAME, DISPLAY_ORDER;

PROMPT COMMIT;
PROMPT

-- =============================================================================
PROMPT PROMPT --- DATA: CRM_MPM_API_WATERMARK ---
PROMPT

SELECT
    'MERGE INTO CRM_MPM_API_WATERMARK T '
    || 'USING (SELECT ' || W.REGISTRY_ID || ' AS R FROM DUAL) X '
    || 'ON (T.REGISTRY_ID=X.R) '
    || 'WHEN NOT MATCHED THEN INSERT '
    || '(REGISTRY_ID,LAST_PROCESSED_TS,LAST_RUN_STATUS,LAST_RUN_RECORDS) VALUES ('
    || W.REGISTRY_ID || ','
    || 'TO_TIMESTAMP(''' || TO_CHAR(W.LAST_PROCESSED_TS,
                                'DD-MON-YYYY HH24:MI:SS') || ''','
    || '''DD-MON-YYYY HH24:MI:SS''),'
    || '''' || NVL(W.LAST_RUN_STATUS,'INIT') || ''','
    || NVL(W.LAST_RUN_RECORDS,0) || ');'
FROM CRM_MPM_API_WATERMARK W
ORDER BY W.REGISTRY_ID;

PROMPT COMMIT;
PROMPT

-- =============================================================================
PROMPT PROMPT --- SCHEDULER JOBS ---
PROMPT

-- Drop and recreate all CRM_MPM scheduler jobs
PROMPT BEGIN
PROMPT   FOR j IN (SELECT JOB_NAME FROM USER_SCHEDULER_JOBS WHERE JOB_NAME LIKE 'CRM_MPM%') LOOP
PROMPT     BEGIN DBMS_SCHEDULER.STOP_JOB(j.JOB_NAME,TRUE); EXCEPTION WHEN OTHERS THEN NULL; END;
PROMPT     BEGIN DBMS_SCHEDULER.DROP_JOB(j.JOB_NAME,TRUE); EXCEPTION WHEN OTHERS THEN NULL; END;
PROMPT   END LOOP;
PROMPT END;
PROMPT /

SELECT
    'BEGIN DBMS_SCHEDULER.CREATE_JOB('
    || 'job_name=>''' || JOB_NAME || ''','
    || 'job_type=>''' || JOB_TYPE || ''','
    || 'job_action=>''' || JOB_ACTION || ''','
    || 'repeat_interval=>''' || REPEAT_INTERVAL || ''','
    || 'enabled=>' || CASE WHEN ENABLED='TRUE' THEN 'TRUE' ELSE 'FALSE' END || ','
    || 'comments=>''' || NVL(COMMENTS,'') || '''); END;'
    || CHR(10) || '/'
FROM USER_SCHEDULER_JOBS
WHERE JOB_NAME LIKE 'CRM_MPM%'
ORDER BY JOB_NAME;

PROMPT COMMIT;
PROMPT

-- =============================================================================
PROMPT PROMPT --- VERIFICATION ---
PROMPT
PROMPT SELECT TABLE_NAME, NUM_ROWS FROM USER_TABLES WHERE TABLE_NAME LIKE 'CRM_MPM%' ORDER BY TABLE_NAME;
PROMPT SELECT SEQUENCE_NAME FROM USER_SEQUENCES WHERE SEQUENCE_NAME LIKE 'CRM_MPM%' ORDER BY 1;
PROMPT SELECT INDEX_NAME, TABLE_NAME FROM USER_INDEXES WHERE TABLE_NAME LIKE 'CRM_MPM%' ORDER BY 1;
PROMPT SELECT OBJECT_NAME, OBJECT_TYPE, STATUS FROM USER_OBJECTS WHERE OBJECT_NAME='PKG_CRM_INTEGRATION';
PROMPT SELECT JOB_NAME, ENABLED, STATE FROM USER_SCHEDULER_JOBS WHERE JOB_NAME LIKE 'CRM_MPM%';
PROMPT

-- SPOOL OFF

PROMPT -- =================================================================
PROMPT -- END OF GENERATED SCRIPT
PROMPT -- =================================================================
