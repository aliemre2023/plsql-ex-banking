DECLARE
  v_avail_after NUMBER;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- Test: tc_01_no_holds — available_balance = balance when hold_amount = 0 (seed data default)
  BEGIN
    pkg_account_mgmt.sync_available_balance(100000); -- balance=5000, hold=0 → available=5000
    SELECT available_balance INTO v_avail_after FROM accounts WHERE account_id = 100000;
    ROLLBACK;
    IF v_avail_after = 5000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_no_holds|OK|available:' || v_avail_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_no_holds|FAIL|expected:5000 got:' || v_avail_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_no_holds|FAIL|' || SQLERRM);
  END;

  -- Test: tc_02_with_hold — available_balance = balance - hold_amount when hold exists
  BEGIN
    UPDATE accounts SET balance = 5000, hold_amount = 1000 WHERE account_id = 100000;
    pkg_account_mgmt.sync_available_balance(100000);
    SELECT available_balance INTO v_avail_after FROM accounts WHERE account_id = 100000;
    ROLLBACK;
    IF v_avail_after = 4000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_with_hold|OK|available:' || v_avail_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_with_hold|FAIL|expected:4000 got:' || v_avail_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_with_hold|FAIL|' || SQLERRM);
  END;

  -- Test: tc_03_null_hold_amount — NULL hold_amount treated as 0 via NVL, available = balance
  BEGIN
    UPDATE accounts SET balance = 15000, hold_amount = NULL WHERE account_id = 100001;
    pkg_account_mgmt.sync_available_balance(100001);
    SELECT available_balance INTO v_avail_after FROM accounts WHERE account_id = 100001;
    ROLLBACK;
    IF v_avail_after = 15000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_null_hold_amount|OK|available:' || v_avail_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_null_hold_amount|FAIL|expected:15000 got:' || v_avail_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_null_hold_amount|FAIL|' || SQLERRM);
  END;

  -- Test: tc_04_hold_equals_balance — available_balance = 0 when hold_amount = balance
  BEGIN
    UPDATE accounts SET balance = 2500, hold_amount = 2500 WHERE account_id = 100002;
    pkg_account_mgmt.sync_available_balance(100002);
    SELECT available_balance INTO v_avail_after FROM accounts WHERE account_id = 100002;
    ROLLBACK;
    IF v_avail_after = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_hold_equals_balance|OK|available:' || v_avail_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_hold_equals_balance|FAIL|expected:0 got:' || v_avail_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_hold_equals_balance|FAIL|' || SQLERRM);
  END;

  -- Test: tc_05_hold_exceeds_balance — available_balance goes negative when hold > balance
  BEGIN
    UPDATE accounts SET balance = 800, hold_amount = 1000 WHERE account_id = 100004;
    pkg_account_mgmt.sync_available_balance(100004);
    SELECT available_balance INTO v_avail_after FROM accounts WHERE account_id = 100004;
    ROLLBACK;
    IF v_avail_after = -200 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_hold_exceeds_balance|OK|available:' || v_avail_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_hold_exceeds_balance|FAIL|expected:-200 got:' || v_avail_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_hold_exceeds_balance|FAIL|' || SQLERRM);
  END;

  -- Test: tc_06_stale_available_corrected — Stale available_balance corrected to balance - hold
  BEGIN
    UPDATE accounts SET balance = 50000, available_balance = 99999, hold_amount = 5000
    WHERE  account_id = 100003; -- available stale/wrong
    pkg_account_mgmt.sync_available_balance(100003);
    SELECT available_balance INTO v_avail_after FROM accounts WHERE account_id = 100003;
    ROLLBACK;
    IF v_avail_after = 45000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_stale_available_corrected|OK|available:' || v_avail_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_stale_available_corrected|FAIL|expected:45000 got:' || v_avail_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_stale_available_corrected|FAIL|' || SQLERRM);
  END;

  -- Test: tc_07_high_value_account — Correct sync for premium account (balance=125000, hold=10000)
  BEGIN
    UPDATE accounts SET balance = 125000, hold_amount = 10000 WHERE account_id = 100005;
    pkg_account_mgmt.sync_available_balance(100005);
    SELECT available_balance INTO v_avail_after FROM accounts WHERE account_id = 100005;
    ROLLBACK;
    IF v_avail_after = 115000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_high_value_account|OK|available:' || v_avail_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_high_value_account|FAIL|expected:115000 got:' || v_avail_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_high_value_account|FAIL|' || SQLERRM);
  END;

  -- Test: tc_08_nonexistent_account — No rows updated for non-existent account_id (silent, no exception)
  DECLARE
    v_rowcount NUMBER;
  BEGIN
    pkg_account_mgmt.sync_available_balance(999999);
    v_rowcount := SQL%ROWCOUNT;
    ROLLBACK;
    IF v_rowcount = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_nonexistent_account|OK|rowcount:' || v_rowcount);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_nonexistent_account|FAIL|expected:0 got:' || v_rowcount);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_nonexistent_account|FAIL|' || SQLERRM);
  END;

  -- Test: tc_09_null_account_id — No rows updated for NULL account_id (silent, no exception)
  DECLARE
    v_rowcount NUMBER;
  BEGIN
    pkg_account_mgmt.sync_available_balance(NULL);
    v_rowcount := SQL%ROWCOUNT;
    ROLLBACK;
    IF v_rowcount = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_null_account_id|OK|rowcount:' || v_rowcount);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_null_account_id|FAIL|expected:0 got:' || v_rowcount);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_null_account_id|FAIL|' || SQLERRM);
  END;

  -- Test: tc_10_updated_at_refreshed — updated_at timestamp refreshed after sync
  DECLARE
    v_updated_before TIMESTAMP;
    v_updated_after  TIMESTAMP;
  BEGIN
    SELECT updated_at INTO v_updated_before FROM accounts WHERE account_id = 100006;
    DBMS_LOCK.SLEEP(1);
    pkg_account_mgmt.sync_available_balance(100006);
    SELECT updated_at INTO v_updated_after FROM accounts WHERE account_id = 100006;
    ROLLBACK;
    IF v_updated_after > v_updated_before THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_updated_at_refreshed|OK|before:' || v_updated_before || ' after:' || v_updated_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_updated_at_refreshed|FAIL|before:' || v_updated_before || ' after:' || v_updated_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_updated_at_refreshed|FAIL|' || SQLERRM);
  END;

  -- Test: tc_11_balance_not_changed — balance column is not modified during sync
  DECLARE
    v_balance_before NUMBER;
    v_balance_after  NUMBER;
  BEGIN
    UPDATE accounts SET hold_amount = 3000 WHERE account_id = 100003;
    SELECT balance INTO v_balance_before FROM accounts WHERE account_id = 100003;
    pkg_account_mgmt.sync_available_balance(100003);
    SELECT balance INTO v_balance_after FROM accounts WHERE account_id = 100003;
    ROLLBACK;
    IF v_balance_before = v_balance_after THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_balance_not_changed|OK|balance:' || v_balance_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_balance_not_changed|FAIL|before:' || v_balance_before || ' after:' || v_balance_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_balance_not_changed|FAIL|' || SQLERRM);
  END;

END;
/