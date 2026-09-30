-- ============================================================
-- SIT UNIT BATCH JOB CHECK QUERIES
-- Purpose : Verify unit batch scheduler jobs are running on SIT
-- Run in  : SQL*Plus or SQL Developer on SIT environment
-- ============================================================

-- -------------------------------------------------------
-- QUERY 1: Check scheduler job status
-- If ENABLED=FALSE or STATE=DISABLED — job not yet enabled on SIT
-- -------------------------------------------------------
SELECT JOB_NAME,
       ENABLED,
       STATE,
       LAST_START_DATE,
       LAST_RUN_DURATION,
       NEXT_RUN_DATE,
       FAILURE_COUNT
FROM   DBA_SCHEDULER_JOBS
WHERE  JOB_NAME LIKE 'CRM_MPM%'
ORDER  BY JOB_NAME;

-- -------------------------------------------------------
-- QUERY 2: Check job run history — has batch actually executed?
-- -------------------------------------------------------
SELECT JOB_NAME,
       STATUS,
       START_TIME,
       END_TIME,
       RECORDS_PROCESSED,
       RECORDS_SUCCESS,
       RECORDS_FAILED,
       ERROR_MESSAGE
FROM   CRM_MPM_JOB_RUN_HISTORY
WHERE  JOB_NAME IN ('UNIT_STATUS_BATCH','OUTBOUND_PUSH','RETRY_JOB')
ORDER  BY START_TIME DESC
FETCH FIRST 20 ROWS ONLY;

-- -------------------------------------------------------
-- QUERY 3: Check integration log — did unit batch push records?
-- -------------------------------------------------------
SELECT ENTITY_NAME,
       OPERATION_TYPE,
       FINAL_STATUS,
       COUNT(*)        AS REC_COUNT,
       MAX(SENT_DATE)  AS LAST_SENT
FROM   CRM_MPM_CRM_INTEGRATION_LOG
WHERE  ENTITY_NAME LIKE '%UNIT%'
GROUP  BY ENTITY_NAME, OPERATION_TYPE, FINAL_STATUS
ORDER  BY LAST_SENT DESC;

-- -------------------------------------------------------
-- QUERY 4: Enable unit batch jobs if they are disabled
-- Uncomment and run ONLY after confirming from Query 1
-- -------------------------------------------------------
/*
BEGIN
    DBMS_SCHEDULER.ENABLE('CRM_MPM_UNIT_STATUS_JOB');
    DBMS_SCHEDULER.ENABLE('CRM_MPM_UNIT_UNAVAILABLE_JOB');
    DBMS_OUTPUT.PUT_LINE('Unit batch jobs enabled.');
END;
/
*/
