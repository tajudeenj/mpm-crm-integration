package com.adib.crm.admin.service;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;

@Service
public class ScriptService {

    @Autowired private JdbcTemplate jdbc;

    public String generate(String section) {
        StringBuilder sb = new StringBuilder();
        String ts = LocalDateTime.now().format(DateTimeFormatter.ofPattern("dd-MMM-yyyy HH:mm:ss"));

        sb.append("-- ============================================================\n");
        sb.append("-- CRM Integration Deployment Script\n");
        sb.append("-- Generated : ").append(ts).append("\n");
        sb.append("-- Section   : ").append(section).append("\n");
        sb.append("-- ============================================================\n");
        sb.append("SET DEFINE OFF\n");
        sb.append("SET SERVEROUTPUT ON SIZE UNLIMITED\n\n");

        switch (section) {
            case "all":
                sb.append(genRegistry());
                sb.append(genMappings());
                sb.append(genErrorCodes());
                sb.append(genScheduler());
                sb.append(genWatermark());
                sb.append(genUsers());
                sb.append(genTableDDL());
                sb.append(genSequenceDDL());
                break;
            case "registry":
                sb.append(genRegistry());
                sb.append(genMappings());
                sb.append(genErrorCodes());
                break;
            case "scheduler":
                sb.append(genScheduler());
                break;
            case "watermark":
                sb.append(genWatermark());
                break;
            case "users":
                sb.append(genUsers());
                break;
            case "ddl":
                sb.append(genTableDDL());
                break;
            case "sequences":
                sb.append(genSequenceDDL());
                break;
            default:
                sb.append("-- Unknown section: ").append(section).append("\n");
        }

        return sb.toString();
    }

    // ── SERVICE REGISTRY ─────────────────────────────────────────────────────
    private String genRegistry() {
        StringBuilder sb = new StringBuilder();
        sb.append("-- ===========================\n");
        sb.append("-- SERVICE REGISTRY\n");
        sb.append("-- ===========================\n");

        List<Map<String, Object>> rows = jdbc.queryForList(
            "SELECT SERVICE_NAME,ENTITY_NAME,OPERATION_TYPE,SOURCE_TYPE," +
            "NVL(SOURCE_VIEW,'') AS SOURCE_VIEW,NVL(SOURCE_PROC,'') AS SOURCE_PROC," +
            "NVL(SOURCE_FILTER_COL,'') AS SOURCE_FILTER_COL," +
            "NVL(SOURCE_KEY_COL,'') AS SOURCE_KEY_COL," +
            "NVL(JSON_MAPPING_NAME,'') AS JSON_MAPPING_NAME," +
            "NVL(RECORD_TYPE_HDR,'') AS RECORD_TYPE_HDR," +
            "NVL(EVENT_CODE_HDR,'') AS EVENT_CODE_HDR," +
            "NVL(APIC_ENDPOINT_URL,'') AS APIC_ENDPOINT_URL," +
            "NVL(HTTP_METHOD,'POST') AS HTTP_METHOD," +
            "NVL(APIC_API_VERSION,'') AS APIC_API_VERSION," +
            "NVL(CALLBACK_TARGET_TABLE,'') AS CALLBACK_TARGET_TABLE," +
            "NVL(CALLBACK_KEY_COL,'') AS CALLBACK_KEY_COL," +
            "NVL(CALLBACK_STATUS_COL,'') AS CALLBACK_STATUS_COL," +
            "NVL(CALLBACK_REF_COL,'') AS CALLBACK_REF_COL," +
            "NVL(POST_CALLBACK_PROC,'') AS POST_CALLBACK_PROC," +
            "NVL(CRED_CODE,'') AS CRED_CODE," +
            "NVL(EXECUTION_ORDER,99) AS EXECUTION_ORDER," +
            "NVL(BATCH_SIZE,100) AS BATCH_SIZE," +
            "NVL(MAX_RETRY_COUNT,3) AS MAX_RETRY_COUNT," +
            "NVL(RETRY_INTERVAL_MINUTES,30) AS RETRY_INTERVAL_MINUTES," +
            "NVL(TIMEOUT_MINUTES,60) AS TIMEOUT_MINUTES," +
            "IS_ACTIVE " +
            "FROM CRM_MPM_API_REGISTRY ORDER BY EXECUTION_ORDER,SERVICE_NAME");

        for (Map<String, Object> r : rows) {
            String svc = s(r.get("SERVICE_NAME"));
            sb.append("MERGE INTO CRM_MPM_API_REGISTRY t\n");
            sb.append("USING (SELECT '").append(svc).append("' AS sn FROM DUAL) s\n");
            sb.append("ON (t.SERVICE_NAME = s.sn)\n");
            sb.append("WHEN MATCHED THEN UPDATE SET\n");
            sb.append("    ENTITY_NAME='").append(q(r.get("ENTITY_NAME"))).append("',\n");
            sb.append("    OPERATION_TYPE='").append(q(r.get("OPERATION_TYPE"))).append("',\n");
            sb.append("    SOURCE_TYPE='").append(q(r.get("SOURCE_TYPE"))).append("',\n");
            sb.append("    SOURCE_VIEW=").append(nv(r.get("SOURCE_VIEW"))).append(",\n");
            sb.append("    SOURCE_PROC=").append(nv(r.get("SOURCE_PROC"))).append(",\n");
            sb.append("    SOURCE_FILTER_COL=").append(nv(r.get("SOURCE_FILTER_COL"))).append(",\n");
            sb.append("    SOURCE_KEY_COL=").append(nv(r.get("SOURCE_KEY_COL"))).append(",\n");
            sb.append("    JSON_MAPPING_NAME=").append(nv(r.get("JSON_MAPPING_NAME"))).append(",\n");
            sb.append("    RECORD_TYPE_HDR=").append(nv(r.get("RECORD_TYPE_HDR"))).append(",\n");
            sb.append("    EVENT_CODE_HDR=").append(nv(r.get("EVENT_CODE_HDR"))).append(",\n");
            sb.append("    APIC_ENDPOINT_URL=").append(nv(r.get("APIC_ENDPOINT_URL"))).append(",\n");
            sb.append("    HTTP_METHOD='").append(q(r.get("HTTP_METHOD"))).append("',\n");
            sb.append("    APIC_API_VERSION=").append(nv(r.get("APIC_API_VERSION"))).append(",\n");
            sb.append("    CALLBACK_TARGET_TABLE=").append(nv(r.get("CALLBACK_TARGET_TABLE"))).append(",\n");
            sb.append("    CALLBACK_KEY_COL=").append(nv(r.get("CALLBACK_KEY_COL"))).append(",\n");
            sb.append("    CALLBACK_STATUS_COL=").append(nv(r.get("CALLBACK_STATUS_COL"))).append(",\n");
            sb.append("    CALLBACK_REF_COL=").append(nv(r.get("CALLBACK_REF_COL"))).append(",\n");
            sb.append("    POST_CALLBACK_PROC=").append(nv(r.get("POST_CALLBACK_PROC"))).append(",\n");
            sb.append("    CRED_CODE=").append(nv(r.get("CRED_CODE"))).append(",\n");
            sb.append("    EXECUTION_ORDER=").append(r.get("EXECUTION_ORDER")).append(",\n");
            sb.append("    BATCH_SIZE=").append(r.get("BATCH_SIZE")).append(",\n");
            sb.append("    MAX_RETRY_COUNT=").append(r.get("MAX_RETRY_COUNT")).append(",\n");
            sb.append("    RETRY_INTERVAL_MINUTES=").append(r.get("RETRY_INTERVAL_MINUTES")).append(",\n");
            sb.append("    TIMEOUT_MINUTES=").append(r.get("TIMEOUT_MINUTES")).append(",\n");
            sb.append("    IS_ACTIVE='").append(q(r.get("IS_ACTIVE"))).append("',UPDATED_DATE=SYSDATE\n");
            sb.append("WHEN NOT MATCHED THEN INSERT (\n");
            sb.append("    SERVICE_NAME,ENTITY_NAME,OPERATION_TYPE,SOURCE_TYPE,\n");
            sb.append("    SOURCE_VIEW,SOURCE_PROC,SOURCE_FILTER_COL,SOURCE_KEY_COL,\n");
            sb.append("    JSON_MAPPING_NAME,RECORD_TYPE_HDR,EVENT_CODE_HDR,\n");
            sb.append("    APIC_ENDPOINT_URL,HTTP_METHOD,APIC_API_VERSION,\n");
            sb.append("    CALLBACK_TARGET_TABLE,CALLBACK_KEY_COL,CALLBACK_STATUS_COL,\n");
            sb.append("    CALLBACK_REF_COL,POST_CALLBACK_PROC,CRED_CODE,\n");
            sb.append("    EXECUTION_ORDER,BATCH_SIZE,MAX_RETRY_COUNT,\n");
            sb.append("    RETRY_INTERVAL_MINUTES,TIMEOUT_MINUTES,IS_ACTIVE,CREATED_DATE,UPDATED_DATE)\n");
            sb.append("VALUES ('").append(svc).append("','").append(q(r.get("ENTITY_NAME")))
              .append("','").append(q(r.get("OPERATION_TYPE"))).append("','")
              .append(q(r.get("SOURCE_TYPE"))).append("',\n    ")
              .append(nv(r.get("SOURCE_VIEW"))).append(",")
              .append(nv(r.get("SOURCE_PROC"))).append(",")
              .append(nv(r.get("SOURCE_FILTER_COL"))).append(",")
              .append(nv(r.get("SOURCE_KEY_COL"))).append(",\n    ")
              .append(nv(r.get("JSON_MAPPING_NAME"))).append(",")
              .append(nv(r.get("RECORD_TYPE_HDR"))).append(",")
              .append(nv(r.get("EVENT_CODE_HDR"))).append(",\n    ")
              .append(nv(r.get("APIC_ENDPOINT_URL"))).append(",'")
              .append(q(r.get("HTTP_METHOD"))).append("',")
              .append(nv(r.get("APIC_API_VERSION"))).append(",\n    ")
              .append(nv(r.get("CALLBACK_TARGET_TABLE"))).append(",")
              .append(nv(r.get("CALLBACK_KEY_COL"))).append(",")
              .append(nv(r.get("CALLBACK_STATUS_COL"))).append(",\n    ")
              .append(nv(r.get("CALLBACK_REF_COL"))).append(",")
              .append(nv(r.get("POST_CALLBACK_PROC"))).append(",")
              .append(nv(r.get("CRED_CODE"))).append(",\n    ")
              .append(r.get("EXECUTION_ORDER")).append(",")
              .append(r.get("BATCH_SIZE")).append(",")
              .append(r.get("MAX_RETRY_COUNT")).append(",")
              .append(r.get("RETRY_INTERVAL_MINUTES")).append(",")
              .append(r.get("TIMEOUT_MINUTES")).append(",'")
              .append(q(r.get("IS_ACTIVE"))).append("',SYSDATE,SYSDATE);\n\n");
        }
        sb.append("COMMIT;\n\n");
        return sb.toString();
    }

    // ── FIELD MAPPINGS ────────────────────────────────────────────────────────
    private String genMappings() {
        StringBuilder sb = new StringBuilder();
        sb.append("-- ===========================\n");
        sb.append("-- FIELD MAPPINGS\n");
        sb.append("-- ===========================\n");

        List<Map<String, Object>> rows = jdbc.queryForList(
            "SELECT JSON_MAPPING_NAME,NVL(DISPLAY_ORDER,1) AS DISPLAY_ORDER," +
            "SOURCE_COLUMN,JSON_PATH,DATA_TYPE," +
            "NVL(DATE_FORMAT,'') AS DATE_FORMAT," +
            "NVL(IS_MANDATORY,'N') AS IS_MANDATORY,IS_ACTIVE " +
            "FROM CRM_MPM_API_FIELD_MAPPING ORDER BY JSON_MAPPING_NAME,DISPLAY_ORDER");

        for (Map<String, Object> r : rows) {
            sb.append("MERGE INTO CRM_MPM_API_FIELD_MAPPING m\n");
            sb.append("USING (SELECT '").append(q(r.get("JSON_MAPPING_NAME")))
              .append("' AS jmn,'").append(q(r.get("SOURCE_COLUMN")))
              .append("' AS sc FROM DUAL) s\n");
            sb.append("ON (m.JSON_MAPPING_NAME=s.jmn AND m.SOURCE_COLUMN=s.sc)\n");
            sb.append("WHEN MATCHED THEN UPDATE SET\n");
            sb.append("    DISPLAY_ORDER=").append(r.get("DISPLAY_ORDER"))
              .append(",JSON_PATH='").append(q(r.get("JSON_PATH")))
              .append("',DATA_TYPE='").append(q(r.get("DATA_TYPE")))
              .append("',DATE_FORMAT=").append(nv(r.get("DATE_FORMAT")))
              .append(",IS_MANDATORY='").append(q(r.get("IS_MANDATORY")))
              .append("',IS_ACTIVE='").append(q(r.get("IS_ACTIVE"))).append("'\n");
            sb.append("WHEN NOT MATCHED THEN INSERT\n");
            sb.append("    (JSON_MAPPING_NAME,DISPLAY_ORDER,SOURCE_COLUMN,JSON_PATH,\n");
            sb.append("     DATA_TYPE,DATE_FORMAT,IS_MANDATORY,IS_ACTIVE)\n");
            sb.append("VALUES ('").append(q(r.get("JSON_MAPPING_NAME")))
              .append("',").append(r.get("DISPLAY_ORDER"))
              .append(",'").append(q(r.get("SOURCE_COLUMN")))
              .append("','").append(q(r.get("JSON_PATH")))
              .append("','").append(q(r.get("DATA_TYPE")))
              .append("',").append(nv(r.get("DATE_FORMAT")))
              .append(",'").append(q(r.get("IS_MANDATORY")))
              .append("','").append(q(r.get("IS_ACTIVE"))).append("');\n\n");
        }
        sb.append("COMMIT;\n\n");
        return sb.toString();
    }

    // ── ERROR CODES ───────────────────────────────────────────────────────────
    private String genErrorCodes() {
        StringBuilder sb = new StringBuilder();
        sb.append("-- ===========================\n");
        sb.append("-- ERROR CODE MASTER\n");
        sb.append("-- ===========================\n");

        List<Map<String, Object>> rows = jdbc.queryForList(
            "SELECT ERROR_CODE,ERROR_CATEGORY,ERROR_DESCRIPTION,IS_RETRYABLE " +
            "FROM CRM_MPM_ERROR_CODE_MASTER ORDER BY ERROR_CODE");

        for (Map<String, Object> r : rows) {
            sb.append("MERGE INTO CRM_MPM_ERROR_CODE_MASTER e\n");
            sb.append("USING (SELECT '").append(q(r.get("ERROR_CODE")))
              .append("' AS ec FROM DUAL) s ON (e.ERROR_CODE=s.ec)\n");
            sb.append("WHEN MATCHED THEN UPDATE SET ERROR_CATEGORY='")
              .append(q(r.get("ERROR_CATEGORY"))).append("',ERROR_DESCRIPTION='")
              .append(q(r.get("ERROR_DESCRIPTION"))).append("',IS_RETRYABLE='")
              .append(q(r.get("IS_RETRYABLE"))).append("'\n");
            sb.append("WHEN NOT MATCHED THEN INSERT\n");
            sb.append("    (ERROR_CODE,ERROR_CATEGORY,ERROR_DESCRIPTION,IS_RETRYABLE)\n");
            sb.append("VALUES ('").append(q(r.get("ERROR_CODE")))
              .append("','").append(q(r.get("ERROR_CATEGORY")))
              .append("','").append(q(r.get("ERROR_DESCRIPTION")))
              .append("','").append(q(r.get("IS_RETRYABLE"))).append("');\n\n");
        }
        sb.append("COMMIT;\n\n");
        return sb.toString();
    }

    // ── USERS ─────────────────────────────────────────────────────────────────
    private String genUsers() {
        StringBuilder sb = new StringBuilder();
        sb.append("-- ===========================\n");
        sb.append("-- APP USERS (CRM_MPM_APP_USERS)\n");
        sb.append("-- Roles: ADMIN, OPERATOR, VIEWER\n");
        sb.append("-- Password hashes are BCrypt — use bcrypt-generator.com to create new ones\n");
        sb.append("-- ===========================\n");

        try {
            List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT USERNAME,NVL(FULL_NAME,'') AS FULL_NAME,PASSWORD_HASH,ROLE," +
                "IS_ACTIVE,NVL(ALLOWED_SERVICES,'') AS ALLOWED_SERVICES " +
                "FROM CRM_MPM_APP_USERS ORDER BY ROLE,USERNAME");

            for (Map<String, Object> r : rows) {
                sb.append("MERGE INTO CRM_MPM_APP_USERS u\n");
                sb.append("USING (SELECT '").append(q(r.get("USERNAME")))
                  .append("' AS un FROM DUAL) s ON (u.USERNAME=s.un)\n");
                sb.append("WHEN MATCHED THEN UPDATE SET\n");
                sb.append("    FULL_NAME='").append(q(r.get("FULL_NAME")))
                  .append("',ROLE='").append(q(r.get("ROLE")))
                  .append("',IS_ACTIVE='").append(q(r.get("IS_ACTIVE")))
                  .append("',ALLOWED_SERVICES=").append(nv(r.get("ALLOWED_SERVICES")))
                  .append(",UPDATED_DATE=SYSDATE\n");
                sb.append("WHEN NOT MATCHED THEN INSERT\n");
                sb.append("    (USERNAME,FULL_NAME,PASSWORD_HASH,ROLE,IS_ACTIVE,");
                sb.append("ALLOWED_SERVICES,CREATED_DATE,UPDATED_DATE)\n");
                sb.append("VALUES ('").append(q(r.get("USERNAME")))
                  .append("','").append(q(r.get("FULL_NAME")))
                  .append("','").append(q(r.get("PASSWORD_HASH")))
                  .append("','").append(q(r.get("ROLE")))
                  .append("','").append(q(r.get("IS_ACTIVE")))
                  .append("',").append(nv(r.get("ALLOWED_SERVICES")))
                  .append(",SYSDATE,SYSDATE);\n");
                sb.append("-- Role: ").append(r.get("ROLE"))
                  .append(" | Services: ")
                  .append(r.get("ALLOWED_SERVICES") == null ||
                          r.get("ALLOWED_SERVICES").toString().isEmpty()
                          ? "ALL" : r.get("ALLOWED_SERVICES"))
                  .append("\n\n");
            }
        } catch (Exception e) {
            sb.append("-- Error reading users: ").append(e.getMessage()).append("\n");
        }
        sb.append("COMMIT;\n\n");
        return sb.toString();
    }

    // ── SCHEDULER ─────────────────────────────────────────────────────────────
    private String genScheduler() {
        StringBuilder sb = new StringBuilder();
        sb.append("-- ===========================\n");
        sb.append("-- SCHEDULER JOBS\n");
        sb.append("-- ===========================\n");

        try {
            List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT JOB_NAME, JOB_ACTION, REPEAT_INTERVAL, " +
                "CASE WHEN ENABLED='TRUE' THEN 'TRUE' ELSE 'FALSE' END AS ENABLED, " +
                "NVL(COMMENTS,'') AS COMMENTS " +
                "FROM USER_SCHEDULER_JOBS ORDER BY JOB_NAME");

            for (Map<String, Object> r : rows) {
                sb.append("BEGIN\n");
                sb.append("    DBMS_SCHEDULER.CREATE_JOB(\n");
                sb.append("        job_name        => '").append(q(r.get("JOB_NAME"))).append("',\n");
                sb.append("        job_type        => 'PLSQL_BLOCK',\n");
                sb.append("        job_action      => '").append(q(r.get("JOB_ACTION"))).append("',\n");
                sb.append("        repeat_interval => '").append(q(r.get("REPEAT_INTERVAL"))).append("',\n");
                sb.append("        enabled         => FALSE,\n");
                sb.append("        comments        => '").append(q(r.get("COMMENTS"))).append("');\n");
                sb.append("END;\n/\n\n");
            }
        } catch (Exception e) {
            sb.append("-- Error reading scheduler jobs: ").append(e.getMessage()).append("\n");
        }
        sb.append("-- Enable jobs after verifying:\n");
        sb.append("-- BEGIN DBMS_SCHEDULER.ENABLE('JOB_NAME'); END;\n");
        sb.append("-- /\n\n");
        sb.append("COMMIT;\n\n");
        return sb.toString();
    }

    // ── WATERMARK ─────────────────────────────────────────────────────────────
    private String genWatermark() {
        StringBuilder sb = new StringBuilder();
        sb.append("-- ===========================\n");
        sb.append("-- WATERMARK INIT\n");
        sb.append("-- ===========================\n");

        List<Map<String, Object>> rows = jdbc.queryForList(
            "SELECT REGISTRY_ID, SERVICE_NAME FROM CRM_MPM_API_REGISTRY " +
            "WHERE IS_ACTIVE='Y' ORDER BY EXECUTION_ORDER,SERVICE_NAME");

        for (Map<String, Object> r : rows) {
            sb.append("INSERT INTO CRM_MPM_API_WATERMARK\n");
            sb.append("    (REGISTRY_ID,LAST_RUN_STATUS,LAST_RUN_RECORDS)\n");
            sb.append("SELECT ").append(r.get("REGISTRY_ID"))
              .append(",'INIT',0 FROM DUAL\n");
            sb.append("WHERE NOT EXISTS (\n");
            sb.append("    SELECT 1 FROM CRM_MPM_API_WATERMARK\n");
            sb.append("    WHERE REGISTRY_ID=").append(r.get("REGISTRY_ID")).append(");\n");
            sb.append("-- Service: ").append(r.get("SERVICE_NAME")).append("\n\n");
        }
        sb.append("COMMIT;\n\n");
        return sb.toString();
    }

    // ── TABLE DDL ─────────────────────────────────────────────────────────────
    private String genTableDDL() {
        return
            "-- ===========================\n" +
            "-- TABLE DDL\n" +
            "-- Run on SOURCE DB to extract DDL:\n" +
            "-- ===========================\n" +
            "SELECT DBMS_METADATA.GET_DDL('TABLE',TABLE_NAME)\n" +
            "FROM   USER_TABLES\n" +
            "WHERE  TABLE_NAME LIKE 'CRM_MPM_%'\n" +
            "ORDER  BY TABLE_NAME;\n\n";
    }

    // ── SEQUENCE DDL ──────────────────────────────────────────────────────────
    private String genSequenceDDL() {
        return
            "-- ===========================\n" +
            "-- SEQUENCE DDL\n" +
            "-- Run on SOURCE DB to extract DDL:\n" +
            "-- ===========================\n" +
            "SELECT DBMS_METADATA.GET_DDL('SEQUENCE',SEQUENCE_NAME)\n" +
            "FROM   USER_SEQUENCES\n" +
            "WHERE  SEQUENCE_NAME LIKE 'SEQ_CRM%'\n" +
            "   OR  SEQUENCE_NAME LIKE 'CRM_MPM%'\n" +
            "ORDER  BY SEQUENCE_NAME;\n\n";
    }

    // ── HELPERS ───────────────────────────────────────────────────────────────
    private String s(Object o)  { return o == null ? "" : String.valueOf(o); }
    private String q(Object o)  { return s(o).replace("'", "''"); }
    private String nv(Object o) {
        String v = s(o).trim();
        return v.isEmpty() ? "NULL" : "'" + q(o) + "'";
    }
}
