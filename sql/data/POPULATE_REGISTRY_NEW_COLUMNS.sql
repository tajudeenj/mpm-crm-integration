/* ============================================================================
   POPULATE new REGISTRY columns for all 9 real services
   Run AFTER ALTER_TABLES_ADD_MISSING_COLUMNS.sql
   Run BEFORE compiling the package (SEND_TO_APIC depends on these being set)

   Maps each SERVICE_NAME to its record-type/event/api-version, matching
   exactly what was already correct in the Java properties file.
   ============================================================================ */

UPDATE CRM_MPM_API_REGISTRY SET APIC_API_VERSION='1', RECORD_TYPE_HDR='md_project',      EVENT_CODE_HDR='100000000' WHERE SERVICE_NAME = 'MD_PROJECT_CREATE';
UPDATE CRM_MPM_API_REGISTRY SET APIC_API_VERSION='1', RECORD_TYPE_HDR='md_project',      EVENT_CODE_HDR='100000001' WHERE SERVICE_NAME = 'MD_PROJECT_UPDATE';
UPDATE CRM_MPM_API_REGISTRY SET APIC_API_VERSION='1', RECORD_TYPE_HDR='md_building',     EVENT_CODE_HDR='100000000' WHERE SERVICE_NAME = 'MD_BUILDING_CREATE';
UPDATE CRM_MPM_API_REGISTRY SET APIC_API_VERSION='1', RECORD_TYPE_HDR='md_building',     EVENT_CODE_HDR='100000001' WHERE SERVICE_NAME = 'MD_BUILDING_UPDATE';
UPDATE CRM_MPM_API_REGISTRY SET APIC_API_VERSION='1', RECORD_TYPE_HDR='md_floor',        EVENT_CODE_HDR='100000000' WHERE SERVICE_NAME = 'MD_FLOOR_CREATE';
UPDATE CRM_MPM_API_REGISTRY SET APIC_API_VERSION='1', RECORD_TYPE_HDR='md_floor',        EVENT_CODE_HDR='100000001' WHERE SERVICE_NAME = 'MD_FLOOR_UPDATE';
UPDATE CRM_MPM_API_REGISTRY SET APIC_API_VERSION='1', RECORD_TYPE_HDR='md_unit',         EVENT_CODE_HDR='100000000' WHERE SERVICE_NAME = 'MD_UNIT_CREATE';
UPDATE CRM_MPM_API_REGISTRY SET APIC_API_VERSION='1', RECORD_TYPE_HDR='md_unit',         EVENT_CODE_HDR='100000001' WHERE SERVICE_NAME = 'MD_UNIT_UPDATE';
UPDATE CRM_MPM_API_REGISTRY SET APIC_API_VERSION='1', RECORD_TYPE_HDR='md_unit_status',  EVENT_CODE_HDR='100000001' WHERE SERVICE_NAME = 'MD_UNIT_STATUS_UPDATE';

COMMIT;

-- Verify all 9 rows are populated (should return 0 rows if all set correctly)
SELECT SERVICE_NAME, APIC_API_VERSION, RECORD_TYPE_HDR, EVENT_CODE_HDR
FROM CRM_MPM_API_REGISTRY
WHERE RECORD_TYPE_HDR IS NULL OR EVENT_CODE_HDR IS NULL OR APIC_API_VERSION IS NULL;

PROMPT ============================================================
PROMPT  If the query above returned ZERO rows, all 9 services are
PROMPT  correctly configured. If any rows appear, SERVICE_NAME values
PROMPT  in this script do not match what is actually in your table —
PROMPT  check actual SERVICE_NAME values with:
PROMPT  SELECT SERVICE_NAME FROM CRM_MPM_API_REGISTRY ORDER BY 1;
PROMPT ============================================================
