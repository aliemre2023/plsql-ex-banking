DECLARE
  v_status_after VARCHAR2(20);
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- Test: tc_01_freeze_active_account — Successfully freeze an ACTIVE account
  BEGIN
    pkg_account_mgmt.freeze_account(100000, 'Suspicious activity', 2000);
    SELECT status INTO v_status_after FROM accounts WHERE account_id = 100000;
    ROLLBACK;
    IF v_status_after = 'FROZEN' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_freeze_active_account|OK|status:' || v_status_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_freeze_active_account|FAIL|expected:FROZEN got:' || v_status_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_freeze_active_account|FAIL|' || SQLERRM);
  END;

  -- Test: tc_02_freeze_inactive_account — Successfully freeze an INACTIVE account (not CLOSED)
  BEGIN
    UPDATE accounts SET status = 'INACTIVE' WHERE account_id = 100001;
    pkg_account_mgmt.freeze_account(100001, 'Compliance hold', 2001);
    SELECT status INTO v_status_after FROM accounts WHERE account_id = 100001;
    ROLLBACK;
    IF v_status_after = 'FROZEN' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_freeze_inactive_account|OK|status:' || v_status_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_freeze_inactive_account|FAIL|expected:FROZEN got:' || v_status_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_freeze_inactive_account|FAIL|' || SQLERRM);
  END;

  -- Test: tc_03_freeze_dormant_account — Successfully freeze a DORMANT account (not CLOSED)
  BEGIN
    UPDATE accounts SET status = 'DORMANT' WHERE account_id = 100002;
    pkg_account_mgmt.freeze_account(100002, 'Fraud investigation', 2000);
    SELECT status INTO v_status_after FROM accounts WHERE account_id = 100002;
    ROLLBACK;
    IF v_status_after = 'FROZEN' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_freeze_dormant_account|OK|status:' || v_status_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_freeze_dormant_account|FAIL|expected:FROZEN got:' || v_status_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_freeze_dormant_account|FAIL|' || SQLERRM);
  END;

  -- Test: tc_04_freeze_already_frozen — Freezing an already FROZEN account succeeds (no guard against it)
  BEGIN
    UPDATE accounts SET status = 'FROZEN' WHERE account_id = 100003;
    pkg_account_mgmt.freeze_account(100003, 'Re-freeze', 2001);
    SELECT status INTO v_status_after FROM accounts WHERE account_id = 100003;
    ROLLBACK;
    IF v_status_after = 'FROZEN' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_freeze_already_frozen|OK|status:' || v_status_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_freeze_already_frozen|FAIL|expected:FROZEN got:' || v_status_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_freeze_already_frozen|FAIL|' || SQLERRM);
  END;

  -- Test: tc_05_freeze_closed_account — Raise -20003 when attempting to freeze a CLOSED account
  BEGIN
    UPDATE accounts SET status = 'CLOSED' WHERE account_id = 100004;
    pkg_account_mgmt.freeze_account(100004, 'Should fail', 2000);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_freeze_closed_account|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20003 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_freeze_closed_account|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_freeze_closed_account|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_06_status_persisted — Status is FROZEN in DB after procedure call (not just in-memory)
  BEGIN
    pkg_account_mgmt.freeze_account(100005, 'Verify persistence', 2002);
    SELECT status INTO v_status_after FROM accounts WHERE account_id = 100005;
    ROLLBACK;
    IF v_status_after = 'FROZEN' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_status_persisted|OK|status:' || v_status_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_status_persisted|FAIL|expected:FROZEN got:' || v_status_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_status_persisted|FAIL|' || SQLERRM);
  END;

  -- Test: tc_07_updated_at_refreshed — updated_at timestamp is refreshed after freeze
  DECLARE
    v_updated_before TIMESTAMP;
    v_updated_after  TIMESTAMP;
  BEGIN
    SELECT updated_at INTO v_updated_before FROM accounts WHERE account_id = 100000;
    DBMS_LOCK.SLEEP(1); -- 1 saniyelik fark yaratmak için
    pkg_account_mgmt.freeze_account(100000, 'Timestamp check', 2000);
    SELECT updated_at INTO v_updated_after FROM accounts WHERE account_id = 100000;
    ROLLBACK;
    IF v_updated_after > v_updated_before THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_updated_at_refreshed|OK|before:' || v_updated_before || ' after:' || v_updated_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_updated_at_refreshed|FAIL|before:' || v_updated_before || ' after:' || v_updated_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_updated_at_refreshed|FAIL|' || SQLERRM);
  END;

  -- Test: tc_08_nonexistent_account — NO_DATA_FOUND for account_id that does not exist
  BEGIN
    pkg_account_mgmt.freeze_account(999999, 'Ghost account', 2000);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_nonexistent_account|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = 100 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_nonexistent_account|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_nonexistent_account|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_09_null_account_id — NO_DATA_FOUND for NULL account_id
  BEGIN
    pkg_account_mgmt.freeze_account(NULL, 'Null account', 2000);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_null_account_id|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = 100 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_null_account_id|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_null_account_id|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_10_null_reason — Freeze succeeds with NULL reason (no guard in procedure)
  BEGIN
    pkg_account_mgmt.freeze_account(100006, NULL, 2003);
    SELECT status INTO v_status_after FROM accounts WHERE account_id = 100006;
    ROLLBACK;
    IF v_status_after = 'FROZEN' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_null_reason|OK|status:' || v_status_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_null_reason|FAIL|expected:FROZEN got:' || v_status_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_null_reason|FAIL|' || SQLERRM);
  END;

  -- Test: tc_11_null_employee_id — Freeze succeeds with NULL employee_id (no guard in procedure)
  BEGIN
    pkg_account_mgmt.freeze_account(100000, 'No employee', NULL);
    SELECT status INTO v_status_after FROM accounts WHERE account_id = 100000;
    ROLLBACK;
    IF v_status_after = 'FROZEN' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_null_employee_id|OK|status:' || v_status_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_null_employee_id|FAIL|expected:FROZEN got:' || v_status_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_null_employee_id|FAIL|' || SQLERRM);
  END;

END;
/