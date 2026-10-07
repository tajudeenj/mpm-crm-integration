-- ============================================================
-- SIT Callback Debug Queries
-- Purpose : Diagnose why callback is not firing / blank
-- Run in  : SQL Developer on SIT environment
-- ============================================================

-- -------------------------------------------------------
-- QUERY 1: Check callback configuration in registry
-- All callback columns should be populated for callback to work
-- -------------------------------------------------------
SELECT REGISTRY_ID, SERVICE_NAME,
       APIC_ENDPOINT_URL,
       CALLBACK_TARGET_TABLE,
       CALLBACK_KEY_COL,
       CALLBACK_STATUS_COL,
       CALLBACK_REF_COL,
       POST_CALLBACK_PROC
FROM   CRM_MPM_API_REGISTRY
WHERE  IS_ACTIVE = 'Y'
ORDER  BY REGISTRY_ID;

-- -------------------------------------------------------
-- QUERY 2: Check current status of recent sent records
-- SENT = waiting for callback, SUCCESS = callback received
-- -------------------------------------------------------
SELECT L.LOG_ID,
       R.SERVICE_NAME,
       L.SOURCE_RECORD_ID,
       L.FINAL_STATUS,
       L.CRM_REFERENCE_NO,
       L.X_UNIQUE_ID,
       TO_CHAR(L.SENT_DATE,    'DD-MON-YY HH24:MI:SS') AS SENT_DATE,
       TO_CHAR(L.CALLBACK_DATE,'DD-MON-YY HH24:MI:SS') AS CALLBACK_DATE,
       SUBSTR(L.CALLBACK_RESULT_DESC,  1,300) AS CALLBACK_RESULT,
       SUBSTR(L.CALLBACK_VALID_ERRORS, 1,300) AS VALIDATION_ERRORS,
       SUBSTR(L.ERROR_MESSAGE,         1,300) AS ERROR_MESSAGE
FROM   CRM_MPM_CRM_INTEGRATION_LOG L
JOIN   CRM_MPM_API_REGISTRY R ON R.REGISTRY_ID = L.REGISTRY_ID
WHERE  L.SENT_DATE >= SYSDATE - 1
ORDER  BY L.LOG_ID DESC
FETCH FIRST 20 ROWS ONLY;

-- -------------------------------------------------------
-- QUERY 3: Records stuck in SENT (waiting for callback)
-- If stuck > 30 min something is wrong with callback
-- -------------------------------------------------------
SELECT L.LOG_ID,
       R.SERVICE_NAME,
       L.SOURCE_RECORD_ID,
       L.FINAL_STATUS,
       L.X_UNIQUE_ID,
       ROUND((SYSDATE - L.SENT_DATE) * 24 * 60, 1) AS WAITING_MINUTES,
       TO_CHAR(L.SENT_DATE, 'DD-MON-YY HH24:MI:SS') AS SENT_DATE
FROM   CRM_MPM_CRM_INTEGRATION_LOG L
JOIN   CRM_MPM_API_REGISTRY R ON R.REGISTRY_ID = L.REGISTRY_ID
WHERE  L.FINAL_STATUS = 'SENT'
AND    L.SENT_DATE   >= SYSDATE - 1
ORDER  BY L.SENT_DATE ASC;

-- -------------------------------------------------------
-- QUERY 4: Callback audit log - what callbacks were received
-- Shows raw payload received from APIC
-- -------------------------------------------------------
SELECT TO_CHAR(A.AUDIT_ID)                            AS AUDIT_ID,
       TO_CHAR(A.RECEIVED_AT,'DD-MON-YY HH24:MI:SS') AS RECEIVED_AT,
       A.SERVICE_NAME,
       A.X_UNIQUE_ID,
       A.CHANNEL_ID,
       A.REQUEST_ID,
       A.STATUS_CODE_SENT,
       SUBSTR(A.DESCRIPTION_SENT, 1,300)              AS DESCRIPTION_SENT,
       SUBSTR(A.RAW_PAYLOAD,      1,500)              AS RAW_PAYLOAD
FROM   CRM_MPM_CALLBACK_AUDIT_LOG A
WHERE  A.RECEIVED_AT >= SYSDATE - 1
ORDER  BY A.AUDIT_ID DESC
FETCH FIRST 20 ROWS ONLY;

-- -------------------------------------------------------
-- QUERY 5: Match sent records with callbacks received
-- Shows which sent records have/have not got a callback
-- -------------------------------------------------------
SELECT L.LOG_ID,
       R.SERVICE_NAME,
       L.SOURCE_RECORD_ID,
       L.X_UNIQUE_ID,
       L.FINAL_STATUS,
       TO_CHAR(L.SENT_DATE,    'DD-MON-YY HH24:MI') AS SENT_DATE,
       TO_CHAR(L.CALLBACK_DATE,'DD-MON-YY HH24:MI') AS CALLBACK_DATE,
       CASE
           WHEN L.CALLBACK_DATE IS NOT NULL THEN 'CALLBACK RECEIVED'
           WHEN L.FINAL_STATUS  = 'SENT'    THEN 'WAITING FOR CALLBACK'
           ELSE L.FINAL_STATUS
       END AS CALLBACK_STATUS
FROM   CRM_MPM_CRM_INTEGRATION_LOG L
JOIN   CRM_MPM_API_REGISTRY R ON R.REGISTRY_ID = L.REGISTRY_ID
WHERE  L.SENT_DATE >= SYSDATE - 1
ORDER  BY L.LOG_ID DESC
FETCH FIRST 20 ROWS ONLY;

-- -------------------------------------------------------
-- QUERY 6: Check PROCESS_CRM_CALLBACK procedure is valid
-- If INVALID - callback will fail silently
-- -------------------------------------------------------
SELECT OBJECT_NAME, OBJECT_TYPE, STATUS,
       TO_CHAR(LAST_DDL_TIME,'DD-MON-YY HH24:MI') AS LAST_COMPILED
FROM   USER_OBJECTS
WHERE  OBJECT_NAME = 'PKG_CRM_INTEGRATION'
ORDER  BY OBJECT_TYPE;

-- -------------------------------------------------------
-- QUERY 7: Check callback endpoint config on SIT
-- Verify the URL APIC should call back to
-- -------------------------------------------------------
SELECT CONFIG_KEY, CONFIG_VALUE, DESCRIPTION
FROM   CRM_MPM_CONFIG_STORE
WHERE  CONFIG_KEY LIKE '%CALLBACK%'
   OR  CONFIG_KEY LIKE '%ENDPOINT%'
   OR  CONFIG_KEY LIKE '%BASE_URL%'
ORDER  BY CONFIG_KEY;

-- -------------------------------------------------------
-- QUERY 8: Timeout check - records sent but no callback
-- for more than TIMEOUT_MINUTES
-- -------------------------------------------------------
SELECT L.LOG_ID,
       R.SERVICE_NAME,
       L.SOURCE_RECORD_ID,
       L.FINAL_STATUS,
       R.TIMEOUT_MINUTES,
       ROUND((SYSDATE - L.SENT_DATE) * 24 * 60, 1) AS ELAPSED_MINUTES,
       CASE
           WHEN ROUND((SYSDATE - L.SENT_DATE)*24*60,1) > R.TIMEOUT_MINUTES
           THEN 'TIMED OUT'
           ELSE 'WITHIN TIMEOUT'
       END AS TIMEOUT_STATUS
FROM   CRM_MPM_CRM_INTEGRATION_LOG L
JOIN   CRM_MPM_API_REGISTRY R ON R.REGISTRY_ID = L.REGISTRY_ID
WHERE  L.FINAL_STATUS = 'SENT'
ORDER  BY L.SENT_DATE ASC;
