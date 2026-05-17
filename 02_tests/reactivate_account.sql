DECLARE
  v_status_after VARCHAR2(20);
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- Test: tc_01_reactivate_dormant — Successfully reactivate a DORMANT account
  BEGIN
    UPDATE accounts SET status = 'DORMANT' WHERE account_id = 100000;
    pkg_account_mgmt.reactivate_account(100000, 2000);
    SELECT status INTO v_status_after FROM accounts WHERE account_id = 100000;
    ROLLBACK;
    IF v_status_after = 'ACTIVE' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_reactivate_dormant|OK|status:' || v_status_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_reactivate_dormant|FAIL|expected:ACTIVE got:' || v_status_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_reactivate_dormant|FAIL|' || SQLERRM);
  END;

  -- Test: tc_02_reactivate_inactive — Successfully reactivate an INACTIVE account
  BEGIN
    UPDATE accounts SET status = 'INACTIVE' WHERE account_id = 100001;
    pkg_account_mgmt.reactivate_account(100001, 2001);
    SELECT status INTO v_status_after FROM accounts WHERE account_id = 100001;
    ROLLBACK;
    IF v_status_after = 'ACTIVE' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_reactivate_inactive|OK|status:' || v_status_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_reactivate_inactive|FAIL|expected:ACTIVE got:' || v_status_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_reactivate_inactive|FAIL|' || SQLERRM);
  END;

  -- Test: tc_03_reactivate_active — Raise -20019 when account is already ACTIVE
  BEGIN
    pkg_account_mgmt.reactivate_account(100002, 2000);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_reactivate_active|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20019 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_reactivate_active|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_reactivate_active|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_04_reactivate_frozen — Raise -20019 when account is FROZEN
  BEGIN
    UPDATE accounts SET status = 'FROZEN' WHERE account_id = 100003;
    pkg_account_mgmt.reactivate_account(100003, 2001);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_reactivate_frozen|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20019 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_reactivate_frozen|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_reactivate_frozen|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_05_reactivate_closed — Raise -20019 when account is CLOSED
  BEGIN
    UPDATE accounts SET status = 'CLOSED' WHERE account_id = 100004;
    pkg_account_mgmt.reactivate_account(100004, 2002);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_reactivate_closed|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20019 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_reactivate_closed|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_reactivate_closed|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_06_nonexistent_account — NO_DATA_FOUND for account_id that does not exist
  BEGIN
    pkg_account_mgmt.reactivate_account(999999, 2000);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_nonexistent_account|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = 100 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_nonexistent_account|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_nonexistent_account|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_07_null_account_id — NO_DATA_FOUND for NULL account_id
  BEGIN
    pkg_account_mgmt.reactivate_account(NULL, 2000);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_null_account_id|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = 100 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_null_account_id|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_null_account_id|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_08_null_employee_id — Reactivation succeeds with NULL employee_id (no guard in procedure)
  BEGIN
    UPDATE accounts SET status = 'DORMANT' WHERE account_id = 100005;
    pkg_account_mgmt.reactivate_account(100005, NULL);
    SELECT status INTO v_status_after FROM accounts WHERE account_id = 100005;
    ROLLBACK;
    IF v_status_after = 'ACTIVE' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_null_employee_id|OK|status:' || v_status_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_null_employee_id|FAIL|expected:ACTIVE got:' || v_status_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_null_employee_id|FAIL|' || SQLERRM);
  END;

  -- Test: tc_09_updated_at_refreshed — updated_at timestamp refreshed after reactivation
  DECLARE
    v_updated_before TIMESTAMP;
    v_updated_after  TIMESTAMP;
  BEGIN
    UPDATE accounts SET status = 'INACTIVE' WHERE account_id = 100006;
    SELECT updated_at INTO v_updated_before FROM accounts WHERE account_id = 100006;
    DBMS_LOCK.SLEEP(1);
    pkg_account_mgmt.reactivate_account(100006, 2003);
    SELECT updated_at INTO v_updated_after FROM accounts WHERE account_id = 100006;
    ROLLBACK;
    IF v_updated_after > v_updated_before THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_updated_at_refreshed|OK|before:' || v_updated_before || ' after:' || v_updated_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_updated_at_refreshed|FAIL|before:' || v_updated_before || ' after:' || v_updated_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_updated_at_refreshed|FAIL|' || SQLERRM);
  END;

  -- Test: tc_10_dormant_reactivate_cycle — mark_dormant_accounts then reactivate restores ACTIVE
  DECLARE
    v_status VARCHAR2(20);
    c_days   NUMBER := 365;
  BEGIN
    UPDATE accounts
    SET    last_transaction_date = SYSDATE - (c_days + 1)
    WHERE  account_id = 100000;
    pkg_account_mgmt.mark_dormant_accounts();
    SELECT status INTO v_status FROM accounts WHERE account_id = 100000;
    IF v_status = 'DORMANT' THEN
      pkg_account_mgmt.reactivate_account(100000, 2000);
      SELECT status INTO v_status_after FROM accounts WHERE account_id = 100000;
      ROLLBACK;
      IF v_status_after = 'ACTIVE' THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_dormant_reactivate_cycle|OK|status:' || v_status_after);
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_dormant_reactivate_cycle|FAIL|expected:ACTIVE got:' || v_status_after);
      END IF;
    ELSE
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_dormant_reactivate_cycle|FAIL|account_not_marked_dormant');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_dormant_reactivate_cycle|FAIL|' || SQLERRM);
  END;

END;
/