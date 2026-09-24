-- =============================================================================
-- EMERGENCY: Stop runaway retry loop for records 509121 and 509122
-- Run IMMEDIATELY in SQL Developer before recompiling package
-- =============================================================================

-- Step 1: Stop the retry job
BEGIN
    DBMS_SCHEDULER.STOP_JOB('CRM_MPM_RETRY_JOB', force => TRUE);
    DBMS_SCHEDULER.DISABLE('CRM_MPM_RETRY_JOB');
END;
/

-- Step 2: Check how many duplicate rows exist
SELECT SOURCE_RECORD_ID, COUNT(*) AS ROW_COUNT
FROM   CRM_MPM_CRM_INTEGRATION_LOG
WHERE  SOURCE_RECORD_ID IN ('509121','509122')
GROUP  BY SOURCE_RECORD_ID;

-- Step 3: Keep only the LATEST row per record, mark all others as RESOLVED
-- This cleans up the 1450 duplicate rows
UPDATE CRM_MPM_CRM_INTEGRATION_LOG
SET    FINAL_STATUS  = 'RESOLVED',
       ERROR_MESSAGE = 'Cleanup: duplicate row from runaway retry bug. '
                       || TO_CHAR(SYSDATE,'DD-MON-YY HH24:MI'),
       UPDATED_DATE  = SYSTIMESTAMP
WHERE  SOURCE_RECORD_ID IN ('509121','509122')
AND    FINAL_STATUS NOT IN ('SUCCESS','ACK_OK')
AND    LOG_ID NOT IN (
    -- Keep one row per SOURCE_RECORD_ID+REGISTRY_ID -- the latest SENT or FAILED
    SELECT MAX(LOG_ID)
    FROM   CRM_MPM_CRM_INTEGRATION_LOG
    WHERE  SOURCE_RECORD_ID IN ('509121','509122')
    GROUP  BY SOURCE_RECORD_ID, REGISTRY_ID
);
COMMIT;

-- Step 4: Reset the surviving rows so they retry properly
UPDATE CRM_MPM_CRM_INTEGRATION_LOG
SET    FINAL_STATUS     = 'FAILED',
       RETRY_COUNT      = 0,
       IS_FINAL_ATTEMPT = 'N',
       NEXT_RETRY_DATE  = SYSTIMESTAMP + (30/1440), -- retry in 30 min
       MANUAL_RETRY     = 'N',
       UPDATED_DATE     = SYSTIMESTAMP
WHERE  SOURCE_RECORD_ID IN ('509121','509122')
AND    FINAL_STATUS NOT IN ('SUCCESS','ACK_OK','RESOLVED');
COMMIT;

-- Step 5: Verify -- should see only 1-2 rows per record now
SELECT LOG_ID, SOURCE_RECORD_ID, FINAL_STATUS,
       RETRY_COUNT, NEXT_RETRY_DATE
FROM   CRM_MPM_CRM_INTEGRATION_LOG
WHERE  SOURCE_RECORD_ID IN ('509121','509122')
AND    FINAL_STATUS NOT IN ('RESOLVED')
ORDER  BY LOG_ID DESC;

-- Step 6: After verifying above looks clean --
-- Recompile package (PKG_CRM_INTEGRATION_BODY_FINAL.sql)
-- Then re-enable retry job:
/*
BEGIN
    DBMS_SCHEDULER.ENABLE('CRM_MPM_RETRY_JOB');
END;
/
*/
