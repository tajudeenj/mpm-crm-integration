-- =============================================================================
-- CRM INTEGRATION MANAGEMENT REPORT
-- For Oracle team front-end application (VBCS / APEX / Custom)
-- Author : ADIB EA Team (Tajudeen Jalaudin)
-- Date   : 2026-09-18
-- =============================================================================
-- CONTENTS:
--   QUERY 1 : Main management report (all services, all statuses)
--   QUERY 2 : Failed / data issues only (action needed)
--   QUERY 3 : Dashboard summary counts by service and status
--   QUERY 4 : Manual retry — update procedure
--   QUERY 5 : Service list (for dropdown filter)
--   QUERY 6 : Status list (for dropdown filter)
-- =============================================================================


-- =============================================================================
-- QUERY 1: MAIN MANAGEMENT REPORT
-- Parameters Oracle team exposes as screen filters:
--   :p_service    VARCHAR2  -- service name or NULL for all
--   :p_status     VARCHAR2  -- final status or NULL for all
--   :p_from_date  DATE      -- sent date from
--   :p_to_date    DATE      -- sent date to
--   :p_record_id  VARCHAR2  -- source record id search
-- =============================================================================
SELECT
    -- ── Identity ──────────────────────────────────────────────
    L.LOG_ID,
    R.SERVICE_NAME,
    L.ENTITY_NAME,
    L.OPERATION_TYPE,
    L.SOURCE_RECORD_ID,

    -- ── Status ────────────────────────────────────────────────
    L.FINAL_STATUS,
    L.ERROR_CODE,
    E.ERROR_CATEGORY,

    -- Business-friendly status label
    CASE L.FINAL_STATUS
        WHEN 'SUCCESS'
            THEN '✅ Synced to CRM'
        WHEN 'SENT'
            THEN '⏳ Waiting CRM response'
        WHEN 'PENDING'
            THEN '🔄 Being processed'
        WHEN 'VALIDATION_FAILED'
            THEN '⚠️ Data issue — see Failed Fields'
        WHEN 'DUPLICATE_RECORD'
            THEN 'ℹ️ Already exists in CRM'
        WHEN 'RECORD_NOT_FOUND'
            THEN '⚠️ Parent record missing in CRM'
        WHEN 'CRM_REJECTED'
            THEN '❌ CRM business rule rejected'
        WHEN 'EXHAUSTED'
            THEN '🚨 Max retries reached — manual action needed'
        WHEN 'FAILED'
            THEN '🔄 Failed — auto retry scheduled'
        WHEN 'TIMEOUT'
            THEN '🔄 Timeout — auto retry scheduled'
        ELSE L.FINAL_STATUS
    END                                         AS STATUS_LABEL,

    -- ── Actual data sent to CRM (full JSON) ───────────────────
    -- Business team reads this to see exactly what was pushed
    DBMS_LOB.SUBSTR(L.REQUEST_PAYLOAD, 4000, 1) AS DATA_SENT_TO_CRM,

    -- ── What CRM said was wrong ────────────────────────────────
    -- The specific field(s) that failed validation
    SUBSTR(L.CALLBACK_VALID_ERRORS, 1, 500)     AS FAILED_FIELDS,

    -- Human readable CRM response
    SUBSTR(L.CALLBACK_RESULT_DESC,  1, 300)     AS CRM_RESPONSE,

    -- Technical error detail
    SUBSTR(L.ERROR_MESSAGE,         1, 300)     AS ERROR_DETAIL,

    -- ── CRM Reference ─────────────────────────────────────────
    L.CRM_REFERENCE_NO,
    L.CRM_ENTITY_ID                             AS CRM_GUID,

    -- ── Dates ─────────────────────────────────────────────────
    TO_CHAR(L.SENT_DATE,      'DD-MON-YY HH24:MI') AS SENT_DATE,
    TO_CHAR(L.CALLBACK_DATE,  'DD-MON-YY HH24:MI') AS CALLBACK_DATE,
    TO_CHAR(L.UPDATED_DATE,   'DD-MON-YY HH24:MI') AS LAST_UPDATED,

    -- ── Retry info ────────────────────────────────────────────
    L.RETRY_COUNT                               AS RETRY_ATTEMPTS,
    R.MAX_RETRY_COUNT                           AS MAX_RETRIES,
    L.RETRY_COUNT || '/' || R.MAX_RETRY_COUNT   AS RETRY_PROGRESS,
    E.IS_RETRYABLE                              AS AUTO_RETRY_ELIGIBLE,
    L.MANUAL_RETRY                              AS MANUAL_RETRY_QUEUED,
    L.IS_FINAL_ATTEMPT,

    -- ── Action needed ─────────────────────────────────────────
    CASE
        WHEN L.FINAL_STATUS = 'SUCCESS'
            THEN 'No action needed'
        WHEN L.FINAL_STATUS = 'SENT'
            THEN 'Wait for CRM callback'
        WHEN L.FINAL_STATUS IN ('FAILED','TIMEOUT')
             AND E.IS_RETRYABLE = 'Y'
             AND L.RETRY_COUNT  < R.MAX_RETRY_COUNT
            THEN 'Auto retry will run at next scheduled job'
        WHEN L.FINAL_STATUS = 'VALIDATION_FAILED'
             AND L.MANUAL_RETRY = 'N'
            THEN 'Fix data in MPM or ask CRM team — then use Manual Retry'
        WHEN L.FINAL_STATUS = 'VALIDATION_FAILED'
             AND L.MANUAL_RETRY = 'Y'
            THEN 'Manual retry queued — will run at next job'
        WHEN L.FINAL_STATUS = 'DUPLICATE_RECORD'
            THEN 'No action — record already in CRM'
        WHEN L.FINAL_STATUS = 'RECORD_NOT_FOUND'
            THEN 'Push parent record first — check execution order'
        WHEN L.FINAL_STATUS = 'EXHAUSTED'
            THEN 'Investigate error — use Manual Retry after fixing'
        WHEN L.FINAL_STATUS = 'CRM_REJECTED'
            THEN 'Contact CRM team — business rule violation'
        ELSE 'Review error detail'
    END                                         AS RECOMMENDED_ACTION,

    -- ── Transaction group (for linking related records) ────────
    L.TRANSACTION_GROUP_ID,
    L.ATTEMPT_NO

FROM  CRM_MPM_CRM_INTEGRATION_LOG    L
JOIN  CRM_MPM_API_REGISTRY           R
   ON R.REGISTRY_ID  = L.REGISTRY_ID
LEFT JOIN CRM_MPM_ERROR_CODE_MASTER  E
   ON E.ERROR_CODE   = L.ERROR_CODE

WHERE 1=1
  AND (:p_service   IS NULL OR R.SERVICE_NAME    = :p_service)
  AND (:p_status    IS NULL OR L.FINAL_STATUS    = :p_status)
  AND (:p_from_date IS NULL OR L.SENT_DATE      >= :p_from_date)
  AND (:p_to_date   IS NULL OR L.SENT_DATE      <= :p_to_date + 1)
  AND (:p_record_id IS NULL OR L.SOURCE_RECORD_ID LIKE '%' || :p_record_id || '%')

ORDER BY L.LOG_ID DESC
FETCH FIRST 500 ROWS ONLY;


-- =============================================================================
-- QUERY 2: FAILED / ACTION NEEDED ONLY
-- Quick view for business team — only records needing attention
-- =============================================================================
SELECT
    L.LOG_ID,
    R.SERVICE_NAME,
    L.SOURCE_RECORD_ID,
    L.FINAL_STATUS,
    L.ERROR_CODE,

    -- Actual data sent
    DBMS_LOB.SUBSTR(L.REQUEST_PAYLOAD, 4000, 1) AS DATA_SENT_TO_CRM,

    -- What failed
    SUBSTR(L.CALLBACK_VALID_ERRORS, 1, 500)     AS FAILED_FIELDS,
    SUBSTR(L.CALLBACK_RESULT_DESC,  1, 300)     AS CRM_RESPONSE,
    SUBSTR(L.ERROR_MESSAGE,         1, 200)     AS ERROR_DETAIL,

    -- Dates
    TO_CHAR(L.SENT_DATE,     'DD-MON-YY HH24:MI') AS SENT_DATE,
    TO_CHAR(L.CALLBACK_DATE, 'DD-MON-YY HH24:MI') AS CALLBACK_DATE,

    -- Retry status
    L.RETRY_COUNT || '/' || R.MAX_RETRY_COUNT   AS RETRY_PROGRESS,
    E.IS_RETRYABLE                              AS AUTO_RETRY,
    L.MANUAL_RETRY,

    -- Action
    CASE
        WHEN L.FINAL_STATUS = 'VALIDATION_FAILED'
            THEN 'Fix data in MPM or ask CRM team to adjust validation'
        WHEN L.FINAL_STATUS = 'EXHAUSTED'
            THEN 'Max retries reached — investigate and manual retry'
        WHEN L.FINAL_STATUS = 'RECORD_NOT_FOUND'
            THEN 'Parent record missing — check if Property/Building pushed first'
        WHEN L.FINAL_STATUS = 'CRM_REJECTED'
            THEN 'CRM business rule — contact CRM team'
        WHEN L.FINAL_STATUS = 'DUPLICATE_RECORD'
            THEN 'Already in CRM — safe to ignore'
        ELSE 'Review and decide'
    END                                         AS ACTION_NEEDED

FROM  CRM_MPM_CRM_INTEGRATION_LOG    L
JOIN  CRM_MPM_API_REGISTRY           R
   ON R.REGISTRY_ID = L.REGISTRY_ID
LEFT JOIN CRM_MPM_ERROR_CODE_MASTER  E
   ON E.ERROR_CODE  = L.ERROR_CODE

WHERE L.FINAL_STATUS IN (
    'VALIDATION_FAILED',
    'EXHAUSTED',
    'RECORD_NOT_FOUND',
    'CRM_REJECTED',
    'DUPLICATE_RECORD'
)
AND L.MANUAL_RETRY = 'N'   -- exclude already queued for retry

ORDER BY
    CASE L.FINAL_STATUS
        WHEN 'EXHAUSTED'          THEN 1  -- highest priority
        WHEN 'VALIDATION_FAILED'  THEN 2
        WHEN 'RECORD_NOT_FOUND'   THEN 3
        WHEN 'CRM_REJECTED'       THEN 4
        WHEN 'DUPLICATE_RECORD'   THEN 5
        ELSE 6
    END,
    L.LOG_ID DESC;


-- =============================================================================
-- QUERY 3: DASHBOARD SUMMARY
-- Count by service and status — for summary cards on screen
-- =============================================================================
SELECT
    R.SERVICE_NAME,
    COUNT(*)                                        AS TOTAL,
    SUM(CASE WHEN L.FINAL_STATUS = 'SUCCESS'
             THEN 1 ELSE 0 END)                     AS SUCCESS,
    SUM(CASE WHEN L.FINAL_STATUS = 'SENT'
             THEN 1 ELSE 0 END)                     AS PENDING_CALLBACK,
    SUM(CASE WHEN L.FINAL_STATUS = 'VALIDATION_FAILED'
             THEN 1 ELSE 0 END)                     AS VALIDATION_FAILED,
    SUM(CASE WHEN L.FINAL_STATUS = 'DUPLICATE_RECORD'
             THEN 1 ELSE 0 END)                     AS DUPLICATE,
    SUM(CASE WHEN L.FINAL_STATUS IN ('FAILED','TIMEOUT')
             THEN 1 ELSE 0 END)                     AS AUTO_RETRY_QUEUE,
    SUM(CASE WHEN L.FINAL_STATUS = 'EXHAUSTED'
             THEN 1 ELSE 0 END)                     AS EXHAUSTED,
    SUM(CASE WHEN L.FINAL_STATUS = 'RECORD_NOT_FOUND'
             THEN 1 ELSE 0 END)                     AS PARENT_MISSING,
    -- Records needing manual action
    SUM(CASE WHEN L.FINAL_STATUS IN (
                 'VALIDATION_FAILED','EXHAUSTED',
                 'RECORD_NOT_FOUND','CRM_REJECTED')
             AND L.MANUAL_RETRY = 'N'
             THEN 1 ELSE 0 END)                     AS ACTION_NEEDED,
    -- Last activity
    TO_CHAR(MAX(L.SENT_DATE),'DD-MON-YY HH24:MI')  AS LAST_SENT,
    TO_CHAR(MAX(L.CALLBACK_DATE),'DD-MON-YY HH24:MI') AS LAST_CALLBACK

FROM  CRM_MPM_CRM_INTEGRATION_LOG L
JOIN  CRM_MPM_API_REGISTRY        R
   ON R.REGISTRY_ID = L.REGISTRY_ID

-- Optional: filter by date range
-- WHERE L.SENT_DATE >= SYSDATE - 30

GROUP BY R.SERVICE_NAME
ORDER BY ACTION_NEEDED DESC, R.SERVICE_NAME;


-- =============================================================================
-- QUERY 4: MANUAL RETRY PROCEDURE
-- Oracle team front-end calls this when business approves retry
-- Pass LOG_ID of the record to retry
-- =============================================================================
/*
PROCEDURE CRM_MANUAL_RETRY (p_log_id IN NUMBER) IS
BEGIN
    UPDATE CRM_MPM_CRM_INTEGRATION_LOG
    SET    MANUAL_RETRY     = 'Y',
           FINAL_STATUS     = 'FAILED',     -- re-open for retry job
           IS_FINAL_ATTEMPT = 'N',
           RETRY_COUNT      = 0,            -- reset counter
           ERROR_MESSAGE    = SUBSTR(ERROR_MESSAGE, 1, 3800) ||
                              ' | Manual retry: ' ||
                              TO_CHAR(SYSDATE,'DD-MON-YY HH24:MI') ||
                              ' by ' || USER,
           UPDATED_DATE     = SYSTIMESTAMP
    WHERE  LOG_ID       = p_log_id
    AND    FINAL_STATUS IN (
               'VALIDATION_FAILED',
               'CRM_REJECTED',
               'EXHAUSTED',
               'RECORD_NOT_FOUND',
               'FAILED'
           );

    IF SQL%ROWCOUNT = 0 THEN
        RAISE_APPLICATION_ERROR(-20001,
            'Record not found or not eligible for retry. LOG_ID=' || p_log_id);
    END IF;

    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END CRM_MANUAL_RETRY;
*/

-- Quick manual retry (run directly in SQL):
/*
UPDATE CRM_MPM_CRM_INTEGRATION_LOG
SET    MANUAL_RETRY     = 'Y',
       FINAL_STATUS     = 'FAILED',
       IS_FINAL_ATTEMPT = 'N',
       RETRY_COUNT      = 0,
       UPDATED_DATE     = SYSTIMESTAMP
WHERE  LOG_ID = <paste_log_id_here>;
COMMIT;
*/


-- =============================================================================
-- QUERY 5: SERVICE LIST — for screen dropdown
-- =============================================================================
SELECT DISTINCT
    R.SERVICE_NAME,
    R.ENTITY_NAME,
    R.OPERATION_TYPE,
    R.IS_ACTIVE,
    COUNT(L.LOG_ID)                             AS TOTAL_RECORDS,
    SUM(CASE WHEN L.FINAL_STATUS = 'SUCCESS'
             THEN 1 ELSE 0 END)                 AS SUCCESS_COUNT,
    SUM(CASE WHEN L.FINAL_STATUS IN (
                 'VALIDATION_FAILED','EXHAUSTED',
                 'RECORD_NOT_FOUND','CRM_REJECTED')
             AND NVL(L.MANUAL_RETRY,'N') = 'N'
             THEN 1 ELSE 0 END)                 AS ACTION_NEEDED
FROM  CRM_MPM_API_REGISTRY           R
LEFT JOIN CRM_MPM_CRM_INTEGRATION_LOG L
       ON L.REGISTRY_ID = R.REGISTRY_ID
WHERE R.IS_ACTIVE = 'Y'
GROUP BY R.SERVICE_NAME, R.ENTITY_NAME,
         R.OPERATION_TYPE, R.IS_ACTIVE
ORDER BY R.SERVICE_NAME;


-- =============================================================================
-- QUERY 6: STATUS LIST — for screen dropdown
-- =============================================================================
SELECT FINAL_STATUS,
       COUNT(*)  AS RECORD_COUNT,
       CASE FINAL_STATUS
           WHEN 'SUCCESS'          THEN '✅ Synced to CRM'
           WHEN 'SENT'             THEN '⏳ Waiting callback'
           WHEN 'VALIDATION_FAILED'THEN '⚠️ Data issue'
           WHEN 'DUPLICATE_RECORD' THEN 'ℹ️ Already in CRM'
           WHEN 'RECORD_NOT_FOUND' THEN '⚠️ Parent missing'
           WHEN 'CRM_REJECTED'     THEN '❌ CRM rejected'
           WHEN 'EXHAUSTED'        THEN '🚨 Max retries reached'
           WHEN 'FAILED'           THEN '🔄 Auto retry queued'
           WHEN 'TIMEOUT'          THEN '🔄 Timeout — retrying'
           WHEN 'PENDING'          THEN '🔄 In progress'
           ELSE FINAL_STATUS
       END       AS STATUS_LABEL
FROM  CRM_MPM_CRM_INTEGRATION_LOG
GROUP BY FINAL_STATUS
ORDER BY RECORD_COUNT DESC;


-- =============================================================================
-- QUICK TEST — run this to verify report works
-- =============================================================================
/*
-- Test Query 1 with no filters (show all)
SELECT COUNT(*) FROM CRM_MPM_CRM_INTEGRATION_LOG;

-- Test Query 3 dashboard
SELECT R.SERVICE_NAME, COUNT(*), MAX(L.FINAL_STATUS)
FROM CRM_MPM_CRM_INTEGRATION_LOG L
JOIN CRM_MPM_API_REGISTRY        R ON R.REGISTRY_ID = L.REGISTRY_ID
GROUP BY R.SERVICE_NAME
ORDER BY R.SERVICE_NAME;
*/
