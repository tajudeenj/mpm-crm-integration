/* ============================================================================
   CRM_MPM_API_REGISTRY — CLEAN INSERT for all 9 real services
   FIX: REGISTRY_ID is GENERATED ALWAYS AS IDENTITY — cannot be inserted
   directly. Oracle assigns it automatically. We capture the generated
   value with RETURNING INTO and PRINT it so you can copy the real IDs
   into Java's properties file afterward.

   FK ORDER: CRM_MPM_CRM_INTEGRATION_LOG.REGISTRY_ID references
   CRM_MPM_API_REGISTRY.REGISTRY_ID — child table cleared first.
   ============================================================================ */

SET SERVEROUTPUT ON SIZE UNLIMITED

-- ── Clear child table first (FK_LOG_REGISTRY depends on REGISTRY_ID) ────────
DELETE FROM CRM_MPM_CRM_INTEGRATION_LOG;
COMMIT;

-- ── Now safe to clear parent table ───────────────────────────────────────────
DELETE FROM CRM_MPM_API_REGISTRY;
COMMIT;

-- Also clear watermark rows (same FK pattern likely exists)
DELETE FROM CRM_MPM_API_WATERMARK;
COMMIT;


/* ============================================================================
   INSERT all 9 rows WITHOUT specifying REGISTRY_ID — Oracle generates it.
   Each statement captures the generated ID with RETURNING INTO and prints
   it via DBMS_OUTPUT so you can see the real REGISTRY_ID values assigned.
   ============================================================================ */
DECLARE
    v_id NUMBER;
BEGIN
    -- 1: PROPERTY CREATE
    INSERT INTO CRM_MPM_API_REGISTRY (
        ENTITY_NAME, OPERATION_TYPE, SOURCE_TYPE, SOURCE_VIEW,
        SOURCE_FILTER_COL, SOURCE_KEY_COL, JSON_MAPPING_NAME,
        APIC_ENDPOINT_URL, APIC_API_VERSION, RECORD_TYPE_HDR, EVENT_CODE_HDR,
        HTTP_METHOD, CRED_CODE, SERVICE_NAME,
        CALLBACK_TARGET_TABLE, CALLBACK_KEY_COL, CALLBACK_STATUS_COL, CALLBACK_REF_COL,
        TIMEOUT_MINUTES, MAX_RETRY_COUNT, RETRY_INTERVAL_MINUTES, IS_ACTIVE
    ) VALUES (
        'Property', 'CREATE', 'VIEW', 'XXMPM_CRM_PROPERTY_CREATE_V',
        'LAST_UPDATE_DATE', 'PROPERTY_ID', 'XXMPM_CRM_PROPERTY_CREATE_V',
        'https://apiditgateway.adib.co.ae/adib/powerautomate/automations/direct/workflows/e287bb6987cc4254bfbaa954d3fd4954/triggers/manual/paths/invoke',
        '1', 'md_project', '100000000',
        'POST', 'APIC_PXRM', 'MD_PROJECT_CREATE',
        'MPM_PROPERTIES', 'PROPERTY_ID', 'CRM_SYNC_STATUS', 'CRM_REFERENCE_NO',
        30, 3, 10, 'Y'
    ) RETURNING REGISTRY_ID INTO v_id;
    DBMS_OUTPUT.PUT_LINE('MD_PROJECT_CREATE          -> REGISTRY_ID = ' || v_id);

    -- 2: PROPERTY UPDATE
    INSERT INTO CRM_MPM_API_REGISTRY (
        ENTITY_NAME, OPERATION_TYPE, SOURCE_TYPE, SOURCE_VIEW,
        SOURCE_FILTER_COL, SOURCE_KEY_COL, JSON_MAPPING_NAME,
        APIC_ENDPOINT_URL, APIC_API_VERSION, RECORD_TYPE_HDR, EVENT_CODE_HDR,
        HTTP_METHOD, CRED_CODE, SERVICE_NAME,
        CALLBACK_TARGET_TABLE, CALLBACK_KEY_COL, CALLBACK_STATUS_COL, CALLBACK_REF_COL,
        TIMEOUT_MINUTES, MAX_RETRY_COUNT, RETRY_INTERVAL_MINUTES, IS_ACTIVE
    ) VALUES (
        'Property', 'UPDATE', 'VIEW', 'XXMPM_CRM_PROPERTY_UPDATE_V',
        'LAST_UPDATE_DATE', 'PROPERTY_ID', 'XXMPM_CRM_PROPERTY_UPDATE_V',
        'https://apiditgateway.adib.co.ae/adib/powerautomate/automations/direct/workflows/e287bb6987cc4254bfbaa954d3fd4954/triggers/manual/paths/invoke',
        '1', 'md_project', '100000001',
        'POST', 'APIC_PXRM', 'MD_PROJECT_UPDATE',
        'MPM_PROPERTIES', 'PROPERTY_ID', 'CRM_SYNC_STATUS', 'CRM_REFERENCE_NO',
        30, 3, 10, 'Y'
    ) RETURNING REGISTRY_ID INTO v_id;
    DBMS_OUTPUT.PUT_LINE('MD_PROJECT_UPDATE          -> REGISTRY_ID = ' || v_id);

    -- 3: BUILDING CREATE
    INSERT INTO CRM_MPM_API_REGISTRY (
        ENTITY_NAME, OPERATION_TYPE, SOURCE_TYPE, SOURCE_VIEW,
        SOURCE_FILTER_COL, SOURCE_KEY_COL, JSON_MAPPING_NAME,
        APIC_ENDPOINT_URL, APIC_API_VERSION, RECORD_TYPE_HDR, EVENT_CODE_HDR,
        HTTP_METHOD, CRED_CODE, SERVICE_NAME,
        CALLBACK_TARGET_TABLE, CALLBACK_KEY_COL, CALLBACK_STATUS_COL, CALLBACK_REF_COL,
        TIMEOUT_MINUTES, MAX_RETRY_COUNT, RETRY_INTERVAL_MINUTES, IS_ACTIVE
    ) VALUES (
        'Building', 'CREATE', 'VIEW', 'XXMPM_CRM_BUILDING_CREATE_V',
        'LAST_UPDATE_DATE', 'BUILDING_ID', 'XXMPM_CRM_BUILDING_CREATE_V',
        'https://apiditgateway.adib.co.ae/adib/powerautomate/automations/direct/workflows/BUILDING_WORKFLOW_ID/triggers/manual/paths/invoke',
        '1', 'md_building', '100000000',
        'POST', 'APIC_PXRM', 'MD_BUILDING_CREATE',
        'MPM_BUILDINGS', 'BUILDING_ID', 'CRM_SYNC_STATUS', 'CRM_REFERENCE_NO',
        30, 3, 10, 'Y'
    ) RETURNING REGISTRY_ID INTO v_id;
    DBMS_OUTPUT.PUT_LINE('MD_BUILDING_CREATE         -> REGISTRY_ID = ' || v_id);

    -- 4: BUILDING UPDATE (note: SOURCE_KEY_COL = UNIQUE_ID, view has no BUILDING_ID)
    INSERT INTO CRM_MPM_API_REGISTRY (
        ENTITY_NAME, OPERATION_TYPE, SOURCE_TYPE, SOURCE_VIEW,
        SOURCE_FILTER_COL, SOURCE_KEY_COL, JSON_MAPPING_NAME,
        APIC_ENDPOINT_URL, APIC_API_VERSION, RECORD_TYPE_HDR, EVENT_CODE_HDR,
        HTTP_METHOD, CRED_CODE, SERVICE_NAME,
        CALLBACK_TARGET_TABLE, CALLBACK_KEY_COL, CALLBACK_STATUS_COL, CALLBACK_REF_COL,
        TIMEOUT_MINUTES, MAX_RETRY_COUNT, RETRY_INTERVAL_MINUTES, IS_ACTIVE
    ) VALUES (
        'Building', 'UPDATE', 'VIEW', 'XXMPM_CRM_BUILDING_UPDATE_V',
        'LAST_UPDATE_DATE', 'UNIQUE_ID', 'XXMPM_CRM_BUILDING_UPDATE_V',
        'https://apiditgateway.adib.co.ae/adib/powerautomate/automations/direct/workflows/BUILDING_WORKFLOW_ID/triggers/manual/paths/invoke',
        '1', 'md_building', '100000001',
        'POST', 'APIC_PXRM', 'MD_BUILDING_UPDATE',
        'MPM_BUILDINGS', 'BUILDING_ID', 'CRM_SYNC_STATUS', 'CRM_REFERENCE_NO',
        30, 3, 10, 'Y'
    ) RETURNING REGISTRY_ID INTO v_id;
    DBMS_OUTPUT.PUT_LINE('MD_BUILDING_UPDATE         -> REGISTRY_ID = ' || v_id);

    -- 5: FLOOR CREATE
    INSERT INTO CRM_MPM_API_REGISTRY (
        ENTITY_NAME, OPERATION_TYPE, SOURCE_TYPE, SOURCE_VIEW,
        SOURCE_FILTER_COL, SOURCE_KEY_COL, JSON_MAPPING_NAME,
        APIC_ENDPOINT_URL, APIC_API_VERSION, RECORD_TYPE_HDR, EVENT_CODE_HDR,
        HTTP_METHOD, CRED_CODE, SERVICE_NAME,
        CALLBACK_TARGET_TABLE, CALLBACK_KEY_COL, CALLBACK_STATUS_COL, CALLBACK_REF_COL,
        TIMEOUT_MINUTES, MAX_RETRY_COUNT, RETRY_INTERVAL_MINUTES, IS_ACTIVE
    ) VALUES (
        'Floor', 'CREATE', 'VIEW', 'XXMPM_CRM_FLOOR_CREATE_V',
        'LAST_UPDATE_DATE', 'FLOOR_ID', 'XXMPM_CRM_FLOOR_CREATE_V',
        'https://apiditgateway.adib.co.ae/adib/powerautomate/automations/direct/workflows/FLOOR_WORKFLOW_ID/triggers/manual/paths/invoke',
        '1', 'md_floor', '100000000',
        'POST', 'APIC_PXRM', 'MD_FLOOR_CREATE',
        'MPM_FLOORS', 'FLOOR_ID', 'CRM_SYNC_STATUS', 'CRM_REFERENCE_NO',
        30, 3, 10, 'Y'
    ) RETURNING REGISTRY_ID INTO v_id;
    DBMS_OUTPUT.PUT_LINE('MD_FLOOR_CREATE            -> REGISTRY_ID = ' || v_id);

    -- 6: FLOOR UPDATE
    INSERT INTO CRM_MPM_API_REGISTRY (
        ENTITY_NAME, OPERATION_TYPE, SOURCE_TYPE, SOURCE_VIEW,
        SOURCE_FILTER_COL, SOURCE_KEY_COL, JSON_MAPPING_NAME,
        APIC_ENDPOINT_URL, APIC_API_VERSION, RECORD_TYPE_HDR, EVENT_CODE_HDR,
        HTTP_METHOD, CRED_CODE, SERVICE_NAME,
        CALLBACK_TARGET_TABLE, CALLBACK_KEY_COL, CALLBACK_STATUS_COL, CALLBACK_REF_COL,
        TIMEOUT_MINUTES, MAX_RETRY_COUNT, RETRY_INTERVAL_MINUTES, IS_ACTIVE
    ) VALUES (
        'Floor', 'UPDATE', 'VIEW', 'XXMPM_CRM_FLOOR_UPDATE_V',
        'LAST_UPDATE_DATE', 'FLOOR_ID', 'XXMPM_CRM_FLOOR_UPDATE_V',
        'https://apiditgateway.adib.co.ae/adib/powerautomate/automations/direct/workflows/FLOOR_WORKFLOW_ID/triggers/manual/paths/invoke',
        '1', 'md_floor', '100000001',
        'POST', 'APIC_PXRM', 'MD_FLOOR_UPDATE',
        'MPM_FLOORS', 'FLOOR_ID', 'CRM_SYNC_STATUS', 'CRM_REFERENCE_NO',
        30, 3, 10, 'Y'
    ) RETURNING REGISTRY_ID INTO v_id;
    DBMS_OUTPUT.PUT_LINE('MD_FLOOR_UPDATE            -> REGISTRY_ID = ' || v_id);

    -- 7: UNIT CREATE
    INSERT INTO CRM_MPM_API_REGISTRY (
        ENTITY_NAME, OPERATION_TYPE, SOURCE_TYPE, SOURCE_VIEW,
        SOURCE_FILTER_COL, SOURCE_KEY_COL, JSON_MAPPING_NAME,
        APIC_ENDPOINT_URL, APIC_API_VERSION, RECORD_TYPE_HDR, EVENT_CODE_HDR,
        HTTP_METHOD, CRED_CODE, SERVICE_NAME,
        CALLBACK_TARGET_TABLE, CALLBACK_KEY_COL, CALLBACK_STATUS_COL, CALLBACK_REF_COL,
        TIMEOUT_MINUTES, MAX_RETRY_COUNT, RETRY_INTERVAL_MINUTES, IS_ACTIVE
    ) VALUES (
        'Unit', 'CREATE', 'VIEW', 'XXMPM_CRM_UNIT_CREATE_V',
        'LAST_UPDATE_DATE', 'UNIT_ID', 'XXMPM_CRM_UNIT_CREATE_V',
        'https://apiditgateway.adib.co.ae/adib/powerautomate/automations/direct/workflows/UNIT_WORKFLOW_ID/triggers/manual/paths/invoke',
        '1', 'md_unit', '100000000',
        'POST', 'APIC_PXRM', 'MD_UNIT_CREATE',
        'MPM_UNITS', 'UNIT_ID', 'CRM_SYNC_STATUS', 'CRM_REFERENCE_NO',
        30, 3, 10, 'Y'
    ) RETURNING REGISTRY_ID INTO v_id;
    DBMS_OUTPUT.PUT_LINE('MD_UNIT_CREATE             -> REGISTRY_ID = ' || v_id);

    -- 8: UNIT UPDATE
    INSERT INTO CRM_MPM_API_REGISTRY (
        ENTITY_NAME, OPERATION_TYPE, SOURCE_TYPE, SOURCE_VIEW,
        SOURCE_FILTER_COL, SOURCE_KEY_COL, JSON_MAPPING_NAME,
        APIC_ENDPOINT_URL, APIC_API_VERSION, RECORD_TYPE_HDR, EVENT_CODE_HDR,
        HTTP_METHOD, CRED_CODE, SERVICE_NAME,
        CALLBACK_TARGET_TABLE, CALLBACK_KEY_COL, CALLBACK_STATUS_COL, CALLBACK_REF_COL,
        TIMEOUT_MINUTES, MAX_RETRY_COUNT, RETRY_INTERVAL_MINUTES, IS_ACTIVE
    ) VALUES (
        'Unit', 'UPDATE', 'VIEW', 'XXMPM_CRM_UNIT_UPDATE_V',
        'LAST_UPDATE_DATE', 'UNIT_ID', 'XXMPM_CRM_UNIT_UPDATE_V',
        'https://apiditgateway.adib.co.ae/adib/powerautomate/automations/direct/workflows/UNIT_WORKFLOW_ID/triggers/manual/paths/invoke',
        '1', 'md_unit', '100000001',
        'POST', 'APIC_PXRM', 'MD_UNIT_UPDATE',
        'MPM_UNITS', 'UNIT_ID', 'CRM_SYNC_STATUS', 'CRM_REFERENCE_NO',
        30, 3, 10, 'Y'
    ) RETURNING REGISTRY_ID INTO v_id;
    DBMS_OUTPUT.PUT_LINE('MD_UNIT_UPDATE             -> REGISTRY_ID = ' || v_id);

    -- 9: UNIT STATUS UPDATE
    INSERT INTO CRM_MPM_API_REGISTRY (
        ENTITY_NAME, OPERATION_TYPE, SOURCE_TYPE, SOURCE_VIEW,
        SOURCE_FILTER_COL, SOURCE_KEY_COL, JSON_MAPPING_NAME,
        APIC_ENDPOINT_URL, APIC_API_VERSION, RECORD_TYPE_HDR, EVENT_CODE_HDR,
        HTTP_METHOD, CRED_CODE, SERVICE_NAME,
        CALLBACK_TARGET_TABLE, CALLBACK_KEY_COL, CALLBACK_STATUS_COL, CALLBACK_REF_COL,
        TIMEOUT_MINUTES, MAX_RETRY_COUNT, RETRY_INTERVAL_MINUTES, IS_ACTIVE
    ) VALUES (
        'UnitStatus', 'UPDATE', 'VIEW', 'XXMPM_CRM_UNIT_STATUS_UPDATE_V',
        'LAST_UPDATE_DATE', 'UNIT_ID', 'XXMPM_CRM_UNIT_STATUS_UPDATE_V',
        'https://apiditgateway.adib.co.ae/adib/powerautomate/automations/direct/workflows/UNIT_STATUS_WORKFLOW_ID/triggers/manual/paths/invoke',
        '1', 'md_unit_status', '100000001',
        'POST', 'APIC_PXRM', 'MD_UNIT_STATUS_UPDATE',
        'MPM_UNITS', 'UNIT_ID', 'CRM_STATUS_SYNC', 'CRM_STATUS_REF',
        30, 3, 10, 'Y'
    ) RETURNING REGISTRY_ID INTO v_id;
    DBMS_OUTPUT.PUT_LINE('MD_UNIT_STATUS_UPDATE      -> REGISTRY_ID = ' || v_id);

    COMMIT;
END;
/


/* ============================================================================
   Re-seed watermark — one row per registry, using the ACTUAL generated
   REGISTRY_IDs (not assumed values). Driven entirely by what's really in
   the table now.
   ============================================================================ */
INSERT INTO CRM_MPM_API_WATERMARK (REGISTRY_ID, LAST_PROCESSED_TS)
SELECT REGISTRY_ID, TIMESTAMP '2000-01-01 00:00:00'
FROM CRM_MPM_API_REGISTRY;
COMMIT;


/* ============================================================================
   VERIFY — copy these REGISTRY_ID values into Java's properties file
   (registry.<SERVICE>.registry_id=<this number>) replacing the old
   assumed 101-109 values.
   ============================================================================ */
SELECT REGISTRY_ID, SERVICE_NAME, SOURCE_VIEW, SOURCE_KEY_COL,
       RECORD_TYPE_HDR, EVENT_CODE_HDR, APIC_API_VERSION,
       CALLBACK_TARGET_TABLE, CALLBACK_KEY_COL, IS_ACTIVE
FROM CRM_MPM_API_REGISTRY
ORDER BY REGISTRY_ID;

PROMPT ============================================================
PROMPT  9 rows inserted — REGISTRY_ID values assigned by Oracle.
PROMPT  COPY the REGISTRY_ID values from the DBMS_OUTPUT above (or
PROMPT  the SELECT below) into Java's crm_integration.properties:
PROMPT    registry.<SERVICE_NAME>.registry_id=<actual_id>
PROMPT  for all 9 services. Do NOT assume 101-109 — use the real values.
PROMPT ============================================================
