-- ============================================================
-- SOURCE_EXTRA_FILTER Deployment Script
-- Purpose : Add CREATION_DATE <> LAST_UPDATE_DATE filter
--           to UPDATE VIEW-based services only
-- Run on  : DEV first, then SIT
-- Date    : Oct 2026
-- ============================================================

-- -------------------------------------------------------
-- STEP 1: Add column to registry table (run once)
-- Skip if column already exists
-- -------------------------------------------------------
ALTER TABLE CRM_MPM_API_REGISTRY
ADD SOURCE_EXTRA_FILTER VARCHAR2(500);

COMMENT ON COLUMN CRM_MPM_API_REGISTRY.SOURCE_EXTRA_FILTER IS
'Optional extra WHERE condition appended to outbound query after watermark filter. Example: CREATION_DATE <> LAST_UPDATE_DATE';

-- -------------------------------------------------------
-- STEP 2: Set filter on UPDATE VIEW-based services only
-- Skips: PROCEDURE type, rows with no SOURCE_FILTER_COL
-- Affected: Unit/Floor/Building/Property/WorkRequest UPDATE
-- -------------------------------------------------------
UPDATE CRM_MPM_API_REGISTRY
SET    SOURCE_EXTRA_FILTER = 'CREATION_DATE <> LAST_UPDATE_DATE'
WHERE  OPERATION_TYPE  = 'UPDATE'
AND    SOURCE_TYPE     = 'VIEW'
AND    SOURCE_FILTER_COL IS NOT NULL
AND    IS_ACTIVE       = 'Y'
AND    SOURCE_VIEW     != 'XXMPM_CRM_UPDATE_WORKREQ_V';  -- WorkRequest does not need this filter

-- Confirm WorkRequest has no extra filter
-- Expected: SOURCE_EXTRA_FILTER = NULL for REGISTRY_ID 125
SELECT REGISTRY_ID, ENTITY_NAME, SOURCE_VIEW, SOURCE_EXTRA_FILTER
FROM   CRM_MPM_API_REGISTRY
WHERE  SOURCE_VIEW = 'XXMPM_CRM_UPDATE_WORKREQ_V';

COMMIT;

-- -------------------------------------------------------
-- STEP 3: Verify — expected 5 rows updated
-- REGISTRY_ID: 29, 27, 25, 23, 125
-- -------------------------------------------------------
SELECT REGISTRY_ID,
       ENTITY_NAME,
       OPERATION_TYPE,
       SOURCE_TYPE,
       SOURCE_VIEW,
       SOURCE_FILTER_COL,
       SOURCE_EXTRA_FILTER,
       IS_ACTIVE
FROM   CRM_MPM_API_REGISTRY
WHERE  IS_ACTIVE = 'Y'
ORDER  BY OPERATION_TYPE, SOURCE_TYPE, REGISTRY_ID;

-- -------------------------------------------------------
-- STEP 4: Watermark check
-- UPDATE services should already have watermark rows.
-- If any are missing, insert them:
-- -------------------------------------------------------
INSERT INTO CRM_MPM_API_WATERMARK (REGISTRY_ID, LAST_RUN_STATUS, LAST_RUN_RECORDS)
SELECT R.REGISTRY_ID, 'INIT', 0
FROM   CRM_MPM_API_REGISTRY R
WHERE  R.IS_ACTIVE      = 'Y'
AND    R.SOURCE_TYPE    = 'VIEW'
AND    R.SOURCE_FILTER_COL IS NOT NULL
AND    NOT EXISTS (
    SELECT 1 FROM CRM_MPM_API_WATERMARK W
    WHERE  W.REGISTRY_ID = R.REGISTRY_ID
);

COMMIT;

-- -------------------------------------------------------
-- STEP 5: Verify watermark rows exist for all VIEW services
-- -------------------------------------------------------
SELECT R.REGISTRY_ID,
       R.SERVICE_NAME,
       R.OPERATION_TYPE,
       R.SOURCE_FILTER_COL,
       R.SOURCE_EXTRA_FILTER,
       TO_CHAR(W.LAST_PROCESSED_TS, 'DD-MON-YY HH24:MI') AS LAST_PROCESSED,
       W.LAST_RUN_STATUS
FROM   CRM_MPM_API_REGISTRY  R
JOIN   CRM_MPM_API_WATERMARK W ON W.REGISTRY_ID = R.REGISTRY_ID
WHERE  R.IS_ACTIVE   = 'Y'
AND    R.SOURCE_TYPE = 'VIEW'
ORDER  BY R.OPERATION_TYPE, R.REGISTRY_ID;

-- -------------------------------------------------------
-- STEP 6: Deploy updated package body
-- File: sql/schema/PKG_CRM_INTEGRATION_BODY_FINAL.sql
-- The package now reads SOURCE_EXTRA_FILTER and appends
-- it to the WHERE clause after the watermark condition:
--
--   WHERE SOURCE_FILTER_COL > :wm
--   AND   <SOURCE_EXTRA_FILTER>   <-- new
--
-- What changes in the package (lines 871-883):
--   CASE
--     WHEN reg.SOURCE_EXTRA_FILTER IS NOT NULL
--     THEN ' AND ' || reg.SOURCE_EXTRA_FILTER
--     ELSE ''
--   END
--
-- Same logic applied to final MAX watermark query too.
-- -------------------------------------------------------

-- -------------------------------------------------------
-- STEP 7: Quick smoke test after package deploy
-- Run this to confirm UPDATE services pick up correctly
-- -------------------------------------------------------
/*
-- Should return only rows where last_update_date > watermark
-- AND creation_date <> last_update_date
SELECT COUNT(*) AS UNIT_UPDATES_PENDING
FROM   XXMPM_CRM_UNIT_UPDATE_V V
JOIN   CRM_MPM_API_WATERMARK   W ON W.REGISTRY_ID = 29
WHERE  V.LAST_UPDATE_DATE > W.LAST_PROCESSED_TS
AND    V.CREATION_DATE   <> V.LAST_UPDATE_DATE;

SELECT COUNT(*) AS BUILDING_UPDATES_PENDING
FROM   XXMPM_CRM_BUILDING_UPDATE_FULL_V V
JOIN   CRM_MPM_API_WATERMARK            W ON W.REGISTRY_ID = 25
WHERE  V.LAST_UPDATE_DATE > W.LAST_PROCESSED_TS
AND    V.CREATION_DATE   <> V.LAST_UPDATE_DATE;
*/
