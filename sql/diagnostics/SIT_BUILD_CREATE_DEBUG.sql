-- ============================================================
-- SIT Building CREATE Debug Queries
-- Purpose : Diagnose HTTP 400 on Building CREATE to APIC
-- Run in  : SQL Developer on SIT environment
-- ============================================================

-- -------------------------------------------------------
-- QUERY 1: Full error detail for Building CREATE failures
-- Check ERROR_MESSAGE for Oracle exception + APIC response
-- -------------------------------------------------------
SELECT L.LOG_ID,
       L.FINAL_STATUS,
       SUBSTR(L.ERROR_MESSAGE, 1, 2000)            AS ERROR_MESSAGE,
       SUBSTR(L.CALLBACK_RESULT_DESC, 1, 2000)     AS CALLBACK_RESULT,
       SUBSTR(L.CALLBACK_VALID_ERRORS, 1, 2000)    AS VALIDATION_ERRORS,
       DBMS_LOB.SUBSTR(L.REQUEST_PAYLOAD, 2000, 1) AS PAYLOAD_SENT,
       TO_CHAR(L.SENT_DATE, 'DD-MON-YY HH24:MI:SS') AS SENT_DATE
FROM   CRM_MPM_CRM_INTEGRATION_LOG L
WHERE  L.REGISTRY_ID  = 24
AND    L.FINAL_STATUS NOT IN ('SUCCESS','SENT')
ORDER  BY L.LOG_ID DESC
FETCH FIRST 3 ROWS ONLY;

-- -------------------------------------------------------
-- QUERY 2: Check registry config for Building CREATE
-- Compare RECORD_TYPE_HDR, EVENT_CODE_HDR with Postman
-- -------------------------------------------------------
SELECT REGISTRY_ID, SERVICE_NAME, ENTITY_NAME,
       OPERATION_TYPE, SOURCE_VIEW, SOURCE_KEY_COL,
       APIC_ENDPOINT_URL, HTTP_METHOD, APIC_API_VERSION,
       RECORD_TYPE_HDR, EVENT_CODE_HDR,
       CRED_CODE, IS_ACTIVE
FROM   CRM_MPM_API_REGISTRY
WHERE  REGISTRY_ID = 24;

-- -------------------------------------------------------
-- QUERY 3: Check field mappings for Building CREATE
-- Verify all mandatory fields are mapped correctly
-- -------------------------------------------------------
SELECT DISPLAY_ORDER, SOURCE_COLUMN, JSON_PATH,
       DATA_TYPE, NVL(DATE_FORMAT,'--') AS DATE_FORMAT,
       IS_MANDATORY, IS_ACTIVE
FROM   CRM_MPM_API_FIELD_MAPPING
WHERE  JSON_MAPPING_NAME = 'BUILDING_CREATE_MAP'
ORDER  BY DISPLAY_ORDER;

-- -------------------------------------------------------
-- QUERY 4: Check source view has data and key columns
-- -------------------------------------------------------
SELECT * FROM XXMPM_CRM_BUILDING_CREATE_FULL_V
FETCH FIRST 3 ROWS ONLY;

-- -------------------------------------------------------
-- QUERY 5: Check credentials on SIT
-- -------------------------------------------------------
SELECT CRED_CODE, CLIENT_ID,
       CLIENT_SECRET_REF, GRANT_TYPE,
       TOKEN_URL, IS_ACTIVE
FROM   CRM_MPM_API_CREDENTIALS
WHERE  IS_ACTIVE = 'Y';

-- -------------------------------------------------------
-- QUERY 6: Full payload of latest Building CREATE attempt
-- Copy payload and test in Postman to confirm
-- -------------------------------------------------------
SELECT DBMS_LOB.SUBSTR(L.REQUEST_PAYLOAD, 32000, 1) AS FULL_PAYLOAD
FROM   CRM_MPM_CRM_INTEGRATION_LOG L
WHERE  L.REGISTRY_ID = 24
ORDER  BY L.LOG_ID DESC
FETCH FIRST 1 ROWS ONLY;
