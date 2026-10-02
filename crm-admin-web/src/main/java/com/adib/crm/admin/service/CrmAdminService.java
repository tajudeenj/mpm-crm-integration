package com.adib.crm.admin.service;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.net.HttpURLConnection;
import java.net.URL;
import java.sql.*;
import java.util.*;
import javax.sql.DataSource;

@Service
public class CrmAdminService {

    @Autowired
    private JdbcTemplate jdbc;

    @Autowired
    private DataSource dataSource;

    // ── CREDENTIALS ─────────────────────────────────────────────────────────
    public List<Map<String, Object>> listCredentials() {
        return jdbc.queryForList(
            "SELECT CRED_CODE, CLIENT_ID, TOKEN_URL, IS_ACTIVE, " +
            "CASE WHEN CLIENT_SECRET_ENCRYPTED IS NOT NULL THEN 'AES256 OK' ELSE 'Plain Text' END AS SECRET_ENC, " +
            "TO_CHAR(UPDATED_DATE,'DD-MON-YY HH24:MI') AS UPDATED " +
            "FROM CRM_MPM_API_CREDENTIALS ORDER BY CRED_CODE");
    }

    public Map<String, Object> loadCredential(String credCode) {
        return jdbc.queryForMap(
            "SELECT CRED_CODE, TOKEN_URL, CLIENT_ID, " +
            "NVL(SCOPE,''), NVL(GRANT_TYPE,'client_credentials'), " +
            "NVL(WALLET_PATH,''), IS_ACTIVE " +
            "FROM CRM_MPM_API_CREDENTIALS WHERE CRED_CODE = ?", credCode);
    }

    public void saveCredential(Map<String, String> b) {
        String sql =
            "DECLARE " +
            "    v_key RAW(32); v_sec_enc BLOB; " +
            "BEGIN " +
            "    SELECT ENCRYPT_KEY INTO v_key FROM CRM_MPM_ENCRYPT_CONFIG " +
            "    WHERE IS_ACTIVE='Y' AND ROWNUM=1; " +
            "    v_sec_enc := DBMS_CRYPTO.ENCRYPT(" +
            "        src => UTL_RAW.CAST_TO_RAW(?), " +
            "        typ => DBMS_CRYPTO.ENCRYPT_AES256+DBMS_CRYPTO.CHAIN_CBC+DBMS_CRYPTO.PAD_PKCS5, " +
            "        key => v_key); " +
            "    MERGE INTO CRM_MPM_API_CREDENTIALS t " +
            "    USING (SELECT ? AS cc FROM DUAL) s ON (t.CRED_CODE=s.cc) " +
            "    WHEN MATCHED THEN UPDATE SET " +
            "        TOKEN_URL=?,CLIENT_ID=?,CLIENT_SECRET_ENCRYPTED=v_sec_enc," +
            "        CLIENT_SECRET_REF='*** ENCRYPTED ***',ENCRYPT_KEY_REF='CRM_INTEGRATION_KEY'," +
            "        SCOPE=?,GRANT_TYPE=?,WALLET_PATH=?,WALLET_PASSWORD=?," +
            "        IS_ACTIVE=?,UPDATED_DATE=SYSDATE " +
            "    WHEN NOT MATCHED THEN INSERT (" +
            "        CRED_CODE,TOKEN_URL,CLIENT_ID,CLIENT_SECRET_ENCRYPTED," +
            "        CLIENT_SECRET_REF,ENCRYPT_KEY_REF,SCOPE,GRANT_TYPE," +
            "        WALLET_PATH,WALLET_PASSWORD,IS_ACTIVE,CREATED_DATE,UPDATED_DATE) " +
            "    VALUES (?,?,?,v_sec_enc,'*** ENCRYPTED ***','CRM_INTEGRATION_KEY'," +
            "        ?,?,?,?,?,SYSDATE,SYSDATE); " +
            "END;";
        jdbc.update(sql,
            b.get("clientSecret"),
            b.get("credCode"), b.get("tokenUrl"), b.get("clientId"),
            n(b.get("scope")), n(b.get("grantType")), n(b.get("walletPath")), n(b.get("walletPwd")),
            b.get("isActive"),
            b.get("credCode"), b.get("tokenUrl"), b.get("clientId"),
            n(b.get("scope")), n(b.get("grantType")), n(b.get("walletPath")), n(b.get("walletPwd")),
            b.get("isActive"));
    }

    public void rotateSecret(String credCode, String newSecret) {
        jdbc.update(
            "DECLARE v_key RAW(32); v_enc BLOB; BEGIN " +
            "SELECT ENCRYPT_KEY INTO v_key FROM CRM_MPM_ENCRYPT_CONFIG " +
            "WHERE IS_ACTIVE='Y' AND ROWNUM=1; " +
            "v_enc := DBMS_CRYPTO.ENCRYPT(src=>UTL_RAW.CAST_TO_RAW(?)," +
            "typ=>DBMS_CRYPTO.ENCRYPT_AES256+DBMS_CRYPTO.CHAIN_CBC+DBMS_CRYPTO.PAD_PKCS5,key=>v_key); " +
            "UPDATE CRM_MPM_API_CREDENTIALS SET CLIENT_SECRET_ENCRYPTED=v_enc," +
            "CLIENT_SECRET_REF='*** ENCRYPTED ***',ENCRYPT_KEY_REF='CRM_INTEGRATION_KEY'," +
            "UPDATED_DATE=SYSDATE WHERE CRED_CODE=?; END;",
            newSecret, credCode);
    }

    public void rotateWallet(String credCode, String newWalletPwd) {
        jdbc.update(
            "UPDATE CRM_MPM_API_CREDENTIALS SET WALLET_PASSWORD=?,UPDATED_DATE=SYSDATE WHERE CRED_CODE=?",
            newWalletPwd, credCode);
    }

    public Map<String, Object> testDecrypt(String credCode, String type) {
        Map<String, Object> result = new LinkedHashMap<>();
        try (Connection con = dataSource.getConnection();
             CallableStatement cs = con.prepareCall(
                "WALLET".equals(type)
                ? "DECLARE v_plain VARCHAR2(4000); v_result VARCHAR2(4000); BEGIN " +
                  "SELECT NVL(WALLET_PASSWORD,'NULL') INTO v_plain FROM CRM_MPM_API_CREDENTIALS WHERE CRED_CODE=?; " +
                  "IF v_plain IS NULL OR v_plain='NULL' THEN v_result:='NOT SET'; " +
                  "ELSIF v_plain='*** ENCRYPTED ***' THEN v_result:='Stored as encrypted marker'; " +
                  "ELSE v_result:='Plain text - length='||LENGTH(v_plain); END IF; ?:=v_result; END;"
                : "DECLARE v_key RAW(32); v_enc BLOB; v_dec VARCHAR2(4000); v_result VARCHAR2(4000); BEGIN " +
                  "SELECT ENCRYPT_KEY INTO v_key FROM CRM_MPM_ENCRYPT_CONFIG WHERE IS_ACTIVE='Y' AND ROWNUM=1; " +
                  "SELECT CLIENT_SECRET_ENCRYPTED INTO v_enc FROM CRM_MPM_API_CREDENTIALS WHERE CRED_CODE=?; " +
                  "IF v_enc IS NOT NULL THEN v_dec:=UTL_RAW.CAST_TO_VARCHAR2(DBMS_CRYPTO.DECRYPT(" +
                  "src=>v_enc,typ=>DBMS_CRYPTO.ENCRYPT_AES256+DBMS_CRYPTO.CHAIN_CBC+DBMS_CRYPTO.PAD_PKCS5,key=>v_key)); " +
                  "v_result:='OK - length='||LENGTH(v_dec); ELSE v_result:='NOT ENCRYPTED'; END IF; ?:=v_result; END;")) {
            cs.setString(1, credCode);
            cs.registerOutParameter(2, Types.VARCHAR);
            cs.execute();
            result.put("result", cs.getString(2));
            result.put("credCode", credCode);
            result.put("type", type);
        } catch (Exception ex) {
            result.put("result", "ERROR: " + ex.getMessage());
        }
        return result;
    }

    public List<String> credCodes() {
        return jdbc.queryForList(
            "SELECT CRED_CODE FROM CRM_MPM_API_CREDENTIALS WHERE IS_ACTIVE='Y' ORDER BY CRED_CODE",
            String.class);
    }

    // ── SERVICE REGISTRY ────────────────────────────────────────────────────
    public List<Map<String, Object>> listRegistry() {
        return jdbc.queryForList(
            "SELECT SERVICE_NAME,ENTITY_NAME,OPERATION_TYPE,SOURCE_TYPE," +
            "NVL(SOURCE_VIEW,''),NVL(SOURCE_PROC,''),NVL(SOURCE_FILTER_COL,''),NVL(SOURCE_KEY_COL,'')," +
            "NVL(JSON_MAPPING_NAME,''),NVL(RECORD_TYPE_HDR,''),NVL(EVENT_CODE_HDR,'')," +
            "NVL(APIC_ENDPOINT_URL,''),NVL(HTTP_METHOD,''),NVL(APIC_API_VERSION,'')," +
            "NVL(CALLBACK_TARGET_TABLE,''),NVL(CALLBACK_KEY_COL,'')," +
            "NVL(CALLBACK_STATUS_COL,''),NVL(CALLBACK_REF_COL,''),NVL(POST_CALLBACK_PROC,'')," +
            "NVL(CRED_CODE,''),TO_CHAR(NVL(EXECUTION_ORDER,99)),TO_CHAR(NVL(BATCH_SIZE,100))," +
            "TO_CHAR(NVL(MAX_RETRY_COUNT,3)),TO_CHAR(NVL(RETRY_INTERVAL_MINUTES,30))," +
            "TO_CHAR(NVL(TIMEOUT_MINUTES,60)),IS_ACTIVE " +
            "FROM CRM_MPM_API_REGISTRY ORDER BY EXECUTION_ORDER,SERVICE_NAME");
    }

    public void saveRegistry(Map<String, String> b) {
        String sql =
            "MERGE INTO CRM_MPM_API_REGISTRY r USING (SELECT ? AS sn FROM DUAL) s ON (r.SERVICE_NAME=s.sn) " +
            "WHEN MATCHED THEN UPDATE SET ENTITY_NAME=?,OPERATION_TYPE=?,SOURCE_TYPE=?," +
            "SOURCE_VIEW=?,SOURCE_PROC=?,SOURCE_FILTER_COL=?,SOURCE_KEY_COL=?," +
            "JSON_MAPPING_NAME=?,RECORD_TYPE_HDR=?,EVENT_CODE_HDR=?," +
            "APIC_ENDPOINT_URL=?,HTTP_METHOD=?,APIC_API_VERSION=?," +
            "CALLBACK_TARGET_TABLE=?,CALLBACK_KEY_COL=?,CALLBACK_STATUS_COL=?,CALLBACK_REF_COL=?," +
            "POST_CALLBACK_PROC=?,CRED_CODE=?," +
            "EXECUTION_ORDER=TO_NUMBER(?),BATCH_SIZE=TO_NUMBER(?),MAX_RETRY_COUNT=TO_NUMBER(?)," +
            "RETRY_INTERVAL_MINUTES=TO_NUMBER(?),TIMEOUT_MINUTES=TO_NUMBER(?),IS_ACTIVE=?,UPDATED_DATE=SYSDATE " +
            "WHEN NOT MATCHED THEN INSERT (" +
            "SERVICE_NAME,ENTITY_NAME,OPERATION_TYPE,SOURCE_TYPE,SOURCE_VIEW,SOURCE_PROC," +
            "SOURCE_FILTER_COL,SOURCE_KEY_COL,JSON_MAPPING_NAME,RECORD_TYPE_HDR,EVENT_CODE_HDR," +
            "APIC_ENDPOINT_URL,HTTP_METHOD,APIC_API_VERSION,CALLBACK_TARGET_TABLE,CALLBACK_KEY_COL," +
            "CALLBACK_STATUS_COL,CALLBACK_REF_COL,POST_CALLBACK_PROC,CRED_CODE," +
            "EXECUTION_ORDER,BATCH_SIZE,MAX_RETRY_COUNT,RETRY_INTERVAL_MINUTES,TIMEOUT_MINUTES,IS_ACTIVE," +
            "CREATED_DATE,UPDATED_DATE) " +
            "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?," +
            "TO_NUMBER(?),TO_NUMBER(?),TO_NUMBER(?),TO_NUMBER(?),TO_NUMBER(?),?,SYSDATE,SYSDATE)";
        Object[] p = {
            b.get("serviceName"),
            b.get("entityName"),b.get("operationType"),b.get("sourceType"),
            n(b.get("sourceView")),n(b.get("sourceProc")),n(b.get("sourceFilterCol")),n(b.get("sourceKeyCol")),
            n(b.get("jsonMappingName")),n(b.get("recordTypeHdr")),n(b.get("eventCodeHdr")),
            n(b.get("apicEndpointUrl")),n(b.get("httpMethod")),n(b.get("apicApiVersion")),
            n(b.get("callbackTargetTable")),n(b.get("callbackKeyCol")),
            n(b.get("callbackStatusCol")),n(b.get("callbackRefCol")),
            n(b.get("postCallbackProc")),n(b.get("credCode")),
            b.get("executionOrder"),b.get("batchSize"),b.get("maxRetryCount"),
            b.get("retryIntervalMinutes"),b.get("timeoutMinutes"),b.get("isActive"),
            // INSERT values
            b.get("serviceName"),
            b.get("entityName"),b.get("operationType"),b.get("sourceType"),
            n(b.get("sourceView")),n(b.get("sourceProc")),n(b.get("sourceFilterCol")),n(b.get("sourceKeyCol")),
            n(b.get("jsonMappingName")),n(b.get("recordTypeHdr")),n(b.get("eventCodeHdr")),
            n(b.get("apicEndpointUrl")),n(b.get("httpMethod")),n(b.get("apicApiVersion")),
            n(b.get("callbackTargetTable")),n(b.get("callbackKeyCol")),
            n(b.get("callbackStatusCol")),n(b.get("callbackRefCol")),
            n(b.get("postCallbackProc")),n(b.get("credCode")),
            b.get("executionOrder"),b.get("batchSize"),b.get("maxRetryCount"),
            b.get("retryIntervalMinutes"),b.get("timeoutMinutes"),b.get("isActive")
        };
        jdbc.update(sql, p);
    }

    public void setRegistryActive(String serviceName, String isActive) {
        jdbc.update(
            "UPDATE CRM_MPM_API_REGISTRY SET IS_ACTIVE=?,UPDATED_DATE=SYSDATE WHERE SERVICE_NAME=?",
            isActive, serviceName);
    }

    // ── FIELD MAPPINGS ───────────────────────────────────────────────────────
    public List<String> mappingNames() {
        return jdbc.queryForList(
            "SELECT DISTINCT JSON_MAPPING_NAME FROM CRM_MPM_API_FIELD_MAPPING ORDER BY JSON_MAPPING_NAME",
            String.class);
    }

    public List<Map<String, Object>> listMappings(String mappingName) {
        if (mappingName == null || mappingName.isEmpty()) {
            return jdbc.queryForList(
                "SELECT TO_CHAR(MAPPING_ID),JSON_MAPPING_NAME,TO_CHAR(DISPLAY_ORDER)," +
                "SOURCE_COLUMN,JSON_PATH,DATA_TYPE,NVL(DATE_FORMAT,''),NVL(IS_MANDATORY,'N'),IS_ACTIVE " +
                "FROM CRM_MPM_API_FIELD_MAPPING ORDER BY JSON_MAPPING_NAME,DISPLAY_ORDER");
        }
        return jdbc.queryForList(
            "SELECT TO_CHAR(MAPPING_ID),JSON_MAPPING_NAME,TO_CHAR(DISPLAY_ORDER)," +
            "SOURCE_COLUMN,JSON_PATH,DATA_TYPE,NVL(DATE_FORMAT,''),NVL(IS_MANDATORY,'N'),IS_ACTIVE " +
            "FROM CRM_MPM_API_FIELD_MAPPING WHERE JSON_MAPPING_NAME=? ORDER BY DISPLAY_ORDER",
            mappingName);
    }

    public void saveMapping(Map<String, String> b) {
        jdbc.update(
            "MERGE INTO CRM_MPM_API_FIELD_MAPPING m USING (SELECT ? AS jmn,? AS sc FROM DUAL) s " +
            "ON (m.JSON_MAPPING_NAME=s.jmn AND m.SOURCE_COLUMN=s.sc) " +
            "WHEN MATCHED THEN UPDATE SET DISPLAY_ORDER=TO_NUMBER(?),JSON_PATH=?,DATA_TYPE=?," +
            "DATE_FORMAT=?,IS_MANDATORY=?,IS_ACTIVE=? " +
            "WHEN NOT MATCHED THEN INSERT (JSON_MAPPING_NAME,DISPLAY_ORDER,SOURCE_COLUMN," +
            "JSON_PATH,DATA_TYPE,DATE_FORMAT,IS_MANDATORY,IS_ACTIVE) " +
            "VALUES (?,TO_NUMBER(?),?,?,?,?,?,?)",
            b.get("jsonMappingName"),b.get("sourceColumn"),
            b.get("displayOrder"),b.get("jsonPath"),b.get("dataType"),
            n(b.get("dateFormat")),b.get("isMandatory"),b.get("isActive"),
            b.get("jsonMappingName"),b.get("displayOrder"),b.get("sourceColumn"),
            b.get("jsonPath"),b.get("dataType"),n(b.get("dateFormat")),
            b.get("isMandatory"),b.get("isActive"));
    }

    public void setMappingActive(String mappingId, String isActive) {
        jdbc.update(
            "UPDATE CRM_MPM_API_FIELD_MAPPING SET IS_ACTIVE=? WHERE MAPPING_ID=TO_NUMBER(?)",
            isActive, mappingId);
    }

    // ── WATERMARK ────────────────────────────────────────────────────────────
    public List<Map<String, Object>> listWatermarks() {
        return jdbc.queryForList(
            "SELECT R.SERVICE_NAME,TO_CHAR(W.LAST_PROCESSED_TS,'DD-MON-YY HH24:MI')," +
            "NVL(W.LAST_RUN_STATUS,'--'),TO_CHAR(NVL(W.LAST_RUN_RECORDS,0)),TO_CHAR(R.REGISTRY_ID) " +
            "FROM CRM_MPM_API_REGISTRY R LEFT JOIN CRM_MPM_API_WATERMARK W ON W.REGISTRY_ID=R.REGISTRY_ID " +
            "WHERE R.IS_ACTIVE='Y' ORDER BY R.EXECUTION_ORDER,R.SERVICE_NAME");
    }

    public void resetWatermark(String serviceName) {
        jdbc.update(
            "UPDATE CRM_MPM_API_WATERMARK SET LAST_PROCESSED_TS=NULL,LAST_RUN_RECORDS=0," +
            "LAST_RUN_STATUS='RESET',UPDATED_DATE=SYSDATE " +
            "WHERE REGISTRY_ID=(SELECT REGISTRY_ID FROM CRM_MPM_API_REGISTRY WHERE SERVICE_NAME=?)",
            serviceName);
    }

    public void setWatermarkDate(String serviceName, String date) {
        jdbc.update(
            "UPDATE CRM_MPM_API_WATERMARK SET LAST_PROCESSED_TS=TO_TIMESTAMP(?,'DD-MON-YY HH24:MI')," +
            "UPDATED_DATE=SYSDATE WHERE REGISTRY_ID=(SELECT REGISTRY_ID FROM CRM_MPM_API_REGISTRY WHERE SERVICE_NAME=?)",
            date, serviceName);
    }

    // ── ERROR CODES ──────────────────────────────────────────────────────────
    public List<Map<String, Object>> listErrorCodes() {
        return jdbc.queryForList(
            "SELECT ERROR_CODE,ERROR_CATEGORY,ERROR_DESCRIPTION,IS_RETRYABLE " +
            "FROM CRM_MPM_ERROR_CODE_MASTER ORDER BY IS_RETRYABLE DESC,ERROR_CODE");
    }

    public void saveErrorCode(Map<String, String> b) {
        jdbc.update(
            "MERGE INTO CRM_MPM_ERROR_CODE_MASTER e USING (SELECT ? AS ec FROM DUAL) s ON (e.ERROR_CODE=s.ec) " +
            "WHEN MATCHED THEN UPDATE SET ERROR_CATEGORY=?,ERROR_DESCRIPTION=?,IS_RETRYABLE=? " +
            "WHEN NOT MATCHED THEN INSERT (ERROR_CODE,ERROR_CATEGORY,ERROR_DESCRIPTION,IS_RETRYABLE) " +
            "VALUES (?,?,?,?)",
            b.get("errorCode"),b.get("errorCategory"),b.get("errorDescription"),b.get("isRetryable"),
            b.get("errorCode"),b.get("errorCategory"),b.get("errorDescription"),b.get("isRetryable"));
    }

    // ── MONITOR ──────────────────────────────────────────────────────────────
    public List<Map<String, Object>> dashboard() {
        return jdbc.queryForList(
            "SELECT R.SERVICE_NAME,COUNT(*) AS TOTAL," +
            "SUM(CASE WHEN L.FINAL_STATUS='SUCCESS' THEN 1 ELSE 0 END) AS SUCCESS," +
            "SUM(CASE WHEN L.FINAL_STATUS='SENT' THEN 1 ELSE 0 END) AS PENDING," +
            "SUM(CASE WHEN L.FINAL_STATUS='VALIDATION_FAILED' THEN 1 ELSE 0 END) AS VAL_FAILED," +
            "SUM(CASE WHEN L.FINAL_STATUS='DUPLICATE_RECORD' THEN 1 ELSE 0 END) AS DUPLICATE," +
            "SUM(CASE WHEN L.FINAL_STATUS IN ('FAILED','TIMEOUT') THEN 1 ELSE 0 END) AS AUTO_RETRY," +
            "SUM(CASE WHEN L.FINAL_STATUS='EXHAUSTED' THEN 1 ELSE 0 END) AS EXHAUSTED," +
            "SUM(CASE WHEN L.FINAL_STATUS='RECORD_NOT_FOUND' THEN 1 ELSE 0 END) AS PARENT_MISSING," +
            "SUM(CASE WHEN L.FINAL_STATUS IN ('VALIDATION_FAILED','EXHAUSTED','RECORD_NOT_FOUND','CRM_REJECTED') " +
            "AND NVL(L.MANUAL_RETRY,'N')='N' THEN 1 ELSE 0 END) AS ACTION_NEEDED," +
            "TO_CHAR(MAX(L.SENT_DATE),'DD-MON-YY HH24:MI') AS LAST_SENT " +
            "FROM CRM_MPM_CRM_INTEGRATION_LOG L JOIN CRM_MPM_API_REGISTRY R ON R.REGISTRY_ID=L.REGISTRY_ID " +
            "GROUP BY R.SERVICE_NAME ORDER BY ACTION_NEEDED DESC,R.SERVICE_NAME");
    }

    public List<Map<String, Object>> mainReport(String svc, String status,
                                                  String from, String to, String recId) {
        return jdbc.queryForList(
            "SELECT L.LOG_ID,R.SERVICE_NAME,L.SOURCE_RECORD_ID,L.FINAL_STATUS," +
            "DBMS_LOB.SUBSTR(L.REQUEST_PAYLOAD,2000,1) AS DATA_SENT," +
            "SUBSTR(L.CALLBACK_VALID_ERRORS,1,300) AS FAILED_FIELDS," +
            "SUBSTR(L.CALLBACK_RESULT_DESC,1,200) AS CRM_RESPONSE," +
            "SUBSTR(L.ERROR_MESSAGE,1,200) AS ERROR_DETAIL," +
            "L.CRM_REFERENCE_NO,TO_CHAR(L.SENT_DATE,'DD-MON-YY HH24:MI') AS SENT_DATE," +
            "TO_CHAR(L.CALLBACK_DATE,'DD-MON-YY HH24:MI') AS CALLBACK_DATE," +
            "L.RETRY_COUNT||'/'||R.MAX_RETRY_COUNT AS RETRY,NVL(L.MANUAL_RETRY,'N') AS MANUAL_RETRY " +
            "FROM CRM_MPM_CRM_INTEGRATION_LOG L JOIN CRM_MPM_API_REGISTRY R ON R.REGISTRY_ID=L.REGISTRY_ID " +
            "WHERE (? IS NULL OR R.SERVICE_NAME=?) AND (? IS NULL OR L.FINAL_STATUS=?) " +
            "AND (? IS NULL OR L.SENT_DATE>=TO_DATE(?,'DD-MON-YY')) " +
            "AND (? IS NULL OR L.SENT_DATE<=TO_DATE(?,'DD-MON-YY')+1) " +
            "AND (? IS NULL OR L.SOURCE_RECORD_ID LIKE '%'||?||'%') " +
            "ORDER BY L.LOG_ID DESC FETCH FIRST 500 ROWS ONLY",
            n(svc),n(svc),n(status),n(status),n(from),n(from),n(to),n(to),n(recId),n(recId));
    }

    public List<Map<String, Object>> actionNeeded() {
        return jdbc.queryForList(
            "SELECT L.LOG_ID,R.SERVICE_NAME,L.SOURCE_RECORD_ID,L.FINAL_STATUS," +
            "DBMS_LOB.SUBSTR(L.REQUEST_PAYLOAD,2000,1) AS DATA_SENT," +
            "SUBSTR(L.CALLBACK_VALID_ERRORS,1,300) AS FAILED_FIELDS," +
            "SUBSTR(L.CALLBACK_RESULT_DESC,1,200) AS CRM_RESPONSE," +
            "SUBSTR(L.ERROR_MESSAGE,1,200) AS ERROR_DETAIL," +
            "TO_CHAR(L.SENT_DATE,'DD-MON-YY HH24:MI') AS SENT_DATE," +
            "TO_CHAR(L.CALLBACK_DATE,'DD-MON-YY HH24:MI') AS CALLBACK_DATE," +
            "L.RETRY_COUNT||'/'||R.MAX_RETRY_COUNT AS RETRY," +
            "CASE L.FINAL_STATUS WHEN 'VALIDATION_FAILED' THEN 'Fix data in MPM or ask CRM team' " +
            "WHEN 'EXHAUSTED' THEN 'Max retries - investigate' " +
            "WHEN 'RECORD_NOT_FOUND' THEN 'Push parent first' " +
            "WHEN 'CRM_REJECTED' THEN 'Contact CRM team' " +
            "WHEN 'DUPLICATE_RECORD' THEN 'Already in CRM - ignore' ELSE 'Review' END AS ACTION_NEEDED " +
            "FROM CRM_MPM_CRM_INTEGRATION_LOG L JOIN CRM_MPM_API_REGISTRY R ON R.REGISTRY_ID=L.REGISTRY_ID " +
            "WHERE L.FINAL_STATUS IN ('VALIDATION_FAILED','EXHAUSTED','RECORD_NOT_FOUND','CRM_REJECTED','DUPLICATE_RECORD') " +
            "AND NVL(L.MANUAL_RETRY,'N')='N' " +
            "ORDER BY CASE L.FINAL_STATUS WHEN 'EXHAUSTED' THEN 1 WHEN 'VALIDATION_FAILED' THEN 2 " +
            "WHEN 'RECORD_NOT_FOUND' THEN 3 WHEN 'CRM_REJECTED' THEN 4 ELSE 5 END, L.LOG_ID DESC");
    }

    public List<Map<String, Object>> retryQueue() {
        return jdbc.queryForList(
            "SELECT L.LOG_ID,R.SERVICE_NAME,L.SOURCE_RECORD_ID,L.FINAL_STATUS," +
            "DBMS_LOB.SUBSTR(L.REQUEST_PAYLOAD,2000,1) AS DATA_SENT," +
            "SUBSTR(L.ERROR_MESSAGE,1,200) AS ERROR_DETAIL," +
            "TO_CHAR(L.SENT_DATE,'DD-MON-YY HH24:MI') AS SENT_DATE," +
            "TO_CHAR(L.UPDATED_DATE,'DD-MON-YY HH24:MI') AS RETRY_QUEUED_AT," +
            "L.RETRY_COUNT||'/'||R.MAX_RETRY_COUNT AS RETRY_PROGRESS " +
            "FROM CRM_MPM_CRM_INTEGRATION_LOG L JOIN CRM_MPM_API_REGISTRY R ON R.REGISTRY_ID=L.REGISTRY_ID " +
            "WHERE L.MANUAL_RETRY='Y' AND L.FINAL_STATUS='FAILED' ORDER BY L.LOG_ID DESC");
    }

    public List<Map<String, Object>> errorTriage() {
        return jdbc.queryForList(
            "SELECT L.FINAL_STATUS,NVL(L.ERROR_CODE,'(none)') AS ERROR_CODE," +
            "NVL(E.ERROR_DESCRIPTION,'Unknown / Not in Error Master') AS ERROR_DESCRIPTION," +
            "NVL(E.IS_RETRYABLE,'N') AS IS_RETRYABLE,COUNT(*) AS RECORD_COUNT," +
            "TO_CHAR(MIN(L.CREATED_DATE),'DD-MON-YY HH24:MI') AS FIRST_OCCURRENCE," +
            "TO_CHAR(MAX(L.UPDATED_DATE),'DD-MON-YY HH24:MI') AS LAST_OCCURRENCE," +
            "COUNT(DISTINCT L.REGISTRY_ID) AS SERVICES_AFFECTED " +
            "FROM CRM_MPM_CRM_INTEGRATION_LOG L LEFT JOIN CRM_MPM_ERROR_CODE_MASTER E ON E.ERROR_CODE=L.ERROR_CODE " +
            "WHERE L.FINAL_STATUS NOT IN ('SUCCESS','ACK_OK','SENT','RESOLVED') " +
            "GROUP BY L.FINAL_STATUS,L.ERROR_CODE,E.ERROR_DESCRIPTION,E.IS_RETRYABLE " +
            "ORDER BY CASE L.FINAL_STATUS WHEN 'EXHAUSTED' THEN 1 WHEN 'VALIDATION_FAILED' THEN 1 " +
            "WHEN 'CRM_REJECTED' THEN 1 WHEN 'FAILED' THEN 2 ELSE 3 END,COUNT(*) DESC");
    }

    public List<Map<String, Object>> callbackAudit(String svc, String statusCode,
                                                     String from, String to) {
        return jdbc.queryForList(
            "SELECT TO_CHAR(A.AUDIT_ID) AS AUDIT_ID," +
            "TO_CHAR(A.RECEIVED_AT,'DD-MON-YY HH24:MI:SS') AS RECEIVED_AT," +
            "A.SERVICE_NAME,A.X_UNIQUE_ID,A.CHANNEL_ID,A.REQUEST_ID," +
            "A.STATUS_CODE_SENT,SUBSTR(A.DESCRIPTION_SENT,1,300) AS DESCRIPTION_SENT," +
            "SUBSTR(A.RAW_PAYLOAD,1,200) AS RAW_PAYLOAD " +
            "FROM CRM_MPM_CALLBACK_AUDIT_LOG A " +
            "WHERE (? IS NULL OR A.SERVICE_NAME=?) AND (? IS NULL OR A.STATUS_CODE_SENT=?) " +
            "AND (? IS NULL OR A.RECEIVED_AT>=TO_TIMESTAMP(?,'DD-MON-YY')) " +
            "AND (? IS NULL OR A.RECEIVED_AT<=TO_TIMESTAMP(?,'DD-MON-YY')+1) " +
            "ORDER BY A.AUDIT_ID DESC FETCH FIRST 500 ROWS ONLY",
            n(svc),n(svc),n(statusCode),n(statusCode),n(from),n(from),n(to),n(to));
    }

    public int manualRetry(String logId) {
        return jdbc.update(
            "UPDATE CRM_MPM_CRM_INTEGRATION_LOG SET MANUAL_RETRY='Y',FINAL_STATUS='FAILED'," +
            "IS_FINAL_ATTEMPT='N',RETRY_COUNT=0," +
            "ERROR_MESSAGE=SUBSTR(ERROR_MESSAGE,1,3800)||' Manual retry: '||TO_CHAR(SYSDATE,'DD-MON-YY HH24:MI')," +
            "UPDATED_DATE=SYSTIMESTAMP WHERE LOG_ID=TO_NUMBER(?) " +
            "AND FINAL_STATUS IN ('VALIDATION_FAILED','CRM_REJECTED','EXHAUSTED','RECORD_NOT_FOUND','FAILED')",
            logId);
    }

    public List<String> serviceNames() {
        return jdbc.queryForList(
            "SELECT SERVICE_NAME FROM CRM_MPM_API_REGISTRY WHERE IS_ACTIVE='Y' ORDER BY SERVICE_NAME",
            String.class);
    }

    public List<String> statusList() {
        return jdbc.queryForList(
            "SELECT DISTINCT FINAL_STATUS FROM CRM_MPM_CRM_INTEGRATION_LOG ORDER BY FINAL_STATUS",
            String.class);
    }

    // ── SCHEDULER ────────────────────────────────────────────────────────────
    public List<Map<String, Object>> listSchedulerJobs() {
        return jdbc.queryForList(
            "SELECT JOB_NAME,CASE WHEN ENABLED='TRUE' THEN 'Y' ELSE 'N' END AS ENABLED," +
            "STATE,NVL(REPEAT_INTERVAL,'--') AS REPEAT_INTERVAL," +
            "TO_CHAR(NEXT_RUN_DATE,'DD-MON-YY HH24:MI') AS NEXT_RUN," +
            "TO_CHAR(LAST_START_DATE,'DD-MON-YY HH24:MI') AS LAST_RUN," +
            "NVL(COMMENTS,'--') AS COMMENTS " +
            "FROM USER_SCHEDULER_JOBS ORDER BY JOB_NAME");
    }

    public void enableJob(String jobName) {
        jdbc.update("BEGIN DBMS_SCHEDULER.ENABLE(?); END;", jobName);
    }

    public void disableJob(String jobName) {
        jdbc.update("BEGIN DBMS_SCHEDULER.DISABLE(?); END;", jobName);
    }

    public void runJobNow(String jobName) {
        jdbc.update("BEGIN DBMS_SCHEDULER.RUN_JOB(?,FALSE); END;", jobName);
    }

    public void stopJob(String jobName) {
        jdbc.update("BEGIN DBMS_SCHEDULER.STOP_JOB(?,TRUE); END;", jobName);
    }

    public List<Map<String, Object>> jobHistory(String jobName) {
        return jdbc.queryForList(
            "SELECT TO_CHAR(LOG_ID),JOB_NAME,STATUS," +
            "TO_CHAR(LOG_DATE,'DD-MON-YY HH24:MI') AS RUN_TIME,OPERATION,USER_NAME " +
            "FROM USER_SCHEDULER_JOB_LOG WHERE JOB_NAME=? ORDER BY LOG_DATE DESC FETCH FIRST 20 ROWS ONLY",
            jobName);
    }

    // ── HEALTH CHECK ─────────────────────────────────────────────────────────
    public List<Map<String, Object>> listHealthUrls() {
        try {
            return jdbc.queryForList(
                "SELECT NAME, URL, NVL(LAST_STATUS,'--') AS LAST_STATUS, " +
                "TO_CHAR(LAST_TESTED,'DD-MON-YY HH24:MI') AS LAST_TESTED " +
                "FROM CRM_MPM_HEALTH_URLS ORDER BY NAME");
        } catch (Exception e) {
            // Table may not exist — return empty
            return Collections.emptyList();
        }
    }

    public Map<String, Object> testUrl(String url, String name) {
        Map<String, Object> result = new LinkedHashMap<>();
        long start = System.currentTimeMillis();
        try {
            HttpURLConnection conn = (HttpURLConnection) new URL(url).openConnection();
            conn.setRequestMethod("GET");
            conn.setConnectTimeout(10000);
            conn.setReadTimeout(10000);
            int code = conn.getResponseCode();
            long elapsed = System.currentTimeMillis() - start;
            result.put("statusCode", code);
            result.put("elapsedMs", elapsed);
            result.put("ok", code >= 200 && code < 300);
            result.put("name", name);
            result.put("url", url);
        } catch (Exception ex) {
            result.put("statusCode", 0);
            result.put("ok", false);
            result.put("error", ex.getMessage());
            result.put("name", name);
            result.put("url", url);
        }
        return result;
    }

    public Map<String, Object> testToken(String credCode) {
        Map<String, Object> result = new LinkedHashMap<>();
        try {
            jdbc.update("BEGIN PKG_CRM_INTEGRATION.GET_BEARER_TOKEN(?); END;", credCode);
            result.put("result", "Token test triggered - check integration log for result");
            result.put("ok", true);
        } catch (Exception ex) {
            result.put("result", "ERROR: " + ex.getMessage());
            result.put("ok", false);
        }
        return result;
    }

    // ── PING ─────────────────────────────────────────────────────────────────
    public Map<String, Object> ping() {
        Map<String, Object> r = new LinkedHashMap<>();
        try {
            String dbTime = jdbc.queryForObject("SELECT TO_CHAR(SYSDATE,'DD-MON-YY HH24:MI:SS') FROM DUAL", String.class);
            r.put("ok", true);
            r.put("dbTime", dbTime);
            r.put("message", "Connected to Oracle DB");
        } catch (Exception ex) {
            r.put("ok", false);
            r.put("message", "DB connection failed: " + ex.getMessage());
        }
        return r;
    }

    // ── HELPER ───────────────────────────────────────────────────────────────
    private String n(String s) {
        return (s == null || s.trim().isEmpty()) ? null : s.trim();
    }
}
