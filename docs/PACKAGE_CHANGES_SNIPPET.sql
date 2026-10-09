-- ============================================================
-- PKG_CRM_INTEGRATION_BODY — EXACT CHANGES ONLY
-- Date    : Oct 2026
-- Purpose : Sequential Dependency + PARENT_PENDING status
-- 
-- HOW TO USE:
-- Find each SEARCH text in your current package body
-- Add the ADD lines immediately after/before as indicated
-- Do NOT replace your entire package — only add these snippets
--
-- >>> THEN ALSO APPLY sql/SIT_PARENT_RELEASE_DEPLOY.sql (CHANGES 4-6) <<<
-- Without it, PARENT_PENDING children are never re-sent (watermark gap).
-- ============================================================

-- ============================================================
-- CHANGE 1 OF 3 — Variable Declaration
-- LOCATION: RUN_OUTBOUND_JOB procedure, DECLARE section
-- SEARCH FOR THIS LINE in your package:
--     v_status     VARCHAR2(20);
-- ADD THIS LINE immediately after it:
-- ============================================================

v_skipped    NUMBER := 0;  -- records skipped due to parent dependency

-- ============================================================
-- CHANGE 2 OF 3 — Dependency Check Block
-- LOCATION: RUN_OUTBOUND_JOB, inside the FETCH loop
-- SEARCH FOR THIS LINE in your package:
--     v_processed := v_processed + 1;
-- ADD THIS ENTIRE BLOCK immediately after that line,
-- BEFORE the existing BEGIN SEND_TO_APIC block:
-- ============================================================

-- *** ADD FROM HERE ***
-- SEQUENTIAL DEPENDENCY CHECK (CREATE services only)
-- Checks parent SUCCESS before sending child record
-- If parent not SUCCESS: inserts PARENT_PENDING log row and skips
IF reg.DEPENDS_ON_REGISTRY_ID IS NOT NULL
AND reg.PARENT_LINK_COL IS NOT NULL THEN
    DECLARE
        v_parent_key   VARCHAR2(500);
        v_parent_count NUMBER := 0;
    BEGIN
        -- Read parent key value from THIS record's source view
        EXECUTE IMMEDIATE
            'SELECT ' || reg.PARENT_LINK_COL ||
            ' FROM '  || reg.SOURCE_VIEW ||
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
            -- Parent not SUCCESS yet — insert PARENT_PENDING and skip
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
-- *** ADD UNTIL HERE — then your existing BEGIN SEND_TO_APIC continues ***

-- ============================================================
-- CHANGE 3 OF 3 — GOTO Label
-- LOCATION: RUN_OUTBOUND_JOB, end of the FETCH loop
-- SEARCH FOR THIS BLOCK in your package:
--     EXCEPTION
--         WHEN OTHERS THEN
--             v_failed := v_failed + 1;
--     END;
-- END LOOP;
-- ADD <<next_record>> NULL; between END; and END LOOP;
-- ============================================================

            EXCEPTION
                WHEN OTHERS THEN
                    v_failed := v_failed + 1;
            END;

            -- *** ADD THESE 2 LINES ***
            <<next_record>>
            NULL; -- GOTO target for dependency skip
            -- *** END ADD ***

        END LOOP;

-- ============================================================
-- ALSO NEEDED: Change outbound job to run every 15 minutes
-- Run this SQL separately after package is compiled:
-- ============================================================
/*
BEGIN
    DBMS_SCHEDULER.DISABLE('CRM_MPM_OUTBOUND_JOB');
    DBMS_SCHEDULER.SET_ATTRIBUTE(
        name      => 'CRM_MPM_OUTBOUND_JOB',
        attribute => 'REPEAT_INTERVAL',
        value     => 'FREQ=MINUTELY;INTERVAL=15');
    DBMS_SCHEDULER.ENABLE('CRM_MPM_OUTBOUND_JOB');
END;
/
*/

-- ============================================================
-- VERIFY AFTER DEPLOYING PACKAGE:
-- ============================================================
/*
-- Both must show STATUS = VALID
SELECT OBJECT_NAME, OBJECT_TYPE, STATUS
FROM   USER_OBJECTS
WHERE  OBJECT_NAME = 'PKG_CRM_INTEGRATION'
ORDER  BY OBJECT_TYPE;
*/
