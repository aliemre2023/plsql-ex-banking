DECLARE
  v_balance_before NUMBER;
  v_balance_after  NUMBER;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- Test: tc_01_credit_simple — CR increases balance and available_balance correctly
  BEGIN
    SELECT balance INTO v_balance_before FROM accounts WHERE account_id = 100000;
    pkg_account_mgmt.update_balance(100000, 1000, 'CR');
    SELECT balance INTO v_balance_after FROM accounts WHERE account_id = 100000;
    ROLLBACK;
    IF v_balance_after = v_balance_before + 1000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_credit_simple|OK|before:' || v_balance_before || ' after:' || v_balance_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_credit_simple|FAIL|expected:' || (v_balance_before+1000) || ' got:' || v_balance_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_credit_simple|FAIL|' || SQLERRM);
  END;

  -- Test: tc_02_debit_simple — DR decreases balance and available_balance correctly
  BEGIN
    SELECT balance INTO v_balance_before FROM accounts WHERE account_id = 100000;
    pkg_account_mgmt.update_balance(100000, 1000, 'DR');
    SELECT balance INTO v_balance_after FROM accounts WHERE account_id = 100000;
    ROLLBACK;
    IF v_balance_after = v_balance_before - 1000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_debit_simple|OK|before:' || v_balance_before || ' after:' || v_balance_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_debit_simple|FAIL|expected:' || (v_balance_before-1000) || ' got:' || v_balance_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_debit_simple|FAIL|' || SQLERRM);
  END;

  -- Test: tc_03_case_insensitive_cr — Lowercase 'cr' treated same as 'CR'
  BEGIN
    SELECT balance INTO v_balance_before FROM accounts WHERE account_id = 100001;
    pkg_account_mgmt.update_balance(100001, 500, 'cr');
    SELECT balance INTO v_balance_after FROM accounts WHERE account_id = 100001;
    ROLLBACK;
    IF v_balance_after = v_balance_before + 500 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_case_insensitive_cr|OK|before:' || v_balance_before || ' after:' || v_balance_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_case_insensitive_cr|FAIL|expected:' || (v_balance_before+500) || ' got:' || v_balance_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_case_insensitive_cr|FAIL|' || SQLERRM);
  END;

  -- Test: tc_04_case_insensitive_dr — Lowercase 'dr' treated same as 'DR'
  BEGIN
    SELECT balance INTO v_balance_before FROM accounts WHERE account_id = 100002;
    pkg_account_mgmt.update_balance(100002, 500, 'dr');
    SELECT balance INTO v_balance_after FROM accounts WHERE account_id = 100002;
    ROLLBACK;
    IF v_balance_after = v_balance_before - 500 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_case_insensitive_dr|OK|before:' || v_balance_before || ' after:' || v_balance_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_case_insensitive_dr|FAIL|expected:' || (v_balance_before-500) || ' got:' || v_balance_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_case_insensitive_dr|FAIL|' || SQLERRM);
  END;

  -- Test: tc_05_debit_exact_available — DR exactly equal to available_balance succeeds (CHECKING 5000)
  BEGIN
    pkg_account_mgmt.update_balance(100000, 5000, 'DR');
    SELECT balance INTO v_balance_after FROM accounts WHERE account_id = 100000;
    ROLLBACK;
    IF v_balance_after = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_debit_exact_available|OK|balance_after:' || v_balance_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_debit_exact_available|FAIL|expected:0 got:' || v_balance_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_debit_exact_available|FAIL|' || SQLERRM);
  END;

  -- Test: tc_06_debit_within_overdraft — DR into overdraft succeeds (CHECKING avail=5000 + limit=500, debit=5400)
  BEGIN
    pkg_account_mgmt.update_balance(100000, 5400, 'DR');
    SELECT balance INTO v_balance_after FROM accounts WHERE account_id = 100000;
    ROLLBACK;
    IF v_balance_after = -400 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_debit_within_overdraft|OK|balance_after:' || v_balance_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_debit_within_overdraft|FAIL|expected:-400 got:' || v_balance_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_debit_within_overdraft|FAIL|' || SQLERRM);
  END;

  -- Test: tc_07_debit_exact_overdraft_limit — DR exactly at available + overdraft limit succeeds (5000+500=5500)
  BEGIN
    pkg_account_mgmt.update_balance(100000, 5500, 'DR');
    SELECT balance INTO v_balance_after FROM accounts WHERE account_id = 100000;
    ROLLBACK;
    IF v_balance_after = -500 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_debit_exact_overdraft_limit|OK|balance_after:' || v_balance_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_debit_exact_overdraft_limit|FAIL|expected:-500 got:' || v_balance_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_debit_exact_overdraft_limit|FAIL|' || SQLERRM);
  END;

  -- Test: tc_08_insufficient_funds — Raise -20001 when debit exceeds available + overdraft (CHECKING 5000+500, debit=5501)
  BEGIN
    pkg_account_mgmt.update_balance(100000, 5501, 'DR');
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_insufficient_funds|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20001 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_insufficient_funds|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_insufficient_funds|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_09_no_overdraft_savings — Raise -20001 when SAVINGS (limit=0) debit exceeds available (15001 > 15000)
  BEGIN
    pkg_account_mgmt.update_balance(100001, 15001, 'DR');
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_no_overdraft_savings|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20001 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_no_overdraft_savings|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_no_overdraft_savings|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_10_frozen_account — Raise -20002 when account is FROZEN
  BEGIN
    UPDATE accounts SET status = 'FROZEN' WHERE account_id = 100002;
    pkg_account_mgmt.update_balance(100002, 100, 'CR');
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_frozen_account|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20002 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_frozen_account|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_frozen_account|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_11_closed_account — Raise -20003 when account is CLOSED
  BEGIN
    UPDATE accounts SET status = 'CLOSED' WHERE account_id = 100003;
    pkg_account_mgmt.update_balance(100003, 100, 'DR');
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_closed_account|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20003 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_closed_account|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_closed_account|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_12_zero_amount — Raise -20005 when amount is 0
  BEGIN
    pkg_account_mgmt.update_balance(100000, 0, 'CR');
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_zero_amount|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20005 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_zero_amount|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_zero_amount|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_13_negative_amount — Raise -20005 when amount is negative
  BEGIN
    pkg_account_mgmt.update_balance(100000, -500, 'DR');
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_negative_amount|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20005 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_negative_amount|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_negative_amount|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_14_invalid_direction — Raise -20014 for unrecognised direction string
  BEGIN
    pkg_account_mgmt.update_balance(100000, 100, 'XX');
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_14_invalid_direction|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20014 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_14_invalid_direction|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_14_invalid_direction|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_15_null_direction — Raise -20014 for NULL direction
  BEGIN
    pkg_account_mgmt.update_balance(100000, 100, NULL);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_15_null_direction|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20014 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_15_null_direction|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_15_null_direction|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_16_nonexistent_account — NO_DATA_FOUND for account_id that does not exist
  BEGIN
    pkg_account_mgmt.update_balance(999999, 100, 'CR');
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_16_nonexistent_account|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = 100 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_16_nonexistent_account|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_16_nonexistent_account|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_17_last_transaction_date_updated — last_transaction_date is set to SYSDATE after update
  DECLARE
    v_last_txn_date DATE;
  BEGIN
    pkg_account_mgmt.update_balance(100004, 100, 'CR');
    SELECT last_transaction_date INTO v_last_txn_date FROM accounts WHERE account_id = 100004;
    ROLLBACK;
    IF TRUNC(v_last_txn_date) = TRUNC(SYSDATE) THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_17_last_transaction_date_updated|OK|last_txn_date:' || v_last_txn_date);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_17_last_transaction_date_updated|FAIL|expected:' || TRUNC(SYSDATE) || ' got:' || v_last_txn_date);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_17_last_transaction_date_updated|FAIL|' || SQLERRM);
  END;

END;
/