-- =============================================================================
-- ADIB MPM PROPERTIES -- CRM xRM INTEGRATION
-- FILE : SIT_DDL.sql
-- DESC : DDL only -- Sequences, Tables, Indexes, Package Spec, Package Body
-- Run on DEV first to generate output, then run output on SIT
-- Author  : Tajudeen Jalaudin -- Senior Solution Architect, ADIB
-- Date    : 24 September 2026
-- =============================================================================
-- HOW TO USE:
--   Step 1 : Run this file on DEV using F5 in SQL*Plus or SQL Developer
--   Step 2 : Spool output to SIT_DDL_output.sql
--   Step 3 : Run SIT_DDL_output.sql on SIT
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

SPOOL C:\temp\SIT_DDL_output.sql

-- =============================================================================
-- PART 1: SEQUENCES
-- =============================================================================
PROMPT -- =============================================================================
PROMPT -- PART 1: SEQUENCES
PROMPT -- =============================================================================

DECLARE
    v_ddl CLOB;
BEGIN
    DBMS_METADATA.SET_TRANSFORM_PARAM(
        DBMS_METADATA.SESSION_TRANSFORM,'STORAGE',FALSE);
    DBMS_METADATA.SET_TRANSFORM_PARAM(
        DBMS_METADATA.SESSION_TRANSFORM,'TABLESPACE',FALSE);
    DBMS_METADATA.SET_TRANSFORM_PARAM(
        DBMS_METADATA.SESSION_TRANSFORM,'SEGMENT_ATTRIBUTES',FALSE);
    DBMS_METADATA.SET_TRANSFORM_PARAM(
        DBMS_METADATA.SESSION_TRANSFORM,'SQLTERMINATOR',TRUE);

    FOR r IN (
        SELECT SEQUENCE_NAME FROM USER_SEQUENCES
        WHERE  SEQUENCE_NAME LIKE 'CRM_MPM%'
        ORDER  BY SEQUENCE_NAME
    ) LOOP
        v_ddl := DBMS_METADATA.GET_DDL('SEQUENCE', r.SEQUENCE_NAME);
        v_ddl := REPLACE(v_ddl, '"APPS".', '');
        DBMS_OUTPUT.PUT_LINE(v_ddl);
        DBMS_OUTPUT.PUT_LINE('/');
    END LOOP;
END;
/

-- =============================================================================
-- PART 2: TABLES
-- =============================================================================
PROMPT -- =============================================================================
PROMPT -- PART 2: TABLES
PROMPT -- =============================================================================

DECLARE
    v_ddl CLOB;
BEGIN
    DBMS_METADATA.SET_TRANSFORM_PARAM(
        DBMS_METADATA.SESSION_TRANSFORM,'STORAGE',FALSE);
    DBMS_METADATA.SET_TRANSFORM_PARAM(
        DBMS_METADATA.SESSION_TRANSFORM,'TABLESPACE',FALSE);
    DBMS_METADATA.SET_TRANSFORM_PARAM(
        DBMS_METADATA.SESSION_TRANSFORM,'SEGMENT_ATTRIBUTES',FALSE);
    DBMS_METADATA.SET_TRANSFORM_PARAM(
        DBMS_METADATA.SESSION_TRANSFORM,'SQLTERMINATOR',TRUE);

    FOR r IN (
        SELECT TABLE_NAME FROM USER_TABLES
        WHERE  TABLE_NAME LIKE 'CRM_MPM%'
        ORDER  BY TABLE_NAME
    ) LOOP
        v_ddl := DBMS_METADATA.GET_DDL('TABLE', r.TABLE_NAME);
        v_ddl := REPLACE(v_ddl, '"APPS".', '');
        DBMS_OUTPUT.PUT_LINE(v_ddl);
        DBMS_OUTPUT.PUT_LINE('/');
    END LOOP;
END;
/

-- =============================================================================
-- PART 3: INDEXES
-- =============================================================================
PROMPT -- =============================================================================
PROMPT -- PART 3: INDEXES
PROMPT -- =============================================================================

DECLARE
    v_ddl CLOB;
BEGIN
    FOR r IN (
        SELECT INDEX_NAME FROM USER_INDEXES
        WHERE  TABLE_NAME LIKE 'CRM_MPM%'
        AND    INDEX_TYPE != 'LOB'
        AND    INDEX_NAME NOT LIKE 'SYS_%'
        ORDER  BY TABLE_NAME, INDEX_NAME
    ) LOOP
        BEGIN
            v_ddl := DBMS_METADATA.GET_DDL('INDEX', r.INDEX_NAME);
            v_ddl := REPLACE(v_ddl, '"APPS".', '');
            DBMS_OUTPUT.PUT_LINE(v_ddl);
            DBMS_OUTPUT.PUT_LINE('/');
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;
    END LOOP;
END;
/

-- =============================================================================
-- PART 4: PACKAGE SPEC
-- =============================================================================
PROMPT -- =============================================================================
PROMPT -- PART 4: PACKAGE SPEC
PROMPT -- =============================================================================

DECLARE
    v_ddl CLOB;
BEGIN
    v_ddl := DBMS_METADATA.GET_DDL('PACKAGE_SPEC','PKG_CRM_INTEGRATION');
    v_ddl := REPLACE(v_ddl, '"APPS".', '');
    DBMS_OUTPUT.PUT_LINE(v_ddl);
    DBMS_OUTPUT.PUT_LINE('/');
END;
/

-- =============================================================================
-- PART 5: PACKAGE BODY
-- =============================================================================
PROMPT -- =============================================================================
PROMPT -- PART 5: PACKAGE BODY
PROMPT -- =============================================================================

DECLARE
    v_ddl CLOB;
BEGIN
    v_ddl := DBMS_METADATA.GET_DDL('PACKAGE_BODY','PKG_CRM_INTEGRATION');
    v_ddl := REPLACE(v_ddl, '"APPS".', '');
    DBMS_OUTPUT.PUT_LINE(v_ddl);
    DBMS_OUTPUT.PUT_LINE('/');
END;
/

SPOOL OFF

PROMPT -- Done. Output saved to C:\temp\SIT_DDL_output.sql
