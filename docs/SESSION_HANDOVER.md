# MPM CRM Integration — Session Handover Notes
**Last Updated:** Oct 2026
**Project:** ADIB MPM Properties CRM/xRM Integration
**GitHub:** https://github.com/tajudeenj/mpm-crm-integration

---

## Current Status — SIT Testing In Progress

### What Is Working
- Package deployed on SIT
- Token authentication — working
- Building CREATE — working (fixed api-version URL issue)
- Callback receiving — working (ESB permission fixed)
- Web Admin Tool — running on Spring Boot

### What Is Pending / In Progress

---

## Issue 1 — Callback "No Matching Log Entry"
**Root Cause:** ESB pointing to DEV callback URL instead of SIT.
**Fix:** ESB team needs to point SIT callback URL to SIT endpoint.
**Status:** Raised with ESB team — pending their fix.

---

## Issue 2 — Sequential Dependency (MOST IMPORTANT)

### Vendor Confirmed Flow (Oct 2026)
```
Project(=Property) → Building → Floor → Unit
Each level: SEND → wait callback SUCCESS → then send next level
If parent FAILED → hold all children
Per property chain is independent
```

### Registry IDs
| Registry ID | Entity | Operation |
|-------------|--------|-----------|
| 22 | Property | CREATE |
| 24 | Building | CREATE |
| 26 | Floor | CREATE |
| 28 | Unit | CREATE |
| 62 | TenantPerson | CREATE |
| 63 | TenantOrg | CREATE |

### Parent-Child Key Relationships (CONFIRMED)
| Child | Child Source View | PARENT_LINK_COL | Parent View | Parent KEY |
|-------|------------------|-----------------|-------------|------------|
| Building (24) | XXMPM_CRM_BUILDING_CREATE_FULL_V | BUILDING_CODE | Property (22) | PROPERTY_CODE |
| Floor (26) | XXMPM_CRM_FLOOR_CREATE_V | BUILDING_ID | Building (24) | BUILDING_ID |
| Unit (28) | XXMPM_CRM_UNIT_CREATE_V | FLOOR_ID | Floor (26) | FLOOR_ID |

### Source Key Columns (CONFIRMED — CRITICAL)
| Registry | Entity | SOURCE_KEY_COL | Why |
|----------|--------|---------------|-----|
| 22 | Property | PROPERTY_CODE | BUILDING_CODE = PROPERTY_CODE (links match) |
| 24 | Building | BUILDING_ID | BUILDING_ID links to floor view |
| 26 | Floor | FLOOR_ID | FLOOR_ID links to unit view |
| 28 | Unit | UNIT_ID | terminal node |

**WARNING:** Do NOT use PROPERTY_ID for Property — use PROPERTY_CODE.
BUILDING_CODE in building view = PROPERTY_CODE in property view (same value MA00810).

### New Columns Needed in CRM_MPM_API_REGISTRY
```sql
ALTER TABLE CRM_MPM_API_REGISTRY ADD DEPENDS_ON_REGISTRY_ID NUMBER;
ALTER TABLE CRM_MPM_API_REGISTRY ADD PARENT_LINK_COL VARCHAR2(100);
```

### Registry UPDATE Values
```sql
UPDATE CRM_MPM_API_REGISTRY SET SOURCE_KEY_COL='PROPERTY_CODE',
       DEPENDS_ON_REGISTRY_ID=NULL, PARENT_LINK_COL=NULL WHERE REGISTRY_ID=22;
UPDATE CRM_MPM_API_REGISTRY SET
       DEPENDS_ON_REGISTRY_ID=22, PARENT_LINK_COL='BUILDING_CODE' WHERE REGISTRY_ID=24;
UPDATE CRM_MPM_API_REGISTRY SET
       DEPENDS_ON_REGISTRY_ID=24, PARENT_LINK_COL='BUILDING_ID' WHERE REGISTRY_ID=26;
UPDATE CRM_MPM_API_REGISTRY SET
       DEPENDS_ON_REGISTRY_ID=26, PARENT_LINK_COL='FLOOR_ID' WHERE REGISTRY_ID=28;
COMMIT;
```

### Package Snippets — 3 Places in RUN_OUTBOUND_JOB
**Full deploy script:** `sql/SIT_SEQUENTIAL_DEPENDENCY_DEPLOY.sql`

**Snippet 1 — Variable declarations (after v_status VARCHAR2(20)):**
```sql
v_skipped    NUMBER := 0;
```

**Snippet 2 — Before SEND_TO_APIC:**
```sql
IF reg.DEPENDS_ON_REGISTRY_ID IS NOT NULL
AND reg.PARENT_LINK_COL IS NOT NULL THEN
    DECLARE
        v_parent_key   VARCHAR2(500);
        v_parent_count NUMBER := 0;
    BEGIN
        EXECUTE IMMEDIATE
            'SELECT ' || reg.PARENT_LINK_COL ||
            ' FROM ' || reg.SOURCE_VIEW ||
            ' WHERE ' || reg.SOURCE_KEY_COL || ' = :k'
            INTO v_parent_key USING v_key_val;
        SELECT COUNT(*) INTO v_parent_count
        FROM   CRM_MPM_CRM_INTEGRATION_LOG
        WHERE  REGISTRY_ID      = reg.DEPENDS_ON_REGISTRY_ID
        AND    SOURCE_RECORD_ID = v_parent_key
        AND    FINAL_STATUS     = 'SUCCESS';
        IF v_parent_count = 0 THEN
            v_skipped := NVL(v_skipped,0) + 1;
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

**Snippet 3 — Before END LOOP (after v_failed block):**
```sql
<<next_record>>
NULL;
```

---

## Issue 3 — Timeout / Retry Settings
- TIMEOUT_MINUTES = 60 (vendor confirmed max 60 min callback)
- RETRY_INTERVAL_MINUTES = 10 (OK — retry job only picks FAILED not TIMEOUT unless error code IS_RETRYABLE=Y)
- Outbound job: change to FREQ=MINUTELY;INTERVAL=15
- Timeout job: keep enabled with 60 min window

---

## Issue 4 — SOURCE_EXTRA_FILTER
UPDATE services need extra WHERE condition:
```sql
-- 4 services only (not WorkRequest 125)
UPDATE CRM_MPM_API_REGISTRY
SET SOURCE_EXTRA_FILTER = 'CREATION_DATE <> LAST_UPDATE_DATE'
WHERE OPERATION_TYPE='UPDATE' AND SOURCE_TYPE='VIEW'
AND SOURCE_FILTER_COL IS NOT NULL AND IS_ACTIVE='Y'
AND SOURCE_VIEW != 'XXMPM_CRM_UPDATE_WORKREQ_V';
```
Deploy script: `sql/SIT_EXTRA_FILTER_DEPLOY.sql`

---

## Web Admin Tool
**Repo path:** `crm-admin-web/`
**Tech:** Spring Boot 3.x + Java 17 + Oracle JDBC
**Run:** `java -jar target/crm-admin-web-1.0.0.jar`
**Login:** crmadmin / (set via bcrypt in CRM_MPM_APP_USERS table)
**Users table DDL:** `sql/schema/CRM_MPM_APP_USERS_DDL.sql`

### Known Issues in Web App
1. All SQL queries hardcoded in CrmAdminService.java — should move to properties file
2. Error log viewer tab missing
3. Chain status view (Property→Building→Floor→Unit) missing
4. PARENT_PENDING status not yet implemented

---

## Files in GitHub
| File | Purpose |
|------|---------|
| sql/schema/PKG_CRM_INTEGRATION_BODY_FINAL.sql | Main package body |
| sql/schema/PKG_CRM_INTEGRATION_SPEC_V2.sql | Package spec |
| sql/SIT_SEQUENTIAL_DEPENDENCY_DEPLOY.sql | Sequential dependency DDL+UPDATE |
| sql/SIT_EXTRA_FILTER_DEPLOY.sql | Extra filter for UPDATE services |
| sql/SIT_DDL.sql | SIT deployment DDL |
| sql/SIT_DATA.sql | SIT config data |
| sql/diagnostics/SIT_CALLBACK_DEBUG.sql | Callback diagnostics |
| sql/diagnostics/SIT_CALLBACK_MATCHING_DEBUG.sql | Callback matching debug |
| sql/diagnostics/SIT_BUILD_CREATE_DEBUG.sql | Building CREATE debug |
| sql/diagnostics/SIT_SUPPORT_QUERIES.sql | General support queries |
| crm-admin-web/ | Spring Boot web admin tool |

---

## Immediate Next Steps
1. Update SOURCE_KEY_COL for Property (22) to PROPERTY_CODE
2. Run SIT_SEQUENTIAL_DEPENDENCY_DEPLOY.sql on SIT
3. Add 3 snippets to package body
4. Change outbound job to 15 min interval
5. Test one property chain end to end on SIT
6. Fix ESB callback URL (ESB team action)
