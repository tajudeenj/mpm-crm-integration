SET DEFINE OFF

ALTER TABLE CRM_MPM_CRM_INTEGRATION_LOG ADD (X_UNIQUE_ID VARCHAR2(60));

COMMENT ON COLUMN CRM_MPM_CRM_INTEGRATION_LOG.X_UNIQUE_ID IS
  'x-unique-id header value sent to APIC for every call. Format: CHANNEL_ID+timestamp+sequence (e.g. 81420260701143022123 0001). Used to trace a specific request in APIC server logs.';

-- Verify
SELECT COLUMN_NAME, DATA_TYPE, DATA_LENGTH
FROM USER_TAB_COLUMNS
WHERE TABLE_NAME = 'CRM_MPM_CRM_INTEGRATION_LOG'
  AND COLUMN_NAME = 'X_UNIQUE_ID';

PROMPT ============================================================
PROMPT  X_UNIQUE_ID column added to CRM_MPM_CRM_INTEGRATION_LOG.
PROMPT  Run in this order:
PROMPT    1. This script  (ALTER TABLE)
PROMPT    2. PKG_CRM_INTEGRATION_BODY_FINAL.sql  (recompile package)
PROMPT ============================================================
