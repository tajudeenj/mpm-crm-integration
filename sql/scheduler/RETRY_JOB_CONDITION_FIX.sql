-- =============================================================================
-- RETRY JOB CONDITION FIX
-- Adds IS_RETRYABLE check so RUN_RETRY_JOB only retries transient errors
-- not permanent business failures (VALIDATION_FAILED, DUPLICATE_RECORD etc.)
-- Author : ADIB EA Team (Tajudeen Jalaudin)
-- Date   : 2026-09-18
-- =============================================================================

SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED


-- =============================================================================
-- PART 1: VERIFY / FIX IS_RETRYABLE VALUES IN ERROR CODE MASTER
-- Ensure every error code has the correct retryable flag
-- =============================================================================

-- Transient errors = retryable (Y) -- network/auth/timeout issues
-- Business errors  = not retryable (N) -- data issues, fix data first

MERGE INTO CRM_MPM_ERROR_CODE_MASTER t
USING (
    SELECT 'CONN_FAILED'         AS ERROR_CODE, 'NETWORK'  AS ERROR_CATEGORY,
           'Connection failed to APIC'          AS ERROR_DESCRIPTION, 'Y' AS IS_RETRYABLE FROM DUAL UNION ALL
    SELECT 'TIMEOUT',             'NETWORK',
           'No callback received within timeout window',              'Y' FROM DUAL UNION ALL
    SELECT 'APIC_ERROR',          'APIC',
           'APIC gateway error',                                      'Y' FROM DUAL UNION ALL
    SELECT 'AUTH_FAILED',         'APIC',
           'HTTP 401/403 authentication failed',                      'Y' FROM DUAL UNION ALL
    SELECT 'AUTH_OR_HEADER_ERROR','APIC',
           'Authorization or header error from APIC LEG1',            'Y' FROM DUAL UNION ALL
    SELECT 'UNKNOWN_ERROR',       'SYSTEM',
           'Unexpected/unclassified error',                           'Y' FROM DUAL UNION ALL
    SELECT 'VALIDATION_ERROR',    'CRM',
           'APIC-level validation error (HTTP 4xx)',                  'N' FROM DUAL UNION ALL
    SELECT 'VALIDATION_FAILED',   'CRM',
           'CRM D365 validation failed — fix data first',             'N' FROM DUAL UNION ALL
    SELECT 'DUPLICATE_RECORD',    'CRM',
           'Record already exists in CRM D365',                       'N' FROM DUAL UNION ALL
    SELECT 'RECORD_NOT_FOUND',    'CRM',
           'Record not found in CRM D365',                            'N' FROM DUAL UNION ALL
    SELECT 'CRM_REJECTED',        'CRM',
           'CRM rejected the record',                                 'N' FROM DUAL UNION ALL
    SELECT 'SUCCESS',             'OK',
           'Processed successfully',                                  'N' FROM DUAL UNION ALL
    SELECT 'ACK_OK',              'OK',
           'APIC acknowledged OK',                                    'N' FROM DUAL UNION ALL
    SELECT 'ALREADY_PROCESSED',   'OK',
           'Already processed — duplicate submission',                'N' FROM DUAL UNION ALL
    SELECT 'EXHAUSTED',           'SYSTEM',
           'Maximum retry attempts exhausted',                        'N' FROM DUAL UNION ALL
    SELECT 'CB_0000',             'CALLBACK',
           'Callback processed successfully',                         'N' FROM DUAL UNION ALL
    SELECT 'CB_1001',             'CALLBACK',
           'Callback — unknown service name',                         'N' FROM DUAL UNION ALL
    SELECT 'CB_1002',             'CALLBACK',
           'Callback — no matching log entry',                        'N' FROM DUAL UNION ALL
    SELECT 'CB_1003',             'CALLBACK',
           'Callback — unhandled exception',                          'N' FROM DUAL
) s ON (t.ERROR_CODE = s.ERROR_CODE)
WHEN MATCHED THEN UPDATE SET
    t.IS_RETRYABLE      = s.IS_RETRYABLE,
    t.ERROR_DESCRIPTION = s.ERROR_DESCRIPTION,
    t.ERROR_CATEGORY    = s.ERROR_CATEGORY
WHEN NOT MATCHED THEN INSERT
    (ERROR_CODE, ERROR_CATEGORY, ERROR_DESCRIPTION, IS_RETRYABLE)
VALUES
    (s.ERROR_CODE, s.ERROR_CATEGORY, s.ERROR_DESCRIPTION, s.IS_RETRYABLE);

COMMIT;

DBMS_OUTPUT.PUT_LINE('✅ Error code master updated');

-- Verify
SELECT ERROR_CODE,
       ERROR_CATEGORY,
       IS_RETRYABLE,
       ERROR_DESCRIPTION
FROM   CRM_MPM_ERROR_CODE_MASTER
ORDER BY IS_RETRYABLE DESC, ERROR_CODE;


-- =============================================================================
-- PART 2: PACKAGE CHANGE — RUN_RETRY_JOB
-- Add IS_RETRYABLE condition to retry cursor
-- Find this cursor in PKG_CRM_INTEGRATION body and apply the change below
-- =============================================================================

-- BEFORE (current code in RUN_RETRY_JOB):
-- ─────────────────────────────────────────
--     FOR rec IN (
--         SELECT L.LOG_ID, L.REGISTRY_ID, L.SOURCE_RECORD_ID,
--                L.RETRY_COUNT, L.TRANSACTION_GROUP_ID, L.ATTEMPT_NO,
--                R.MAX_RETRY_COUNT, R.RETRY_INTERVAL_MINUTES
--         FROM CRM_MPM_CRM_INTEGRATION_LOG L
--         JOIN CRM_MPM_API_REGISTRY        R ON R.REGISTRY_ID = L.REGISTRY_ID
--         WHERE L.FINAL_STATUS     IN ('FAILED','TIMEOUT')
--           AND L.RETRY_COUNT      <  R.MAX_RETRY_COUNT
--           AND L.IS_FINAL_ATTEMPT =  'N'
--           AND (L.NEXT_RETRY_DATE IS NULL OR L.NEXT_RETRY_DATE <= SYSTIMESTAMP)
--           AND R.IS_ACTIVE = 'Y'
--     ) LOOP

-- AFTER (add IS_RETRYABLE join):
-- ─────────────────────────────────────────
--     FOR rec IN (
--         SELECT L.LOG_ID, L.REGISTRY_ID, L.SOURCE_RECORD_ID,
--                L.RETRY_COUNT, L.TRANSACTION_GROUP_ID, L.ATTEMPT_NO,
--                R.MAX_RETRY_COUNT, R.RETRY_INTERVAL_MINUTES
--         FROM CRM_MPM_CRM_INTEGRATION_LOG L
--         JOIN CRM_MPM_API_REGISTRY        R ON R.REGISTRY_ID = L.REGISTRY_ID
--         WHERE L.FINAL_STATUS     IN ('FAILED','TIMEOUT')
--           AND L.RETRY_COUNT      <  R.MAX_RETRY_COUNT
--           AND L.IS_FINAL_ATTEMPT =  'N'
--           AND (L.NEXT_RETRY_DATE IS NULL OR L.NEXT_RETRY_DATE <= SYSTIMESTAMP)
--           AND R.IS_ACTIVE        =  'Y'
--           -- KEY FIX: only retry transient errors, not permanent business failures
--           AND EXISTS (
--               SELECT 1
--               FROM   CRM_MPM_ERROR_CODE_MASTER e
--               WHERE  e.ERROR_CODE   = L.ERROR_CODE
--               AND    e.IS_RETRYABLE = 'Y'
--           )
--     ) LOOP

DBMS_OUTPUT.PUT_LINE('ℹ️  Apply the cursor change above to RUN_RETRY_JOB in package body');


-- =============================================================================
-- PART 3: ALSO FIX RUN_TIMEOUT_JOB
-- When timeout marks a record — only set IS_FINAL_ATTEMPT=Y if not retryable
-- Current code always moves to EXHAUSTED regardless
-- Add IS_RETRYABLE check before setting EXHAUSTED
-- =============================================================================

-- BEFORE (in RUN_TIMEOUT_JOB):
-- ─────────────────────────────────────────
--     IF v_retry_count >= v_max_retry THEN
--         UPDATE CRM_MPM_CRM_INTEGRATION_LOG
--         SET FINAL_STATUS = 'EXHAUSTED', ERROR_CODE = 'EXHAUSTED'
--         WHERE LOG_ID = v_log_id;
--     END IF;

-- AFTER:
-- ─────────────────────────────────────────
--     IF v_retry_count >= v_max_retry THEN
--         UPDATE CRM_MPM_CRM_INTEGRATION_LOG
--         SET FINAL_STATUS     = 'EXHAUSTED',
--             ERROR_CODE       = 'EXHAUSTED',
--             IS_FINAL_ATTEMPT = 'Y'
--         WHERE LOG_ID = v_log_id;
--     END IF;
--     -- No change needed here -- TIMEOUT is already IS_RETRYABLE='Y'
--     -- so RUN_RETRY_JOB will pick it up on next run automatically

DBMS_OUTPUT.PUT_LINE('ℹ️  RUN_TIMEOUT_JOB change documented above');


-- =============================================================================
-- PART 4: VERIFY — CHECK CURRENT FAILED RECORDS AND THEIR RETRYABLE STATUS
-- Run this after applying the package change to see what will and won't retry
-- =============================================================================
SELECT
    L.LOG_ID,
    R.SERVICE_NAME,
    L.SOURCE_RECORD_ID,
    L.FINAL_STATUS,
    L.ERROR_CODE,
    E.IS_RETRYABLE,
    L.RETRY_COUNT,
    R.MAX_RETRY_COUNT,
    L.IS_FINAL_ATTEMPT,
    TO_CHAR(L.SENT_DATE, 'DD-MON-YY HH24:MI') AS SENT_DATE,
    SUBSTR(L.ERROR_MESSAGE, 1, 80)             AS ERROR_MSG
FROM CRM_MPM_CRM_INTEGRATION_LOG   L
JOIN CRM_MPM_API_REGISTRY          R ON R.REGISTRY_ID = L.REGISTRY_ID
LEFT JOIN CRM_MPM_ERROR_CODE_MASTER E ON E.ERROR_CODE  = L.ERROR_CODE
WHERE L.FINAL_STATUS IN ('FAILED', 'TIMEOUT', 'VALIDATION_FAILED',
                         'DUPLICATE_RECORD', 'RECORD_NOT_FOUND')
ORDER BY L.LOG_ID DESC
FETCH FIRST 20 ROWS ONLY;


-- =============================================================================
-- PART 5: SUMMARY — WHAT RETRIES AND WHAT DOESN'T
-- =============================================================================
-- ERROR_CODE          IS_RETRYABLE   ACTION
-- ─────────────────── ────────────── ─────────────────────────────────────
-- CONN_FAILED         Y              Retried — network issue, transient
-- TIMEOUT             Y              Retried — may succeed next time
-- APIC_ERROR          Y              Retried — gateway issue, transient
-- AUTH_FAILED         Y              Retried — token may have expired
-- AUTH_OR_HEADER_ERROR Y             Retried — APIC header issue
-- UNKNOWN_ERROR       Y              Retried — unknown, worth trying again
-- ─────────────────── ────────────── ─────────────────────────────────────
-- VALIDATION_FAILED   N              NOT retried — fix data in MPM first
-- DUPLICATE_RECORD    N              NOT retried — already in CRM, no action
-- RECORD_NOT_FOUND    N              NOT retried — parent missing in CRM
-- CRM_REJECTED        N              NOT retried — CRM business rule failed
-- VALIDATION_ERROR    N              NOT retried — APIC 4xx, fix payload
-- EXHAUSTED           N              NOT retried — max attempts reached
-- SUCCESS             N              NOT retried — already done
-- ─────────────────── ────────────── ─────────────────────────────────────
-- Building MAX_CAPACITY missing = VALIDATION_FAILED → NOT retried
-- Fix MAX_CAPACITY in MPM → watermark picks it up next scheduled run ✅

DBMS_OUTPUT.PUT_LINE('');
DBMS_OUTPUT.PUT_LINE('=== RETRY CONDITION FIX SUMMARY ===');
DBMS_OUTPUT.PUT_LINE('Part 1: Error code master updated ✅');
DBMS_OUTPUT.PUT_LINE('Part 2: Apply RUN_RETRY_JOB cursor change to package');
DBMS_OUTPUT.PUT_LINE('Part 3: RUN_TIMEOUT_JOB documented (no change needed)');
DBMS_OUTPUT.PUT_LINE('Part 4: Run verify query to see current failed records');
