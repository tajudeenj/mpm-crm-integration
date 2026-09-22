# ADIB MPM Properties — CRM xRM Integration

Oracle-based CRM integration platform for MPM Properties at ADIB.
Handles outbound push of property, building, floor, unit, tenant and work request data to Microsoft Dynamics CRM via IBM APIC.

## Repository Structure

```
admin-tool/        Java Swing desktop admin tool (main application)
sql/schema/        Table DDL, ALTER scripts, package spec and body
sql/data/          Registry inserts, field mapping seeds, config data
sql/scheduler/     Scheduler job scripts
sql/diagnostics/   Monitoring queries, wallet tests, health checks
docs/              Oracle team handover document, objects inventory
```

## Admin Tool — Quick Start

### Prerequisites
- Java 8 (JRE or JDK)
- ojdbc8.jar (Oracle JDBC driver) — place in same folder as .java files

### Windows
```
1. Edit crm-admin.properties — update db.url, db.username, db.password
2. Double-click compile.bat
3. Double-click run.bat
```

### Solaris / Linux
```
1. Edit crm-admin.properties — update db.url, db.username, db.password
2. sh compile.sh
3. sh run.sh
```

### Compile command (manual)
```
javac -encoding UTF-8 -source 8 -target 8 -cp ojdbc8.jar CrmAdminTool.java EncryptPassword.java
```

### Run command (manual)
```
java -Dfile.encoding=UTF-8 -cp .;ojdbc8.jar CrmAdminTool       (Windows)
java -Dfile.encoding=UTF-8 -cp .:ojdbc8.jar CrmAdminTool       (Solaris/Linux)
```

## Admin Tool — 10 Tabs

| Tab | Purpose |
|-----|---------|
| Credentials | Manage API credentials with AES-256 encryption |
| Service Registry | Add/Edit/Enable/Disable services + New Service Wizard |
| Field Mappings | JSON field mappings per service |
| Watermark | Track last processed timestamp per service |
| Error Codes | Error code master with IS_RETRYABLE flag |
| Monitor | Dashboard / All Records / Action Needed / Retry Queue / Error Triage / Callback Audit |
| Script Download | Generate SQL scripts for SIT/UAT/PROD deployment |
| Scheduler | View/Enable/Disable/Run scheduler jobs |
| Health Check | Test APIC token and connectivity |
| Test Push | Push a single record to CRM for testing |

## Monitor Tab — Error Triage Priority

| Priority | Condition | Action |
|----------|-----------|--------|
| 1-CRITICAL | EXHAUSTED + IS_RETRYABLE=N | Fix data/config manually |
| 2-MANUAL | EXHAUSTED + IS_RETRYABLE=Y | Fix issue then Manual Retry |
| 3-AUTO | FAILED + IS_RETRYABLE=Y | Retry job handles automatically |

## Key Design Decisions

- All SQL externalized to `crm-admin.properties` — no SQL hardcoded in Java
- AES-256 encryption for CLIENT_SECRET via Oracle DBMS_CRYPTO
- DB password encrypted via built-in Encrypt Utility (stored as `db.password.enc`)
- Java 8 compatible — no lambdas, no streams, no String.repeat()
- Named bind parameters (`:param`) auto-converted to positional `?` at runtime
- Auto-commit disabled on all connections
- All errors logged to `crm-admin.log` with timestamp

## Scheduler Jobs

| Job | Schedule | Purpose |
|-----|----------|---------|
| CRM_MPM_OUTBOUND_6AM/10AM/2PM/5PM | Daily | Main outbound push |
| CRM_MPM_RETRY_JOB | Every 30 min | Auto-retry FAILED records |
| CRM_MPM_TIMEOUT_JOB | Every 60 min | Mark SENT records as TIMEOUT |
| CRM_MPM_ALL_UNIT_STATUS_11PM/4AM | Daily | Batch unit status push |

## SQL Execution Order (fresh environment)

```
1. sql/schema/CRM_MPM_TABLES_COMPLETE.sql
2. sql/schema/ALTER_TABLES_ADD_MISSING_COLUMNS.sql
3. sql/schema/ALTER_ADD_*.sql  (all ALTER scripts)
4. sql/schema/CREDENTIAL_ENCRYPTION_SETUP.sql
5. sql/schema/PKG_CRM_INTEGRATION_SPEC_V2.sql
6. sql/schema/PKG_CRM_INTEGRATION_BODY_FINAL.sql
7. sql/data/CRM_MPM_API_REGISTRY_INSERT.sql
8. sql/data/CRM_MPM_FIELD_MAPPING_SEED.sql
9. sql/data/INSERT_CALLBACK_ERROR_CODES.sql
10. sql/scheduler/SCHEDULER_CLEANUP_RECREATE.sql
```

## Author

Tajudeen Jalaudin — Senior Solution Architect, ADIB  
GitHub: github.com/Tajudeenj
