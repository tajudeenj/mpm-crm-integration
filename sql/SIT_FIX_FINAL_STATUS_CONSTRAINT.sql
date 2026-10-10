-- ============================================================
-- FIX: CHECK constraint on CRM_MPM_CRM_INTEGRATION_LOG.FINAL_STATUS
-- Date : 10-Oct-2026 (Session 9)
--
-- PROBLEM
--   SYS_C005700592 (added on SIT directly, not in repo DDL) allows only:
--   PENDING, ACK_FAILED, SENT, SUCCESS, FAILED, TIMEOUT, ALREADY_PROCESSED, EXHAUSTED
--   The package also writes VALIDATION_FAILED, DUPLICATE_RECORD,
--   RECORD_NOT_FOUND, CRM_REJECTED (callback) and PARENT_PENDING,
--   PARENT_FAILED, RELEASED (dependency).
--   -> every non-SUCCESS callback crashes with ORA-02290 (CB_1003),
--      row stays SENT -> TIMEOUT -> resent (building 523118: 15 sends)
--   -> PARENT_PENDING / RELEASED writes fail the same way.
--
-- FIX: replace with a NAMED constraint that lists every status in use.
-- ============================================================

-- 1. Current values in the table (all must be in the new list)
SELECT FINAL_STATUS, COUNT(*) FROM CRM_MPM_CRM_INTEGRATION_LOG
GROUP  BY FINAL_STATUS ORDER BY 1;

-- 2. Drop the system-named constraint
ALTER TABLE CRM_MPM_CRM_INTEGRATION_LOG DROP CONSTRAINT SYS_C005700592;

-- 3. Re-create, named, with the full list
--    Keep the exact spelling from the old constraint for ALREADY_PROCESSED
--    (check step 1 output if unsure).
ALTER TABLE CRM_MPM_CRM_INTEGRATION_LOG
  ADD CONSTRAINT CK_CRM_LOG_FINAL_STATUS CHECK (FINAL_STATUS IN (
      -- outbound / LEG 1
      'PENDING','SENT','ACK_FAILED','ACK_OK','FAILED','TIMEOUT',
      'RETRY_IN_PROGRESS','UNKNOWN_ERROR','EXHAUSTED',
      -- callback / LEG 2
      'SUCCESS','ALREADY_PROCESSED','VALIDATION_FAILED','DUPLICATE_RECORD',
      'RECORD_NOT_FOUND','CRM_REJECTED',
      -- sequential dependency (Session 9)
      'PARENT_PENDING','PARENT_FAILED','RELEASED',
      -- admin
      'RESOLVED'
  ));

-- 4. Verify
SELECT CONSTRAINT_NAME, STATUS, SEARCH_CONDITION
FROM   USER_CONSTRAINTS
WHERE  TABLE_NAME = 'CRM_MPM_CRM_INTEGRATION_LOG' AND CONSTRAINT_TYPE = 'C'
AND    CONSTRAINT_NAME = 'CK_CRM_LOG_FINAL_STATUS';

-- RULE GOING FORWARD: any new FINAL_STATUS used by the package must be
-- added to CK_CRM_LOG_FINAL_STATUS in the same deployment.
