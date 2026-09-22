-- =============================================================================
-- WALLET PASSWORD ENCRYPTION
-- Encrypts WALLET_PASSWORD column in CRM_MPM_API_CREDENTIALS
-- Follows exact same pattern as CLIENT_SECRET encryption
-- Author : ADIB EA Team (Tajudeen Jalaudin)
-- Date   : 2026-09-18
-- Run    : Top to bottom. Parts 1-4 safe to run anytime.
--          Part 5 (clear plain text) only AFTER Part 4 passes.
-- =============================================================================

SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED


-- =============================================================================
-- PART 1: ADD WALLET PASSWORD ENCRYPTED COLUMNS
-- =============================================================================

-- Add WALLET_PASSWORD_ENC BLOB
BEGIN
    EXECUTE IMMEDIATE
        'ALTER TABLE CRM_MPM_API_CREDENTIALS
         ADD WALLET_PASSWORD_ENC BLOB';
    DBMS_OUTPUT.PUT_LINE('✅ WALLET_PASSWORD_ENC BLOB column added');
EXCEPTION
    WHEN OTHERS THEN
        BEGIN
            -- Already exists as wrong type -- drop and recreate
            EXECUTE IMMEDIATE
                'ALTER TABLE CRM_MPM_API_CREDENTIALS
                 DROP COLUMN WALLET_PASSWORD_ENC';
            EXECUTE IMMEDIATE
                'ALTER TABLE CRM_MPM_API_CREDENTIALS
                 ADD WALLET_PASSWORD_ENC BLOB';
            DBMS_OUTPUT.PUT_LINE('✅ WALLET_PASSWORD_ENC recreated as BLOB');
        EXCEPTION
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('WALLET_PASSWORD_ENC: ' || SQLERRM);
        END;
END;
/

-- Add WALLET_PWD_KEY_REF (tracks which encryption key was used)
BEGIN
    EXECUTE IMMEDIATE
        'ALTER TABLE CRM_MPM_API_CREDENTIALS
         ADD WALLET_PWD_KEY_REF VARCHAR2(100)';
    DBMS_OUTPUT.PUT_LINE('✅ WALLET_PWD_KEY_REF column added');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('WALLET_PWD_KEY_REF exists: ' || SQLERRM);
END;
/

-- Verify columns added
SELECT COLUMN_NAME, DATA_TYPE, NULLABLE
FROM   USER_TAB_COLUMNS
WHERE  TABLE_NAME  = 'CRM_MPM_API_CREDENTIALS'
AND    COLUMN_NAME IN (
    'WALLET_PASSWORD',
    'WALLET_PASSWORD_ENC',
    'WALLET_PWD_KEY_REF',
    'CLIENT_SECRET_ENCRYPTED',
    'ENCRYPT_KEY_REF'
)
ORDER BY COLUMN_ID;


-- =============================================================================
-- PART 2: ENCRYPT EXISTING WALLET PASSWORDS
-- =============================================================================
DECLARE
    v_key       RAW(32);
    v_encrypted BLOB;
    v_count     NUMBER := 0;
    v_skipped   NUMBER := 0;
BEGIN
    -- Get master key (same key used for CLIENT_SECRET)
    SELECT ENCRYPT_KEY INTO v_key
    FROM   CRM_MPM_ENCRYPT_CONFIG
    WHERE  IS_ACTIVE = 'Y'
    AND    ROWNUM    = 1;

    -- Loop all active credentials with a wallet password
    FOR rec IN (
        SELECT ROWID,
               CRED_CODE,
               WALLET_PASSWORD
        FROM   CRM_MPM_API_CREDENTIALS
        WHERE  IS_ACTIVE        = 'Y'
        AND    WALLET_PASSWORD  IS NOT NULL
        AND    WALLET_PASSWORD  != '*** ENCRYPTED ***'
    ) LOOP
        BEGIN
            -- Encrypt plain text wallet password to BLOB
            v_encrypted := DBMS_CRYPTO.ENCRYPT(
                src => UTL_RAW.CAST_TO_RAW(rec.WALLET_PASSWORD),
                typ => DBMS_CRYPTO.ENCRYPT_AES256 +
                       DBMS_CRYPTO.CHAIN_CBC       +
                       DBMS_CRYPTO.PAD_PKCS5,
                key => v_key
            );

            -- Store encrypted
            UPDATE CRM_MPM_API_CREDENTIALS
            SET    WALLET_PASSWORD_ENC = v_encrypted,
                   WALLET_PWD_KEY_REF  = 'CRM_INTEGRATION_KEY'
            WHERE  ROWID = rec.ROWID;

            v_count := v_count + 1;
            DBMS_OUTPUT.PUT_LINE('✅ Encrypted wallet password for: ' || rec.CRED_CODE);

        EXCEPTION
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('❌ ERROR encrypting ' || rec.CRED_CODE || ': ' || SQLERRM);
        END;
    END LOOP;

    -- Count rows with no wallet password
    SELECT COUNT(*) INTO v_skipped
    FROM   CRM_MPM_API_CREDENTIALS
    WHERE  IS_ACTIVE       = 'Y'
    AND   (WALLET_PASSWORD IS NULL OR WALLET_PASSWORD = '*** ENCRYPTED ***');

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('✅ Wallet passwords encrypted : ' || v_count);
    DBMS_OUTPUT.PUT_LINE('ℹ️  Rows skipped (null/done)  : ' || v_skipped);

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('❌ No encryption key found in CRM_MPM_ENCRYPT_CONFIG');
        DBMS_OUTPUT.PUT_LINE('   Run ENCRYPTION_COMPLETE_READY.sql Part 1 first');
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('❌ ENCRYPT ERROR: ' || SQLERRM);
END;
/


-- =============================================================================
-- PART 3: TEST DECRYPT -- MUST PASS BEFORE CLEARING PLAIN TEXT
-- =============================================================================
DECLARE
    v_key       RAW(32);
    v_encrypted BLOB;
    v_decrypted VARCHAR2(4000);
    v_original  VARCHAR2(4000);
    v_cred_code VARCHAR2(50);
BEGIN
    SELECT ENCRYPT_KEY INTO v_key
    FROM   CRM_MPM_ENCRYPT_CONFIG
    WHERE  IS_ACTIVE = 'Y'
    AND    ROWNUM    = 1;

    -- Pick first encrypted wallet password
    SELECT WALLET_PASSWORD_ENC,
           WALLET_PASSWORD,
           CRED_CODE
    INTO   v_encrypted,
           v_original,
           v_cred_code
    FROM   CRM_MPM_API_CREDENTIALS
    WHERE  IS_ACTIVE           = 'Y'
    AND    WALLET_PASSWORD_ENC IS NOT NULL
    AND    WALLET_PASSWORD     IS NOT NULL
    AND    WALLET_PASSWORD     != '*** ENCRYPTED ***'
    AND    ROWNUM              = 1;

    -- Decrypt
    v_decrypted := UTL_RAW.CAST_TO_VARCHAR2(
        DBMS_CRYPTO.DECRYPT(
            src => v_encrypted,
            typ => DBMS_CRYPTO.ENCRYPT_AES256 +
                   DBMS_CRYPTO.CHAIN_CBC       +
                   DBMS_CRYPTO.PAD_PKCS5,
            key => v_key
        )
    );

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('=== DECRYPT TEST: ' || v_cred_code || ' ===');

    IF v_decrypted = v_original THEN
        DBMS_OUTPUT.PUT_LINE('✅ DECRYPT TEST PASSED');
        DBMS_OUTPUT.PUT_LINE('   Original length : ' || LENGTH(v_original));
        DBMS_OUTPUT.PUT_LINE('   Decrypted length: ' || LENGTH(v_decrypted));
        DBMS_OUTPUT.PUT_LINE('   Match           : YES ✅');
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('>>> SAFE TO RUN PART 4 (clear plain text) <<<');
    ELSE
        DBMS_OUTPUT.PUT_LINE('❌ DECRYPT TEST FAILED -- DO NOT RUN PART 4');
        DBMS_OUTPUT.PUT_LINE('   Original  : ' || v_original);
        DBMS_OUTPUT.PUT_LINE('   Decrypted : ' || v_decrypted);
    END IF;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('ℹ️  No wallet passwords to test');
        DBMS_OUTPUT.PUT_LINE('   Either WALLET_PASSWORD is NULL or already cleared');
        DBMS_OUTPUT.PUT_LINE('   If credentials have no wallet -- this is fine, skip Part 4');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('❌ DECRYPT ERROR: ' || SQLERRM);
END;
/


-- =============================================================================
-- PART 4: CLEAR PLAIN TEXT WALLET PASSWORD
-- *** ONLY RUN AFTER PART 3 SHOWS "DECRYPT TEST PASSED" ***
-- Uncomment the block below when ready
-- =============================================================================
/*
UPDATE CRM_MPM_API_CREDENTIALS
SET    WALLET_PASSWORD = '*** ENCRYPTED ***'
WHERE  IS_ACTIVE           = 'Y'
AND    WALLET_PASSWORD_ENC IS NOT NULL;
COMMIT;
DBMS_OUTPUT.PUT_LINE('✅ Plain text wallet passwords cleared');
*/


-- =============================================================================
-- PART 5: PACKAGE CHANGE -- GET_BEARER_TOKEN wallet password decrypt
-- Apply this change in PKG_CRM_INTEGRATION body
-- Find the section that opens the Oracle Wallet and replace:
--
--   UTL_HTTP.SET_WALLET(v_cred.WALLET_PATH, v_cred.WALLET_PASSWORD);
--
-- With:
--
--   DECLARE
--       v_wallet_pwd VARCHAR2(4000);
--       v_key        RAW(32);
--   BEGIN
--       IF v_cred.WALLET_PASSWORD_ENC IS NOT NULL THEN
--           SELECT ENCRYPT_KEY INTO v_key
--           FROM   CRM_MPM_ENCRYPT_CONFIG
--           WHERE  IS_ACTIVE = 'Y' AND ROWNUM = 1;
--
--           v_wallet_pwd := UTL_RAW.CAST_TO_VARCHAR2(
--               DBMS_CRYPTO.DECRYPT(
--                   src => v_cred.WALLET_PASSWORD_ENC,
--                   typ => DBMS_CRYPTO.ENCRYPT_AES256 +
--                          DBMS_CRYPTO.CHAIN_CBC       +
--                          DBMS_CRYPTO.PAD_PKCS5,
--                   key => v_key
--               )
--           );
--       ELSE
--           v_wallet_pwd := v_cred.WALLET_PASSWORD;  -- fallback plain text
--       END IF;
--       UTL_HTTP.SET_WALLET(v_cred.WALLET_PATH, v_wallet_pwd);
--   END;
--
-- Also update the SELECT in GET_BEARER_TOKEN cursor to include new columns:
--   SELECT ..., WALLET_PASSWORD_ENC, WALLET_PWD_KEY_REF
-- =============================================================================
DBMS_OUTPUT.PUT_LINE('ℹ️  See Part 5 comments for GET_BEARER_TOKEN package change');


-- =============================================================================
-- PART 6: VERIFY FINAL STATE
-- =============================================================================
DBMS_OUTPUT.PUT_LINE('');
DBMS_OUTPUT.PUT_LINE('=== FINAL ENCRYPTION STATUS ===');

SELECT
    CRED_CODE,
    CASE WHEN CLIENT_SECRET_ENCRYPTED IS NOT NULL
         THEN '✅ AES256' ELSE '❌ PLAIN' END  AS CLIENT_SECRET_STATUS,
    CASE WHEN WALLET_PASSWORD_ENC IS NOT NULL
         THEN '✅ AES256'
         WHEN WALLET_PASSWORD IS NULL
         THEN 'N/A (no wallet)'
         ELSE '❌ PLAIN'
    END                                        AS WALLET_PWD_STATUS,
    ENCRYPT_KEY_REF,
    WALLET_PWD_KEY_REF
FROM CRM_MPM_API_CREDENTIALS
WHERE IS_ACTIVE = 'Y'
ORDER BY CRED_CODE;
