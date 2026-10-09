create or replace PACKAGE BODY PKG_CRM_INTEGRATION AS
/*

    Name: Tajudeen Jalaudin
    Date: 12-July-2026
/*

    /* ====================================================================
       UTILITIES
       ==================================================================== */
    FUNCTION NEW_GUID RETURN VARCHAR2 IS
    BEGIN
        RETURN RAWTOHEX(SYS_GUID());
    END NEW_GUID;


    /* ====================================================================
       GENERATE_UNIQUE_ID
       Builds x-unique-id for the APIC header: <channel_id><timestamp><seq>
       Format driven entirely by CRM_MPM_UNIQUE_ID_CONFIG (single row) so
       the standard can change later without touching this package.
       Sequence portion comes from CRM_MPM_UNIQUE_ID_SEQ (DB sequence,
       CYCLE'd automatically — no manual reset needed, concurrency-safe
       across multiple sessions since Oracle sequences are atomic).
       Mirrors Java's UniqueIdGenerator exactly — same channel/format/width
       by default (817 / YYYYMMDDHH24MISSFF3 / 4 digits).
       ==================================================================== */
    FUNCTION GENERATE_UNIQUE_ID RETURN VARCHAR2 IS
        v_channel_id       VARCHAR2(10);
        v_timestamp_format VARCHAR2(50);
        v_sequence_digits  NUMBER;
        v_timestamp        VARCHAR2(50);
        v_seq              NUMBER;
        v_seq_padded       VARCHAR2(20);
    BEGIN
        SELECT CHANNEL_ID, TIMESTAMP_FORMAT, SEQUENCE_DIGITS
        INTO   v_channel_id, v_timestamp_format, v_sequence_digits
        FROM   CRM_MPM_UNIQUE_ID_CONFIG
        WHERE  CONFIG_ID = 1
          AND  IS_ACTIVE = 'Y';

        v_timestamp := TO_CHAR(SYSTIMESTAMP, v_timestamp_format);

        SELECT CRM_MPM_UNIQUE_ID_SEQ.NEXTVAL INTO v_seq FROM DUAL;

        v_seq_padded := LPAD(TO_CHAR(v_seq), v_sequence_digits, '0');

        RETURN v_channel_id || v_timestamp || v_seq_padded;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            -- Config missing or inactive — fall back to a safe default
            -- so SEND_TO_APIC never fails purely because of this header.
            RETURN '817' || TO_CHAR(SYSTIMESTAMP, 'YYYYMMDDHH24MISSFF3') ||
                   LPAD(TO_CHAR(CRM_MPM_UNIQUE_ID_SEQ.NEXTVAL), 4, '0');
        WHEN OTHERS THEN
            -- Never let unique-id generation fail the whole send — log and
            -- fall back to a timestamp-only id so the request still goes out.
            RETURN '817' || TO_CHAR(SYSTIMESTAMP, 'YYYYMMDDHH24MISSFF3');
    END GENERATE_UNIQUE_ID;


    /* ====================================================================
       TOKEN MANAGEMENT 
       ==================================================================== */
    FUNCTION GET_BEARER_TOKEN(p_cred_code IN VARCHAR2) RETURN VARCHAR2 IS
        v_cred            CRM_MPM_API_CREDENTIALS%ROWTYPE;
        v_client_secret   VARCHAR2(500);
        v_request_body    VARCHAR2(4000);
        v_http_req        UTL_HTTP.REQ;
        v_http_resp       UTL_HTTP.RESP;
        v_response        CLOB := EMPTY_CLOB();
        v_buffer          VARCHAR2(32767);
        v_token           VARCHAR2(4000);
        v_expires_in      NUMBER;
        -- FIX: capture SQLERRM into a variable before use in RAISE_APPLICATION_ERROR
        v_err_msg         VARCHAR2(4000);
    BEGIN
        SELECT * INTO v_cred
        FROM CRM_MPM_API_CREDENTIALS
        WHERE CRED_CODE = p_cred_code
          AND IS_ACTIVE = 'Y';

        IF v_cred.TOKEN_CACHE_VALUE IS NOT NULL
           AND v_cred.TOKEN_EXPIRY IS NOT NULL
           AND v_cred.TOKEN_EXPIRY > SYSTIMESTAMP + (60/86400)
        THEN
            RETURN v_cred.TOKEN_CACHE_VALUE;
        END IF;

        -- reads plain secret (encryption handled separately)
        v_client_secret := v_cred.CLIENT_SECRET_REF;  -- reads from CRM_MPM_API_CREDENTIALS table


        -- Encryption fallback: try BLOB decrypt, fall back to plain text
        DECLARE
            v_enc_key RAW(32);
        BEGIN
            SELECT ENCRYPT_KEY INTO v_enc_key
            FROM CRM_MPM_ENCRYPT_CONFIG
            WHERE IS_ACTIVE = 'Y' AND ROWNUM = 1;

            v_client_secret := UTL_RAW.CAST_TO_VARCHAR2(
                DBMS_CRYPTO.DECRYPT(
                    src => v_cred.CLIENT_SECRET_ENCRYPTED,
                    typ => DBMS_CRYPTO.ENCRYPT_AES256 +
                           DBMS_CRYPTO.CHAIN_CBC +
                           DBMS_CRYPTO.PAD_PKCS5,
                    key => v_enc_key
                )
            );
        EXCEPTION
            WHEN OTHERS THEN
                -- Fallback to plain text if encrypted not available
                v_client_secret := v_cred.CLIENT_SECRET_REF;
        END;


    /*
        v_request_body :=
            'grant_type=' || v_cred.GRANT_TYPE ||
            '=' || UTL_URL.ESCAPE(v_cred.CLIENT_ID, TRUE) ||
            '=' || UTL_URL.ESCAPE(v_client_secret, TRUE) ||
            CASE WHEN v_cred.SCOPE IS NOT NULL
                 THEN '=' || UTL_URL.ESCAPE(v_cred.SCOPE, TRUE)
                 ELSE NULL END;
                 */
          
          v_request_body :=
       'grant_type='
    || UTL_URL.ESCAPE(TRIM(v_cred.GRANT_TYPE), TRUE)

    || CHR(38)
    || 'client_id='
    || UTL_URL.ESCAPE(TRIM(v_cred.CLIENT_ID), TRUE)

    || CHR(38)
    || 'client_secret='
    || UTL_URL.ESCAPE(v_client_secret, TRUE)

    || CASE
           WHEN TRIM(v_cred.SCOPE) IS NOT NULL
           THEN CHR(38)
                || 'scope='
                || UTL_URL.ESCAPE(TRIM(v_cred.SCOPE), TRUE)
           ELSE NULL
       END;

       
                 



        UTL_HTTP.SET_TRANSFER_TIMEOUT(30);
        -- Set Oracle Wallet for HTTPS — required for any TOKEN_URL using https://
        IF v_cred.WALLET_PATH IS NOT NULL THEN

            UTL_HTTP.SET_WALLET(v_cred.WALLET_PATH, v_cred.WALLET_PASSWORD);
/*
           DECLARE
               v_wallet_pwd VARCHAR2(4000);
               v_key        RAW(32);
           BEGIN
               IF v_cred.WALLET_PASSWORD_ENC IS NOT NULL THEN
                   SELECT ENCRYPT_KEY INTO v_key
                   FROM   CRM_MPM_ENCRYPT_CONFIG
                   WHERE  IS_ACTIVE = 'Y' AND ROWNUM = 1;

                   v_wallet_pwd := UTL_RAW.CAST_TO_VARCHAR2(
                       DBMS_CRYPTO.DECRYPT(
                           src => v_cred.WALLET_PASSWORD_ENC,
                           typ => DBMS_CRYPTO.ENCRYPT_AES256 +
                                  DBMS_CRYPTO.CHAIN_CBC       +
                                  DBMS_CRYPTO.PAD_PKCS5,
                           key => v_key
                       )
                   );
               ELSE
                   v_wallet_pwd := v_cred.WALLET_PASSWORD;  -- fallback plain text
               END IF;
               UTL_HTTP.SET_WALLET(v_cred.WALLET_PATH, v_wallet_pwd);
           END;
*/

        END IF;
        v_http_req := UTL_HTTP.BEGIN_REQUEST(v_cred.TOKEN_URL, 'POST', 'HTTP/1.1');
        UTL_HTTP.SET_HEADER(v_http_req, 'Content-Type', 'application/x-www-form-urlencoded');
        --UTL_HTTP.SET_HEADER(v_http_req, 'Content-Length', LENGTH(v_request_body));
        UTL_HTTP.SET_HEADER( v_http_req, 'Content-Length',TO_CHAR(LENGTHB(v_request_body)));
        UTL_HTTP.WRITE_TEXT(v_http_req, v_request_body);

        v_http_resp := UTL_HTTP.GET_RESPONSE(v_http_req);

        DBMS_LOB.CREATETEMPORARY(v_response, TRUE);
        BEGIN
            LOOP
                UTL_HTTP.READ_TEXT(v_http_resp, v_buffer, 32767);
                DBMS_LOB.WRITEAPPEND(v_response, LENGTH(v_buffer), v_buffer);
            END LOOP;
        EXCEPTION
            WHEN UTL_HTTP.END_OF_BODY THEN NULL;
        END;
        UTL_HTTP.END_RESPONSE(v_http_resp);

        IF v_http_resp.status_code <> 200 THEN
            RAISE_APPLICATION_ERROR(-20001,
                'Token request failed. HTTP ' || v_http_resp.status_code ||
                ' Response: ' || DBMS_LOB.SUBSTR(v_response, 4000, 1));
        END IF;

        v_token      := JSON_VALUE(v_response, '$.access_token');
        v_expires_in := JSON_VALUE(v_response, '$.expires_in' RETURNING NUMBER DEFAULT 3600 ON ERROR);

        IF v_token IS NULL THEN
            RAISE_APPLICATION_ERROR(-20002, 'Token response did not contain access_token: ' ||
                DBMS_LOB.SUBSTR(v_response, 4000, 1));
        END IF;

        UPDATE CRM_MPM_API_CREDENTIALS
        SET TOKEN_CACHE_VALUE = v_token,
            TOKEN_EXPIRY      = SYSTIMESTAMP + (v_expires_in / 86400),
            UPDATED_DATE      = SYSTIMESTAMP
        WHERE CRED_CODE = p_cred_code;

        RETURN v_token;

    EXCEPTION
        -- FIX: capture SQLERRM into local variable before embedding in SQL/string
        WHEN UTL_HTTP.TRANSFER_TIMEOUT OR UTL_HTTP.HTTP_CLIENT_ERROR OR UTL_HTTP.HTTP_SERVER_ERROR THEN
            v_err_msg := SQLERRM;  -- capture first
            BEGIN UTL_HTTP.END_RESPONSE(v_http_resp); EXCEPTION WHEN OTHERS THEN NULL; END;
            RAISE_APPLICATION_ERROR(-20003, 'Token endpoint connection failed: ' || v_err_msg);
        WHEN OTHERS THEN
            BEGIN UTL_HTTP.END_RESPONSE(v_http_resp); EXCEPTION WHEN OTHERS THEN NULL; END;
            RAISE;
    END GET_BEARER_TOKEN;


    /* ====================================================================
       JSON BUILDER
       ==================================================================== */
    FUNCTION BUILD_JSON_PAYLOAD(
        p_registry_id IN NUMBER,
        p_source_view IN VARCHAR2,
        p_key_col     IN VARCHAR2,
        p_key_value   IN VARCHAR2
    ) RETURN CLOB IS
        v_cursor_id     INTEGER;
        v_sql           VARCHAR2(4000);
        v_col_cnt       INTEGER;
        v_desc_tab      DBMS_SQL.DESC_TAB2;
        v_result_clob   CLOB;
        v_json_obj      JSON_OBJECT_T := JSON_OBJECT_T();



        CURSOR c_map(p_mapping_name VARCHAR2) IS
            SELECT SOURCE_COLUMN, JSON_PATH, DATA_TYPE, DATE_FORMAT, DISPLAY_ORDER
            FROM CRM_MPM_API_FIELD_MAPPING
            WHERE JSON_MAPPING_NAME = p_mapping_name
              AND IS_ACTIVE = 'Y'
            ORDER BY DISPLAY_ORDER;

        v_mapping_name  VARCHAR2(100);
        v_source_type   VARCHAR2(20);
        v_source_proc   VARCHAR2(128);
        v_ref_cursor    SYS_REFCURSOR;
        v_val_varchar   VARCHAR2(4000);
        v_date DATE;

        PROCEDURE SET_NESTED_VALUE(
            p_root      IN OUT NOCOPY JSON_OBJECT_T,
            p_path      IN VARCHAR2,
            p_value     IN VARCHAR2,
            p_data_type IN VARCHAR2
        ) IS
            v_dot   PLS_INTEGER;
            v_key   VARCHAR2(100);
            v_rest  VARCHAR2(200);
            v_child JSON_OBJECT_T;
        BEGIN

            v_dot := INSTR(p_path, '.');
            IF v_dot = 0 THEN
                CASE p_data_type
                    WHEN 'NUMBER' THEN
                        IF p_value IS NOT NULL THEN
                            p_root.put(p_path, TO_NUMBER(p_value));
                        ELSE
                            p_root.put_null(p_path);
                        END IF;
                    WHEN 'BOOLEAN' THEN
                        p_root.put(p_path, (p_value IN ('Y','1','TRUE')));
                    ELSE
                        -- Check if source column name ends with _JSON
                        -- These columns contain pre-built JSON arrays from the view
                        -- e.g. UTILITIES_JSON, SECURITY_OFFICERS_JSON
                        IF UPPER(p_path) LIKE '%_JSON' OR
                           p_value LIKE '[%' OR p_value LIKE '{%' THEN
                            IF p_value IS NOT NULL THEN
                                BEGIN
                                    p_root.put(p_path, JSON_ELEMENT_T.PARSE(p_value));
                                EXCEPTION
                                    WHEN OTHERS THEN
                                        p_root.put(p_path, p_value);
                                END;
                            ELSE
                                p_root.put(p_path, JSON_ARRAY_T());
                            END IF;
                        ELSE
                        p_root.put(p_path, p_value);
                        END IF;
                END CASE;
            ELSE
                v_key  := SUBSTR(p_path, 1, v_dot - 1);
                v_rest := SUBSTR(p_path, v_dot + 1);
                IF p_root.has(v_key) THEN
                    v_child := TREAT(p_root.get(v_key) AS JSON_OBJECT_T);
                ELSE
                    v_child := JSON_OBJECT_T();
                END IF;
                SET_NESTED_VALUE(v_child, v_rest, p_value, p_data_type);
                p_root.put(v_key, v_child);
            END IF;
        END SET_NESTED_VALUE;

    BEGIN
        SELECT JSON_MAPPING_NAME, SOURCE_TYPE, SOURCE_PROC
        INTO v_mapping_name, v_source_type, v_source_proc
        FROM CRM_MPM_API_REGISTRY WHERE REGISTRY_ID = p_registry_id;

        IF v_source_type = 'PROCEDURE' THEN
            IF v_source_proc IS NULL THEN
                RAISE_APPLICATION_ERROR(-20011,
                    'SOURCE_TYPE=PROCEDURE but SOURCE_PROC is NULL for REGISTRY_ID=' || p_registry_id);
            END IF;

            -- FIX: EXECUTE IMMEDIATE with OUT bind for ref cursor
            v_sql := 'BEGIN ' || v_source_proc || '(:p_key, :p_cursor); END;';
            EXECUTE IMMEDIATE v_sql USING IN p_key_value, IN OUT v_ref_cursor;

            v_cursor_id := DBMS_SQL.TO_CURSOR_NUMBER(v_ref_cursor);
            DBMS_SQL.DESCRIBE_COLUMNS2(v_cursor_id, v_col_cnt, v_desc_tab);

            FOR i IN 1..v_col_cnt LOOP
                DBMS_SQL.DEFINE_COLUMN(v_cursor_id, i, v_val_varchar, 4000);
            END LOOP;

            IF DBMS_SQL.FETCH_ROWS(v_cursor_id) = 0 THEN
                DBMS_SQL.CLOSE_CURSOR(v_cursor_id);
                RAISE_APPLICATION_ERROR(-20010,
                    'No row returned by procedure ' || v_source_proc ||
                    ' for ' || p_key_col || ' = ' || p_key_value);
            END IF;

        ELSE
            v_sql := 'SELECT * FROM ' || p_source_view ||
                     ' WHERE ' || p_key_col || ' = :keyval';

            v_cursor_id := DBMS_SQL.OPEN_CURSOR;
            DBMS_SQL.PARSE(v_cursor_id, v_sql, DBMS_SQL.NATIVE);
            DBMS_SQL.BIND_VARIABLE(v_cursor_id, ':keyval', p_key_value);
            DBMS_SQL.DESCRIBE_COLUMNS2(v_cursor_id, v_col_cnt, v_desc_tab);

            FOR i IN 1..v_col_cnt LOOP
                DBMS_SQL.DEFINE_COLUMN(v_cursor_id, i, v_val_varchar, 4000);
            END LOOP;

            IF DBMS_SQL.EXECUTE_AND_FETCH(v_cursor_id) = 0 THEN
                DBMS_SQL.CLOSE_CURSOR(v_cursor_id);
                RAISE_APPLICATION_ERROR(-20010,
                    'No row found in ' || p_source_view ||
                    ' for ' || p_key_col || ' = ' || p_key_value);
            END IF;
        END IF;


        FOR rec IN c_map(v_mapping_name) LOOP
            v_val_varchar := NULL;
            FOR i IN 1..v_col_cnt LOOP
                IF UPPER(v_desc_tab(i).col_name) = UPPER(rec.SOURCE_COLUMN) THEN
                    DBMS_SQL.COLUMN_VALUE(v_cursor_id, i, v_val_varchar);
                    DBMS_OUTPUT.PUT_LINE(
                       rec.SOURCE_COLUMN || '=[' || v_val_varchar || ']'
                    );
                -- ADD Date formate -- inside existing IF, after COLUMN_VALUE
                   IF v_desc_tab(i).col_type = 12 
                   AND v_val_varchar IS NOT NULL THEN
                    BEGIN

                        -- Date format fix: explicitly parse using DD-MON-YYYY first,
                        -- then fall back to DD-MON-RR for older 2-digit year formats.
                        -- This replaces the original ALTER SESSION approach — same result,
                        -- no session-level side effects on other procedures/jobs.
                        BEGIN
                            v_val_varchar := TO_CHAR(
                                TO_DATE(v_val_varchar, 'DD-MON-YYYY HH24:MI:SS'),
                                NVL(rec.DATE_FORMAT, 'DD-MON-YYYY HH24:MI:SS'));
                        EXCEPTION
                            WHEN OTHERS THEN
                                -- Fallback: try RR (2-digit year) format
                                v_val_varchar := TO_CHAR(
                                    TO_DATE(v_val_varchar, 'DD-MON-RR HH24:MI:SS'),
                                    NVL(rec.DATE_FORMAT, 'DD-MON-YYYY HH24:MI:SS'));
                        END;



                    EXCEPTION
                            WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE(
            'Date conversion failed: ' ||
            v_val_varchar || ' Error=' || SQLERRM
        );

                    END;
                END IF;

                END IF;
            END LOOP;
            SET_NESTED_VALUE(v_json_obj, rec.JSON_PATH, v_val_varchar, rec.DATA_TYPE);
        END LOOP;

        DBMS_SQL.CLOSE_CURSOR(v_cursor_id);
        v_result_clob := v_json_obj.to_clob();
        RETURN v_result_clob;

    EXCEPTION
        WHEN OTHERS THEN
            IF DBMS_SQL.IS_OPEN(v_cursor_id) THEN
                DBMS_SQL.CLOSE_CURSOR(v_cursor_id);
            END IF;
            RAISE;
    END BUILD_JSON_PAYLOAD;

    /* ====================================================================
       INTERNAL HELPER  sends a CLOB payload to APIC
       Used by both SEND_TO_APIC and SUBMIT_TO_STAGING
       KEY FIX: Transfer-Encoding chunked (no Content-Length)
                WRITE_TEXT with VARCHAR2 â€” Arabic works correctly
       ==================================================================== */
    PROCEDURE SEND_PAYLOAD_TO_APIC(
        p_endpoint      IN  VARCHAR2,
        p_http_method   IN  VARCHAR2,
        p_token         IN  VARCHAR2,
        p_wallet_path   IN  VARCHAR2,
        p_wallet_pwd    IN  VARCHAR2,
        p_txn_group     IN  VARCHAR2,
        p_unique_id     IN  VARCHAR2,
        p_rec_type      IN  VARCHAR2,
        p_rec_action    IN  VARCHAR2,
        p_api_version   IN  VARCHAR2,
        p_payload       IN  CLOB,
        p_status_code   OUT VARCHAR2,
        p_response      OUT CLOB
    ) IS
        v_http_req  UTL_HTTP.REQ;
        v_http_resp UTL_HTTP.RESP;
        v_buffer    VARCHAR2(32767);
        v_full_url  VARCHAR2(1000);
        v_offset    PLS_INTEGER := 1;
        v_amount    PLS_INTEGER := 32767;
        v_len       PLS_INTEGER;
        v_chunk     VARCHAR2(32767);
    BEGIN
        -- Build URL with api-version
        v_full_url := p_endpoint;
        IF p_api_version IS NOT NULL THEN
            IF INSTR(v_full_url, '?') > 0 THEN
                v_full_url := v_full_url || '-version=' || p_api_version;
            ELSE
                v_full_url := v_full_url || '?api-version=' || p_api_version;
            END IF;
        END IF;

        UTL_HTTP.SET_TRANSFER_TIMEOUT(60);
        IF p_wallet_path IS NOT NULL THEN
            UTL_HTTP.SET_WALLET(p_wallet_path, p_wallet_pwd);
        END IF;

        v_http_req := UTL_HTTP.BEGIN_REQUEST(v_full_url, p_http_method, 'HTTP/1.1');

        -- Headers
        -- NOTE: Transfer-Encoding chunked used instead of Content-Length
        -- Content-Length causes Arabic corruption (char count != byte count for multibyte)
        -- Transfer-Encoding chunked lets Oracle handle byte boundaries automatically
        UTL_HTTP.SET_HEADER(v_http_req, 'Content-Type',           'application/json; charset=UTF-8');
        UTL_HTTP.SET_HEADER(v_http_req, 'Authorization',          'Bearer ' || p_token);
        UTL_HTTP.SET_HEADER(v_http_req, 'X-Transaction-Group-Id', p_txn_group);
        UTL_HTTP.SET_HEADER(v_http_req, 'record-type',            p_rec_type);
        UTL_HTTP.SET_HEADER(v_http_req, 'record-action',          p_rec_action);
        UTL_HTTP.SET_HEADER(v_http_req, 'x-unique-id',            p_unique_id);
        UTL_HTTP.SET_HEADER(v_http_req, 'Transfer-Encoding',      'chunked');

        -- Send payload in chunks using WRITE_TEXT
        -- WRITE_TEXT with Transfer-Encoding chunked correctly handles Arabic/multibyte
        v_len := DBMS_LOB.GETLENGTH(p_payload);
        WHILE v_offset <= v_len LOOP
            v_chunk  := DBMS_LOB.SUBSTR(p_payload, v_amount, v_offset);
            UTL_HTTP.WRITE_TEXT(v_http_req, v_chunk);
            v_offset := v_offset + v_amount;
        END LOOP;

        -- Get response
        v_http_resp   := UTL_HTTP.GET_RESPONSE(v_http_req);
        p_status_code := TO_CHAR(v_http_resp.status_code);

        DBMS_LOB.CREATETEMPORARY(p_response, TRUE);
        BEGIN
            LOOP
                UTL_HTTP.READ_TEXT(v_http_resp, v_buffer, 32767);
                DBMS_LOB.WRITEAPPEND(p_response, LENGTH(v_buffer), v_buffer);
            END LOOP;
        EXCEPTION
            WHEN UTL_HTTP.END_OF_BODY THEN NULL;
        END;
        UTL_HTTP.END_RESPONSE(v_http_resp);

    END SEND_PAYLOAD_TO_APIC;


    /* ====================================================================
       SEND_TO_APIC
       ==================================================================== */
    PROCEDURE SEND_TO_APIC(
        p_registry_id          IN NUMBER,
        p_key_value            IN VARCHAR2,
        p_transaction_group_id IN VARCHAR2 DEFAULT NULL,
        p_attempt_no           IN NUMBER   DEFAULT 1,
        p_log_id_out           OUT NUMBER
    ) IS
        v_reg           CRM_MPM_API_REGISTRY%ROWTYPE;
        v_payload       CLOB;
        v_token         VARCHAR2(4000);
        v_http_req      UTL_HTTP.REQ;
        v_http_resp     UTL_HTTP.RESP;
        v_response      CLOB := EMPTY_CLOB();
        v_buffer        VARCHAR2(32767);
        v_txn_group     VARCHAR2(40);
        v_unique_id     VARCHAR2(60);
        v_wallet_path     VARCHAR2(200);
        v_wallet_password VARCHAR2(200);
        v_log_id        NUMBER;
        v_status_code   VARCHAR2(10);
        v_final_status  VARCHAR2(20);
        v_error_code    VARCHAR2(30);
        v_error_message VARCHAR2(4000);
        -- ACK response fields (LEG 1 synchronous response from CRM via APIC)
        v_ack_request_id    VARCHAR2(100);
        v_ack_status_code   VARCHAR2(10);
        v_ack_description   VARCHAR2(500);
        v_ack_message       VARCHAR2(1000);
        v_ack_response_ts   VARCHAR2(50);  -- response_timestamp from LEG 1 ACK
        -- FIX: local variables to hold SQLERRM before use in DML
        v_err_msg       VARCHAR2(4000);
    BEGIN
        SELECT * INTO v_reg
        FROM CRM_MPM_API_REGISTRY
        WHERE REGISTRY_ID = p_registry_id AND IS_ACTIVE = 'Y';

        -- ----------------------------------------------------------------
        -- DUPLICATE GUARD (attempt_no=1 only — retries are intentional)
        -- If a SENT, SUCCESS or PENDING row already exists for this record,
        -- return the existing LOG_ID and skip re-sending to APIC.
        -- Prevents duplicates from scheduler overlaps or manual re-runs.
        -- ----------------------------------------------------------------
        IF p_attempt_no = 1 THEN
            DECLARE
                v_exist_log_id NUMBER;
                v_exist_status VARCHAR2(20);
            BEGIN
                SELECT LOG_ID, FINAL_STATUS
                INTO   v_exist_log_id, v_exist_status
                FROM   CRM_MPM_CRM_INTEGRATION_LOG
                WHERE  REGISTRY_ID      = p_registry_id
                  AND  SOURCE_RECORD_ID = p_key_value
                  AND  FINAL_STATUS     IN ('PENDING','SENT','SUCCESS','ALREADY_PROCESSED')
                ORDER BY LOG_ID DESC
                FETCH FIRST 1 ROW ONLY;
                -- Duplicate found — return existing log_id, do not re-send
                p_log_id_out := v_exist_log_id;
                RETURN;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN NULL; -- no duplicate, safe to proceed
            END;
        END IF;

        v_txn_group := COALESCE(p_transaction_group_id, NEW_GUID());
        v_unique_id := GENERATE_UNIQUE_ID();

        v_payload := BUILD_JSON_PAYLOAD(
            p_registry_id, v_reg.SOURCE_VIEW, v_reg.SOURCE_KEY_COL, p_key_value);

        -- NOTE: v_unique_id is sent as the x-unique-id HTTP header below.
        -- It is NOT stored in a dedicated column here because CRM_MPM_CRM_INTEGRATION_LOG's
        -- exact columns have not been independently re-verified for an X_UNIQUE_ID field.
        -- If traceability in the log table is needed, ADD a column first:
        --   ALTER TABLE CRM_MPM_CRM_INTEGRATION_LOG ADD X_UNIQUE_ID VARCHAR2(60);
        -- then add X_UNIQUE_ID to the INSERT below. Until then, the value is only
        -- visible in session trace / APIC's own logs by header inspection.

        INSERT INTO CRM_MPM_CRM_INTEGRATION_LOG (
            REGISTRY_ID, ENTITY_NAME, OPERATION_TYPE, SOURCE_RECORD_ID,
            TRANSACTION_GROUP_ID, ATTEMPT_NO,
            REQUEST_PAYLOAD, SENT_DATE, FINAL_STATUS, X_UNIQUE_ID
        ) VALUES (
            p_registry_id, v_reg.ENTITY_NAME, v_reg.OPERATION_TYPE, p_key_value,
            v_txn_group, p_attempt_no,
            v_payload, SYSTIMESTAMP, 'PENDING', v_unique_id
        ) RETURNING LOG_ID INTO v_log_id;

        p_log_id_out := v_log_id;

        BEGIN
            v_token := GET_BEARER_TOKEN(v_reg.CRED_CODE);

            -- Fetch wallet path/password for this credential — needed for
            -- HTTPS calls to APIC, same wallet used for the token endpoint.
            BEGIN
                SELECT WALLET_PATH, WALLET_PASSWORD
                INTO   v_wallet_path, v_wallet_password
                FROM   CRM_MPM_API_CREDENTIALS
                WHERE  CRED_CODE = v_reg.CRED_CODE;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    v_wallet_path     := NULL;
                    v_wallet_password := NULL;
            END;

            UTL_HTTP.SET_TRANSFER_TIMEOUT(60);
            IF v_wallet_path IS NOT NULL THEN
                UTL_HTTP.SET_WALLET(v_wallet_path, v_wallet_password);
            END IF;
            -- Append api-version query param from registry (no hardcoding)
            DECLARE
                v_full_url VARCHAR2(1000);
            BEGIN
                v_full_url := v_reg.APIC_ENDPOINT_URL;
                IF v_reg.APIC_API_VERSION IS NOT NULL THEN
                    IF INSTR(v_full_url, '?') > 0 THEN
                        v_full_url := v_full_url || '-version=' || v_reg.APIC_API_VERSION;
                    ELSE
                        v_full_url := v_full_url || '?api-version=' || v_reg.APIC_API_VERSION;
                    END IF;
                END IF;
                v_http_req := UTL_HTTP.BEGIN_REQUEST(v_full_url, v_reg.HTTP_METHOD, 'HTTP/1.1');
            END;
            UTL_HTTP.SET_HEADER(v_http_req, 'Content-Type',           'application/json');
            --UTL_HTTP.SET_BODY_CHARSET(v_http_req, 'UTF-8');
            --UTL_HTTP.SET_HEADER(v_http_req, 'Content-Type', 'application/json; charset=UTF-8');
            UTL_HTTP.SET_HEADER(v_http_req, 'Authorization',          'Bearer ' || v_token);
            UTL_HTTP.SET_HEADER(v_http_req, 'X-Transaction-Group-Id', v_txn_group);
            -- Dynamic headers from registry — no hardcoding in package
            UTL_HTTP.SET_HEADER(v_http_req, 'record-type',   v_reg.RECORD_TYPE_HDR);
            UTL_HTTP.SET_HEADER(v_http_req, 'record-action', v_reg.EVENT_CODE_HDR);
            UTL_HTTP.SET_HEADER(v_http_req, 'x-unique-id',            v_unique_id);
            --UTL_HTTP.SET_HEADER(v_http_req, 'Content-Length',         DBMS_LOB.GETLENGTH(v_payload));
            UTL_HTTP.SET_HEADER(v_http_req, 'Transfer-Encoding', 'chunked');


--            DECLARE
--                v_offset PLS_INTEGER := 1;
--                v_amount PLS_INTEGER := 32767;
--                v_len    PLS_INTEGER := DBMS_LOB.GETLENGTH(v_payload);
--                v_chunk  VARCHAR2(32767);
--            BEGIN
--                WHILE v_offset <= v_len LOOP
--                    v_chunk  := DBMS_LOB.SUBSTR(v_payload, v_amount, v_offset);
--                    DBMS_OUTPUT.PUT_LINE(
--                         DBMS_LOB.SUBSTR(v_payload, 4000, 1));
--                    UTL_HTTP.WRITE_TEXT(v_http_req, v_chunk);
--                    v_offset := v_offset + LENGTH(v_chunk);
--                END LOOP;
--            END;

            DECLARE
                v_offset PLS_INTEGER := 1;
                v_amount PLS_INTEGER := 8191;
                v_len    PLS_INTEGER := DBMS_LOB.GETLENGTH(v_payload);
                v_chunk  VARCHAR2(32767);
                v_raw    RAW(32767);
            BEGIN
                WHILE v_offset <= v_len LOOP
                    v_chunk  := DBMS_LOB.SUBSTR(v_payload, v_amount, v_offset);

                    v_raw := UTL_RAW.CAST_TO_RAW(CONVERT(v_chunk,'AL32UTF8','AL32UTF8'));
                    UTL_HTTP.WRITE_RAW(v_http_req, v_raw);

                    v_offset := v_offset + LENGTH(v_chunk);
                END LOOP;
            END;

            v_http_resp   := UTL_HTTP.GET_RESPONSE(v_http_req);
            v_status_code := TO_CHAR(v_http_resp.status_code);

            DBMS_LOB.CREATETEMPORARY(v_response, TRUE);
            BEGIN
                LOOP
                    UTL_HTTP.READ_TEXT(v_http_resp, v_buffer, 32767);
                    DBMS_LOB.WRITEAPPEND(v_response, LENGTH(v_buffer), v_buffer);
                END LOOP;
            EXCEPTION
                WHEN UTL_HTTP.END_OF_BODY THEN NULL;
            END;
            UTL_HTTP.END_RESPONSE(v_http_resp);

            IF v_http_resp.status_code BETWEEN 200 AND 299 THEN
                -- HTTP OK — parse the CRM ACK JSON body for LEG 1 result.
                -- Confirmed LEG 1 ACK format (vendor confirmed 2026-07-01):
                -- { "request_id":"...", "status":"0000"/"9999",
                --   "description":"Success"/"Failed", "record_type":"...",
                --   "record_action":"...", "message":"...", "response_timestamp":"..." }
                -- status=0000 always unless header/auth issue (vendor confirmed).
                -- Business failures only come in LEG 2 via PROCESS_CRM_CALLBACK.
                -- request_id primary (spec). requestid fallback (live APIC response).
                v_ack_request_id  := JSON_VALUE(v_response, '$.request_id');
                IF v_ack_request_id IS NULL THEN
                    v_ack_request_id := JSON_VALUE(v_response, '$.requestid');
                END IF;
                v_ack_status_code := JSON_VALUE(v_response, '$.status');
                v_ack_description := JSON_VALUE(v_response, '$.description');
                v_ack_message     := JSON_VALUE(v_response, '$.message');
                -- Parse response_timestamp into dedicated variable
                v_ack_response_ts := JSON_VALUE(v_response, '$.response_timestamp');

                -- LEG 1 status: 0000=accepted (LEG 2 will follow), 9999=header/auth error
                IF NVL(v_ack_status_code,'0000') = '0000' THEN
                    v_final_status  := 'SENT';
                    v_error_code    := NULL;
                    v_error_message := NULL;
                ELSE
                    -- status=9999: CRM/PxRM failed to create the record — retryable
                    -- NOTE: confirmed by CRM team email — 9999 = failure, record not created
                    -- retry job must pick this up and re-push
                    v_final_status  := 'FAILED';
                    v_error_code    := 'FAILURE';
                    v_error_message := 'PxRM rejected record (status=9999): ' ||
                                       v_ack_description || ' | ' || v_ack_message;
                END IF;
            ELSIF v_http_resp.status_code IN (401, 403) THEN
                v_final_status  := 'FAILED';
                v_error_code    := 'AUTH_FAILED';
                v_error_message := 'HTTP ' || v_status_code || ': ' ||
                                   DBMS_LOB.SUBSTR(v_response, 2000, 1);
            ELSIF v_http_resp.status_code BETWEEN 400 AND 499 THEN
                v_final_status  := 'FAILED';
                v_error_code    := 'VALIDATION_ERROR';
                v_error_message := 'HTTP ' || v_status_code || ': ' ||
                                   DBMS_LOB.SUBSTR(v_response, 2000, 1);
            ELSE
                v_final_status  := 'FAILED';
                v_error_code    := 'APIC_ERROR';
                v_error_message := 'HTTP ' || v_status_code || ': ' ||
                                   DBMS_LOB.SUBSTR(v_response, 2000, 1);
            END IF;

        EXCEPTION
            -- FIX: capture SQLERRM into local var before assigning to v_error_message
            WHEN UTL_HTTP.TRANSFER_TIMEOUT THEN
                v_err_msg := SQLERRM;
                BEGIN UTL_HTTP.END_RESPONSE(v_http_resp); EXCEPTION WHEN OTHERS THEN NULL; END;
                v_status_code   := NULL;
                v_final_status  := 'FAILED';
                v_error_code    := 'CONN_FAILED';
                v_error_message := 'Connection timeout calling APIC: ' || v_err_msg;
            WHEN UTL_HTTP.HTTP_CLIENT_ERROR OR UTL_HTTP.HTTP_SERVER_ERROR THEN
                v_err_msg := SQLERRM;
                BEGIN UTL_HTTP.END_RESPONSE(v_http_resp); EXCEPTION WHEN OTHERS THEN NULL; END;
                v_status_code   := NULL;
                v_final_status  := 'FAILED';
                v_error_code    := 'APIC_ERROR';
                v_error_message := 'HTTP client/server error: ' || v_err_msg;
            WHEN OTHERS THEN
                v_err_msg := SQLERRM;
                BEGIN UTL_HTTP.END_RESPONSE(v_http_resp); EXCEPTION WHEN OTHERS THEN NULL; END;
                v_status_code   := NULL;
                v_final_status  := 'FAILED';
                v_error_code    := 'UNKNOWN_ERROR';
                v_error_message := 'Unexpected error: ' || v_err_msg;
        END;

        UPDATE CRM_MPM_CRM_INTEGRATION_LOG
        SET HTTP_STATUS_CODE = v_status_code,
            ACK_RESPONSE     = v_response,
            ACK_REQUEST_ID      = v_ack_request_id,    -- request_id from CRM ACK
            ACK_STATUS_CODE     = v_ack_status_code,   -- '0000' or '9999'
            ACK_DESCRIPTION     = v_ack_description,
            ACK_RESPONSE_TIMESTAMP = v_ack_response_ts, -- response_timestamp from LEG 1
            FINAL_STATUS        = v_final_status,
            ERROR_CODE          = v_error_code,
            ERROR_MESSAGE       = v_error_message,
            X_UNIQUE_ID         = v_unique_id,
            RETRY_COUNT         = p_attempt_no - 1,
            UPDATED_DATE        = SYSTIMESTAMP
        WHERE LOG_ID = v_log_id;

        COMMIT;

    EXCEPTION
        WHEN OTHERS THEN
            -- FIX: capture SQLERRM before embedding in UPDATE
            v_err_msg := SQLERRM;
            IF v_log_id IS NOT NULL THEN
                UPDATE CRM_MPM_CRM_INTEGRATION_LOG
                SET FINAL_STATUS  = 'FAILED',
                    ERROR_CODE    = 'UNKNOWN_ERROR',
                    ERROR_MESSAGE = 'SEND_TO_APIC fatal error: ' || v_err_msg,
                    UPDATED_DATE  = SYSTIMESTAMP
                WHERE LOG_ID = v_log_id;
                COMMIT;
            END IF;
            RAISE;
    END SEND_TO_APIC;


    /* ====================================================================
       RELEASE_PARENT_PENDING  (Session 9 — 09-Oct-2026)
       Children skipped as PARENT_PENDING are never re-read by the outbound
       cursor (watermark moves past them). This pass works from the LOG:
       parent SUCCESS -> send child, pending row -> RELEASED
       parent terminal failure -> PARENT_FAILED ; parent retried -> PARENT_PENDING
       Called at the start of every RUN_OUTBOUND_JOB.
       ==================================================================== */
    PROCEDURE RELEASE_PARENT_PENDING IS
        v_parent_key     VARCHAR2(500);
        v_parent_ok      NUMBER;
        v_parent_status  VARCHAR2(30);
        v_new_log_id     NUMBER;
        v_err_msg        VARCHAR2(4000);
    BEGIN
        FOR p IN (
            SELECT L.LOG_ID, L.REGISTRY_ID, L.SOURCE_RECORD_ID, L.FINAL_STATUS,
                   R.DEPENDS_ON_REGISTRY_ID, R.PARENT_LINK_COL,
                   R.SOURCE_VIEW, R.SOURCE_KEY_COL
            FROM   CRM_MPM_CRM_INTEGRATION_LOG L
            JOIN   CRM_MPM_API_REGISTRY R ON R.REGISTRY_ID = L.REGISTRY_ID
            WHERE  L.FINAL_STATUS IN ('PARENT_PENDING','PARENT_FAILED')
            AND    R.IS_ACTIVE = 'Y'
            AND    R.DEPENDS_ON_REGISTRY_ID IS NOT NULL
            AND    R.PARENT_LINK_COL IS NOT NULL
            ORDER  BY R.EXECUTION_ORDER, L.LOG_ID
        ) LOOP
            BEGIN
                -- 1. Resolve parent key from the child's source view
                v_parent_key := NULL;
                BEGIN
                    EXECUTE IMMEDIATE
                        'SELECT ' || p.PARENT_LINK_COL ||
                        ' FROM '  || p.SOURCE_VIEW ||
                        ' WHERE ' || p.SOURCE_KEY_COL || ' = :k AND ROWNUM = 1'
                        INTO v_parent_key USING p.SOURCE_RECORD_ID;
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN v_parent_key := NULL;
                END;

                IF v_parent_key IS NOT NULL THEN

                    -- 2. Same rule as the outbound check: any SUCCESS row for parent
                    SELECT COUNT(*) INTO v_parent_ok
                    FROM   CRM_MPM_CRM_INTEGRATION_LOG
                    WHERE  REGISTRY_ID      = p.DEPENDS_ON_REGISTRY_ID
                    AND    SOURCE_RECORD_ID = v_parent_key
                    AND    FINAL_STATUS     = 'SUCCESS';

                    IF v_parent_ok > 0 THEN
                        -- 3. Send the child
                        v_new_log_id := NULL;
                        v_err_msg    := NULL;
                        BEGIN
                            SEND_TO_APIC(
                                p_registry_id => p.REGISTRY_ID,
                                p_key_value   => p.SOURCE_RECORD_ID,
                                p_attempt_no  => 1,
                                p_log_id_out  => v_new_log_id);
                        EXCEPTION
                            WHEN OTHERS THEN
                                v_err_msg := SQLERRM;
                                -- SEND_TO_APIC marks its own row FAILED before RAISE
                                -- (retry job owns it); OUT param is lost, so look it up
                                SELECT MAX(LOG_ID) INTO v_new_log_id
                                FROM   CRM_MPM_CRM_INTEGRATION_LOG
                                WHERE  REGISTRY_ID      = p.REGISTRY_ID
                                AND    SOURCE_RECORD_ID = p.SOURCE_RECORD_ID
                                AND    LOG_ID           > p.LOG_ID
                                AND    FINAL_STATUS NOT IN ('PARENT_PENDING','PARENT_FAILED','RELEASED');
                        END;

                        IF v_new_log_id IS NOT NULL THEN
                            UPDATE CRM_MPM_CRM_INTEGRATION_LOG
                            SET    FINAL_STATUS  = 'RELEASED',
                                   ERROR_MESSAGE = SUBSTR(ERROR_MESSAGE || ' | Released '
                                                   || TO_CHAR(SYSDATE,'DD-MON-YYYY HH24:MI')
                                                   || ' -> LOG_ID=' || v_new_log_id, 1, 4000),
                                   UPDATED_DATE  = SYSTIMESTAMP
                            WHERE  LOG_ID = p.LOG_ID;
                        ELSE
                            -- Nothing was logged: stay pending, try again next run
                            UPDATE CRM_MPM_CRM_INTEGRATION_LOG
                            SET    ERROR_MESSAGE = SUBSTR('Release attempt failed: ' || v_err_msg, 1, 4000),
                                   UPDATED_DATE  = SYSTIMESTAMP
                            WHERE  LOG_ID = p.LOG_ID;
                        END IF;

                    ELSE
                        -- 4. Parent not SUCCESS yet: flag terminal failures so they are visible
                        SELECT MAX(FINAL_STATUS) KEEP (DENSE_RANK LAST ORDER BY LOG_ID)
                        INTO   v_parent_status
                        FROM   CRM_MPM_CRM_INTEGRATION_LOG
                        WHERE  REGISTRY_ID      = p.DEPENDS_ON_REGISTRY_ID
                        AND    SOURCE_RECORD_ID = v_parent_key
                        AND    FINAL_STATUS    <> 'RELEASED';

                        IF v_parent_status IN ('EXHAUSTED','VALIDATION_FAILED',
                                               'RECORD_NOT_FOUND','CRM_REJECTED','PARENT_FAILED')
                           AND p.FINAL_STATUS = 'PARENT_PENDING' THEN
                            UPDATE CRM_MPM_CRM_INTEGRATION_LOG
                            SET    FINAL_STATUS  = 'PARENT_FAILED',
                                   ERROR_CODE    = 'PARENT_FAILED',
                                   ERROR_MESSAGE = SUBSTR('Parent Registry=' || p.DEPENDS_ON_REGISTRY_ID
                                                   || ' Key=' || v_parent_key
                                                   || ' is ' || v_parent_status, 1, 4000),
                                   UPDATED_DATE  = SYSTIMESTAMP
                            WHERE  LOG_ID = p.LOG_ID;
                        ELSIF (v_parent_status IS NULL OR v_parent_status NOT IN
                                  ('EXHAUSTED','VALIDATION_FAILED','RECORD_NOT_FOUND',
                                   'CRM_REJECTED','PARENT_FAILED'))
                           AND p.FINAL_STATUS = 'PARENT_FAILED' THEN
                            -- Parent was manually retried: back to waiting
                            UPDATE CRM_MPM_CRM_INTEGRATION_LOG
                            SET    FINAL_STATUS  = 'PARENT_PENDING',
                                   ERROR_CODE    = 'PARENT_PENDING',
                                   ERROR_MESSAGE = SUBSTR('Waiting for parent Registry='
                                                   || p.DEPENDS_ON_REGISTRY_ID
                                                   || ' Key=' || v_parent_key
                                                   || ' to reach SUCCESS status', 1, 4000),
                                   UPDATED_DATE  = SYSTIMESTAMP
                            WHERE  LOG_ID = p.LOG_ID;
                        END IF;
                    END IF;
                END IF;

                COMMIT;
            EXCEPTION
                WHEN OTHERS THEN
                    ROLLBACK;  -- one bad row must never stop the outbound job
            END;
        END LOOP;
    END RELEASE_PARENT_PENDING;


    /* ====================================================================
       RUN_OUTBOUND_JOB
       ==================================================================== */
    PROCEDURE RUN_OUTBOUND_JOB IS
        v_run_id     NUMBER;
        v_processed  NUMBER := 0;
        v_success    NUMBER := 0;
        v_failed     NUMBER := 0;
        v_max_ts     TIMESTAMP;
        v_log_id     NUMBER;
        v_cursor_id  INTEGER;
        v_sql        VARCHAR2(4000);
        v_key_val    VARCHAR2(4000);
        v_filter_val VARCHAR2(4000);
        v_status     VARCHAR2(20);
        v_skipped    NUMBER := 0;  -- records skipped due to parent dependency
        -- FIX: local var to capture SQLERRM before DML
        v_err_msg    VARCHAR2(4000);
    BEGIN
        -- ----------------------------------------------------------------
        -- JOB-LOCK GUARD: prevent concurrent overlapping executions.
        -- If another OUTBOUND_PUSH has been RUNNING for more than 5 minutes
        -- (i.e. it is a real overlap, not the current insert we are about to do)
        -- skip this invocation entirely.
        -- ----------------------------------------------------------------
        DECLARE
            v_running_count NUMBER;
        BEGIN
            SELECT COUNT(*) INTO v_running_count
            FROM CRM_MPM_JOB_RUN_HISTORY
            WHERE JOB_NAME   = 'OUTBOUND_PUSH'
              AND STATUS      = 'RUNNING'
              AND START_TIME  < SYSTIMESTAMP - (5/1440); -- older than 5 min = real overlap

            IF v_running_count > 0 THEN
                RETURN; -- previous run still active, skip this invocation
            END IF;
        END;

        INSERT INTO CRM_MPM_JOB_RUN_HISTORY (JOB_NAME, STATUS)
        VALUES ('OUTBOUND_PUSH', 'RUNNING')
        RETURNING RUN_ID INTO v_run_id;
        COMMIT;

        -- Session 9: release children whose parent has since reached SUCCESS
        BEGIN
            RELEASE_PARENT_PENDING;
        EXCEPTION
            WHEN OTHERS THEN NULL;  -- never block the main outbound run
        END;

        FOR reg IN (
            SELECT r.*, w.LAST_PROCESSED_TS
            FROM CRM_MPM_API_REGISTRY r
            JOIN CRM_MPM_API_WATERMARK w ON w.REGISTRY_ID = r.REGISTRY_ID
            WHERE r.IS_ACTIVE = 'Y'
            AND r.SOURCE_TYPE = 'VIEW'
            AND r.EXECUTION_ORDER < 99
            ORDER BY r.EXECUTION_ORDER
        ) LOOP

            v_max_ts := reg.LAST_PROCESSED_TS;

            -- Build dynamic SQL with optional extra filter
            -- SOURCE_EXTRA_FILTER can hold any additional WHERE condition
            -- e.g. for UPDATE services: CREATION_DATE <> LAST_UPDATE_DATE
            v_sql := 'SELECT ' || reg.SOURCE_KEY_COL || ', ' || reg.SOURCE_FILTER_COL ||
                     ' FROM '  || reg.SOURCE_VIEW ||
                     ' WHERE ' || reg.SOURCE_FILTER_COL || ' > :wm' ||
                     CASE
                         WHEN reg.SOURCE_EXTRA_FILTER IS NOT NULL
                         THEN ' AND ' || reg.SOURCE_EXTRA_FILTER
                         ELSE ''
                     END ||
                     ' ORDER BY ' || reg.SOURCE_FILTER_COL;

            v_cursor_id := DBMS_SQL.OPEN_CURSOR;
            DBMS_SQL.PARSE(v_cursor_id, v_sql, DBMS_SQL.NATIVE);
            DBMS_SQL.BIND_VARIABLE(v_cursor_id, ':wm', reg.LAST_PROCESSED_TS);
            DBMS_SQL.DEFINE_COLUMN(v_cursor_id, 1, v_key_val,    4000);
            DBMS_SQL.DEFINE_COLUMN(v_cursor_id, 2, v_filter_val, 4000);
            -- FIX: DBMS_SQL.EXECUTE is a FUNCTION returning INTEGER; must capture return value
            DECLARE v_exec_rows INTEGER; BEGIN v_exec_rows := DBMS_SQL.EXECUTE(v_cursor_id); END;

            LOOP
                EXIT WHEN DBMS_SQL.FETCH_ROWS(v_cursor_id) = 0;

                DBMS_SQL.COLUMN_VALUE(v_cursor_id, 1, v_key_val);
                DBMS_SQL.COLUMN_VALUE(v_cursor_id, 2, v_filter_val);

                v_processed := v_processed + 1;

                -- -----------------------------------------------
                -- SEQUENTIAL DEPENDENCY CHECK (CREATE services)
                -- If DEPENDS_ON_REGISTRY_ID is set, check parent
                -- SUCCESS before sending this record
                -- -----------------------------------------------
                IF reg.DEPENDS_ON_REGISTRY_ID IS NOT NULL
                AND reg.PARENT_LINK_COL IS NOT NULL THEN
                    DECLARE
                        v_parent_key   VARCHAR2(500);
                        v_parent_count NUMBER := 0;
                    BEGIN
                        -- Read parent key value from source view
                        EXECUTE IMMEDIATE
                            'SELECT ' || reg.PARENT_LINK_COL ||
                            ' FROM ' || reg.SOURCE_VIEW ||
                            ' WHERE ' || reg.SOURCE_KEY_COL || ' = :k'
                            INTO v_parent_key
                            USING v_key_val;

                        -- Check parent is SUCCESS in integration log
                        SELECT COUNT(*) INTO v_parent_count
                        FROM   CRM_MPM_CRM_INTEGRATION_LOG
                        WHERE  REGISTRY_ID      = reg.DEPENDS_ON_REGISTRY_ID
                        AND    SOURCE_RECORD_ID = v_parent_key
                        AND    FINAL_STATUS     = 'SUCCESS';

                        IF v_parent_count = 0 THEN
                            -- *** CHANGE: INSERT PARENT_PENDING instead of silent skip ***
                            -- Admin Tool and Monitor tab will show this record as waiting
                            v_skipped := NVL(v_skipped, 0) + 1;
                            BEGIN
                                INSERT INTO CRM_MPM_CRM_INTEGRATION_LOG (
                                    REGISTRY_ID, ENTITY_NAME, OPERATION_TYPE,
                                    SOURCE_RECORD_ID, FINAL_STATUS,
                                    ERROR_MESSAGE, CREATED_DATE, UPDATED_DATE)
                                SELECT reg.REGISTRY_ID, reg.ENTITY_NAME,
                                       reg.OPERATION_TYPE, v_key_val,
                                       'PARENT_PENDING',
                                       'Waiting for parent Registry='
                                       || reg.DEPENDS_ON_REGISTRY_ID
                                       || ' Key=' || v_parent_key
                                       || ' to reach SUCCESS status',
                                       SYSTIMESTAMP, SYSTIMESTAMP
                                FROM   DUAL
                                WHERE  NOT EXISTS (
                                    -- Avoid duplicate PARENT_PENDING rows
                                    SELECT 1 FROM CRM_MPM_CRM_INTEGRATION_LOG
                                    WHERE  REGISTRY_ID      = reg.REGISTRY_ID
                                    AND    SOURCE_RECORD_ID = v_key_val
                                    AND    FINAL_STATUS     = 'PARENT_PENDING');
                            EXCEPTION WHEN OTHERS THEN NULL;
                            END;
                            GOTO next_record;
                        END IF;

                    EXCEPTION
                        WHEN NO_DATA_FOUND THEN
                            -- Parent key not found in source view
                            v_skipped := NVL(v_skipped, 0) + 1;
                            BEGIN
                                INSERT INTO CRM_MPM_CRM_INTEGRATION_LOG (
                                    REGISTRY_ID, ENTITY_NAME, OPERATION_TYPE,
                                    SOURCE_RECORD_ID, FINAL_STATUS,
                                    ERROR_MESSAGE, CREATED_DATE, UPDATED_DATE)
                                SELECT reg.REGISTRY_ID, reg.ENTITY_NAME,
                                       reg.OPERATION_TYPE, v_key_val,
                                       'PARENT_PENDING',
                                       'Parent key column ' || reg.PARENT_LINK_COL
                                       || ' not found in view for key=' || v_key_val,
                                       SYSTIMESTAMP, SYSTIMESTAMP
                                FROM   DUAL
                                WHERE  NOT EXISTS (
                                    SELECT 1 FROM CRM_MPM_CRM_INTEGRATION_LOG
                                    WHERE  REGISTRY_ID      = reg.REGISTRY_ID
                                    AND    SOURCE_RECORD_ID = v_key_val
                                    AND    FINAL_STATUS     = 'PARENT_PENDING');
                            EXCEPTION WHEN OTHERS THEN NULL;
                            END;
                            GOTO next_record;
                        WHEN OTHERS THEN
                            NULL;
                    END;
                END IF;

                BEGIN
                    SEND_TO_APIC(
                        p_registry_id => reg.REGISTRY_ID,
                        p_key_value   => v_key_val,
                        p_attempt_no  => 1,
                        p_log_id_out  => v_log_id
                    );

                    -- FIX: use separate variable v_status instead of reusing v_filter_val
                    SELECT FINAL_STATUS INTO v_status
                    FROM CRM_MPM_CRM_INTEGRATION_LOG
                    WHERE LOG_ID = v_log_id;

                    IF v_status = 'SENT' THEN
                        v_success := v_success + 1;
                        -- ------------------------------------------------
                        -- WATERMARK ADVANCE PER ROW (Fix 3 — crash safety)
                        -- Advance immediately after each successful send so
                        -- a mid-run crash never re-sends already-sent rows.
                        -- v_filter_val holds the SOURCE_FILTER_COL value for
                        -- this row (fetched as VARCHAR2 via DBMS_SQL above).
                        -- ------------------------------------------------
                        BEGIN
                            UPDATE CRM_MPM_API_WATERMARK
                            SET LAST_PROCESSED_TS = TO_TIMESTAMP(v_filter_val,
                                                        'YYYY-MM-DD HH24:MI:SS.FF6'),
                                UPDATED_DATE      = SYSTIMESTAMP
                            WHERE REGISTRY_ID     = reg.REGISTRY_ID
                              AND (LAST_PROCESSED_TS IS NULL
                                   OR LAST_PROCESSED_TS < TO_TIMESTAMP(v_filter_val,
                                                              'YYYY-MM-DD HH24:MI:SS.FF6'));
                        EXCEPTION
                            WHEN OTHERS THEN NULL; -- non-fatal; end-of-loop update covers it
                        END;
                    ELSE
                        v_failed := v_failed + 1;
                    END IF;

                EXCEPTION
                    WHEN OTHERS THEN
                        v_failed := v_failed + 1;
                END;

                <<next_record>>
                NULL; -- GOTO target for dependency skip

            END LOOP;

            DBMS_SQL.CLOSE_CURSOR(v_cursor_id);

            -- Final watermark update (covers edge case where filter_col is
            -- not a parseable TIMESTAMP string — falls back to MAX query).
            BEGIN
                EXECUTE IMMEDIATE
                    'SELECT MAX(' || reg.SOURCE_FILTER_COL || ') FROM ' || reg.SOURCE_VIEW ||
                    ' WHERE ' || reg.SOURCE_FILTER_COL || ' > :wm' ||
                    CASE
                        WHEN reg.SOURCE_EXTRA_FILTER IS NOT NULL
                        THEN ' AND ' || reg.SOURCE_EXTRA_FILTER
                        ELSE ''
                    END
                    INTO v_max_ts
                    USING reg.LAST_PROCESSED_TS;

                IF v_max_ts IS NOT NULL THEN
                    UPDATE CRM_MPM_API_WATERMARK
                    SET LAST_PROCESSED_TS = v_max_ts,
                        LAST_RUN_STATUS   = 'COMPLETED',
                        LAST_RUN_RECORDS  = v_processed,
                        UPDATED_DATE      = SYSTIMESTAMP
                    WHERE REGISTRY_ID = reg.REGISTRY_ID;
                END IF;
            EXCEPTION
                WHEN OTHERS THEN
                    v_err_msg := SQLERRM;
                    UPDATE CRM_MPM_API_WATERMARK
                    SET LAST_RUN_STATUS = 'ERROR: ' || SUBSTR(v_err_msg, 1, 200)
                    WHERE REGISTRY_ID = reg.REGISTRY_ID;
            END;

            COMMIT;
        END LOOP;

        UPDATE CRM_MPM_JOB_RUN_HISTORY
        SET END_TIME         = SYSTIMESTAMP,
            RECORDS_PROCESSED = v_processed,
            RECORDS_SUCCESS   = v_success,
            RECORDS_FAILED    = v_failed,
            STATUS            = 'COMPLETED'
        WHERE RUN_ID = v_run_id;
        COMMIT;

    EXCEPTION
        WHEN OTHERS THEN
            v_err_msg := SQLERRM;
            IF DBMS_SQL.IS_OPEN(v_cursor_id) THEN
                DBMS_SQL.CLOSE_CURSOR(v_cursor_id);
            END IF;
            UPDATE CRM_MPM_JOB_RUN_HISTORY
            SET END_TIME      = SYSTIMESTAMP,
                STATUS        = 'ERROR',
                ERROR_MESSAGE = SUBSTR(v_err_msg, 1, 4000)
            WHERE RUN_ID = v_run_id;
            COMMIT;
            RAISE;
    END RUN_OUTBOUND_JOB;


    /* ====================================================================
       PROCESS_CRM_CALLBACK
       ==================================================================== */
    PROCEDURE PROCESS_CRM_CALLBACK(
        p_service_name     IN  VARCHAR2,
        p_callback_payload IN  CLOB,
        p_result_out       OUT VARCHAR2,   -- full JSON response
        p_status_code      OUT VARCHAR2,   -- 'OK' or 'ERROR'
        p_description      OUT VARCHAR2,   -- human readable description
        p_x_unique_id      IN  VARCHAR2 DEFAULT NULL,
        p_channel_id       IN  VARCHAR2 DEFAULT NULL
    ) IS
        v_crm_reference    VARCHAR2(200);
        v_reg              CRM_MPM_API_REGISTRY%ROWTYPE;
        v_log_id           NUMBER;
        v_final_status     VARCHAR2(20);
        v_error_code       VARCHAR2(30);
        v_callback_message VARCHAR2(4000);
        v_current_status   VARCHAR2(20);
        v_sql              VARCHAR2(1000);
        v_audit_id         NUMBER;  -- row in CRM_MPM_CALLBACK_AUDIT_LOG

        -- ── Write audit row — every callback receives this FIRST ──────────
        PROCEDURE WRITE_AUDIT(
            p_status    IN VARCHAR2,
            p_msg       IN VARCHAR2,
            p_log_id    IN NUMBER   DEFAULT NULL,
            p_response  IN VARCHAR2 DEFAULT NULL,
            p_scode     IN VARCHAR2 DEFAULT NULL,
            p_desc      IN VARCHAR2 DEFAULT NULL
        ) IS
            PRAGMA AUTONOMOUS_TRANSACTION;
        BEGIN
            IF v_audit_id IS NULL THEN
                INSERT INTO CRM_MPM_CALLBACK_AUDIT_LOG (
                    SERVICE_NAME, X_UNIQUE_ID, CHANNEL_ID,
                    REQUEST_ID, STATUS_CODE, RESULT_CODE,
                    PROCESSING_STATUS, PROCESSING_MSG,
                    MATCHED_LOG_ID, RESPONSE_SENT,
                    STATUS_CODE_SENT, DESCRIPTION_SENT,
                    RAW_PAYLOAD
                ) VALUES (
                    p_service_name, p_x_unique_id, p_channel_id,
                    JSON_VALUE(p_callback_payload, '$.request_id'),
                    JSON_VALUE(p_callback_payload, '$.status'),
                    JSON_VALUE(p_callback_payload, '$.processing_result.result_code'),
                    p_status, SUBSTR(p_msg, 1, 500),
                    p_log_id, p_response,
                    p_scode, SUBSTR(p_desc, 1, 500),
                    p_callback_payload
                ) RETURNING AUDIT_ID INTO v_audit_id;
            ELSE
                UPDATE CRM_MPM_CALLBACK_AUDIT_LOG
                SET PROCESSING_STATUS = p_status,
                    PROCESSING_MSG    = SUBSTR(p_msg, 1, 500),
                    MATCHED_LOG_ID    = NVL(p_log_id, MATCHED_LOG_ID),
                    RESPONSE_SENT     = NVL(p_response, RESPONSE_SENT),
                    STATUS_CODE_SENT  = NVL(p_scode,    STATUS_CODE_SENT),
                    DESCRIPTION_SENT  = NVL(SUBSTR(p_desc,1,500), DESCRIPTION_SENT)
                WHERE AUDIT_ID = v_audit_id;
            END IF;
            COMMIT;
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END WRITE_AUDIT;

        -- ── Read callback status code from master table ────────────────
        FUNCTION GET_CB_CODE(p_code IN VARCHAR2) RETURN VARCHAR2 IS
            v_code VARCHAR2(20);
        BEGIN
            SELECT ERROR_CODE INTO v_code
            FROM CRM_MPM_ERROR_CODE_MASTER
            WHERE ERROR_CODE = p_code;
            RETURN v_code;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN RETURN p_code;
            WHEN OTHERS THEN RETURN p_code;
        END GET_CB_CODE;

    BEGIN
        -- ── LEVEL 1: Log receipt immediately ─────────────────────────────
        WRITE_AUDIT('RECEIVED',
            'Callback received from ESB. service=' || NVL(p_service_name,'(null)') ||
            ' x-unique-id=' || NVL(p_x_unique_id,'(null)') ||
            ' channel=' || NVL(p_channel_id,'(null)') ||
            ' payload_len=' || NVL(TO_CHAR(DBMS_LOB.GETLENGTH(p_callback_payload)),'0'));

        -- ── LEVEL 2: Validate service name ───────────────────────────────
        BEGIN
            SELECT * INTO v_reg
            FROM CRM_MPM_API_REGISTRY
            WHERE SERVICE_NAME = p_service_name AND IS_ACTIVE = 'Y';
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                WRITE_AUDIT('FAILED',
                    'Unknown SERVICE_NAME [' || p_service_name || '] — not found in CRM_MPM_API_REGISTRY');
                p_status_code := GET_CB_CODE('CB_1001');
                p_description := 'Unknown SERVICE_NAME [' || p_service_name || ']';
                p_result_out :=
                    '{"status":"ERROR"' ||
                    ',"service_type":"' || NVL(p_service_name,'') || '"' ||
                    ',"message":"Unknown SERVICE_NAME [' || p_service_name || ']"' ||
                    '}';
                WRITE_AUDIT('FAILED', p_description, NULL,
                            p_result_out, p_status_code, p_description);
                RETURN;
        END;

        WRITE_AUDIT('VALIDATING',
            'Registry found. REGISTRY_ID=' || v_reg.REGISTRY_ID ||
            ' Parsing callback JSON...');

        -- Parse callback fields — confirmed JSON contract (6 cases spec):
        -- { "request_id":"...", "status":"0000"/"9999",
        --   "description":"...", "record_type":"...", "record_action":"...",
        --   "message":"...", "callback_timestamp":"...",
        --   "crm_entity_id":"D365-GUID or null",
        --   "processing_result": { "result_code":"SUCCESS/VALIDATION_FAILED/
        --     RECORD_NOT_FOUND/DUPLICATE_RECORD", "result_description":"...",
        --     "validation_errors":[{"field":"","error_code":"","error_message":""}] } }
        -- Spec confirmed: field name is "request_id" (with underscore).
        -- "requestid" (no underscore) was only used during manual Postman testing.
        -- Try spec field name first, fall back to real APIC field name
        v_crm_reference    := JSON_VALUE(p_callback_payload, '$.request_id');
        IF v_crm_reference IS NULL THEN
            v_crm_reference := JSON_VALUE(p_callback_payload, '$.requestid');
        END IF;
        v_callback_message := JSON_VALUE(p_callback_payload, '$.message');

        WRITE_AUDIT('MATCHING',
            'Parsed request_id=' || NVL(v_crm_reference,'(null)') ||
            ' Searching CRM_MPM_CRM_INTEGRATION_LOG by ACK_REQUEST_ID...');

        -- Primary lookup: by ACK_REQUEST_ID = request_id from callback JSON
        BEGIN
            SELECT LOG_ID, FINAL_STATUS INTO v_log_id, v_current_status
            FROM CRM_MPM_CRM_INTEGRATION_LOG
            WHERE REGISTRY_ID    = v_reg.REGISTRY_ID
              AND ACK_REQUEST_ID = v_crm_reference
            ORDER BY LOG_ID DESC
            FETCH FIRST 1 ROW ONLY;

            WRITE_AUDIT('MATCHED',
                'Log row found by ACK_REQUEST_ID. LOG_ID=' || v_log_id ||
                ' current FINAL_STATUS=' || v_current_status, v_log_id);
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                -- request_id not found in ACK_REQUEST_ID column.
                -- NO FALLBACK — we never guess which log row to update.
                -- If request_id is wrong or missing, reject the callback cleanly.
                -- ESB must send the exact request_id returned in LEG 1 ACK.
                WRITE_AUDIT('NO_LOG_MATCH',
                    'No log row found for ACK_REQUEST_ID=' ||
                    NVL(v_crm_reference,'(null)') ||
                    ' SERVICE_NAME=' || p_service_name ||
                    ' — rejected. ESB must send exact request_id from LEG 1 ACK.');
                p_status_code := GET_CB_CODE('CB_1002');
                p_description := 'No matching log entry. request_id=' ||
                    NVL(v_crm_reference,'(null)') ||
                    ' not found for SERVICE_NAME=' || p_service_name;
                p_result_out :=
                    '{"status":"ERROR"' ||
                    ',"service_type":"' || NVL(p_service_name,'') || '"' ||
                    ',"message":"No matching log entry. request_id=' ||
                    NVL(v_crm_reference,'(null)') ||
                    ' not found in ACK_REQUEST_ID for SERVICE_NAME=' ||
                    p_service_name || '. Use exact request_id from LEG 1 ACK response."' ||
                    '}';
                WRITE_AUDIT('NO_LOG_MATCH',
                    'Rejected — response sent to ESB',
                    NULL, p_result_out, p_status_code, p_description);
                RETURN;
        END;

        -- Parse callback JSON body to get result_code and crm_entity_id
        DECLARE
            v_result_code  VARCHAR2(50);
            v_result_desc  VARCHAR2(500);
            v_crm_ent_id   VARCHAR2(200);
            v_valid_errors CLOB;
            v_cb_status    VARCHAR2(10);
        BEGIN
            -- Parse all LEG 2 callback fields per confirmed 6-case spec
            v_cb_status   := JSON_VALUE(p_callback_payload, '$.status');
            v_crm_ent_id  := JSON_VALUE(p_callback_payload, '$.crm_entity_id');
            v_result_code := JSON_VALUE(p_callback_payload, '$.processing_result.result_code');
            v_result_desc := JSON_VALUE(p_callback_payload, '$.processing_result.result_description');

            -- Extract validation_errors array as JSON string for storage
            BEGIN
                SELECT JSON_QUERY(p_callback_payload, '$.processing_result.validation_errors')
                INTO v_valid_errors FROM DUAL;
            EXCEPTION WHEN OTHERS THEN v_valid_errors := NULL;
            END;

            -- Map processing_result.result_code → FINAL_STATUS
            -- This is the authoritative field — top-level status (0000/9999) in LEG 2
            -- only indicates whether D365 processing succeeded or failed broadly.
            -- The specific reason is always in result_code.
            -- CASE 1: result_code=SUCCESS                → FINAL_STATUS=SUCCESS
            -- CASE 2: result_code=VALIDATION_FAILED      → FINAL_STATUS=VALIDATION_FAILED
            -- CASE 3: result_code=RECORD_NOT_FOUND       → FINAL_STATUS=RECORD_NOT_FOUND
            -- CASE 4: result_code=DUPLICATE_RECORD       → FINAL_STATUS=DUPLICATE_RECORD
            -- CASE 5: result_code=INVALID_JSON           → FINAL_STATUS=VALIDATION_FAILED
            -- CASE 6: result_code=CONFIG_NOT_FOUND       → FINAL_STATUS=CRM_REJECTED
            -- CASE 7: result_code=MANDATORY_FIELD_MISSING→ FINAL_STATUS=VALIDATION_FAILED
            -- CASE 8: result_code=PRIMARY_FIELD_MISSING  → FINAL_STATUS=VALIDATION_FAILED
            -- CASE 9: result_code=LOOKUP_VALIDATION_FAILED→ FINAL_STATUS=RECORD_NOT_FOUND
            -- CASE 10:result_code=FAILURE                → FINAL_STATUS=FAILED
           IF v_result_code = 'SUCCESS' OR v_cb_status = '0000' THEN
                v_final_status := 'SUCCESS';
                v_error_code   := 'SUCCESS';
            ELSIF v_cb_status = '9999' AND v_result_code IS NULL THEN
                -- status=9999 with no result_code — CRM failed, record not created
                -- Confirmed by CRM team: 9999 = failure, must retry from Oracle
                v_final_status := 'FAILED';
                v_error_code   := 'FAILURE';
            ELSIF v_result_code = 'VALIDATION_FAILED' THEN
                v_final_status := 'VALIDATION_FAILED';
                v_error_code   := 'VALIDATION_FAILED';

            ELSIF v_result_code = 'RECORD_NOT_FOUND' THEN
                v_final_status := 'RECORD_NOT_FOUND';
                v_error_code   := 'RECORD_NOT_FOUND';

            ELSIF v_result_code = 'DUPLICATE_RECORD' THEN
                v_final_status := 'DUPLICATE_RECORD';
                v_error_code   := 'DUPLICATE_RECORD';
            -- New CRM error codes confirmed by CRM team
            ELSIF v_result_code = 'INVALID_JSON' THEN
                -- Bad JSON payload -- data fix needed, no retry
                v_final_status := 'VALIDATION_FAILED';
                v_error_code   := 'INVALID_JSON';
            ELSIF v_result_code = 'CONFIG_NOT_FOUND' THEN
                -- PxRM integration master missing -- config fix needed
                v_final_status := 'CRM_REJECTED';
                v_error_code   := 'CONFIG_NOT_FOUND';
            ELSIF v_result_code = 'MANDATORY_FIELD_MISSING' THEN
                -- Required field absent in payload -- data fix needed
                v_final_status := 'VALIDATION_FAILED';
                v_error_code   := 'MANDATORY_FIELD_MISSING';
            ELSIF v_result_code = 'PRIMARY_FIELD_MISSING' THEN
                -- Oracle primary key missing in payload -- mapping fix needed
                v_final_status := 'VALIDATION_FAILED';
                v_error_code   := 'PRIMARY_FIELD_MISSING';
            ELSIF v_result_code = 'LOOKUP_VALIDATION_FAILED' THEN
                -- Parent/related record not found in PxRM -- retryable after parent pushed
                v_final_status := 'RECORD_NOT_FOUND';
                v_error_code   := 'LOOKUP_VALIDATION_FAILED';
            ELSIF v_result_code = 'FAILURE' THEN
                -- Generic PostOperation catch -- retryable
                v_final_status := 'FAILED';
                v_error_code   := 'FAILURE';
            ELSE
                -- Unknown result_code — validate against master table
                v_final_status := 'FAILED';

                BEGIN
                    SELECT ERROR_CODE
                    INTO v_error_code
                    FROM CRM_MPM_ERROR_CODE_MASTER
                    WHERE ERROR_CODE = NVL(v_result_code,'UNKNOWN_ERROR');
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        v_error_code := 'UNKNOWN_ERROR';
                END;
            END IF;

            -- ----------------------------------------------------------------
            -- 9999 OVERRIDE: CRM team confirmed status=9999 means record was
            -- NOT created in PxRM regardless of result_code.
            -- Therefore ALL 9999 responses must be retried from Oracle EXCEPT
            -- DUPLICATE_RECORD (record already exists — retry is pointless).
            -- This override runs AFTER result_code mapping so error_code
            -- still captures the specific reason for the failure.
            -- ----------------------------------------------------------------
            IF v_cb_status = '9999'
               AND NVL(v_result_code,'x') != 'DUPLICATE_RECORD'
               AND NVL(v_final_status,'x') != 'SUCCESS' THEN
                v_final_status := 'FAILED';
                -- Keep v_error_code as-is so specific reason is preserved
                -- e.g. MANDATORY_FIELD_MISSING stays as error code
                -- but FINAL_STATUS=FAILED means retry job picks it up
            END IF;

            -- Store crm_entity_id and validation_errors via additional UPDATE
            UPDATE CRM_MPM_CRM_INTEGRATION_LOG
            SET CRM_ENTITY_ID          = v_crm_ent_id,
                CALLBACK_RESULT_CODE   = v_result_code,
                CALLBACK_RESULT_DESC   = v_result_desc,
                CALLBACK_VALID_ERRORS  = v_valid_errors
            WHERE LOG_ID = v_log_id;
        END;

        UPDATE CRM_MPM_CRM_INTEGRATION_LOG
        SET CRM_REFERENCE_NO        = NVL(CRM_REFERENCE_NO, v_crm_reference),
            FINAL_STATUS            = v_final_status,
            ERROR_CODE              = v_error_code,
            ERROR_MESSAGE           = v_callback_message,
            CALLBACK_PAYLOAD        = p_callback_payload,
            CALLBACK_DATE           = SYSTIMESTAMP,
            CALLBACK_X_UNIQUE_ID    = p_x_unique_id,
            CALLBACK_CHANNEL_ID     = p_channel_id,
            IS_FINAL_ATTEMPT        = CASE WHEN v_final_status IN ('SUCCESS','ALREADY_PROCESSED')
                                          THEN 'Y' ELSE IS_FINAL_ATTEMPT END,
            UPDATED_DATE            = SYSTIMESTAMP
        WHERE LOG_ID = v_log_id;

        DECLARE
            v_source_rec_id VARCHAR2(4000);
        BEGIN
            SELECT SOURCE_RECORD_ID INTO v_source_rec_id
            FROM CRM_MPM_CRM_INTEGRATION_LOG
            WHERE LOG_ID = v_log_id;

            IF v_reg.POST_CALLBACK_PROC IS NOT NULL THEN
                -- Custom post-callback procedure defined — call it
                v_sql := 'BEGIN ' || v_reg.POST_CALLBACK_PROC ||
                         '(:p_key, :p_status, :p_ref, :p_errcode, :p_errmsg); END;';
                EXECUTE IMMEDIATE v_sql
                    USING v_source_rec_id, v_final_status, v_crm_reference,
                          v_error_code, v_callback_message;

            ELSIF v_reg.CALLBACK_TARGET_TABLE IS NOT NULL
              AND v_reg.CALLBACK_STATUS_COL   IS NOT NULL
              AND v_reg.CALLBACK_REF_COL      IS NOT NULL
              AND v_reg.CALLBACK_KEY_COL      IS NOT NULL
            THEN
                -- Update entity table with CRM sync status — only if table is configured
                -- and actually exists. Skip gracefully if table does not exist yet.
                BEGIN
                    v_sql := 'UPDATE ' || v_reg.CALLBACK_TARGET_TABLE ||
                             ' SET ' || v_reg.CALLBACK_STATUS_COL || ' = :p_status, ' ||
                                        v_reg.CALLBACK_REF_COL    || ' = :p_ref '     ||
                             ' WHERE ' || v_reg.CALLBACK_KEY_COL  || ' = :p_key';
                    EXECUTE IMMEDIATE v_sql
                        USING v_final_status, v_crm_reference, v_source_rec_id;
                EXCEPTION
                    WHEN OTHERS THEN
                        -- Table does not exist or column missing — log and continue.
                        -- The integration log (CRM_MPM_CRM_INTEGRATION_LOG) is already
                        -- updated above. The entity table update is optional.
                        NULL;
                END;
            END IF;
            -- If no callback table configured at all — skip silently.
            -- CRM_MPM_CRM_INTEGRATION_LOG already has the full result.
        END;

        COMMIT;

        -- Return full JSON response to ESB
        DECLARE
            v_crm_ent_id_out VARCHAR2(200);
        BEGIN
            SELECT NVL(CRM_ENTITY_ID,'')
            INTO v_crm_ent_id_out
            FROM CRM_MPM_CRM_INTEGRATION_LOG
            WHERE LOG_ID = v_log_id;

            p_result_out :=
                '{"status":"OK"' ||
                ',"service_type":"'          || p_service_name       || '"' ||
                ',"log_id":'                 || v_log_id                    ||
                ',"final_status":"'          || v_final_status        || '"' ||
                ',"request_id":"'            || NVL(v_crm_reference,'') || '"' ||
                ',"crm_entity_id":"'         || v_crm_ent_id_out     || '"' ||
                ',"callback_result_code":"'  || NVL(v_final_status,'') || '"' ||
                '}';
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                p_result_out :=
                    '{"status":"OK"' ||
                    ',"service_type":"'         || p_service_name       || '"' ||
                    ',"log_id":'                || v_log_id                    ||
                    ',"final_status":"'         || v_final_status        || '"' ||
                    ',"request_id":"'           || NVL(v_crm_reference,'') || '"' ||
                    ',"crm_entity_id":""'                                       ||
                    ',"callback_result_code":"' || NVL(v_final_status,'') || '"' ||
                    '}';
        END;

        -- Set simple OUT params for ESB alongside full JSON
        p_status_code := GET_CB_CODE('CB_0000');
        p_description := 'Callback processed successfully. FINAL_STATUS=' ||
                         v_final_status || ' LOG_ID=' || TO_CHAR(v_log_id) ||
                         ' SERVICE=' || p_service_name;

        -- Write final audit AFTER p_result_out is built — stores exact response sent to ESB
        WRITE_AUDIT('PROCESSED',
            'Callback fully processed. FINAL_STATUS=' || v_final_status ||
            ' LOG_ID=' || v_log_id, v_log_id, p_result_out,
            p_status_code, p_description);

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_status_code := GET_CB_CODE('CB_1003');
            p_description := 'Unhandled exception: ' || SUBSTR(SQLERRM,1,200);
            p_result_out :=
                '{"status":"ERROR"' ||
                ',"service_type":"' || NVL(p_service_name,'') || '"' ||
                ',"message":"'      || REPLACE(SQLERRM,'"','''') || '"' ||
                '}';
            WRITE_AUDIT('FAILED',
                'Unhandled exception: ' || REPLACE(SQLERRM,'"',''''),
                NULL, p_result_out, p_status_code, p_description);
    END PROCESS_CRM_CALLBACK;


    /* ====================================================================
       RUN_TIMEOUT_JOB
       ==================================================================== */
    PROCEDURE RUN_TIMEOUT_JOB IS
        -- FIX: Declare an explicit named cursor — implicit FOR loop cursors over
        --      views can raise PLS-00364 and ORA-00904 when their columns are
        --      referenced in DML or assignments inside the loop body.
        -- Query joins LOG directly to REGISTRY to get MAX_RETRY_COUNT.
        CURSOR c_timeout IS
            SELECT t.LOG_ID,
                   t.REGISTRY_ID,
                   t.RETRY_COUNT,
                   r.MAX_RETRY_COUNT,
                   r.RETRY_INTERVAL_MINUTES
            FROM CRM_MPM_CRM_INTEGRATION_LOG t
            JOIN CRM_MPM_API_REGISTRY        r ON r.REGISTRY_ID = t.REGISTRY_ID
            WHERE t.FINAL_STATUS IN ('SENT','PENDING')
              AND t.SENT_DATE    < SYSTIMESTAMP - (r.TIMEOUT_MINUTES / 1440)
              AND r.IS_ACTIVE    = 'Y';

        v_run_id      NUMBER;
        v_count       NUMBER  := 0;
        -- Scalar locals populated from each fetched row
        v_log_id      NUMBER;
        v_retry_count    NUMBER;
        v_max_retry      NUMBER;
        v_reg_id         NUMBER;
        v_retry_interval NUMBER;
        v_err_msg     VARCHAR2(4000);
    BEGIN
        INSERT INTO CRM_MPM_JOB_RUN_HISTORY (JOB_NAME, STATUS)
        VALUES ('TIMEOUT_JOB', 'RUNNING')
        RETURNING RUN_ID INTO v_run_id;
        COMMIT;

        -- FIX: OPEN/FETCH/CLOSE pattern — no PLS-00364 risk
        OPEN c_timeout;
        LOOP
            FETCH c_timeout
            INTO v_log_id, v_reg_id, v_retry_count, v_max_retry, v_retry_interval;
            EXIT WHEN c_timeout%NOTFOUND;

            UPDATE CRM_MPM_CRM_INTEGRATION_LOG
            SET FINAL_STATUS     = 'TIMEOUT',
                ERROR_CODE       = 'TIMEOUT',
                ERROR_MESSAGE    = 'No callback received within configured timeout window',
                IS_FINAL_ATTEMPT = CASE WHEN v_retry_count >= v_max_retry THEN 'Y' ELSE 'N' END,
                UPDATED_DATE     = SYSTIMESTAMP
            WHERE LOG_ID = v_log_id;

            IF v_retry_count >= v_max_retry THEN
                UPDATE CRM_MPM_CRM_INTEGRATION_LOG
                SET FINAL_STATUS = 'EXHAUSTED',
                    ERROR_CODE   = 'EXHAUSTED',
                    -- Confirmed 18-Sep-2026: EXHAUSTED is terminal, no further retry
                    IS_FINAL_ATTEMPT = 'Y'
                WHERE LOG_ID = v_log_id;
            END IF;

            v_count := v_count + 1;
        END LOOP;
        CLOSE c_timeout;

        UPDATE CRM_MPM_JOB_RUN_HISTORY
        SET END_TIME          = SYSTIMESTAMP,
            RECORDS_PROCESSED = v_count,
            STATUS            = 'COMPLETED'
        WHERE RUN_ID = v_run_id;

        COMMIT;

    EXCEPTION
        WHEN OTHERS THEN
            v_err_msg := SQLERRM;
            IF c_timeout%ISOPEN THEN CLOSE c_timeout; END IF;
            UPDATE CRM_MPM_JOB_RUN_HISTORY
            SET END_TIME      = SYSTIMESTAMP,
                STATUS        = 'ERROR',
                ERROR_MESSAGE = SUBSTR(v_err_msg, 1, 4000)
            WHERE RUN_ID = v_run_id;
            COMMIT;
            RAISE;
    END RUN_TIMEOUT_JOB;


    /* ====================================================================
       RUN_RETRY_JOB
       UNKNOWN_ERROR added 18-Sep-2026 — retryable per CRM team confirmation
       ==================================================================== */
    PROCEDURE RUN_RETRY_JOB IS
        v_run_id      NUMBER;
        v_processed   NUMBER := 0;
        v_success     NUMBER := 0;
        v_failed      NUMBER := 0;
        v_log_id_new  NUMBER;
        v_status      VARCHAR2(20);
        -- FIX: capture SQLERRM
        v_err_msg     VARCHAR2(4000);
    BEGIN
        INSERT INTO CRM_MPM_JOB_RUN_HISTORY (JOB_NAME, STATUS)
        VALUES ('RETRY_JOB', 'RUNNING')
        RETURNING RUN_ID INTO v_run_id;
        COMMIT;

        FOR rec IN (
            SELECT L.LOG_ID, L.REGISTRY_ID, L.SOURCE_RECORD_ID,
                   L.RETRY_COUNT, L.TRANSACTION_GROUP_ID,
                   L.ATTEMPT_NO,
                   R.MAX_RETRY_COUNT, R.RETRY_INTERVAL_MINUTES
            FROM CRM_MPM_CRM_INTEGRATION_LOG L
            JOIN CRM_MPM_API_REGISTRY         R ON R.REGISTRY_ID = L.REGISTRY_ID
            --WHERE L.FINAL_STATUS    IN ('FAILED','TIMEOUT')
            WHERE L.FINAL_STATUS IN ('FAILED','TIMEOUT','UNKNOWN_ERROR')
              AND L.RETRY_COUNT     <  R.MAX_RETRY_COUNT
              AND L.IS_FINAL_ATTEMPT = 'N'
              AND (L.NEXT_RETRY_DATE IS NULL OR L.NEXT_RETRY_DATE <= SYSTIMESTAMP)
              AND R.IS_ACTIVE = 'Y'
              -- KEY FIX: only retry transient errors, not permanent business failures
              AND EXISTS (
                   SELECT 1
                   FROM   CRM_MPM_ERROR_CODE_MASTER e
                   WHERE  e.ERROR_CODE   = L.ERROR_CODE
                   AND    e.IS_RETRYABLE = 'Y'
               )
          ) LOOP

            v_processed := v_processed + 1;

            BEGIN

                UPDATE CRM_MPM_CRM_INTEGRATION_LOG
                SET RETRY_COUNT = RETRY_COUNT +1,
                    UPDATED_DATE = SYSTIMESTAMP
                WHERE LOG_ID = rec.LOG_ID;

                IF rec.RETRY_COUNT + 1 >= rec.MAX_RETRY_COUNT THEN
                    UPDATE CRM_MPM_CRM_INTEGRATION_LOG
                    SET IS_FINAL_ATTEMPT = 'Y'
                    WHERE LOG_ID = rec.LOG_ID;
                END IF;

                SEND_TO_APIC(
                    p_registry_id          => rec.REGISTRY_ID,
                    p_key_value            => rec.SOURCE_RECORD_ID,
                    p_transaction_group_id => rec.TRANSACTION_GROUP_ID,
                    p_attempt_no           => rec.ATTEMPT_NO + 1,
                    p_log_id_out           => v_log_id_new
                );

                UPDATE CRM_MPM_CRM_INTEGRATION_LOG
                SET NEXT_RETRY_DATE  = SYSTIMESTAMP + (rec.RETRY_INTERVAL_MINUTES / 1440),
                    RETRY_COUNT      = rec.RETRY_COUNT + 1,
                    IS_FINAL_ATTEMPT = CASE WHEN rec.RETRY_COUNT + 1 >= rec.MAX_RETRY_COUNT
                                           THEN 'Y' ELSE 'N' END
                WHERE LOG_ID = v_log_id_new;

                SELECT FINAL_STATUS INTO v_status
                FROM CRM_MPM_CRM_INTEGRATION_LOG
                WHERE LOG_ID = v_log_id_new;

                IF v_status = 'SENT' THEN
                    v_success := v_success + 1;
                ELSE
                    v_failed := v_failed + 1;
                    IF rec.RETRY_COUNT + 1 >= rec.MAX_RETRY_COUNT THEN
                        UPDATE CRM_MPM_CRM_INTEGRATION_LOG
                        SET FINAL_STATUS = 'EXHAUSTED',
                            ERROR_CODE   = 'EXHAUSTED',
                            IS_FINAL_ATTEMPT = 'Y'
                        WHERE LOG_ID = v_log_id_new;
                    END IF;
                END IF;

                COMMIT;

            EXCEPTION
                WHEN OTHERS THEN
--                    v_failed := v_failed + 1;
--                    NULL;
                    v_err_msg := SQLERRM;
                    v_failed := v_failed + 1;
                    ROLLBACK;
            END;
        END LOOP; 

        UPDATE CRM_MPM_JOB_RUN_HISTORY
        SET END_TIME          = SYSTIMESTAMP,
            RECORDS_PROCESSED = v_processed,
            RECORDS_SUCCESS   = v_success,
            RECORDS_FAILED    = v_failed,
            STATUS            = 'COMPLETED'
        WHERE RUN_ID = v_run_id;

        COMMIT;

    EXCEPTION
        WHEN OTHERS THEN
            v_err_msg := SQLERRM;
            UPDATE CRM_MPM_JOB_RUN_HISTORY
            SET END_TIME      = SYSTIMESTAMP,
                STATUS        = 'ERROR',
                ERROR_MESSAGE = SUBSTR(v_err_msg, 1, 4000)
            WHERE RUN_ID = v_run_id;
            COMMIT;
            RAISE;
    END RUN_RETRY_JOB;

    /* ====================================================================
       SUBMIT_TO_STAGING
       Oracle team calls this. Inserts into staging + instant push.
       If push fails, RUN_STAGING_JOB retries up to 3 times.
       ==================================================================== */
    PROCEDURE SUBMIT_TO_STAGING(
        p_service_name      IN  VARCHAR2,
        p_source_record_id  IN  VARCHAR2,
        p_json_payload      IN  CLOB,
        p_staging_id_out    OUT NUMBER,
        p_status_out        OUT VARCHAR2
    ) IS
        v_staging_id    NUMBER;
        v_reg           CRM_MPM_API_REGISTRY%ROWTYPE;
        v_token         VARCHAR2(4000);
        v_unique_id     VARCHAR2(60);
        v_txn_group     VARCHAR2(40);
        v_wallet_path   VARCHAR2(200);
        v_wallet_pwd    VARCHAR2(200);
        v_status_code   VARCHAR2(10);
        v_response      CLOB;
        v_request_id    VARCHAR2(200);
        v_err_msg       VARCHAR2(4000);
    BEGIN
        -- Validate service exists
        SELECT * INTO v_reg
        FROM   CRM_MPM_API_REGISTRY
        WHERE  SERVICE_NAME = p_service_name
        AND    IS_ACTIVE    = 'Y';

        -- Insert into staging as PENDING
        v_staging_id := SEQ_CRM_STAGING.NEXTVAL;

        INSERT INTO CRM_MPM_OUTBOUND_STAGING (
            STAGING_ID, SERVICE_NAME, SOURCE_RECORD_ID,
            JSON_PAYLOAD, STATUS, ATTEMPT_NO, MAX_ATTEMPTS,
            CREATED_DATE, LAST_UPDATED, CREATED_BY
        ) VALUES (
            v_staging_id, p_service_name, p_source_record_id,
            p_json_payload, 'PENDING', 0, 3,
            SYSDATE, SYSDATE, USER
        );
        COMMIT;

        p_staging_id_out := v_staging_id;

        -- -------------------------------------------------------
        -- INSTANT PUSH
        -- -------------------------------------------------------
        BEGIN
			v_unique_id  := GENERATE_UNIQUE_ID();

            UPDATE CRM_MPM_OUTBOUND_STAGING
            SET    STATUS      = 'SENDING',X_UNIQUE_ID = v_unique_id,
                   ATTEMPT_NO  = 1,
                   LAST_UPDATED = SYSDATE
            WHERE  STAGING_ID  = v_staging_id;
            COMMIT;

            v_token      := GET_BEARER_TOKEN(v_reg.CRED_CODE);

            v_txn_group  := NEW_GUID();

            BEGIN
                SELECT WALLET_PATH, WALLET_PASSWORD
                INTO   v_wallet_path, v_wallet_pwd
                FROM   CRM_MPM_API_CREDENTIALS
                WHERE  CRED_CODE = v_reg.CRED_CODE;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    v_wallet_path := NULL;
                    v_wallet_pwd  := NULL;
            END;

            SEND_PAYLOAD_TO_APIC(
                p_endpoint    => v_reg.APIC_ENDPOINT_URL,
                p_http_method => v_reg.HTTP_METHOD,
                p_token       => v_token,
                p_wallet_path => v_wallet_path,
                p_wallet_pwd  => v_wallet_pwd,
                p_txn_group   => v_txn_group,
                p_unique_id   => v_unique_id,
                p_rec_type    => v_reg.RECORD_TYPE_HDR,
                p_rec_action  => v_reg.EVENT_CODE_HDR,
                p_api_version => v_reg.APIC_API_VERSION,
                p_payload     => p_json_payload,
                p_status_code => v_status_code,
                p_response    => v_response
            );

            -- Parse request_id from ACK
            IF v_status_code BETWEEN '200' AND '299' THEN
                v_request_id := JSON_VALUE(v_response, '$.request_id');
                IF v_request_id IS NULL THEN
                    v_request_id := JSON_VALUE(v_response, '$.requestid');
                END IF;
            END IF;

            UPDATE CRM_MPM_OUTBOUND_STAGING
            SET    STATUS           = CASE WHEN v_status_code BETWEEN '200' AND '299'
                                           THEN 'SENT' ELSE 'FAILED' END,
                   HTTP_STATUS_CODE = v_status_code,
                   REQUEST_ID       = v_request_id,
                   SENT_DATE        = SYSDATE,
                   LAST_UPDATED     = SYSDATE,
                   ERROR_MESSAGE    = CASE WHEN v_status_code NOT BETWEEN '200' AND '299'
                                           THEN DBMS_LOB.SUBSTR(v_response, 4000, 1)
                                           ELSE NULL END
            WHERE  STAGING_ID = v_staging_id;

			INSERT INTO CRM_MPM_CRM_INTEGRATION_LOG (
				REGISTRY_ID, ENTITY_NAME, OPERATION_TYPE,
				SOURCE_RECORD_ID, TRANSACTION_GROUP_ID,
				ATTEMPT_NO, REQUEST_PAYLOAD, ACK_RESPONSE,
				ACK_REQUEST_ID, HTTP_STATUS_CODE,
				SENT_DATE, FINAL_STATUS,
				ERROR_CODE, ERROR_MESSAGE, X_UNIQUE_ID
			) VALUES (
            v_reg.REGISTRY_ID, v_reg.ENTITY_NAME, v_reg.OPERATION_TYPE,
            p_source_record_id, v_txn_group,
            1, p_json_payload, v_response,
            v_request_id, v_status_code,
				SYSTIMESTAMP,
				CASE WHEN v_status_code BETWEEN '200' AND '299'
					 THEN 'SENT' ELSE 'FAILED' END,
				CASE WHEN v_status_code NOT BETWEEN '200' AND '299'
					 THEN 'APIC_ERROR' ELSE NULL END,
				CASE WHEN v_status_code NOT BETWEEN '200' AND '299'
					 THEN DBMS_LOB.SUBSTR(v_response, 4000, 1) ELSE NULL END,
				v_unique_id
			);


            COMMIT;

            p_status_out := CASE WHEN v_status_code BETWEEN '200' AND '299'
                                 THEN 'SENT'
                                 ELSE 'FAILED-RETRY-SCHEDULED' END;

        EXCEPTION
            WHEN OTHERS THEN
                v_err_msg := SQLERRM;
                ROLLBACK;
                UPDATE CRM_MPM_OUTBOUND_STAGING
                SET    STATUS        = 'FAILED',
                       ERROR_MESSAGE = SUBSTR(v_err_msg, 1, 4000),
                       LAST_UPDATED  = SYSDATE
                WHERE  STAGING_ID   = v_staging_id;
                COMMIT;
                p_status_out := 'FAILED-RETRY-SCHEDULED';
        END;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_staging_id_out := NULL;
            p_status_out     := 'ERROR: Service [' || p_service_name || '] not found or inactive';
        WHEN OTHERS THEN
            ROLLBACK;
            p_staging_id_out := NULL;
            p_status_out     := 'ERROR: ' || SQLERRM;
    END SUBMIT_TO_STAGING;


    /* ====================================================================
       RUN_STAGING_JOB
       Scheduler retries FAILED staging records up to MAX_ATTEMPTS
       ==================================================================== */
    PROCEDURE RUN_STAGING_JOB IS
        v_token       VARCHAR2(4000);
        v_unique_id   VARCHAR2(60);
        v_txn_group   VARCHAR2(40);
        v_wallet_path VARCHAR2(200);
        v_wallet_pwd  VARCHAR2(200);
        v_status_code VARCHAR2(10);
        v_response    CLOB;
        v_request_id  VARCHAR2(200);
        v_err_msg     VARCHAR2(4000);
    BEGIN
        FOR rec IN (
            SELECT s.STAGING_ID, s.SERVICE_NAME, s.JSON_PAYLOAD,
                   s.ATTEMPT_NO, s.MAX_ATTEMPTS,
                   r.APIC_ENDPOINT_URL, r.HTTP_METHOD,
                   r.RECORD_TYPE_HDR, r.EVENT_CODE_HDR,
                   r.APIC_API_VERSION, r.CRED_CODE
            FROM   CRM_MPM_OUTBOUND_STAGING  s
            JOIN   CRM_MPM_API_REGISTRY      r
                ON r.SERVICE_NAME = s.SERVICE_NAME
               AND r.IS_ACTIVE    = 'Y'
            WHERE  s.STATUS     = 'FAILED'
            AND    s.ATTEMPT_NO  < s.MAX_ATTEMPTS
            ORDER  BY s.CREATED_DATE
        ) LOOP
            BEGIN
                UPDATE CRM_MPM_OUTBOUND_STAGING
                SET STATUS       = 'SENDING',
                    ATTEMPT_NO   = ATTEMPT_NO + 1,
                    LAST_UPDATED = SYSDATE
                WHERE STAGING_ID = rec.STAGING_ID;
                COMMIT;

                v_token     := GET_BEARER_TOKEN(rec.CRED_CODE);
                v_unique_id := GENERATE_UNIQUE_ID();
                v_txn_group := NEW_GUID();

                BEGIN
                    SELECT WALLET_PATH, WALLET_PASSWORD
                    INTO   v_wallet_path, v_wallet_pwd
                    FROM   CRM_MPM_API_CREDENTIALS
                    WHERE  CRED_CODE = rec.CRED_CODE;
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        v_wallet_path := NULL;
                        v_wallet_pwd  := NULL;
                END;

                SEND_PAYLOAD_TO_APIC(
                    p_endpoint    => rec.APIC_ENDPOINT_URL,
                    p_http_method => rec.HTTP_METHOD,
                    p_token       => v_token,
                    p_wallet_path => v_wallet_path,
                    p_wallet_pwd  => v_wallet_pwd,
                    p_txn_group   => v_txn_group,
                    p_unique_id   => v_unique_id,
                    p_rec_type    => rec.RECORD_TYPE_HDR,
                    p_rec_action  => rec.EVENT_CODE_HDR,
                    p_api_version => rec.APIC_API_VERSION,
                    p_payload     => rec.JSON_PAYLOAD,
                    p_status_code => v_status_code,
                    p_response    => v_response
                );

                IF v_status_code BETWEEN '200' AND '299' THEN
                    v_request_id := JSON_VALUE(v_response, '$.request_id');
                    IF v_request_id IS NULL THEN
                        v_request_id := JSON_VALUE(v_response, '$.requestid');
                    END IF;
                END IF;

                UPDATE CRM_MPM_OUTBOUND_STAGING
                SET STATUS           = CASE WHEN v_status_code BETWEEN '200' AND '299'
                                           THEN 'SENT' ELSE 'FAILED' END,
                    HTTP_STATUS_CODE = v_status_code,
                    REQUEST_ID       = v_request_id,
					X_UNIQUE_ID = v_unique_id,
                    SENT_DATE        = SYSDATE,
                    LAST_UPDATED     = SYSDATE,
                    ERROR_MESSAGE    = CASE WHEN v_status_code NOT BETWEEN '200' AND '299'
                                           THEN DBMS_LOB.SUBSTR(v_response, 4000, 1)
                                           ELSE NULL END
                WHERE STAGING_ID = rec.STAGING_ID;
                COMMIT;

            EXCEPTION
                WHEN OTHERS THEN
                    v_err_msg := SQLERRM;
                    ROLLBACK;
                    UPDATE CRM_MPM_OUTBOUND_STAGING
                    SET STATUS        = 'FAILED',
                        ERROR_MESSAGE = SUBSTR(v_err_msg, 1, 4000),
                        LAST_UPDATED  = SYSDATE
                    WHERE STAGING_ID  = rec.STAGING_ID;
                    COMMIT;
            END;
        END LOOP;
    EXCEPTION
        WHEN OTHERS THEN NULL; -- job must never crash scheduler
    END RUN_STAGING_JOB;


    /* ====================================================================
       PROCESS_STAGING_CALLBACK
       ESB calls this for LEG 2 on staging-submitted records
       ==================================================================== */
    PROCEDURE PROCESS_STAGING_CALLBACK(
        p_request_id        IN  VARCHAR2,
        p_crm_reference     IN  VARCHAR2,
        p_callback_status   IN  VARCHAR2,
        p_status_out        OUT VARCHAR2
    ) IS
        v_staging_id NUMBER;
    BEGIN
        SELECT STAGING_ID INTO v_staging_id
        FROM   CRM_MPM_OUTBOUND_STAGING
        WHERE  REQUEST_ID = p_request_id
        AND    ROWNUM     = 1;

        UPDATE CRM_MPM_OUTBOUND_STAGING
        SET    STATUS             = 'COMPLETED',
               CRM_REFERENCE     = p_crm_reference,
               CALLBACK_STATUS   = p_callback_status,
               CALLBACK_RECEIVED = SYSDATE,
               LAST_UPDATED      = SYSDATE
        WHERE  STAGING_ID = v_staging_id;
        COMMIT;

        p_status_out := 'SUCCESS';

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_status_out := 'ERROR: No staging record found for request_id=' || p_request_id;
        WHEN OTHERS THEN
            ROLLBACK;
            p_status_out := 'ERROR: ' || SQLERRM;
    END PROCESS_STAGING_CALLBACK;

     /* ====================================================================
       RUN_UNIT_UNAVAILABLE_BATCH
       Batch running
       ==================================================================== */

    PROCEDURE RUN_UNIT_UNAVAILABLE_BATCH IS 
        v_reg            CRM_MPM_API_REGISTRY%ROWTYPE;
        v_token          VARCHAR2(4000);
        v_wallet_path    VARCHAR2(200);
        v_wallet_pwd     VARCHAR2(200);
        v_batch_size     NUMBER;
        v_err_msg        VARCHAR2(4000);
        v_cursor_id      INTEGER;
        v_sql            VARCHAR2(500);
        v_rec_count      NUMBER := 0;
        v_total          NUMBER;
        v_start          NUMBER;
        v_end            NUMBER;
        v_batch_num      NUMBER;

        -- Record type to hold all 3 columns
        TYPE t_unit_rec IS RECORD (
            unit_code     VARCHAR2(200),
            customer_id   VARCHAR2(200),
            customer_name VARCHAR2(500)
        );
        TYPE t_unit_tab IS TABLE OF t_unit_rec INDEX BY PLS_INTEGER;
        v_units       t_unit_tab;
        v_unit_code   VARCHAR2(200);
        v_cust_id     VARCHAR2(200);
        v_cust_name   VARCHAR2(500);

        -- Send one batch
        PROCEDURE SEND_BATCH(
            p_batch_num IN NUMBER,
            p_start     IN NUMBER,
            p_end       IN NUMBER
        ) IS
            v_batch_payload  CLOB;
            v_batch_status   VARCHAR2(10);
            v_batch_response CLOB;
            v_batch_unique   VARCHAR2(60);
            v_batch_txn      VARCHAR2(40);
            v_batch_log_id   NUMBER;
            v_batch_req_id   VARCHAR2(200);
            v_batch_id_str   VARCHAR2(100);
            v_unit_json      VARCHAR2(1000);
        BEGIN
            v_batch_id_str := 'UNAVAIL_BATCH_' ||
                              TO_CHAR(SYSDATE,'YYYYMMDD_HH24MI') ||
                              '_' || LPAD(TO_CHAR(p_batch_num),3,'0');
            v_batch_unique  := GENERATE_UNIQUE_ID();
            v_batch_txn     := NEW_GUID();

            -- Build JSON array for this batch
            DBMS_LOB.CREATETEMPORARY(v_batch_payload, TRUE);
            DBMS_LOB.WRITEAPPEND(v_batch_payload, 1, '[');

            FOR i IN p_start..p_end LOOP
                IF i > p_start THEN
                    DBMS_LOB.WRITEAPPEND(v_batch_payload, 1, ',');
                END IF;

                -- Build nested JSON with tenantaccount object
                v_unit_json :=
                    '{"unitid":"'         || NVL(v_units(i).unit_code,'')   || '"'  ||
                    ',"tenantaccount":{'  ||
                    '"tenantaccount_id":"'|| NVL(v_units(i).customer_id,'') || '"'  ||
                    ',"tenantaccount_name":"' ||
                        REPLACE(NVL(v_units(i).customer_name,''),'"','\"')   || '"'  ||
                    '}}';

                DBMS_LOB.WRITEAPPEND(v_batch_payload,
                                     LENGTH(v_unit_json), v_unit_json);
            END LOOP;

            DBMS_LOB.WRITEAPPEND(v_batch_payload, 1, ']');

            -- Insert log record
            INSERT INTO CRM_MPM_CRM_INTEGRATION_LOG (
                REGISTRY_ID, ENTITY_NAME, OPERATION_TYPE,
                SOURCE_RECORD_ID, TRANSACTION_GROUP_ID,
                ATTEMPT_NO, REQUEST_PAYLOAD,
                SENT_DATE, FINAL_STATUS, X_UNIQUE_ID
            ) VALUES (
                v_reg.REGISTRY_ID, v_reg.ENTITY_NAME, v_reg.OPERATION_TYPE,
                v_batch_id_str, v_batch_txn,
                1, v_batch_payload,
                SYSTIMESTAMP, 'PENDING', v_batch_unique
            ) RETURNING LOG_ID INTO v_batch_log_id;
            COMMIT;

            -- Send to APIC
            SEND_PAYLOAD_TO_APIC(
                p_endpoint    => v_reg.APIC_ENDPOINT_URL,
                p_http_method => v_reg.HTTP_METHOD,
                p_token       => v_token,
                p_wallet_path => v_wallet_path,
                p_wallet_pwd  => v_wallet_pwd,
                p_txn_group   => v_batch_txn,
                p_unique_id   => v_batch_unique,
                p_rec_type    => v_reg.RECORD_TYPE_HDR,
                p_rec_action  => v_reg.EVENT_CODE_HDR,
                p_api_version => v_reg.APIC_API_VERSION,
                p_payload     => v_batch_payload,
                p_status_code => v_batch_status,
                p_response    => v_batch_response
            );

            -- Parse request_id
            IF v_batch_status BETWEEN '200' AND '299' THEN
                v_batch_req_id := JSON_VALUE(v_batch_response, '$.request_id');
                IF v_batch_req_id IS NULL THEN
                    v_batch_req_id := JSON_VALUE(v_batch_response, '$.requestid');
                END IF;
            END IF;

            -- Update log
            UPDATE CRM_MPM_CRM_INTEGRATION_LOG
            SET HTTP_STATUS_CODE = v_batch_status,
                ACK_RESPONSE     = v_batch_response,
                ACK_REQUEST_ID   = v_batch_req_id,
                FINAL_STATUS     = CASE WHEN v_batch_status BETWEEN '200' AND '299'
                                        THEN 'SENT' ELSE 'FAILED' END,
                ERROR_CODE       = CASE WHEN v_batch_status NOT BETWEEN '200' AND '299'
                                        THEN 'APIC_ERROR' ELSE NULL END,
                ERROR_MESSAGE    = CASE WHEN v_batch_status NOT BETWEEN '200' AND '299'
                                        THEN DBMS_LOB.SUBSTR(v_batch_response,4000,1)
                                        ELSE NULL END,
                UPDATED_DATE     = SYSTIMESTAMP
            WHERE LOG_ID = v_batch_log_id;
            COMMIT;

            DBMS_LOB.FREETEMPORARY(v_batch_payload);

            DBMS_OUTPUT.PUT_LINE(
                'Batch ' || p_batch_num ||
                ' (' || (p_end - p_start + 1) || ' units): ' ||
                CASE WHEN v_batch_status BETWEEN '200' AND '299'
                     THEN 'SENT OK'
                     ELSE 'FAILED HTTP ' || v_batch_status END
            );

        EXCEPTION
            WHEN OTHERS THEN
                v_err_msg := SQLERRM;
                UPDATE CRM_MPM_CRM_INTEGRATION_LOG
                SET FINAL_STATUS  = 'FAILED',
                    ERROR_CODE    = 'UNKNOWN_ERROR',
                    ERROR_MESSAGE = SUBSTR(v_err_msg,1,4000),
                    UPDATED_DATE  = SYSTIMESTAMP
                WHERE LOG_ID = v_batch_log_id;
                COMMIT;
                DBMS_OUTPUT.PUT_LINE('Batch ' || p_batch_num ||
                                     ' ERROR: ' || v_err_msg);
        END SEND_BATCH;

    BEGIN
        -- Get registry
        SELECT * INTO v_reg
        FROM CRM_MPM_API_REGISTRY
        WHERE SERVICE_NAME = 'MD_UNIT_UNAVAILABLE_UPDATE'
        AND   IS_ACTIVE    = 'Y';

        v_batch_size := NVL(v_reg.BATCH_SIZE, 50);

        -- Get token once
        v_token := GET_BEARER_TOKEN(v_reg.CRED_CODE);

        -- Get wallet once
        BEGIN
            SELECT WALLET_PATH, WALLET_PASSWORD
            INTO   v_wallet_path, v_wallet_pwd
            FROM   CRM_MPM_API_CREDENTIALS
            WHERE  CRED_CODE = v_reg.CRED_CODE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_wallet_path := NULL;
                v_wallet_pwd  := NULL;
        END;

        -- Load all records into collection
        -- Note: view already handles required filtering
        v_sql := 'SELECT UNIT_CODE, CUSTOMER_ID, CUSTOMER_NAME ' ||
                 'FROM XXMPM_CRM_LEASED_UNIT_TENANTS ' ||
                 'ORDER BY UNIT_CODE';

        v_cursor_id := DBMS_SQL.OPEN_CURSOR;
        DBMS_SQL.PARSE(v_cursor_id, v_sql, DBMS_SQL.NATIVE);
        DBMS_SQL.DEFINE_COLUMN(v_cursor_id, 1, v_unit_code,   200);
        DBMS_SQL.DEFINE_COLUMN(v_cursor_id, 2, v_cust_id,     200);
        DBMS_SQL.DEFINE_COLUMN(v_cursor_id, 3, v_cust_name,   500);
        DECLARE v_exec INTEGER; BEGIN v_exec := DBMS_SQL.EXECUTE(v_cursor_id); END;

        LOOP
            EXIT WHEN DBMS_SQL.FETCH_ROWS(v_cursor_id) = 0;
            DBMS_SQL.COLUMN_VALUE(v_cursor_id, 1, v_unit_code);
            DBMS_SQL.COLUMN_VALUE(v_cursor_id, 2, v_cust_id);
            DBMS_SQL.COLUMN_VALUE(v_cursor_id, 3, v_cust_name);
            v_rec_count := v_rec_count + 1;
            v_units(v_rec_count).unit_code     := v_unit_code;
            v_units(v_rec_count).customer_id   := v_cust_id;
            v_units(v_rec_count).customer_name := v_cust_name;
        END LOOP;
        DBMS_SQL.CLOSE_CURSOR(v_cursor_id);

        v_total := v_rec_count;
        DBMS_OUTPUT.PUT_LINE(
            'Total unavailable units: ' || v_total ||
            ' | Batch size: '           || v_batch_size ||
            ' | Batches: '              || CEIL(v_total / v_batch_size)
        );

        -- Send in batches
        v_batch_num := 1;
        v_start     := 1;

        WHILE v_start <= v_total LOOP
            v_end       := LEAST(v_start + v_batch_size - 1, v_total);
            SEND_BATCH(v_batch_num, v_start, v_end);
            v_batch_num := v_batch_num + 1;
            v_start     := v_end + 1;
        END LOOP;

        DBMS_OUTPUT.PUT_LINE('All batches completed. Total: ' || v_total);

    EXCEPTION
        WHEN OTHERS THEN
            v_err_msg := SQLERRM;
            IF DBMS_SQL.IS_OPEN(v_cursor_id) THEN
                DBMS_SQL.CLOSE_CURSOR(v_cursor_id);
            END IF;
            DBMS_OUTPUT.PUT_LINE('RUN_UNIT_UNAVAILABLE_BATCH ERROR: ' || v_err_msg);
    END RUN_UNIT_UNAVAILABLE_BATCH;

    -- =============================================================================
-- PACKAGE BODY -- RUN_UNIT_STATUS_BATCH
-- procedure to PKG_CRM_INTEGRATION body
-- =============================================================================

    PROCEDURE RUN_UNIT_STATUS_BATCH IS
        v_reg            CRM_MPM_API_REGISTRY%ROWTYPE;
        v_token          VARCHAR2(4000);
        v_unique_id      VARCHAR2(60);
        v_txn_group      VARCHAR2(40);
        v_wallet_path    VARCHAR2(200);
        v_wallet_pwd     VARCHAR2(200);
        v_status_code    VARCHAR2(10);
        v_response       CLOB;
        v_payload        CLOB;
        v_batch_id       VARCHAR2(50);
        v_log_id         NUMBER;
        v_unit_id        VARCHAR2(200);
        v_batch_size     NUMBER;
        v_batch_num      NUMBER := 1;
        v_rec_count      NUMBER := 0;
        v_first          BOOLEAN := TRUE;
        v_err_msg        VARCHAR2(4000);
        v_ack_request_id VARCHAR2(200);

        -- Collect all unit IDs into array first
        TYPE t_unit_tab IS TABLE OF VARCHAR2(200) INDEX BY PLS_INTEGER;
        v_units     t_unit_tab;
        v_cursor_id INTEGER;
        v_sql       VARCHAR2(500);
        v_total     NUMBER;
        v_start     NUMBER;
        v_end       NUMBER;

        -- Send one batch of units to APIC
        PROCEDURE SEND_BATCH(
            p_batch_num  IN NUMBER,
            p_start      IN NUMBER,
            p_end        IN NUMBER
        ) IS
            v_batch_payload  CLOB;
            v_batch_status   VARCHAR2(10);
            v_batch_response CLOB;
            v_batch_unique   VARCHAR2(60);
            v_batch_txn      VARCHAR2(40);
            v_batch_log_id   NUMBER;
            v_batch_req_id   VARCHAR2(200);
            v_batch_id_str   VARCHAR2(100);
        BEGIN
            v_batch_id_str := 'BATCH_' || TO_CHAR(SYSDATE,'YYYYMMDD_HH24MI') ||
                              '_' || LPAD(TO_CHAR(p_batch_num), 3, '0');
            v_batch_unique  := GENERATE_UNIQUE_ID();
            v_batch_txn     := NEW_GUID();

            -- Build JSON array for this batch
            DBMS_LOB.CREATETEMPORARY(v_batch_payload, TRUE);
            DBMS_LOB.WRITEAPPEND(v_batch_payload, LENGTH('{"units":['), '{"units":[');

            FOR i IN p_start..p_end LOOP
                IF i > p_start THEN
                    DBMS_LOB.WRITEAPPEND(v_batch_payload, 1, ',');
                END IF;
                DECLARE
                    v_unit_json VARCHAR2(300);
                BEGIN
                    v_unit_json := '{"unit_id":"' || v_units(i) ||
                                   '","status":"Available"}';
                    DBMS_LOB.WRITEAPPEND(v_batch_payload,
                                         LENGTH(v_unit_json), v_unit_json);
                END;
            END LOOP;

            DBMS_LOB.WRITEAPPEND(v_batch_payload, LENGTH(']}'), ']}');

            -- Insert log record for this batch
            INSERT INTO CRM_MPM_CRM_INTEGRATION_LOG (
                REGISTRY_ID, ENTITY_NAME, OPERATION_TYPE,
                SOURCE_RECORD_ID, TRANSACTION_GROUP_ID,
                ATTEMPT_NO, REQUEST_PAYLOAD,
                SENT_DATE, FINAL_STATUS, X_UNIQUE_ID
            ) VALUES (
                v_reg.REGISTRY_ID, v_reg.ENTITY_NAME, v_reg.OPERATION_TYPE,
                v_batch_id_str, v_batch_txn,
                1, v_batch_payload,
                SYSTIMESTAMP, 'PENDING', v_batch_unique
            ) RETURNING LOG_ID INTO v_batch_log_id;
            COMMIT;

            -- Send to APIC
            SEND_PAYLOAD_TO_APIC(
                p_endpoint    => v_reg.APIC_ENDPOINT_URL,
                p_http_method => v_reg.HTTP_METHOD,
                p_token       => v_token,
                p_wallet_path => v_wallet_path,
                p_wallet_pwd  => v_wallet_pwd,
                p_txn_group   => v_batch_txn,
                p_unique_id   => v_batch_unique,
                p_rec_type    => v_reg.RECORD_TYPE_HDR,
                p_rec_action  => v_reg.EVENT_CODE_HDR,
                p_api_version => v_reg.APIC_API_VERSION,
                p_payload     => v_batch_payload,
                p_status_code => v_batch_status,
                p_response    => v_batch_response
            );

            -- Parse request_id
            IF v_batch_status BETWEEN '200' AND '299' THEN
                v_batch_req_id := JSON_VALUE(v_batch_response, '$.request_id');
                IF v_batch_req_id IS NULL THEN
                    v_batch_req_id := JSON_VALUE(v_batch_response, '$.requestid');
                END IF;
            END IF;

            -- Update log
            UPDATE CRM_MPM_CRM_INTEGRATION_LOG
            SET HTTP_STATUS_CODE = v_batch_status,
                ACK_RESPONSE     = v_batch_response,
                ACK_REQUEST_ID   = v_batch_req_id,
                FINAL_STATUS     = CASE WHEN v_batch_status BETWEEN '200' AND '299'
                                        THEN 'SENT' ELSE 'FAILED' END,
                ERROR_CODE       = CASE WHEN v_batch_status NOT BETWEEN '200' AND '299'
                                        THEN 'APIC_ERROR' ELSE NULL END,
                ERROR_MESSAGE    = CASE WHEN v_batch_status NOT BETWEEN '200' AND '299'
                                        THEN DBMS_LOB.SUBSTR(v_batch_response, 4000, 1)
                                        ELSE NULL END,
                UPDATED_DATE     = SYSTIMESTAMP
            WHERE LOG_ID = v_batch_log_id;
            COMMIT;

            DBMS_LOB.FREETEMPORARY(v_batch_payload);

            DBMS_OUTPUT.PUT_LINE(
                'Batch ' || p_batch_num ||
                ' (' || (p_end - p_start + 1) || ' units): ' ||
                CASE WHEN v_batch_status BETWEEN '200' AND '299'
                     THEN 'SENT OK' ELSE 'FAILED HTTP ' || v_batch_status END
            );

        EXCEPTION
            WHEN OTHERS THEN
                v_err_msg := SQLERRM;
                UPDATE CRM_MPM_CRM_INTEGRATION_LOG
                SET FINAL_STATUS  = 'FAILED',
                    ERROR_CODE    = 'UNKNOWN_ERROR',
                    ERROR_MESSAGE = SUBSTR(v_err_msg, 1, 4000),
                    UPDATED_DATE  = SYSTIMESTAMP
                WHERE LOG_ID = v_batch_log_id;
                COMMIT;
                DBMS_OUTPUT.PUT_LINE('Batch ' || p_batch_num || ' ERROR: ' || v_err_msg);
        END SEND_BATCH;

    BEGIN
        -- Get registry
        SELECT * INTO v_reg
        FROM CRM_MPM_API_REGISTRY
        WHERE SERVICE_NAME = 'MD_UNIT_STATUS_UPDATE'
        AND   IS_ACTIVE    = 'Y';

        -- Get configurable batch size from registry
        v_batch_size := NVL(v_reg.BATCH_SIZE, 50);

        -- Get token once for all batches
        v_token := GET_BEARER_TOKEN(v_reg.CRED_CODE);

        -- Get wallet once
        BEGIN
            SELECT WALLET_PATH, WALLET_PASSWORD
            INTO   v_wallet_path, v_wallet_pwd
            FROM   CRM_MPM_API_CREDENTIALS
            WHERE  CRED_CODE = v_reg.CRED_CODE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_wallet_path := NULL;
                v_wallet_pwd  := NULL;
        END;

        -- Load ALL unit IDs into collection
        -- Note: XXMPM_CRM_UNIT_STATUS_UPDATE_V already filters CREATION_DATE <> LAST_UPDATE_DATE
        v_sql := 'SELECT UNIT_ID FROM XXMPM_CRM_UNIT_STATUS_UPDATE_V ORDER BY UNIT_ID';
        v_cursor_id := DBMS_SQL.OPEN_CURSOR;
        DBMS_SQL.PARSE(v_cursor_id, v_sql, DBMS_SQL.NATIVE);
        DBMS_SQL.DEFINE_COLUMN(v_cursor_id, 1, v_unit_id, 200);
        DECLARE v_exec INTEGER; BEGIN v_exec := DBMS_SQL.EXECUTE(v_cursor_id); END;

        LOOP
            EXIT WHEN DBMS_SQL.FETCH_ROWS(v_cursor_id) = 0;
            DBMS_SQL.COLUMN_VALUE(v_cursor_id, 1, v_unit_id);
            v_rec_count := v_rec_count + 1;
            v_units(v_rec_count) := v_unit_id;
        END LOOP;
        DBMS_SQL.CLOSE_CURSOR(v_cursor_id);

        v_total := v_rec_count;
        DBMS_OUTPUT.PUT_LINE('Total units: ' || v_total ||
                             ' | Batch size: ' || v_batch_size ||
                             ' | Batches: ' ||
                             CEIL(v_total / v_batch_size));

        -- Send in batches
        v_batch_num := 1;
        v_start     := 1;

        WHILE v_start <= v_total LOOP
            v_end := LEAST(v_start + v_batch_size - 1, v_total);
            SEND_BATCH(v_batch_num, v_start, v_end);
            v_batch_num := v_batch_num + 1;
            v_start     := v_end + 1;
        END LOOP;

        DBMS_OUTPUT.PUT_LINE('All batches completed. Total sent: ' || v_total);

    EXCEPTION
        WHEN OTHERS THEN
            v_err_msg := SQLERRM;
            IF DBMS_SQL.IS_OPEN(v_cursor_id) THEN
                DBMS_SQL.CLOSE_CURSOR(v_cursor_id);
            END IF;
            DBMS_OUTPUT.PUT_LINE('RUN_UNIT_STATUS_BATCH ERROR: ' || v_err_msg);
    END RUN_UNIT_STATUS_BATCH;

    PROCEDURE RUN_UNIT_UNAVAILABLE_AVAILABLE_BATCH IS
        v_reg            CRM_MPM_API_REGISTRY%ROWTYPE;
        v_token          VARCHAR2(4000);
        v_wallet_path    VARCHAR2(200);
        v_wallet_pwd     VARCHAR2(200);
        v_batch_size     NUMBER;
        v_err_msg        VARCHAR2(4000);
        v_cursor_id      INTEGER;
        v_sql            VARCHAR2(500);
        v_rec_count      NUMBER := 0;
        v_total          NUMBER;
        v_start          NUMBER;
        v_end            NUMBER;
        v_batch_num      NUMBER;

        -- Record type for all 4 columns
        TYPE t_unit_rec IS RECORD (
            unit_id      VARCHAR2(200),
            unit_status  VARCHAR2(50),
            customertype VARCHAR2(200),
            tenantid     VARCHAR2(200)
        );
        TYPE t_unit_tab IS TABLE OF t_unit_rec INDEX BY PLS_INTEGER;
        v_units       t_unit_tab;
        v_unit_id     VARCHAR2(200);
        v_unit_status VARCHAR2(50);
        v_cust_type   VARCHAR2(200);
        v_tenant_id   VARCHAR2(200);

        -- Send one batch
        PROCEDURE SEND_BATCH(
            p_batch_num IN NUMBER,
            p_start     IN NUMBER,
            p_end       IN NUMBER
        ) IS
            v_batch_payload  CLOB;
            v_batch_status   VARCHAR2(10);
            v_batch_response CLOB;
            v_batch_unique   VARCHAR2(60);
            v_batch_txn      VARCHAR2(40);
            v_batch_log_id   NUMBER;
            v_batch_req_id   VARCHAR2(200);
            v_batch_id_str   VARCHAR2(100);
            v_unit_json      VARCHAR2(1000);
        BEGIN
            v_batch_id_str := 'UNIT_BATCH_' ||
                              TO_CHAR(SYSDATE,'YYYYMMDD_HH24MI') ||
                              '_' || LPAD(TO_CHAR(p_batch_num),3,'0');
            v_batch_unique  := GENERATE_UNIQUE_ID();
            v_batch_txn     := NEW_GUID();

            -- Build JSON
            DBMS_LOB.CREATETEMPORARY(v_batch_payload, TRUE);
            DBMS_LOB.WRITEAPPEND(v_batch_payload,
                                 LENGTH('{"units":['), '{"units":[');

            FOR i IN p_start..p_end LOOP
                IF i > p_start THEN
                    DBMS_LOB.WRITEAPPEND(v_batch_payload, 1, ',');
                END IF;

                v_unit_json :=
                    '{"unit_id":"'     || NVL(v_units(i).unit_id,'')      || '"' ||
                    ',"unit_status":"' || NVL(v_units(i).unit_status,'')  || '"' ||
                    ',"customertype":"'|| NVL(v_units(i).customertype,'') || '"' ||
                    ',"tenantid":"'    || NVL(v_units(i).tenantid,'')     || '"' ||
                    '}';

                DBMS_LOB.WRITEAPPEND(v_batch_payload,
                                     LENGTH(v_unit_json), v_unit_json);
            END LOOP;

            DBMS_LOB.WRITEAPPEND(v_batch_payload, LENGTH(']}'), ']}');

            -- Insert log
            INSERT INTO CRM_MPM_CRM_INTEGRATION_LOG (
                REGISTRY_ID, ENTITY_NAME, OPERATION_TYPE,
                SOURCE_RECORD_ID, TRANSACTION_GROUP_ID,
                ATTEMPT_NO, REQUEST_PAYLOAD,
                SENT_DATE, FINAL_STATUS, X_UNIQUE_ID
            ) VALUES (
                v_reg.REGISTRY_ID, v_reg.ENTITY_NAME, v_reg.OPERATION_TYPE,
                v_batch_id_str, v_batch_txn,
                1, v_batch_payload,
                SYSTIMESTAMP, 'PENDING', v_batch_unique
            ) RETURNING LOG_ID INTO v_batch_log_id;
            COMMIT;

            -- Send to APIC
            SEND_PAYLOAD_TO_APIC(
                p_endpoint    => v_reg.APIC_ENDPOINT_URL,
                p_http_method => v_reg.HTTP_METHOD,
                p_token       => v_token,
                p_wallet_path => v_wallet_path,
                p_wallet_pwd  => v_wallet_pwd,
                p_txn_group   => v_batch_txn,
                p_unique_id   => v_batch_unique,
                p_rec_type    => v_reg.RECORD_TYPE_HDR,
                p_rec_action  => v_reg.EVENT_CODE_HDR,
                p_api_version => v_reg.APIC_API_VERSION,
                p_payload     => v_batch_payload,
                p_status_code => v_batch_status,
                p_response    => v_batch_response
            );

            -- Parse request_id
            IF v_batch_status BETWEEN '200' AND '299' THEN
                v_batch_req_id := JSON_VALUE(v_batch_response, '$.request_id');
                IF v_batch_req_id IS NULL THEN
                    v_batch_req_id := JSON_VALUE(v_batch_response, '$.requestid');
                END IF;
            END IF;

            -- Update log
            UPDATE CRM_MPM_CRM_INTEGRATION_LOG
            SET HTTP_STATUS_CODE = v_batch_status,
                ACK_RESPONSE     = v_batch_response,
                ACK_REQUEST_ID   = v_batch_req_id,
                FINAL_STATUS     = CASE WHEN v_batch_status BETWEEN '200' AND '299'
                                        THEN 'SENT' ELSE 'FAILED' END,
                ERROR_CODE       = CASE WHEN v_batch_status NOT BETWEEN '200' AND '299'
                                        THEN 'APIC_ERROR' ELSE NULL END,
                ERROR_MESSAGE    = CASE WHEN v_batch_status NOT BETWEEN '200' AND '299'
                                        THEN DBMS_LOB.SUBSTR(v_batch_response,4000,1)
                                        ELSE NULL END,
                UPDATED_DATE     = SYSTIMESTAMP
            WHERE LOG_ID = v_batch_log_id;
            COMMIT;

            DBMS_LOB.FREETEMPORARY(v_batch_payload);

            DBMS_OUTPUT.PUT_LINE(
                'Batch ' || p_batch_num ||
                ' (' || (p_end - p_start + 1) || ' units): ' ||
                CASE WHEN v_batch_status BETWEEN '200' AND '299'
                     THEN 'SENT OK'
                     ELSE 'FAILED HTTP ' || v_batch_status END
            );

        EXCEPTION
            WHEN OTHERS THEN
                v_err_msg := SQLERRM;
                UPDATE CRM_MPM_CRM_INTEGRATION_LOG
                SET FINAL_STATUS  = 'FAILED',
                    ERROR_CODE    = 'UNKNOWN_ERROR',
                    ERROR_MESSAGE = SUBSTR(v_err_msg,1,4000),
                    UPDATED_DATE  = SYSTIMESTAMP
                WHERE LOG_ID = v_batch_log_id;
                COMMIT;
                DBMS_OUTPUT.PUT_LINE('Batch ' || p_batch_num ||
                                     ' ERROR: ' || v_err_msg);
        END SEND_BATCH;

    BEGIN
        -- Get registry
        SELECT * INTO v_reg
        FROM CRM_MPM_API_REGISTRY
        WHERE SERVICE_NAME = 'MD_UNIT_ALL_STATUS'
        AND   IS_ACTIVE    = 'Y';

        v_batch_size := NVL(v_reg.BATCH_SIZE, 100);

        -- Get token once
        v_token := GET_BEARER_TOKEN(v_reg.CRED_CODE);

        -- Get wallet once
        BEGIN
            SELECT WALLET_PATH, WALLET_PASSWORD
            INTO   v_wallet_path, v_wallet_pwd
            FROM   CRM_MPM_API_CREDENTIALS
            WHERE  CRED_CODE = v_reg.CRED_CODE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_wallet_path := NULL;
                v_wallet_pwd  := NULL;
        END;

        -- Load all records from consolidated view
        -- Note: view already handles required filtering
        v_sql := 'SELECT UNIT_ID, UNIT_STATUS, CUSTOMERTYPE, TENANTID ' ||
                 'FROM XXMPM_CRM_ALL_UNIT_STATUS_V ' ||
                 'ORDER BY UNIT_STATUS, UNIT_ID';

        v_cursor_id := DBMS_SQL.OPEN_CURSOR;
        DBMS_SQL.PARSE(v_cursor_id, v_sql, DBMS_SQL.NATIVE);
        DBMS_SQL.DEFINE_COLUMN(v_cursor_id, 1, v_unit_id,     200);
        DBMS_SQL.DEFINE_COLUMN(v_cursor_id, 2, v_unit_status, 50);
        DBMS_SQL.DEFINE_COLUMN(v_cursor_id, 3, v_cust_type,   200);
        DBMS_SQL.DEFINE_COLUMN(v_cursor_id, 4, v_tenant_id,   200);
        DECLARE v_exec INTEGER; BEGIN v_exec := DBMS_SQL.EXECUTE(v_cursor_id); END;

        LOOP
            EXIT WHEN DBMS_SQL.FETCH_ROWS(v_cursor_id) = 0;
            DBMS_SQL.COLUMN_VALUE(v_cursor_id, 1, v_unit_id);
            DBMS_SQL.COLUMN_VALUE(v_cursor_id, 2, v_unit_status);
            DBMS_SQL.COLUMN_VALUE(v_cursor_id, 3, v_cust_type);
            DBMS_SQL.COLUMN_VALUE(v_cursor_id, 4, v_tenant_id);
            v_rec_count := v_rec_count + 1;
            v_units(v_rec_count).unit_id      := v_unit_id;
            v_units(v_rec_count).unit_status  := v_unit_status;
            v_units(v_rec_count).customertype := v_cust_type;
            v_units(v_rec_count).tenantid     := v_tenant_id;
        END LOOP;
        DBMS_SQL.CLOSE_CURSOR(v_cursor_id);

        v_total := v_rec_count;
        DBMS_OUTPUT.PUT_LINE(
            'Total units: '   || v_total       ||
            ' | Batch size: ' || v_batch_size  ||
            ' | Batches: '    || CEIL(v_total / v_batch_size)
        );

        -- Send in batches
        v_batch_num := 1;
        v_start     := 1;

        WHILE v_start <= v_total LOOP
            v_end       := LEAST(v_start + v_batch_size - 1, v_total);
            SEND_BATCH(v_batch_num, v_start, v_end);
            v_batch_num := v_batch_num + 1;
            v_start     := v_end + 1;
        END LOOP;

        DBMS_OUTPUT.PUT_LINE('All batches completed. Total: ' || v_total);

    EXCEPTION
        WHEN OTHERS THEN
            v_err_msg := SQLERRM;
            IF DBMS_SQL.IS_OPEN(v_cursor_id) THEN
                DBMS_SQL.CLOSE_CURSOR(v_cursor_id);
            END IF;
            DBMS_OUTPUT.PUT_LINE('RUN_UNIT_UNAVAILABLE_BATCH ERROR: ' || v_err_msg);
    END RUN_UNIT_UNAVAILABLE_AVAILABLE_BATCH;



END PKG_CRM_INTEGRATION;
