# MPM CRM Integration — Complete Project Handover
**Last Updated:** 09-Oct-2026 (Session 9)
**Project:** ADIB MPM Properties CRM/xRM Integration
**GitHub:** https://github.com/tajudeenj/mpm-crm-integration
**Developer:** Tajudeen Jalaudin, Senior Solution Architect, ADIB
**Sessions:** 9 sessions from Jul-2026 to Oct-2026

---

## HOW TO USE THIS DOCUMENT
When starting a new session paste:
"Read docs/SESSION_HANDOVER.md from https://github.com/tajudeenj/mpm-crm-integration
and continue. I am Tajudeen, Senior Solution Architect at ADIB working on
MPM Properties CRM integration."

---

## PROJECT OVERVIEW
Oracle EBS/Fusion → IBM APIC → Microsoft Dynamics 365 CRM integration
for ADIB MPM Properties. Pushes master data (Property, Building, Floor,
Unit, Tenant) and transactional data (Work Requests) from Oracle to CRM.
Callbacks from CRM update Oracle log with SUCCESS/FAILED status.

---

## ARCHITECTURE

### Technology Stack
- Source: Oracle EBS/Fusion (APPS schema)
- Integration Package: PKG_CRM_INTEGRATION (Oracle PL/SQL)
- Transport: IBM APIC (API Connect) + IBM ESB/DataPower
- Target: Microsoft Dynamics 365 CRM
- Admin Tool: Java Swing (standalone) + Spring Boot Web
- Encryption: Oracle DBMS_CRYPTO AES-256
- Wallet: Oracle Wallet (UTL_HTTP SSL)

### Flow — Outbound
```
Oracle Source View
    → RUN_OUTBOUND_JOB (watermark-based)
    → BUILD_JSON_PAYLOAD
    → GET_BEARER_TOKEN (OAuth2 client_credentials)
    → SEND_TO_APIC (UTL_HTTP POST)
    → CRM_MPM_CRM_INTEGRATION_LOG (status=SENT)
    → APIC → Dynamics 365 CRM
    → Callback → PROCESS_CRM_CALLBACK
    → Log updated (SUCCESS/FAILED/VALIDATION_FAILED)
```

### Flow — Retry
```
RUN_RETRY_JOB
    → Picks FAILED records where NEXT_RETRY_DATE <= SYSDATE
    → Re-sends via SEND_TO_APIC
    → Max MAX_RETRY_COUNT attempts
    → Then EXHAUSTED
```

### Flow — Timeout
```
RUN_TIMEOUT_JOB
    → Picks SENT records older than TIMEOUT_MINUTES
    → Marks as TIMEOUT
    → Retry job picks up and re-sends
```

---

## DATABASE TABLES

### Core Tables
| Table | Purpose |
|-------|---------|
| CRM_MPM_API_REGISTRY | Service configuration — one row per integration service |
| CRM_MPM_API_CREDENTIALS | APIC OAuth credentials (encrypted) |
| CRM_MPM_API_FIELD_MAPPING | JSON field mappings per service |
| CRM_MPM_API_WATERMARK | Last processed timestamp per service |
| CRM_MPM_ERROR_CODE_MASTER | Error codes and retry flags |
| CRM_MPM_CRM_INTEGRATION_LOG | Main integration log — every sent record |
| CRM_MPM_CALLBACK_AUDIT_LOG | Raw callback payloads from CRM |
| CRM_MPM_CONFIG_STORE | Key-value config store |
| CRM_MPM_ENCRYPT_CONFIG | AES-256 encryption key |
| CRM_MPM_APP_USERS | Web admin tool users (BCrypt passwords) |
| CRM_MPM_JOB_RUN_HISTORY | Scheduler job run history |

### Registry Columns (Key Ones)
| Column | Purpose |
|--------|---------|
| SERVICE_NAME | Unique service identifier |
| SOURCE_VIEW | Oracle view/table to read from |
| SOURCE_KEY_COL | Column used as SOURCE_RECORD_ID in log |
| SOURCE_FILTER_COL | Watermark column (LAST_UPDATE_DATE etc) |
| SOURCE_EXTRA_FILTER | Additional WHERE condition (e.g. CREATION_DATE<>LAST_UPDATE_DATE) |
| DEPENDS_ON_REGISTRY_ID | Parent registry ID (sequential dependency) |
| PARENT_LINK_COL | Column in child view = parent SOURCE_RECORD_ID |
| JSON_MAPPING_NAME | Links to CRM_MPM_API_FIELD_MAPPING |
| APIC_ENDPOINT_URL | Target APIC URL (no ?api-version suffix) |
| CRED_CODE | Links to CRM_MPM_API_CREDENTIALS |
| TIMEOUT_MINUTES | 60 (vendor confirmed max callback time) |
| RETRY_INTERVAL_MINUTES | 10 |
| MAX_RETRY_COUNT | 3 |

---

## PACKAGE: PKG_CRM_INTEGRATION

### File: sql/schema/PKG_CRM_INTEGRATION_BODY_FINAL.sql
### Spec: sql/schema/PKG_CRM_INTEGRATION_SPEC_V2.sql

### Key Procedures
| Procedure | Purpose |
|-----------|---------|
| RUN_OUTBOUND_JOB | Main outbound — watermark-based, all VIEW services |
| RUN_RETRY_JOB | Retry FAILED records |
| RUN_TIMEOUT_JOB | Mark SENT records as TIMEOUT after TIMEOUT_MINUTES |
| SEND_TO_APIC | Core HTTP send — gets token, builds payload, posts |
| GET_BEARER_TOKEN | OAuth2 token from APIC |
| BUILD_JSON_PAYLOAD | Dynamic JSON from field mappings |
| PROCESS_CRM_CALLBACK | Handles callback from CRM — updates log |
| PROCESS_STAGING_CALLBACK | Callback for staging-based services |
| RUN_UNIT_STATUS_BATCH | Unit status batch push |
| RUN_UNIT_UNAVAILABLE_BATCH | Unit unavailable batch push |
| RUN_UNIT_UNAVAILABLE_AVAILABLE_BATCH | All unit status consolidated batch |

### Important Fixes Applied (All Sessions)
1. Runaway retry loop fix — RUN_RETRY_JOB marks RETRY_IN_PROGRESS before send
2. Status 9999 override — force retry except DUPLICATE_RECORD
3. 6 new CRM error codes in PROCESS_CRM_CALLBACK
4. Date format — DD-MON-YYYY explicit mask (no ALTER SESSION)
5. LENGTHB instead of LENGTH for Content-Length header
6. SOURCE_EXTRA_FILTER — appended to outbound WHERE clause
7. Sequential dependency check — PARENT_PENDING status (Oct 2026)
8. PARENT_PENDING release pass — RELEASE_PARENT_PENDING (Session 9, 09-Oct-2026)
   BUG FOUND: changes 1-3 skip the child via GOTO, but the end-of-loop
   watermark update moves to MAX(filter col) of the whole view, so a skipped
   child is NEVER re-read. Since callbacks are async (up to 60 min), the parent
   is almost never SUCCESS in the same run -> chain would stall at Building.
   FIX: merged into PKG_CRM_INTEGRATION_SPEC_V2 + BODY_FINAL (snippet copy in
   sql/SIT_PARENT_RELEASE_DEPLOY.sql, changes 4-6) — release pass at the
   start of each RUN_OUTBOUND_JOB reads PARENT_PENDING rows from the LOG and
   sends them once parent is SUCCESS. Pending row -> RELEASED (+ new SENT row).
   Parent terminal failure -> child PARENT_FAILED; parent retried -> back to PENDING.

---

## ACTIVE SERVICES (14 rows IS_ACTIVE=Y)

### CREATE Services
| Registry ID | Entity | Source View | SOURCE_KEY_COL |
|-------------|--------|------------|----------------|
| 22 | Property | XXMPM_CRM_PROPERTY_CREATE_V | PROPERTY_CODE |
| 24 | Building | XXMPM_CRM_BUILDING_CREATE_FULL_V | BUILDING_ID |
| 26 | Floor | XXMPM_CRM_FLOOR_CREATE_V | FLOOR_ID |
| 28 | Unit | XXMPM_CRM_UNIT_CREATE_V | UNIT_ID |
| 62 | TenantPerson | XXMPM_CRM_TENANT_PERSON_V | CUSTOMER_ID |
| 63 | TenantOrg | XXMPM_CRM_TENANT_ORG_V | CUSTOMER_ID |

### UPDATE Services
| Registry ID | Entity | Source View | SOURCE_KEY_COL |
|-------------|--------|------------|----------------|
| 23 | Property | XXMPM_CRM_PROPERTY_UPDATE_V | PROPERTY_CODE |
| 25 | Building | XXMPM_CRM_BUILDING_UPDATE_FULL_V | UNIQUE_ID |
| 27 | Floor | XXMPM_CRM_FLOOR_UPDATE_V | UNIQUE_ID |
| 29 | Unit | XXMPM_CRM_UNIT_UPDATE_V | UNIT_ID |
| 83 | Customer | NA (PROCEDURE) | oracle-customerid |
| 122 | Unit Legal Lock | NA (PROCEDURE) | unitno |
| 125 | WorkRequest | XXMPM_CRM_UPDATE_WORKREQ_V | UNIQUE_ID |
| 141 | Unit All Status | XXMPM_CRM_ALL_UNIT_STATUS_V | UNIT_ID |

### Sequential Dependency (CREATE only — confirmed Oct 2026)
| Child Registry | Depends On | PARENT_LINK_COL |
|----------------|------------|-----------------|
| 24 Building | 22 Property | BUILDING_CODE |
| 26 Floor | 24 Building | BUILDING_ID |
| 28 Unit | 26 Floor | FLOOR_ID |

### Key Relationship
```
Property PROPERTY_CODE = 'MA00810'
Building BUILDING_CODE = 'MA00810'  ← same value
Floor    BUILDING_ID   = 523118
Unit     FLOOR_ID      = 523119
```

### SOURCE_EXTRA_FILTER (UPDATE services — not WorkRequest)
```
CREATION_DATE <> LAST_UPDATE_DATE
Applied to: Registry 23, 25, 27, 29
NOT applied to: 125 (WorkRequest), 83, 122, 141
```

---

## ENVIRONMENT
| Env | Purpose | ESB |
|-----|---------|-----|
| DEV | Development | Not connected |
| SIT | System Integration Testing | Connected — only env |

---

## ADMIN TOOLS

### Java Swing (Standalone)
- File: admin-tool/CrmAdminTool.java
- 10 tabs: Credentials, Registry, Mappings, Watermark,
  Error Codes, Monitor, Script Download, Scheduler,
  Health Check, Test Push
- Compile: javac + ojdbc8.jar
- Config: admin-tool/crm-admin.properties (ALL SQL queries here)
- Run: java -cp ... CrmAdminTool

### Spring Boot Web
- Folder: crm-admin-web/
- Same 10 tabs + Users tab
- Tech: Spring Boot 3.2 + Java 17
- Compile: mvn clean package -DskipTests
- Run: java -jar target/crm-admin-web-1.0.0.jar
- URL: http://server:8080
- Login: CRM_MPM_APP_USERS table (BCrypt)
- DB config: application.properties (update before run)
- SQL: ALL queries in src/main/resources/queries.properties (Session 9)
  loaded by config/QueryStore.java. Override without recompile:
  drop ./queries.properties next to the JAR (only changed keys needed)
  or -Dcrm.queries.file=/path. Bind with ? ; *.filter.* keys appended
  only when a filter is set (ORA-17004 safe).
  Covers CrmAdminService, TestPushService, UserService.
  ScriptService (DDL/insert generator) still builds SQL in Java.
- New in Session 9: Error Log tab (integration errors + full payload
  detail + job-run errors), Chain Status tab (per-property tree),
  Monitor > Parent Pending sub-tab + dashboard KPI/columns.
- Chain Status resolves registry IDs by SOURCE_VIEW (env-independent).
  RELEASED rows are excluded from all counts (no double counting).

---

## WORKING RULE — SUPPORT QUERIES
All support / diagnostic queries go into ONE file:
  sql/diagnostics/SIT_SUPPORT_QUERIES.sql
Append each new query as the next QUERY number (last: QUERY 27) and push.
Tajudeen downloads it, runs the query, shares output. Do not create new files.

## CURRENT STATUS (09-Oct-2026)

### ISSUE — Building 523118 callback failing (found 10-Oct-2026)
- CRM callback: status 9999, result_code DUPLICATE_RECORD — building already
  exists in PxRM (CRM Id 8d8e9f77-1ac3-f111-aaad-7ced8dac5956).
- Our callback handler crashed: ORA-02290 check constraint APPS.SYS_C005700592
  violated -> returned CB_1003 'Unhandled exception' -> nothing written to log.
- Log row stayed SENT -> TIMEOUT (retryable) -> resent -> duplicate again.
  15 sends 08-09 Oct (LOG 2389..2713), all TIMEOUT/EXHAUSTED, CALLBACK_DATE null.
- CONFIRMED (QUERY 26): SYS_C005700592 = CHECK on CRM_MPM_CRM_INTEGRATION_LOG.FINAL_STATUS
  allowing only PENDING, ACK_FAILED, SENT, SUCCESS, FAILED, TIMEOUT,
  ALREADY_PROCESSED, EXHAUSTED. Blocks every non-SUCCESS callback status AND
  PARENT_PENDING / PARENT_FAILED / RELEASED.
- FIX: sql/SIT_FIX_FINAL_STATUS_CONSTRAINT.sql — drop SYS_C005700592, add named
  CK_CRM_LOG_FINAL_STATUS with all 19 statuses. RULE: new status -> add here too.
- SYS_C005700592 is NOT in repo DDL (added on DB directly, like the
  ERROR_CATEGORY check). Suspect CHECK on FINAL_STATUS (log) or on the
  callback target table status column. Identify with QUERY 26.
- RISK: if it is a FINAL_STATUS check on CRM_MPM_CRM_INTEGRATION_LOG it will
  ALSO block PARENT_PENDING / PARENT_FAILED / RELEASED inserts (QUERY 27 lists all).
- After fix, building 523118 will land as DUPLICATE_RECORD -> its floors wait
  forever (decision D1 is now real, not theoretical).

### SIT deployment — DONE 09/10-Oct-2026 (Tajudeen)
- ✅ Error codes: PARENT_PENDING, PARENT_FAILED, MANUAL_RETRY (category CHECK constraint dropped on SIT)
- ✅ Package changes 1-6 applied, spec + body compiled VALID
- ✅ Outbound scheduler job at 15 min
- ✅ 10-Oct: SYS_C005700592 (FINAL_STATUS check) DROPPED on SIT. Decision:
  NOT re-added (re-add step in sql/SIT_FIX_FINAL_STATUS_CONSTRAINT.sql is optional).
  PROD: greenfield — nothing exists yet; PROD will be built fresh from the
  repo scripts. So the repo DDL is the source of truth for PROD. The 15 other
  CHECK constraints seen on SIT (QUERY 27) are NOT in repo DDL -> they will
  not exist on PROD unless added to the repo before go-live.
- QUERY 27 (10-Oct): 16 CHECK constraints on SIT, none in repo DDL. Only
  FINAL_STATUS is wrong for the package. But admin-tool dropdowns did NOT
  match them (saves would fail ORA-02290) — FIXED both tools to match DB:
    OPERATION_TYPE : CREATE, UPDATE, STATUS_UPDATE, LEGAL_HOLD, OTHER
    SOURCE_TYPE    : VIEW, PROCEDURE
    DATA_TYPE      : STRING, NUMBER, DATE, BOOLEAN   (web had VARCHAR/CLOB)
  OK as-is: JOB_RUN_HISTORY.STATUS, OUTBOUND_STAGING.STATUS, IS_* Y/N,
  CHK_CRM_ERR_CATEGORY (re-added on SIT with real categories).
- ⏳ NEXT: rebuild web app (crm-admin-web: mvn clean package -DskipTests), git pull
- ⏳ NEXT: run Property->Building->Floor->Unit chain test, watch Chain Status tab
- ⏳ OPEN: send SOURCE_FILTER_COL for registry 22-29 — decides fix for
  'MPM fixes failed CREATE -> UPDATE also fires -> false RECORD_NOT_FOUND'
  (proposed: UPDATE service DEPENDS_ON its own CREATE via existing mechanism)


### Working on SIT ✅
- Package VALID, deployed
- Token authentication working
- Outbound job running
- Building CREATE working (fixed api-version URL issue)
- Callback receiving (fixed ESB GRANT EXECUTE permission)
- Web admin tool running

### Pending Actions

#### Tajudeen (DBA/Package)
1. Add 3 snippets to SIT package (file: docs/PACKAGE_CHANGES_SNIPPET.sql)
1b. Recompile spec + body from sql/schema/ (now include RELEASE_PARENT_PENDING)
    OR apply only changes 4-6 via sql/SIT_PARENT_RELEASE_DEPLOY.sql — REQUIRED,
    without it children stay PARENT_PENDING forever
2. Insert PARENT_PENDING and PARENT_FAILED error codes
   (run sql/SIT_ERROR_CODES_DEPENDENCY.sql — idempotent MERGE, both IS_RETRYABLE='N')
3. Change outbound job to 15 min interval
4. Test one full Property→Building→Floor→Unit chain on SIT
   (watch it in web app: Chain Status tab; expect ~4 x (callback + 15 min))
5. Rebuild web app: mvn clean package -DskipTests (new queries.properties)

#### Decisions needed (Session 9)
D1. Parent DUPLICATE_RECORD: child check requires parent SUCCESS only.
    If CRM returns DUPLICATE_RECORD for a property that already exists,
    its buildings wait forever. Accept DUPLICATE_RECORD as "parent OK"?
    (change both CHANGE 2 and RELEASE_PARENT_PENDING if yes)
D2. Pre-existing parents (in CRM before go-live, no log row): children
    will wait. Options: seed SUCCESS log rows for migrated masters, or
    reset parent watermark to re-push.

#### ESB Team
5. Point SIT callback URL to SIT endpoint (currently pointing to DEV)

#### Claude — DONE Session 9 (09-Oct-2026)
6. ✅ SQL moved to queries.properties (+ QueryStore, external override)
7. ✅ Error Log tab
8. ✅ Chain Status tab
9. ✅ PARENT_PENDING in Monitor (sub-tab, KPI, dashboard columns)
   + found & fixed watermark gap (RELEASE_PARENT_PENDING)
   + MANUAL RETRY BUG: button set FINAL_STATUS='FAILED' but left ERROR_CODE
     (VALIDATION_FAILED/EXHAUSTED/... all IS_RETRYABLE='N'), and RUN_RETRY_JOB
     only retries retryable codes -> manual retries were never resent.
     Fix: manual retry now sets ERROR_CODE='MANUAL_RETRY' (new code, 'Y'),
     NEXT_RETRY_DATE=NULL — web app AND Swing tool.
   + fixed Monitor table headers (All Records / Action / Retry had fewer
     headers than columns returned)

#### Claude (Next Session)
10. Port same features to Java Swing tool (Error Log, Chain, Parent Pending)
11. Move ScriptService SQL to queries.properties
12. Registry tab: show/edit DEPENDS_ON_REGISTRY_ID + PARENT_LINK_COL
13. Apply D1/D2 decisions once Tajudeen confirms

---

## SNIPPETS TO ADD TO SIT PACKAGE

### Full file: docs/PACKAGE_CHANGES_SNIPPET.sql

### CHANGE 1 — In RUN_OUTBOUND_JOB DECLARE section
Find: `v_status     VARCHAR2(20);`
Add after:
```sql
v_skipped    NUMBER := 0;
```

### CHANGE 2 — In RUN_OUTBOUND_JOB fetch loop
Find: `v_processed := v_processed + 1;`
Add entire block after (before existing BEGIN SEND_TO_APIC):
```sql
IF reg.DEPENDS_ON_REGISTRY_ID IS NOT NULL
AND reg.PARENT_LINK_COL IS NOT NULL THEN
    DECLARE
        v_parent_key   VARCHAR2(500);
        v_parent_count NUMBER := 0;
    BEGIN
        EXECUTE IMMEDIATE
            'SELECT '||reg.PARENT_LINK_COL||
            ' FROM ' ||reg.SOURCE_VIEW||
            ' WHERE '||reg.SOURCE_KEY_COL||' = :k'
            INTO v_parent_key USING v_key_val;
        SELECT COUNT(*) INTO v_parent_count
        FROM   CRM_MPM_CRM_INTEGRATION_LOG
        WHERE  REGISTRY_ID      = reg.DEPENDS_ON_REGISTRY_ID
        AND    SOURCE_RECORD_ID = v_parent_key
        AND    FINAL_STATUS     = 'SUCCESS';
        IF v_parent_count = 0 THEN
            v_skipped := NVL(v_skipped,0)+1;
            BEGIN
                INSERT INTO CRM_MPM_CRM_INTEGRATION_LOG(
                    REGISTRY_ID,ENTITY_NAME,OPERATION_TYPE,
                    SOURCE_RECORD_ID,FINAL_STATUS,
                    ERROR_MESSAGE,CREATED_DATE,UPDATED_DATE)
                SELECT reg.REGISTRY_ID,reg.ENTITY_NAME,
                       reg.OPERATION_TYPE,v_key_val,
                       'PARENT_PENDING',
                       'Waiting for parent Registry='
                       ||reg.DEPENDS_ON_REGISTRY_ID
                       ||' Key='||v_parent_key||' SUCCESS',
                       SYSTIMESTAMP,SYSTIMESTAMP
                FROM DUAL WHERE NOT EXISTS(
                    SELECT 1 FROM CRM_MPM_CRM_INTEGRATION_LOG
                    WHERE REGISTRY_ID=reg.REGISTRY_ID
                    AND SOURCE_RECORD_ID=v_key_val
                    AND FINAL_STATUS='PARENT_PENDING');
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
            GOTO next_record;
        END IF;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_skipped:=NVL(v_skipped,0)+1;
            GOTO next_record;
        WHEN OTHERS THEN NULL;
    END;
END IF;
```

### CHANGE 3 — End of fetch loop
Find:
```sql
            EXCEPTION
                WHEN OTHERS THEN
                    v_failed := v_failed + 1;
            END;
        END LOOP;
```
Add `<<next_record>> NULL;` before END LOOP:
```sql
            EXCEPTION
                WHEN OTHERS THEN
                    v_failed := v_failed + 1;
            END;
            <<next_record>>
            NULL;
        END LOOP;
```

---

## ERROR CODES TO INSERT
```sql
INSERT INTO CRM_MPM_ERROR_CODE_MASTER
    (ERROR_CODE,ERROR_CATEGORY,ERROR_DESCRIPTION,IS_RETRYABLE)
SELECT 'PARENT_PENDING','DEPENDENCY',
       'Child record waiting for parent SUCCESS before sending','N'
FROM DUAL WHERE NOT EXISTS(
    SELECT 1 FROM CRM_MPM_ERROR_CODE_MASTER
    WHERE ERROR_CODE='PARENT_PENDING');

INSERT INTO CRM_MPM_ERROR_CODE_MASTER
    (ERROR_CODE,ERROR_CATEGORY,ERROR_DESCRIPTION,IS_RETRYABLE)
SELECT 'PARENT_FAILED','DEPENDENCY',
       'Parent record failed — child on hold until parent fixed','N'
FROM DUAL WHERE NOT EXISTS(
    SELECT 1 FROM CRM_MPM_ERROR_CODE_MASTER
    WHERE ERROR_CODE='PARENT_FAILED');

COMMIT;
```

---

## SCHEDULER SETTINGS
```sql
-- Change outbound to 15 min
BEGIN
    DBMS_SCHEDULER.DISABLE('CRM_MPM_OUTBOUND_JOB');
    DBMS_SCHEDULER.SET_ATTRIBUTE(
        name=>'CRM_MPM_OUTBOUND_JOB',
        attribute=>'REPEAT_INTERVAL',
        value=>'FREQ=MINUTELY;INTERVAL=15');
    DBMS_SCHEDULER.ENABLE('CRM_MPM_OUTBOUND_JOB');
END;
/
-- TIMEOUT_MINUTES = 60 (vendor confirmed)
-- RETRY_INTERVAL_MINUTES = 10 (fine — retry only FAILED not TIMEOUT)
-- Keep timeout job enabled
```

---

## KEY GITHUB FILES
| File | Purpose |
|------|---------|
| sql/schema/PKG_CRM_INTEGRATION_BODY_FINAL.sql | Full package body |
| sql/schema/PKG_CRM_INTEGRATION_SPEC_V2.sql | Package spec |
| docs/PACKAGE_CHANGES_SNIPPET.sql | ONLY 3 changes for SIT package |
| sql/SIT_ERROR_CODES_DEPENDENCY.sql | PARENT_PENDING / PARENT_FAILED error codes |
| sql/SIT_PARENT_RELEASE_DEPLOY.sql | Changes 4-6: PARENT_PENDING release pass |
| crm-admin-web/src/main/resources/queries.properties | ALL web app SQL |
| crm-admin-web/src/main/java/com/adib/crm/admin/config/QueryStore.java | Loads queries |
| sql/SIT_SEQUENTIAL_DEPENDENCY_DEPLOY.sql | DDL+UPDATE for dependency |
| sql/SIT_EXTRA_FILTER_DEPLOY.sql | Extra filter UPDATE services |
| sql/SIT_DDL.sql | SIT DDL deployment |
| sql/SIT_DATA.sql | SIT config data |
| sql/SIT_ENCRYPT_SECRET.sql | Re-encrypt secrets on SIT |
| sql/diagnostics/SIT_SUPPORT_QUERIES.sql | 15 support queries |
| sql/diagnostics/SIT_CALLBACK_DEBUG.sql | Callback diagnostics |
| sql/diagnostics/SIT_CALLBACK_MATCHING_DEBUG.sql | Callback match debug |
| sql/diagnostics/SIT_BUILD_CREATE_DEBUG.sql | Building CREATE debug |
| sql/diagnostics/EMERGENCY_STOP_RUNAWAY_RETRY.sql | Emergency stop |
| admin-tool/CrmAdminTool.java | Java Swing admin tool |
| admin-tool/crm-admin.properties | ALL SQL queries for standalone |
| crm-admin-web/ | Spring Boot web admin tool |
| crm-admin-web/src/main/resources/application.properties | DB config |
| docs/SESSION_HANDOVER.md | This file |
| docs/PACKAGE_CHANGES_SNIPPET.sql | Package change snippets |
| docs/PKG_BODY_HIGHLIGHTED.html | Color-coded package viewer |

---

## COMMON ISSUES AND FIXES

| Issue | Fix |
|-------|-----|
| ORA-29273 URL health check | Media service URLs use direct Java HTTP not Oracle UTL_HTTP |
| ORA-06502 buffer overflow | Use DBMS_OUTPUT not EXECUTE IMMEDIATE for large DDL |
| ORA-17004 NULL TIMESTAMP bind | Use dynamic SQL builder not ? IS NULL pattern |
| HTTP 400 from APIC | Check APIC_ENDPOINT_URL has no ?api-version= suffix |
| No matching log entry callback | ESB pointing to wrong env (DEV vs SIT) |
| Runaway retry loop | Package fix applied — RETRY_IN_PROGRESS before send |
| Bad credentials login | Use bcrypt-generator.com to generate hash |
| DisabledException compile error | Add import org.springframework.security.authentication.DisabledException |
| Duplicate bean passwordEncoder | Add spring.main.allow-bean-definition-overriding=true |
| ORA-02290 on error code MERGE (SIT) | SIT had a CHECK on ERROR_CATEGORY (not in repo DDL) without 'DEPENDENCY'. Dropped on SIT 09-Oct-2026. Optional re-add incl. DEPENDENCY at end of sql/SIT_ERROR_CODES_DEPENDENCY.sql |
| Child stuck PARENT_PENDING | Deploy SIT_PARENT_RELEASE_DEPLOY.sql; check parent in Chain Status |
| "Missing query key" in status bar | Key absent in queries.properties / override file |
