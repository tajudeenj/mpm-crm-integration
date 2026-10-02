-- ============================================================
-- CRM Admin Web App — User Management Table
-- Run this on DEV and SIT before starting crm-admin-web.jar
-- ============================================================

CREATE TABLE CRM_MPM_APP_USERS (
    USERNAME        VARCHAR2(50)   NOT NULL,
    FULL_NAME       VARCHAR2(100),
    PASSWORD_HASH   VARCHAR2(200)  NOT NULL,   -- BCrypt hashed
    ROLE            VARCHAR2(20)   DEFAULT 'VIEWER' NOT NULL,
    -- Roles: ADMIN, OPERATOR, VIEWER
    IS_ACTIVE       CHAR(1)        DEFAULT 'Y' NOT NULL,
    ALLOWED_SERVICES VARCHAR2(2000),
    -- Comma-separated service names. NULL = access all services.
    LAST_LOGIN      DATE,
    CREATED_DATE    DATE           DEFAULT SYSDATE,
    UPDATED_DATE    DATE           DEFAULT SYSDATE,
    CONSTRAINT PK_CRM_APP_USERS PRIMARY KEY (USERNAME),
    CONSTRAINT CK_CRM_APP_USERS_ROLE CHECK (ROLE IN ('ADMIN','OPERATOR','VIEWER')),
    CONSTRAINT CK_CRM_APP_USERS_ACTIVE CHECK (IS_ACTIVE IN ('Y','N'))
);

COMMENT ON TABLE  CRM_MPM_APP_USERS IS 'Web admin tool users — managed via UI by ADMIN role';
COMMENT ON COLUMN CRM_MPM_APP_USERS.PASSWORD_HASH IS 'BCrypt encoded password — never store plain text';
COMMENT ON COLUMN CRM_MPM_APP_USERS.ROLE IS 'ADMIN=full, OPERATOR=monitor+retry, VIEWER=read-only';
COMMENT ON COLUMN CRM_MPM_APP_USERS.ALLOWED_SERVICES IS 'NULL means all services. CSV of SERVICE_NAME values to restrict.';

-- ── SEED: Initial admin user ─────────────────────────────────────────────────
-- Password: Adib@CRM2024  (BCrypt hash — change after first login)
INSERT INTO CRM_MPM_APP_USERS (USERNAME, FULL_NAME, PASSWORD_HASH, ROLE, IS_ACTIVE)
VALUES (
    'crmadmin',
    'CRM Administrator',
    '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lHqu',
    'ADMIN',
    'Y'
);

COMMIT;
