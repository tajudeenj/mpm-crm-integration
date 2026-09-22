/* ============================================================================
   ALTER TABLE — Add missing columns to real existing tables
   Run this BEFORE compiling PKG_CRM_INTEGRATION_SPEC.sql / BODY.
   Confirmed against actual DESC output — only adds columns that are
   genuinely missing, nothing duplicated.
   ============================================================================ */

/* ----------------------------------------------------------------------------
   CRM_MPM_API_REGISTRY — add header/version config columns
   ---------------------------------------------------------------------------- */
ALTER TABLE CRM_MPM_API_REGISTRY ADD (
    APIC_API_VERSION   VARCHAR2(20)  DEFAULT '1',
    RECORD_TYPE_HDR    VARCHAR2(100),
    EVENT_CODE_HDR     VARCHAR2(50)
);

COMMENT ON COLUMN CRM_MPM_API_REGISTRY.APIC_API_VERSION IS
  'Appended as ?api-version=N (or &api-version=N) on the APIC endpoint URL';
COMMENT ON COLUMN CRM_MPM_API_REGISTRY.RECORD_TYPE_HDR IS
  'Value sent in the record-type HTTP header to APIC, e.g. md_project, md_unit';
COMMENT ON COLUMN CRM_MPM_API_REGISTRY.EVENT_CODE_HDR IS
  'Value sent in the event HTTP header to APIC, e.g. 100000000=create, 100000001=update';


/* ----------------------------------------------------------------------------
   CRM_MPM_CRM_INTEGRATION_LOG — add ACK (LEG 1) and callback (LEG 2) detail
   ---------------------------------------------------------------------------- */
ALTER TABLE CRM_MPM_CRM_INTEGRATION_LOG ADD (
    ACK_REQUEST_ID         VARCHAR2(100),
    ACK_STATUS_CODE        VARCHAR2(10),
    ACK_DESCRIPTION        VARCHAR2(500),
    CRM_ENTITY_ID          VARCHAR2(200),
    CALLBACK_RESULT_CODE   VARCHAR2(50),
    CALLBACK_RESULT_DESC   VARCHAR2(500),
    CALLBACK_VALID_ERRORS  CLOB
);

COMMENT ON COLUMN CRM_MPM_CRM_INTEGRATION_LOG.ACK_REQUEST_ID IS
  'request_id from LEG 1 synchronous ACK JSON — used to match the LEG 2 async callback';
COMMENT ON COLUMN CRM_MPM_CRM_INTEGRATION_LOG.ACK_STATUS_CODE IS
  'status code from LEG 1 ACK JSON: 0000=accepted, 9999=rejected at intake';
COMMENT ON COLUMN CRM_MPM_CRM_INTEGRATION_LOG.ACK_DESCRIPTION IS
  'description field from LEG 1 ACK JSON';
COMMENT ON COLUMN CRM_MPM_CRM_INTEGRATION_LOG.CRM_ENTITY_ID IS
  'D365 GUID returned in LEG 2 callback crm_entity_id field (null if callback failed)';
COMMENT ON COLUMN CRM_MPM_CRM_INTEGRATION_LOG.CALLBACK_RESULT_CODE IS
  'processing_result.result_code from LEG 2 callback: SUCCESS/VALIDATION_FAILED/RECORD_NOT_FOUND/DUPLICATE_RECORD';
COMMENT ON COLUMN CRM_MPM_CRM_INTEGRATION_LOG.CALLBACK_RESULT_DESC IS
  'processing_result.result_description from LEG 2 callback';
COMMENT ON COLUMN CRM_MPM_CRM_INTEGRATION_LOG.CALLBACK_VALID_ERRORS IS
  'processing_result.validation_errors array from LEG 2 callback, stored as JSON text';


/* ----------------------------------------------------------------------------
   Index to support fast lookup by ACK_REQUEST_ID (PROCESS_CRM_CALLBACK uses
   this to find the matching log row when CRM's callback arrives)
   ---------------------------------------------------------------------------- */
CREATE INDEX IX_CRM_LOG_ACK_REQID ON CRM_MPM_CRM_INTEGRATION_LOG (ACK_REQUEST_ID);


PROMPT ============================================================
PROMPT  Columns added successfully.
PROMPT  CRM_MPM_API_REGISTRY: +3 columns (APIC_API_VERSION, RECORD_TYPE_HDR, EVENT_CODE_HDR)
PROMPT  CRM_MPM_CRM_INTEGRATION_LOG: +7 columns (ACK_*, CRM_ENTITY_ID, CALLBACK_*)
PROMPT  Next: populate RECORD_TYPE_HDR and EVENT_CODE_HDR for all 9 registry rows.
PROMPT  Then compile PKG_CRM_INTEGRATION_SPEC.sql and BODY.
PROMPT ============================================================
