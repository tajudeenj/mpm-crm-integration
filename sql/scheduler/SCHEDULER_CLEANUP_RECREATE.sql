-- =============================================================================
-- SCHEDULER CLEANUP AND RECREATE -- CRM_MPM JOBS ONLY
-- ADIB MPM CRM Integration
-- Author : ADIB EA Team (Tajudeen Jalaudin)
-- Date   : 2026-09-19
-- NOTE   : Only touches CRM_MPM_* jobs -- all others left untouched
-- =============================================================================

SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED


-- =============================================================================
-- PART 1: STOP RUNNING CRM_MPM JOBS FIRST
-- CRM_MPM_RETRY_JOB and CRM_MPM_TIMEOUT_JOB currently RUNNING
-- Must stop before drop otherwise DROP_JOB will hang
-- =============================================================================
BEGIN
    BEGIN
        DBMS_SCHEDULER.STOP_JOB(
            job_name => 'CRM_MPM_RETRY_JOB',
            force    => TRUE);
        DBMS_OUTPUT.PUT_LINE('Stopped: CRM_MPM_RETRY_JOB');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Stop RETRY_JOB: ' || SQLERRM);
    END;

    BEGIN
        DBMS_SCHEDULER.STOP_JOB(
            job_name => 'CRM_MPM_TIMEOUT_JOB',
            force    => TRUE);
        DBMS_OUTPUT.PUT_LINE('Stopped: CRM_MPM_TIMEOUT_JOB');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Stop TIMEOUT_JOB: ' || SQLERRM);
    END;
END;
/

-- Wait 5 seconds for jobs to stop cleanly
BEGIN
    DBMS_LOCK.SLEEP(5);
    DBMS_OUTPUT.PUT_LINE('Waited 5 seconds');
END;
/

-- Verify no CRM_MPM jobs running before proceeding
SELECT JOB_NAME, STATE
FROM   USER_SCHEDULER_JOBS
WHERE  STATE    = 'RUNNING'
AND    JOB_NAME LIKE 'CRM_MPM%';
-- Must return 0 rows before continuing to Part 2


-- =============================================================================
-- PART 2: DROP ALL CRM_MPM JOBS ONLY
-- =============================================================================
BEGIN
    FOR j IN (
        SELECT JOB_NAME
        FROM   USER_SCHEDULER_JOBS
        WHERE  JOB_NAME LIKE 'CRM_MPM%'
    ) LOOP
        BEGIN
            DBMS_SCHEDULER.DROP_JOB(j.JOB_NAME, TRUE);
            DBMS_OUTPUT.PUT_LINE('Dropped: ' || j.JOB_NAME);
        EXCEPTION
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE(
                    'Drop failed ' || j.JOB_NAME ||
                    ': ' || SQLERRM);
        END;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('All CRM_MPM jobs dropped');
END;
/


-- =============================================================================
-- PART 3: RECREATE ALL 8 CRM_MPM JOBS FRESH
-- =============================================================================

-- OUTBOUND 6AM
BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name        => 'CRM_MPM_OUTBOUND_6AM',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN PKG_CRM_INTEGRATION.RUN_OUTBOUND_JOB; END;',
        repeat_interval => 'FREQ=DAILY; BYHOUR=6; BYMINUTE=0; BYSECOND=0',
        enabled         => TRUE,
        auto_drop       => FALSE,
        comments        => 'CRM outbound push -- 6AM daily'
    );
    DBMS_OUTPUT.PUT_LINE('Created: CRM_MPM_OUTBOUND_6AM');
END;
/

-- OUTBOUND 10AM
BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name        => 'CRM_MPM_OUTBOUND_10AM',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN PKG_CRM_INTEGRATION.RUN_OUTBOUND_JOB; END;',
        repeat_interval => 'FREQ=DAILY; BYHOUR=10; BYMINUTE=0; BYSECOND=0',
        enabled         => TRUE,
        auto_drop       => FALSE,
        comments        => 'CRM outbound push -- 10AM daily'
    );
    DBMS_OUTPUT.PUT_LINE('Created: CRM_MPM_OUTBOUND_10AM');
END;
/

-- OUTBOUND 2PM
BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name        => 'CRM_MPM_OUTBOUND_2PM',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN PKG_CRM_INTEGRATION.RUN_OUTBOUND_JOB; END;',
        repeat_interval => 'FREQ=DAILY; BYHOUR=14; BYMINUTE=0; BYSECOND=0',
        enabled         => TRUE,
        auto_drop       => FALSE,
        comments        => 'CRM outbound push -- 2PM daily'
    );
    DBMS_OUTPUT.PUT_LINE('Created: CRM_MPM_OUTBOUND_2PM');
END;
/

-- OUTBOUND 5PM
BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name        => 'CRM_MPM_OUTBOUND_5PM',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN PKG_CRM_INTEGRATION.RUN_OUTBOUND_JOB; END;',
        repeat_interval => 'FREQ=DAILY; BYHOUR=17; BYMINUTE=0; BYSECOND=0',
        enabled         => TRUE,
        auto_drop       => FALSE,
        comments        => 'CRM outbound push -- 5PM daily'
    );
    DBMS_OUTPUT.PUT_LINE('Created: CRM_MPM_OUTBOUND_5PM');
END;
/

-- RETRY JOB -- every 30 minutes
BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name        => 'CRM_MPM_RETRY_JOB',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN PKG_CRM_INTEGRATION.RUN_RETRY_JOB; END;',
        repeat_interval => 'FREQ=MINUTELY; INTERVAL=30',
        enabled         => TRUE,
        auto_drop       => FALSE,
        comments        => 'CRM retry failed records -- every 30 mins'
    );
    DBMS_OUTPUT.PUT_LINE('Created: CRM_MPM_RETRY_JOB');
END;
/

-- TIMEOUT JOB -- every hour
BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name        => 'CRM_MPM_TIMEOUT_JOB',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN PKG_CRM_INTEGRATION.RUN_TIMEOUT_JOB; END;',
        repeat_interval => 'FREQ=HOURLY; INTERVAL=1',
        enabled         => TRUE,
        auto_drop       => FALSE,
        comments        => 'CRM timeout check -- every hour'
    );
    DBMS_OUTPUT.PUT_LINE('Created: CRM_MPM_TIMEOUT_JOB');
END;
/

-- UNIT STATUS BATCH -- 11PM
BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name        => 'CRM_MPM_ALL_UNIT_STATUS_11PM',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN PKG_CRM_INTEGRATION.RUN_UNIT_UNAVAILABLE_BATCH; END;',
        repeat_interval => 'FREQ=DAILY; BYHOUR=23; BYMINUTE=0; BYSECOND=0',
        enabled         => TRUE,
        auto_drop       => FALSE,
        comments        => 'CRM all unit status batch -- 11PM daily'
    );
    DBMS_OUTPUT.PUT_LINE('Created: CRM_MPM_ALL_UNIT_STATUS_11PM');
END;
/

-- UNIT STATUS BATCH -- 4AM
BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name        => 'CRM_MPM_ALL_UNIT_STATUS_4AM',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN PKG_CRM_INTEGRATION.RUN_UNIT_UNAVAILABLE_BATCH; END;',
        repeat_interval => 'FREQ=DAILY; BYHOUR=4; BYMINUTE=0; BYSECOND=0',
        enabled         => TRUE,
        auto_drop       => FALSE,
        comments        => 'CRM all unit status batch -- 4AM daily'
    );
    DBMS_OUTPUT.PUT_LINE('Created: CRM_MPM_ALL_UNIT_STATUS_4AM');
END;
/


-- =============================================================================
-- PART 4: VERIFY -- CRM_MPM JOBS ONLY
-- Expected: 8 rows all SCHEDULED
-- =============================================================================
SELECT
    JOB_NAME,
    CASE WHEN ENABLED = 'TRUE' THEN 'Y' ELSE 'N' END AS ENABLED,
    STATE,
    REPEAT_INTERVAL,
    TO_CHAR(NEXT_RUN_DATE, 'DD-MON-YY HH24:MI') AS NEXT_RUN,
    COMMENTS
FROM   USER_SCHEDULER_JOBS
WHERE  JOB_NAME LIKE 'CRM_MPM%'
ORDER BY JOB_NAME;

-- =============================================================================
-- EXPECTED 8 ROWS:
-- CRM_MPM_ALL_UNIT_STATUS_11PM  Y  SCHEDULED  FREQ=DAILY;BYHOUR=23
-- CRM_MPM_ALL_UNIT_STATUS_4AM   Y  SCHEDULED  FREQ=DAILY;BYHOUR=4
-- CRM_MPM_OUTBOUND_6AM          Y  SCHEDULED  FREQ=DAILY;BYHOUR=6
-- CRM_MPM_OUTBOUND_10AM         Y  SCHEDULED  FREQ=DAILY;BYHOUR=10
-- CRM_MPM_OUTBOUND_2PM          Y  SCHEDULED  FREQ=DAILY;BYHOUR=14
-- CRM_MPM_OUTBOUND_5PM          Y  SCHEDULED  FREQ=DAILY;BYHOUR=17
-- CRM_MPM_RETRY_JOB             Y  SCHEDULED  FREQ=MINUTELY;INTERVAL=30
-- CRM_MPM_TIMEOUT_JOB           Y  SCHEDULED  FREQ=HOURLY;INTERVAL=1
-- =============================================================================
