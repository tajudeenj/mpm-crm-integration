-- =============================================================================
-- ADIB MPM Properties -- CRM xRM Integration
-- Supporting & Diagnostic Queries
-- Author  : Tajudeen Jalaudin -- Senior Solution Architect, ADIB
-- Updated : 23 September 2026
-- Run in  : SQL Developer / SQL*Plus
-- =============================================================================

SET LINESIZE 200
SET PAGESIZE 100

-- =============================================================================
-- 1. ERROR TRIAGE -- Priority view of all active failures
--    Run this first to know which errors to fix
-- =============================================================================
PROMPT === 1. ERROR TRIAGE ===
SELECT
    CASE
        WHEN L.FINAL_STATUS IN ('EXHAUSTED','VALIDATION_FAILED','CRM_REJECTED')
             AND NVL(E.IS_RETRYABLE,'N') = 'N'
            THEN '1-CRITICAL'
        WHEN L.FINAL_STATUS IN ('EXHAUSTED','VALIDATION_FAILED','CRM_REJECTED')
             AND NVL(E.IS_RETRYABLE,'N') = 'Y'
            THEN '2-MANUAL'
        ELSE '3-AUTO'
    END                                                     AS PRIORITY,
    L.FINAL_STATUS,
    NVL(L.ERROR_CODE,'(none)')                              AS ERROR_CODE,
    NVL(E.ERROR_DESCRIPTION,'Not in Error Master')          AS ERROR_DESCRIPTION,
    NVL(E.IS_RETRYABLE,'N')                                 AS IS_RETRYABLE,
    COUNT(*)                                                 AS RECORD_COUNT,
    COUNT(DISTINCT L.REGISTRY_ID)                           AS SERVICES_AFFECTED,
    TO_CHAR(MIN(L.CREATED_DATE),'DD-MON-YY HH24:MI')       AS FIRST_OCCURRENCE,
    TO_CHAR(MAX(L.UPDATED_DATE),'DD-MON-YY HH24:MI')       AS LAST_OCCURRENCE
FROM   CRM_MPM_CRM_INTEGRATION_LOG L
LEFT   JOIN CRM_MPM_ERROR_CODE_MASTER E ON E.ERROR_CODE = L.ERROR_CODE
WHERE  L.FINAL_STATUS NOT IN ('SUCCESS','ACK_OK','SENT','RESOLVED')
GROUP  BY
    L.FINAL_STATUS, L.ERROR_CODE, E.ERROR_DESCRIPTION, E.IS_RETRYABLE
ORDER  BY
    CASE L.FINAL_STATUS
        WHEN 'EXHAUSTED'          THEN 1
        WHEN 'VALIDATION_FAILED'  THEN 1
        WHEN 'CRM_REJECTED'       THEN 1
        WHEN 'FAILED'             THEN 2
        ELSE 3
    END,
    COUNT(*) DESC;


-- =============================================================================
-- 2. DASHBOARD -- Summary counts per service
-- =============================================================================
PROMPT === 2. DASHBOARD ===
SELECT
    R.SERVICE_NAME,
    COUNT(*)                                                        AS TOTAL,
    SUM(CASE WHEN L.FINAL_STATUS='SUCCESS'           THEN 1 END)   AS SUCCESS,
    SUM(CASE WHEN L.FINAL_STATUS='SENT'              THEN 1 END)   AS PENDING,
    SUM(CASE WHEN L.FINAL_STATUS IN
        ('FAILED','TIMEOUT')                         THEN 1 END)   AS AUTO_RETRY,
    SUM(CASE WHEN L.FINAL_STATUS='EXHAUSTED'         THEN 1 END)   AS EXHAUSTED,
    SUM(CASE WHEN L.FINAL_STATUS='VALIDATION_FAILED' THEN 1 END)   AS VAL_FAILED,
    SUM(CASE WHEN L.FINAL_STATUS='DUPLICATE_RECORD'  THEN 1 END)   AS DUPLICATE,
    SUM(CASE WHEN L.FINAL_STATUS='RECORD_NOT_FOUND'  THEN 1 END)   AS PARENT_MISSING,
    SUM(CASE WHEN L.FINAL_STATUS IN
        ('VALIDATION_FAILED','EXHAUSTED',
         'RECORD_NOT_FOUND','CRM_REJECTED')
        AND NVL(L.MANUAL_RETRY,'N')='N'              THEN 1 END)   AS ACTION_NEEDED,
    TO_CHAR(MAX(L.SENT_DATE),'DD-MON-YY HH24:MI')                 AS LAST_SENT
FROM   CRM_MPM_CRM_INTEGRATION_LOG L
JOIN   CRM_MPM_API_REGISTRY R ON R.REGISTRY_ID = L.REGISTRY_ID
GROUP  BY R.SERVICE_NAME
ORDER  BY ACTION_NEEDED DESC NULLS LAST, R.SERVICE_NAME;


-- =============================================================================
-- 3. ACTION NEEDED -- Records requiring manual intervention
--    Excludes records already resolved by a later SUCCESS entry
-- =============================================================================
PROMPT === 3. ACTION NEEDED ===
SELECT
    L.LOG_ID,
    R.SERVICE_NAME,
    L.SOURCE_RECORD_ID,
    L.FINAL_STATUS,
    L.ERROR_CODE,
    SUBSTR(L.ERROR_MESSAGE,1,200)                           AS ERROR_MESSAGE,
    SUBSTR(L.CALLBACK_VALID_ERRORS,1,200)                   AS FAILED_FIELDS,
    TO_CHAR(L.SENT_DATE,    'DD-MON-YY HH24:MI')           AS SENT_DATE,
    TO_CHAR(L.CALLBACK_DATE,'DD-MON-YY HH24:MI')           AS CALLBACK_DATE,
    L.RETRY_COUNT||'/'||R.MAX_RETRY_COUNT                   AS RETRY,
    CASE L.FINAL_STATUS
        WHEN 'VALIDATION_FAILED' THEN 'Fix data in MPM'
        WHEN 'EXHAUSTED'         THEN 'Max retries -- investigate'
        WHEN 'RECORD_NOT_FOUND'  THEN 'Push parent first'
        WHEN 'CRM_REJECTED'      THEN 'Contact CRM team'
        ELSE 'Review error'
    END                                                     AS ACTION
FROM   CRM_MPM_CRM_INTEGRATION_LOG L
JOIN   CRM_MPM_API_REGISTRY R ON R.REGISTRY_ID = L.REGISTRY_ID
WHERE  L.FINAL_STATUS IN
       ('VALIDATION_FAILED','EXHAUSTED','RECORD_NOT_FOUND','CRM_REJECTED','DUPLICATE_RECORD')
AND    NVL(L.MANUAL_RETRY,'N') = 'N'
AND    NOT EXISTS (
           SELECT 1
           FROM   CRM_MPM_CRM_INTEGRATION_LOG S
           WHERE  S.SOURCE_RECORD_ID = L.SOURCE_RECORD_ID
           AND    S.REGISTRY_ID      = L.REGISTRY_ID
           AND    S.FINAL_STATUS     = 'SUCCESS'
       )
ORDER  BY
    CASE L.FINAL_STATUS
        WHEN 'EXHAUSTED'         THEN 1
        WHEN 'VALIDATION_FAILED' THEN 2
        WHEN 'RECORD_NOT_FOUND'  THEN 3
        WHEN 'CRM_REJECTED'      THEN 4
        ELSE 5
    END,
    L.LOG_ID DESC;


-- =============================================================================
-- 4. RETRY QUEUE -- Records flagged for manual retry
-- =============================================================================
PROMPT === 4. RETRY QUEUE ===
SELECT
    L.LOG_ID,
    R.SERVICE_NAME,
    L.SOURCE_RECORD_ID,
    L.FINAL_STATUS,
    SUBSTR(L.ERROR_MESSAGE,1,150)                           AS ERROR_MESSAGE,
    TO_CHAR(L.SENT_DATE,   'DD-MON-YY HH24:MI')           AS SENT_DATE,
    TO_CHAR(L.UPDATED_DATE,'DD-MON-YY HH24:MI')           AS RETRY_QUEUED_AT,
    L.RETRY_COUNT||'/'||R.MAX_RETRY_COUNT                   AS RETRY_PROGRESS
FROM   CRM_MPM_CRM_INTEGRATION_LOG L
JOIN   CRM_MPM_API_REGISTRY R ON R.REGISTRY_ID = L.REGISTRY_ID
WHERE  L.MANUAL_RETRY = 'Y'
AND    L.FINAL_STATUS = 'FAILED'
ORDER  BY L.LOG_ID DESC;


-- =============================================================================
-- 5. FIND ROOT CAUSE OF A SPECIFIC FAILED RECORD
--    Replace :source_record_id with actual key value
-- =============================================================================
PROMPT === 5. RECORD HISTORY (replace value below) ===
SELECT
    L.LOG_ID,
    R.SERVICE_NAME,
    L.FINAL_STATUS,
    L.ERROR_CODE,
    SUBSTR(L.ERROR_MESSAGE,1,300)                           AS ERROR_MESSAGE,
    L.RETRY_COUNT,
    NVL(L.MANUAL_RETRY,'N')                                AS MANUAL_RETRY,
    L.ATTEMPT_NO,
    L.ACK_STATUS_CODE,
    TO_CHAR(L.SENT_DATE,    'DD-MON-YY HH24:MI')           AS SENT,
    TO_CHAR(L.CALLBACK_DATE,'DD-MON-YY HH24:MI')           AS CALLBACK,
    SUBSTR(L.CALLBACK_VALID_ERRORS,1,300)                   AS FAILED_FIELDS,
    CASE
        WHEN NVL(L.MANUAL_RETRY,'N') = 'Y'
            THEN 'MANUAL RETRY'
        WHEN NVL(L.ATTEMPT_NO,1) = 1 AND NVL(L.RETRY_COUNT,0) = 0
            THEN 'OUTBOUND JOB'
        WHEN NVL(L.RETRY_COUNT,0) > 0
            THEN 'RETRY JOB (x'||L.RETRY_COUNT||')'
        WHEN L.FINAL_STATUS = 'TIMEOUT'
            THEN 'TIMEOUT JOB'
        ELSE 'OUTBOUND JOB'
    END                                                     AS EXECUTED_BY
FROM   CRM_MPM_CRM_INTEGRATION_LOG L
JOIN   CRM_MPM_API_REGISTRY R ON R.REGISTRY_ID = L.REGISTRY_ID
WHERE  L.SOURCE_RECORD_ID = '&source_record_id'
ORDER  BY L.LOG_ID DESC;


-- =============================================================================
-- 6. STALE FAILED RECORDS -- Already succeeded but old entry still sitting
--    Safe to resolve these
-- =============================================================================
PROMPT === 6. STALE FAILED RECORDS (already have SUCCESS) ===
SELECT
    L.LOG_ID,
    R.SERVICE_NAME,
    L.SOURCE_RECORD_ID,
    L.FINAL_STATUS,
    L.ERROR_CODE,
    TO_CHAR(L.UPDATED_DATE,'DD-MON-YY HH24:MI')           AS UPDATED
FROM   CRM_MPM_CRM_INTEGRATION_LOG L
JOIN   CRM_MPM_API_REGISTRY R ON R.REGISTRY_ID = L.REGISTRY_ID
WHERE  NVL(L.MANUAL_RETRY,'N') = 'Y'
AND    L.FINAL_STATUS           = 'FAILED'
AND    EXISTS (
           SELECT 1
           FROM   CRM_MPM_CRM_INTEGRATION_LOG S
           WHERE  S.SOURCE_RECORD_ID = L.SOURCE_RECORD_ID
           AND    S.REGISTRY_ID      = L.REGISTRY_ID
           AND    S.FINAL_STATUS     = 'SUCCESS'
       )
ORDER  BY L.LOG_ID DESC;


-- =============================================================================
-- 7. BULK RESOLVE STALE RECORDS -- Run after verifying Query 6
-- =============================================================================
PROMPT === 7. BULK RESOLVE STALE (uncomment to run) ===
/*
UPDATE CRM_MPM_CRM_INTEGRATION_LOG L
SET    FINAL_STATUS  = 'RESOLVED',
       UPDATED_DATE  = SYSTIMESTAMP,
       ERROR_MESSAGE = SUBSTR(NVL(ERROR_MESSAGE,''),1,3800)
                       ||' Auto-resolved: SUCCESS exists. '
                       ||TO_CHAR(SYSDATE,'DD-MON-YY HH24:MI')
WHERE  NVL(MANUAL_RETRY,'N') = 'Y'
AND    FINAL_STATUS           = 'FAILED'
AND    EXISTS (
           SELECT 1
           FROM   CRM_MPM_CRM_INTEGRATION_LOG S
           WHERE  S.SOURCE_RECORD_ID = L.SOURCE_RECORD_ID
           AND    S.REGISTRY_ID      = L.REGISTRY_ID
           AND    S.FINAL_STATUS     = 'SUCCESS'
       );
COMMIT;
*/


-- =============================================================================
-- 8. CALLBACK AUDIT -- Recent callbacks from CRM
--    CB_0000 = processed OK, CB_1002 = no matching log entry
-- =============================================================================
PROMPT === 8. CALLBACK AUDIT (last 100) ===
SELECT
    A.AUDIT_ID,
    TO_CHAR(A.RECEIVED_AT,'DD-MON-YY HH24:MI:SS')         AS RECEIVED_AT,
    A.SERVICE_NAME,
    A.X_UNIQUE_ID,
    A.CHANNEL_ID,
    A.STATUS_CODE_SENT,
    SUBSTR(A.DESCRIPTION_SENT,1,200)                       AS DESCRIPTION_SENT
FROM   CRM_MPM_CALLBACK_AUDIT_LOG A
ORDER  BY A.AUDIT_ID DESC
FETCH  FIRST 100 ROWS ONLY;


-- =============================================================================
-- 9. ORPHAN CALLBACKS -- CB_1002 -- no matching log entry found
--    These are callbacks CRM sent but Oracle could not match
-- =============================================================================
PROMPT === 9. ORPHAN CALLBACKS (CB_1002) ===
SELECT
    A.AUDIT_ID,
    TO_CHAR(A.RECEIVED_AT,'DD-MON-YY HH24:MI:SS')         AS RECEIVED_AT,
    A.SERVICE_NAME,
    A.X_UNIQUE_ID,
    A.REQUEST_ID,
    SUBSTR(A.DESCRIPTION_SENT,1,300)                       AS DESCRIPTION_SENT,
    SUBSTR(A.RAW_PAYLOAD,1,200)                            AS RAW_PAYLOAD
FROM   CRM_MPM_CALLBACK_AUDIT_LOG A
WHERE  A.STATUS_CODE_SENT = 'CB_1002'
ORDER  BY A.AUDIT_ID DESC;


-- =============================================================================
-- 10. SCHEDULER STATUS -- CRM_MPM jobs only
-- =============================================================================
PROMPT === 10. SCHEDULER STATUS ===
SELECT
    JOB_NAME,
    ENABLED,
    STATE,
    TO_CHAR(LAST_START_DATE,'DD-MON-YY HH24:MI')          AS LAST_RUN,
    TO_CHAR(NEXT_RUN_DATE,  'DD-MON-YY HH24:MI')          AS NEXT_RUN,
    RUN_COUNT,
    FAILURE_COUNT,
    REPEAT_INTERVAL
FROM   USER_SCHEDULER_JOBS
WHERE  JOB_NAME LIKE 'CRM_MPM%'
ORDER  BY JOB_NAME;


-- =============================================================================
-- 11. WATERMARK STATUS -- Last processed timestamp per service
-- =============================================================================
PROMPT === 11. WATERMARK STATUS ===
SELECT
    R.SERVICE_NAME,
    TO_CHAR(W.LAST_PROCESSED_TS,'DD-MON-YY HH24:MI:SS')   AS LAST_PROCESSED,
    W.LAST_RUN_STATUS,
    W.LAST_RUN_RECORDS,
    TO_CHAR(W.UPDATED_DATE,'DD-MON-YY HH24:MI')           AS UPDATED_DATE
FROM   CRM_MPM_API_WATERMARK W
JOIN   CRM_MPM_API_REGISTRY R ON R.REGISTRY_ID = W.REGISTRY_ID
ORDER  BY R.SERVICE_NAME;


-- =============================================================================
-- 12. ERROR CODE MASTER -- All registered error codes
-- =============================================================================
PROMPT === 12. ERROR CODE MASTER ===
SELECT
    ERROR_CODE,
    IS_RETRYABLE,
    ERROR_DESCRIPTION,
    IS_ACTIVE
FROM   CRM_MPM_ERROR_CODE_MASTER
ORDER  BY IS_RETRYABLE DESC, ERROR_CODE;


-- =============================================================================
-- 13. 9999 FAILURES -- Records that got status=9999 from CRM
--    All should be FINAL_STATUS=FAILED (retryable) after latest package fix
-- =============================================================================
PROMPT === 13. STATUS 9999 FAILURES ===
SELECT
    L.LOG_ID,
    R.SERVICE_NAME,
    L.SOURCE_RECORD_ID,
    L.FINAL_STATUS,
    L.ERROR_CODE,
    L.ACK_STATUS_CODE,
    SUBSTR(L.ERROR_MESSAGE,1,200)                          AS ERROR_MESSAGE,
    TO_CHAR(L.SENT_DATE,'DD-MON-YY HH24:MI')             AS SENT_DATE
FROM   CRM_MPM_CRM_INTEGRATION_LOG L
JOIN   CRM_MPM_API_REGISTRY R ON R.REGISTRY_ID = L.REGISTRY_ID
WHERE  L.ACK_STATUS_CODE = '9999'
ORDER  BY L.LOG_ID DESC;


-- =============================================================================
-- 14. PACKAGE STATUS -- Verify package compiled clean
-- =============================================================================
PROMPT === 14. PACKAGE STATUS ===
SELECT
    OBJECT_NAME,
    OBJECT_TYPE,
    STATUS,
    TO_CHAR(LAST_DDL_TIME,'DD-MON-YY HH24:MI')            AS LAST_COMPILED
FROM   USER_OBJECTS
WHERE  OBJECT_NAME = 'PKG_CRM_INTEGRATION'
ORDER  BY OBJECT_TYPE;

-- Show any errors if INVALID
SELECT  LINE, POSITION, TEXT
FROM    USER_ERRORS
WHERE   NAME = 'PKG_CRM_INTEGRATION'
ORDER   BY SEQUENCE;


-- =============================================================================
-- 15. TODAYS ACTIVITY SUMMARY
-- =============================================================================
PROMPT === 15. TODAY SUMMARY ===
SELECT
    R.SERVICE_NAME,
    L.FINAL_STATUS,
    COUNT(*)                                               AS COUNT
FROM   CRM_MPM_CRM_INTEGRATION_LOG L
JOIN   CRM_MPM_API_REGISTRY R ON R.REGISTRY_ID = L.REGISTRY_ID
WHERE  TRUNC(L.CREATED_DATE) = TRUNC(SYSDATE)
GROUP  BY R.SERVICE_NAME, L.FINAL_STATUS
ORDER  BY R.SERVICE_NAME, L.FINAL_STATUS;

PROMPT === END OF SUPPORTING QUERIES ===
