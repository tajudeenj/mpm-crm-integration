-- =============================================================================
-- ADIB MPM PROPERTIES -- CRM xRM INTEGRATION
-- FILE : SIT_SUPPORT_QUERIES.sql
-- DESC : Support queries for troubleshooting, locks, retry, deployment checks
-- Author  : Tajudeen Jalaudin -- Senior Solution Architect, ADIB
-- Date    : 24 September 2026
-- Updated : 10 October 2026 (Session 9) -- QUERY 16+ appended
--
-- RULE: this is the ONE growing support file. Every new support query is
--       appended here as the next QUERY number. Do not create new files.
-- &variables prompt for a value in SQL Developer (needs SET DEFINE ON).
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


-- =============================================================================
-- ================  SESSION 9 (Oct 2026) — DEPENDENCY / CALLBACK  =============
-- =============================================================================
SET DEFINE ON

-- =============================================================================
-- QUERY 16: CALLBACK AUDIT — raw payload received + response we sent
-- Use when: callback failed / technical error on callback
-- Input   : service name part, e.g. BUILDING
-- =============================================================================
PROMPT -- QUERY 16: CALLBACK AUDIT
SELECT AUDIT_ID, TO_CHAR(RECEIVED_AT,'DD-MON-YY HH24:MI:SS') AS RECEIVED_AT,
       SERVICE_NAME, X_UNIQUE_ID, CHANNEL_ID, REQUEST_ID,
       STATUS_CODE_SENT, DESCRIPTION_SENT, RAW_PAYLOAD
FROM   CRM_MPM_CALLBACK_AUDIT_LOG
WHERE  UPPER(SERVICE_NAME) LIKE '%'||UPPER('&service_part')||'%'
ORDER  BY AUDIT_ID DESC
FETCH  FIRST 10 ROWS ONLY;

-- =============================================================================
-- QUERY 17: FULL LOG HISTORY FOR ONE RECORD (all attempts, ACK + callback)
-- Input   : source record id (e.g. BUILDING_ID 523118)
-- =============================================================================
PROMPT -- QUERY 17: LOG HISTORY FOR ONE RECORD
SELECT L.LOG_ID, R.SERVICE_NAME, L.SOURCE_RECORD_ID, L.FINAL_STATUS, L.ERROR_CODE,
       L.ERROR_MESSAGE, L.HTTP_STATUS_CODE, L.ACK_STATUS_CODE, L.ACK_DESCRIPTION,
       L.CALLBACK_RESULT_CODE, L.CALLBACK_RESULT_DESC, L.CALLBACK_VALID_ERRORS,
       L.RETRY_COUNT, NVL(L.MANUAL_RETRY,'N') AS MANUAL_RETRY,
       TO_CHAR(L.SENT_DATE,'DD-MON-YY HH24:MI:SS')     AS SENT_DATE,
       TO_CHAR(L.CALLBACK_DATE,'DD-MON-YY HH24:MI:SS') AS CALLBACK_DATE,
       L.REQUEST_PAYLOAD, L.ACK_RESPONSE, L.CALLBACK_PAYLOAD
FROM   CRM_MPM_CRM_INTEGRATION_LOG L
JOIN   CRM_MPM_API_REGISTRY R ON R.REGISTRY_ID = L.REGISTRY_ID
WHERE  L.SOURCE_RECORD_ID = '&record_id'
ORDER  BY L.LOG_ID DESC;

-- =============================================================================
-- QUERY 18: REGISTRY CONFIG — watermark column + dependency per service
-- Use when: deciding CREATE/UPDATE behaviour after MPM fixes data
-- =============================================================================
PROMPT -- QUERY 18: REGISTRY CONFIG
SELECT REGISTRY_ID, SERVICE_NAME, OPERATION_TYPE, SOURCE_VIEW,
       SOURCE_KEY_COL, SOURCE_FILTER_COL, SOURCE_EXTRA_FILTER,
       DEPENDS_ON_REGISTRY_ID, PARENT_LINK_COL, EXECUTION_ORDER, IS_ACTIVE
FROM   CRM_MPM_API_REGISTRY
ORDER  BY EXECUTION_ORDER, REGISTRY_ID;

-- =============================================================================
-- QUERY 19: PARENT PENDING / PARENT FAILED / RELEASED
-- Use when: child not sent — is it waiting on its parent?
-- =============================================================================
PROMPT -- QUERY 19: DEPENDENCY QUEUE
SELECT L.LOG_ID, R.SERVICE_NAME, L.SOURCE_RECORD_ID, L.FINAL_STATUS,
       PR.SERVICE_NAME AS PARENT_SERVICE,
       REGEXP_SUBSTR(L.ERROR_MESSAGE,'Key=([^ ]+)',1,1,NULL,1) AS PARENT_KEY,
       TO_CHAR(L.CREATED_DATE,'DD-MON-YY HH24:MI') AS CREATED,
       TO_CHAR(L.UPDATED_DATE,'DD-MON-YY HH24:MI') AS UPDATED,
       L.ERROR_MESSAGE
FROM   CRM_MPM_CRM_INTEGRATION_LOG L
JOIN   CRM_MPM_API_REGISTRY R  ON R.REGISTRY_ID  = L.REGISTRY_ID
LEFT   JOIN CRM_MPM_API_REGISTRY PR ON PR.REGISTRY_ID = R.DEPENDS_ON_REGISTRY_ID
WHERE  L.FINAL_STATUS IN ('PARENT_PENDING','PARENT_FAILED','RELEASED')
ORDER  BY L.LOG_ID DESC;

-- =============================================================================
-- QUERY 20: RUN RELEASE PASS NOW (no wait for the 15-min job)
-- Then re-run QUERY 19
-- =============================================================================
PROMPT -- QUERY 20: RELEASE PARENT PENDING (manual)
BEGIN
    PKG_CRM_INTEGRATION.RELEASE_PARENT_PENDING;
END;
/

-- =============================================================================
-- QUERY 21: DEPENDENCY + MANUAL RETRY ERROR CODES PRESENT?
-- Expect 3 rows: PARENT_* = N, MANUAL_RETRY = Y
-- =============================================================================
PROMPT -- QUERY 21: DEPENDENCY ERROR CODES
SELECT ERROR_CODE, ERROR_CATEGORY, IS_RETRYABLE, ERROR_DESCRIPTION
FROM   CRM_MPM_ERROR_CODE_MASTER
WHERE  ERROR_CODE IN ('PARENT_PENDING','PARENT_FAILED','MANUAL_RETRY');

-- =============================================================================
-- QUERY 22: MANUAL RETRY QUEUE — queued rows + will the retry job pick them?
-- PICKABLE = N means ERROR_CODE not retryable -> retry job will skip it
-- =============================================================================
PROMPT -- QUERY 22: MANUAL RETRY QUEUE
SELECT L.LOG_ID, R.SERVICE_NAME, L.SOURCE_RECORD_ID, L.FINAL_STATUS, L.ERROR_CODE,
       L.RETRY_COUNT, TO_CHAR(L.NEXT_RETRY_DATE,'DD-MON-YY HH24:MI') AS NEXT_RETRY,
       NVL(E.IS_RETRYABLE,'N') AS PICKABLE
FROM   CRM_MPM_CRM_INTEGRATION_LOG L
JOIN   CRM_MPM_API_REGISTRY R ON R.REGISTRY_ID = L.REGISTRY_ID
LEFT   JOIN CRM_MPM_ERROR_CODE_MASTER E ON E.ERROR_CODE = L.ERROR_CODE
WHERE  L.MANUAL_RETRY = 'Y' AND L.FINAL_STATUS = 'FAILED'
ORDER  BY L.LOG_ID DESC;

-- =============================================================================
-- QUERY 23: CHECK CONSTRAINTS ON ERROR CODE MASTER (run on PROD before deploy)
-- =============================================================================
PROMPT -- QUERY 23: ERROR MASTER CONSTRAINTS
SELECT CONSTRAINT_NAME, CONSTRAINT_TYPE, SEARCH_CONDITION, STATUS
FROM   USER_CONSTRAINTS
WHERE  TABLE_NAME = 'CRM_MPM_ERROR_CODE_MASTER';

-- =============================================================================
-- QUERY 24: OUTBOUND JOB — interval, state, last/next run, last runs
-- =============================================================================
PROMPT -- QUERY 24: OUTBOUND JOB
SELECT JOB_NAME, ENABLED, STATE, REPEAT_INTERVAL,
       TO_CHAR(LAST_START_DATE,'DD-MON-YY HH24:MI') AS LAST_RUN,
       TO_CHAR(NEXT_RUN_DATE,'DD-MON-YY HH24:MI')   AS NEXT_RUN
FROM   USER_SCHEDULER_JOBS
WHERE  JOB_NAME = 'CRM_MPM_OUTBOUND_JOB';

SELECT RUN_ID, JOB_NAME, STATUS,
       TO_CHAR(START_TIME,'DD-MON-YY HH24:MI:SS') AS STARTED,
       TO_CHAR(END_TIME,'DD-MON-YY HH24:MI:SS')   AS ENDED,
       RECORDS_PROCESSED, RECORDS_SUCCESS, RECORDS_FAILED, ERROR_MESSAGE
FROM   CRM_MPM_JOB_RUN_HISTORY
WHERE  JOB_NAME = 'OUTBOUND_PUSH'
ORDER  BY RUN_ID DESC FETCH FIRST 10 ROWS ONLY;

-- =============================================================================
-- QUERY 25: CHAIN STATUS FOR ONE PROPERTY (Property > Building > Floor > Unit)
-- Same SQL as web app Chain Status tab. Input: property code e.g. MA00810
-- =============================================================================
PROMPT -- QUERY 25: CHAIN FOR ONE PROPERTY
WITH RG AS (
    SELECT MAX(CASE WHEN SOURCE_VIEW='XXMPM_CRM_PROPERTY_CREATE_V'      THEN REGISTRY_ID END) AS P_ID,
           MAX(CASE WHEN SOURCE_VIEW='XXMPM_CRM_BUILDING_CREATE_FULL_V' THEN REGISTRY_ID END) AS B_ID,
           MAX(CASE WHEN SOURCE_VIEW='XXMPM_CRM_FLOOR_CREATE_V'         THEN REGISTRY_ID END) AS F_ID,
           MAX(CASE WHEN SOURCE_VIEW='XXMPM_CRM_UNIT_CREATE_V'          THEN REGISTRY_ID END) AS U_ID
    FROM   CRM_MPM_API_REGISTRY WHERE OPERATION_TYPE='CREATE'
), LS AS (
    SELECT REGISTRY_ID, SOURCE_RECORD_ID, FINAL_STATUS, CRM_ENTITY_ID, LOG_ID,
           NVL(UPDATED_DATE,CREATED_DATE) AS LAST_TS, ERROR_MESSAGE,
           ROW_NUMBER() OVER (PARTITION BY REGISTRY_ID, SOURCE_RECORD_ID ORDER BY LOG_ID DESC) AS RN
    FROM   CRM_MPM_CRM_INTEGRATION_LOG
    WHERE  FINAL_STATUS <> 'RELEASED'
    AND    REGISTRY_ID IN (SELECT P_ID FROM RG UNION ALL SELECT B_ID FROM RG
                           UNION ALL SELECT F_ID FROM RG UNION ALL SELECT U_ID FROM RG)
), NODES AS (
    SELECT TO_CHAR(P.PROPERTY_CODE) AS PROP, 1 AS LVL_NO, 'PROPERTY' AS LVL,
           TO_CHAR(P.PROPERTY_CODE) AS NODE_KEY, CAST(NULL AS VARCHAR2(200)) AS PARENT_KEY, RG.P_ID AS RID
    FROM   XXMPM_CRM_PROPERTY_CREATE_V P CROSS JOIN RG
    UNION ALL
    SELECT TO_CHAR(B.BUILDING_CODE), 2, 'BUILDING', TO_CHAR(B.BUILDING_ID), TO_CHAR(B.BUILDING_CODE), RG.B_ID
    FROM   XXMPM_CRM_BUILDING_CREATE_FULL_V B CROSS JOIN RG
    UNION ALL
    SELECT TO_CHAR(B.BUILDING_CODE), 3, 'FLOOR', TO_CHAR(F.FLOOR_ID), TO_CHAR(F.BUILDING_ID), RG.F_ID
    FROM   XXMPM_CRM_FLOOR_CREATE_V F
    JOIN   XXMPM_CRM_BUILDING_CREATE_FULL_V B ON TO_CHAR(B.BUILDING_ID)=TO_CHAR(F.BUILDING_ID)
    CROSS  JOIN RG
    UNION ALL
    SELECT TO_CHAR(B.BUILDING_CODE), 4, 'UNIT', TO_CHAR(U.UNIT_ID), TO_CHAR(U.FLOOR_ID), RG.U_ID
    FROM   XXMPM_CRM_UNIT_CREATE_V U
    JOIN   XXMPM_CRM_FLOOR_CREATE_V F ON TO_CHAR(F.FLOOR_ID)=TO_CHAR(U.FLOOR_ID)
    JOIN   XXMPM_CRM_BUILDING_CREATE_FULL_V B ON TO_CHAR(B.BUILDING_ID)=TO_CHAR(F.BUILDING_ID)
    CROSS  JOIN RG
), CN AS (
    SELECT N.PROP, N.LVL_NO, N.LVL, N.NODE_KEY, N.PARENT_KEY,
           NVL(LS.FINAL_STATUS,'NOT_SENT') AS ST, LS.CRM_ENTITY_ID, LS.LOG_ID, LS.LAST_TS, LS.ERROR_MESSAGE
    FROM   NODES N
    LEFT   JOIN LS ON LS.REGISTRY_ID=N.RID AND LS.SOURCE_RECORD_ID=N.NODE_KEY AND LS.RN=1
)
SELECT LVL, NODE_KEY, PARENT_KEY, ST AS STATUS, NVL(TO_CHAR(LOG_ID),'--') AS LOG_ID,
       NVL(CRM_ENTITY_ID,'--') AS CRM_ENTITY_ID, TO_CHAR(LAST_TS,'DD-MON-YY HH24:MI') AS LAST_UPDATE,
       SUBSTR(ERROR_MESSAGE,1,250) AS DETAIL
FROM   CN
WHERE  PROP = '&property_code'
ORDER  BY LVL_NO, PARENT_KEY NULLS FIRST, NODE_KEY;

-- =============================================================================
-- QUERY 26: IDENTIFY A CONSTRAINT BY NAME (e.g. from ORA-02290 / ORA-02293)
-- Use when: callback returns CB_1003 "check constraint (APPS.SYS_Cxxxx) violated"
-- Input   : constraint name, e.g. SYS_C005700592
-- =============================================================================
PROMPT -- QUERY 26: WHICH TABLE/COLUMN IS THIS CONSTRAINT ON
SELECT C.OWNER, C.TABLE_NAME, CC.COLUMN_NAME, C.CONSTRAINT_TYPE,
       C.SEARCH_CONDITION, C.STATUS
FROM   ALL_CONSTRAINTS C
JOIN   ALL_CONS_COLUMNS CC ON CC.OWNER = C.OWNER AND CC.CONSTRAINT_NAME = C.CONSTRAINT_NAME
WHERE  C.CONSTRAINT_NAME = UPPER('&constraint_name');

-- =============================================================================
-- QUERY 27: ALL CHECK CONSTRAINTS ON INTEGRATION TABLES (find hidden SYS_C ones)
-- None of these are in repo DDL — anything listed was added directly on the DB
-- =============================================================================
PROMPT -- QUERY 27: CHECK CONSTRAINTS ON CRM_MPM TABLES
SELECT C.TABLE_NAME, C.CONSTRAINT_NAME, CC.COLUMN_NAME, C.SEARCH_CONDITION
FROM   USER_CONSTRAINTS C
JOIN   USER_CONS_COLUMNS CC ON CC.CONSTRAINT_NAME = C.CONSTRAINT_NAME
WHERE  C.CONSTRAINT_TYPE = 'C'
AND    C.TABLE_NAME LIKE 'CRM_MPM%'
AND    C.SEARCH_CONDITION_VC NOT LIKE '%IS NOT NULL%'
ORDER  BY C.TABLE_NAME, C.CONSTRAINT_NAME;

-- =============================================================================
-- QUERY 28: DID THIS CALLBACK REACH ORACLE? — search audit by request_id
-- Run on SIT AND on DEV (SIT callback URL may still point to DEV).
-- Input   : request_id from ACK_RESPONSE (QUERY 17)
-- No row in either DB = callback never reached Oracle -> check APIC / ESB
-- logs with the same request_id. PROCESS_CRM_CALLBACK writes the audit row
-- even when it fails (CB_1003), so "no row" really means "never arrived".
-- =============================================================================
PROMPT -- QUERY 28: CALLBACK BY REQUEST_ID
SELECT AUDIT_ID, TO_CHAR(RECEIVED_AT,'DD-MON-YY HH24:MI:SS') AS RECEIVED_AT,
       SERVICE_NAME, X_UNIQUE_ID, REQUEST_ID, STATUS_CODE_SENT, DESCRIPTION_SENT
FROM   CRM_MPM_CALLBACK_AUDIT_LOG
WHERE  REQUEST_ID = '&request_id'
   OR  RAW_PAYLOAD LIKE '%&request_id%';
