package com.adib.crm.admin.service;

import com.adib.crm.admin.config.QueryStore;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import javax.sql.DataSource;
import java.net.HttpURLConnection;
import java.net.URL;
import java.sql.CallableStatement;
import java.sql.Connection;
import java.sql.Types;
import java.util.*;

/**
 * All SQL lives in src/main/resources/queries.properties (see QueryStore).
 * This class only binds parameters and assembles optional filter clauses.
 */
@Service
public class CrmAdminService {

    @Autowired private JdbcTemplate jdbc;
    @Autowired private DataSource   dataSource;
    @Autowired private QueryStore   q;

    // ── CREDENTIALS ─────────────────────────────────────────────────────────
    public List<Map<String, Object>> listCredentials() {
        return jdbc.queryForList(q.get("query.cred.list"));
    }

    public Map<String, Object> loadCredential(String credCode) {
        return jdbc.queryForMap(q.get("query.cred.load.single"), credCode);
    }

    public void saveCredential(Map<String, String> b) {
        jdbc.update(q.get("query.cred.save"),
            b.get("clientSecret"),
            b.get("credCode"), b.get("tokenUrl"), b.get("clientId"),
            n(b.get("scope")), n(b.get("grantType")), n(b.get("walletPath")), n(b.get("walletPwd")),
            b.get("isActive"),
            b.get("credCode"), b.get("tokenUrl"), b.get("clientId"),
            n(b.get("scope")), n(b.get("grantType")), n(b.get("walletPath")), n(b.get("walletPwd")),
            b.get("isActive"));
    }

    public void rotateSecret(String credCode, String newSecret) {
        jdbc.update(q.get("query.cred.rotate.secret"), newSecret, credCode);
    }

    public void rotateWallet(String credCode, String newWalletPwd) {
        jdbc.update(q.get("query.cred.rotate.wallet"), newWalletPwd, credCode);
    }

    public Map<String, Object> testDecrypt(String credCode, String type) {
        Map<String, Object> result = new LinkedHashMap<>();
        String key = "WALLET".equals(type) ? "query.cred.test.wallet" : "query.cred.test.secret";
        try (Connection con = dataSource.getConnection();
             CallableStatement cs = con.prepareCall(q.get(key))) {
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
        return jdbc.queryForList(q.get("query.cred.codes"), String.class);
    }

    // ── SERVICE REGISTRY ────────────────────────────────────────────────────
    public List<Map<String, Object>> listRegistry() {
        return jdbc.queryForList(q.get("query.registry.list"));
    }

    public void saveRegistry(Map<String, String> b) {
        List<Object> p = new ArrayList<>();
        p.add(b.get("serviceName"));          // MERGE source
        p.addAll(registryFields(b, false));   // UPDATE SET (26)
        p.addAll(registryFields(b, true));    // INSERT VALUES (27)
        jdbc.update(q.get("query.registry.save"), p.toArray());
    }

    private List<Object> registryFields(Map<String, String> b, boolean withName) {
        List<Object> f = new ArrayList<>();
        if (withName) f.add(b.get("serviceName"));
        f.add(b.get("entityName"));   f.add(b.get("operationType")); f.add(b.get("sourceType"));
        f.add(n(b.get("sourceView"))); f.add(n(b.get("sourceProc")));
        f.add(n(b.get("sourceFilterCol"))); f.add(n(b.get("sourceKeyCol")));
        f.add(n(b.get("sourceExtraFilter")));
        f.add(n(b.get("jsonMappingName"))); f.add(n(b.get("recordTypeHdr"))); f.add(n(b.get("eventCodeHdr")));
        f.add(n(b.get("apicEndpointUrl"))); f.add(n(b.get("httpMethod"))); f.add(n(b.get("apicApiVersion")));
        f.add(n(b.get("callbackTargetTable"))); f.add(n(b.get("callbackKeyCol")));
        f.add(n(b.get("callbackStatusCol"))); f.add(n(b.get("callbackRefCol")));
        f.add(n(b.get("postCallbackProc"))); f.add(n(b.get("credCode")));
        f.add(b.get("executionOrder")); f.add(b.get("batchSize")); f.add(b.get("maxRetryCount"));
        f.add(b.get("retryIntervalMinutes")); f.add(b.get("timeoutMinutes")); f.add(b.get("isActive"));
        return f;
    }

    public void setRegistryActive(String serviceName, String isActive) {
        jdbc.update(q.get("query.registry.toggle"), isActive, serviceName);
    }

    // ── FIELD MAPPINGS ───────────────────────────────────────────────────────
    public List<String> mappingNames() {
        return jdbc.queryForList(q.get("query.mapping.names"), String.class);
    }

    public List<Map<String, Object>> listMappings(String mappingName) {
        if (isBlank(mappingName)) return jdbc.queryForList(q.get("query.mapping.list.all"));
        return jdbc.queryForList(q.get("query.mapping.list.byname"), mappingName);
    }

    public void saveMapping(Map<String, String> b) {
        jdbc.update(q.get("query.mapping.save"),
            b.get("jsonMappingName"), b.get("sourceColumn"),
            b.get("displayOrder"), b.get("jsonPath"), b.get("dataType"),
            n(b.get("dateFormat")), b.get("isMandatory"), b.get("isActive"),
            b.get("jsonMappingName"), b.get("displayOrder"), b.get("sourceColumn"),
            b.get("jsonPath"), b.get("dataType"), n(b.get("dateFormat")),
            b.get("isMandatory"), b.get("isActive"));
    }

    public void setMappingActive(String mappingId, String isActive) {
        jdbc.update(q.get("query.mapping.toggle"), isActive, mappingId);
    }

    // ── WATERMARK ────────────────────────────────────────────────────────────
    public List<Map<String, Object>> listWatermarks() {
        return jdbc.queryForList(q.get("query.watermark.list"));
    }

    public void resetWatermark(String serviceName) {
        jdbc.update(q.get("query.watermark.reset"), serviceName);
    }

    public void setWatermarkDate(String serviceName, String date) {
        jdbc.update(q.get("query.watermark.setdate"), date, serviceName);
    }

    // ── ERROR CODES ──────────────────────────────────────────────────────────
    public List<Map<String, Object>> listErrorCodes() {
        return jdbc.queryForList(q.get("query.errorcode.list"));
    }

    public void saveErrorCode(Map<String, String> b) {
        jdbc.update(q.get("query.errorcode.save"),
            b.get("errorCode"), b.get("errorCategory"), b.get("errorDescription"), b.get("isRetryable"),
            b.get("errorCode"), b.get("errorCategory"), b.get("errorDescription"), b.get("isRetryable"));
    }

    // ── MONITOR ──────────────────────────────────────────────────────────────
    public List<Map<String, Object>> dashboard() {
        return jdbc.queryForList(q.get("query.monitor.dashboard"));
    }

    public List<Map<String, Object>> mainReport(String svc, String status,
                                                  String from, String to, String recId) {
        return new Filtered("query.monitor.records")
            .add("service", svc).add("status", status)
            .add("from", from).add("to", to).add("recid", recId)
            .run();
    }

    public List<Map<String, Object>> actionNeeded() {
        return jdbc.queryForList(q.get("query.monitor.action"));
    }

    public List<Map<String, Object>> retryQueue() {
        return jdbc.queryForList(q.get("query.monitor.retryqueue"));
    }

    public List<Map<String, Object>> errorTriage() {
        return jdbc.queryForList(q.get("query.monitor.triage"));
    }

    public List<Map<String, Object>> parentPending() {
        return jdbc.queryForList(q.get("query.monitor.parentpending"));
    }

    public List<Map<String, Object>> callbackAudit(String svc, String statusCode,
                                                     String from, String to) {
        return new Filtered("query.monitor.callback")
            .add("service", svc).add("status", statusCode)
            .add("from", from).add("to", to)
            .run();
    }

    public int manualRetry(String logId) {
        return jdbc.update(q.get("query.monitor.manualretry"), logId);
    }

    public List<String> serviceNames() {
        return jdbc.queryForList(q.get("query.monitor.servicenames"), String.class);
    }

    public List<String> statusList() {
        return jdbc.queryForList(q.get("query.monitor.statuses"), String.class);
    }

    // ── ERROR LOG ────────────────────────────────────────────────────────────
    public List<Map<String, Object>> errorLog(String svc, String status, String errorCode,
                                               String from, String to, String recId, String text) {
        return new Filtered("query.errorlog")
            .add("service", svc).add("status", status).add("errorcode", errorCode)
            .add("from", from).add("to", to).add("recid", recId).add("text", text)
            .run();
    }

    public Map<String, Object> errorLogDetail(String logId) {
        return jdbc.queryForMap(q.get("query.errorlog.detail"), logId);
    }

    public List<String> errorLogCodes() {
        return jdbc.queryForList(q.get("query.errorlog.codes"), String.class);
    }

    public List<Map<String, Object>> jobRunErrors() {
        return jdbc.queryForList(q.get("query.errorlog.jobruns"));
    }

    // ── CHAIN STATUS (Property → Building → Floor → Unit) ────────────────────
    public List<Map<String, Object>> chainSummary(String propertyCode, String state) {
        String base = q.get("query.chain.cte") + " " + q.get("query.chain.summary");
        return new Filtered(base, "query.chain.summary")
            .add("prop", propertyCode).add("state", state)
            .run();
    }

    public List<Map<String, Object>> chainDetail(String propertyCode) {
        return jdbc.queryForList(q.get("query.chain.cte") + " " + q.get("query.chain.detail"),
                                 propertyCode);
    }

    // ── SCHEDULER ────────────────────────────────────────────────────────────
    public List<Map<String, Object>> listSchedulerJobs() {
        return jdbc.queryForList(q.get("query.scheduler.list"));
    }

    public void enableJob(String jobName)  { jdbc.update(q.get("query.scheduler.enable"),  jobName); }
    public void disableJob(String jobName) { jdbc.update(q.get("query.scheduler.disable"), jobName); }
    public void runJobNow(String jobName)  { jdbc.update(q.get("query.scheduler.runnow"),  jobName); }
    public void stopJob(String jobName)    { jdbc.update(q.get("query.scheduler.stop"),    jobName); }

    public Map<String, Object> createJob(Map<String, String> b) {
        Map<String, Object> result = new LinkedHashMap<>();
        String jobName  = b.get("jobName");
        String interval = b.getOrDefault("interval", "FREQ=DAILY;BYHOUR=6;BYMINUTE=0;BYSECOND=0");
        String proc     = b.getOrDefault("proc", "PKG_CRM_INTEGRATION.RUN_OUTBOUND_JOB");
        String enabled  = "Y".equals(b.getOrDefault("enabled", "N")) ? "Y" : "N";
        String comment  = b.getOrDefault("comment", "Created via CRM Admin Web");
        String action   = "BEGIN " + proc + "; END;";
        try {
            jdbc.update(q.get("query.scheduler.create"), jobName, action, interval, enabled, comment);
            result.put("ok", true);
            result.put("result", "Job created: " + jobName + ("Y".equals(enabled) ? " (enabled)" : " (disabled)"));
        } catch (Exception ex) {
            result.put("ok", false);
            result.put("result", "ERROR: " + ex.getMessage());
        }
        return result;
    }

    public List<Map<String, Object>> jobHistory(String jobName) {
        return jdbc.queryForList(q.get("query.scheduler.history"), jobName);
    }

    // ── HEALTH CHECK ─────────────────────────────────────────────────────────
    public List<Map<String, Object>> listHealthUrls() {
        try {
            return jdbc.queryForList(q.get("query.health.urls"));
        } catch (Exception e) {
            return Collections.emptyList();   // table may not exist
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
            result.put("statusCode", code);
            result.put("elapsedMs", System.currentTimeMillis() - start);
            result.put("ok", code >= 200 && code < 300);
        } catch (Exception ex) {
            result.put("statusCode", 0);
            result.put("ok", false);
            result.put("error", ex.getMessage());
        }
        result.put("name", name);
        result.put("url", url);
        return result;
    }

    public Map<String, Object> testToken(String credCode) {
        Map<String, Object> result = new LinkedHashMap<>();
        try {
            jdbc.update(q.get("query.health.token"), credCode);
            result.put("result", "Token test triggered - check integration log for result");
            result.put("ok", true);
        } catch (Exception ex) {
            result.put("result", "ERROR: " + ex.getMessage());
            result.put("ok", false);
        }
        return result;
    }

    // ── TEST PUSH ─────────────────────────────────────────────────────────────
    public Map<String, Object> testPush() {
        Map<String, Object> result = new LinkedHashMap<>();
        try {
            jdbc.update(q.get("query.health.testpush"));
            result.put("ok", true);
            result.put("result", "RUN_OUTBOUND_JOB triggered — check Monitor tab for new records");
        } catch (Exception ex) {
            result.put("ok", false);
            result.put("result", "ERROR: " + ex.getMessage());
        }
        return result;
    }

    // ── PING ─────────────────────────────────────────────────────────────────
    public Map<String, Object> ping() {
        Map<String, Object> r = new LinkedHashMap<>();
        try {
            r.put("ok", true);
            r.put("dbTime", jdbc.queryForObject(q.get("query.ping"), String.class));
            r.put("message", "Connected to Oracle DB");
        } catch (Exception ex) {
            r.put("ok", false);
            r.put("message", "DB connection failed: " + ex.getMessage());
        }
        return r;
    }

    // ── HELPERS ──────────────────────────────────────────────────────────────
    /**
     * Builds  <prefix>.base  +  <prefix>.filter.<name> (only for non-blank values)  +  <prefix>.order
     * Filters are appended as text only when set — never NULL-bound (ORA-17004 safe).
     */
    private class Filtered {
        private final StringBuilder sql;
        private final String prefix;
        private final List<Object> params = new ArrayList<>();

        Filtered(String prefix) { this(q.get(prefix + ".base"), prefix); }

        Filtered(String baseSql, String prefix) {
            this.sql = new StringBuilder(baseSql);
            this.prefix = prefix;
        }

        Filtered add(String filter, String value) {
            if (!isBlank(value)) {
                sql.append(' ').append(q.get(prefix + ".filter." + filter));
                params.add(value.trim());
            }
            return this;
        }

        List<Map<String, Object>> run() {
            sql.append(' ').append(q.get(prefix + ".order"));
            return jdbc.queryForList(sql.toString(), params.toArray());
        }
    }

    private static boolean isBlank(String s) { return s == null || s.trim().isEmpty(); }

    private String n(String s) { return isBlank(s) ? null : s.trim(); }
}
