-- =============================================================================
-- ADIB MPM PROPERTIES -- CRM xRM INTEGRATION
-- GENERATE COMPLETE SIT SCRIPT FROM DEV DATABASE
-- Author  : Tajudeen Jalaudin -- Senior Solution Architect, ADIB
-- Date    : 24 September 2026
-- Run on  : DEV database as schema owner
-- Output  : Copy the spool file and run on SIT
-- =============================================================================
-- HOW TO USE:
--   1. Open SQL Developer on DEV database
--   2. Run this entire script
--   3. Copy the output (or spool to file)
--   4. Save as SIT_FROM_DEV.sql
--   5. Run SIT_FROM_DEV.sql on SIT database
-- =============================================================================

SET LONG          2000000
SET LONGCHUNKSIZE 2000000
SET PAGESIZE      0
SET LINESIZE      32767
SET FEEDBACK      OFF
SET VERIFY        OFF
SET HEADING       OFF
SET ECHO          OFF
SET TRIMSPOOL     ON
SET SERVEROUTPUT  ON SIZE UNLIMITED

-- Spool to file (update path as needed)
-- SPOOL /tmp/SIT_FROM_DEV.sql

PROMPT -- =================================================================
PROMPT -- ADIB MPM CRM INTEGRATION -- GENERATED FROM DEV
PROMPT -- Generated : SYS_DATE_HERE
PROMPT -- Source    : DEV Database
PROMPT -- Target    : SIT Database
PROMPT -- =================================================================
PROMPT SET DEFINE OFF
PROMPT SET FEEDBACK OFF
PROMPT WHENEVER SQLERROR CONTINUE
PROMPT

-- =============================================================================
-- PART 1: DDL -- SEQUENCES
-- =============================================================================
PROMPT PROMPT --- SEQUENCES ---
PROMPT

BEGIN
    DBMS_METADATA.SET_TRANSFORM_PARAM(
        DBMS_METADATA.SESSION_TRANSFORM,'STORAGE',FALSE);
    DBMS_METADATA.SET_TRANSFORM_PARAM(
        DBMS_METADATA.SESSION_TRANSFORM,'TABLESPACE',FALSE);
    DBMS_METADATA.SET_TRANSFORM_PARAM(
        DBMS_METADATA.SESSION_TRANSFORM,'SEGMENT_ATTRIBUTES',FALSE);
    DBMS_METADATA.SET_TRANSFORM_PARAM(
        DBMS_METADATA.SESSION_TRANSFORM,'SQLTERMINATOR',TRUE);
END;
/

SELECT
    'BEGIN EXECUTE IMMEDIATE '''
    || REPLACE(
        REPLACE(DBMS_METADATA.GET_DDL('SEQUENCE', SEQUENCE_NAME), CHR(10), ' '),
        '''', ''''''
       )
    || '''; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -955 THEN RAISE; END IF; END;'
    || CHR(10) || '/'
FROM USER_SEQUENCES
WHERE SEQUENCE_NAME LIKE 'CRM_MPM%'
ORDER BY SEQUENCE_NAME;


-- =============================================================================
-- PART 2: DDL -- TABLES (exact structure from DEV)
-- =============================================================================
PROMPT PROMPT --- TABLES ---
PROMPT

SELECT
    'BEGIN EXECUTE IMMEDIATE '''
    || REPLACE(
        REPLACE(DBMS_METADATA.GET_DDL('TABLE', TABLE_NAME), CHR(10), ' '),
        '''', ''''''
       )
    || '''; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -955 THEN RAISE; END IF; END;'
    || CHR(10) || '/'
FROM USER_TABLES
WHERE TABLE_NAME LIKE 'CRM_MPM%'
ORDER BY TABLE_NAME;


-- =============================================================================
-- PART 3: DDL -- INDEXES
-- =============================================================================
PROMPT PROMPT --- INDEXES ---
PROMPT

SELECT
    'BEGIN EXECUTE IMMEDIATE '''
    || REPLACE(
        REPLACE(DBMS_METADATA.GET_DDL('INDEX', INDEX_NAME), CHR(10), ' '),
        '''', ''''''
       )
    || '''; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -955 THEN RAISE; END IF; END;'
    || CHR(10) || '/'
FROM USER_INDEXES
WHERE TABLE_NAME LIKE 'CRM_MPM%'
AND   INDEX_TYPE  != 'LOB'
AND   INDEX_NAME  NOT LIKE 'SYS_%'
ORDER BY TABLE_NAME, INDEX_NAME;


-- =============================================================================
-- PART 4: DDL -- PACKAGE SPEC
-- =============================================================================
PROMPT PROMPT --- PACKAGE SPEC ---
PROMPT

SELECT DBMS_METADATA.GET_DDL('PACKAGE_SPEC','PKG_CRM_INTEGRATION')
    || CHR(10) || '/'
FROM DUAL;


-- =============================================================================
-- PART 5: DDL -- PACKAGE BODY
-- =============================================================================
PROMPT PROMPT --- PACKAGE BODY ---
PROMPT

SELECT DBMS_METADATA.GET_DDL('PACKAGE_BODY','PKG_CRM_INTEGRATION')
    || CHR(10) || '/'
FROM DUAL;


-- =============================================================================
-- PART 6: DATA -- ALL CRM_MPM TABLES
-- Pure INSERT statements generated directly from DEV
-- Tables deleted first for clean load
-- =============================================================================

PROMPT PROMPT --- DELETE ALL FOR CLEAN LOAD ---
PROMPT DELETE FROM CRM_MPM_API_WATERMARK;
PROMPT DELETE FROM CRM_MPM_API_FIELD_MAPPING;
PROMPT DELETE FROM CRM_MPM_API_REGISTRY;
PROMPT DELETE FROM CRM_MPM_API_CREDENTIALS;
PROMPT DELETE FROM CRM_MPM_ERROR_CODE_MASTER;
PROMPT DELETE FROM CRM_MPM_UNIQUE_ID_CONFIG;
PROMPT DELETE FROM CRM_MPM_ENCRYPT_CONFIG;
PROMPT COMMIT;
PROMPT

-- =============================================================================
PROMPT PROMPT --- DATA: CRM_MPM_ENCRYPT_CONFIG ---
PROMPT

SELECT
    'INSERT INTO CRM_MPM_ENCRYPT_CONFIG'
    ||' (CONFIG_ID,KEY_NAME,ENCRYPT_KEY,IS_ACTIVE,CREATED_DATE) VALUES ('
    || CONFIG_ID                                                        ||','
    ||''''|| KEY_NAME                                                   ||''',' 
    ||'HEXTORAW('''|| LOWER(RAWTOHEX(CAST(ENCRYPT_KEY AS RAW(32))))    ||'''),'
    ||''''|| NVL(IS_ACTIVE,'Y')                                         ||''',' 
    ||'SYSDATE);'
FROM CRM_MPM_ENCRYPT_CONFIG;

PROMPT COMMIT;
PROMPT

-- =============================================================================
PROMPT PROMPT --- DATA: CRM_MPM_UNIQUE_ID_CONFIG ---
PROMPT

SELECT
    'INSERT INTO CRM_MPM_UNIQUE_ID_CONFIG'
    ||' (CONFIG_ID,CHANNEL_ID,TIMESTAMP_FORMAT,SEQUENCE_DIGITS,IS_ACTIVE,UPDATED_DATE) VALUES ('
    || CONFIG_ID                                 ||','
    ||''''|| CHANNEL_ID                          ||''','
    ||''''|| TIMESTAMP_FORMAT                    ||''','
    || SEQUENCE_DIGITS                           ||','
    ||''''|| NVL(IS_ACTIVE,'Y')                  ||''','
    ||'SYSTIMESTAMP);'
FROM CRM_MPM_UNIQUE_ID_CONFIG;

PROMPT COMMIT;
PROMPT

-- =============================================================================
PROMPT PROMPT --- DATA: CRM_MPM_ERROR_CODE_MASTER ---
PROMPT

SELECT
    'INSERT INTO CRM_MPM_ERROR_CODE_MASTER'
    ||' (ERROR_CODE,ERROR_DESCRIPTION,IS_RETRYABLE,MATCHED_FRAGMENT,IS_ACTIVE,CREATED_DATE) VALUES ('
    ||''''|| ERROR_CODE                                                          ||''','
    ||''''|| REPLACE(NVL(ERROR_DESCRIPTION,''),'''','''''')                      ||''','
    ||''''|| NVL(IS_RETRYABLE,'N')                                               ||''','
    ||''''|| REPLACE(NVL(MATCHED_FRAGMENT,''),'''','''''')                       ||''','
    ||''''|| NVL(IS_ACTIVE,'Y')                                                  ||''','
    ||'SYSTIMESTAMP);'
FROM CRM_MPM_ERROR_CODE_MASTER
ORDER BY ERROR_CODE;

PROMPT COMMIT;
PROMPT

-- =============================================================================
PROMPT PROMPT --- DATA: CRM_MPM_API_CREDENTIALS ---
PROMPT
-- Confirmed columns from USER_TAB_COLUMNS (18 columns):
-- CRED_ID(NUMBER), CRED_CODE(VARCHAR2 50), TOKEN_URL(VARCHAR2 500),
-- CLIENT_ID(VARCHAR2 200), CLIENT_SECRET_REF(VARCHAR2 200),
-- SCOPE(VARCHAR2 200), GRANT_TYPE(VARCHAR2 50),
-- TOKEN_CACHE_VALUE(VARCHAR2 4000), TOKEN_EXPIRY(TIMESTAMP),
-- IS_ACTIVE(CHAR 1), CREATED_DATE(TIMESTAMP), UPDATED_DATE(TIMESTAMP),
-- WALLET_PATH(VARCHAR2 200), WALLET_PASSWORD(VARCHAR2 200),
-- CLIENT_SECRET_ENCRYPTED(BLOB), ENCRYPT_KEY_REF(VARCHAR2 100),
-- WALLET_PASSWORD_ENC(BLOB), WALLET_PWD_KEY_REF(VARCHAR2 100)
-- BLOB columns handled in PL/SQL -- cannot concat in SQL SELECT
DECLARE
    v_cs_hex  VARCHAR2(32767);
    v_wp_hex  VARCHAR2(32767);
BEGIN
    FOR r IN (
        SELECT CRED_ID, CRED_CODE, TOKEN_URL, CLIENT_ID,
               CLIENT_SECRET_REF, SCOPE, GRANT_TYPE,
               TOKEN_CACHE_VALUE, TOKEN_EXPIRY,
               IS_ACTIVE, WALLET_PATH, WALLET_PASSWORD,
               CLIENT_SECRET_ENCRYPTED,
               ENCRYPT_KEY_REF,
               WALLET_PASSWORD_ENC,
               WALLET_PWD_KEY_REF
        FROM   CRM_MPM_API_CREDENTIALS
    ) LOOP
        -- Convert BLOB to HEX string in PL/SQL (supports up to 32767)
        IF r.CLIENT_SECRET_ENCRYPTED IS NOT NULL
           AND DBMS_LOB.GETLENGTH(r.CLIENT_SECRET_ENCRYPTED) > 0 THEN
            v_cs_hex := LOWER(RAWTOHEX(
                DBMS_LOB.SUBSTR(r.CLIENT_SECRET_ENCRYPTED,
                    DBMS_LOB.GETLENGTH(r.CLIENT_SECRET_ENCRYPTED), 1)));
        ELSE
            v_cs_hex := NULL;
        END IF;

        IF r.WALLET_PASSWORD_ENC IS NOT NULL
           AND DBMS_LOB.GETLENGTH(r.WALLET_PASSWORD_ENC) > 0 THEN
            v_wp_hex := LOWER(RAWTOHEX(
                DBMS_LOB.SUBSTR(r.WALLET_PASSWORD_ENC,
                    DBMS_LOB.GETLENGTH(r.WALLET_PASSWORD_ENC), 1)));
        ELSE
            v_wp_hex := NULL;
        END IF;

        INSERT INTO CRM_MPM_API_CREDENTIALS (
            CRED_ID, CRED_CODE, TOKEN_URL, CLIENT_ID,
            CLIENT_SECRET_REF, SCOPE, GRANT_TYPE,
            TOKEN_CACHE_VALUE, TOKEN_EXPIRY,
            IS_ACTIVE, CREATED_DATE, UPDATED_DATE,
            WALLET_PATH, WALLET_PASSWORD,
            CLIENT_SECRET_ENCRYPTED,
            ENCRYPT_KEY_REF,
            WALLET_PASSWORD_ENC,
            WALLET_PWD_KEY_REF)
        VALUES (
            r.CRED_ID,
            r.CRED_CODE,
            r.TOKEN_URL,
            r.CLIENT_ID,
            r.CLIENT_SECRET_REF,
            r.SCOPE,
            r.GRANT_TYPE,
            r.TOKEN_CACHE_VALUE,
            r.TOKEN_EXPIRY,
            r.IS_ACTIVE,
            SYSTIMESTAMP,
            SYSTIMESTAMP,
            r.WALLET_PATH,
            r.WALLET_PASSWORD,
            CASE WHEN v_cs_hex IS NOT NULL
                 THEN TO_BLOB(HEXTORAW(v_cs_hex))
                 ELSE NULL END,
            r.ENCRYPT_KEY_REF,
            CASE WHEN v_wp_hex IS NOT NULL
                 THEN TO_BLOB(HEXTORAW(v_wp_hex))
                 ELSE NULL END,
            r.WALLET_PWD_KEY_REF
        );

        DBMS_OUTPUT.PUT_LINE('Inserted credential: ' || r.CRED_CODE);
    END LOOP;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Done: CRM_MPM_API_CREDENTIALS');
END;
/

-- =============================================================================
PROMPT PROMPT --- DATA: CRM_MPM_API_REGISTRY ---