DECLARE
  v_hold_id        NUMBER;
  v_avail_after    NUMBER;
  v_hold_after     NUMBER;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- Test: tc_01_happy_path_simple — Successfully place a hold, available decreases and hold_amount increases
  BEGIN
    pkg_account_mgmt.place_hold(100000, 1000, 'Test hold', v_hold_id);
    SELECT available_balance, hold_amount
    INTO   v_avail_after, v_hold_after
    FROM   accounts WHERE account_id = 100000;
    ROLLBACK;
    IF v_avail_after = 4000 AND v_hold_after = 1000 AND v_hold_id IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path_simple|OK|avail:' || v_avail_after || ' hold:' || v_hold_after || ' hold_id:' || v_hold_id);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path_simple|FAIL|avail:' || v_avail_after || ' hold:' || v_hold_after || ' hold_id:' || v_hold_id);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path_simple|FAIL|' || SQLERRM);
  END;

  -- Test: tc_02_exact_available — Hold amount exactly equal to available_balance succeeds
  BEGIN
    pkg_account_mgmt.place_hold(100004, 800, 'Exact hold', v_hold_id);
    SELECT available_balance, hold_amount
    INTO   v_avail_after, v_hold_after
    FROM   accounts WHERE account_id = 100004;
    ROLLBACK;
    IF v_avail_after = 0 AND v_hold_after = 800 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_exact_available|OK|avail:' || v_avail_after || ' hold:' || v_hold_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_exact_available|FAIL|avail:' || v_avail_after || ' hold:' || v_hold_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_exact_available|FAIL|' || SQLERRM);
  END;

  -- Test: tc_03_insufficient_balance — Raise -20001 when hold amount exceeds available_balance
  BEGIN
    pkg_account_mgmt.place_hold(100004, 801, 'Over hold', v_hold_id);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_insufficient_balance|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20001 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_insufficient_balance|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_insufficient_balance|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_04_hold_id_not_null — Returned hold_id is always a positive number
  BEGIN
    pkg_account_mgmt.place_hold(100001, 500, 'Hold ID check', v_hold_id);
    ROLLBACK;
    IF v_hold_id > 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_hold_id_not_null|OK|hold_id:' || v_hold_id);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_hold_id_not_null|FAIL|hold_id:' || v_hold_id);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_hold_id_not_null|FAIL|' || SQLERRM);
  END;

  -- Test: tc_05_hold_ids_unique — Two consecutive calls return different hold_ids
  DECLARE
    v_hold_id_1 NUMBER;
    v_hold_id_2 NUMBER;
  BEGIN
    pkg_account_mgmt.place_hold(100001, 100, 'First hold',  v_hold_id_1);
    pkg_account_mgmt.place_hold(100001, 100, 'Second hold', v_hold_id_2);
    ROLLBACK;
    IF v_hold_id_1 <> v_hold_id_2 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_hold_ids_unique|OK|id1:' || v_hold_id_1 || ' id2:' || v_hold_id_2);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_hold_ids_unique|FAIL|duplicate_hold_id:' || v_hold_id_1);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_hold_ids_unique|FAIL|' || SQLERRM);
  END;

  -- Test: tc_06_balance_unchanged — balance column is not affected by hold, only available_balance changes
  DECLARE
    v_balance_before NUMBER;
    v_balance_after  NUMBER;
  BEGIN
    SELECT balance INTO v_balance_before FROM accounts WHERE account_id = 100000;
    pkg_account_mgmt.place_hold(100000, 2000, 'Balance check', v_hold_id);
    SELECT balance INTO v_balance_after FROM accounts WHERE account_id = 100000;
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

  -- Test: tc_07_cumulative_holds — Two sequential holds accumulate correctly on hold_amount and available_balance
  DECLARE
    v_hold_id_1 NUMBER;
    v_hold_id_2 NUMBER;
  BEGIN
    pkg_account_mgmt.place_hold(100003, 10000, 'First hold',  v_hold_id_1);
    pkg_account_mgmt.place_hold(100003, 5000,  'Second hold', v_hold_id_2);
    SELECT available_balance, hold_amount
    INTO   v_avail_after, v_hold_after
    FROM   accounts WHERE account_id = 100003;
    ROLLBACK;
    IF v_avail_after = 35000 AND v_hold_after = 15000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_cumulative_holds|OK|avail:' || v_avail_after || ' hold:' || v_hold_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_cumulative_holds|FAIL|avail:' || v_avail_after || ' hold:' || v_hold_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_cumulative_holds|FAIL|' || SQLERRM);
  END;

  -- Test: tc_08_second_hold_exceeds_reduced_available — Second hold fails after first hold reduces available
  DECLARE
    v_hold_id_1 NUMBER;
    v_hold_id_2 NUMBER;
  BEGIN
    pkg_account_mgmt.place_hold(100004, 700, 'First hold', v_hold_id_1);  -- avail: 800 → 100
    pkg_account_mgmt.place_hold(100004, 200, 'Over hold',  v_hold_id_2);  -- avail: 100 < 200 → fail
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_second_hold_exceeds_reduced_available|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20001 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_second_hold_exceeds_reduced_available|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_second_hold_exceeds_reduced_available|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_09_zero_amount — Raise -20001 when hold amount is 0 (0 < avail is false, but 0 not meaningful)
  -- Note: procedure checks v_avail < p_amount; 0 < 5000 is FALSE so hold proceeds — verify actual behaviour
  BEGIN
    pkg_account_mgmt.place_hold(100000, 0, 'Zero hold', v_hold_id);
    SELECT available_balance, hold_amount
    INTO   v_avail_after, v_hold_after
    FROM   accounts WHERE account_id = 100000;
    ROLLBACK;
    IF v_avail_after = 5000 AND v_hold_after = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_zero_amount|OK|zero_hold_no_change:avail:' || v_avail_after || ' hold:' || v_hold_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_zero_amount|FAIL|avail:' || v_avail_after || ' hold:' || v_hold_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_zero_amount|FAIL|' || SQLERRM);
  END;

  -- Test: tc_10_nonexistent_account — NO_DATA_FOUND for account_id that does not exist
  BEGIN
    pkg_account_mgmt.place_hold(999999, 100, 'Ghost hold', v_hold_id);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_nonexistent_account|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = 100 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_nonexistent_account|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_nonexistent_account|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_11_null_account_id — NO_DATA_FOUND for NULL account_id
  BEGIN
    pkg_account_mgmt.place_hold(NULL, 100, 'Null account', v_hold_id);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_null_account_id|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = 100 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_null_account_id|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_null_account_id|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_12_null_amount — NULL amount: v_avail < NULL evaluates to NULL (not TRUE) so hold proceeds with NULL deduction
  -- Note: This is an edge case — verify actual behaviour; procedure has no explicit NULL guard on p_amount
  BEGIN
    pkg_account_mgmt.place_hold(100000, NULL, 'Null amount', v_hold_id);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_null_amount|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE IN (-20001, 100, -6502) THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_null_amount|OK|exception_raised:' || SQLCODE);
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_null_amount|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

END;
/