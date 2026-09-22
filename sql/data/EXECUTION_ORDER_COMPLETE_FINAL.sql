-- =============================================================================
-- EXECUTION ORDER -- COMPLETE FINAL SCRIPT
-- Sequential order for RUN_OUTBOUND_JOB
-- Unit Status runs separately at 11PM and 4AM
-- Author : ADIB EA Team (Tajudeen Jalaudin)
-- Date   : 2026-08-20
-- =============================================================================

SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED


-- =============================================================================
-- STEP 1: ADD EXECUTION_ORDER COLUMN (if not already added)
-- =============================================================================
BEGIN
    EXECUTE IMMEDIATE
        'ALTER TABLE CRM_MPM_API_REGISTRY ADD EXECUTION_ORDER NUMBER DEFAULT 99';
    DBMS_OUTPUT.PUT_LINE('Column added');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Column already exists -- skipping');
END;
/


-- =============================================================================
-- STEP 2: SET EXECUTION ORDER
-- =============================================================================

-- Order 1: Property CREATE
UPDATE CRM_MPM_API_REGISTRY
SET EXECUTION_ORDER = 1
WHERE SERVICE_NAME = 'MD_PROJECT_CREATE';

-- Order 2: Property UPDATE
UPDATE CRM_MPM_API_REGISTRY
SET EXECUTION_ORDER = 2
WHERE SERVICE_NAME = 'MD_PROJECT_UPDATE';

-- Order 3: Building CREATE
UPDATE CRM_MPM_API_REGISTRY
SET EXECUTION_ORDER = 3
WHERE SERVICE_NAME = 'MD_BUILDING_CREATE';

-- Order 4: Building UPDATE
UPDATE CRM_MPM_API_REGISTRY
SET EXECUTION_ORDER = 4
WHERE SERVICE_NAME = 'MD_BUILDING_UPDATE';

-- Order 5: Building Utility CREATE
UPDATE CRM_MPM_API_REGISTRY
SET EXECUTION_ORDER = 5
WHERE SERVICE_NAME = 'MD_BUILDING_UTILITY_CREATE';

-- Order 6: Building Utility UPDATE
UPDATE CRM_MPM_API_REGISTRY
SET EXECUTION_ORDER = 6
WHERE SERVICE_NAME = 'MD_BUILDING_UTILITY_UPDATE';

-- Order 7: Floor CREATE
UPDATE CRM_MPM_API_REGISTRY
SET EXECUTION_ORDER = 7
WHERE SERVICE_NAME = 'MD_FLOOR_CREATE';

-- Order 8: Floor UPDATE
UPDATE CRM_MPM_API_REGISTRY
SET EXECUTION_ORDER = 8
WHERE SERVICE_NAME = 'MD_FLOOR_UPDATE';

-- Order 9: Unit CREATE
UPDATE CRM_MPM_API_REGISTRY
SET EXECUTION_ORDER = 9
WHERE SERVICE_NAME = 'MD_UNIT_CREATE';

-- Order 10: Unit UPDATE
UPDATE CRM_MPM_API_REGISTRY
SET EXECUTION_ORDER = 10
WHERE SERVICE_NAME = 'MD_UNIT_UPDATE';

-- Order 11: Tenant Person CREATE
UPDATE CRM_MPM_API_REGISTRY
SET EXECUTION_ORDER = 11
WHERE SERVICE_NAME = 'MD_TENANT_PERSON_CREATE';

-- Order 12: Tenant Org CREATE
UPDATE CRM_MPM_API_REGISTRY
SET EXECUTION_ORDER = 12
WHERE SERVICE_NAME = 'MD_TENANT_ORG_CREATE';

-- Order 13: Work Request UPDATE
UPDATE CRM_MPM_API_REGISTRY
SET EXECUTION_ORDER = 13
WHERE SERVICE_NAME = 'MD_WORKREQUEST_UPDATE';

-- Order 99: NOT in RUN_OUTBOUND_JOB
-- Unit Status -- runs separately 11PM and 4AM
-- Staging-based -- Oracle team calls directly
UPDATE CRM_MPM_API_REGISTRY
SET EXECUTION_ORDER = 99
WHERE SERVICE_NAME IN (
    'MD_UNIT_ALL_STATUS',
    'MD_UNIT_STATUS_UPDATE',
    'MD_UNIT_UNAVAILABLE_UPDATE',
    'MD_CUSTOMER_BLACKLIST_UPDATE',
    'MD_UNIT_LEGAL_LOCK'
);

COMMIT;
DBMS_OUTPUT.PUT_LINE('All execution orders set successfully');


-- =============================================================================
-- STEP 3: VERIFY
-- =============================================================================
SELECT EXECUTION_ORDER,
       SERVICE_NAME,
       SOURCE_TYPE,
       IS_ACTIVE,
       SOURCE_VIEW
FROM CRM_MPM_API_REGISTRY
ORDER BY EXECUTION_ORDER, SERVICE_NAME;


-- =============================================================================
-- STEP 4: TWO PACKAGE CHANGES IN RUN_OUTBOUND_JOB
-- =============================================================================

/*
-- CHANGE A: Add ORDER BY and SOURCE_TYPE filter
-- FIND THIS:
FOR reg IN (
    SELECT r.*, w.LAST_PROCESSED_TS
    FROM CRM_MPM_API_REGISTRY r
    JOIN CRM_MPM_API_WATERMARK w ON w.REGISTRY_ID = r.REGISTRY_ID
    WHERE r.IS_ACTIVE = 'Y'
) LOOP

-- REPLACE WITH:
FOR reg IN (
    SELECT r.*, w.LAST_PROCESSED_TS
    FROM CRM_MPM_API_REGISTRY r
    JOIN CRM_MPM_API_WATERMARK w ON w.REGISTRY_ID = r.REGISTRY_ID
    WHERE r.IS_ACTIVE      = 'Y'
    AND   r.SOURCE_TYPE    = 'VIEW'
    AND   r.EXECUTION_ORDER < 99
    ORDER BY r.EXECUTION_ORDER
) LOOP


-- CHANGE B: Fix NULL watermark
-- FIND THIS:
' WHERE ' || reg.SOURCE_FILTER_COL || ' > :wm' ||

-- REPLACE WITH:
' WHERE (:wm IS NULL OR ' || reg.SOURCE_FILTER_COL || ' > :wm)' ||
*/


-- =============================================================================
-- STEP 5: COMPILE
-- =============================================================================
/*
ALTER PACKAGE PKG_CRM_INTEGRATION COMPILE BODY;

SELECT * FROM USER_ERRORS
WHERE NAME = 'PKG_CRM_INTEGRATION';
*/


-- =============================================================================
-- STEP 6: VERIFY SCHEDULER JOBS
-- Confirm unit status runs separately
-- =============================================================================
SELECT JOB_NAME, ENABLED,
       REPEAT_INTERVAL,
       TO_CHAR(NEXT_RUN_DATE,'DD-MON-YY HH24:MI') AS NEXT_RUN
FROM USER_SCHEDULER_JOBS
WHERE JOB_NAME LIKE 'CRM_MPM%'
ORDER BY JOB_NAME;


-- =============================================================================
-- STEP 7: MANUAL TEST
-- =============================================================================
/*
SET SERVEROUTPUT ON SIZE UNLIMITED
BEGIN
    PKG_CRM_INTEGRATION.RUN_OUTBOUND_JOB;
END;
/

-- Verify execution sequence in log
SELECT
    R.EXECUTION_ORDER,
    R.SERVICE_NAME,
    COUNT(*)            AS RECORDS_SENT,
    MAX(L.FINAL_STATUS) AS STATUS,
    TO_CHAR(MIN(L.SENT_DATE),'DD-MON-YY HH24:MI:SS') AS FIRST_SENT,
    TO_CHAR(MAX(L.SENT_DATE),'DD-MON-YY HH24:MI:SS') AS LAST_SENT
FROM CRM_MPM_CRM_INTEGRATION_LOG L
JOIN CRM_MPM_API_REGISTRY        R ON R.REGISTRY_ID = L.REGISTRY_ID
WHERE L.SENT_DATE >= TRUNC(SYSDATE)
GROUP BY R.EXECUTION_ORDER, R.SERVICE_NAME
ORDER BY R.EXECUTION_ORDER;
*/


-- =============================================================================
-- STEP 8: SUMMARY
-- =============================================================================
/*
RUN_OUTBOUND_JOB runs at: 6AM, 10AM, 2PM, 5PM
Sequence per run:
  Order  1 -- MD_PROJECT_CREATE
  Order  2 -- MD_PROJECT_UPDATE
  Order  3 -- MD_BUILDING_CREATE
  Order  4 -- MD_BUILDING_UPDATE
  Order  5 -- MD_BUILDING_UTILITY_CREATE
  Order  6 -- MD_BUILDING_UTILITY_UPDATE
  Order  7 -- MD_FLOOR_CREATE
  Order  8 -- MD_FLOOR_UPDATE
  Order  9 -- MD_UNIT_CREATE
  Order 10 -- MD_UNIT_UPDATE
  Order 11 -- MD_TENANT_PERSON_CREATE
  Order 12 -- MD_TENANT_ORG_CREATE
  Order 13 -- MD_WORKREQUEST_UPDATE

RUN_UNIT_UNAVAILABLE_BATCH runs at: 11PM, 4AM
  Sends ALL available + unavailable units
  Always after all other data synced to CRM

Staging-based (Oracle team calls directly):
  MD_CUSTOMER_BLACKLIST_UPDATE
  MD_UNIT_LEGAL_LOCK
*/
