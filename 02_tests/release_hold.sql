DECLARE
  v_avail_after  NUMBER;
  v_hold_after   NUMBER;
  v_hold_id      NUMBER;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- Test: tc_01_happy_path_full_release — Release entire hold amount, available restored and hold_amount zeroed
  BEGIN
    UPDATE accounts SET available_balance = 4000, hold_amount = 1000 WHERE account_id = 100000;
    pkg_account_mgmt.release_hold(100000, 1000);
    SELECT available_balance, hold_amount INTO v_avail_after, v_hold_after
    FROM   accounts WHERE account_id = 100000;
    ROLLBACK;
    IF v_avail_after = 5000 AND v_hold_after = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path_full_release|OK|avail:' || v_avail_after || ' hold:' || v_hold_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path_full_release|FAIL|avail:' || v_avail_after || ' hold:' || v_hold_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path_full_release|FAIL|' || SQLERRM);
  END;

  -- Test: tc_02_partial_release — Release part of hold, remaining hold and available correct
  BEGIN
    UPDATE accounts SET available_balance = 40000, hold_amount = 10000 WHERE account_id = 100003;
    pkg_account_mgmt.release_hold(100003, 4000);
    SELECT available_balance, hold_amount INTO v_avail_after, v_hold_after
    FROM   accounts WHERE account_id = 100003;
    ROLLBACK;
    IF v_avail_after = 44000 AND v_hold_after = 6000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_partial_release|OK|avail:' || v_avail_after || ' hold:' || v_hold_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_partial_release|FAIL|avail:' || v_avail_after || ' hold:' || v_hold_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_partial_release|FAIL|' || SQLERRM);
  END;

  -- Test: tc_03_exact_hold_amount — Release exactly equal to hold_amount succeeds
  BEGIN
    UPDATE accounts SET available_balance = 74500, hold_amount = 500 WHERE account_id = 100006;
    pkg_account_mgmt.release_hold(100006, 500);
    SELECT available_balance, hold_amount INTO v_avail_after, v_hold_after
    FROM   accounts WHERE account_id = 100006;
    ROLLBACK;
    IF v_avail_after = 75000 AND v_hold_after = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_exact_hold_amount|OK|avail:' || v_avail_after || ' hold:' || v_hold_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_exact_hold_amount|FAIL|avail:' || v_avail_after || ' hold:' || v_hold_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_exact_hold_amount|FAIL|' || SQLERRM);
  END;

  -- Test: tc_04_release_exceeds_hold — Raise -20015 when release amount > hold_amount
  BEGIN
    UPDATE accounts SET available_balance = 4000, hold_amount = 1000 WHERE account_id = 100000;
    pkg_account_mgmt.release_hold(100000, 1001);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_release_exceeds_hold|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20015 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_release_exceeds_hold|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_release_exceeds_hold|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_05_release_on_zero_hold — Raise -20015 when hold_amount is 0 (seed data default)
  BEGIN
    pkg_account_mgmt.release_hold(100001, 100);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_release_on_zero_hold|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20015 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_release_on_zero_hold|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_release_on_zero_hold|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_06_balance_unchanged — balance column is not modified during hold release
  DECLARE
    v_balance_before NUMBER;
    v_balance_after  NUMBER;
  BEGIN
    UPDATE accounts SET available_balance = 49000, hold_amount = 1000 WHERE account_id = 100003;
    SELECT balance INTO v_balance_before FROM accounts WHERE account_id = 100003;
    pkg_account_mgmt.release_hold(100003, 1000);
    SELECT balance INTO v_balance_after FROM accounts WHERE account_id = 100003;
    ROLLBACK;
    IF v_balance_before = v_balance_after THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_balance_unchanged|OK|balance:' || v_balance_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_balance_unchanged|FAIL|before:' || v_balance_before || ' after:' || v_balance_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_balance_unchanged|FAIL|' || SQLERRM);
  END;

  -- Test: tc_07_sequential_releases — Two partial releases correctly reduce hold_amount step by step
  BEGIN
    UPDATE accounts SET available_balance = 115000, hold_amount = 10000 WHERE account_id = 100005;
    pkg_account_mgmt.release_hold(100005, 3000);
    pkg_account_mgmt.release_hold(100005, 4000);
    SELECT available_balance, hold_amount INTO v_avail_after, v_hold_after
    FROM   accounts WHERE account_id = 100005;
    ROLLBACK;
    IF v_avail_after = 122000 AND v_hold_after = 3000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_sequential_releases|OK|avail:' || v_avail_after || ' hold:' || v_hold_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_sequential_releases|FAIL|avail:' || v_avail_after || ' hold:' || v_hold_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_sequential_releases|FAIL|' || SQLERRM);
  END;

  -- Test: tc_08_nonexistent_account — NO_DATA_FOUND for account_id that does not exist
  BEGIN
    pkg_account_mgmt.release_hold(999999, 100);
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
    pkg_account_mgmt.release_hold(NULL, 100);
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

  -- Test: tc_10_zero_release_amount — Zero release amount: 0 <= hold, proceeds, no effective change
  BEGIN
    UPDATE accounts SET available_balance = 4500, hold_amount = 500 WHERE account_id = 100002;
    pkg_account_mgmt.release_hold(100002, 0);
    SELECT available_balance, hold_amount INTO v_avail_after, v_hold_after
    FROM   accounts WHERE account_id = 100002;
    ROLLBACK;
    IF v_avail_after = 4500 AND v_hold_after = 500 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_zero_release_amount|OK|avail:' || v_avail_after || ' hold:' || v_hold_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_zero_release_amount|FAIL|avail:' || v_avail_after || ' hold:' || v_hold_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_zero_release_amount|FAIL|' || SQLERRM);
  END;

END;
/