SET DEFINE OFF

/* ============================================================================
   CRM MPM INTEGRATION — MONITORING & DIAGNOSTICS QUERIES
   Self-service troubleshooting. Run any section independently.
   ============================================================================ */


/* ============================================================================
   QUERY 1 — LIVE DASHBOARD
   Full picture of every record across all 9 services.
   Run this first every time you want to know current state.
   ============================================================================ */
SELECT
    R.SERVICE_NAME,
    L.LOG_ID,
    L.SOURCE_RECORD_ID                                       AS RECORD_KEY,
    L.ATTEMPT_NO                                             AS TRY,
    L.FINAL_STATUS,
    -- LEG 1 details
    L.HTTP_STATUS_CODE                                       AS HTTP,
    L.ACK_STATUS_CODE                                        AS ACK_STATUS,
    L.ACK_REQUEST_ID,
    L.ACK_RESPONSE_TIMESTAMP                                 AS CRM_RECEIVED_AT,
    -- LEG 2 details
    L.CRM_ENTITY_ID,
    L.CALLBACK_RESULT_CODE,
    SUBSTR(L.CALLBACK_RESULT_DESC,1,60)                      AS CALLBACK_DESC,
    -- Header sent
    L.X_UNIQUE_ID,
    -- Timing
    TO_CHAR(L.SENT_DATE,    'DD-MON HH24:MI:SS')             AS LEG1_SENT,
    TO_CHAR(L.CALLBACK_DATE,'DD-MON HH24:MI:SS')             AS LEG2_RECEIVED,
    CASE
        WHEN L.CALLBACK_DATE IS NOT NULL AND L.SENT_DATE IS NOT NULL
        THEN ROUND((L.CALLBACK_DATE - L.SENT_DATE)*86400,1)||'s'
        WHEN L.FINAL_STATUS = 'SENT'
        THEN ROUND((SYSTIMESTAMP  - L.SENT_DATE)*86400,1)||'s waiting'
        ELSE NULL
    END                                                      AS RESPONSE_TIME,
    -- Error detail
    SUBSTR(L.ERROR_MESSAGE,1,100)                            AS ERROR_MSG
FROM CRM_MPM_CRM_INTEGRATION_LOG L
JOIN CRM_MPM_API_REGISTRY         R ON R.REGISTRY_ID = L.REGISTRY_ID
ORDER BY L.LOG_ID DESC
FETCH FIRST 50 ROWS ONLY;


/* ============================================================================
   QUERY 2 — STATUS SUMMARY BY SERVICE
   Quick count of how many records are in each state per service.
   ============================================================================ */
SELECT
    R.SERVICE_NAME,
    COUNT(*)                                                  AS TOTAL,
    SUM(CASE WHEN L.FINAL_STATUS = 'SENT'             THEN 1 ELSE 0 END) AS SENT,
    SUM(CASE WHEN L.FINAL_STATUS = 'SUCCESS'          THEN 1 ELSE 0 END) AS SUCCESS,
    SUM(CASE WHEN L.FINAL_STATUS = 'FAILED'           THEN 1 ELSE 0 END) AS FAILED,
    SUM(CASE WHEN L.FINAL_STATUS = 'TIMEOUT'          THEN 1 ELSE 0 END) AS TIMEOUT,
    SUM(CASE WHEN L.FINAL_STATUS = 'VALIDATION_FAILED'THEN 1 ELSE 0 END) AS VAL_FAILED,
    SUM(CASE WHEN L.FINAL_STATUS = 'RECORD_NOT_FOUND' THEN 1 ELSE 0 END) AS NOT_FOUND,
    SUM(CASE WHEN L.FINAL_STATUS = 'DUPLICATE_RECORD' THEN 1 ELSE 0 END) AS DUPLICATE,
    SUM(CASE WHEN L.FINAL_STATUS = 'EXHAUSTED'        THEN 1 ELSE 0 END) AS EXHAUSTED
FROM CRM_MPM_CRM_INTEGRATION_LOG L
JOIN CRM_MPM_API_REGISTRY         R ON R.REGISTRY_ID = L.REGISTRY_ID
GROUP BY R.SERVICE_NAME
ORDER BY R.SERVICE_NAME;


/* ============================================================================
   QUERY 3 — FAILED RECORDS DETAIL
   Shows exactly what went wrong: which API, which error, which record.
   HTTP column tells you WHICH layer failed:
     401/403 = token/auth problem  → check CRM_MPM_API_CREDENTIALS
     400     = bad request         → check JSON payload / headers
     404     = wrong endpoint URL  → check CRM_MPM_API_REGISTRY.APIC_ENDPOINT_URL
     500/503 = APIC/CRM server err → APIC team to investigate
     null    = never reached APIC  → Oracle package error (check ERROR_MSG)
   ============================================================================ */
SELECT
    R.SERVICE_NAME,
    R.APIC_ENDPOINT_URL,
    L.LOG_ID,
    L.SOURCE_RECORD_ID                                        AS RECORD_KEY,
    L.ATTEMPT_NO,
    L.FINAL_STATUS,
    L.HTTP_STATUS_CODE                                        AS HTTP,
    L.ACK_STATUS_CODE,
    L.ACK_DESCRIPTION,
    L.ERROR_CODE,
    L.ERROR_MESSAGE,
    TO_CHAR(L.SENT_DATE,'DD-MON-YYYY HH24:MI:SS')            AS FAILED_AT,
    L.X_UNIQUE_ID                                             AS TRACE_ID
FROM CRM_MPM_CRM_INTEGRATION_LOG L
JOIN CRM_MPM_API_REGISTRY         R ON R.REGISTRY_ID = L.REGISTRY_ID
WHERE L.FINAL_STATUS IN ('FAILED','TIMEOUT','EXHAUSTED',
                          'VALIDATION_FAILED','RECORD_NOT_FOUND','DUPLICATE_RECORD')
ORDER BY L.LOG_ID DESC
FETCH FIRST 30 ROWS ONLY;


/* ============================================================================
   QUERY 4 — TOKEN AND CREDENTIAL STATUS
   Tells you if the bearer token is valid or needs refreshing.
   If TOKEN_STATUS = EXPIRED or NOT CACHED → GET_BEARER_TOKEN will fetch fresh.
   If you get 401/403 from APIC even with a valid token → wrong client_id/secret.
   ============================================================================ */
SELECT
    CRED_CODE,
    TOKEN_URL,
    CLIENT_ID,
    SCOPE,
    WALLET_PATH,
    CASE
        WHEN TOKEN_CACHE_VALUE IS NULL     THEN 'NOT CACHED — will fetch fresh'
        WHEN TOKEN_EXPIRY < SYSTIMESTAMP   THEN 'EXPIRED — will fetch fresh'
        WHEN TOKEN_EXPIRY < SYSTIMESTAMP
                           + (60/86400)   THEN 'EXPIRING SOON (<60s)'
        ELSE 'VALID until ' ||
             TO_CHAR(TOKEN_EXPIRY,'DD-MON-YYYY HH24:MI:SS')
    END                                                       AS TOKEN_STATUS,
    IS_ACTIVE
FROM CRM_MPM_API_CREDENTIALS;


/* ============================================================================
   QUERY 5 — ENDPOINT CONFIGURATION
   Shows exactly which URL and headers are being used for each service.
   If you get 404 → APIC_ENDPOINT_URL is wrong.
   If you get 400 → RECORD_TYPE_HDR or EVENT_CODE_HDR might be wrong.
   ============================================================================ */
SELECT
    SERVICE_NAME,
    OPERATION_TYPE,
    APIC_ENDPOINT_URL,
    APIC_API_VERSION,
    RECORD_TYPE_HDR,
    EVENT_CODE_HDR,
    SOURCE_VIEW,
    SOURCE_KEY_COL,
    JSON_MAPPING_NAME,
    CRED_CODE,
    IS_ACTIVE
FROM CRM_MPM_API_REGISTRY
ORDER BY SERVICE_NAME;


/* ============================================================================
   QUERY 6 — RECORDS WAITING FOR LEG 2 CALLBACK
   These are SENT but CRM has not called back yet.
   If waiting > TIMEOUT_MINUTES (30) → RUN_TIMEOUT_JOB will mark them TIMEOUT.
   ============================================================================ */
SELECT
    R.SERVICE_NAME,
    L.LOG_ID,
    L.SOURCE_RECORD_ID                                        AS RECORD_KEY,
    L.ACK_REQUEST_ID,
    L.ACK_RESPONSE_TIMESTAMP                                  AS CRM_LOGGED_AT,
    TO_CHAR(L.SENT_DATE,'DD-MON-YYYY HH24:MI:SS')            AS SENT_AT,
    ROUND((SYSTIMESTAMP - L.SENT_DATE)*1440, 1)               AS MINS_WAITING,
    R.TIMEOUT_MINUTES                                         AS TIMEOUT_AFTER_MINS,
    L.X_UNIQUE_ID                                             AS TRACE_ID
FROM CRM_MPM_CRM_INTEGRATION_LOG L
JOIN CRM_MPM_API_REGISTRY         R ON R.REGISTRY_ID = L.REGISTRY_ID
WHERE L.FINAL_STATUS = 'SENT'
ORDER BY L.SENT_DATE;


/* ============================================================================
   QUERY 7 — FULL DETAIL FOR ONE SPECIFIC LOG ROW
   Use when you have a LOG_ID and want every field.
   Replace 99999 with the actual LOG_ID.
   ============================================================================ */
SELECT
    L.LOG_ID,
    R.SERVICE_NAME,
    R.APIC_ENDPOINT_URL,
    R.RECORD_TYPE_HDR,
    R.EVENT_CODE_HDR,
    L.SOURCE_RECORD_ID,
    L.TRANSACTION_GROUP_ID,
    L.ATTEMPT_NO,
    L.FINAL_STATUS,
    -- LEG 1
    L.HTTP_STATUS_CODE,
    L.ACK_REQUEST_ID,
    L.ACK_STATUS_CODE,
    L.ACK_DESCRIPTION,
    L.ACK_RESPONSE_TIMESTAMP,
    L.X_UNIQUE_ID,
    -- LEG 2
    L.CRM_ENTITY_ID,
    L.CALLBACK_RESULT_CODE,
    L.CALLBACK_RESULT_DESC,
    L.CALLBACK_VALID_ERRORS,
    -- Error
    L.ERROR_CODE,
    L.ERROR_MESSAGE,
    -- Timing
    TO_CHAR(L.SENT_DATE,    'DD-MON-YYYY HH24:MI:SS') AS LEG1_SENT_AT,
    TO_CHAR(L.CALLBACK_DATE,'DD-MON-YYYY HH24:MI:SS') AS LEG2_RECEIVED_AT,
    TO_CHAR(L.CREATED_DATE, 'DD-MON-YYYY HH24:MI:SS') AS CREATED_AT,
    -- Payloads
    L.REQUEST_PAYLOAD,
    L.ACK_RESPONSE,
    L.CALLBACK_PAYLOAD
FROM CRM_MPM_CRM_INTEGRATION_LOG L
JOIN CRM_MPM_API_REGISTRY         R ON R.REGISTRY_ID = L.REGISTRY_ID
WHERE L.LOG_ID = 99999;  -- <-- replace with real LOG_ID


/* ============================================================================
   QUERY 8 — WATERMARK (next pickup point per service)
   Shows which LAST_UPDATE_DATE the next job run will pick up from.
   If watermark is too far in the past → many records will be picked up.
   If watermark is null/epoch → ALL records will be picked up (first run).
   ============================================================================ */
SELECT
    R.SERVICE_NAME,
    R.SOURCE_VIEW,
    TO_CHAR(W.LAST_PROCESSED_TS,'DD-MON-YYYY HH24:MI:SS')    AS NEXT_PICKUP_FROM,
    W.LAST_RUN_STATUS,
    W.LAST_RUN_RECORDS
FROM CRM_MPM_API_WATERMARK W
JOIN CRM_MPM_API_REGISTRY  R ON R.REGISTRY_ID = W.REGISTRY_ID
ORDER BY R.SERVICE_NAME;


/* ============================================================================
   QUERY 9 — RETRY ELIGIBLE RECORDS
   Records that failed/timed out and still have retries remaining.
   These will be picked up by RUN_RETRY_JOB automatically.
   ============================================================================ */
SELECT
    R.SERVICE_NAME,
    L.LOG_ID,
    L.SOURCE_RECORD_ID,
    L.FINAL_STATUS,
    L.RETRY_COUNT,
    R.MAX_RETRY_COUNT,
    L.ATTEMPT_NO,
    TO_CHAR(L.NEXT_RETRY_DATE,'DD-MON-YYYY HH24:MI:SS')      AS RETRY_AT,
    CASE
        WHEN L.NEXT_RETRY_DATE <= SYSTIMESTAMP
        THEN 'READY TO RETRY NOW'
        ELSE 'WAITING — ' ||
             ROUND((L.NEXT_RETRY_DATE - SYSTIMESTAMP)*1440,1) ||
             ' mins remaining'
    END                                                        AS RETRY_STATUS
FROM CRM_MPM_CRM_INTEGRATION_LOG L
JOIN CRM_MPM_API_REGISTRY         R ON R.REGISTRY_ID = L.REGISTRY_ID
WHERE L.FINAL_STATUS   IN ('FAILED','TIMEOUT')
  AND L.RETRY_COUNT    <  R.MAX_RETRY_COUNT
  AND L.IS_FINAL_ATTEMPT = 'N'
ORDER BY L.NEXT_RETRY_DATE;


/* ============================================================================
   QUERY 10 — SCHEDULER JOB HISTORY
   Shows when each job last ran and whether it succeeded.
   ============================================================================ */
SELECT
    RUN_ID,
    JOB_NAME,
    STATUS,
    TO_CHAR(START_TIME,'DD-MON-YYYY HH24:MI:SS')             AS STARTED,
    TO_CHAR(END_TIME,  'DD-MON-YYYY HH24:MI:SS')             AS ENDED,
    ROUND((END_TIME - START_TIME)*86400, 1)                   AS DURATION_SECS,
    RECORDS_PROCESSED,
    RECORDS_SUCCESS,
    RECORDS_FAILED,
    SUBSTR(ERROR_MESSAGE,1,150)                               AS ERROR_MSG
FROM CRM_MPM_JOB_RUN_HISTORY
ORDER BY RUN_ID DESC
FETCH FIRST 20 ROWS ONLY;
