SET DEFINE OFF

ALTER TABLE CRM_MPM_CRM_INTEGRATION_LOG
ADD (ACK_RESPONSE_TIMESTAMP VARCHAR2(50));

COMMENT ON COLUMN CRM_MPM_CRM_INTEGRATION_LOG.ACK_RESPONSE_TIMESTAMP IS
  'response_timestamp field from LEG 1 ACK JSON — e.g. 2026-06-19T10:15:32Z. Confirms exact time CRM received and logged the record.';

-- Verify
SELECT COLUMN_NAME, DATA_TYPE, DATA_LENGTH
FROM USER_TAB_COLUMNS
WHERE TABLE_NAME  = 'CRM_MPM_CRM_INTEGRATION_LOG'
  AND COLUMN_NAME = 'ACK_RESPONSE_TIMESTAMP';

PROMPT ============================================================
PROMPT  ACK_RESPONSE_TIMESTAMP column added.
PROMPT  Run order:
PROMPT    1. This script  (ALTER TABLE)
PROMPT    2. PKG_CRM_INTEGRATION_BODY_FINAL.sql  (recompile)
PROMPT ============================================================
