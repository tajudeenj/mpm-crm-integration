-- ============================================================
-- PKG_CRM_INTEGRATION — PARENT_PENDING RELEASE (CHANGES 4-6)
-- Date    : 09-Oct-2026
-- Apply   : AFTER docs/PACKAGE_CHANGES_SNIPPET.sql (changes 1-3)
--
-- WHY THIS IS NEEDED
-- ------------------
-- Changes 1-3 log a child as PARENT_PENDING and GOTO next_record.
-- But at the end of the registry loop RUN_OUTBOUND_JOB advances the
-- watermark to MAX(SOURCE_FILTER_COL) of the whole view — including
-- the skipped child. The child is never re-read by the cursor again,
-- so without a release step it stays PARENT_PENDING forever.
--
-- Because callbacks are async (up to 60 min), the parent is almost
-- never SUCCESS in the same run, so Property -> Building -> Floor -> Unit
-- would stall at Building on every new property.
--
-- FIX: a release pass at the start of every outbound run picks up
-- PARENT_PENDING / PARENT_FAILED rows from the LOG (not the view, so the
-- watermark no longer matters) and sends them once the parent is SUCCESS.
--
-- STATUS LIFECYCLE (child)
--   PARENT_PENDING --parent SUCCESS--> RELEASED (+ new row SENT/...)
--   PARENT_PENDING --parent terminal fail--> PARENT_FAILED
--   PARENT_FAILED  --parent retried / SUCCESS--> PARENT_PENDING / RELEASED
--
-- Chain timing: each level waits for its parent's callback + next run
-- (15 min interval) => full Property->Unit chain ~ 4 x (callback + 15 min).
-- ============================================================


-- ============================================================
-- CHANGE 4 OF 6 — PACKAGE SPEC
-- File: sql/schema/PKG_CRM_INTEGRATION_SPEC_V2.sql
-- SEARCH FOR:
--     PROCEDURE RUN_OUTBOUND_JOB;
-- ADD THIS LINE immediately BEFORE it:
-- ============================================================

    PROCEDURE RELEASE_PARENT_PENDING;  -- releases children whose parent reached SUCCESS


-- ============================================================
-- CHANGE 5 OF 6 — PACKAGE BODY: new procedure
-- LOCATION: immediately BEFORE   PROCEDURE RUN_OUTBOUND_JOB IS
-- ============================================================

    PROCEDURE RELEASE_PARENT_PENDING IS
        v_parent_key     VARCHAR2(500);
        v_parent_ok      NUMBER;
        v_parent_status  VARCHAR2(30);
        v_new_log_id     NUMBER;
        v_err_msg        VARCHAR2(4000);
    BEGIN
        FOR p IN (
            SELECT L.LOG_ID, L.REGISTRY_ID, L.SOURCE_RECORD_ID, L.FINAL_STATUS,
                   R.DEPENDS_ON_REGISTRY_ID, R.PARENT_LINK_COL,
                   R.SOURCE_VIEW, R.SOURCE_KEY_COL
            FROM   CRM_MPM_CRM_INTEGRATION_LOG L
            JOIN   CRM_MPM_API_REGISTRY R ON R.REGISTRY_ID = L.REGISTRY_ID
            WHERE  L.FINAL_STATUS IN ('PARENT_PENDING','PARENT_FAILED')
            AND    R.IS_ACTIVE = 'Y'
            AND    R.DEPENDS_ON_REGISTRY_ID IS NOT NULL
            AND    R.PARENT_LINK_COL IS NOT NULL
            ORDER  BY R.EXECUTION_ORDER, L.LOG_ID
        ) LOOP
            BEGIN
                -- 1. Resolve parent key from the child's source view
                v_parent_key := NULL;
                BEGIN
                    EXECUTE IMMEDIATE
                        'SELECT ' || p.PARENT_LINK_COL ||
                        ' FROM '  || p.SOURCE_VIEW ||
                        ' WHERE ' || p.SOURCE_KEY_COL || ' = :k AND ROWNUM = 1'
                        INTO v_parent_key USING p.SOURCE_RECORD_ID;
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN v_parent_key := NULL;
                END;

                IF v_parent_key IS NOT NULL THEN

                    -- 2. Same rule as the outbound check: any SUCCESS row for parent
                    SELECT COUNT(*) INTO v_parent_ok
                    FROM   CRM_MPM_CRM_INTEGRATION_LOG
                    WHERE  REGISTRY_ID      = p.DEPENDS_ON_REGISTRY_ID
                    AND    SOURCE_RECORD_ID = v_parent_key
                    AND    FINAL_STATUS     = 'SUCCESS';

                    IF v_parent_ok > 0 THEN
                        -- 3. Send the child
                        v_new_log_id := NULL;
                        v_err_msg    := NULL;
                        BEGIN
                            SEND_TO_APIC(
                                p_registry_id => p.REGISTRY_ID,
                                p_key_value   => p.SOURCE_RECORD_ID,
                                p_attempt_no  => 1,
                                p_log_id_out  => v_new_log_id);
                        EXCEPTION
                            WHEN OTHERS THEN
                                v_err_msg := SQLERRM;
                                -- SEND_TO_APIC marks its own row FAILED before RAISE
                                -- (retry job owns it); OUT param is lost, so look it up
                                SELECT MAX(LOG_ID) INTO v_new_log_id
                                FROM   CRM_MPM_CRM_INTEGRATION_LOG
                                WHERE  REGISTRY_ID      = p.REGISTRY_ID
                                AND    SOURCE_RECORD_ID = p.SOURCE_RECORD_ID
                                AND    LOG_ID           > p.LOG_ID
                                AND    FINAL_STATUS NOT IN ('PARENT_PENDING','PARENT_FAILED','RELEASED');
                        END;

                        IF v_new_log_id IS NOT NULL THEN
                            UPDATE CRM_MPM_CRM_INTEGRATION_LOG
                            SET    FINAL_STATUS  = 'RELEASED',
                                   ERROR_MESSAGE = SUBSTR(ERROR_MESSAGE || ' | Released '
                                                   || TO_CHAR(SYSDATE,'DD-MON-YYYY HH24:MI')
                                                   || ' -> LOG_ID=' || v_new_log_id, 1, 4000),
                                   UPDATED_DATE  = SYSTIMESTAMP
                            WHERE  LOG_ID = p.LOG_ID;
                        ELSE
                            -- Nothing was logged: stay pending, try again next run
                            UPDATE CRM_MPM_CRM_INTEGRATION_LOG
                            SET    ERROR_MESSAGE = SUBSTR('Release attempt failed: ' || v_err_msg, 1, 4000),
                                   UPDATED_DATE  = SYSTIMESTAMP
                            WHERE  LOG_ID = p.LOG_ID;
                        END IF;

                    ELSE
                        -- 4. Parent not SUCCESS yet: flag terminal failures so they are visible
                        SELECT MAX(FINAL_STATUS) KEEP (DENSE_RANK LAST ORDER BY LOG_ID)
                        INTO   v_parent_status
                        FROM   CRM_MPM_CRM_INTEGRATION_LOG
                        WHERE  REGISTRY_ID      = p.DEPENDS_ON_REGISTRY_ID
                        AND    SOURCE_RECORD_ID = v_parent_key
                        AND    FINAL_STATUS    <> 'RELEASED';

                        IF v_parent_status IN ('EXHAUSTED','VALIDATION_FAILED',
                                               'RECORD_NOT_FOUND','CRM_REJECTED','PARENT_FAILED')
                           AND p.FINAL_STATUS = 'PARENT_PENDING' THEN
                            UPDATE CRM_MPM_CRM_INTEGRATION_LOG
                            SET    FINAL_STATUS  = 'PARENT_FAILED',
                                   ERROR_CODE    = 'PARENT_FAILED',
                                   ERROR_MESSAGE = SUBSTR('Parent Registry=' || p.DEPENDS_ON_REGISTRY_ID
                                                   || ' Key=' || v_parent_key
                                                   || ' is ' || v_parent_status, 1, 4000),
                                   UPDATED_DATE  = SYSTIMESTAMP
                            WHERE  LOG_ID = p.LOG_ID;
                        ELSIF (v_parent_status IS NULL OR v_parent_status NOT IN
                                  ('EXHAUSTED','VALIDATION_FAILED','RECORD_NOT_FOUND',
                                   'CRM_REJECTED','PARENT_FAILED'))
                           AND p.FINAL_STATUS = 'PARENT_FAILED' THEN
                            -- Parent was manually retried: back to waiting
                            UPDATE CRM_MPM_CRM_INTEGRATION_LOG
                            SET    FINAL_STATUS  = 'PARENT_PENDING',
                                   ERROR_CODE    = 'PARENT_PENDING',
                                   ERROR_MESSAGE = SUBSTR('Waiting for parent Registry='
                                                   || p.DEPENDS_ON_REGISTRY_ID
                                                   || ' Key=' || v_parent_key
                                                   || ' to reach SUCCESS status', 1, 4000),
                                   UPDATED_DATE  = SYSTIMESTAMP
                            WHERE  LOG_ID = p.LOG_ID;
                        END IF;
                    END IF;
                END IF;

                COMMIT;
            EXCEPTION
                WHEN OTHERS THEN
                    ROLLBACK;  -- one bad row must never stop the outbound job
            END;
        END LOOP;
    END RELEASE_PARENT_PENDING;


-- ============================================================
-- CHANGE 6 OF 6 — call the release pass
-- LOCATION: RUN_OUTBOUND_JOB, right after the job-lock insert:
-- SEARCH FOR:
--         INSERT INTO CRM_MPM_JOB_RUN_HISTORY (JOB_NAME, STATUS)
--         VALUES ('OUTBOUND_PUSH', 'RUNNING')
--         RETURNING RUN_ID INTO v_run_id;
--         COMMIT;
-- ADD immediately after that COMMIT:
-- ============================================================

        -- Release children whose parent has since reached SUCCESS
        BEGIN
            RELEASE_PARENT_PENDING;
        EXCEPTION
            WHEN OTHERS THEN NULL;  -- never block the main outbound run
        END;


-- ============================================================
-- NOTE ON SNIPPET (CHANGE 2) — no edit needed, just be aware
-- The PARENT_PENDING insert in CHANGE 2 leaves ERROR_CODE NULL.
-- The release pass sets ERROR_CODE on status changes, and the web
-- Monitor uses FINAL_STATUS, so this is cosmetic only.
-- ============================================================


-- ============================================================
-- VERIFY after compile
-- ============================================================
-- SELECT OBJECT_NAME, OBJECT_TYPE, STATUS FROM USER_OBJECTS
-- WHERE  OBJECT_NAME = 'PKG_CRM_INTEGRATION';
--
-- Manual test (no wait for the 15-min job):
-- BEGIN PKG_CRM_INTEGRATION.RELEASE_PARENT_PENDING; END;
-- /
-- SELECT LOG_ID, REGISTRY_ID, SOURCE_RECORD_ID, FINAL_STATUS, ERROR_MESSAGE
-- FROM   CRM_MPM_CRM_INTEGRATION_LOG
-- WHERE  FINAL_STATUS IN ('PARENT_PENDING','PARENT_FAILED','RELEASED')
-- ORDER  BY LOG_ID DESC;
