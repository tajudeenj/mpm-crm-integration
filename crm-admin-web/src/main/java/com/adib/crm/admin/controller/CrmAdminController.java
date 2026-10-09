package com.adib.crm.admin.controller;

import com.adib.crm.admin.service.CrmAdminService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@RestController
@RequestMapping("/api")
@CrossOrigin
public class CrmAdminController {

    @Autowired
    private CrmAdminService svc;

    // ── CREDENTIALS ─────────────────────────────────────────────────────────
    @GetMapping("/credentials")
    public ResponseEntity<?> listCredentials() {
        return ok(svc.listCredentials());
    }

    @GetMapping("/credentials/{credCode}")
    public ResponseEntity<?> loadCredential(@PathVariable String credCode) {
        return ok(svc.loadCredential(credCode));
    }

    @PostMapping("/credentials")
    public ResponseEntity<?> saveCredential(@RequestBody Map<String, String> body) {
        svc.saveCredential(body);
        return ok("Saved and encrypted: " + body.get("credCode"));
    }

    @PostMapping("/credentials/{credCode}/rotate-secret")
    public ResponseEntity<?> rotateSecret(@PathVariable String credCode,
                                           @RequestBody Map<String, String> body) {
        svc.rotateSecret(credCode, body.get("newSecret"));
        return ok("Secret rotated for " + credCode);
    }

    @PostMapping("/credentials/{credCode}/rotate-wallet")
    public ResponseEntity<?> rotateWallet(@PathVariable String credCode,
                                           @RequestBody Map<String, String> body) {
        svc.rotateWallet(credCode, body.get("newWalletPwd"));
        return ok("Wallet password updated for " + credCode);
    }

    @PostMapping("/credentials/{credCode}/test-secret")
    public ResponseEntity<?> testSecret(@PathVariable String credCode) {
        return ok(svc.testDecrypt(credCode, "SECRET"));
    }

    @PostMapping("/credentials/{credCode}/test-wallet")
    public ResponseEntity<?> testWallet(@PathVariable String credCode) {
        return ok(svc.testDecrypt(credCode, "WALLET"));
    }

    @GetMapping("/credentials/codes")
    public ResponseEntity<?> credCodes() {
        return ok(svc.credCodes());
    }

    // ── SERVICE REGISTRY ────────────────────────────────────────────────────
    @GetMapping("/registry")
    public ResponseEntity<?> listRegistry() {
        return ok(svc.listRegistry());
    }

    @PostMapping("/registry")
    public ResponseEntity<?> saveRegistry(@RequestBody Map<String, String> body) {
        svc.saveRegistry(body);
        return ok("Registry saved: " + body.get("serviceName"));
    }

    @PostMapping("/registry/{serviceName}/toggle")
    public ResponseEntity<?> toggleRegistry(@PathVariable String serviceName,
                                             @RequestBody Map<String, String> body) {
        svc.setRegistryActive(serviceName, body.get("isActive"));
        return ok("Updated: " + serviceName);
    }

    // ── FIELD MAPPINGS ───────────────────────────────────────────────────────
    @GetMapping("/mappings/names")
    public ResponseEntity<?> mappingNames() {
        return ok(svc.mappingNames());
    }

    @GetMapping("/mappings")
    public ResponseEntity<?> listMappings(@RequestParam(required = false) String mappingName) {
        return ok(svc.listMappings(mappingName));
    }

    @PostMapping("/mappings")
    public ResponseEntity<?> saveMapping(@RequestBody Map<String, String> body) {
        svc.saveMapping(body);
        return ok("Mapping saved");
    }

    @PostMapping("/mappings/{mappingId}/toggle")
    public ResponseEntity<?> toggleMapping(@PathVariable String mappingId,
                                            @RequestBody Map<String, String> body) {
        svc.setMappingActive(mappingId, body.get("isActive"));
        return ok("Updated mapping " + mappingId);
    }

    // ── WATERMARK ────────────────────────────────────────────────────────────
    @GetMapping("/watermarks")
    public ResponseEntity<?> listWatermarks() {
        return ok(svc.listWatermarks());
    }

    @PostMapping("/watermarks/{serviceName}/reset")
    public ResponseEntity<?> resetWatermark(@PathVariable String serviceName) {
        svc.resetWatermark(serviceName);
        return ok("Watermark reset for " + serviceName);
    }

    @PostMapping("/watermarks/{serviceName}/set-date")
    public ResponseEntity<?> setWatermarkDate(@PathVariable String serviceName,
                                               @RequestBody Map<String, String> body) {
        svc.setWatermarkDate(serviceName, body.get("date"));
        return ok("Watermark date set for " + serviceName);
    }

    // ── ERROR CODES ──────────────────────────────────────────────────────────
    @GetMapping("/error-codes")
    public ResponseEntity<?> listErrorCodes() {
        return ok(svc.listErrorCodes());
    }

    @PostMapping("/error-codes")
    public ResponseEntity<?> saveErrorCode(@RequestBody Map<String, String> body) {
        svc.saveErrorCode(body);
        return ok("Error code saved: " + body.get("errorCode"));
    }

    // ── MONITOR ──────────────────────────────────────────────────────────────
    @GetMapping("/monitor/dashboard")
    public ResponseEntity<?> dashboard() {
        return ok(svc.dashboard());
    }

    @GetMapping("/monitor/records")
    public ResponseEntity<?> mainReport(@RequestParam(required = false) String serviceName,
                                         @RequestParam(required = false) String status,
                                         @RequestParam(required = false) String fromDate,
                                         @RequestParam(required = false) String toDate,
                                         @RequestParam(required = false) String recordId) {
        return ok(svc.mainReport(serviceName, status, fromDate, toDate, recordId));
    }

    @GetMapping("/monitor/action-needed")
    public ResponseEntity<?> actionNeeded() {
        return ok(svc.actionNeeded());
    }

    @GetMapping("/monitor/retry-queue")
    public ResponseEntity<?> retryQueue() {
        return ok(svc.retryQueue());
    }

    @GetMapping("/monitor/error-triage")
    public ResponseEntity<?> errorTriage() {
        return ok(svc.errorTriage());
    }

    @GetMapping("/monitor/callback-audit")
    public ResponseEntity<?> callbackAudit(@RequestParam(required = false) String serviceName,
                                            @RequestParam(required = false) String statusCode,
                                            @RequestParam(required = false) String fromDate,
                                            @RequestParam(required = false) String toDate) {
        return ok(svc.callbackAudit(serviceName, statusCode, fromDate, toDate));
    }

    @PostMapping("/monitor/records/{logId}/manual-retry")
    public ResponseEntity<?> manualRetry(@PathVariable String logId) {
        int rows = svc.manualRetry(logId);
        return ok(rows > 0 ? "Queued for retry: LOG_ID=" + logId : "Record not eligible for retry");
    }

    @GetMapping("/monitor/parent-pending")
    public ResponseEntity<?> parentPending() {
        return ok(svc.parentPending());
    }

    // ── ERROR LOG ────────────────────────────────────────────────────────────
    @GetMapping("/errorlog")
    public ResponseEntity<?> errorLog(@RequestParam(required = false) String serviceName,
                                       @RequestParam(required = false) String status,
                                       @RequestParam(required = false) String errorCode,
                                       @RequestParam(required = false) String fromDate,
                                       @RequestParam(required = false) String toDate,
                                       @RequestParam(required = false) String recordId,
                                       @RequestParam(required = false) String text) {
        return ok(svc.errorLog(serviceName, status, errorCode, fromDate, toDate, recordId, text));
    }

    @GetMapping("/errorlog/codes")
    public ResponseEntity<?> errorLogCodes() {
        return ok(svc.errorLogCodes());
    }

    @GetMapping("/errorlog/job-runs")
    public ResponseEntity<?> jobRunErrors() {
        return ok(svc.jobRunErrors());
    }

    @GetMapping("/errorlog/{logId}")
    public ResponseEntity<?> errorLogDetail(@PathVariable String logId) {
        return ok(svc.errorLogDetail(logId));
    }

    // ── CHAIN STATUS ─────────────────────────────────────────────────────────
    @GetMapping("/chain")
    public ResponseEntity<?> chainSummary(@RequestParam(required = false) String propertyCode,
                                           @RequestParam(required = false) String state) {
        return ok(svc.chainSummary(propertyCode, state));
    }

    @GetMapping("/chain/{propertyCode}")
    public ResponseEntity<?> chainDetail(@PathVariable String propertyCode) {
        return ok(svc.chainDetail(propertyCode));
    }

    @GetMapping("/monitor/service-names")
    public ResponseEntity<?> serviceNames() {
        return ok(svc.serviceNames());
    }

    @GetMapping("/monitor/statuses")
    public ResponseEntity<?> statusList() {
        return ok(svc.statusList());
    }

    // ── SCHEDULER ────────────────────────────────────────────────────────────
    @GetMapping("/scheduler")
    public ResponseEntity<?> listJobs() {
        return ok(svc.listSchedulerJobs());
    }

    @PostMapping("/scheduler/{jobName}/enable")
    public ResponseEntity<?> enableJob(@PathVariable String jobName) {
        svc.enableJob(jobName);
        return ok("Enabled: " + jobName);
    }

    @PostMapping("/scheduler/{jobName}/disable")
    public ResponseEntity<?> disableJob(@PathVariable String jobName) {
        svc.disableJob(jobName);
        return ok("Disabled: " + jobName);
    }

    @PostMapping("/scheduler/{jobName}/run-now")
    public ResponseEntity<?> runNow(@PathVariable String jobName) {
        svc.runJobNow(jobName);
        return ok("Triggered: " + jobName);
    }

    @PostMapping("/scheduler/{jobName}/stop")
    public ResponseEntity<?> stopJob(@PathVariable String jobName) {
        svc.stopJob(jobName);
        return ok("Stopped: " + jobName);
    }

    @GetMapping("/scheduler/{jobName}/history")
    public ResponseEntity<?> jobHistory(@PathVariable String jobName) {
        return ok(svc.jobHistory(jobName));
    }

    @PostMapping("/scheduler/create")
    public ResponseEntity<?> createJob(@RequestBody Map<String, String> body) {
        return ok(svc.createJob(body));
    }

    // ── HEALTH CHECK ─────────────────────────────────────────────────────────
    @GetMapping("/health/urls")
    public ResponseEntity<?> listHealthUrls() {
        return ok(svc.listHealthUrls());
    }

    @PostMapping("/health/test")
    public ResponseEntity<?> testUrl(@RequestBody Map<String, String> body) {
        return ok(svc.testUrl(body.get("url"), body.get("name")));
    }

    @PostMapping("/health/test-token")
    public ResponseEntity<?> testToken(@RequestBody Map<String, String> body) {
        return ok(svc.testToken(body.get("credCode")));
    }

    @PostMapping("/health/test-push")
    public ResponseEntity<?> testPush() {
        return ok(svc.testPush());
    }

    // ── DB CONNECTIVITY CHECK ─────────────────────────────────────────────────
    @GetMapping("/ping")
    public ResponseEntity<?> ping() {
        return ok(svc.ping());
    }

    // ── HELPER ───────────────────────────────────────────────────────────────
    private ResponseEntity<Map<String, Object>> ok(Object data) {
        Map<String, Object> r = new LinkedHashMap<>();
        r.put("success", true);
        r.put("data", data);
        return ResponseEntity.ok(r);
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<Map<String, Object>> handleError(Exception ex) {
        Map<String, Object> r = new LinkedHashMap<>();
        r.put("success", false);
        r.put("error", ex.getMessage());
        return ResponseEntity.status(500).body(r);
    }
}
