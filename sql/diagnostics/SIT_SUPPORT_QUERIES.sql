-- =============================================================================
-- ADIB MPM PROPERTIES -- CRM xRM INTEGRATION
-- FILE : SIT_SUPPORT_QUERIES.sql
-- DESC : Support queries for troubleshooting, locks, retry, deployment checks
-- Author  : Tajudeen Jalaudin -- Senior Solution Architect, ADIB
-- Date    : 24 September 2026
-- =============================================================================

-- =============================================================================
-- QUERY 1: WHAT IS RUNNING RIGHT NOW (active sessions)
-- Use when: compile hangs, package locked, retry spinning
-- =============================================================================
PROMPT -- QUERY 1: ACTIVE SESSIONS
SELECT s.SID,
       s.SERIAL#,
       s.STATUS,
       s.PROGRAM,
       s.MODULE,
       s.ACTION,
       s.LOGON_TIME,
       q.SQL_TEXT
FROM   V$SESSION s
LEFT   JOIN V$SQL q ON s.SQL_ID = q.SQL_ID
WHERE  s.STATUS   = 'ACTIVE'
AND    s.USERNAME = 'APPS'
ORDER  BY s.LOGON_TIME;

-- =============================================================================
-- QUERY 2: CHECK WHAT IS LOCKING THE PACKAGE
-- Use when: package compile hangs
-- =============================================================================
PROMPT -- QUERY 2: OBJECT LOCKS
SELECT o.OBJECT_NAME,
       o.OBJECT_TYPE,
       s.SID,
       s.SERIAL#,
       s.STATUS,
       s.PROGRAM,
       s.LOGON_TIME
FROM   V$LOCKED_OBJECT l
JOIN   DBA_OBJECTS      o ON l.OBJECT_ID   = o.OBJECT_ID
JOIN   V$SESSION        s ON l.SESSION_ID  = s.SID
WHERE  o.OBJECT_NAME LIKE '%CRM%'
ORDER  BY o.OBJECT_NAME;

-- =============================================================================
-- QUERY 3: STOP RETRY JOB (run before compiling package)
-- Use when: package compile hangs due to retry job running
-- =============================================================================
PROMPT -- QUERY 3: STOP RETRY JOB
BEGIN
    DBMS_SCHEDULER.STOP_JOB('CRM_MPM_RETRY_JOB', TRUE);
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

BEGIN
    DBMS_SCHEDULER.DISABLE('CRM_MPM_RETRY_JOB');
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

-- Confirm job is disabled
SELECT JOB_NAME, ENABLED, STATE, LAST_START_DATE, NEXT_RUN_DATE
FROM   USER_SCHEDULER_JOBS
WHERE  JOB_NAME LIKE 'CRM_MPM%'
ORDER  BY JOB_NAME;

-- =============================================================================
-- QUERY 4: RE-ENABLE RETRY JOB (run after compile is done)
-- Use when: ready to resume normal processing
-- =============================================================================
PROMPT -- QUERY 4: RE-ENABLE RETRY JOB
BEGIN
    DBMS_SCHEDULER.ENABLE('CRM_MPM_RETRY_JOB');
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

-- Confirm job is enabled
SELECT JOB_NAME, ENABLED, STATE, LAST_START_DATE, NEXT_RUN_DATE
FROM   USER_SCHEDULER_JOBS
WHERE  JOB_NAME LIKE 'CRM_MPM%'
ORDER  BY JOB_NAME;

-- =============================================================================
-- QUERY 5: HOW MANY RECORDS STUCK IN RETRY
-- Use when: retry job running too much / too frequently
-- =============================================================================
PROMPT -- QUERY 5: RETRY STUCK RECORDS COUNT
SELECT COUNT(*)        AS RECORD_COUNT,
       FINAL_STATUS,
       ERROR_CODE
FROM   CRM_MPM_CRM_INTEGRATION_LOG
WHERE  FINAL_STATUS    IN ('FAILED','RETRY_PENDING')
AND    NEXT_RETRY_DATE <  SYSDATE
GROUP  BY FINAL_STATUS, ERROR_CODE
ORDER  BY 1 DESC;

-- =============================================================================
-- QUERY 6: RETRY QUEUE DETAIL -- which records are being retried
-- =============================================================================
PROMPT -- QUERY 6: RETRY QUEUE DETAIL
SELECT LOG_ID,
       REGISTRY_ID,
       SOURCE_RECORD_ID,
       FINAL_STATUS,
       ERROR_CODE,
       RETRY_COUNT,
       NEXT_RETRY_DATE,
       UPDATED_DATE
FROM   CRM_MPM_CRM_INTEGRATION_LOG
WHERE  FINAL_STATUS    IN ('FAILED','RETRY_PENDING','RETRY_IN_PROGRESS')
AND    NEXT_RETRY_DATE <  SYSDATE + 1
ORDER  BY NEXT_RETRY_DATE, LOG_ID;

-- =============================================================================
-- QUERY 7: RUNAWAY RETRY CHECK
-- Use when: same record being retried hundreds of times
-- Shows records with unusually high retry count
-- =============================================================================
PROMPT -- QUERY 7: RUNAWAY RETRY CHECK
SELECT SOURCE_RECORD_ID,
       COUNT(*)         AS DUPLICATE_ROWS,
       MAX(RETRY_COUNT) AS MAX_RETRY,
       MAX(ATTEMPT_NO)  AS MAX_ATTEMPT,
       MIN(CREATED_DATE) AS FIRST_SEEN,
       MAX(UPDATED_DATE) AS LAST_UPDATED,
       MAX(FINAL_STATUS) AS LATEST_STATUS,
       MAX(ERROR_CODE)   AS ERROR_CODE
FROM   CRM_MPM_CRM_INTEGRATION_LOG
GROUP  BY SOURCE_RECORD_ID
HAVING COUNT(*) > 5
    OR MAX(RETRY_COUNT) > 10
ORDER  BY COUNT(*) DESC, MAX(RETRY_COUNT) DESC;

-- =============================================================================
-- QUERY 8: STOP ALL CRM_MPM JOBS (emergency -- stop everything)
-- Use when: need to stop all processing immediately
-- =============================================================================
PROMPT -- QUERY 8: STOP ALL CRM_MPM JOBS
BEGIN
    FOR j IN (
        SELECT JOB_NAME FROM USER_SCHEDULER_JOBS
        WHERE  JOB_NAME LIKE 'CRM_MPM%'
    ) LOOP
        BEGIN
            DBMS_SCHEDULER.STOP_JOB(j.JOB_NAME, TRUE);
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
        BEGIN
            DBMS_SCHEDULER.DISABLE(j.JOB_NAME);
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('All CRM_MPM jobs stopped and disabled');
END;
/

SELECT JOB_NAME, ENABLED, STATE
FROM   USER_SCHEDULER_JOBS
WHERE  JOB_NAME LIKE 'CRM_MPM%'
ORDER  BY JOB_NAME;

-- =============================================================================
-- QUERY 9: RE-ENABLE ALL CRM_MPM JOBS
-- Use when: ready to resume all processing after fix
-- =============================================================================
PROMPT -- QUERY 9: RE-ENABLE ALL CRM_MPM JOBS
BEGIN
    FOR j IN (
        SELECT JOB_NAME FROM USER_SCHEDULER_JOBS
        WHERE  JOB_NAME LIKE 'CRM_MPM%'
    ) LOOP
        BEGIN
            DBMS_SCHEDULER.ENABLE(j.JOB_NAME);
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('All CRM_MPM jobs enabled');
END;
/

SELECT JOB_NAME, ENABLED, STATE, NEXT_RUN_DATE
FROM   USER_SCHEDULER_JOBS
WHERE  JOB_NAME LIKE 'CRM_MPM%'
ORDER  BY JOB_NAME;

-- =============================================================================
-- QUERY 10: KILL A HANGING SESSION
-- Use when: compile hangs and you know the SID and SERIAL# from Query 1
-- Replace 123 and 456 with actual SID and SERIAL# from Query 1
-- =============================================================================
PROMPT -- QUERY 10: KILL HANGING SESSION (update SID and SERIAL# first)
-- ALTER SYSTEM KILL SESSION '123,456' IMMEDIATE;

-- =============================================================================
-- QUERY 11: PACKAGE STATUS -- is package valid or invalid
-- =============================================================================
PROMPT -- QUERY 11: PACKAGE STATUS
SELECT OBJECT_NAME,
       OBJECT_TYPE,
       STATUS,
       LAST_DDL_TIME
FROM   USER_OBJECTS
WHERE  OBJECT_NAME = 'PKG_CRM_INTEGRATION'
ORDER  BY OBJECT_TYPE;

-- =============================================================================
-- QUERY 12: SCHEDULER JOB STATUS -- full detail
-- =============================================================================
PROMPT -- QUERY 12: SCHEDULER JOB STATUS
SELECT JOB_NAME,
       ENABLED,
       STATE,
       RUN_COUNT,
       FAILURE_COUNT,
       LAST_START_DATE,
       LAST_RUN_DURATION,
       NEXT_RUN_DATE
FROM   USER_SCHEDULER_JOBS
WHERE  JOB_NAME LIKE 'CRM_MPM%'
ORDER  BY JOB_NAME;

-- =============================================================================
-- QUERY 13: TODAY SUMMARY -- overall health check
-- =============================================================================
PROMPT -- QUERY 13: TODAY SUMMARY
SELECT FINAL_STATUS,
       COUNT(*)          AS RECORD_COUNT,
       MIN(CREATED_DATE) AS FIRST_RECORD,
       MAX(CREATED_DATE) AS LAST_RECORD
FROM   CRM_MPM_CRM_INTEGRATION_LOG
WHERE  CREATED_DATE >= TRUNC(SYSDATE)
GROUP  BY FINAL_STATUS
ORDER  BY COUNT(*) DESC;

-- =============================================================================
-- QUERY 14: RECORDS NEEDING MANUAL ATTENTION
-- =============================================================================
PROMPT -- QUERY 14: RECORDS NEEDING MANUAL ATTENTION
SELECT LOG_ID,
       SOURCE_RECORD_ID,
       REGISTRY_ID,
       FINAL_STATUS,
       ERROR_CODE,
       ERROR_MESSAGE,
       RETRY_COUNT,
       CREATED_DATE,
       UPDATED_DATE
FROM   CRM_MPM_CRM_INTEGRATION_LOG
WHERE  FINAL_STATUS IN ('EXHAUSTED','FAILED')
AND    (RETRY_COUNT >= 3 OR NEXT_RETRY_DATE IS NULL)
ORDER  BY CREATED_DATE DESC;

-- =============================================================================
-- QUERY 15: VERIFY SIT DEPLOYMENT -- run on SIT after deployment
-- Checks all objects created correctly
-- =============================================================================
PROMPT -- QUERY 15: SIT DEPLOYMENT VERIFICATION
SELECT 'TABLES' AS OBJECT_TYPE, COUNT(*) AS COUNT
FROM   USER_TABLES
WHERE  TABLE_NAME LIKE 'CRM_MPM%'
UNION ALL
SELECT 'SEQUENCES', COUNT(*)
FROM   USER_SEQUENCES
WHERE  SEQUENCE_NAME LIKE 'CRM_MPM%'
   OR  SEQUENCE_NAME LIKE 'SEQ_CRM%'
UNION ALL
SELECT 'INDEXES', COUNT(*)
FROM   USER_INDEXES
WHERE  TABLE_NAME LIKE 'CRM_MPM%'
UNION ALL
SELECT 'PACKAGES', COUNT(*)
FROM   USER_OBJECTS
WHERE  OBJECT_NAME = 'PKG_CRM_INTEGRATION'
AND    OBJECT_TYPE IN ('PACKAGE','PACKAGE BODY')
UNION ALL
SELECT 'INVALID OBJECTS', COUNT(*)
FROM   USER_OBJECTS
WHERE  OBJECT_NAME LIKE '%CRM%'
AND    STATUS = 'INVALID';

PROMPT -- Done.
