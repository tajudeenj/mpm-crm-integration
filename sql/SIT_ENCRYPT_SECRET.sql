-- =============================================================================
-- ADIB MPM PROPERTIES -- CRM xRM INTEGRATION
-- ENCRYPT CLIENT SECRET -- RUN SEPARATELY AFTER SIT_FULL_DATA_INSERT.sql
-- Author  : Tajudeen Jalaudin -- Senior Solution Architect, ADIB
-- Date    : 24 September 2026
-- Purpose : Encrypts CLIENT_SECRET_REF using AES-256 (DBMS_CRYPTO)
--           Stores encrypted value in CLIENT_SECRET_ENCRYPTED (RAW column)
--           Clears plain text CLIENT_SECRET_REF after encryption
-- Pre-req : CRM_MPM_ENCRYPT_CONFIG must have 1 active row (encryption key)
--           CRM_MPM_API_CREDENTIALS must have APIC_PXRM row
--           DBMS_CRYPTO grant must exist for schema owner
-- =============================================================================

SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED

PROMPT
PROMPT =============================================================
PROMPT   ENCRYPT CLIENT SECRET -- APIC_PXRM
PROMPT =============================================================
PROMPT

DECLARE
    v_key        RAW(32);
    v_secret     VARCHAR2(500);
    v_encrypted  RAW(4000);
    v_decrypted  VARCHAR2(500);

    -- AES256 CBC with PKCS5 padding -- same as Java EncryptPassword.java
    v_algo  CONSTANT PLS_INTEGER :=
        DBMS_CRYPTO.ENCRYPT_AES256
        + DBMS_CRYPTO.CHAIN_CBC
        + DBMS_CRYPTO.PAD_PKCS5;

BEGIN
    -- Step 1: Get encryption key
    SELECT ENCRYPT_KEY INTO v_key
    FROM   CRM_MPM_ENCRYPT_CONFIG
    WHERE  IS_ACTIVE = 'Y'
    AND    ROWNUM    = 1;
    DBMS_OUTPUT.PUT_LINE('Step 1: Encryption key loaded');

    -- Step 2: Get current plain text secret
    SELECT CLIENT_SECRET_REF INTO v_secret
    FROM   CRM_MPM_API_CREDENTIALS
    WHERE  CRED_CODE  = 'APIC_PXRM'
    AND    IS_ACTIVE  = 'Y';

    IF v_secret IS NULL OR v_secret = '*** ENCRYPTED ***' THEN
        DBMS_OUTPUT.PUT_LINE('ERROR: CLIENT_SECRET_REF is empty or already encrypted');
        DBMS_OUTPUT.PUT_LINE('Update CLIENT_SECRET_REF with plain text secret first');
        RETURN;
    END IF;
    DBMS_OUTPUT.PUT_LINE('Step 2: Plain text secret loaded ('||LENGTH(v_secret)||' chars)');

    -- Step 3: Encrypt
    v_encrypted := DBMS_CRYPTO.ENCRYPT(
        src => UTL_RAW.CAST_TO_RAW(v_secret),
        typ => v_algo,
        key => v_key
    );
    DBMS_OUTPUT.PUT_LINE('Step 3: Encryption done');

    -- Step 4: Roundtrip verify -- decrypt and compare
    v_decrypted := UTL_RAW.CAST_TO_VARCHAR2(
        DBMS_CRYPTO.DECRYPT(
            src => v_encrypted,
            typ => v_algo,
            key => v_key
        )
    );

    IF v_decrypted != v_secret THEN
        DBMS_OUTPUT.PUT_LINE('ERROR: Roundtrip verify FAILED -- aborting, no changes made');
        RETURN;
    END IF;
    DBMS_OUTPUT.PUT_LINE('Step 4: Roundtrip verify PASSED');

    -- Step 5: Store encrypted value, clear plain text
    UPDATE CRM_MPM_API_CREDENTIALS
    SET    CLIENT_SECRET_ENCRYPTED = v_encrypted,
           CLIENT_SECRET_REF       = '*** ENCRYPTED ***',
           UPDATED_DATE            = SYSTIMESTAMP
    WHERE  CRED_CODE = 'APIC_PXRM';
    COMMIT;

    DBMS_OUTPUT.PUT_LINE('Step 5: Encrypted value stored, plain text cleared');
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('=== DONE ===');
    DBMS_OUTPUT.PUT_LINE('CLIENT_SECRET_ENCRYPTED : populated (RAW blob)');
    DBMS_OUTPUT.PUT_LINE('CLIENT_SECRET_REF       : *** ENCRYPTED ***');
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('To use in Admin Tool: Go to Credentials tab,');
    DBMS_OUTPUT.PUT_LINE('click Load Selected -- secret shown as encrypted.');

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('ERROR: APIC_PXRM credential or encrypt key not found');
        DBMS_OUTPUT.PUT_LINE('Run SIT_FULL_DATA_INSERT.sql first');
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('No changes made -- rolled back');
END;
/

-- Verify result
PROMPT
PROMPT Verification:
SELECT
    CRED_CODE,
    CLIENT_ID,
    CLIENT_SECRET_REF,
    CASE WHEN CLIENT_SECRET_ENCRYPTED IS NOT NULL
         THEN 'ENCRYPTED (blob '||RAWTOHEX(UTLRAW.SUBSTR(CLIENT_SECRET_ENCRYPTED,1,4))||'...)'
         ELSE 'NOT ENCRYPTED'
    END AS SECRET_STATUS,
    IS_ACTIVE
FROM CRM_MPM_API_CREDENTIALS
WHERE CRED_CODE = 'APIC_PXRM';

PROMPT
PROMPT =============================================================
PROMPT   Encryption complete
PROMPT   CLIENT_SECRET_REF is now *** ENCRYPTED ***
PROMPT   Encrypted blob stored in CLIENT_SECRET_ENCRYPTED
PROMPT   Package GET_BEARER_TOKEN will use encrypted value
PROMPT =============================================================
