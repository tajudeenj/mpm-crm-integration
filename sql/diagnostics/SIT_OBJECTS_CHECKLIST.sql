-- =============================================================================
-- SIT DEPLOYMENT OBJECTS CHECKLIST
-- All objects to ship from DEV to SIT
-- Author : ADIB EA Team (Tajudeen Jalaudin)
-- Date   : 2026-08-20
-- =============================================================================

-- =============================================================================
-- 1. VERIFY ALL OBJECTS IN DEV BEFORE SHIPPING
-- =============================================================================

-- TABLES
SELECT OBJECT_NAME, OBJECT_TYPE, STATUS,
       TO_CHAR(LAST_DDL_TIME,'DD-MON-YY HH24:MI') AS LAST_CHANGED
FROM USER_OBJECTS
WHERE OBJECT_NAME IN (
    'CRM_MPM_API_CREDENTIALS',
    'CRM_MPM_API_REGISTRY',
    'CRM_MPM_API_FIELD_MAPPING',
    'CRM_MPM_API_WATERMARK',
    'CRM_MPM_CRM_INTEGRATION_LOG',
    'CRM_MPM_JOB_RUN_HISTORY',
    'CRM_MPM_ERROR_CODE_MASTER',
    'CRM_MPM_UNIQUE_ID_CONFIG',
    'CRM_MPM_CALLBACK_AUDIT_LOG',
    'CRM_MPM_OUTBOUND_STAGING'
)
AND OBJECT_TYPE = 'TABLE'
ORDER BY OBJECT_NAME;

-- SEQUENCES
SELECT OBJECT_NAME, OBJECT_TYPE, STATUS
FROM USER_OBJECTS
WHERE OBJECT_NAME IN (
    'CRM_MPM_API_REGISTRY_SEQ',
    'CRM_MPM_FIELD_MAP_SEQ',
    'CRM_MPM_UNIQUE_ID_SEQ',
    'SEQ_CRM_STAGING'
)
AND OBJECT_TYPE = 'SEQUENCE'
ORDER BY OBJECT_NAME;

-- PACKAGE
SELECT OBJECT_NAME, OBJECT_TYPE, STATUS,
       TO_CHAR(LAST_DDL_TIME,'DD-MON-YY HH24:MI') AS LAST_CHANGED
FROM USER_OBJECTS
WHERE OBJECT_NAME = 'PKG_CRM_INTEGRATION'
ORDER BY OBJECT_TYPE;

-- VIEWS
SELECT OBJECT_NAME, OBJECT_TYPE, STATUS,
       TO_CHAR(LAST_DDL_TIME,'DD-MON-YY HH24:MI') AS LAST_CHANGED
FROM USER_OBJECTS
WHERE OBJECT_NAME IN (
    'XXMPM_CRM_BUILDING_CREATE_FULL_V',
    'XXMPM_CRM_BUILDING_UPDATE_FULL_V',
    'XXMPM_CRM_BUILDING_UTILITIES_CREATE_V',
    'XXMPM_CRM_BUILDING_UTILITIES_UPDATE_V',
    'XXMPM_CRM_TENANT_PERSON_V',
    'XXMPM_CRM_TENANT_ORG_V',
    'XXMPM_CRM_ALL_UNIT_STATUS_V'
)
AND OBJECT_TYPE = 'VIEW'
ORDER BY OBJECT_NAME;

-- SCHEDULER JOBS
SELECT JOB_NAME, ENABLED, STATE,
       REPEAT_INTERVAL,
       TO_CHAR(NEXT_RUN_DATE,'DD-MON-YY HH24:MI') AS NEXT_RUN
FROM USER_SCHEDULER_JOBS
WHERE JOB_NAME LIKE 'CRM_MPM%'
ORDER BY JOB_NAME;


-- =============================================================================
-- 2. COMPLETE OBJECT LIST TO SHIP
-- =============================================================================

/*
============================================================
TABLES (10) -- DDL + data for config tables
============================================================
1.  CRM_MPM_API_CREDENTIALS        -- config: token URL, client ID, secret, wallet
2.  CRM_MPM_API_REGISTRY           -- config: all services (13 view + 3 staging + 2 batch)
3.  CRM_MPM_API_FIELD_MAPPING      -- config: all field mappings
4.  CRM_MPM_API_WATERMARK          -- config: one row per view-based service
5.  CRM_MPM_CRM_INTEGRATION_LOG    -- empty in SIT
6.  CRM_MPM_JOB_RUN_HISTORY        -- empty in SIT
7.  CRM_MPM_ERROR_CODE_MASTER      -- config: all error codes
8.  CRM_MPM_UNIQUE_ID_CONFIG       -- config: channel ID 817, format, sequence digits
9.  CRM_MPM_CALLBACK_AUDIT_LOG     -- empty in SIT
10. CRM_MPM_OUTBOUND_STAGING       -- empty in SIT

============================================================
SEQUENCES (4)
============================================================
1.  CRM_MPM_API_REGISTRY_SEQ
2.  CRM_MPM_FIELD_MAP_SEQ
3.  CRM_MPM_UNIQUE_ID_SEQ
4.  SEQ_CRM_STAGING

============================================================
PACKAGE (1 spec + 1 body)
============================================================
1.  PKG_CRM_INTEGRATION SPEC  -- PKG_CRM_INTEGRATION_SPEC_V2.sql
2.  PKG_CRM_INTEGRATION BODY  -- PKG_CRM_INTEGRATION_BODY_V3.sql
    (with all fixes: Transfer-Encoding chunked, Arabic fix,
     SUBMIT_TO_STAGING, RUN_STAGING_JOB, RUN_UNIT_UNAVAILABLE_BATCH,
     RUN_UNIT_STATUS_BATCH, PROCESS_STAGING_CALLBACK,
     DATE col_type fix, SEND_PAYLOAD_TO_APIC helper)

============================================================
VIEWS (7) -- created by Oracle/ALMADAR team
============================================================
1.  XXMPM_CRM_BUILDING_CREATE_FULL_V
2.  XXMPM_CRM_BUILDING_UPDATE_FULL_V
3.  XXMPM_CRM_BUILDING_UTILITIES_CREATE_V
4.  XXMPM_CRM_BUILDING_UTILITIES_UPDATE_V
5.  XXMPM_CRM_TENANT_PERSON_V
6.  XXMPM_CRM_TENANT_ORG_V
7.  XXMPM_CRM_ALL_UNIT_STATUS_V      -- new consolidated view

============================================================
SCHEDULER JOBS (8)
============================================================
-- Outbound (4 times daily):
1.  CRM_MPM_OUTBOUND_6AM
2.  CRM_MPM_OUTBOUND_10AM
3.  CRM_MPM_OUTBOUND_2PM
4.  CRM_MPM_OUTBOUND_5PM

-- Retry job:
5.  CRM_MPM_RETRY_JOB
6.  CRM_MPM_TIMEOUT_JOB

-- Staging retry:
7.  CRM_MPM_STAGING_JOB

-- Unit status batch (out of hours):
8.  CRM_MPM_ALL_UNIT_STATUS_11PM
9.  CRM_MPM_ALL_UNIT_STATUS_4AM

============================================================
INDEXES (auto-created with tables)
============================================================
-- All indexes on CRM_MPM_* tables

============================================================
DATA TO MIGRATE (config tables only)
============================================================
1.  CRM_MPM_API_CREDENTIALS     -- UPDATE with SIT values
2.  CRM_MPM_API_REGISTRY        -- all services
3.  CRM_MPM_API_FIELD_MAPPING   -- all mappings
4.  CRM_MPM_API_WATERMARK       -- one row per view service
5.  CRM_MPM_ERROR_CODE_MASTER   -- all error codes
6.  CRM_MPM_UNIQUE_ID_CONFIG    -- channel 817 config

============================================================
WHAT CHANGES DEV → SIT
============================================================
Only CRM_MPM_API_CREDENTIALS needs SIT values:
- TOKEN_URL
- CLIENT_ID
- CLIENT_SECRET
- WALLET_PATH
- WALLET_PASSWORD
- APIC_ENDPOINT_URL (if different in SIT)

Everything else is identical DEV → SIT
*/


-- =============================================================================
-- 3. EXPORT CONFIG TABLE DATA
-- Run in DEV -- copy output to SIT
-- =============================================================================

-- Registry
SELECT * FROM CRM_MPM_API_REGISTRY
ORDER BY REGISTRY_ID;

-- Field Mappings
SELECT * FROM CRM_MPM_API_FIELD_MAPPING
ORDER BY REGISTRY_ID, DISPLAY_ORDER;

-- Watermark
SELECT * FROM CRM_MPM_API_WATERMARK
ORDER BY REGISTRY_ID;

-- Error Codes
SELECT * FROM CRM_MPM_ERROR_CODE_MASTER
ORDER BY ERROR_CODE;

-- Unique ID Config
SELECT * FROM CRM_MPM_UNIQUE_ID_CONFIG;


-- =============================================================================
-- 4. SIT CREDENTIALS TEMPLATE
-- Fill in SIT values before running in SIT
-- =============================================================================
/*
UPDATE CRM_MPM_API_CREDENTIALS
SET TOKEN_URL        = '<SIT_TOKEN_URL>',
    CLIENT_ID        = '<SIT_CLIENT_ID>',
    CLIENT_SECRET    = '<SIT_CLIENT_SECRET>',
    WALLET_PATH      = '<SIT_WALLET_PATH>',
    WALLET_PASSWORD  = '<SIT_WALLET_PASSWORD>',
    APIC_ENDPOINT_URL = '<SIT_APIC_ENDPOINT_URL>'
WHERE IS_ACTIVE = 'Y';
COMMIT;
*/


-- =============================================================================
-- 5. POST-DEPLOYMENT VERIFICATION IN SIT
-- =============================================================================
-- Check package compiled
SELECT OBJECT_NAME, OBJECT_TYPE, STATUS
FROM USER_OBJECTS
WHERE OBJECT_NAME = 'PKG_CRM_INTEGRATION';

-- Check all errors
SELECT * FROM USER_ERRORS
WHERE NAME = 'PKG_CRM_INTEGRATION';

-- Check registry
SELECT COUNT(*) AS TOTAL_SERVICES,
       SUM(CASE WHEN IS_ACTIVE='Y' THEN 1 ELSE 0 END) AS ACTIVE
FROM CRM_MPM_API_REGISTRY;

-- Check watermark
SELECT COUNT(*) AS WATERMARK_COUNT
FROM CRM_MPM_API_WATERMARK;

-- Check scheduler jobs
SELECT JOB_NAME, ENABLED, STATE
FROM USER_SCHEDULER_JOBS
WHERE JOB_NAME LIKE 'CRM_MPM%'
ORDER BY JOB_NAME;

-- Test one service
/*
SET SERVEROUTPUT ON SIZE UNLIMITED
DECLARE
    v_log_id NUMBER;
    v_reg_id NUMBER;
BEGIN
    SELECT REGISTRY_ID INTO v_reg_id
    FROM CRM_MPM_API_REGISTRY
    WHERE SERVICE_NAME = 'MD_BUILDING_CREATE';

    PKG_CRM_INTEGRATION.SEND_TO_APIC(
        p_registry_id => v_reg_id,
        p_key_value   => '<SIT_BUILDING_ID>',
        p_attempt_no  => 1,
        p_log_id_out  => v_log_id
    );
    DBMS_OUTPUT.PUT_LINE('LOG_ID: ' || v_log_id);
END;
/
*/
