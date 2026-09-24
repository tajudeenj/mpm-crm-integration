-- =============================================================================
-- ADIB MPM PROPERTIES -- CRM xRM INTEGRATION
-- ORACLE WALLET SETUP FOR APIC HTTPS CALLS
-- Author  : Tajudeen Jalaudin -- Senior Solution Architect, ADIB
-- Date    : 24 September 2026
-- Purpose : Step by step guide to create Oracle Wallet, install APIC
--           certificate, and configure for UTL_HTTP HTTPS calls
-- =============================================================================
-- PRE-REQUISITES:
--   - Oracle DB server access (OS level)
--   - orapki or mkstore utility available (comes with Oracle client/db)
--   - APIC SSL certificate file (from APIC/network team)
--   - SYSDBA or DBA role to configure ACL
-- =============================================================================

/*
==============================================================================
PART 1: OS LEVEL STEPS (Run on Oracle DB Server as oracle user)
==============================================================================

STEP 1: Create wallet directory
-----------------------------------------------------------------------
mkdir -p /u01/app/oracle/wallet/sit_apic
chmod 700 /u01/app/oracle/wallet/sit_apic

STEP 2: Create the wallet with password
-----------------------------------------------------------------------
orapki wallet create \
    -wallet /u01/app/oracle/wallet/sit_apic \
    -pwd WalletPassw0rd \
    -auto_login

    -- -auto_login creates cwallet.sso (no password needed at runtime)
    -- Wallet directory will contain:
    --   ewallet.p12   (password protected wallet)
    --   cwallet.sso   (auto-login wallet -- used by Oracle at runtime)

STEP 3: Verify wallet created
-----------------------------------------------------------------------
orapki wallet display \
    -wallet /u01/app/oracle/wallet/sit_apic \
    -pwd WalletPassw0rd

    -- Should show: Requested Certificates: (empty at this stage)

STEP 4: Get APIC certificate
-----------------------------------------------------------------------
Option A -- Download from browser:
    Open https://apisitgatewaylb.adib.co.ae in Chrome
    Click padlock icon > Certificate > Details > Export
    Save as: apic_sit_cert.cer (Base64/PEM format)

Option B -- Using openssl on server:
    openssl s_client -connect apisitgatewaylb.adib.co.ae:443 \
        -showcerts </dev/null 2>/dev/null \
        | openssl x509 -outform PEM \
        > /tmp/apic_sit_cert.cer

Option C -- Get from APIC/network team:
    Ask them to provide the SSL certificate chain (.cer or .pem file)
    You may need root CA + intermediate CA + server cert (full chain)

STEP 5: Copy certificate to server
-----------------------------------------------------------------------
    scp apic_sit_cert.cer oracle@dbserver:/tmp/apic_sit_cert.cer

STEP 6: Add certificate to wallet (repeat for each cert in chain)
-----------------------------------------------------------------------
    -- Add root CA certificate first
    orapki wallet add \
        -wallet /u01/app/oracle/wallet/sit_apic \
        -trusted_cert \
        -cert /tmp/apic_sit_cert.cer \
        -pwd WalletPassw0rd

    -- If you have intermediate CA as well:
    orapki wallet add \
        -wallet /u01/app/oracle/wallet/sit_apic \
        -trusted_cert \
        -cert /tmp/apic_sit_intermediate.cer \
        -pwd WalletPassw0rd

STEP 7: Verify certificate added
-----------------------------------------------------------------------
    orapki wallet display \
        -wallet /u01/app/oracle/wallet/sit_apic \
        -pwd WalletPassw0rd

    -- Should now show certificate details under Trusted Certificates

STEP 8: Set correct permissions
-----------------------------------------------------------------------
    chown oracle:oinstall /u01/app/oracle/wallet/sit_apic/*
    chmod 600 /u01/app/oracle/wallet/sit_apic/*

==============================================================================
PART 2: ORACLE DB LEVEL STEPS (Run in SQL Developer as SYSDBA or DBA)
==============================================================================
*/

-- STEP 9: Create ACL (Access Control List) for UTL_HTTP outbound calls
-- This allows the schema user to make HTTP/HTTPS calls to APIC host
-- Run as SYSDBA
PROMPT --- STEP 9: CREATE ACL ---

BEGIN
    -- Create ACL
    DBMS_NETWORK_ACL_ADMIN.CREATE_ACL(
        acl         => 'apic_sit_acl.xml',
        description => 'APIC SIT Gateway HTTP access for MPM CRM Integration',
        principal   => 'XXMPM',          -- replace with your schema name
        is_grant    => TRUE,
        privilege   => 'connect'
    );

    -- Add resolve privilege
    DBMS_NETWORK_ACL_ADMIN.ADD_PRIVILEGE(
        acl       => 'apic_sit_acl.xml',
        principal => 'XXMPM',            -- replace with your schema name
        is_grant  => TRUE,
        privilege => 'resolve'
    );

    -- Assign ACL to APIC hostname
    DBMS_NETWORK_ACL_ADMIN.ASSIGN_ACL(
        acl  => 'apic_sit_acl.xml',
        host => 'apisitgatewaylb.adib.co.ae',
        lower_port => 443,
        upper_port => 443
    );

    -- Also assign for token endpoint if different host
    DBMS_NETWORK_ACL_ADMIN.ASSIGN_ACL(
        acl  => 'apic_sit_acl.xml',
        host => 'apisitgatewaylb.adib.co.ae',
        lower_port => 80,
        upper_port => 80
    );

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('ACL created and assigned');
EXCEPTION
    WHEN OTHERS THEN
        -- If ACL already exists update it
        DBMS_NETWORK_ACL_ADMIN.ADD_PRIVILEGE(
            acl       => 'apic_sit_acl.xml',
            principal => 'XXMPM',
            is_grant  => TRUE,
            privilege => 'connect'
        );
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('ACL updated: ' || SQLERRM);
END;
/

-- STEP 10: Verify ACL
PROMPT --- STEP 10: VERIFY ACL ---

SELECT HOST, LOWER_PORT, UPPER_PORT, ACL
FROM   DBA_NETWORK_ACLS
WHERE  ACL LIKE '%apic%';

SELECT ACL, PRINCIPAL, PRIVILEGE, IS_GRANT
FROM   DBA_NETWORK_ACL_PRIVILEGES
WHERE  ACL LIKE '%apic%';


-- STEP 11: Update wallet path and password in credentials table
PROMPT --- STEP 11: UPDATE WALLET PATH IN CREDENTIALS ---

UPDATE CRM_MPM_API_CREDENTIALS
SET    WALLET_PATH     = '/u01/app/oracle/wallet/sit_apic',
       WALLET_PASSWORD = 'WalletPassw0rd',
       UPDATED_DATE    = SYSTIMESTAMP
WHERE  CRED_CODE = 'APIC_PXRM';
COMMIT;

DBMS_OUTPUT.PUT_LINE('Wallet path updated in CRM_MPM_API_CREDENTIALS');

-- Verify
SELECT CRED_CODE, WALLET_PATH, WALLET_PASSWORD, IS_ACTIVE
FROM   CRM_MPM_API_CREDENTIALS
WHERE  CRED_CODE = 'APIC_PXRM';


-- STEP 12: Test wallet and HTTPS connection
PROMPT --- STEP 12: TEST WALLET AND HTTPS ---

DECLARE
    v_req   UTL_HTTP.REQ;
    v_resp  UTL_HTTP.RESP;
    v_url   VARCHAR2(500) := 'https://apisitgatewaylb.adib.co.ae:443/adib/oauth-client/oauth2/token';
BEGIN
    -- Set wallet
    UTL_HTTP.SET_WALLET(
        'file:/u01/app/oracle/wallet/sit_apic',
        'WalletPassw0rd'
    );
    UTL_HTTP.SET_TRANSFER_TIMEOUT(30);

    -- Try to open connection (just test connectivity)
    v_req  := UTL_HTTP.BEGIN_REQUEST(v_url, 'POST', 'HTTP/1.1');
    UTL_HTTP.SET_HEADER(v_req, 'Content-Type', 'application/x-www-form-urlencoded');
    UTL_HTTP.SET_HEADER(v_req, 'Content-Length', '0');
    v_resp := UTL_HTTP.GET_RESPONSE(v_req);

    DBMS_OUTPUT.PUT_LINE('Connection OK -- HTTP Status: '
        || v_resp.status_code || ' ' || v_resp.reason_phrase);
    UTL_HTTP.END_RESPONSE(v_resp);

EXCEPTION
    WHEN UTL_HTTP.TRANSFER_TIMEOUT THEN
        DBMS_OUTPUT.PUT_LINE('TIMEOUT -- check network/firewall to APIC host');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('Common causes:');
        DBMS_OUTPUT.PUT_LINE('  ORA-29273 -- certificate not in wallet or wrong path');
        DBMS_OUTPUT.PUT_LINE('  ORA-24247 -- ACL not configured (run Step 9)');
        DBMS_OUTPUT.PUT_LINE('  ORA-29276 -- connection refused (firewall/network)');
END;
/


-- STEP 13: Test full token call via package
PROMPT --- STEP 13: TEST GET_BEARER_TOKEN ---

DECLARE
    v_token VARCHAR2(4000);
BEGIN
    v_token := PKG_CRM_INTEGRATION.GET_BEARER_TOKEN('APIC_PXRM');

    IF v_token IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE('SUCCESS -- Token received');
        DBMS_OUTPUT.PUT_LINE('Token (first 50 chars): '
            || SUBSTR(v_token, 1, 50) || '...');
    ELSE
        DBMS_OUTPUT.PUT_LINE('FAILED -- Token is null');
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
END;
/

PROMPT
PROMPT =============================================================
PROMPT   WALLET SETUP COMPLETE CHECKLIST
PROMPT
PROMPT   OS Steps (on DB server):
PROMPT   [ ] Wallet directory created
PROMPT   [ ] Wallet created with orapki
PROMPT   [ ] APIC certificate obtained (.cer file)
PROMPT   [ ] Certificate added to wallet (orapki wallet add)
PROMPT   [ ] Certificate verified (orapki wallet display)
PROMPT   [ ] File permissions set (chmod 600)
PROMPT
PROMPT   DB Steps (in SQL Developer):
PROMPT   [ ] ACL created for APIC hostname port 443
PROMPT   [ ] WALLET_PATH updated in CRM_MPM_API_CREDENTIALS
PROMPT   [ ] WALLET_PASSWORD updated in CRM_MPM_API_CREDENTIALS
PROMPT   [ ] Step 12 test shows Connection OK
PROMPT   [ ] Step 13 test shows Token received
PROMPT
PROMPT   If all checked -- run SIT_ENCRYPT_SECRET.sql to encrypt
PROMPT   the CLIENT_SECRET before going live
PROMPT =============================================================
