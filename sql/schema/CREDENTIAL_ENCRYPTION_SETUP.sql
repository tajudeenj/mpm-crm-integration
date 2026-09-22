-- =============================================================================
-- CREDENTIAL ENCRYPTION USING DBMS_CRYPTO
-- Encrypts CLIENT_SECRET in CRM_MPM_API_CREDENTIALS
-- AES256 encryption -- secret never stored as plain text
-- Author : ADIB EA Team (Tajudeen Jalaudin)
-- Date   : 2026-08-20
-- =============================================================================

SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED


-- =============================================================================
-- STEP 1: ADD ENCRYPTED COLUMN TO CREDENTIALS TABLE
-- =============================================================================
ALTER TABLE CRM_MPM_API_CREDENTIALS
ADD CLIENT_SECRET_ENCRYPTED RAW(4000);

ALTER TABLE CRM_MPM_API_CREDENTIALS
ADD ENCRYPT_KEY_REF VARCHAR2(100);  -- reference to where key is stored

-- Verify
SELECT COLUMN_NAME, DATA_TYPE
FROM USER_TAB_COLUMNS
WHERE TABLE_NAME = 'CRM_MPM_API_CREDENTIALS'
ORDER BY COLUMN_ID;


-- =============================================================================
-- STEP 2: CREATE ENCRYPTION KEY TABLE
-- Stores the AES256 key securely -- access restricted by grants
-- =============================================================================
CREATE TABLE CRM_MPM_ENCRYPT_CONFIG (
    CONFIG_ID    NUMBER        NOT NULL,
    KEY_NAME     VARCHAR2(50)  NOT NULL,
    ENCRYPT_KEY  RAW(32)       NOT NULL,  -- 32 bytes = 256 bits for AES256
    IS_ACTIVE    CHAR(1)       DEFAULT 'Y',
    CREATED_DATE DATE          DEFAULT SYSDATE,
    CONSTRAINT PK_ENCRYPT_CONFIG PRIMARY KEY (CONFIG_ID)
);

-- Insert encryption key
-- IMPORTANT: Change this key in SIT/PROD -- keep it secret
-- Key must be exactly 32 characters (256 bits)
INSERT INTO CRM_MPM_ENCRYPT_CONFIG (
    CONFIG_ID, KEY_NAME, ENCRYPT_KEY, IS_ACTIVE
) VALUES (
    1,
    'CRM_INTEGRATION_KEY',
    UTL_RAW.CAST_TO_RAW('CRM_ADIB_MPM_2026_SECRET_KEY_32C'),  -- 32 chars
    'Y'
);
COMMIT;

-- Restrict access to key table -- only package owner can read
-- REVOKE ALL ON CRM_MPM_ENCRYPT_CONFIG FROM PUBLIC;
-- GRANT SELECT ON CRM_MPM_ENCRYPT_CONFIG TO <package_owner>;


-- =============================================================================
-- STEP 3: ENCRYPTION PROCEDURE
-- Run this to encrypt existing plain text secrets
-- =============================================================================
DECLARE
    v_key        RAW(32);
    v_encrypted  RAW(4000);
    v_secret     VARCHAR2(500);
BEGIN
    -- Get encryption key
    SELECT ENCRYPT_KEY INTO v_key
    FROM CRM_MPM_ENCRYPT_CONFIG
    WHERE IS_ACTIVE = 'Y' AND ROWNUM = 1;

    -- Encrypt each credential
    FOR rec IN (
        SELECT ROWID, CLIENT_SECRET_REF
        FROM CRM_MPM_API_CREDENTIALS
        WHERE IS_ACTIVE = 'Y'
        AND   CLIENT_SECRET_REF IS NOT NULL
    ) LOOP
        BEGIN
            v_secret   := rec.CLIENT_SECRET_REF;

            -- Encrypt using AES256
            v_encrypted := DBMS_CRYPTO.ENCRYPT(
                src => UTL_RAW.CAST_TO_RAW(v_secret),
                typ => DBMS_CRYPTO.ENCRYPT_AES256 +
                       DBMS_CRYPTO.CHAIN_CBC       +
                       DBMS_CRYPTO.PAD_PKCS5,
                key => v_key
            );

            -- Store encrypted value
            UPDATE CRM_MPM_API_CREDENTIALS
            SET    CLIENT_SECRET_ENCRYPTED = v_encrypted,
                   ENCRYPT_KEY_REF         = 'CRM_INTEGRATION_KEY'
            WHERE  ROWID = rec.ROWID;

            DBMS_OUTPUT.PUT_LINE('Encrypted credential for ROWID: ' || rec.ROWID);

        EXCEPTION
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('ERROR encrypting: ' || SQLERRM);
        END;
    END LOOP;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('All credentials encrypted successfully');

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
END;
/


-- =============================================================================
-- STEP 4: VERIFY ENCRYPTION WORKED
-- =============================================================================
SELECT CRED_CODE,
       CLIENT_ID,
       CASE WHEN CLIENT_SECRET_ENCRYPTED IS NOT NULL
            THEN 'ENCRYPTED ✓'
            ELSE 'NOT ENCRYPTED ✗'
       END AS SECRET_STATUS,
       ENCRYPT_KEY_REF
FROM CRM_MPM_API_CREDENTIALS
WHERE IS_ACTIVE = 'Y';


-- =============================================================================
-- STEP 5: TEST DECRYPTION
-- Verify we can decrypt back to original value
-- =============================================================================
DECLARE
    v_key       RAW(32);
    v_decrypted VARCHAR2(500);
BEGIN
    SELECT ENCRYPT_KEY INTO v_key
    FROM CRM_MPM_ENCRYPT_CONFIG
    WHERE IS_ACTIVE = 'Y' AND ROWNUM = 1;

    SELECT UTL_RAW.CAST_TO_VARCHAR2(
               DBMS_CRYPTO.DECRYPT(
                   src => CLIENT_SECRET_ENCRYPTED,
                   typ => DBMS_CRYPTO.ENCRYPT_AES256 +
                          DBMS_CRYPTO.CHAIN_CBC       +
                          DBMS_CRYPTO.PAD_PKCS5,
                   key => v_key
               )
           )
    INTO v_decrypted
    FROM CRM_MPM_API_CREDENTIALS
    WHERE IS_ACTIVE = 'Y' AND ROWNUM = 1;

    -- Compare with original
    DBMS_OUTPUT.PUT_LINE('Decrypted OK: ' ||
        CASE WHEN v_decrypted IS NOT NULL
             THEN 'YES -- length=' || LENGTH(v_decrypted)
             ELSE 'FAILED'
        END);

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Decrypt ERROR: ' || SQLERRM);
END;
/


-- =============================================================================
-- STEP 6: UPDATE GET_BEARER_TOKEN IN PACKAGE
-- Replace plain text secret with decrypted value
-- Find this section in GET_BEARER_TOKEN and replace:
-- =============================================================================
/*
-- FIND THIS LINE in GET_BEARER_TOKEN:
v_client_secret := v_cred.CLIENT_SECRET_REF;

-- REPLACE WITH THIS:
DECLARE
    v_enc_key RAW(32);
BEGIN
    -- Get encryption key
    SELECT ENCRYPT_KEY INTO v_enc_key
    FROM CRM_MPM_ENCRYPT_CONFIG
    WHERE KEY_NAME  = v_cred.ENCRYPT_KEY_REF
    AND   IS_ACTIVE = 'Y';

    -- Decrypt secret
    v_client_secret := UTL_RAW.CAST_TO_VARCHAR2(
        DBMS_CRYPTO.DECRYPT(
            src => v_cred.CLIENT_SECRET_ENCRYPTED,
            typ => DBMS_CRYPTO.ENCRYPT_AES256 +
                   DBMS_CRYPTO.CHAIN_CBC       +
                   DBMS_CRYPTO.PAD_PKCS5,
            key => v_enc_key
        )
    );
EXCEPTION
    WHEN OTHERS THEN
        -- Fallback to plain text if encrypted not available
        v_client_secret := v_cred.CLIENT_SECRET_REF;
END;
*/


-- =============================================================================
-- STEP 7: AFTER ENCRYPTION CONFIRMED WORKING
-- Optionally clear plain text secret from table
-- DO THIS ONLY AFTER CONFIRMING DECRYPTION WORKS
-- =============================================================================
/*
UPDATE CRM_MPM_API_CREDENTIALS
SET CLIENT_SECRET_REF = '*** ENCRYPTED ***'
WHERE IS_ACTIVE = 'Y'
AND CLIENT_SECRET_ENCRYPTED IS NOT NULL;
COMMIT;
DBMS_OUTPUT.PUT_LINE('Plain text secrets cleared');
*/


-- =============================================================================
-- STEP 8: FOR SIT DEPLOYMENT
-- In SIT -- insert new encrypted secret
-- =============================================================================
/*
DECLARE
    v_key       RAW(32);
    v_encrypted RAW(4000);
    v_secret    VARCHAR2(500) := '<SIT_CLIENT_SECRET>';
BEGIN
    SELECT ENCRYPT_KEY INTO v_key
    FROM CRM_MPM_ENCRYPT_CONFIG
    WHERE IS_ACTIVE = 'Y' AND ROWNUM = 1;

    v_encrypted := DBMS_CRYPTO.ENCRYPT(
        src => UTL_RAW.CAST_TO_RAW(v_secret),
        typ => DBMS_CRYPTO.ENCRYPT_AES256 +
               DBMS_CRYPTO.CHAIN_CBC       +
               DBMS_CRYPTO.PAD_PKCS5,
        key => v_key
    );

    UPDATE CRM_MPM_API_CREDENTIALS
    SET    CLIENT_SECRET_ENCRYPTED = v_encrypted,
           CLIENT_SECRET_REF       = '*** ENCRYPTED ***',
           ENCRYPT_KEY_REF         = 'CRM_INTEGRATION_KEY'
    WHERE  IS_ACTIVE = 'Y';
    COMMIT;

    DBMS_OUTPUT.PUT_LINE('SIT secret encrypted and stored');
END;
/
*/


-- =============================================================================
-- STEP 9: GRANT EXECUTE ON DBMS_CRYPTO IF NEEDED
-- Run as DBA if package compilation fails
-- =============================================================================
/*
GRANT EXECUTE ON DBMS_CRYPTO TO <your_schema>;
*/
