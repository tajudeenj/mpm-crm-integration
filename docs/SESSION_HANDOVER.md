# MPM CRM Integration — Complete Session Handover
**Last Updated:** 09-Oct-2026
**Project:** ADIB MPM Properties CRM/xRM Integration
**GitHub:** https://github.com/tajudeenj/mpm-crm-integration
**Developer:** Tajudeen Jalaudin, Senior Solution Architect, ADIB

---

## HOW TO USE THIS DOCUMENT
When starting a new session, say:
"Read docs/SESSION_HANDOVER.md from https://github.com/tajudeenj/mpm-crm-integration and continue"

---

## ENVIRONMENT
- DEV: Oracle DB — package deployed, ESB not connected
- SIT: Oracle DB — active testing, ESB connected, CRM vendor testing here
- ESB: IBM ESB/DataPower — only one instance, points to SIT
- CRM: Microsoft Dynamics 365 via IBM APIC
- Web Admin Tool: Spring Boot JAR running on Windows for now

---

## CURRENT STATUS

### Working on SIT ✅
- Package deployed and VALID
- Token authentication working
- Building CREATE sending — HTTP 400 fixed (removed api-version from URL)
- Callback receiving — ESB permission fixed (GRANT EXECUTE on PKG_CRM_INTEGRATION)
- Web Admin Tool — compiled, running, login working

### Pending / In Progress
1. Sequential dependency testing (Property→Building→Floor→Unit)
2. ESB callback URL pointing to DEV instead of SIT (ESB team action)
3. PARENT_PENDING error code insert
4. Web app improvements (error log tab, chain status view, queries in properties file)

---

## SEQUENTIAL DEPENDENCY — VENDOR CONFIRMED DESIGN

### Flow (Confirmed with CRM vendor Oct 2026)
```
Property → SENT → callback SUCCESS
                      ↓
Building → SENT → callback SUCCESS  (only after Property SUCCESS)
                      ↓
Floor    → SENT → callback SUCCESS  (only after Building SUCCESS)
                      ↓
Unit     → SENT → callback SUCCESS  (only after Floor SUCCESS)
```
- Each property chain is INDEPENDENT
- Multiple properties run in parallel
- If parent FAILED — hold all children
- Job runs every 15 minutes
- Project = Property (no separate Project entity)

### Registry IDs — CREATE Services
| Registry ID | Entity | SOURCE_KEY_COL | DEPENDS_ON_REGISTRY_ID | PARENT_LINK_COL |
|-------------|--------|---------------|----------------------|-----------------|
| 22 | Property | PROPERTY_CODE | NULL | NULL |
| 24 | Building | BUILDING_ID | 22 | BUILDING_CODE |
| 26 | Floor | FLOOR_ID | 24 | BUILDING_ID |
| 28 | Unit | UNIT_ID | 26 | FLOOR_ID |
| 62 | TenantPerson | CUSTOMER_ID | NULL | NULL |
| 63 | TenantOrg | CUSTOMER_ID | NULL | NULL |

### Key Relationship (CRITICAL)
```
Property view:  PROPERTY_CODE = 'MA00810'
Building view:  BUILDING_CODE = 'MA00810'  ← same value, different column name
Floor view:     BUILDING_ID   = 523118     ← links to building
Unit view:      FLOOR_ID      = 523119     ← links to floor
```

### WARNING
- Property SOURCE_KEY_COL MUST be PROPERTY_CODE (not PROPERTY_ID)
- BUILDING_CODE in building view = PROPERTY_CODE value (they match)

---

## WHAT HAS BEEN DEPLOYED ON SIT

### DDL Changes (already run)
```sql
ALTER TABLE CRM_MPM_API_REGISTRY ADD DEPENDS_ON_REGISTRY_ID NUMBER;
ALTER TABLE CRM_MPM_API_REGISTRY ADD PARENT_LINK_COL VARCHAR2(100);
ALTER TABLE CRM_MPM_API_REGISTRY ADD SOURCE_EXTRA_FILTER VARCHAR2(500);
```

### Registry Updates (already run)
```sql
-- Sequential dependency
UPDATE CRM_MPM_API_REGISTRY SET SOURCE_KEY_COL='PROPERTY_CODE',
       DEPENDS_ON_REGISTRY_ID=NULL,PARENT_LINK_COL=NULL WHERE REGISTRY_ID=22;
UPDATE CRM_MPM_API_REGISTRY SET
       DEPENDS_ON_REGISTRY_ID=22,PARENT_LINK_COL='BUILDING_CODE' WHERE REGISTRY_ID=24;
UPDATE CRM_MPM_API_REGISTRY SET
       DEPENDS_ON_REGISTRY_ID=24,PARENT_LINK_COL='BUILDING_ID' WHERE REGISTRY_ID=26;
UPDATE CRM_MPM_API_REGISTRY SET
       DEPENDS_ON_REGISTRY_ID=26,PARENT_LINK_COL='FLOOR_ID' WHERE REGISTRY_ID=28;

-- Extra filter for UPDATE services (not WorkRequest)
UPDATE CRM_MPM_API_REGISTRY
SET SOURCE_EXTRA_FILTER='CREATION_DATE <> LAST_UPDATE_DATE'
WHERE OPERATION_TYPE='UPDATE' AND SOURCE_TYPE='VIEW'
AND SOURCE_FILTER_COL IS NOT NULL AND IS_ACTIVE='Y'
AND SOURCE_VIEW != 'XXMPM_CRM_UPDATE_WORKREQ_V';

COMMIT;
```

---

## PACKAGE CHANGES STILL NEEDED

### File: docs/PACKAGE_CHANGES_SNIPPET.sql
Three snippets to add to RUN_OUTBOUND_JOB in your SIT package.

### CHANGE 1 — Variable Declaration
Find: `v_status     VARCHAR2(20);`
Add after:
```sql
v_skipped    NUMBER := 0;  -- records skipped due to parent dependency
```

### CHANGE 2 — Dependency Check Block
Find: `v_processed := v_processed + 1;`
Add ENTIRE block after it (before BEGIN SEND_TO_APIC):
```sql
IF reg.DEPENDS_ON_REGISTRY_ID IS NOT NULL
AND reg.PARENT_LINK_COL IS NOT NULL THEN
    DECLARE
        v_parent_key   VARCHAR2(500);
        v_parent_count NUMBER := 0;
    BEGIN
        EXECUTE IMMEDIATE
            'SELECT ' || reg.PARENT_LINK_COL ||
            ' FROM '  || reg.SOURCE_VIEW ||
            ' WHERE ' || reg.SOURCE_KEY_COL || ' = :k'
            INTO v_parent_key USING v_key_val;
        SELECT COUNT(*) INTO v_parent_count
        FROM   CRM_MPM_CRM_INTEGRATION_LOG
        WHERE  REGISTRY_ID      = reg.DEPENDS_ON_REGISTRY_ID
        AND    SOURCE_RECORD_ID = v_parent_key
        AND    FINAL_STATUS     = 'SUCCESS';
        IF v_parent_count = 0 THEN
            v_skipped := NVL(v_skipped,0) + 1;
            BEGIN
                INSERT INTO CRM_MPM_CRM_INTEGRATION_LOG (
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
                FROM DUAL WHERE NOT EXISTS (
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
            v_skipped := NVL(v_skipped,0) + 1;
            GOTO next_record;
        WHEN OTHERS THEN NULL;
    END;
END IF;
```

### CHANGE 3 — GOTO Label
Find:
```sql
            EXCEPTION
                WHEN OTHERS THEN
                    v_failed := v_failed + 1;
            END;
        END LOOP;
```
Change to:
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

## ERROR CODES TO ADD (PENDING)
```sql
INSERT INTO CRM_MPM_ERROR_CODE_MASTER
    (ERROR_CODE,ERROR_CATEGORY,ERROR_DESCRIPTION,IS_RETRYABLE)
SELECT 'PARENT_PENDING','DEPENDENCY',
       'Child record waiting for parent SUCCESS before sending','N'
FROM DUAL WHERE NOT EXISTS (
    SELECT 1 FROM CRM_MPM_ERROR_CODE_MASTER WHERE ERROR_CODE='PARENT_PENDING');

INSERT INTO CRM_MPM_ERROR_CODE_MASTER
    (ERROR_CODE,ERROR_CATEGORY,ERROR_DESCRIPTION,IS_RETRYABLE)
SELECT 'PARENT_FAILED','DEPENDENCY',
       'Parent record failed — child on hold until parent fixed','N'
FROM DUAL WHERE NOT EXISTS (
    SELECT 1 FROM CRM_MPM_ERROR_CODE_MASTER WHERE ERROR_CODE='PARENT_FAILED');

COMMIT;
```

---

## SCHEDULER SETTINGS
```sql
-- Change outbound job to 15 min interval
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
-- RETRY_INTERVAL_MINUTES = 10 (OK — retry only picks FAILED not TIMEOUT)
-- Timeout job: keep enabled
```

---

## WEB ADMIN TOOL
**Repo:** crm-admin-web/
**Tech:** Spring Boot 3.2 + Java 17 + Oracle JDBC
**Login:** crmadmin / (bcrypt hash in CRM_MPM_APP_USERS)
**Users DDL:** sql/schema/CRM_MPM_APP_USERS_DDL.sql
**Compile:** mvn clean package -DskipTests
**Run:** java -jar target/crm-admin-web-1.0.0.jar
**URL:** http://localhost:8080

### Known Issues to Fix
1. SQL queries hardcoded in CrmAdminService.java — move to queries.properties
2. Error log viewer tab missing
3. Chain status view missing (Property→Building→Floor→Unit per property)
4. PARENT_PENDING not shown in Monitor tab yet

---

## OPEN ISSUES
| # | Issue | Owner | Status |
|---|-------|-------|--------|
| 1 | ESB callback pointing to DEV not SIT | ESB Team | Pending |
| 2 | Package 3 snippets not yet added to SIT | Tajudeen | Pending |
| 3 | Error codes PARENT_PENDING/PARENT_FAILED insert | Tajudeen | Pending |
| 4 | Outbound job change to 15 min | Tajudeen | Pending |
| 5 | Web app SQL to properties file | Claude | Pending |
| 6 | Web app error log tab | Claude | Pending |

---

## KEY FILES IN GITHUB
| File | Purpose |
|------|---------|
| sql/schema/PKG_CRM_INTEGRATION_BODY_FINAL.sql | Full package body |
| sql/schema/PKG_CRM_INTEGRATION_SPEC_V2.sql | Package spec |
| docs/PACKAGE_CHANGES_SNIPPET.sql | ONLY the 3 changes needed |
| sql/SIT_SEQUENTIAL_DEPENDENCY_DEPLOY.sql | DDL + UPDATE for dependency |
| sql/SIT_EXTRA_FILTER_DEPLOY.sql | Extra filter UPDATE services |
| sql/diagnostics/SIT_CALLBACK_DEBUG.sql | Callback diagnostics |
| sql/diagnostics/SIT_CALLBACK_MATCHING_DEBUG.sql | Callback matching debug |
| sql/diagnostics/SIT_BUILD_CREATE_DEBUG.sql | Building CREATE debug |
| sql/diagnostics/SIT_SUPPORT_QUERIES.sql | General support queries |
| crm-admin-web/ | Spring Boot web admin tool |
