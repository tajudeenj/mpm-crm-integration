-- ============================================================
-- SIT CREDENTIALS DEBUG QUERIES
-- Purpose : Diagnose token authentication failures on SIT
-- Run in  : SQL*Plus or SQL Developer on SIT environment
-- ============================================================

-- -------------------------------------------------------
-- QUERY 1: Check credentials with pipe delimiters
-- Reveals hidden spaces or extra characters in values
-- -------------------------------------------------------
SELECT CRED_CODE,
       '|' || GRANT_TYPE        || '|'  AS grant_type_check,
       '|' || CLIENT_ID         || '|'  AS client_id_check,
       '|' || CLIENT_SECRET_REF || '|'  AS secret_check,
       '|' || TOKEN_URL         || '|'  AS token_url_check,
       IS_ACTIVE
FROM   CRM_MPM_API_CREDENTIALS
WHERE  CRED_CODE = 'APIC_PXRM';

-- -------------------------------------------------------
-- QUERY 2: Check character lengths
-- If LENGTH differs from expected, hidden chars present
-- -------------------------------------------------------
SELECT CRED_CODE,
       LENGTH(GRANT_TYPE)        AS grant_type_len,
       LENGTH(CLIENT_ID)         AS client_id_len,
       LENGTH(CLIENT_SECRET_REF) AS secret_len,
       LENGTH(TOKEN_URL)         AS token_url_len
FROM   CRM_MPM_API_CREDENTIALS
WHERE  CRED_CODE = 'APIC_PXRM';

-- -------------------------------------------------------
-- QUERY 3: Fix if hidden spaces found — run this UPDATE
-- then COMMIT, then re-test token call
-- -------------------------------------------------------
/*
UPDATE CRM_MPM_API_CREDENTIALS
SET    GRANT_TYPE        = TRIM(GRANT_TYPE),
       CLIENT_ID         = TRIM(CLIENT_ID),
       CLIENT_SECRET_REF = TRIM(CLIENT_SECRET_REF),
       TOKEN_URL         = TRIM(TOKEN_URL)
WHERE  CRED_CODE = 'APIC_PXRM';
COMMIT;
*/

-- -------------------------------------------------------
-- QUERY 4: Force clean values — use if QUERY 1 shows
-- GRANT_TYPE is not exactly 'client_credentials'
-- Replace CLIENT_ID and CLIENT_SECRET_REF with real values
-- -------------------------------------------------------
/*
UPDATE CRM_MPM_API_CREDENTIALS
SET    GRANT_TYPE        = 'client_credentials',
       CLIENT_ID         = 'your_client_id_here',
       CLIENT_SECRET_REF = 'your_plain_secret_here',
       IS_ACTIVE         = 'Y'
WHERE  CRED_CODE = 'APIC_PXRM';
COMMIT;
*/
