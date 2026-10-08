-- ============================================================
-- Sequential Dependency Deployment Script
-- Purpose : Enforce Property → Building → Floor → Unit
--           CREATE order with callback confirmation
-- Scope   : CREATE services only (Registry IDs 22,24,26,28)
-- Run on  : DEV first, then SIT
-- ============================================================

-- -------------------------------------------------------
-- STEP 1: Add dependency columns to registry table
-- -------------------------------------------------------
ALTER TABLE CRM_MPM_API_REGISTRY
ADD DEPENDS_ON_REGISTRY_ID NUMBER;

ALTER TABLE CRM_MPM_API_REGISTRY
ADD PARENT_LINK_COL VARCHAR2(100);

COMMENT ON COLUMN CRM_MPM_API_REGISTRY.DEPENDS_ON_REGISTRY_ID IS
'Registry ID of parent service that must be SUCCESS before this service sends. NULL = no dependency.';

COMMENT ON COLUMN CRM_MPM_API_REGISTRY.PARENT_LINK_COL IS
'Column in THIS service source view whose value matches parent SOURCE_RECORD_ID in log. Used for dependency check.';

-- -------------------------------------------------------
-- STEP 2: Set dependency for CREATE services only
-- Property(22) → Building(24) → Floor(26) → Unit(28)
-- -------------------------------------------------------

-- Property CREATE — no parent, runs first
UPDATE CRM_MPM_API_REGISTRY
SET    DEPENDS_ON_REGISTRY_ID = NULL,
       PARENT_LINK_COL        = NULL
WHERE  REGISTRY_ID = 22;

-- Building CREATE — depends on Property (22)
-- BUILDING_CODE in building view = PROPERTY_CODE = SOURCE_RECORD_ID in property log
UPDATE CRM_MPM_API_REGISTRY
SET    DEPENDS_ON_REGISTRY_ID = 22,
       PARENT_LINK_COL        = 'BUILDING_CODE'
WHERE  REGISTRY_ID = 24;

-- Floor CREATE — depends on Building (24)
-- BUILDING_ID in floor view = SOURCE_RECORD_ID in building log
UPDATE CRM_MPM_API_REGISTRY
SET    DEPENDS_ON_REGISTRY_ID = 24,
       PARENT_LINK_COL        = 'BUILDING_ID'
WHERE  REGISTRY_ID = 26;

-- Unit CREATE — depends on Floor (26)
-- FLOOR_ID in unit view = SOURCE_RECORD_ID in floor log
UPDATE CRM_MPM_API_REGISTRY
SET    DEPENDS_ON_REGISTRY_ID = 26,
       PARENT_LINK_COL        = 'FLOOR_ID'
WHERE  REGISTRY_ID = 28;

COMMIT;

-- -------------------------------------------------------
-- STEP 3: Verify
-- -------------------------------------------------------
SELECT REGISTRY_ID,
       SERVICE_NAME,
       OPERATION_TYPE,
       SOURCE_KEY_COL,
       DEPENDS_ON_REGISTRY_ID,
       PARENT_LINK_COL
FROM   CRM_MPM_API_REGISTRY
WHERE  REGISTRY_ID IN (22, 24, 26, 28)
ORDER  BY REGISTRY_ID;

-- -------------------------------------------------------
-- STEP 4: Test dependency check manually
-- Before sending a Building record — run this to confirm
-- parent Property is SUCCESS
-- Replace 'MA00810' with actual BUILDING_CODE value
-- -------------------------------------------------------
/*
SELECT CASE WHEN COUNT(*) > 0 THEN 'PARENT OK - CAN SEND'
            ELSE 'PARENT NOT SUCCESS - HOLD'
       END AS DEPENDENCY_STATUS
FROM   CRM_MPM_CRM_INTEGRATION_LOG
WHERE  REGISTRY_ID      = 22         -- Property CREATE
AND    SOURCE_RECORD_ID = 'MA00810'  -- BUILDING_CODE value
AND    FINAL_STATUS     = 'SUCCESS';
*/

-- -------------------------------------------------------
-- STEP 5: Deploy updated package
-- File: sql/schema/PKG_CRM_INTEGRATION_BODY_FINAL.sql
--
-- What changes in RUN_OUTBOUND_JOB:
-- Before inserting each record into log and sending to APIC,
-- the package:
-- 1. Reads DEPENDS_ON_REGISTRY_ID and PARENT_LINK_COL from registry
-- 2. If DEPENDS_ON_REGISTRY_ID is NOT NULL:
--    - Reads PARENT_LINK_COL value from source view for this record
--    - Checks CRM_MPM_CRM_INTEGRATION_LOG for parent SUCCESS
--    - If parent NOT SUCCESS: skips this record (status = PARENT_PENDING)
--    - If parent SUCCESS: proceeds with send
-- -------------------------------------------------------
