package com.adib.crm.admin.service;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
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

    // ── Spring Security — loads user for login ────────────────────────────────
    @Override
    public UserDetails loadUserByUsername(String username) throws UsernameNotFoundException {
        try {
            return jdbc.queryForObject(
                "SELECT USERNAME, PASSWORD_HASH, ROLE, IS_ACTIVE " +
                "FROM CRM_MPM_APP_USERS WHERE USERNAME = ?",
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
                "SELECT USERNAME, FULL_NAME, ROLE, IS_ACTIVE, " +
                "NVL(ALLOWED_SERVICES,'All') AS ALLOWED_SERVICES, " +
                "TO_CHAR(LAST_LOGIN,'DD-MON-YY HH24:MI') AS LAST_LOGIN, " +
                "TO_CHAR(CREATED_DATE,'DD-MON-YY') AS CREATED_DATE " +
                "FROM CRM_MPM_APP_USERS WHERE USERNAME = ?",
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
            "SELECT USERNAME, NVL(FULL_NAME,'') AS FULL_NAME, ROLE, IS_ACTIVE, " +
            "NVL(ALLOWED_SERVICES,'All') AS ALLOWED_SERVICES, " +
            "TO_CHAR(LAST_LOGIN,'DD-MON-YY HH24:MI') AS LAST_LOGIN, " +
            "TO_CHAR(CREATED_DATE,'DD-MON-YY') AS CREATED_DATE " +
            "FROM CRM_MPM_APP_USERS " +
            "ORDER BY ROLE, USERNAME");
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
            "SELECT COUNT(*) FROM CRM_MPM_APP_USERS WHERE USERNAME=?",
            Integer.class, username);

        if (count != null && count > 0) {
            // Update existing — only update password if provided
            if (!password.isEmpty()) {
                jdbc.update(
                    "UPDATE CRM_MPM_APP_USERS SET FULL_NAME=?, ROLE=?, IS_ACTIVE=?, " +
                    "ALLOWED_SERVICES=?, PASSWORD_HASH=?, UPDATED_DATE=SYSDATE WHERE USERNAME=?",
                    fullName, role, isActive, svcVal, encoder.encode(password), username);
            } else {
                jdbc.update(
                    "UPDATE CRM_MPM_APP_USERS SET FULL_NAME=?, ROLE=?, IS_ACTIVE=?, " +
                    "ALLOWED_SERVICES=?, UPDATED_DATE=SYSDATE WHERE USERNAME=?",
                    fullName, role, isActive, svcVal, username);
            }
        } else {
            // Insert new user — password required
            if (password.isEmpty()) {
                throw new RuntimeException("Password is required for new user");
            }
            jdbc.update(
                "INSERT INTO CRM_MPM_APP_USERS " +
                "(USERNAME, FULL_NAME, PASSWORD_HASH, ROLE, IS_ACTIVE, ALLOWED_SERVICES, CREATED_DATE, UPDATED_DATE) " +
                "VALUES (?, ?, ?, ?, ?, ?, SYSDATE, SYSDATE)",
                username, fullName, encoder.encode(password), role, isActive, svcVal);
        }
    }

    // ── Toggle active / inactive ──────────────────────────────────────────────
    public void toggleUser(String username, String isActive) {
        jdbc.update(
            "UPDATE CRM_MPM_APP_USERS SET IS_ACTIVE=?, UPDATED_DATE=SYSDATE WHERE USERNAME=?",
            isActive, username.toLowerCase());
    }

    // ── Reset password ────────────────────────────────────────────────────────
    public void resetPassword(String username, String newPassword) {
        if (newPassword == null || newPassword.trim().isEmpty()) {
            throw new RuntimeException("New password cannot be empty");
        }
        jdbc.update(
            "UPDATE CRM_MPM_APP_USERS SET PASSWORD_HASH=?, UPDATED_DATE=SYSDATE WHERE USERNAME=?",
            encoder.encode(newPassword.trim()), username.toLowerCase());
    }

    // ── Update last login timestamp ───────────────────────────────────────────
    public void updateLastLogin(String username) {
        try {
            jdbc.update(
                "UPDATE CRM_MPM_APP_USERS SET LAST_LOGIN=SYSDATE WHERE USERNAME=?",
                username.toLowerCase());
        } catch (Exception ignored) {}
    }
}
