package com.adib.crm.admin.service;

import com.adib.crm.admin.config.QueryStore;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import javax.sql.DataSource;
import java.sql.*;
import java.util.*;

@Service
public class TestPushService {

    @Autowired private JdbcTemplate jdbc;
    @Autowired private DataSource   dataSource;
    @Autowired private QueryStore   q;

    public Map<String, Object> push(String serviceName, String keyValue) {
        Map<String, Object> result = new LinkedHashMap<>();

        // Step 1 — get registry ID
        Long registryId;
        try {
            registryId = jdbc.queryForObject(
                q.get("query.testpush.registryid"),
                Long.class, serviceName);
        } catch (Exception e) {
            throw new RuntimeException("Service not found: " + serviceName);
        }

        if (registryId == null) {
            throw new RuntimeException("Service not found: " + serviceName);
        }

        // Step 2 — delete any existing test log entry for this key
        jdbc.update(
            q.get("query.testpush.cleanup"),
            registryId, keyValue);

        // Step 3 — call SEND_TO_APIC
        try (Connection con = dataSource.getConnection();
             CallableStatement cs = con.prepareCall(q.get("query.testpush.send"))) {

            cs.setLong(1, registryId);
            cs.setString(2, keyValue);
            cs.registerOutParameter(3, Types.NUMERIC);
            cs.execute();
            con.commit();

            long logId = cs.getLong(3);
            result.put("logId", logId);
            result.put("registryId", registryId);
            result.put("serviceName", serviceName);
            result.put("keyValue", keyValue);
            result.put("ok", logId > 0);

        } catch (Exception ex) {
            throw new RuntimeException("Push failed: " + ex.getMessage());
        }

        return result;
    }
}
