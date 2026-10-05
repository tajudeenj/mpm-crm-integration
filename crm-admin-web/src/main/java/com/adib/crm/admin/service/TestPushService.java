package com.adib.crm.admin.service;

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

    public Map<String, Object> push(String serviceName, String keyValue) {
        Map<String, Object> result = new LinkedHashMap<>();

        // Step 1 — get registry ID
        Long registryId;
        try {
            registryId = jdbc.queryForObject(
                "SELECT REGISTRY_ID FROM CRM_MPM_API_REGISTRY WHERE SERVICE_NAME = ?",
                Long.class, serviceName);
        } catch (Exception e) {
            throw new RuntimeException("Service not found: " + serviceName);
        }

        if (registryId == null) {
            throw new RuntimeException("Service not found: " + serviceName);
        }

        // Step 2 — delete any existing test log entry for this key
        jdbc.update(
            "DELETE FROM CRM_MPM_CRM_INTEGRATION_LOG " +
            "WHERE REGISTRY_ID = ? AND SOURCE_RECORD_ID = ? AND RETRY_COUNT = 0",
            registryId, keyValue);

        // Step 3 — call SEND_TO_APIC
        try (Connection con = dataSource.getConnection();
             CallableStatement cs = con.prepareCall(
                "BEGIN " +
                "    PKG_CRM_INTEGRATION.SEND_TO_APIC(" +
                "        p_registry_id          => ?," +
                "        p_key_value            => ?," +
                "        p_transaction_group_id => NULL," +
                "        p_attempt_no           => 1," +
                "        p_log_id_out           => ?);" +
                "END;")) {

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
