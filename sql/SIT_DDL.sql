-- =============================================================================
-- ADIB MPM PROPERTIES -- CRM xRM INTEGRATION
-- FILE : SIT_DDL.sql
-- DESC : DDL -- Sequences, Tables, Indexes (Package handled separately)
-- Author  : Tajudeen Jalaudin -- Senior Solution Architect, ADIB
-- Date    : 24 September 2026
-- =============================================================================
-- HOW TO USE:
--   Step 1 : Run this file on DEV in SQL*Plus  -->  @SIT_DDL.sql
--   Step 2 : File written to C:\temp\SIT_DDL_output.sql automatically
--   Step 3 : Run SIT_DDL_output.sql on SIT
-- =============================================================================

SET LONG          2000000
SET LONGCHUNKSIZE 32767
SET PAGESIZE      0
SET LINESIZE      32767
SET FEEDBACK      OFF
SET VERIFY        OFF
SET HEADING       OFF
SET ECHO          OFF
SET TRIMSPOOL     ON

-- SPOOL handles the file directly -- no directory or grants needed
SPOOL C:\temp\SIT_DDL_output.sql

SELECT '-- Generated from DEV: ' || TO_CHAR(SYSDATE,'DD-MON-YYYY HH24:MI:SS') FROM DUAL;
SELECT '-- Run this file on SIT database' FROM DUAL;
SELECT 'SET DEFINE OFF;' FROM DUAL;
SELECT 'WHENEVER SQLERROR CONTINUE;' FROM DUAL;

-- =============================================================================
-- PART 1: SEQUENCES
-- =============================================================================
SELECT '-- =============================================' FROM DUAL;
SELECT '-- PART 1: SEQUENCES' FROM DUAL;
SELECT '-- =============================================' FROM DUAL;

SELECT
    REPLACE(DBMS_METADATA.GET_DDL('SEQUENCE', SEQUENCE_NAME), '"APPS".', '')
    || CHR(10) || '/'
FROM USER_SEQUENCES
WHERE SEQUENCE_NAME LIKE 'CRM_MPM%'
ORDER BY SEQUENCE_NAME;

-- =============================================================================
-- PART 2: TABLES
-- =============================================================================
SELECT '-- =============================================' FROM DUAL;
SELECT '-- PART 2: TABLES' FROM DUAL;
SELECT '-- =============================================' FROM DUAL;

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
    REPLACE(DBMS_METADATA.GET_DDL('TABLE', TABLE_NAME), '"APPS".', '')
    || CHR(10) || '/'
FROM USER_TABLES
WHERE TABLE_NAME LIKE 'CRM_MPM%'
ORDER BY TABLE_NAME;

-- =============================================================================
-- PART 3: INDEXES
-- =============================================================================
SELECT '-- =============================================' FROM DUAL;
SELECT '-- PART 3: INDEXES' FROM DUAL;
SELECT '-- =============================================' FROM DUAL;

SELECT
    REPLACE(DBMS_METADATA.GET_DDL('INDEX', INDEX_NAME), '"APPS".', '')
    || CHR(10) || '/'
FROM USER_INDEXES
WHERE TABLE_NAME LIKE 'CRM_MPM%'
AND   INDEX_TYPE != 'LOB'
AND   INDEX_NAME NOT LIKE 'SYS_%'
ORDER BY TABLE_NAME, INDEX_NAME;

SELECT '-- END OF DDL SCRIPT' FROM DUAL;

SPOOL OFF

PROMPT Done. File saved to C:\temp\SIT_DDL_output.sql
