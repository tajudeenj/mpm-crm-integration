-- =============================================================================
-- ADIB MPM PROPERTIES -- CRM xRM INTEGRATION
-- FILE : SIT_DDL.sql
-- DESC : DDL only -- Sequences, Tables, Indexes (Package handled separately)
-- Run on DEV to generate SIT_DDL_output.sql then run that on SIT
-- Author  : Tajudeen Jalaudin -- Senior Solution Architect, ADIB
-- Date    : 24 September 2026
-- =============================================================================
-- HOW TO USE:
--   Step 1 : Run this file on DEV in SQL*Plus
--   Step 2 : Output spools to C:\temp\SIT_DDL_output.sql
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
SET SERVEROUTPUT  ON SIZE 1000000

-- =============================================================================
-- Create Oracle Directory for file output (run once as DBA if not exists)
-- GRANT READ,WRITE ON DIRECTORY CRM_EXPORT_DIR TO APPS;
-- CREATE OR REPLACE DIRECTORY CRM_EXPORT_DIR AS 'C:\temp';
-- =============================================================================

DECLARE
    v_file  UTL_FILE.FILE_TYPE;
    v_ddl   CLOB;
    v_len   NUMBER;
    v_pos   NUMBER;
    v_chunk VARCHAR2(32767);
    v_size  NUMBER := 32767;

    PROCEDURE write_ddl(p_ddl IN CLOB) IS
        v_l   NUMBER := 1;
        v_end NUMBER;
        v_line VARCHAR2(32767);
    BEGIN
        -- Write CLOB line by line preserving newlines
        v_l := 1;
        LOOP
            v_end := DBMS_LOB.INSTR(p_ddl, CHR(10), v_l);
            IF v_end = 0 OR v_end IS NULL THEN
                -- Last line
                v_line := DBMS_LOB.SUBSTR(p_ddl, 32767, v_l);
                IF v_line IS NOT NULL THEN
                    UTL_FILE.PUT_LINE(v_file, v_line);
                END IF;
                EXIT;
            END IF;
            v_line := DBMS_LOB.SUBSTR(p_ddl, v_end - v_l, v_l);
            UTL_FILE.PUT_LINE(v_file, NVL(v_line,' '));
            v_l := v_end + 1;
        END LOOP;
    END write_ddl;

BEGIN
    -- Open output file
    v_file := UTL_FILE.FOPEN('CRM_EXPORT_DIR', 'SIT_DDL_output.sql', 'W', 32767);

    -- Set DBMS_METADATA transform params
    DBMS_METADATA.SET_TRANSFORM_PARAM(
        DBMS_METADATA.SESSION_TRANSFORM,'STORAGE',FALSE);
    DBMS_METADATA.SET_TRANSFORM_PARAM(
        DBMS_METADATA.SESSION_TRANSFORM,'TABLESPACE',FALSE);
    DBMS_METADATA.SET_TRANSFORM_PARAM(
        DBMS_METADATA.SESSION_TRANSFORM,'SEGMENT_ATTRIBUTES',FALSE);
    DBMS_METADATA.SET_TRANSFORM_PARAM(
        DBMS_METADATA.SESSION_TRANSFORM,'SQLTERMINATOR',TRUE);

    UTL_FILE.PUT_LINE(v_file,'-- Generated from DEV on '||TO_CHAR(SYSDATE,'DD-MON-YYYY HH24:MI:SS'));
    UTL_FILE.PUT_LINE(v_file,'-- Run this file on SIT database');
    UTL_FILE.PUT_LINE(v_file,'SET DEFINE OFF');
    UTL_FILE.PUT_LINE(v_file,'WHENEVER SQLERROR CONTINUE');
    UTL_FILE.PUT_LINE(v_file,' ');

    -- =========================================================================
    -- PART 1: SEQUENCES
    -- =========================================================================
    UTL_FILE.PUT_LINE(v_file,'-- =============================================');
    UTL_FILE.PUT_LINE(v_file,'-- PART 1: SEQUENCES');
    UTL_FILE.PUT_LINE(v_file,'-- =============================================');

    FOR r IN (
        SELECT SEQUENCE_NAME FROM USER_SEQUENCES
        WHERE  SEQUENCE_NAME LIKE 'CRM_MPM%'
        ORDER  BY SEQUENCE_NAME
    ) LOOP
        v_ddl := DBMS_METADATA.GET_DDL('SEQUENCE', r.SEQUENCE_NAME);
        v_ddl := REPLACE(v_ddl, '"APPS".', '');
        write_ddl(v_ddl);
        UTL_FILE.PUT_LINE(v_file, '/');
        UTL_FILE.PUT_LINE(v_file, ' ');
    END LOOP;

    -- =========================================================================
    -- PART 2: TABLES
    -- =========================================================================
    UTL_FILE.PUT_LINE(v_file,'-- =============================================');
    UTL_FILE.PUT_LINE(v_file,'-- PART 2: TABLES');
    UTL_FILE.PUT_LINE(v_file,'-- =============================================');

    FOR r IN (
        SELECT TABLE_NAME FROM USER_TABLES
        WHERE  TABLE_NAME LIKE 'CRM_MPM%'
        ORDER  BY TABLE_NAME
    ) LOOP
        v_ddl := DBMS_METADATA.GET_DDL('TABLE', r.TABLE_NAME);
        v_ddl := REPLACE(v_ddl, '"APPS".', '');
        write_ddl(v_ddl);
        UTL_FILE.PUT_LINE(v_file, '/');
        UTL_FILE.PUT_LINE(v_file, ' ');
    END LOOP;

    -- =========================================================================
    -- PART 3: INDEXES
    -- =========================================================================
    UTL_FILE.PUT_LINE(v_file,'-- =============================================');
    UTL_FILE.PUT_LINE(v_file,'-- PART 3: INDEXES');
    UTL_FILE.PUT_LINE(v_file,'-- =============================================');

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
            write_ddl(v_ddl);
            UTL_FILE.PUT_LINE(v_file, '/');
            UTL_FILE.PUT_LINE(v_file, ' ');
        EXCEPTION
            WHEN OTHERS THEN NULL; -- skip system generated indexes
        END;
    END LOOP;

    UTL_FILE.PUT_LINE(v_file,' ');
    UTL_FILE.PUT_LINE(v_file,'-- END OF DDL SCRIPT');

    -- Close file
    UTL_FILE.FCLOSE(v_file);
    DBMS_OUTPUT.PUT_LINE('SUCCESS -- File written to CRM_EXPORT_DIR/SIT_DDL_output.sql');

EXCEPTION
    WHEN UTL_FILE.INVALID_PATH THEN
        DBMS_OUTPUT.PUT_LINE('ERROR: Directory CRM_EXPORT_DIR not found.');
        DBMS_OUTPUT.PUT_LINE('Run this as DBA first:');
        DBMS_OUTPUT.PUT_LINE('  CREATE OR REPLACE DIRECTORY CRM_EXPORT_DIR AS ''C:\temp'';');
        DBMS_OUTPUT.PUT_LINE('  GRANT READ,WRITE ON DIRECTORY CRM_EXPORT_DIR TO APPS;');
        IF UTL_FILE.IS_OPEN(v_file) THEN UTL_FILE.FCLOSE(v_file); END IF;
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
        IF UTL_FILE.IS_OPEN(v_file) THEN UTL_FILE.FCLOSE(v_file); END IF;
        RAISE;
END;
/
