DECLARE
  v_count_before  NUMBER;
  v_count_dormant NUMBER;
  v_audit_count   NUMBER;
  -- c_dormancy_days paket sabitini varsayılan 365 olarak simüle ediyoruz
  -- Gerçek paketten okunuyorsa bu değeri pakete göre ayarlayın
  c_days          NUMBER := 365;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- Test: tc_01_no_eligible_accounts — No accounts updated when all opened today with no transactions
  -- Seed datadaki tüm account'lar bugün açılmış, last_transaction_date NULL → dormancy süresi dolmamış
  BEGIN
    SELECT COUNT(*) INTO v_count_before FROM accounts WHERE status = 'ACTIVE';
    pkg_account_mgmt.mark_dormant_accounts();
    SELECT COUNT(*) INTO v_count_dormant FROM accounts WHERE status = 'DORMANT';
    ROLLBACK;
    IF v_count_dormant = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_no_eligible_accounts|OK|dormant_count:' || v_count_dormant);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_no_eligible_accounts|FAIL|expected:0 got:' || v_count_dormant);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_no_eligible_accounts|FAIL|' || SQLERRM);
  END;

  -- Test: tc_02_null_txn_old_open_date — ACTIVE account with NULL last_transaction_date and old opened_date marked DORMANT
  BEGIN
    UPDATE accounts
    SET    opened_date           = SYSDATE - (c_days + 1),
           last_transaction_date = NULL
    WHERE  account_id = 100000;
    pkg_account_mgmt.mark_dormant_accounts();
    SELECT status INTO v_count_dormant FROM accounts WHERE account_id = 100000;
    ROLLBACK;
    IF v_count_dormant = 1 THEN -- reusing NUMBER as flag: 1 row updated
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_null_txn_old_open_date|OK|status:DORMANT');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_null_txn_old_open_date|FAIL|unexpected_status');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_null_txn_old_open_date|FAIL|' || SQLERRM);
  END;

  -- Test: tc_02_null_txn_old_open_date — rewrite with VARCHAR status check
  DECLARE
    v_status VARCHAR2(20);
  BEGIN
    UPDATE accounts
    SET    opened_date           = SYSDATE - (c_days + 1),
           last_transaction_date = NULL
    WHERE  account_id = 100000;
    pkg_account_mgmt.mark_dormant_accounts();
    SELECT status INTO v_status FROM accounts WHERE account_id = 100000;
    ROLLBACK;
    IF v_status = 'DORMANT' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_null_txn_old_open_date|OK|status:' || v_status);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_null_txn_old_open_date|FAIL|expected:DORMANT got:' || v_status);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_null_txn_old_open_date|FAIL|' || SQLERRM);
  END;

  -- Test: tc_03_old_last_txn_date — ACTIVE account with last_transaction_date older than c_dormancy_days marked DORMANT
  DECLARE
    v_status VARCHAR2(20);
  BEGIN
    UPDATE accounts
    SET    last_transaction_date = SYSDATE - (c_days + 1)
    WHERE  account_id = 100001;
    pkg_account_mgmt.mark_dormant_accounts();
    SELECT status INTO v_status FROM accounts WHERE account_id = 100001;
    ROLLBACK;
    IF v_status = 'DORMANT' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_old_last_txn_date|OK|status:' || v_status);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_old_last_txn_date|FAIL|expected:DORMANT got:' || v_status);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_old_last_txn_date|FAIL|' || SQLERRM);
  END;

  -- Test: tc_04_exact_boundary_not_dormant — last_transaction_date exactly = SYSDATE - c_days not marked DORMANT
  DECLARE
    v_status VARCHAR2(20);
  BEGIN
    UPDATE accounts
    SET    last_transaction_date = TRUNC(SYSDATE) - c_days
    WHERE  account_id = 100002;
    pkg_account_mgmt.mark_dormant_accounts();
    SELECT status INTO v_status FROM accounts WHERE account_id = 100002;
    ROLLBACK;
    IF v_status = 'ACTIVE' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_exact_boundary_not_dormant|OK|status:' || v_status);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_exact_boundary_not_dormant|FAIL|expected:ACTIVE got:' || v_status);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_exact_boundary_not_dormant|FAIL|' || SQLERRM);
  END;

  -- Test: tc_05_recent_txn_not_dormant — ACTIVE account with recent last_transaction_date not marked DORMANT
  DECLARE
    v_status VARCHAR2(20);
  BEGIN
    UPDATE accounts
    SET    last_transaction_date = SYSDATE - 30
    WHERE  account_id = 100003;
    pkg_account_mgmt.mark_dormant_accounts();
    SELECT status INTO v_status FROM accounts WHERE account_id = 100003;
    ROLLBACK;
    IF v_status = 'ACTIVE' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_recent_txn_not_dormant|OK|status:' || v_status);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_recent_txn_not_dormant|FAIL|expected:ACTIVE got:' || v_status);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_recent_txn_not_dormant|FAIL|' || SQLERRM);
  END;

  -- Test: tc_06_frozen_not_affected — FROZEN account not changed to DORMANT (WHERE status = 'ACTIVE')
  DECLARE
    v_status VARCHAR2(20);
  BEGIN
    UPDATE accounts
    SET    status                = 'FROZEN',
           last_transaction_date = SYSDATE - (c_days + 1)
    WHERE  account_id = 100004;
    pkg_account_mgmt.mark_dormant_accounts();
    SELECT status INTO v_status FROM accounts WHERE account_id = 100004;
    ROLLBACK;
    IF v_status = 'FROZEN' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_frozen_not_affected|OK|status:' || v_status);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_frozen_not_affected|FAIL|expected:FROZEN got:' || v_status);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_frozen_not_affected|FAIL|' || SQLERRM);
  END;

  -- Test: tc_07_closed_not_affected — CLOSED account not changed to DORMANT
  DECLARE
    v_status VARCHAR2(20);
  BEGIN
    UPDATE accounts
    SET    status                = 'CLOSED',
           last_transaction_date = SYSDATE - (c_days + 1)
    WHERE  account_id = 100004;
    pkg_account_mgmt.mark_dormant_accounts();
    SELECT status INTO v_status FROM accounts WHERE account_id = 100004;
    ROLLBACK;
    IF v_status = 'CLOSED' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_closed_not_affected|OK|status:' || v_status);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_closed_not_affected|FAIL|expected:CLOSED got:' || v_status);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_closed_not_affected|FAIL|' || SQLERRM);
  END;

  -- Test: tc_08_multiple_eligible — Multiple eligible accounts all marked DORMANT in one call
  DECLARE
    v_dormant_count NUMBER;
  BEGIN
    UPDATE accounts
    SET    last_transaction_date = SYSDATE - (c_days + 1)
    WHERE  account_id IN (100000, 100001, 100002);
    pkg_account_mgmt.mark_dormant_accounts();
    SELECT COUNT(*) INTO v_dormant_count
    FROM   accounts
    WHERE  account_id IN (100000, 100001, 100002)
    AND    status = 'DORMANT';
    ROLLBACK;
    IF v_dormant_count = 3 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_multiple_eligible|OK|dormant_count:' || v_dormant_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_multiple_eligible|FAIL|expected:3 got:' || v_dormant_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_multiple_eligible|FAIL|' || SQLERRM);
  END;

  -- Test: tc_09_audit_log_inserted — audit_log record inserted with correct table_name and action
  DECLARE
    v_audit_count NUMBER;
  BEGIN
    UPDATE accounts
    SET    last_transaction_date = SYSDATE - (c_days + 1)
    WHERE  account_id = 100001;
    pkg_account_mgmt.mark_dormant_accounts();
    SELECT COUNT(*) INTO v_audit_count
    FROM   audit_log
    WHERE  table_name  = 'ACCOUNTS'
    AND    record_id   = -1
    AND    action      = 'UPDATE'
    AND    TRUNC(changed_at) = TRUNC(SYSTIMESTAMP);
    ROLLBACK;
    IF v_audit_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_audit_log_inserted|OK|audit_count:' || v_audit_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_audit_log_inserted|FAIL|expected:>=1 got:' || v_audit_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_audit_log_inserted|FAIL|' || SQLERRM);
  END;

  -- Test: tc_10_null_open_date_boundary — opened_date exactly = SYSDATE - c_days with NULL txn not marked DORMANT
  DECLARE
    v_status VARCHAR2(20);
  BEGIN
    UPDATE accounts
    SET    opened_date           = TRUNC(SYSDATE) - c_days,
           last_transaction_date = NULL
    WHERE  account_id = 100005;
    pkg_account_mgmt.mark_dormant_accounts();
    SELECT status INTO v_status FROM accounts WHERE account_id = 100005;
    ROLLBACK;
    IF v_status = 'ACTIVE' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_null_open_date_boundary|OK|status:' || v_status);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_null_open_date_boundary|FAIL|expected:ACTIVE got:' || v_status);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_null_open_date_boundary|FAIL|' || SQLERRM);
  END;

END;
/