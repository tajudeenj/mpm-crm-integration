package com.adib.crm.admin.config;

import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.Reader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Properties;

/**
 * Central SQL store — same model as the standalone Swing tool (crm-admin.properties).
 *
 * Load order (later wins):
 *   1. classpath:queries.properties        (packaged inside the JAR — defaults)
 *   2. ./queries.properties                (next to the JAR — optional override,
 *                                           same convention as application.properties)
 *   3. -Dcrm.queries.file=/path/x.properties (explicit override)
 *
 * A query can therefore be hot-fixed on SIT/PROD by dropping a properties file
 * next to the JAR and restarting — no recompile.
 */
@Component
public class QueryStore {

    private static final Logger log = LoggerFactory.getLogger(QueryStore.class);
    private final Properties props = new Properties();

    @PostConstruct
    public void load() {
        try (InputStream in = getClass().getClassLoader().getResourceAsStream("queries.properties")) {
            if (in == null) throw new IllegalStateException("queries.properties not found on classpath");
            try (Reader r = new InputStreamReader(in, StandardCharsets.UTF_8)) {
                props.load(r);
            }
        } catch (Exception e) {
            throw new IllegalStateException("Failed to load queries.properties: " + e.getMessage(), e);
        }
        int base = props.size();

        overlay(Paths.get("queries.properties"));
        String explicit = System.getProperty("crm.queries.file");
        if (explicit != null && !explicit.isBlank()) overlay(Paths.get(explicit));

        log.info("QueryStore loaded {} queries ({} from classpath)", props.size(), base);
    }

    private void overlay(Path p) {
        if (!Files.isRegularFile(p)) return;
        try (Reader r = Files.newBufferedReader(p, StandardCharsets.UTF_8)) {
            Properties ext = new Properties();
            ext.load(r);
            props.putAll(ext);
            log.info("QueryStore override applied: {} ({} keys)", p.toAbsolutePath(), ext.size());
        } catch (Exception e) {
            log.warn("QueryStore override ignored ({}): {}", p, e.getMessage());
        }
    }

    /** Returns the SQL for a key; fails loudly so a missing key is obvious in the UI status bar. */
    public String get(String key) {
        String sql = props.getProperty(key);
        if (sql == null || sql.isBlank()) {
            throw new IllegalStateException("Missing query key in queries.properties: " + key);
        }
        return sql.trim();
    }
}
