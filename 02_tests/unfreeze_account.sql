DECLARE
  v_status_after VARCHAR2(20);
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- Test: tc_01_happy_path_unfreeze — Successfully unfreeze a FROZEN account, status becomes ACTIVE
  BEGIN
    UPDATE accounts SET status = 'FROZEN' WHERE account_id = 100000;
    pkg_account_mgmt.unfreeze_account(100000, 2000);
    SELECT status INTO v_status_after FROM accounts WHERE account_id = 100000;
    ROLLBACK;
    IF v_status_after = 'ACTIVE' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path_unfreeze|OK|status:' || v_status_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path_unfreeze|FAIL|expected:ACTIVE got:' || v_status_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path_unfreeze|FAIL|' || SQLERRM);
  END;

  -- Test: tc_02_active_account — Raise -20016 when account is already ACTIVE (not FROZEN)
  BEGIN
    pkg_account_mgmt.unfreeze_account(100001, 2000);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_active_account|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20016 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_active_account|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_active_account|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_03_closed_account — Raise -20016 when account is CLOSED (not FROZEN)
  BEGIN
    UPDATE accounts SET status = 'CLOSED' WHERE account_id = 100002;
    pkg_account_mgmt.unfreeze_account(100002, 2001);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_closed_account|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20016 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_closed_account|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_closed_account|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_04_inactive_account — Raise -20016 when account is INACTIVE (not FROZEN)
  BEGIN
    UPDATE accounts SET status = 'INACTIVE' WHERE account_id = 100003;
    pkg_account_mgmt.unfreeze_account(100003, 2001);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_inactive_account|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20016 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_inactive_account|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_inactive_account|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_05_dormant_account — Raise -20016 when account is DORMANT (not FROZEN)
  BEGIN
    UPDATE accounts SET status = 'DORMANT' WHERE account_id = 100004;
    pkg_account_mgmt.unfreeze_account(100004, 2002);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_dormant_account|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20016 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_dormant_account|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_dormant_account|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_06_nonexistent_account — Raise -20016 when account_id does not exist (ROWCOUNT = 0)
  BEGIN
    pkg_account_mgmt.unfreeze_account(999999, 2000);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_nonexistent_account|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20016 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_nonexistent_account|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_nonexistent_account|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_07_null_account_id — Raise -20016 for NULL account_id (WHERE matches nothing, ROWCOUNT = 0)
  BEGIN
    pkg_account_mgmt.unfreeze_account(NULL, 2000);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_null_account_id|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20016 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_null_account_id|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_null_account_id|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_08_null_employee_id — Unfreeze succeeds with NULL employee_id (no guard in procedure)
  BEGIN
    UPDATE accounts SET status = 'FROZEN' WHERE account_id = 100005;
    pkg_account_mgmt.unfreeze_account(100005, NULL);
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

  -- Test: tc_09_updated_at_refreshed — updated_at timestamp is refreshed after unfreeze
  DECLARE
    v_updated_before TIMESTAMP;
    v_updated_after  TIMESTAMP;
  BEGIN
    UPDATE accounts SET status = 'FROZEN' WHERE account_id = 100006;
    SELECT updated_at INTO v_updated_before FROM accounts WHERE account_id = 100006;
    DBMS_LOCK.SLEEP(1);
    pkg_account_mgmt.unfreeze_account(100006, 2003);
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

  -- Test: tc_10_freeze_then_unfreeze_cycle — freeze_account followed by pkg_account_mgmt.unfreeze_account restores ACTIVE status
  BEGIN
    freeze_account(100000, 'Cycle test', 2000);
    pkg_account_mgmt.unfreeze_account(100000, 2000);
    SELECT status INTO v_status_after FROM accounts WHERE account_id = 100000;
    ROLLBACK;
    IF v_status_after = 'ACTIVE' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_freeze_then_unfreeze_cycle|OK|status:' || v_status_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_freeze_then_unfreeze_cycle|FAIL|expected:ACTIVE got:' || v_status_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_freeze_then_unfreeze_cycle|FAIL|' || SQLERRM);
  END;

END;
/