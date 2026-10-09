-- ============================================================
-- CRM_MPM_ERROR_CODE_MASTER — Sequential dependency codes
-- Date    : 09-Oct-2026 (Session 9)
-- Run on  : DEV, then SIT (safe to re-run — MERGE)
--
-- Used by PKG_CRM_INTEGRATION:
--   PARENT_PENDING : child waiting for parent SUCCESS (RUN_OUTBOUND_JOB,
--                    RELEASE_PARENT_PENDING when parent is retried)
--   PARENT_FAILED  : parent is EXHAUSTED / VALIDATION_FAILED /
--                    RECORD_NOT_FOUND / CRM_REJECTED (RELEASE_PARENT_PENDING)
--
-- IS_RETRYABLE = 'N' is REQUIRED: these rows are moved on by
-- RELEASE_PARENT_PENDING, never by RUN_RETRY_JOB.
--
-- No code is needed for RELEASED — it is a FINAL_STATUS only
-- (bookkeeping on the old pending row), ERROR_CODE is not changed.
-- ============================================================

SET DEFINE OFF

-- ------------------------------------------------------------
-- NOTE (09-Oct-2026): SIT had a CHECK constraint on ERROR_CATEGORY
-- (not in repo DDL — added directly on the DB) that did not allow
-- 'DEPENDENCY', so the MERGE below failed. Tajudeen dropped it on SIT.
-- Re-adding it WITH 'DEPENDENCY' is in the optional block at the end.
-- ------------------------------------------------------------

-- Pre-check: SIT uses ERROR_DESCRIPTION (as the web app does).
-- If this returns DESCRIPTION instead, rename the column below.
SELECT COLUMN_NAME FROM USER_TAB_COLUMNS
WHERE  TABLE_NAME = 'CRM_MPM_ERROR_CODE_MASTER'
ORDER  BY COLUMN_ID;

MERGE INTO CRM_MPM_ERROR_CODE_MASTER e
USING (
    SELECT 'PARENT_PENDING' AS ERROR_CODE, 'DEPENDENCY' AS ERROR_CATEGORY,
           'Child record waiting for parent SUCCESS before sending' AS ERROR_DESCRIPTION,
           'N' AS IS_RETRYABLE FROM DUAL
    UNION ALL
    SELECT 'PARENT_FAILED', 'DEPENDENCY',
           'Parent record failed - child on hold until parent fixed and retried',
           'N' FROM DUAL
    UNION ALL
    -- Session 9: Manual Retry button sets this code so RUN_RETRY_JOB picks
    -- the row (it only retries codes with IS_RETRYABLE='Y')
    SELECT 'MANUAL_RETRY', 'RETRYABLE',
           'Manually queued for retry from admin tool after data/config fix',
           'Y' FROM DUAL
) s
ON (e.ERROR_CODE = s.ERROR_CODE)
WHEN MATCHED THEN UPDATE SET
    e.ERROR_CATEGORY    = s.ERROR_CATEGORY,
    e.ERROR_DESCRIPTION = s.ERROR_DESCRIPTION,
    e.IS_RETRYABLE      = s.IS_RETRYABLE
WHEN NOT MATCHED THEN INSERT (ERROR_CODE, ERROR_CATEGORY, ERROR_DESCRIPTION, IS_RETRYABLE)
VALUES (s.ERROR_CODE, s.ERROR_CATEGORY, s.ERROR_DESCRIPTION, s.IS_RETRYABLE);

COMMIT;

-- Verify: expect 3 rows — PARENT_* = 'N', MANUAL_RETRY = 'Y'
SELECT ERROR_CODE, ERROR_CATEGORY, IS_RETRYABLE, ERROR_DESCRIPTION
FROM   CRM_MPM_ERROR_CODE_MASTER
WHERE  ERROR_CODE IN ('PARENT_PENDING','PARENT_FAILED','MANUAL_RETRY');


-- ============================================================
-- OPTIONAL — re-add the ERROR_CATEGORY check, now incl. DEPENDENCY
-- Keeps category values clean (UI / triage group by them).
-- 1. See what categories exist today:
SELECT ERROR_CATEGORY, COUNT(*) FROM CRM_MPM_ERROR_CODE_MASTER
GROUP  BY ERROR_CATEGORY ORDER BY 1;
-- 2. Make sure every value above is in the list, then:
-- ALTER TABLE CRM_MPM_ERROR_CODE_MASTER
--   ADD CONSTRAINT CHK_CRM_ERR_CATEGORY
--   CHECK (ERROR_CATEGORY IN ('OK','CRM','APIC','NETWORK','SYSTEM',
--                             'RETRYABLE','CALLBACK','DEPENDENCY'));
-- (actual SIT categories, confirmed 09-Oct-2026)
-- ============================================================
