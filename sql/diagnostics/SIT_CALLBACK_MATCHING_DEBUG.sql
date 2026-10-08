-- ============================================================
-- SIT Callback Matching Debug
-- Purpose : Diagnose "No matching log entry" on callback
-- Run in  : SQL Developer on SIT environment
-- ============================================================

-- -------------------------------------------------------
-- QUERY 1: What X_UNIQUE_ID was sent for Property
-- Compare with Query 2 to find mismatch
-- -------------------------------------------------------
SELECT L.LOG_ID,
       L.X_UNIQUE_ID,
       L.SOURCE_RECORD_ID,
       L.FINAL_STATUS,
       TO_CHAR(L.SENT_DATE,'DD-MON-YY HH24:MI') AS SENT_DATE
FROM   CRM_MPM_CRM_INTEGRATION_LOG L
WHERE  L.REGISTRY_ID = 23
ORDER  BY L.LOG_ID DESC
FETCH FIRST 5 ROWS ONLY;

-- -------------------------------------------------------
-- QUERY 2: What X_UNIQUE_ID APIC sent back in callback
-- Compare with Query 1 to find mismatch
-- -------------------------------------------------------
SELECT AUDIT_ID,
       X_UNIQUE_ID,
       REQUEST_ID,
       SERVICE_NAME,
       STATUS_CODE_SENT,
       SUBSTR(RAW_PAYLOAD, 1, 500) AS RAW_PAYLOAD,
       TO_CHAR(RECEIVED_AT,'DD-MON-YY HH24:MI') AS RECEIVED_AT
FROM   CRM_MPM_CALLBACK_AUDIT_LOG
ORDER  BY AUDIT_ID DESC
FETCH FIRST 5 ROWS ONLY;

-- -------------------------------------------------------
-- QUERY 3: Check how callback lookup works in package
-- Shows what column is used to match log entry
-- -------------------------------------------------------
SELECT LINE, TEXT
FROM   USER_SOURCE
WHERE  NAME = 'PKG_CRM_INTEGRATION'
AND    TYPE = 'PACKAGE BODY'
AND    TEXT LIKE '%X_UNIQUE_ID%'
ORDER  BY LINE;

-- -------------------------------------------------------
-- QUERY 4: Cross match - sent vs received
-- Shows clearly which sent records got callback
-- and which X_UNIQUE_ID values do not match
-- -------------------------------------------------------
SELECT L.LOG_ID,
       L.X_UNIQUE_ID                              AS SENT_X_UNIQUE_ID,
       A.X_UNIQUE_ID                              AS CALLBACK_X_UNIQUE_ID,
       L.SOURCE_RECORD_ID,
       L.FINAL_STATUS,
       A.STATUS_CODE_SENT,
       TO_CHAR(L.SENT_DATE,    'DD-MON-YY HH24:MI') AS SENT_DATE,
       TO_CHAR(A.RECEIVED_AT,  'DD-MON-YY HH24:MI') AS CALLBACK_DATE,
       CASE
           WHEN A.X_UNIQUE_ID IS NULL     THEN 'NO CALLBACK RECEIVED'
           WHEN A.X_UNIQUE_ID = L.X_UNIQUE_ID THEN 'MATCHED OK'
           ELSE 'X_UNIQUE_ID MISMATCH'
       END AS MATCH_STATUS
FROM       CRM_MPM_CRM_INTEGRATION_LOG L
LEFT JOIN  CRM_MPM_CALLBACK_AUDIT_LOG  A
        ON A.X_UNIQUE_ID = L.X_UNIQUE_ID
WHERE  L.REGISTRY_ID = 23
AND    L.SENT_DATE  >= SYSDATE - 3
ORDER  BY L.LOG_ID DESC;

-- -------------------------------------------------------
-- QUERY 5: Check if REQUEST_ID is used instead of X_UNIQUE_ID
-- Sometimes APIC returns REQUEST_ID not X_UNIQUE_ID
-- -------------------------------------------------------
SELECT L.LOG_ID,
       L.X_UNIQUE_ID,
       A.REQUEST_ID,
       A.X_UNIQUE_ID                              AS CALLBACK_X_UNIQUE_ID,
       SUBSTR(A.RAW_PAYLOAD, 1, 1000)             AS RAW_PAYLOAD
FROM       CRM_MPM_CRM_INTEGRATION_LOG L
LEFT JOIN  CRM_MPM_CALLBACK_AUDIT_LOG  A
        ON A.REQUEST_ID = L.X_UNIQUE_ID  -- trying REQUEST_ID match
WHERE  L.REGISTRY_ID = 23
AND    L.SENT_DATE  >= SYSDATE - 3
ORDER  BY L.LOG_ID DESC;

-- -------------------------------------------------------
-- QUERY 6: Full raw payload of latest callback received
-- Check what identifier APIC is sending back
-- -------------------------------------------------------
SELECT SUBSTR(RAW_PAYLOAD, 1, 4000) AS FULL_RAW_PAYLOAD,
       X_UNIQUE_ID,
       REQUEST_ID,
       CHANNEL_ID,
       TO_CHAR(RECEIVED_AT,'DD-MON-YY HH24:MI:SS') AS RECEIVED_AT
FROM   CRM_MPM_CALLBACK_AUDIT_LOG
ORDER  BY AUDIT_ID DESC
FETCH FIRST 1 ROWS ONLY;
