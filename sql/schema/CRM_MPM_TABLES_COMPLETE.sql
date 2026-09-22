/* ============================================================================
   CRM MPM INTEGRATION — COMPLETE TABLE DESIGN
   All configuration is 100% driven by tables — no hardcoding in package.
   
   SIMPLE FLOW (read this first):
   
   SOURCE VIEW  →  BUILD JSON  →  GET TOKEN  →  POST to APIC  →  LOG (SENT)
        ↑                                                              ↓
   (registry tells us which view,              CRM processes async and fires
    which columns, which endpoint,             callback → PROCESS_CRM_CALLBACK
    which headers, which event code)           updates LOG → SUCCESS/FAILED
   
   ============================================================================ */


/* ============================================================================
   TABLE 1: CRM_MPM_API_CREDENTIALS
   PURPOSE : Stores OAuth2 token endpoint details.
             One row = one token endpoint (can be shared across many registries).
   ============================================================================ */
CREATE TABLE CRM_MPM_API_CREDENTIALS (
    CRED_CODE         VARCHAR2(50)   NOT NULL,   -- PK: e.g. 'MPM_APIC_CRED'
    TOKEN_URL         VARCHAR2(500)  NOT NULL,   -- https://apisitgateway.../oauth2/token
    CLIENT_ID         VARCHAR2(200)  NOT NULL,   -- bdbd7c57145bcbaaf4e81bdc16181287
    CLIENT_SECRET_REF VARCHAR2(500)  NOT NULL,   -- actual secret or vault ref
    GRANT_TYPE        VARCHAR2(50)   DEFAULT 'client_credentials',
    SCOPE             VARCHAR2(200),             -- powerapp:access
    TOKEN_CACHE_VALUE VARCHAR2(4000),            -- cached token (written by package)
    TOKEN_EXPIRY      TIMESTAMP,                 -- written by package after token fetch
    IS_ACTIVE         VARCHAR2(1)    DEFAULT 'Y',
    CREATED_DATE      TIMESTAMP      DEFAULT SYSTIMESTAMP,
    UPDATED_DATE      TIMESTAMP,
    CONSTRAINT PK_CRM_CREDENTIALS PRIMARY KEY (CRED_CODE)
);
/*
   HOW IT IS USED:
   - PKG_CRM_INTEGRATION.GET_BEARER_TOKEN reads this table.
   - If TOKEN_EXPIRY > now + 60s → returns TOKEN_CACHE_VALUE (no HTTP call).
   - Otherwise → POSTs to TOKEN_URL with CLIENT_ID + CLIENT_SECRET_REF + SCOPE.
   - Writes fresh token back to TOKEN_CACHE_VALUE + TOKEN_EXPIRY.

   SAMPLE DATA:
   CRED_CODE         = 'MPM_APIC_CRED'
   TOKEN_URL         = 'https://apisitgatewaylb.adib.co.ae:443/adib/oauth-client/oauth2/token'
   CLIENT_ID         = 'bdbd7c57145bcbaaf4e81bdc16181287'
   CLIENT_SECRET_REF = 'cb9ed345fcc99e9c165049a6f608ee5b'
   GRANT_TYPE        = 'client_credentials'
   SCOPE             = 'powerapp:access'
*/


/* ============================================================================
   TABLE 2: CRM_MPM_API_REGISTRY
   PURPOSE : One row per VIEW × OPERATION combination.
             This is the MASTER CONFIG table — everything flows from here.
             
   WHAT CHANGES PER VIEW:
     - SOURCE_VIEW       : which Oracle view to read (V_CRM_MPM_PROJECT, V_CRM_MPM_UNIT...)
     - APIC_ENDPOINT_URL : the Power Automate workflow URL (unique per entity type)
     - RECORD_TYPE_HDR   : 'md_project' / 'md_unit' / 'md_floor' etc (HTTP Header)
     - EVENT_CODE_HDR    : 100000000=create, 100000001=update (HTTP Header)
     - JSON_MAPPING_NAME : which rows in FIELD_MAPPING to use
   ============================================================================ */
CREATE TABLE CRM_MPM_API_REGISTRY (
    REGISTRY_ID            NUMBER         NOT NULL,   -- PK
    -- Entity identification
    ENTITY_NAME            VARCHAR2(100)  NOT NULL,   -- 'Property', 'Unit', 'Floor'
    SERVICE_NAME           VARCHAR2(100)  NOT NULL,   -- 'MD_PROJECT' — used by callback to find this row
    OPERATION_TYPE         VARCHAR2(20)   NOT NULL,   -- 'CREATE' or 'UPDATE'
    -- Credentials (FK to TABLE 1)
    CRED_CODE              VARCHAR2(50)   NOT NULL,   -- FK → CRM_MPM_API_CREDENTIALS
    -- APIC endpoint (all params stored here — change without touching package)
    APIC_ENDPOINT_URL      VARCHAR2(500)  NOT NULL,   -- base URL (without api-version param)
    APIC_API_VERSION       VARCHAR2(20)   DEFAULT '1',-- api-version query param value
    HTTP_METHOD            VARCHAR2(10)   DEFAULT 'POST',
    -- APIC custom headers (change values without recompiling package)
    RECORD_TYPE_HDR        VARCHAR2(100)  NOT NULL,   -- 'md_project','md_unit','md_floor' etc
    EVENT_CODE_HDR         VARCHAR2(50)   NOT NULL,   -- '100000000'=create, '100000001'=update
    -- Source data
    SOURCE_VIEW            VARCHAR2(128)  NOT NULL,   -- 'V_CRM_MPM_PROJECT'
    SOURCE_KEY_COL         VARCHAR2(128)  NOT NULL,   -- 'PROPERTY_ID' (PK col of the view)
    SOURCE_FILTER_COL      VARCHAR2(128)  NOT NULL,   -- 'LAST_UPDATE_DATE' (watermark col)
    SOURCE_TYPE            VARCHAR2(20)   DEFAULT 'VIEW', -- 'VIEW' or 'PROCEDURE'
    SOURCE_PROC            VARCHAR2(128),              -- only if SOURCE_TYPE='PROCEDURE'
    -- JSON field mapping
    JSON_MAPPING_NAME      VARCHAR2(100)  NOT NULL,   -- FK → CRM_MPM_API_FIELD_MAPPING
    -- Retry config
    MAX_RETRY_COUNT        NUMBER         DEFAULT 3,
    TIMEOUT_MINUTES        NUMBER         DEFAULT 30,
    RETRY_INTERVAL_MINUTES NUMBER         DEFAULT 10,
    -- Callback config: where to write the CRM result back in Oracle
    CALLBACK_TARGET_TABLE  VARCHAR2(128),             -- 'MPM_PROPERTIES'
    CALLBACK_STATUS_COL    VARCHAR2(128),             -- 'CRM_SYNC_STATUS'
    CALLBACK_REF_COL       VARCHAR2(128),             -- 'CRM_REFERENCE_NO' (crm_entity_id)
    CALLBACK_KEY_COL       VARCHAR2(128),             -- 'PROPERTY_ID'
    POST_CALLBACK_PROC     VARCHAR2(128),             -- optional custom proc after callback
    -- Admin
    IS_ACTIVE              VARCHAR2(1)    DEFAULT 'Y',
    CREATED_DATE           TIMESTAMP      DEFAULT SYSTIMESTAMP,
    UPDATED_DATE           TIMESTAMP,
    CONSTRAINT PK_CRM_REGISTRY PRIMARY KEY (REGISTRY_ID),
    CONSTRAINT FK_CRM_REG_CRED FOREIGN KEY (CRED_CODE)
        REFERENCES CRM_MPM_API_CREDENTIALS(CRED_CODE)
);
/*
   HOW IT IS USED:
   - RUN_OUTBOUND_JOB loops over every IS_ACTIVE='Y' row here.
   - For each row it reads SOURCE_VIEW, calls BUILD_JSON_PAYLOAD, 
     then SEND_TO_APIC which adds:
       Header: record-type = RECORD_TYPE_HDR
       Header: event       = EVENT_CODE_HDR
       Param:  api-version = APIC_API_VERSION
   - PROCESS_CRM_CALLBACK finds the row by SERVICE_NAME to know
     which CALLBACK_TARGET_TABLE and CALLBACK_REF_COL to update.

   SAMPLE DATA (10 registries — one per view × operation):
   
   ID  | ENTITY    | SERVICE_NAME       | OP     | SOURCE_VIEW             | RECORD_TYPE_HDR    | EVENT_CODE
   ----|-----------|-------------------|--------|-------------------------|--------------------|----------
   101 | Property  | MD_PROJECT_CREATE | CREATE | V_CRM_MPM_PROJECT       | md_project         | 100000000
   102 | Property  | MD_PROJECT_UPDATE | UPDATE | V_CRM_MPM_PROJECT       | md_project         | 100000001
   103 | Unit      | MD_UNIT_CREATE    | CREATE | V_CRM_MPM_UNIT          | md_unit            | 100000000
   104 | Unit      | MD_UNIT_UPDATE    | UPDATE | V_CRM_MPM_UNIT          | md_unit            | 100000001
   105 | Floor     | MD_FLOOR_CREATE   | CREATE | V_CRM_MPM_FLOOR         | md_floor           | 100000000
   106 | Floor     | MD_FLOOR_UPDATE   | UPDATE | V_CRM_MPM_FLOOR         | md_floor           | 100000001
   107 | UnitStat  | MD_UNIT_STATUS_UPD| UPDATE | V_CRM_MPM_UNIT_STATUS   | md_unit_status     | 100000001
   108 | Block     | MD_BLOCK_CREATE   | CREATE | V_CRM_MPM_BLOCK         | md_block           | 100000000
   109 | Block     | MD_BLOCK_UPDATE   | UPDATE | V_CRM_MPM_BLOCK         | md_block           | 100000001
   110 | Cluster   | MD_CLUSTER_CREATE | CREATE | V_CRM_MPM_CLUSTER       | md_cluster         | 100000000
*/


/* ============================================================================
   TABLE 3: CRM_MPM_API_FIELD_MAPPING
   PURPOSE : Maps Oracle view column names → JSON path in the request body.
             One row per field, per entity mapping.
             Dot notation builds nested objects automatically.
   ============================================================================ */
CREATE TABLE CRM_MPM_API_FIELD_MAPPING (
    MAPPING_ID        NUMBER         GENERATED ALWAYS AS IDENTITY,
    JSON_MAPPING_NAME VARCHAR2(100)  NOT NULL,   -- links to REGISTRY.JSON_MAPPING_NAME
    SOURCE_COLUMN     VARCHAR2(128)  NOT NULL,   -- exact column name in the SOURCE_VIEW
    JSON_PATH         VARCHAR2(200)  NOT NULL,   -- dot path e.g. 'region.region_id'
    DATA_TYPE         VARCHAR2(20)   DEFAULT 'STRING', -- STRING / NUMBER / BOOLEAN
    DATE_FORMAT       VARCHAR2(50),              -- for DATE columns: 'YYYY-MM-DD'
    IS_MANDATORY      VARCHAR2(1)    DEFAULT 'N',-- 'Y' = raise error if NULL
    DISPLAY_ORDER     NUMBER         DEFAULT 10,
    IS_ACTIVE         VARCHAR2(1)    DEFAULT 'Y',
    CONSTRAINT PK_CRM_FIELD_MAP PRIMARY KEY (MAPPING_ID)
);
CREATE INDEX IX_FIELD_MAP_NAME ON CRM_MPM_API_FIELD_MAPPING (JSON_MAPPING_NAME, IS_ACTIVE);
/*
   HOW IT IS USED:
   - BUILD_JSON_PAYLOAD reads rows WHERE JSON_MAPPING_NAME = registry.JSON_MAPPING_NAME
   - For each row: fetches SOURCE_COLUMN value from the view, writes it to JSON_PATH
   - Dot paths like 'region.region_id' produce:  { "region": { "region_id": "02" } }

   SAMPLE DATA (md_project):
   JSON_MAPPING_NAME    | SOURCE_COLUMN | JSON_PATH           | DATA_TYPE
   ---------------------|---------------|---------------------|----------
   MD_PROJECT_MAPPING   | PROPERTY_ID   | property_id         | STRING
   MD_PROJECT_MAPPING   | PROPERTY_NAME | property_name       | STRING
   MD_PROJECT_MAPPING   | REGION_ID     | region.region_id    | STRING
   MD_PROJECT_MAPPING   | REGION_NAME   | region.region_name  | STRING
   MD_PROJECT_MAPPING   | CITY_ID       | city.city_id        | STRING
   MD_PROJECT_MAPPING   | CITY_NAME     | city.city_name      | STRING
   ... (22 rows total for md_project)
   
   For md_unit — different JSON_MAPPING_NAME, different SOURCE_COLUMNs, different JSON_PATHs
   For md_floor — same pattern, its own JSON_MAPPING_NAME
*/


/* ============================================================================
   TABLE 4: CRM_MPM_API_WATERMARK
   PURPOSE : Tracks last-processed timestamp per registry.
             Prevents re-processing already-sent records after a crash.
   ============================================================================ */
CREATE TABLE CRM_MPM_API_WATERMARK (
    REGISTRY_ID        NUMBER        NOT NULL,   -- FK → CRM_MPM_API_REGISTRY
    LAST_PROCESSED_TS  TIMESTAMP     DEFAULT TIMESTAMP '2000-01-01 00:00:00',
    LAST_RUN_STATUS    VARCHAR2(100),
    LAST_RUN_RECORDS   NUMBER        DEFAULT 0,
    UPDATED_DATE       TIMESTAMP,
    CONSTRAINT PK_CRM_WATERMARK PRIMARY KEY (REGISTRY_ID),
    CONSTRAINT FK_CRM_WM_REG FOREIGN KEY (REGISTRY_ID)
        REFERENCES CRM_MPM_API_REGISTRY(REGISTRY_ID)
);
/*
   HOW IT IS USED:
   - RUN_OUTBOUND_JOB reads LAST_PROCESSED_TS.
   - Queries: WHERE LAST_UPDATE_DATE > LAST_PROCESSED_TS
   - After each SENT record → updates LAST_PROCESSED_TS immediately (crash-safe).
*/


/* ============================================================================
   TABLE 5: CRM_MPM_CRM_INTEGRATION_LOG
   PURPOSE : Full audit trail — every send attempt and its outcome.
             LEG 1 (outbound) and LEG 2 (callback) both write here.
   ============================================================================ */
CREATE TABLE CRM_MPM_CRM_INTEGRATION_LOG (
    LOG_ID               NUMBER         GENERATED ALWAYS AS IDENTITY,
    -- What was sent
    REGISTRY_ID          NUMBER         NOT NULL,
    ENTITY_NAME          VARCHAR2(100),           -- 'Property', 'Unit' etc
    OPERATION_TYPE       VARCHAR2(20),            -- 'CREATE' / 'UPDATE'
    SOURCE_RECORD_ID     VARCHAR2(200)  NOT NULL, -- e.g. 'KI-9383'
    TRANSACTION_GROUP_ID VARCHAR2(40),            -- GUID — groups all attempts for same record
    ATTEMPT_NO           NUMBER         DEFAULT 1,
    -- LEG 1: outbound request
    REQUEST_PAYLOAD      CLOB,                    -- JSON body sent to APIC
    SENT_DATE            TIMESTAMP,
    HTTP_STATUS_CODE     VARCHAR2(10),            -- 200, 202, 400, 500 etc
    -- LEG 1: APIC synchronous ACK (CRM's immediate response)
    ACK_RESPONSE         CLOB,                    -- full JSON from APIC (LEG 1)
    ACK_REQUEST_ID       VARCHAR2(100),           -- request_id from ACK JSON
    ACK_STATUS_CODE      VARCHAR2(10),            -- '0000'=success, '9999'=failed
    ACK_DESCRIPTION      VARCHAR2(500),           -- 'Success' or error description
    -- Status after LEG 1
    FINAL_STATUS         VARCHAR2(30)   DEFAULT 'PENDING',
    --   PENDING          : sent, waiting for LEG 2 callback
    --   SENT             : ACK received OK (status=0000), awaiting async callback
    --   FAILED           : LEG 1 HTTP error OR ACK status=9999 (CRM rejected at intake)
    --   SUCCESS          : LEG 2 callback received with result_code=SUCCESS
    --   VALIDATION_FAILED: LEG 2 callback result_code=VALIDATION_FAILED
    --   RECORD_NOT_FOUND : LEG 2 callback result_code=RECORD_NOT_FOUND
    --   DUPLICATE_RECORD : LEG 2 callback result_code=DUPLICATE_RECORD
    --   TIMEOUT          : No LEG 2 callback within TIMEOUT_MINUTES
    --   EXHAUSTED        : All retries used up
    ERROR_CODE           VARCHAR2(50),
    ERROR_MESSAGE        VARCHAR2(4000),
    -- LEG 2: async callback from CRM
    CRM_ENTITY_ID        VARCHAR2(200),           -- crm_entity_id from callback (D365 GUID)
    CRM_REFERENCE_NO     VARCHAR2(200),           -- request_id from callback (same as ACK)
    CALLBACK_PAYLOAD     CLOB,                    -- full callback JSON
    CALLBACK_DATE        TIMESTAMP,
    CALLBACK_RESULT_CODE VARCHAR2(50),            -- SUCCESS/VALIDATION_FAILED/RECORD_NOT_FOUND/DUPLICATE_RECORD
    CALLBACK_RESULT_DESC VARCHAR2(500),
    CALLBACK_VALID_ERRORS CLOB,                  -- validation_errors array as JSON string
    -- Retry tracking
    RETRY_COUNT          NUMBER         DEFAULT 0,
    NEXT_RETRY_DATE      TIMESTAMP,
    IS_FINAL_ATTEMPT     VARCHAR2(1)    DEFAULT 'N',
    -- Admin
    CREATED_DATE         TIMESTAMP      DEFAULT SYSTIMESTAMP,
    UPDATED_DATE         TIMESTAMP,
    CONSTRAINT PK_CRM_INTG_LOG PRIMARY KEY (LOG_ID)
);
CREATE INDEX IX_INTG_LOG_REG_REC  ON CRM_MPM_CRM_INTEGRATION_LOG (REGISTRY_ID, SOURCE_RECORD_ID);
CREATE INDEX IX_INTG_LOG_STATUS   ON CRM_MPM_CRM_INTEGRATION_LOG (FINAL_STATUS, REGISTRY_ID);
CREATE INDEX IX_INTG_LOG_TXNGRP   ON CRM_MPM_CRM_INTEGRATION_LOG (TRANSACTION_GROUP_ID);
CREATE INDEX IX_INTG_LOG_REQID    ON CRM_MPM_CRM_INTEGRATION_LOG (ACK_REQUEST_ID);
/*
   HOW IT IS USED:
   LEG 1 (SEND_TO_APIC):
     INSERT row with STATUS='PENDING'
     → POST to APIC
     → Parse ACK: ACK_REQUEST_ID=request_id, ACK_STATUS_CODE=status ('0000'/'9999')
     → If ACK status='0000': FINAL_STATUS='SENT'
     → If ACK status='9999': FINAL_STATUS='FAILED', ERROR_MESSAGE=ACK.message
     → UPDATE row with HTTP_STATUS_CODE, ACK_RESPONSE, ACK fields, FINAL_STATUS
   
   LEG 2 (PROCESS_CRM_CALLBACK):
     → Find row by ACK_REQUEST_ID = callback.request_id
     → Parse: crm_entity_id, processing_result.result_code, validation_errors
     → Map result_code → FINAL_STATUS
     → UPDATE row: CRM_ENTITY_ID, CALLBACK_PAYLOAD, CALLBACK_RESULT_CODE, FINAL_STATUS
     → UPDATE entity table: CRM_REFERENCE_NO = crm_entity_id (the D365 GUID)
*/


/* ============================================================================
   TABLE 6: CRM_MPM_JOB_RUN_HISTORY
   PURPOSE : One row per scheduler execution — for monitoring and job-lock guard.
   ============================================================================ */
CREATE TABLE CRM_MPM_JOB_RUN_HISTORY (
    RUN_ID            NUMBER         GENERATED ALWAYS AS IDENTITY,
    JOB_NAME          VARCHAR2(60)   NOT NULL,   -- 'OUTBOUND_PUSH','TIMEOUT_JOB','RETRY_JOB'
    STATUS            VARCHAR2(20)   DEFAULT 'RUNNING',
    START_TIME        TIMESTAMP      DEFAULT SYSTIMESTAMP,
    END_TIME          TIMESTAMP,
    RECORDS_PROCESSED NUMBER         DEFAULT 0,
    RECORDS_SUCCESS   NUMBER         DEFAULT 0,
    RECORDS_FAILED    NUMBER         DEFAULT 0,
    ERROR_MESSAGE     VARCHAR2(4000),
    CONSTRAINT PK_CRM_JOB_HIST PRIMARY KEY (RUN_ID)
);
/*
   HOW IT IS USED:
   - Every job procedure inserts a RUNNING row at start (job-lock guard reads this).
   - Updates to COMPLETED or ERROR at end.
   - Job-lock: if RUNNING row exists with START_TIME < now - 5min → skip invocation.
*/


/* ============================================================================
   TABLE 7: CRM_MPM_ERROR_CODE_MASTER
   PURPOSE : Lookup table validating error codes from CRM callbacks.
             Maps CRM result_codes to Oracle-side error codes and descriptions.
   ============================================================================ */
CREATE TABLE CRM_MPM_ERROR_CODE_MASTER (
    ERROR_CODE        VARCHAR2(50)   NOT NULL,   -- e.g. 'VALIDATION_FAILED'
    ERROR_CATEGORY    VARCHAR2(50),              -- 'BUSINESS_ERROR','SYSTEM_ERROR'
    DESCRIPTION       VARCHAR2(500),
    IS_RETRYABLE      VARCHAR2(1)    DEFAULT 'N',-- 'Y' = RETRY_JOB will retry
    IS_ACTIVE         VARCHAR2(1)    DEFAULT 'Y',
    CONSTRAINT PK_CRM_ERR_MASTER PRIMARY KEY (ERROR_CODE)
);
/*
   SEED DATA — matches all 6 CRM callback cases:
   
   ERROR_CODE          | CATEGORY       | RETRYABLE | DESCRIPTION
   --------------------|----------------|-----------|---------------------------
   SUCCESS             | SUCCESS        | N         | Record created/updated OK
   VALIDATION_FAILED   | BUSINESS_ERROR | N         | CRM business rule rejected
   RECORD_NOT_FOUND    | BUSINESS_ERROR | N         | Target record missing in D365
   DUPLICATE_RECORD    | BUSINESS_ERROR | N         | Already exists in D365
   UNKNOWN_ERROR       | SYSTEM_ERROR   | Y         | Unexpected CRM error
   CONN_FAILED         | SYSTEM_ERROR   | Y         | Network/timeout
   AUTH_FAILED         | SYSTEM_ERROR   | Y         | Token expired mid-flight
   TIMEOUT             | SYSTEM_ERROR   | Y         | No callback within window
   EXHAUSTED           | SYSTEM_ERROR   | N         | All retries used
*/


/* ============================================================================
   VIEW 1: V_CRM_TIMEOUT_CANDIDATES
   PURPOSE : SENT/PENDING rows that have been waiting > TIMEOUT_MINUTES.
             RUN_TIMEOUT_JOB reads this — does NOT include MAX_RETRY_COUNT
             (that comes from REGISTRY join inside the job).
   ============================================================================ */
CREATE OR REPLACE VIEW V_CRM_TIMEOUT_CANDIDATES AS
SELECT
    L.LOG_ID,
    L.REGISTRY_ID,
    L.SOURCE_RECORD_ID,
    L.TRANSACTION_GROUP_ID,
    L.ATTEMPT_NO,
    L.RETRY_COUNT,
    L.SENT_DATE,
    L.FINAL_STATUS
FROM CRM_MPM_CRM_INTEGRATION_LOG L
JOIN CRM_MPM_API_REGISTRY         R ON R.REGISTRY_ID = L.REGISTRY_ID
WHERE L.FINAL_STATUS IN ('SENT', 'PENDING')
  AND L.SENT_DATE    < SYSTIMESTAMP - (R.TIMEOUT_MINUTES / 1440)
  AND R.IS_ACTIVE    = 'Y';


/* ============================================================================
   VIEW 2: V_CRM_PENDING_RETRY
   PURPOSE : FAILED/TIMEOUT rows eligible for retry (retries remaining,
             interval elapsed). RUN_RETRY_JOB reads this.
   ============================================================================ */
CREATE OR REPLACE VIEW V_CRM_PENDING_RETRY AS
SELECT
    L.LOG_ID,
    L.REGISTRY_ID,
    L.SOURCE_RECORD_ID,
    L.TRANSACTION_GROUP_ID,
    L.ATTEMPT_NO,
    L.RETRY_COUNT,
    R.MAX_RETRY_COUNT,
    R.RETRY_INTERVAL_MINUTES,
    L.FINAL_STATUS
FROM CRM_MPM_CRM_INTEGRATION_LOG L
JOIN CRM_MPM_API_REGISTRY         R ON R.REGISTRY_ID = L.REGISTRY_ID
WHERE L.FINAL_STATUS   IN ('FAILED', 'TIMEOUT')
  AND L.RETRY_COUNT    <  R.MAX_RETRY_COUNT
  AND (L.NEXT_RETRY_DATE IS NULL OR L.NEXT_RETRY_DATE <= SYSTIMESTAMP)
  AND L.IS_FINAL_ATTEMPT = 'N'
  AND R.IS_ACTIVE        = 'Y';


/* ============================================================================
   MASTER SEED DATA
   All 10 registry entries + error code master.
   Add your actual endpoint URLs and adjust SOURCE_VIEW names.
   ============================================================================ */

-- ERROR CODE MASTER
INSERT INTO CRM_MPM_ERROR_CODE_MASTER VALUES ('SUCCESS',          'SUCCESS',        'Record processed successfully in D365',                   'N','Y');
INSERT INTO CRM_MPM_ERROR_CODE_MASTER VALUES ('VALIDATION_FAILED','BUSINESS_ERROR', 'CRM business rule validation failed',                     'N','Y');
INSERT INTO CRM_MPM_ERROR_CODE_MASTER VALUES ('RECORD_NOT_FOUND', 'BUSINESS_ERROR', 'Target record not found in D365',                         'N','Y');
INSERT INTO CRM_MPM_ERROR_CODE_MASTER VALUES ('DUPLICATE_RECORD', 'BUSINESS_ERROR', 'Record already exists in D365',                           'N','Y');
INSERT INTO CRM_MPM_ERROR_CODE_MASTER VALUES ('UNKNOWN_ERROR',    'SYSTEM_ERROR',   'Unexpected error from CRM',                               'Y','Y');
INSERT INTO CRM_MPM_ERROR_CODE_MASTER VALUES ('CONN_FAILED',      'SYSTEM_ERROR',   'Network connection or timeout to APIC',                   'Y','Y');
INSERT INTO CRM_MPM_ERROR_CODE_MASTER VALUES ('AUTH_FAILED',      'SYSTEM_ERROR',   'Bearer token rejected by APIC',                           'Y','Y');
INSERT INTO CRM_MPM_ERROR_CODE_MASTER VALUES ('TIMEOUT',          'SYSTEM_ERROR',   'No callback received within timeout window',              'Y','Y');
INSERT INTO CRM_MPM_ERROR_CODE_MASTER VALUES ('EXHAUSTED',        'SYSTEM_ERROR',   'Maximum retry attempts reached, manual intervention needed','N','Y');
COMMIT;

-- CREDENTIALS (one row — shared by all registries)
INSERT INTO CRM_MPM_API_CREDENTIALS (
    CRED_CODE, TOKEN_URL, CLIENT_ID, CLIENT_SECRET_REF, GRANT_TYPE, SCOPE, IS_ACTIVE
) VALUES (
    'MPM_APIC_CRED',
    'https://apisitgatewaylb.adib.co.ae:443/adib/oauth-client/oauth2/token',
    'bdbd7c57145bcbaaf4e81bdc16181287',
    'cb9ed345fcc99e9c165049a6f608ee5b',
    'client_credentials',
    'powerapp:access',
    'Y'
);

-- API REGISTRY — 10 entries (adjust APIC_ENDPOINT_URL per entity when confirmed)
-- Property (md_project)
INSERT INTO CRM_MPM_API_REGISTRY (
    REGISTRY_ID, ENTITY_NAME, SERVICE_NAME, OPERATION_TYPE,
    CRED_CODE, APIC_ENDPOINT_URL, APIC_API_VERSION, HTTP_METHOD,
    RECORD_TYPE_HDR, EVENT_CODE_HDR,
    SOURCE_VIEW, SOURCE_KEY_COL, SOURCE_FILTER_COL,
    JSON_MAPPING_NAME, MAX_RETRY_COUNT, TIMEOUT_MINUTES, RETRY_INTERVAL_MINUTES,
    CALLBACK_TARGET_TABLE, CALLBACK_STATUS_COL, CALLBACK_REF_COL, CALLBACK_KEY_COL, IS_ACTIVE
) VALUES (
    101, 'Property', 'MD_PROJECT_CREATE', 'CREATE',
    'MPM_APIC_CRED',
    'https://apiditgateway.adib.co.ae/adib/powerautomate/automations/direct/workflows/e287bb6987cc4254bfbaa954d3fd4954/triggers/manual/paths/invoke',
    '1', 'POST', 'md_project', '100000000',
    'V_CRM_MPM_PROJECT', 'PROPERTY_ID', 'LAST_UPDATE_DATE',
    'MD_PROJECT_MAPPING', 3, 30, 10,
    'MPM_PROPERTIES', 'CRM_SYNC_STATUS', 'CRM_REFERENCE_NO', 'PROPERTY_ID', 'Y'
);
INSERT INTO CRM_MPM_API_REGISTRY (
    REGISTRY_ID, ENTITY_NAME, SERVICE_NAME, OPERATION_TYPE,
    CRED_CODE, APIC_ENDPOINT_URL, APIC_API_VERSION, HTTP_METHOD,
    RECORD_TYPE_HDR, EVENT_CODE_HDR,
    SOURCE_VIEW, SOURCE_KEY_COL, SOURCE_FILTER_COL,
    JSON_MAPPING_NAME, MAX_RETRY_COUNT, TIMEOUT_MINUTES, RETRY_INTERVAL_MINUTES,
    CALLBACK_TARGET_TABLE, CALLBACK_STATUS_COL, CALLBACK_REF_COL, CALLBACK_KEY_COL, IS_ACTIVE
) VALUES (
    102, 'Property', 'MD_PROJECT_UPDATE', 'UPDATE',
    'MPM_APIC_CRED',
    'https://apiditgateway.adib.co.ae/adib/powerautomate/automations/direct/workflows/e287bb6987cc4254bfbaa954d3fd4954/triggers/manual/paths/invoke',
    '1', 'POST', 'md_project', '100000001',
    'V_CRM_MPM_PROJECT', 'PROPERTY_ID', 'LAST_UPDATE_DATE',
    'MD_PROJECT_UPDATE_MAPPING', 3, 30, 10,
    'MPM_PROPERTIES', 'CRM_SYNC_STATUS', 'CRM_REFERENCE_NO', 'PROPERTY_ID', 'Y'
);

-- Unit (md_unit)
INSERT INTO CRM_MPM_API_REGISTRY (
    REGISTRY_ID, ENTITY_NAME, SERVICE_NAME, OPERATION_TYPE,
    CRED_CODE, APIC_ENDPOINT_URL, APIC_API_VERSION, HTTP_METHOD,
    RECORD_TYPE_HDR, EVENT_CODE_HDR,
    SOURCE_VIEW, SOURCE_KEY_COL, SOURCE_FILTER_COL,
    JSON_MAPPING_NAME, MAX_RETRY_COUNT, TIMEOUT_MINUTES, RETRY_INTERVAL_MINUTES,
    CALLBACK_TARGET_TABLE, CALLBACK_STATUS_COL, CALLBACK_REF_COL, CALLBACK_KEY_COL, IS_ACTIVE
) VALUES (
    103, 'Unit', 'MD_UNIT_CREATE', 'CREATE',
    'MPM_APIC_CRED',
    'https://apiditgateway.adib.co.ae/adib/powerautomate/automations/direct/workflows/UNIT_WORKFLOW_ID/triggers/manual/paths/invoke',
    '1', 'POST', 'md_unit', '100000000',
    'V_CRM_MPM_UNIT', 'UNIT_ID', 'LAST_UPDATE_DATE',
    'MD_UNIT_MAPPING', 3, 30, 10,
    'MPM_UNITS', 'CRM_SYNC_STATUS', 'CRM_REFERENCE_NO', 'UNIT_ID', 'Y'
);
INSERT INTO CRM_MPM_API_REGISTRY (
    REGISTRY_ID, ENTITY_NAME, SERVICE_NAME, OPERATION_TYPE,
    CRED_CODE, APIC_ENDPOINT_URL, APIC_API_VERSION, HTTP_METHOD,
    RECORD_TYPE_HDR, EVENT_CODE_HDR,
    SOURCE_VIEW, SOURCE_KEY_COL, SOURCE_FILTER_COL,
    JSON_MAPPING_NAME, MAX_RETRY_COUNT, TIMEOUT_MINUTES, RETRY_INTERVAL_MINUTES,
    CALLBACK_TARGET_TABLE, CALLBACK_STATUS_COL, CALLBACK_REF_COL, CALLBACK_KEY_COL, IS_ACTIVE
) VALUES (
    104, 'Unit', 'MD_UNIT_UPDATE', 'UPDATE',
    'MPM_APIC_CRED',
    'https://apiditgateway.adib.co.ae/adib/powerautomate/automations/direct/workflows/UNIT_WORKFLOW_ID/triggers/manual/paths/invoke',
    '1', 'POST', 'md_unit', '100000001',
    'V_CRM_MPM_UNIT', 'UNIT_ID', 'LAST_UPDATE_DATE',
    'MD_UNIT_UPDATE_MAPPING', 3, 30, 10,
    'MPM_UNITS', 'CRM_SYNC_STATUS', 'CRM_REFERENCE_NO', 'UNIT_ID', 'Y'
);

-- Floor (md_floor)
INSERT INTO CRM_MPM_API_REGISTRY (
    REGISTRY_ID, ENTITY_NAME, SERVICE_NAME, OPERATION_TYPE,
    CRED_CODE, APIC_ENDPOINT_URL, APIC_API_VERSION, HTTP_METHOD,
    RECORD_TYPE_HDR, EVENT_CODE_HDR,
    SOURCE_VIEW, SOURCE_KEY_COL, SOURCE_FILTER_COL,
    JSON_MAPPING_NAME, MAX_RETRY_COUNT, TIMEOUT_MINUTES, RETRY_INTERVAL_MINUTES,
    CALLBACK_TARGET_TABLE, CALLBACK_STATUS_COL, CALLBACK_REF_COL, CALLBACK_KEY_COL, IS_ACTIVE
) VALUES (
    105, 'Floor', 'MD_FLOOR_CREATE', 'CREATE',
    'MPM_APIC_CRED',
    'https://apiditgateway.adib.co.ae/adib/powerautomate/automations/direct/workflows/FLOOR_WORKFLOW_ID/triggers/manual/paths/invoke',
    '1', 'POST', 'md_floor', '100000000',
    'V_CRM_MPM_FLOOR', 'FLOOR_ID', 'LAST_UPDATE_DATE',
    'MD_FLOOR_MAPPING', 3, 30, 10,
    'MPM_FLOORS', 'CRM_SYNC_STATUS', 'CRM_REFERENCE_NO', 'FLOOR_ID', 'Y'
);
INSERT INTO CRM_MPM_API_REGISTRY (
    REGISTRY_ID, ENTITY_NAME, SERVICE_NAME, OPERATION_TYPE,
    CRED_CODE, APIC_ENDPOINT_URL, APIC_API_VERSION, HTTP_METHOD,
    RECORD_TYPE_HDR, EVENT_CODE_HDR,
    SOURCE_VIEW, SOURCE_KEY_COL, SOURCE_FILTER_COL,
    JSON_MAPPING_NAME, MAX_RETRY_COUNT, TIMEOUT_MINUTES, RETRY_INTERVAL_MINUTES,
    CALLBACK_TARGET_TABLE, CALLBACK_STATUS_COL, CALLBACK_REF_COL, CALLBACK_KEY_COL, IS_ACTIVE
) VALUES (
    106, 'Floor', 'MD_FLOOR_UPDATE', 'UPDATE',
    'MPM_APIC_CRED',
    'https://apiditgateway.adib.co.ae/adib/powerautomate/automations/direct/workflows/FLOOR_WORKFLOW_ID/triggers/manual/paths/invoke',
    '1', 'POST', 'md_floor', '100000001',
    'V_CRM_MPM_FLOOR', 'FLOOR_ID', 'LAST_UPDATE_DATE',
    'MD_FLOOR_UPDATE_MAPPING', 3, 30, 10,
    'MPM_FLOORS', 'CRM_SYNC_STATUS', 'CRM_REFERENCE_NO', 'FLOOR_ID', 'Y'
);

-- Unit Status (md_unit_status) — UPDATE only
INSERT INTO CRM_MPM_API_REGISTRY (
    REGISTRY_ID, ENTITY_NAME, SERVICE_NAME, OPERATION_TYPE,
    CRED_CODE, APIC_ENDPOINT_URL, APIC_API_VERSION, HTTP_METHOD,
    RECORD_TYPE_HDR, EVENT_CODE_HDR,
    SOURCE_VIEW, SOURCE_KEY_COL, SOURCE_FILTER_COL,
    JSON_MAPPING_NAME, MAX_RETRY_COUNT, TIMEOUT_MINUTES, RETRY_INTERVAL_MINUTES,
    CALLBACK_TARGET_TABLE, CALLBACK_STATUS_COL, CALLBACK_REF_COL, CALLBACK_KEY_COL, IS_ACTIVE
) VALUES (
    107, 'Unit Status', 'MD_UNIT_STATUS_UPDATE', 'UPDATE',
    'MPM_APIC_CRED',
    'https://apiditgateway.adib.co.ae/adib/powerautomate/automations/direct/workflows/UNIT_STATUS_WORKFLOW_ID/triggers/manual/paths/invoke',
    '1', 'POST', 'md_unit_status', '100000001',
    'V_CRM_MPM_UNIT_STATUS', 'UNIT_ID', 'STATUS_CHANGE_DATE',
    'MD_UNIT_STATUS_MAPPING', 3, 30, 10,
    'MPM_UNITS', 'CRM_STATUS_SYNC', 'CRM_STATUS_REF', 'UNIT_ID', 'Y'
);

-- Block (md_block)
INSERT INTO CRM_MPM_API_REGISTRY (
    REGISTRY_ID, ENTITY_NAME, SERVICE_NAME, OPERATION_TYPE,
    CRED_CODE, APIC_ENDPOINT_URL, APIC_API_VERSION, HTTP_METHOD,
    RECORD_TYPE_HDR, EVENT_CODE_HDR,
    SOURCE_VIEW, SOURCE_KEY_COL, SOURCE_FILTER_COL,
    JSON_MAPPING_NAME, MAX_RETRY_COUNT, TIMEOUT_MINUTES, RETRY_INTERVAL_MINUTES,
    CALLBACK_TARGET_TABLE, CALLBACK_STATUS_COL, CALLBACK_REF_COL, CALLBACK_KEY_COL, IS_ACTIVE
) VALUES (
    108, 'Block', 'MD_BLOCK_CREATE', 'CREATE',
    'MPM_APIC_CRED',
    'https://apiditgateway.adib.co.ae/adib/powerautomate/automations/direct/workflows/BLOCK_WORKFLOW_ID/triggers/manual/paths/invoke',
    '1', 'POST', 'md_block', '100000000',
    'V_CRM_MPM_BLOCK', 'BLOCK_ID', 'LAST_UPDATE_DATE',
    'MD_BLOCK_MAPPING', 3, 30, 10,
    'MPM_BLOCKS', 'CRM_SYNC_STATUS', 'CRM_REFERENCE_NO', 'BLOCK_ID', 'Y'
);
INSERT INTO CRM_MPM_API_REGISTRY (
    REGISTRY_ID, ENTITY_NAME, SERVICE_NAME, OPERATION_TYPE,
    CRED_CODE, APIC_ENDPOINT_URL, APIC_API_VERSION, HTTP_METHOD,
    RECORD_TYPE_HDR, EVENT_CODE_HDR,
    SOURCE_VIEW, SOURCE_KEY_COL, SOURCE_FILTER_COL,
    JSON_MAPPING_NAME, MAX_RETRY_COUNT, TIMEOUT_MINUTES, RETRY_INTERVAL_MINUTES,
    CALLBACK_TARGET_TABLE, CALLBACK_STATUS_COL, CALLBACK_REF_COL, CALLBACK_KEY_COL, IS_ACTIVE
) VALUES (
    109, 'Block', 'MD_BLOCK_UPDATE', 'UPDATE',
    'MPM_APIC_CRED',
    'https://apiditgateway.adib.co.ae/adib/powerautomate/automations/direct/workflows/BLOCK_WORKFLOW_ID/triggers/manual/paths/invoke',
    '1', 'POST', 'md_block', '100000001',
    'V_CRM_MPM_BLOCK', 'BLOCK_ID', 'LAST_UPDATE_DATE',
    'MD_BLOCK_UPDATE_MAPPING', 3, 30, 10,
    'MPM_BLOCKS', 'CRM_SYNC_STATUS', 'CRM_REFERENCE_NO', 'BLOCK_ID', 'Y'
);

-- Cluster (md_cluster)
INSERT INTO CRM_MPM_API_REGISTRY (
    REGISTRY_ID, ENTITY_NAME, SERVICE_NAME, OPERATION_TYPE,
    CRED_CODE, APIC_ENDPOINT_URL, APIC_API_VERSION, HTTP_METHOD,
    RECORD_TYPE_HDR, EVENT_CODE_HDR,
    SOURCE_VIEW, SOURCE_KEY_COL, SOURCE_FILTER_COL,
    JSON_MAPPING_NAME, MAX_RETRY_COUNT, TIMEOUT_MINUTES, RETRY_INTERVAL_MINUTES,
    CALLBACK_TARGET_TABLE, CALLBACK_STATUS_COL, CALLBACK_REF_COL, CALLBACK_KEY_COL, IS_ACTIVE
) VALUES (
    110, 'Cluster', 'MD_CLUSTER_CREATE', 'CREATE',
    'MPM_APIC_CRED',
    'https://apiditgateway.adib.co.ae/adib/powerautomate/automations/direct/workflows/CLUSTER_WORKFLOW_ID/triggers/manual/paths/invoke',
    '1', 'POST', 'md_cluster', '100000000',
    'V_CRM_MPM_CLUSTER', 'CLUSTER_ID', 'LAST_UPDATE_DATE',
    'MD_CLUSTER_MAPPING', 3, 30, 10,
    'MPM_CLUSTERS', 'CRM_SYNC_STATUS', 'CRM_REFERENCE_NO', 'CLUSTER_ID', 'Y'
);
COMMIT;

-- WATERMARK — one row per registry
INSERT INTO CRM_MPM_API_WATERMARK (REGISTRY_ID, LAST_PROCESSED_TS)
SELECT REGISTRY_ID, TIMESTAMP '2000-01-01 00:00:00'
FROM CRM_MPM_API_REGISTRY;
COMMIT;

PROMPT ============================================================
PROMPT  All tables, views, and seed data created successfully.
PROMPT  Next step: add your FIELD_MAPPING rows for each entity.
PROMPT ============================================================
