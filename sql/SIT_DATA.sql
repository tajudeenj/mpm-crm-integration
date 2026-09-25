-- =============================================================================
-- ADIB MPM PROPERTIES -- CRM xRM INTEGRATION
-- FILE : SIT_DATA.sql
-- DESC : Data only -- INSERTs for config/seed tables only
--        Runtime tables (log, audit, staging, history) are intentionally empty
-- Run on DEV first to generate output, then run output on SIT
-- Author  : Tajudeen Jalaudin -- Senior Solution Architect, ADIB
-- Date    : 24 September 2026
-- =============================================================================
-- CONFIG TABLES (data extracted from DEV):
--   CRM_MPM_ENCRYPT_CONFIG
--   CRM_MPM_UNIQUE_ID_CONFIG
--   CRM_MPM_ERROR_CODE_MASTER
--   CRM_MPM_API_CREDENTIALS
--   CRM_MPM_API_REGISTRY
--   CRM_MPM_API_FIELD_MAPPING
--   CRM_MPM_API_WATERMARK
--   CRM_MPM_CONFIG_STORE
--
-- RUNTIME TABLES (empty on SIT -- correct):
--   CRM_MPM_CRM_INTEGRATION_LOG        -- transaction log
--   CRM_MPM_CRM_INTEGRATION_LOG_DETAIL -- log detail
--   CRM_MPM_CALLBACK_AUDIT_LOG         -- callback audit
--   CRM_MPM_CONFIG_AUDIT               -- config audit
--   CRM_MPM_JOB_RUN_HISTORY            -- job history
--   CRM_MPM_OUTBOUND_STAGING           -- staging
-- =============================================================================
-- HOW TO USE:
--   Step 1 : Run SIT_DDL.sql on DEV first -- get DDL output -- run on SIT
--   Step 2 : Run THIS file on DEV -- get INSERT output -- run on SIT
--   Step 3 : Run SIT_DATA_output.sql on SIT AFTER DDL is done
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
SET SERVEROUTPUT  ON
SET DEFINE        OFF

SPOOL C:\temp\SIT_DATA_output.sql

PROMPT SET DEFINE OFF;
PROMPT SET FEEDBACK OFF;
PROMPT WHENEVER SQLERROR CONTINUE;

-- =============================================================================
-- PART 1: CRM_MPM_ENCRYPT_CONFIG
-- =============================================================================
PROMPT -- =============================================================================
PROMPT -- PART 1: CRM_MPM_ENCRYPT_CONFIG
PROMPT -- =============================================================================

BEGIN
    FOR r IN (
        SELECT CONFIG_ID, KEY_NAME, ENCRYPT_KEY, IS_ACTIVE, CREATED_DATE
        FROM   CRM_MPM_ENCRYPT_CONFIG
        ORDER  BY CONFIG_ID
    ) LOOP
        DBMS_OUTPUT.PUT_LINE(
            'INSERT INTO CRM_MPM_ENCRYPT_CONFIG'
            ||' (CONFIG_ID,KEY_NAME,ENCRYPT_KEY,IS_ACTIVE,CREATED_DATE) VALUES ('
            || r.CONFIG_ID                                                    ||','
            ||''''|| REPLACE(NVL(r.KEY_NAME,''),'''','''''')                  ||''','
            ||'HEXTORAW('''|| RAWTOHEX(r.ENCRYPT_KEY)                         ||'''),'
            ||''''|| NVL(r.IS_ACTIVE,'Y')                                     ||''','
            || 'TO_DATE('''|| TO_CHAR(r.CREATED_DATE,'YYYY-MM-DD')            ||''',''YYYY-MM-DD''));'
        );
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('COMMIT;');
END;
/

-- =============================================================================
-- PART 2: CRM_MPM_UNIQUE_ID_CONFIG
-- =============================================================================
PROMPT -- =============================================================================
PROMPT -- PART 2: CRM_MPM_UNIQUE_ID_CONFIG
PROMPT -- =============================================================================

BEGIN
    FOR r IN (
        SELECT CONFIG_ID, CHANNEL_ID, TIMESTAMP_FORMAT,
               SEQUENCE_DIGITS, IS_ACTIVE, UPDATED_DATE
        FROM   CRM_MPM_UNIQUE_ID_CONFIG
        ORDER  BY CONFIG_ID
    ) LOOP
        DBMS_OUTPUT.PUT_LINE(
            'INSERT INTO CRM_MPM_UNIQUE_ID_CONFIG'
            ||' (CONFIG_ID,CHANNEL_ID,TIMESTAMP_FORMAT,SEQUENCE_DIGITS,IS_ACTIVE,UPDATED_DATE) VALUES ('
            || r.CONFIG_ID                                                          ||','
            ||''''|| REPLACE(NVL(r.CHANNEL_ID,''),'''','''''')                      ||''','
            ||''''|| REPLACE(NVL(r.TIMESTAMP_FORMAT,''),'''','''''')                ||''','
            || NVL(r.SEQUENCE_DIGITS,4)                                             ||','
            ||''''|| NVL(r.IS_ACTIVE,'Y')                                           ||''','
            || 'TO_DATE('''|| TO_CHAR(r.UPDATED_DATE,'YYYY-MM-DD')                  ||''',''YYYY-MM-DD''));'
        );
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('COMMIT;');
END;
/

-- =============================================================================
-- PART 3: CRM_MPM_ERROR_CODE_MASTER
-- (4 columns only: ERROR_CODE, ERROR_CATEGORY, ERROR_DESCRIPTION, IS_RETRYABLE)
-- =============================================================================
PROMPT -- =============================================================================
PROMPT -- PART 3: CRM_MPM_ERROR_CODE_MASTER
PROMPT -- =============================================================================

BEGIN
    FOR r IN (
        SELECT ERROR_CODE, ERROR_CATEGORY, ERROR_DESCRIPTION, IS_RETRYABLE
        FROM   CRM_MPM_ERROR_CODE_MASTER
        ORDER  BY ERROR_CODE
    ) LOOP
        DBMS_OUTPUT.PUT_LINE(
            'INSERT INTO CRM_MPM_ERROR_CODE_MASTER'
            ||' (ERROR_CODE,ERROR_CATEGORY,ERROR_DESCRIPTION,IS_RETRYABLE) VALUES ('
            ||''''|| REPLACE(NVL(r.ERROR_CODE,''),'''','''''')                      ||''','
            ||''''|| REPLACE(NVL(r.ERROR_CATEGORY,''),'''','''''')                  ||''','
            ||''''|| REPLACE(NVL(r.ERROR_DESCRIPTION,''),'''','''''')               ||''','
            ||''''|| NVL(r.IS_RETRYABLE,'N')                                        ||''');'
        );
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('COMMIT;');
END;
/

-- =============================================================================
-- PART 4: CRM_MPM_API_CREDENTIALS
-- (CRED_ID excluded -- GENERATED ALWAYS AS IDENTITY)
-- BLOB columns: inserted as NULL here -- re-encrypt on SIT using SIT_ENCRYPT_SECRET.sql
-- =============================================================================
PROMPT -- =============================================================================
PROMPT -- PART 4: CRM_MPM_API_CREDENTIALS
PROMPT -- =============================================================================

-- NOTE: CLIENT_SECRET_ENCRYPTED and WALLET_PASSWORD_ENC inserted as NULL
-- After deployment run SIT_ENCRYPT_SECRET.sql on SIT to set encrypted values

SELECT
    'INSERT INTO CRM_MPM_API_CREDENTIALS'
    ||' (CRED_CODE,TOKEN_URL,CLIENT_ID,'
    ||'CLIENT_SECRET_REF,SCOPE,GRANT_TYPE,'
    ||'IS_ACTIVE,CREATED_DATE,UPDATED_DATE,'
    ||'WALLET_PATH,ENCRYPT_KEY_REF,WALLET_PWD_KEY_REF,'
    ||'CLIENT_SECRET_ENCRYPTED,WALLET_PASSWORD_ENC) VALUES ('
    ||''''|| REPLACE(NVL(CRED_CODE,''),'''','''''')           ||''','
    ||''''|| REPLACE(NVL(TOKEN_URL,''),'''','''''')            ||''','
    ||''''|| REPLACE(NVL(CLIENT_ID,''),'''','''''')            ||''','
    ||''''|| REPLACE(NVL(CLIENT_SECRET_REF,''),'''','''''')    ||''','
    ||''''|| REPLACE(NVL(SCOPE,''),'''','''''')                ||''','
    ||''''|| REPLACE(NVL(GRANT_TYPE,'client_credentials'),'''','''''') ||''','
    ||''''|| NVL(IS_ACTIVE,'Y')                               ||''','
    ||'SYSTIMESTAMP,'
    ||'SYSTIMESTAMP,'
    ||''''|| REPLACE(NVL(WALLET_PATH,''),'''','''''')          ||''','
    ||''''|| REPLACE(NVL(ENCRYPT_KEY_REF,''),'''','''''')      ||''','
    ||''''|| REPLACE(NVL(WALLET_PWD_KEY_REF,''),'''','''''')   ||''','
    ||'NULL,'  -- CLIENT_SECRET_ENCRYPTED -- set via SIT_ENCRYPT_SECRET.sql
    ||'NULL);' -- WALLET_PASSWORD_ENC     -- set via SIT_ENCRYPT_SECRET.sql
FROM CRM_MPM_API_CREDENTIALS
ORDER BY CRED_CODE;

SELECT 'COMMIT;' FROM DUAL;

-- =============================================================================
-- PART 5: CRM_MPM_API_REGISTRY
-- =============================================================================
PROMPT -- =============================================================================
PROMPT -- PART 5: CRM_MPM_API_REGISTRY
PROMPT -- =============================================================================

SELECT
    'INSERT INTO CRM_MPM_API_REGISTRY'
    ||' (REGISTRY_ID,ENTITY_NAME,OPERATION_TYPE,SOURCE_TYPE,'
    ||'SOURCE_VIEW,SOURCE_PROC,SOURCE_FILTER_COL,SOURCE_KEY_COL,'
    ||'JSON_MAPPING_NAME,APIC_ENDPOINT_URL,HTTP_METHOD,CRED_CODE,'
    ||'SERVICE_NAME,CALLBACK_TARGET_TABLE,CALLBACK_KEY_COL,'
    ||'CALLBACK_STATUS_COL,CALLBACK_REF_COL,POST_CALLBACK_PROC,'
    ||'TIMEOUT_MINUTES,MAX_RETRY_COUNT,RETRY_INTERVAL_MINUTES,'
    ||'IS_ACTIVE,CREATED_DATE,UPDATED_DATE,APIC_API_VERSION,'
    ||'RECORD_TYPE_HDR,EVENT_CODE_HDR,BATCH_SIZE,EXECUTION_ORDER) VALUES ('
    || NVL(TO_CHAR(REGISTRY_ID),'NULL')                                   ||','
    ||''''|| REPLACE(NVL(ENTITY_NAME,''),'''','''''')                      ||''','
    ||''''|| REPLACE(NVL(OPERATION_TYPE,''),'''','''''')                   ||''','
    ||''''|| REPLACE(NVL(SOURCE_TYPE,''),'''','''''')                      ||''','
    ||''''|| REPLACE(NVL(SOURCE_VIEW,''),'''','''''')                      ||''','
    ||''''|| REPLACE(NVL(SOURCE_PROC,''),'''','''''')                      ||''','
    ||''''|| REPLACE(NVL(SOURCE_FILTER_COL,''),'''','''''')                ||''','
    ||''''|| REPLACE(NVL(SOURCE_KEY_COL,''),'''','''''')                   ||''','
    ||''''|| REPLACE(NVL(JSON_MAPPING_NAME,''),'''','''''')                ||''','
    ||''''|| REPLACE(NVL(APIC_ENDPOINT_URL,''),'''','''''')                ||''','
    ||''''|| REPLACE(NVL(HTTP_METHOD,'POST'),'''','''''')                  ||''','
    ||''''|| REPLACE(NVL(CRED_CODE,''),'''','''''')                        ||''','
    ||''''|| REPLACE(NVL(SERVICE_NAME,''),'''','''''')                     ||''','
    ||''''|| REPLACE(NVL(CALLBACK_TARGET_TABLE,''),'''','''''')            ||''','
    ||''''|| REPLACE(NVL(CALLBACK_KEY_COL,''),'''','''''')                 ||''','
    ||''''|| REPLACE(NVL(CALLBACK_STATUS_COL,''),'''','''''')              ||''','
    ||''''|| REPLACE(NVL(CALLBACK_REF_COL,''),'''','''''')                 ||''','
    ||''''|| REPLACE(NVL(POST_CALLBACK_PROC,''),'''','''''')               ||''','
    || NVL(TO_CHAR(TIMEOUT_MINUTES),'30')                                  ||','
    || NVL(TO_CHAR(MAX_RETRY_COUNT),'3')                                   ||','
    || NVL(TO_CHAR(RETRY_INTERVAL_MINUTES),'5')                            ||','
    ||''''|| NVL(IS_ACTIVE,'Y')                                            ||''','
    ||'SYSDATE,'
    ||'SYSDATE,'
    ||''''|| REPLACE(NVL(APIC_API_VERSION,''),'''','''''')                 ||''','
    ||''''|| REPLACE(NVL(RECORD_TYPE_HDR,''),'''','''''')                  ||''','
    ||''''|| REPLACE(NVL(EVENT_CODE_HDR,''),'''','''''')                   ||''','
    || NVL(TO_CHAR(BATCH_SIZE),'100')                                      ||','
    || NVL(TO_CHAR(EXECUTION_ORDER),'10')                                  ||');'
FROM CRM_MPM_API_REGISTRY
ORDER BY EXECUTION_ORDER, REGISTRY_ID;

SELECT 'COMMIT;' FROM DUAL;

-- PART 6: CRM_MPM_API_FIELD_MAPPING
-- (MAPPING_ID excluded -- GENERATED ALWAYS AS IDENTITY)
-- =============================================================================
PROMPT -- =============================================================================
PROMPT -- PART 6: CRM_MPM_API_FIELD_MAPPING
PROMPT -- =============================================================================

BEGIN
    FOR r IN (
        SELECT JSON_MAPPING_NAME, SOURCE_COLUMN, JSON_PATH,
               DATA_TYPE, DATE_FORMAT, IS_MANDATORY,
               DISPLAY_ORDER, IS_ACTIVE
        FROM   CRM_MPM_API_FIELD_MAPPING
        ORDER  BY JSON_MAPPING_NAME, DISPLAY_ORDER
    ) LOOP
        -- MAPPING_ID excluded -- GENERATED ALWAYS AS IDENTITY
        DBMS_OUTPUT.PUT_LINE(
            'INSERT INTO CRM_MPM_API_FIELD_MAPPING'
            ||' (JSON_MAPPING_NAME,SOURCE_COLUMN,JSON_PATH,'
            ||'DATA_TYPE,DATE_FORMAT,IS_MANDATORY,DISPLAY_ORDER,IS_ACTIVE) VALUES ('
            ||''''|| REPLACE(NVL(r.JSON_MAPPING_NAME,''),'''','''''')   ||''','
            ||''''|| REPLACE(NVL(r.SOURCE_COLUMN,''),'''','''''')        ||''','
            ||''''|| REPLACE(NVL(r.JSON_PATH,''),'''','''''')            ||''','
            ||''''|| NVL(r.DATA_TYPE,'VARCHAR2')                         ||''','
            ||''''|| REPLACE(NVL(r.DATE_FORMAT,''),'''','''''')          ||''','
            ||''''|| NVL(r.IS_MANDATORY,'N')                             ||''','
            || NVL(r.DISPLAY_ORDER,10)                                   ||','
            ||''''|| NVL(r.IS_ACTIVE,'Y')                                ||''');'
        );
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('COMMIT;');
END;
/

-- =============================================================================
-- PART 7: CRM_MPM_API_WATERMARK
-- =============================================================================
PROMPT -- =============================================================================
PROMPT -- PART 7: CRM_MPM_API_WATERMARK
PROMPT -- =============================================================================

BEGIN
    FOR r IN (
        SELECT REGISTRY_ID, LAST_PROCESSED_TS, LAST_RUN_STATUS,
               LAST_RUN_RECORDS, UPDATED_DATE
        FROM   CRM_MPM_API_WATERMARK
        ORDER  BY REGISTRY_ID
    ) LOOP
        DBMS_OUTPUT.PUT_LINE(
            'INSERT INTO CRM_MPM_API_WATERMARK'
            ||' (REGISTRY_ID,LAST_PROCESSED_TS,LAST_RUN_STATUS,LAST_RUN_RECORDS,UPDATED_DATE) VALUES ('
            || NVL(TO_CHAR(r.REGISTRY_ID),'NULL')                                    ||','
            || CASE WHEN r.LAST_PROCESSED_TS IS NOT NULL
               THEN 'TIMESTAMP '''||TO_CHAR(r.LAST_PROCESSED_TS,'YYYY-MM-DD HH24:MI:SS')||''''
               ELSE 'NULL' END                                                        ||','
            ||''''|| NVL(r.LAST_RUN_STATUS,'SUCCESS')                                ||''','
            || NVL(TO_CHAR(r.LAST_RUN_RECORDS),'0')                                  ||','
            ||'SYSDATE);'
        );
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('COMMIT;');
END;
/

-- =============================================================================
-- PART 8: CRM_MPM_CONFIG_STORE
-- BLOB column KEY_VALUE_ENC inserted as NULL -- set manually on SIT if needed
-- =============================================================================
PROMPT -- =============================================================================
PROMPT -- PART 8: CRM_MPM_CONFIG_STORE
PROMPT -- =============================================================================

SELECT
    'INSERT INTO CRM_MPM_CONFIG_STORE'
    ||' (CONFIG_ID,KEY_NAME,CATEGORY,'
    ||'DESCRIPTION,OWNER_SYSTEM,IS_ACTIVE,'
    ||'CREATED_DATE,UPDATED_DATE,CREATED_BY,KEY_VALUE_ENC) VALUES ('
    || NVL(TO_CHAR(CONFIG_ID),'NULL')                                  ||','
    ||''''|| REPLACE(NVL(KEY_NAME,''),'''','''''')                      ||''','
    ||''''|| REPLACE(NVL(CATEGORY,''),'''','''''')                      ||''','
    ||''''|| REPLACE(NVL(DESCRIPTION,''),'''','''''')                   ||''','
    ||''''|| REPLACE(NVL(OWNER_SYSTEM,''),'''','''''')                  ||''','
    ||''''|| NVL(IS_ACTIVE,'Y')                                         ||''','
    ||'SYSDATE,'
    ||'SYSDATE,'
    ||''''|| REPLACE(NVL(CREATED_BY,''),'''','''''')                    ||''','
    ||'NULL);'  -- KEY_VALUE_ENC BLOB -- set manually on SIT if needed
FROM CRM_MPM_CONFIG_STORE
ORDER BY CONFIG_ID;

SELECT 'COMMIT;' FROM DUAL;

SPOOL OFF

PROMPT -- Done. Output saved to C:\temp\SIT_DATA_output.sql
