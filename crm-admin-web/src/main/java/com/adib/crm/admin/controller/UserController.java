package com.adib.crm.admin.controller;

import com.adib.crm.admin.service.UserService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@RestController
@RequestMapping("/api/users")
@CrossOrigin
public class UserController {

    @Autowired
    private UserService userService;

    // Current logged-in user info
    @GetMapping("/me")
    public ResponseEntity<?> me(Authentication auth) {
        return ok(userService.getUser(auth.getName()));
    }

    // List all users — ADMIN only
    @GetMapping
    @PreAuthorize("hasRole('ADMIN')")
    public ResponseEntity<?> listUsers() {
        return ok(userService.listUsers());
    }

    // Save (create or update) user — ADMIN only
    @PostMapping
    @PreAuthorize("hasRole('ADMIN')")
    public ResponseEntity<?> saveUser(@RequestBody Map<String, String> body) {
        userService.saveUser(body);
        return ok("User saved: " + body.get("username"));
    }

    // Toggle active/inactive — ADMIN only
    @PostMapping("/{username}/toggle")
    @PreAuthorize("hasRole('ADMIN')")
    public ResponseEntity<?> toggleUser(@PathVariable String username,
                                         @RequestBody Map<String, String> body) {
        userService.toggleUser(username, body.get("isActive"));
        return ok("User " + username + " set to " + body.get("isActive"));
    }

    // Reset password — ADMIN only
    @PostMapping("/{username}/reset-password")
    @PreAuthorize("hasRole('ADMIN')")
    public ResponseEntity<?> resetPassword(@PathVariable String username,
                                            @RequestBody Map<String, String> body) {
        userService.resetPassword(username, body.get("newPassword"));
        return ok("Password reset for " + username);
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
