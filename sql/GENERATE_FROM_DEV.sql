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

-- =============================================================================
-- HOW TO USE:
-- Step 1: Run this script on DEV using F5 in SQL Developer
-- Step 2: Click Script Output tab at bottom
-- Step 3: Right-click -> Save As -> SIT_FROM_DEV.sql
-- Step 4: Run SIT_FROM_DEV.sql on SIT database
--
-- NOTE: "APPS". schema prefix is removed automatically in the script
--       No manual find/replace needed
-- =============================================================================

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

DECLARE
    v_ddl CLOB;
BEGIN
    FOR r IN (
        SELECT SEQUENCE_NAME FROM USER_SEQUENCES
        WHERE  SEQUENCE_NAME LIKE 'CRM_MPM%'
        ORDER  BY SEQUENCE_NAME
    ) LOOP
        v_ddl := DBMS_METADATA.GET_DDL('SEQUENCE', r.SEQUENCE_NAME);
        -- Remove schema prefix
        v_ddl := REPLACE(v_ddl, '"APPS".', '');
        DBMS_OUTPUT.PUT_LINE(v_ddl);
        DBMS_OUTPUT.PUT_LINE('/');
    END LOOP;
END;
/


-- =============================================================================
-- PART 2: DDL -- TABLES (exact structure from DEV)
-- =============================================================================
PROMPT PROMPT --- TABLES ---
PROMPT

DECLARE
    v_ddl CLOB;
BEGIN
    -- Set transform params to strip storage/tablespace clauses
    DBMS_METADATA.SET_TRANSFORM_PARAM(
        DBMS_METADATA.SESSION_TRANSFORM,'STORAGE',FALSE);
    DBMS_METADATA.SET_TRANSFORM_PARAM(
        DBMS_METADATA.SESSION_TRANSFORM,'TABLESPACE',FALSE);
    DBMS_METADATA.SET_TRANSFORM_PARAM(
        DBMS_METADATA.SESSION_TRANSFORM,'SEGMENT_ATTRIBUTES',FALSE);
    DBMS_METADATA.SET_TRANSFORM_PARAM(
        DBMS_METADATA.SESSION_TRANSFORM,'SQLTERMINATOR',TRUE);

    FOR r IN (
        SELECT TABLE_NAME FROM USER_TABLES
        WHERE  TABLE_NAME LIKE 'CRM_MPM%'
        ORDER  BY TABLE_NAME
    ) LOOP
        v_ddl := DBMS_METADATA.GET_DDL('TABLE', r.TABLE_NAME);
        -- Remove schema prefix
        v_ddl := REPLACE(v_ddl, '"APPS".', '');
        DBMS_OUTPUT.PUT_LINE(v_ddl);
        DBMS_OUTPUT.PUT_LINE('/');
    END LOOP;
END;
/


-- =============================================================================
-- PART 3: DDL -- INDEXES
-- =============================================================================
PROMPT PROMPT --- INDEXES ---
PROMPT

DECLARE
    v_ddl CLOB;
BEGIN
    FOR r IN (
        SELECT INDEX_NAME FROM USER_INDEXES
        WHERE  TABLE_NAME LIKE 'CRM_MPM%'
        AND    INDEX_TYPE != 'LOB'
        AND    INDEX_NAME NOT LIKE 'SYS_%'
        ORDER  BY TABLE_NAME, INDEX_NAME
    ) LOOP
        BEGIN
            v_ddl := DBMS_METADATA.GET_DDL('INDEX', r.INDEX_NAME);
            -- Remove schema prefix
            v_ddl := REPLACE(v_ddl, '"APPS".', '');
            DBMS_OUTPUT.PUT_LINE(v_ddl);
            DBMS_OUTPUT.PUT_LINE('/');
        EXCEPTION
            WHEN OTHERS THEN NULL; -- skip system-generated indexes
        END;
    END LOOP;
END;
/


-- =============================================================================
-- PART 4: DDL -- PACKAGE SPEC
-- =============================================================================
PROMPT PROMPT --- PACKAGE SPEC ---
PROMPT

DECLARE
    v_ddl CLOB;
BEGIN
    v_ddl := DBMS_METADATA.GET_DDL('PACKAGE_SPEC','PKG_CRM_INTEGRATION');
    v_ddl := REPLACE(v_ddl, '"APPS".', '');
    DBMS_OUTPUT.PUT_LINE(v_ddl);
    DBMS_OUTPUT.PUT_LINE('/');
END;
/


-- =============================================================================
-- PART 5: DDL -- PACKAGE BODY
-- =============================================================================
PROMPT PROMPT --- PACKAGE BODY ---
PROMPT

DECLARE
    v_ddl CLOB;
BEGIN
    v_ddl := DBMS_METADATA.GET_DDL('PACKAGE_BODY','PKG_CRM_INTEGRATION');
    v_ddl := REPLACE(v_ddl, '"APPS".', '');
    DBMS_OUTPUT.PUT_LINE(v_ddl);
    DBMS_OUTPUT.PUT_LINE('/');
END;
/


-- =============================================================================
-- =============================================================================
-- PART 6: DATA -- ALL CRM_MPM TABLES
-- Based on EXACT columns from USER_TAB_COLUMNS on DEV database
-- Pure INSERT statements -- tables deleted first for clean load
-- =============================================================================

PROMPT PROMPT --- DELETE ALL TABLES FOR CLEAN LOAD ---
PROMPT -- Delete in FK-safe order
PROMPT DELETE FROM CRM_MPM_CRM_INTEGRATION_LOG_DETAIL;
PROMPT DELETE FROM CRM_MPM_CRM_INTEGRATION_LOG;
PROMPT DELETE FROM CRM_MPM_API_WATERMARK;
PROMPT DELETE FROM CRM_MPM_API_FIELD_MAPPING;
PROMPT DELETE FROM CRM_MPM_OUTBOUND_STAGING;
PROMPT DELETE FROM CRM_MPM_JOB_RUN_HISTORY;
PROMPT DELETE FROM CRM_MPM_CALLBACK_AUDIT_LOG;
PROMPT DELETE FROM CRM_MPM_API_REGISTRY;
PROMPT DELETE FROM CRM_MPM_API_CREDENTIALS;
PROMPT DELETE FROM CRM_MPM_ERROR_CODE_MASTER;
PROMPT DELETE FROM CRM_MPM_CONFIG_STORE;
PROMPT DELETE FROM CRM_MPM_CONFIG_AUDIT;
PROMPT DELETE FROM CRM_MPM_UNIQUE_ID_CONFIG;
PROMPT DELETE FROM CRM_MPM_ENCRYPT_CONFIG;
PROMPT COMMIT;
PROMPT

-- =============================================================================
-- TABLE: CRM_MPM_ENCRYPT_CONFIG
-- Columns: CONFIG_ID(NUMBER), KEY_NAME(VARCHAR2 50), ENCRYPT_KEY(RAW 32),
--          IS_ACTIVE(CHAR 1), CREATED_DATE(DATE)
-- RAW(32) handled with HEXTORAW
-- =============================================================================
PROMPT PROMPT --- DATA: CRM_MPM_ENCRYPT_CONFIG ---
PROMPT

SELECT
    'INSERT INTO CRM_MPM_ENCRYPT_CONFIG'
    ||' (CONFIG_ID,KEY_NAME,ENCRYPT_KEY,IS_ACTIVE,CREATED_DATE) VALUES ('
    || CONFIG_ID                                                    ||','
    ||''''|| KEY_NAME                                               ||''','
    ||'HEXTORAW('''|| LOWER(RAWTOHEX(ENCRYPT_KEY))                 ||'''),'
    ||''''|| NVL(IS_ACTIVE,'Y')                                     ||''','
    ||'SYSDATE);'
FROM CRM_MPM_ENCRYPT_CONFIG;

PROMPT COMMIT;
PROMPT

-- =============================================================================
-- TABLE: CRM_MPM_UNIQUE_ID_CONFIG
-- Columns: CONFIG_ID(NUMBER), CHANNEL_ID(VARCHAR2 10),
--          TIMESTAMP_FORMAT(VARCHAR2 50), SEQUENCE_DIGITS(NUMBER),
--          IS_ACTIVE(VARCHAR2 1), UPDATED_DATE(TIMESTAMP)
-- =============================================================================
PROMPT PROMPT --- DATA: CRM_MPM_UNIQUE_ID_CONFIG ---
PROMPT

SELECT
    'INSERT INTO CRM_MPM_UNIQUE_ID_CONFIG'
    ||' (CONFIG_ID,CHANNEL_ID,TIMESTAMP_FORMAT,SEQUENCE_DIGITS,IS_ACTIVE,UPDATED_DATE)'
    ||' VALUES ('
    || CONFIG_ID                             ||','
    ||''''|| CHANNEL_ID                      ||''','
    ||''''|| TIMESTAMP_FORMAT                ||''','
    || SEQUENCE_DIGITS                       ||','
    ||''''|| NVL(IS_ACTIVE,'Y')              ||''','
    ||'SYSTIMESTAMP);'
FROM CRM_MPM_UNIQUE_ID_CONFIG;

PROMPT COMMIT;
PROMPT

-- =============================================================================
-- TABLE: CRM_MPM_ERROR_CODE_MASTER
-- Columns: ERROR_CODE(VARCHAR2 30), ERROR_CATEGORY(VARCHAR2 30),
--          ERROR_DESCRIPTION(VARCHAR2 400), IS_RETRYABLE(CHAR 1)
-- NOTE: No MATCHED_FRAGMENT, IS_ACTIVE, CREATED_DATE columns in actual table
-- =============================================================================
PROMPT PROMPT --- DATA: CRM_MPM_ERROR_CODE_MASTER ---
PROMPT

SELECT
    'INSERT INTO CRM_MPM_ERROR_CODE_MASTER'
    ||' (ERROR_CODE,ERROR_CATEGORY,ERROR_DESCRIPTION,IS_RETRYABLE) VALUES ('
    ||''''|| REPLACE(ERROR_CODE,'''','''''')                          ||''','
    ||''''|| REPLACE(NVL(ERROR_CATEGORY,'GENERAL'),'''','''''')       ||''','
    ||''''|| REPLACE(NVL(ERROR_DESCRIPTION,''),'''','''''')           ||''','
    ||''''|| NVL(IS_RETRYABLE,'N')                                    ||''');'
FROM CRM_MPM_ERROR_CODE_MASTER
ORDER BY ERROR_CODE;

PROMPT COMMIT;
PROMPT

-- =============================================================================
-- TABLE: CRM_MPM_API_CREDENTIALS (18 columns)
-- BLOB columns: CLIENT_SECRET_ENCRYPTED, WALLET_PASSWORD_ENC
-- Handled via PL/SQL block -- cannot use BLOB in SQL string concat
-- =============================================================================
PROMPT PROMPT --- DATA: CRM_MPM_API_CREDENTIALS ---
PROMPT

DECLARE
    v_cs_hex  VARCHAR2(32767);
    v_wp_hex  VARCHAR2(32767);
BEGIN
    FOR r IN (
        SELECT CRED_ID, CRED_CODE, TOKEN_URL, CLIENT_ID,
               CLIENT_SECRET_REF, SCOPE, GRANT_TYPE,
               TOKEN_CACHE_VALUE, TOKEN_EXPIRY,
               IS_ACTIVE, WALLET_PATH, WALLET_PASSWORD,
               CLIENT_SECRET_ENCRYPTED, ENCRYPT_KEY_REF,
               WALLET_PASSWORD_ENC, WALLET_PWD_KEY_REF
        FROM   CRM_MPM_API_CREDENTIALS
    ) LOOP
        -- Read BLOB columns into PL/SQL VARCHAR2 via DBMS_LOB.SUBSTR
        IF r.CLIENT_SECRET_ENCRYPTED IS NOT NULL
           AND DBMS_LOB.GETLENGTH(r.CLIENT_SECRET_ENCRYPTED) > 0 THEN
            v_cs_hex := LOWER(RAWTOHEX(
                DBMS_LOB.SUBSTR(r.CLIENT_SECRET_ENCRYPTED,
                    DBMS_LOB.GETLENGTH(r.CLIENT_SECRET_ENCRYPTED), 1)));
        ELSE
            v_cs_hex := NULL;
        END IF;

        IF r.WALLET_PASSWORD_ENC IS NOT NULL
           AND DBMS_LOB.GETLENGTH(r.WALLET_PASSWORD_ENC) > 0 THEN
            v_wp_hex := LOWER(RAWTOHEX(
                DBMS_LOB.SUBSTR(r.WALLET_PASSWORD_ENC,
                    DBMS_LOB.GETLENGTH(r.WALLET_PASSWORD_ENC), 1)));
        ELSE
            v_wp_hex := NULL;
        END IF;

        -- CRED_ID excluded -- GENERATED ALWAYS AS IDENTITY
        INSERT INTO CRM_MPM_API_CREDENTIALS (
            CRED_CODE, TOKEN_URL, CLIENT_ID,
            CLIENT_SECRET_REF, SCOPE, GRANT_TYPE,
            TOKEN_CACHE_VALUE, TOKEN_EXPIRY,
            IS_ACTIVE, CREATED_DATE, UPDATED_DATE,
            WALLET_PATH, WALLET_PASSWORD,
            CLIENT_SECRET_ENCRYPTED, ENCRYPT_KEY_REF,
            WALLET_PASSWORD_ENC, WALLET_PWD_KEY_REF)
        VALUES (
            r.CRED_CODE, r.TOKEN_URL, r.CLIENT_ID,
            r.CLIENT_SECRET_REF, r.SCOPE, r.GRANT_TYPE,
            r.TOKEN_CACHE_VALUE, r.TOKEN_EXPIRY,
            r.IS_ACTIVE, SYSTIMESTAMP, SYSTIMESTAMP,
            r.WALLET_PATH, r.WALLET_PASSWORD,
            CASE WHEN v_cs_hex IS NOT NULL
                 THEN TO_BLOB(HEXTORAW(v_cs_hex)) ELSE NULL END,
            r.ENCRYPT_KEY_REF,
            CASE WHEN v_wp_hex IS NOT NULL
                 THEN TO_BLOB(HEXTORAW(v_wp_hex)) ELSE NULL END,
            r.WALLET_PWD_KEY_REF);

        DBMS_OUTPUT.PUT_LINE('Inserted: ' || r.CRED_CODE);
    END LOOP;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Done: CRM_MPM_API_CREDENTIALS');
END;
/

-- =============================================================================
-- TABLE: CRM_MPM_API_REGISTRY (29 columns)
-- Columns: REGISTRY_ID, ENTITY_NAME, OPERATION_TYPE, SOURCE_TYPE,
--   SOURCE_VIEW, SOURCE_PROC, SOURCE_FILTER_COL, SOURCE_KEY_COL,
--   JSON_MAPPING_NAME, APIC_ENDPOINT_URL, HTTP_METHOD, CRED_CODE,
--   SERVICE_NAME, CALLBACK_TARGET_TABLE, CALLBACK_KEY_COL,
--   CALLBACK_STATUS_COL, CALLBACK_REF_COL, POST_CALLBACK_PROC,
--   TIMEOUT_MINUTES, MAX_RETRY_COUNT, RETRY_INTERVAL_MINUTES,
--   IS_ACTIVE(CHAR), CREATED_DATE, UPDATED_DATE,
--   APIC_API_VERSION, RECORD_TYPE_HDR, EVENT_CODE_HDR,
--   BATCH_SIZE, EXECUTION_ORDER
-- NOTE: No MANUAL_RETRY column in registry
-- =============================================================================
PROMPT PROMPT --- DATA: CRM_MPM_API_REGISTRY ---
PROMPT

SELECT
    'INSERT INTO CRM_MPM_API_REGISTRY'
    ||' (REGISTRY_ID,ENTITY_NAME,OPERATION_TYPE,SOURCE_TYPE,'
    ||'SOURCE_VIEW,SOURCE_PROC,SOURCE_FILTER_COL,SOURCE_KEY_COL,'
    ||'JSON_MAPPING_NAME,APIC_ENDPOINT_URL,HTTP_METHOD,CRED_CODE,'
    ||'SERVICE_NAME,CALLBACK_TARGET_TABLE,CALLBACK_KEY_COL,'
    ||'CALLBACK_STATUS_COL,CALLBACK_REF_COL,POST_CALLBACK_PROC,'
    ||'TIMEOUT_MINUTES,MAX_RETRY_COUNT,RETRY_INTERVAL_MINUTES,'
    ||'IS_ACTIVE,CREATED_DATE,UPDATED_DATE,'
    ||'APIC_API_VERSION,RECORD_TYPE_HDR,EVENT_CODE_HDR,'
    ||'BATCH_SIZE,EXECUTION_ORDER) VALUES ('
    || REGISTRY_ID                                                          ||','
    ||''''|| REPLACE(NVL(ENTITY_NAME,''),'''','''''')                       ||''','
    ||''''|| NVL(OPERATION_TYPE,'CREATE')                                   ||''','
    ||''''|| NVL(SOURCE_TYPE,'VIEW')                                        ||''','
    ||''''|| REPLACE(NVL(SOURCE_VIEW,''),'''','''''')                       ||''','
    ||''''|| REPLACE(NVL(SOURCE_PROC,''),'''','''''')                       ||''','
    ||''''|| REPLACE(NVL(SOURCE_FILTER_COL,''),'''','''''')                 ||''','
    ||''''|| REPLACE(NVL(SOURCE_KEY_COL,''),'''','''''')                    ||''','
    ||''''|| REPLACE(NVL(JSON_MAPPING_NAME,''),'''','''''')                 ||''','
    ||''''|| REPLACE(NVL(APIC_ENDPOINT_URL,''),'''','''''')                 ||''','
    ||''''|| NVL(HTTP_METHOD,'POST')                                        ||''','
    ||''''|| NVL(CRED_CODE,'')                                              ||''','
    ||''''|| REPLACE(NVL(SERVICE_NAME,''),'''','''''')                      ||''','
    ||''''|| REPLACE(NVL(CALLBACK_TARGET_TABLE,''),'''','''''')             ||''','
    ||''''|| REPLACE(NVL(CALLBACK_KEY_COL,''),'''','''''')                  ||''','
    ||''''|| REPLACE(NVL(CALLBACK_STATUS_COL,''),'''','''''')               ||''','
    ||''''|| REPLACE(NVL(CALLBACK_REF_COL,''),'''','''''')                  ||''','
    ||''''|| REPLACE(NVL(POST_CALLBACK_PROC,''),'''','''''')                ||''','
    || NVL(TIMEOUT_MINUTES,60)                                              ||','
    || NVL(MAX_RETRY_COUNT,3)                                               ||','
    || NVL(RETRY_INTERVAL_MINUTES,30)                                       ||','
    ||''''|| NVL(IS_ACTIVE,'Y')                                             ||''','
    ||'SYSTIMESTAMP,'
    ||'SYSTIMESTAMP,'
    ||''''|| NVL(APIC_API_VERSION,'1')                                      ||''','
    ||''''|| REPLACE(NVL(RECORD_TYPE_HDR,''),'''','''''')                   ||''','
    ||''''|| REPLACE(NVL(EVENT_CODE_HDR,''),'''','''''')                    ||''','
    || NVL(BATCH_SIZE,100)                                                  ||','
    || NVL(EXECUTION_ORDER,10)                                              ||');'
FROM CRM_MPM_API_REGISTRY
ORDER BY EXECUTION_ORDER;

PROMPT COMMIT;
PROMPT

-- =============================================================================
-- TABLE: CRM_MPM_API_FIELD_MAPPING (9 columns)
-- Columns: MAPPING_ID(NUMBER), JSON_MAPPING_NAME(VARCHAR2 100),
--   SOURCE_COLUMN(VARCHAR2 128), JSON_PATH(VARCHAR2 200),
--   DATA_TYPE(VARCHAR2 20), DATE_FORMAT(VARCHAR2 50),
--   IS_MANDATORY(CHAR 1), DISPLAY_ORDER(NUMBER), IS_ACTIVE(CHAR 1)
-- NOTE: No CREATED_DATE column in actual table
-- =============================================================================
PROMPT PROMPT --- DATA: CRM_MPM_API_FIELD_MAPPING ---
PROMPT

SELECT
    -- MAPPING_ID excluded -- GENERATED ALWAYS AS IDENTITY
    'INSERT INTO CRM_MPM_API_FIELD_MAPPING'
    ||' (JSON_MAPPING_NAME,SOURCE_COLUMN,JSON_PATH,'
    ||'DATA_TYPE,DATE_FORMAT,IS_MANDATORY,DISPLAY_ORDER,IS_ACTIVE) VALUES ('
    ||''''|| REPLACE(NVL(JSON_MAPPING_NAME,''),'''','''''')         ||''','
    ||''''|| REPLACE(NVL(SOURCE_COLUMN,''),'''','''''')             ||''','
    ||''''|| REPLACE(NVL(JSON_PATH,''),'''','''''')                 ||''','
    ||''''|| NVL(DATA_TYPE,'VARCHAR2')                              ||''','
    ||''''|| NVL(DATE_FORMAT,'')                                    ||''','
    ||''''|| NVL(IS_MANDATORY,'N')                                  ||''','
    || NVL(DISPLAY_ORDER,10)                                        ||','
    ||''''|| NVL(IS_ACTIVE,'Y')                                     ||''');'
FROM CRM_MPM_API_FIELD_MAPPING
WHERE IS_ACTIVE = 'Y'
ORDER BY JSON_MAPPING_NAME, DISPLAY_ORDER;

PROMPT COMMIT;
PROMPT

-- =============================================================================
-- TABLE: CRM_MPM_API_WATERMARK (5 columns)
-- Columns: REGISTRY_ID(NUMBER), LAST_PROCESSED_TS(TIMESTAMP),
--   LAST_RUN_STATUS(VARCHAR2 20), LAST_RUN_RECORDS(NUMBER),
--   UPDATED_DATE(TIMESTAMP)
-- =============================================================================
PROMPT PROMPT --- DATA: CRM_MPM_API_WATERMARK ---
PROMPT

SELECT
    'INSERT INTO CRM_MPM_API_WATERMARK'
    ||' (REGISTRY_ID,LAST_PROCESSED_TS,LAST_RUN_STATUS,'
    ||'LAST_RUN_RECORDS,UPDATED_DATE) VALUES ('
    || REGISTRY_ID                                                              ||','
    || CASE WHEN LAST_PROCESSED_TS IS NOT NULL
            THEN 'TO_TIMESTAMP('''
                 ||TO_CHAR(LAST_PROCESSED_TS,'DD-MON-YYYY HH24:MI:SS')
                 ||''',''DD-MON-YYYY HH24:MI:SS'')'
            ELSE 'SYSDATE-1' END                                                ||','
    ||''''|| NVL(LAST_RUN_STATUS,'INIT')                                        ||''','
    || NVL(LAST_RUN_RECORDS,0)                                                  ||','
    ||'SYSTIMESTAMP);'
FROM CRM_MPM_API_WATERMARK
ORDER BY REGISTRY_ID;

PROMPT COMMIT;
PROMPT

-- =============================================================================
-- TABLE: CRM_MPM_CONFIG_STORE (10 columns)
-- Columns: CONFIG_ID(NUMBER), KEY_NAME(VARCHAR2 100), KEY_VALUE_ENC(BLOB),
--   CATEGORY(VARCHAR2 50), DESCRIPTION(VARCHAR2 200), OWNER_SYSTEM(VARCHAR2 100),
--   IS_ACTIVE(CHAR 1), CREATED_DATE(DATE), UPDATED_DATE(DATE), CREATED_BY(VARCHAR2 100)
-- BLOB handled in PL/SQL
-- =============================================================================
PROMPT PROMPT --- DATA: CRM_MPM_CONFIG_STORE ---
PROMPT

DECLARE
    v_hex VARCHAR2(32767);
BEGIN
    FOR r IN (
        SELECT CONFIG_ID, KEY_NAME, KEY_VALUE_ENC, CATEGORY,
               DESCRIPTION, OWNER_SYSTEM, IS_ACTIVE,
               CREATED_DATE, UPDATED_DATE, CREATED_BY
        FROM CRM_MPM_CONFIG_STORE
    ) LOOP
        IF r.KEY_VALUE_ENC IS NOT NULL
           AND DBMS_LOB.GETLENGTH(r.KEY_VALUE_ENC) > 0 THEN
            v_hex := LOWER(RAWTOHEX(
                DBMS_LOB.SUBSTR(r.KEY_VALUE_ENC,
                    DBMS_LOB.GETLENGTH(r.KEY_VALUE_ENC), 1)));
        ELSE
            v_hex := NULL;
        END IF;

        INSERT INTO CRM_MPM_CONFIG_STORE (
            CONFIG_ID, KEY_NAME, KEY_VALUE_ENC, CATEGORY,
            DESCRIPTION, OWNER_SYSTEM, IS_ACTIVE,
            CREATED_DATE, UPDATED_DATE, CREATED_BY)
        VALUES (
            r.CONFIG_ID, r.KEY_NAME,
            CASE WHEN v_hex IS NOT NULL
                 THEN TO_BLOB(HEXTORAW(v_hex)) ELSE NULL END,
            r.CATEGORY, r.DESCRIPTION, r.OWNER_SYSTEM,
            r.IS_ACTIVE, r.CREATED_DATE, r.UPDATED_DATE, r.CREATED_BY);

        DBMS_OUTPUT.PUT_LINE('Inserted config: ' || r.KEY_NAME);
    END LOOP;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Done: CRM_MPM_CONFIG_STORE');
END;
/

-- =============================================================================
-- TABLES WITH NO SEED DATA (runtime/transactional tables)
-- CRM_MPM_CRM_INTEGRATION_LOG       -- runtime log
-- CRM_MPM_CRM_INTEGRATION_LOG_DETAIL-- runtime detail
-- CRM_MPM_CALLBACK_AUDIT_LOG        -- runtime audit
-- CRM_MPM_JOB_RUN_HISTORY           -- runtime history
-- CRM_MPM_OUTBOUND_STAGING          -- runtime staging
-- CRM_MPM_CONFIG_AUDIT              -- runtime audit
-- These are left empty on SIT -- data created when jobs run
-- =============================================================================
PROMPT PROMPT --- RUNTIME TABLES: No seed data needed ---
PROMPT -- CRM_MPM_CRM_INTEGRATION_LOG, CRM_MPM_CALLBACK_AUDIT_LOG,
PROMPT -- CRM_MPM_JOB_RUN_HISTORY, CRM_MPM_OUTBOUND_STAGING left empty
PROMPT

-- =============================================================================
-- PART 7: SCHEDULER JOBS
-- =============================================================================
PROMPT PROMPT --- SCHEDULER JOBS ---
PROMPT

PROMPT BEGIN
PROMPT   FOR j IN (SELECT JOB_NAME FROM USER_SCHEDULER_JOBS WHERE JOB_NAME LIKE 'CRM_MPM%') LOOP
PROMPT     BEGIN DBMS_SCHEDULER.STOP_JOB(j.JOB_NAME,TRUE); EXCEPTION WHEN OTHERS THEN NULL; END;
PROMPT     BEGIN DBMS_SCHEDULER.DROP_JOB(j.JOB_NAME,TRUE); EXCEPTION WHEN OTHERS THEN NULL; END;
PROMPT   END LOOP;
PROMPT END;
PROMPT /

SELECT
    'BEGIN DBMS_SCHEDULER.CREATE_JOB('
    ||'job_name=>'''  || JOB_NAME         || ''','
    ||'job_type=>'''  || JOB_TYPE         || ''','
    ||'job_action=>'''|| JOB_ACTION       || ''','
    ||'repeat_interval=>'''||REPEAT_INTERVAL||''','
    ||'enabled=>'|| CASE WHEN ENABLED='TRUE' THEN 'TRUE' ELSE 'FALSE' END ||','
    ||'comments=>'''|| NVL(COMMENTS,'')   || '''); END;'
    || CHR(10) || '/'
FROM USER_SCHEDULER_JOBS
WHERE JOB_NAME LIKE 'CRM_MPM%'
ORDER BY JOB_NAME;

PROMPT COMMIT;
PROMPT

-- =============================================================================
-- PART 8: VERIFICATION
-- =============================================================================
PROMPT PROMPT --- VERIFICATION ---
PROMPT

PROMPT SELECT TABLE_NAME, NUM_ROWS FROM USER_TABLES WHERE TABLE_NAME LIKE 'CRM_MPM%' ORDER BY TABLE_NAME;
PROMPT SELECT SEQUENCE_NAME, LAST_NUMBER FROM USER_SEQUENCES WHERE SEQUENCE_NAME LIKE 'CRM_MPM%' ORDER BY 1;
PROMPT SELECT INDEX_NAME, TABLE_NAME, STATUS FROM USER_INDEXES WHERE TABLE_NAME LIKE 'CRM_MPM%' AND INDEX_NAME NOT LIKE 'SYS%' ORDER BY 1;
PROMPT SELECT OBJECT_NAME, OBJECT_TYPE, STATUS FROM USER_OBJECTS WHERE OBJECT_NAME='PKG_CRM_INTEGRATION' ORDER BY 2;
PROMPT SELECT JOB_NAME, ENABLED, STATE FROM USER_SCHEDULER_JOBS WHERE JOB_NAME LIKE 'CRM_MPM%' ORDER BY 1;
PROMPT SELECT ERROR_CODE, IS_RETRYABLE FROM CRM_MPM_ERROR_CODE_MASTER ORDER BY ERROR_CODE;
PROMPT SELECT SERVICE_NAME, IS_ACTIVE, EXECUTION_ORDER FROM CRM_MPM_API_REGISTRY ORDER BY EXECUTION_ORDER;
PROMPT SELECT JSON_MAPPING_NAME, COUNT(*) AS FIELDS FROM CRM_MPM_API_FIELD_MAPPING GROUP BY JSON_MAPPING_NAME ORDER BY 1;
PROMPT SELECT R.SERVICE_NAME, TO_CHAR(W.LAST_PROCESSED_TS,'DD-MON-YY HH24:MI') FROM CRM_MPM_API_WATERMARK W JOIN CRM_MPM_API_REGISTRY R ON R.REGISTRY_ID=W.REGISTRY_ID ORDER BY R.EXECUTION_ORDER;
PROMPT

PROMPT -- =================================================================
PROMPT -- END OF GENERATED SCRIPT
PROMPT -- =================================================================
