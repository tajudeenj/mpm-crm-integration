-- =============================================================================
-- WALLET PASSWORD AND APIC TOKEN DIAGNOSTIC SCRIPT
-- ADIB MPM CRM Integration
-- Author : ADIB EA Team (Tajudeen Jalaudin)
-- Date   : 2026-09-21
-- Run in SQL Developer with SERVEROUTPUT ON
-- =============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200

DBMS_OUTPUT.PUT_LINE('==============================================');
DBMS_OUTPUT.PUT_LINE('CRM Integration -- Wallet & Token Diagnostics');
DBMS_OUTPUT.PUT_LINE('==============================================');
DBMS_OUTPUT.PUT_LINE('Run Time: ' || TO_CHAR(SYSDATE,'DD-MON-YY HH24:MI:SS'));
DBMS_OUTPUT.PUT_LINE(' ');


-- =============================================================================
-- TEST 1: CHECK CREDENTIAL COLUMNS
-- =============================================================================
DBMS_OUTPUT.PUT_LINE('--- TEST 1: CREDENTIAL STATE ---');
BEGIN
    FOR r IN (
        SELECT
            CRED_CODE,
            TOKEN_URL,
            CLIENT_ID,
            NVL(WALLET_PATH,  'NOT SET') AS WALLET_PATH,
            NVL(WALLET_PASSWORD, 'NULL') AS WALLET_PWD_PLAIN,
            CASE WHEN CLIENT_SECRET_ENCRYPTED IS NOT NULL
                 THEN 'AES256 BLOB EXISTS (' ||
                      DBMS_LOB.GETLENGTH(CLIENT_SECRET_ENCRYPTED) ||
                      ' bytes)'
                 ELSE 'NOT ENCRYPTED'
            END AS SECRET_STATUS,
            CASE WHEN WALLET_PASSWORD_ENC IS NOT NULL
                 THEN 'AES256 BLOB EXISTS (' ||
                      DBMS_LOB.GETLENGTH(WALLET_PASSWORD_ENC) ||
                      ' bytes)'
                 ELSE 'NO ENCRYPTED BLOB'
            END AS WALLET_ENC_STATUS,
            NVL(WALLET_PWD_KEY_REF, 'NOT SET') AS KEY_REF,
            IS_ACTIVE
        FROM CRM_MPM_API_CREDENTIALS
        ORDER BY CRED_CODE
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('Cred Code  : ' || r.CRED_CODE);
        DBMS_OUTPUT.PUT_LINE('Token URL  : ' || r.TOKEN_URL);
        DBMS_OUTPUT.PUT_LINE('Client ID  : ' || r.CLIENT_ID);
        DBMS_OUTPUT.PUT_LINE('Wallet Path: ' || r.WALLET_PATH);
        DBMS_OUTPUT.PUT_LINE('Wallet Pwd : ' || r.WALLET_PWD_PLAIN);
        DBMS_OUTPUT.PUT_LINE('Secret Enc : ' || r.SECRET_STATUS);
        DBMS_OUTPUT.PUT_LINE('Wallet Enc : ' || r.WALLET_ENC_STATUS);
        DBMS_OUTPUT.PUT_LINE('Key Ref    : ' || r.KEY_REF);
        DBMS_OUTPUT.PUT_LINE('Is Active  : ' || r.IS_ACTIVE);
        DBMS_OUTPUT.PUT_LINE(' ');
    END LOOP;
END;
/


-- =============================================================================
-- TEST 2: DECRYPT CLIENT SECRET
-- =============================================================================
DBMS_OUTPUT.PUT_LINE('--- TEST 2: DECRYPT CLIENT SECRET ---');
DECLARE
    v_key     RAW(32);
    v_enc     BLOB;
    v_dec     VARCHAR2(4000);
BEGIN
    SELECT ENCRYPT_KEY INTO v_key
    FROM   CRM_MPM_ENCRYPT_CONFIG
    WHERE  IS_ACTIVE = 'Y' AND ROWNUM = 1;

    SELECT CLIENT_SECRET_ENCRYPTED INTO v_enc
    FROM   CRM_MPM_API_CREDENTIALS
    WHERE  CRED_CODE = 'APIC_PXRM';

    IF v_enc IS NOT NULL THEN
        v_dec := UTL_RAW.CAST_TO_VARCHAR2(
            DBMS_CRYPTO.DECRYPT(
                src => v_enc,
                typ => DBMS_CRYPTO.ENCRYPT_AES256 +
                       DBMS_CRYPTO.CHAIN_CBC +
                       DBMS_CRYPTO.PAD_PKCS5,
                key => v_key));
        DBMS_OUTPUT.PUT_LINE('Client Secret Decrypt: OK');
        DBMS_OUTPUT.PUT_LINE('Length: ' || LENGTH(v_dec) || ' chars');
    ELSE
        DBMS_OUTPUT.PUT_LINE('Client Secret: NOT ENCRYPTED');
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Client Secret Decrypt FAILED: ' || SQLERRM);
END;
/


-- =============================================================================
-- TEST 3: DECRYPT WALLET PASSWORD
-- =============================================================================
DBMS_OUTPUT.PUT_LINE('--- TEST 3: DECRYPT WALLET PASSWORD ---');
DECLARE
    v_key     RAW(32);
    v_enc     BLOB;
    v_dec     VARCHAR2(4000);
    v_plain   VARCHAR2(4000);
BEGIN
    -- Check plain text first
    SELECT NVL(WALLET_PASSWORD, 'NULL')
    INTO   v_plain
    FROM   CRM_MPM_API_CREDENTIALS
    WHERE  CRED_CODE = 'APIC_PXRM';

    DBMS_OUTPUT.PUT_LINE('Wallet Plain Text: ' || v_plain);

    -- Check encrypted BLOB
    SELECT WALLET_PASSWORD_ENC INTO v_enc
    FROM   CRM_MPM_API_CREDENTIALS
    WHERE  CRED_CODE = 'APIC_PXRM';

    IF v_enc IS NOT NULL THEN
        SELECT ENCRYPT_KEY INTO v_key
        FROM   CRM_MPM_ENCRYPT_CONFIG
        WHERE  IS_ACTIVE = 'Y' AND ROWNUM = 1;

        v_dec := UTL_RAW.CAST_TO_VARCHAR2(
            DBMS_CRYPTO.DECRYPT(
                src => v_enc,
                typ => DBMS_CRYPTO.ENCRYPT_AES256 +
                       DBMS_CRYPTO.CHAIN_CBC +
                       DBMS_CRYPTO.PAD_PKCS5,
                key => v_key));
        DBMS_OUTPUT.PUT_LINE('Wallet Pwd Decrypt: OK');
        DBMS_OUTPUT.PUT_LINE('Length: ' || LENGTH(v_dec) || ' chars');
    ELSE
        DBMS_OUTPUT.PUT_LINE('Wallet Pwd Enc Blob: NULL -- not encrypted');
        DBMS_OUTPUT.PUT_LINE('Using plain text value above');
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Wallet Decrypt FAILED: ' || SQLERRM);
END;
/


-- =============================================================================
-- TEST 4: TEST WALLET OPEN DIRECTLY
-- =============================================================================
DBMS_OUTPUT.PUT_LINE('--- TEST 4: TEST WALLET OPEN ---');
DECLARE
    v_path VARCHAR2(500);
    v_pwd  VARCHAR2(500);
    v_key  RAW(32);
    v_enc  BLOB;
BEGIN
    SELECT WALLET_PATH,
           NVL(WALLET_PASSWORD, 'NULL')
    INTO   v_path, v_pwd
    FROM   CRM_MPM_API_CREDENTIALS
    WHERE  CRED_CODE = 'APIC_PXRM';

    -- Try encrypted first
    SELECT WALLET_PASSWORD_ENC INTO v_enc
    FROM   CRM_MPM_API_CREDENTIALS
    WHERE  CRED_CODE = 'APIC_PXRM';

    IF v_enc IS NOT NULL THEN
        SELECT ENCRYPT_KEY INTO v_key
        FROM   CRM_MPM_ENCRYPT_CONFIG
        WHERE  IS_ACTIVE = 'Y' AND ROWNUM = 1;

        v_pwd := UTL_RAW.CAST_TO_VARCHAR2(
            DBMS_CRYPTO.DECRYPT(
                src => v_enc,
                typ => DBMS_CRYPTO.ENCRYPT_AES256 +
                       DBMS_CRYPTO.CHAIN_CBC +
                       DBMS_CRYPTO.PAD_PKCS5,
                key => v_key));
        DBMS_OUTPUT.PUT_LINE('Using encrypted wallet password');
    ELSE
        DBMS_OUTPUT.PUT_LINE('Using plain text wallet password');
    END IF;

    DBMS_OUTPUT.PUT_LINE('Wallet Path: ' || v_path);
    DBMS_OUTPUT.PUT_LINE('Attempting UTL_HTTP.SET_WALLET...');

    UTL_HTTP.SET_WALLET(v_path, v_pwd);
    DBMS_OUTPUT.PUT_LINE('Wallet Open: OK');

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Wallet Open FAILED: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('This is likely the root cause of ORA-29273');
END;
/


-- =============================================================================
-- TEST 5: GET BEARER TOKEN
-- =============================================================================
DBMS_OUTPUT.PUT_LINE('--- TEST 5: GET BEARER TOKEN ---');
DECLARE
    v_token VARCHAR2(4000);
BEGIN
    DBMS_OUTPUT.PUT_LINE('Calling GET_BEARER_TOKEN...');
    v_token := PKG_CRM_INTEGRATION.GET_BEARER_TOKEN('APIC_PXRM');
    IF v_token IS NOT NULL AND LENGTH(v_token) > 10 THEN
        DBMS_OUTPUT.PUT_LINE('Token: OK');
        DBMS_OUTPUT.PUT_LINE('Length : ' || LENGTH(v_token));
        DBMS_OUTPUT.PUT_LINE('Preview: Bearer ' ||
            SUBSTR(v_token,1,30) || '...');
    ELSE
        DBMS_OUTPUT.PUT_LINE('Token: NULL or empty -- FAILED');
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('GET_BEARER_TOKEN FAILED: ' || SQLERRM);
END;
/


-- =============================================================================
-- TEST 6: QUICK HTTP TEST TO APIC
-- =============================================================================
DBMS_OUTPUT.PUT_LINE('--- TEST 6: HTTP CONNECTIVITY ---');
DECLARE
    v_req  UTL_HTTP.REQ;
    v_resp UTL_HTTP.RESP;
    v_path VARCHAR2(500);
    v_pwd  VARCHAR2(500);
    v_url  VARCHAR2(1000);
    v_key  RAW(32);
    v_enc  BLOB;
BEGIN
    SELECT WALLET_PATH, TOKEN_URL
    INTO   v_path, v_url
    FROM   CRM_MPM_API_CREDENTIALS
    WHERE  CRED_CODE = 'APIC_PXRM';

    SELECT WALLET_PASSWORD_ENC INTO v_enc
    FROM   CRM_MPM_API_CREDENTIALS
    WHERE  CRED_CODE = 'APIC_PXRM';

    IF v_enc IS NOT NULL THEN
        SELECT ENCRYPT_KEY INTO v_key
        FROM   CRM_MPM_ENCRYPT_CONFIG
        WHERE  IS_ACTIVE = 'Y' AND ROWNUM = 1;
        v_pwd := UTL_RAW.CAST_TO_VARCHAR2(
            DBMS_CRYPTO.DECRYPT(
                src => v_enc,
                typ => DBMS_CRYPTO.ENCRYPT_AES256 +
                       DBMS_CRYPTO.CHAIN_CBC +
                       DBMS_CRYPTO.PAD_PKCS5,
                key => v_key));
    ELSE
        SELECT NVL(WALLET_PASSWORD,'NULL')
        INTO   v_pwd
        FROM   CRM_MPM_API_CREDENTIALS
        WHERE  CRED_CODE = 'APIC_PXRM';
    END IF;

    DBMS_OUTPUT.PUT_LINE('Testing URL: ' || v_url);
    UTL_HTTP.SET_WALLET(v_path, v_pwd);
    v_req  := UTL_HTTP.BEGIN_REQUEST(v_url, 'GET');
    v_resp := UTL_HTTP.GET_RESPONSE(v_req);
    DBMS_OUTPUT.PUT_LINE('HTTP Status: ' ||
        v_resp.STATUS_CODE || ' ' || v_resp.REASON_PHRASE);
    UTL_HTTP.END_RESPONSE(v_resp);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('HTTP Test FAILED: ' || SQLERRM);
END;
/

DBMS_OUTPUT.PUT_LINE(' ');
DBMS_OUTPUT.PUT_LINE('==============================================');
DBMS_OUTPUT.PUT_LINE('Diagnostics Complete');
DBMS_OUTPUT.PUT_LINE('==============================================');
