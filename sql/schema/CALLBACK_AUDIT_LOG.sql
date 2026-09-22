SET DEFINE OFF

/* ============================================================================
   CRM_MPM_CALLBACK_AUDIT_LOG — Raw callback audit table
   Records EVERY callback received BEFORE any processing.
   Even if PROCESS_CRM_CALLBACK fails halfway, this row exists.
   This is your independent evidence that ESB called Oracle.
   ============================================================================ */

CREATE TABLE CRM_MPM_CALLBACK_AUDIT_LOG (
    AUDIT_ID          NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    RECEIVED_AT       TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    -- ESB headers
    SERVICE_NAME      VARCHAR2(100),
    X_UNIQUE_ID       VARCHAR2(60),
    CHANNEL_ID        VARCHAR2(20),
    -- Parsed from payload
    REQUEST_ID        VARCHAR2(100),
    STATUS_CODE       VARCHAR2(10),
    RESULT_CODE       VARCHAR2(50),
    -- Processing result
    PROCESSING_STATUS VARCHAR2(20),  -- RECEIVED / MATCHED / PROCESSED / FAILED / NO_LOG_MATCH
    PROCESSING_MSG    VARCHAR2(500),
    MATCHED_LOG_ID    NUMBER,        -- CRM_MPM_CRM_INTEGRATION_LOG.LOG_ID matched
    -- Exact JSON string Oracle returned to ESB via p_result_out
    RESPONSE_SENT     VARCHAR2(4000),
    -- Full raw payload
    RAW_PAYLOAD       CLOB,
    CREATED_DATE      TIMESTAMP      DEFAULT SYSTIMESTAMP
);

CREATE INDEX IX_CALLBACK_AUDIT_REQID   ON CRM_MPM_CALLBACK_AUDIT_LOG (REQUEST_ID);
CREATE INDEX IX_CALLBACK_AUDIT_SVC     ON CRM_MPM_CALLBACK_AUDIT_LOG (SERVICE_NAME, RECEIVED_AT);
CREATE INDEX IX_CALLBACK_AUDIT_STATUS  ON CRM_MPM_CALLBACK_AUDIT_LOG (PROCESSING_STATUS);

COMMENT ON TABLE CRM_MPM_CALLBACK_AUDIT_LOG IS
  'Raw audit of every LEG 2 callback received. Written FIRST before any processing. Independent of CRM_MPM_CRM_INTEGRATION_LOG.';

PROMPT ============================================================
PROMPT  CRM_MPM_CALLBACK_AUDIT_LOG created.
PROMPT  Run PKG_CRM_INTEGRATION_BODY_FINAL.sql after this.
PROMPT ============================================================
