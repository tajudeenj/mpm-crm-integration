package com.adib.crm.admin.controller;

import com.adib.crm.admin.service.ScriptService;
import com.adib.crm.admin.service.TestPushService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@RestController
@CrossOrigin
public class TestPushController {

    @Autowired private TestPushService pushSvc;
    @Autowired private ScriptService   scriptSvc;

    // ── TEST PUSH ─────────────────────────────────────────────────────────────
    @PostMapping("/api/testpush/push")
    public ResponseEntity<?> push(@RequestBody Map<String, String> body) {
        return ok(pushSvc.push(body.get("serviceName"), body.get("keyValue")));
    }

    // ── SCRIPT DOWNLOAD ───────────────────────────────────────────────────────
    @GetMapping("/api/scripts/generate")
    public ResponseEntity<?> generate(@RequestParam String section) {
        return ok(Map.of("script", scriptSvc.generate(section)));
    }

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
