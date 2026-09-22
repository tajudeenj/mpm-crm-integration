/* ============================================================================
   CRM_MPM_UNIQUE_ID_CONFIG
   Single-row config table controlling x-unique-id format on the Oracle side.
   Mirrors Java's unique_id.* properties exactly — same format, same logic,
   so Oracle and Java NEVER disagree on what x-unique-id looks like.

   Format: <channel_id><timestamp><sequence>
     channel_id : fixed prefix (e.g. '814')
     timestamp  : TO_CHAR(SYSTIMESTAMP, timestamp_format)
     sequence   : zero-padded counter from CRM_MPM_UNIQUE_ID_SEQ, wraps per
                  sequence_digits (e.g. 4 digits -> 0001..9999 then back to 0001)

   To change the standard later — UPDATE this one row. No package recompile.
   ============================================================================ */

CREATE TABLE CRM_MPM_UNIQUE_ID_CONFIG (
    CONFIG_ID         NUMBER          DEFAULT 1 NOT NULL,
    CHANNEL_ID        VARCHAR2(10)    NOT NULL,
    TIMESTAMP_FORMAT  VARCHAR2(50)    NOT NULL,
    SEQUENCE_DIGITS   NUMBER          NOT NULL,
    IS_ACTIVE         VARCHAR2(1)     DEFAULT 'Y',
    UPDATED_DATE      TIMESTAMP       DEFAULT SYSTIMESTAMP,
    CONSTRAINT PK_CRM_UNIQUE_ID_CFG PRIMARY KEY (CONFIG_ID),
    CONSTRAINT CK_UNIQUE_ID_SINGLE_ROW CHECK (CONFIG_ID = 1)  -- enforce single row
);

-- Seed with current standard: 814 + yyyymmddhh24missff3 + 4-digit sequence
-- Matches Java exactly: channel_id=814, timestamp_format=yyyyMMddHHmmssSSS, sequence_digits=4
INSERT INTO CRM_MPM_UNIQUE_ID_CONFIG (CONFIG_ID, CHANNEL_ID, TIMESTAMP_FORMAT, SEQUENCE_DIGITS, IS_ACTIVE)
VALUES (1, '814', 'YYYYMMDDHH24MISSFF3', 4, 'Y');
COMMIT;

-- Sequence used for the rolling counter portion (wraps automatically via
-- MAXVALUE + CYCLE so it never needs manual reset)
CREATE SEQUENCE CRM_MPM_UNIQUE_ID_SEQ
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 9999
    MINVALUE 1
    CYCLE
    NOCACHE
    NOORDER;

COMMENT ON TABLE CRM_MPM_UNIQUE_ID_CONFIG IS
  'Single-row config controlling x-unique-id header format sent to APIC. Mirrors Java unique_id.* properties — keep both in sync if changed.';

PROMPT ============================================================
PROMPT  CRM_MPM_UNIQUE_ID_CONFIG and CRM_MPM_UNIQUE_ID_SEQ created.
PROMPT  Default: channel_id=814, format=YYYYMMDDHH24MISSFF3, 4-digit seq
PROMPT ============================================================
