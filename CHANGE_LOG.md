# ADIB MPM CRM Integration — Complete Change Log
**Project:** MPM Properties CRM xRM Integration  
**Author:** Tajudeen Jalaudin — Senior Solution Architect, ADIB  
**Last Updated:** 23 September 2026

---

## 1. TABLE CHANGES

### CRM_MPM_API_REGISTRY — 3 columns added
| Column | Type | Purpose |
|--------|------|---------|
| APIC_API_VERSION | VARCHAR2(20) | Appended as ?api-version=N on APIC URL |
| RECORD_TYPE_HDR | VARCHAR2(100) | Value sent in record-type HTTP header to APIC |
| EVENT_CODE_HDR | VARCHAR2(50) | Value sent in event HTTP header (create=100000000, update=100000001) |

**Script:** `ALTER_TABLES_ADD_MISSING_COLUMNS.sql`

---

### CRM_MPM_CRM_INTEGRATION_LOG — 11 columns added
| Column | Type | Purpose |
|--------|------|---------|
| ACK_REQUEST_ID | VARCHAR2(100) | request_id from LEG 1 ACK — used to match LEG 2 callback |
| ACK_STATUS_CODE | VARCHAR2(10) | LEG 1 ACK status: 0000=accepted, 9999=rejected |
| ACK_DESCRIPTION | VARCHAR2(500) | Description from LEG 1 ACK JSON |
| ACK_RESPONSE_TIMESTAMP | VARCHAR2(50) | Timestamp CRM received and logged the record |
| CRM_ENTITY_ID | VARCHAR2(200) | D365 GUID returned in LEG 2 callback |
| CALLBACK_RESULT_CODE | VARCHAR2(50) | processing_result.result_code from LEG 2 |
| CALLBACK_RESULT_DESC | VARCHAR2(500) | processing_result.result_description from LEG 2 |
| CALLBACK_VALID_ERRORS | CLOB | validation_errors array from LEG 2 callback |
| CALLBACK_X_UNIQUE_ID | VARCHAR2(60) | x-unique-id header from ESB LEG 2 callback |
| CALLBACK_CHANNEL_ID | VARCHAR2(20) | x-channel-id header from ESB (e.g. PCRM) |
| X_UNIQUE_ID | VARCHAR2(60) | x-unique-id sent to APIC on every outbound call |

**Index added:** `IX_CRM_LOG_ACK_REQID` on ACK_REQUEST_ID (fast callback matching)

**Scripts:** `ALTER_TABLES_ADD_MISSING_COLUMNS.sql`, `ALTER_ADD_ACK_RESPONSE_TIMESTAMP.sql`, `ALTER_ADD_CALLBACK_HEADERS.sql`, `ALTER_ADD_X_UNIQUE_ID.sql`

---

### CRM_MPM_API_CREDENTIALS — 4 columns added
| Column | Type | Purpose |
|--------|------|---------|
| WALLET_PATH | VARCHAR2(200) | Oracle Wallet file path for UTL_HTTP.SET_WALLET |
| WALLET_PASSWORD | VARCHAR2(200) | Oracle Wallet password (plain text — encryption reverted, see note) |
| CLIENT_SECRET_ENCRYPTED | RAW(4000) | AES-256 encrypted CLIENT_SECRET |
| ENCRYPT_KEY_REF | VARCHAR2(100) | Reference to encryption key in CRM_MPM_ENCRYPT_CONFIG |

**Scripts:** `ALTER_ADD_WALLET_COLUMNS.sql`, `CREDENTIAL_ENCRYPTION_SETUP.sql`

> **NOTE on Wallet Password Encryption:** `WALLET_PASSWORD_ENC` BLOB column was added and encryption logic built, but reverted to plain text because the package had 6 SELECT cursors that did not include the new column — wallet always read as NULL, causing ORA-29273. Plain WALLET_PASSWORD is active. Wallet encryption can be revisited by adding WALLET_PASSWORD_ENC to all 6 cursors in the package.

---

### CRM_MPM_CALLBACK_AUDIT_LOG — 2 columns added
| Column | Type | Purpose |
|--------|------|---------|
| STATUS_CODE_SENT | VARCHAR2(20) | CB_0000/CB_1001/CB_1002/CB_1003 returned to ESB |
| DESCRIPTION_SENT | VARCHAR2(500) | Human readable result returned to ESB |

**Script:** `ALTER_ADD_STATUS_DESC_TO_AUDIT.sql`

---

### CRM_MPM_ENCRYPT_CONFIG — new table created
Stores AES-256 encryption keys for CLIENT_SECRET encryption.  
**Script:** `CREDENTIAL_ENCRYPTION_SETUP.sql`

---

## 2. PACKAGE CHANGES — PKG_CRM_INTEGRATION

### GET_BEARER_TOKEN
- Added `v_err_msg VARCHAR2(4000)` local variable to capture SQLERRM before use in RAISE_APPLICATION_ERROR
- **Why:** ORA-06550 — SQLERRM cannot be used directly in string concatenation in exception handlers

---

### BUILD_JSON_PAYLOAD
- `EXECUTE IMMEDIATE` for stored procedure source now uses `IN OUT` bind for ref cursor
- `DBMS_SQL.EXECUTE` return value captured in local variable (it is a FUNCTION not a statement)
- SQLERRM capture pattern applied in exception block
- **Why:** PLS-00363, PLS-00221 compile errors

---

### RUN_OUTBOUND_JOB
- Replaced implicit FOR loop cursor with explicit OPEN/FETCH/CLOSE pattern
- Introduced separate `v_status` variable — stopped reusing `v_filter_val` to check FINAL_STATUS
- **Watermark now advances per row** (immediately after each successful SEND_TO_APIC) instead of end of batch
- **Why:** PLS-00364, wrong watermark value, crash safety — crash mid-run no longer re-sends already sent records

---

### SEND_TO_APIC
- SQLERRM capture pattern in all exception handlers
- **status=9999 fix (today):** Now sets FINAL_STATUS=FAILED, ERROR_CODE=FAILURE (IS_RETRYABLE=Y)
- **Why:** CRM team confirmed 9999 = record NOT created in PxRM — must retry. Was wrongly treated as AUTH_OR_HEADER_ERROR

---

### PROCESS_CRM_CALLBACK
- SQLERRM capture pattern throughout
- **status=9999 with no result_code (today):** Now sets FAILED + FAILURE error code
- **6 new CRM error codes mapped (today):**

| result_code from CRM | FINAL_STATUS set | IS_RETRYABLE | Action |
|----------------------|-----------------|--------------|--------|
| INVALID_JSON | VALIDATION_FAILED | N | Fix payload structure |
| CONFIG_NOT_FOUND | CRM_REJECTED | N | Fix PxRM integration master config |
| MANDATORY_FIELD_MISSING | VALIDATION_FAILED | N | Fix source data in MPM |
| PRIMARY_FIELD_MISSING | VALIDATION_FAILED | N | Fix field mapping |
| LOOKUP_VALIDATION_FAILED | RECORD_NOT_FOUND | **Y** | Push parent record first — auto retry |
| FAILURE | FAILED | **Y** | Generic CRM failure — auto retry |

- **Why:** All 6 previously fell through to ELSE branch as UNKNOWN_ERROR — no visibility and no retry

---

### RUN_RETRY_JOB
- SQLERRM capture pattern in exception handler

---

### RUN_TIMEOUT_JOB
- SQLERRM capture pattern
- Explicit cursor pattern

---

## 3. DATA CHANGES

### CRM_MPM_ERROR_CODE_MASTER — new records inserted
**8 CRM error codes registered (today):**

| ERROR_CODE | IS_RETRYABLE | Description |
|------------|-------------|-------------|
| INVALID_JSON | N | Bad JSON payload |
| CONFIG_NOT_FOUND | N | PxRM integration master missing |
| MANDATORY_FIELD_MISSING | N | Required field absent |
| PRIMARY_FIELD_MISSING | N | Oracle key missing in payload |
| LOOKUP_VALIDATION_FAILED | **Y** | Parent/related record not in PxRM yet |
| DUPLICATE_RECORD | N | Already exists in PxRM |
| VALIDATION_FAILED | N | Fallback unknown validation |
| FAILURE | **Y** | Generic PostOperation catch |

**Script:** `INSERT_CRM_ERROR_CODES.sql`

---

### CRM_MPM_API_REGISTRY — 9 services configured
Property, Building, Floor, Unit, Tenant, Unit Status, Work Request etc.  
**Script:** `CRM_MPM_API_REGISTRY_INSERT.sql`

---

### CRM_MPM_API_FIELD_MAPPING — 15 mapping sets seeded
BUILDING_CREATE_MAP, BUILDING_UPDATE_MAP, FLOOR_CREATE_MAP, FLOOR_UPDATE_MAP,  
PROPERTY_CREATE_MAP, PROPERTY_UPDATE_MAP, TENANT_CREATE_MAP, UNIT_CREATE_MAP,  
UNIT_STATUS_UPDATE_MAP, UNIT_UPDATE_MAP, WORKREQUEST_UPDATE_MAP etc.  
**Script:** `CRM_MPM_FIELD_MAPPING_SEED.sql`

---

## 4. SCHEDULER CHANGES
8 jobs recreated (only CRM_MPM_* jobs — no other jobs touched):

| Job | Schedule |
|-----|---------|
| CRM_MPM_OUTBOUND_6AM | Daily 06:00 |
| CRM_MPM_OUTBOUND_10AM | Daily 10:00 |
| CRM_MPM_OUTBOUND_2PM | Daily 14:00 |
| CRM_MPM_OUTBOUND_5PM | Daily 17:00 |
| CRM_MPM_RETRY_JOB | Every 30 min |
| CRM_MPM_TIMEOUT_JOB | Every 60 min |
| CRM_MPM_ALL_UNIT_STATUS_11PM | Daily 23:00 |
| CRM_MPM_ALL_UNIT_STATUS_4AM | Daily 04:00 |

**Script:** `SCHEDULER_CLEANUP_RECREATE.sql`

---

## 5. JAVA ADMIN TOOL CHANGES (CrmAdminTool.java)

### New Features Added
- **New Service Wizard** — 4-step guided dialog: Registry → Field Mappings → Watermark Init → Scheduler Job
- **Callback Audit tab** — 6th subtab in Monitor showing CRM_MPM_CALLBACK_AUDIT_LOG with filters
- **Error Triage tab** — 5th subtab with priority color coding (RED/YELLOW/GREEN)
- **Executed By column** — All Records tab shows which job pushed each record (OUTBOUND/RETRY/TIMEOUT/MANUAL)
- **Double-click detail dialog** — 5-tab popup: Summary, Request Payload, CRM Response, Error Detail, All Fields
- **Mark as Resolved button** — Action Needed tab, sets FINAL_STATUS=RESOLVED with audit note
- **Export to Log button** — Error Triage exports priority report to crm-admin.log

### Bug Fixes
- IS_ACTIVE label overlap in Credentials tab (GridBagConstraints gridy fix)
- Button text invisible on Windows (switched to CrossPlatformLookAndFeel)
- Named bind parameters (:param) auto-converted to positional ? at runtime (Oracle JDBC limitation)
- con.setAutoCommit(false) added to getConnection() (fixed ORA-01000)
- Manual Retry blocked for SUCCESS/SENT/ACK_OK/DUPLICATE_RECORD status
- String.repeat() replaced with repeatChar() helper (Java 8 compatibility)
- All Unicode/emoji replaced with ASCII (Windows Cp1252 encoding fix)
- ENABLED column in Scheduler tab compared as string 'TRUE' not integer

### compile.bat / run.bat
- Added `-encoding UTF-8` to javac
- Added `-Dfile.encoding=UTF-8` to java runtime

---

## 6. EXECUTION ORDER — Fresh Environment

```
1.  CRM_MPM_TABLES_COMPLETE.sql
2.  ALTER_TABLES_ADD_MISSING_COLUMNS.sql
3.  ALTER_ADD_ACK_RESPONSE_TIMESTAMP.sql
4.  ALTER_ADD_CALLBACK_HEADERS.sql
5.  ALTER_ADD_X_UNIQUE_ID.sql
6.  ALTER_ADD_WALLET_COLUMNS.sql
7.  CREDENTIAL_ENCRYPTION_SETUP.sql
8.  PKG_CRM_INTEGRATION_SPEC_V2.sql
9.  PKG_CRM_INTEGRATION_BODY_FINAL.sql
10. CRM_MPM_API_REGISTRY_INSERT.sql
11. CRM_MPM_FIELD_MAPPING_SEED.sql
12. INSERT_CALLBACK_ERROR_CODES.sql
13. INSERT_CRM_ERROR_CODES.sql
14. SCHEDULER_CLEANUP_RECREATE.sql
```
