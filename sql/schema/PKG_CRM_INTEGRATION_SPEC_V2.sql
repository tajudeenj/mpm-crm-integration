SET DEFINE OFF

/* ============================================================================
   PKG_CRM_INTEGRATION — PACKAGE SPEC V2
   Changes from V1:
   - Added SUBMIT_TO_STAGING (instant push + auto retry via scheduler)
   - Added RUN_STAGING_JOB (scheduler for staging retry)
   - Added PROCESS_STAGING_CALLBACK (LEG 2 for staging records)
   Compile this BEFORE the package body.
   ============================================================================ */
CREATE OR REPLACE PACKAGE PKG_CRM_INTEGRATION AS

    /* ------------------------------------------------------------------
       UTILITY
       ------------------------------------------------------------------ */
    FUNCTION NEW_GUID RETURN VARCHAR2;

    /* ------------------------------------------------------------------
       X-UNIQUE-ID — generated fresh for every APIC call.
       ------------------------------------------------------------------ */
    FUNCTION GENERATE_UNIQUE_ID RETURN VARCHAR2;

    /* ------------------------------------------------------------------
       TOKEN — called internally, exposed for testing
       ------------------------------------------------------------------ */
    FUNCTION GET_BEARER_TOKEN(p_cred_code IN VARCHAR2) RETURN VARCHAR2;

    /* ------------------------------------------------------------------
       JSON BUILD — exposed for testing / debugging
       ------------------------------------------------------------------ */
    FUNCTION BUILD_JSON_PAYLOAD(
        p_registry_id IN NUMBER,
        p_source_view IN VARCHAR2,
        p_key_col     IN VARCHAR2,
        p_key_value   IN VARCHAR2
    ) RETURN CLOB;

    /* ------------------------------------------------------------------
       OUTBOUND SEND — view-based, for existing 13 services
       ------------------------------------------------------------------ */
    PROCEDURE SEND_TO_APIC(
        p_registry_id          IN  NUMBER,
        p_key_value            IN  VARCHAR2,
        p_transaction_group_id IN  VARCHAR2 DEFAULT NULL,
        p_attempt_no           IN  NUMBER   DEFAULT 1,
        p_log_id_out           OUT NUMBER
    );

    /* ------------------------------------------------------------------
       STAGING — for Oracle team to submit JSON directly
       Oracle team calls SUBMIT_TO_STAGING from their procedure.
       Instant push + auto retry via RUN_STAGING_JOB scheduler.
       ------------------------------------------------------------------ */
    PROCEDURE SUBMIT_TO_STAGING(
        p_service_name      IN  VARCHAR2,   -- e.g. 'MD_CUSTOMER_BLACKLIST_UPDATE'
        p_source_record_id  IN  VARCHAR2,   -- business key e.g. customer_id
        p_json_payload      IN  CLOB,       -- complete JSON built by Oracle team
        p_staging_id_out    OUT NUMBER,     -- staging record ID returned
        p_status_out        OUT VARCHAR2    -- SENT / FAILED-RETRY-SCHEDULED / ERROR
    );

    /* ------------------------------------------------------------------
       SCHEDULED JOBS — called by DBMS_SCHEDULER
       ------------------------------------------------------------------ */
    PROCEDURE RUN_OUTBOUND_JOB;    -- existing: view-based outbound
    PROCEDURE RUN_TIMEOUT_JOB;     -- existing: marks timed-out records
    PROCEDURE RUN_RETRY_JOB;       -- existing: retries failed log records
    PROCEDURE RUN_STAGING_JOB;     -- new: retries failed staging records

    /* ------------------------------------------------------------------
       CALLBACK — LEG 2 from ESB
       ------------------------------------------------------------------ */
    PROCEDURE PROCESS_CRM_CALLBACK(
        p_service_name     IN  VARCHAR2,
        p_callback_payload IN  CLOB,
        p_result_out       OUT VARCHAR2,
        p_status_code      OUT VARCHAR2,
        p_description      OUT VARCHAR2,
        p_x_unique_id      IN  VARCHAR2 DEFAULT NULL,
        p_channel_id       IN  VARCHAR2 DEFAULT NULL
    );

    /* ------------------------------------------------------------------
       STAGING CALLBACK — LEG 2 for staging-submitted records
       ESB calls this when CRM acknowledges a staging-originated request
       ------------------------------------------------------------------ */
    PROCEDURE PROCESS_STAGING_CALLBACK(
        p_request_id        IN  VARCHAR2,   -- request_id from LEG 1 ACK
        p_crm_reference     IN  VARCHAR2,   -- CRM record reference
        p_callback_status   IN  VARCHAR2,   -- status from CRM
        p_status_out        OUT VARCHAR2    -- SUCCESS or ERROR: ...
    );

END PKG_CRM_INTEGRATION;
/
