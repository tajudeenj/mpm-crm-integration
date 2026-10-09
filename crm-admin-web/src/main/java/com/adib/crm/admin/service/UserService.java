package com.adib.crm.admin.service;

import com.adib.crm.admin.config.QueryStore;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.DisabledException;
import org.springframework.security.core.userdetails.*;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import java.util.*;

@Service
public class UserService implements UserDetailsService {

    @Autowired
    private JdbcTemplate jdbc;

    @Autowired
    private PasswordEncoder encoder;

    @Autowired
    private QueryStore q;

    // ── Spring Security — loads user for login ────────────────────────────────
    @Override
    public UserDetails loadUserByUsername(String username) throws UsernameNotFoundException {
        try {
            return jdbc.queryForObject(
                q.get("query.user.login"),
                (rs, i) -> {
                    String uname    = rs.getString("USERNAME");
                    String pwdHash  = rs.getString("PASSWORD_HASH");
                    String role     = rs.getString("ROLE");
                    String isActive = rs.getString("IS_ACTIVE");

                    if (!"Y".equals(isActive)) {
                        throw new DisabledException("Account is inactive: " + uname);
                    }

                    return User.withUsername(uname)
                        .password(pwdHash)
                        .roles(role)
                        .build();
                },
                username.toLowerCase());
        } catch (org.springframework.dao.EmptyResultDataAccessException e) {
            throw new UsernameNotFoundException("User not found: " + username);
        }
    }

    // ── Get current user info ─────────────────────────────────────────────────
    public Map<String, Object> getUser(String username) {
        try {
            return jdbc.queryForMap(
                q.get("query.user.get"),
                username.toLowerCase());
        } catch (Exception e) {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("username", username);
            m.put("role", "VIEWER");
            return m;
        }
    }

    // ── List all users ────────────────────────────────────────────────────────
    public List<Map<String, Object>> listUsers() {
        return jdbc.queryForList(
            q.get("query.user.list"));
    }

    // ── Save (create or update) user ──────────────────────────────────────────
    public void saveUser(Map<String, String> b) {
        String username  = b.get("username").toLowerCase().trim();
        String fullName  = b.getOrDefault("fullName", "").trim();
        String password  = b.getOrDefault("password", "").trim();
        String role      = b.getOrDefault("role", "VIEWER");
        String isActive  = b.getOrDefault("isActive", "Y");
        String services  = b.getOrDefault("services", "").trim();
        String svcVal    = services.isEmpty() ? null : services;

        // Check if user exists
        Integer count = jdbc.queryForObject(
            q.get("query.user.exists"),
            Integer.class, username);

        if (count != null && count > 0) {
            // Update existing — only update password if provided
            if (!password.isEmpty()) {
                jdbc.update(
                    q.get("query.user.update.withpwd"),
                    fullName, role, isActive, svcVal, encoder.encode(password), username);
            } else {
                jdbc.update(
                    q.get("query.user.update.nopwd"),
                    fullName, role, isActive, svcVal, username);
            }
        } else {
            // Insert new user — password required
            if (password.isEmpty()) {
                throw new RuntimeException("Password is required for new user");
            }
            jdbc.update(
                q.get("query.user.insert"),
                username, fullName, encoder.encode(password), role, isActive, svcVal);
        }
    }

    // ── Toggle active / inactive ──────────────────────────────────────────────
    public void toggleUser(String username, String isActive) {
        jdbc.update(
            q.get("query.user.toggle"),
            isActive, username.toLowerCase());
    }

    // ── Reset password ────────────────────────────────────────────────────────
    public void resetPassword(String username, String newPassword) {
        if (newPassword == null || newPassword.trim().isEmpty()) {
            throw new RuntimeException("New password cannot be empty");
        }
        jdbc.update(
            q.get("query.user.resetpwd"),
            encoder.encode(newPassword.trim()), username.toLowerCase());
    }

    // ── Update last login timestamp ───────────────────────────────────────────
    public void updateLastLogin(String username) {
        try {
            jdbc.update(
                q.get("query.user.lastlogin"),
                username.toLowerCase());
        } catch (Exception ignored) {}
    }
}
