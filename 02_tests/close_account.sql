DECLARE
  v_final_balance NUMBER;
  v_status_after  VARCHAR2(20);
  v_balance_after NUMBER;
  v_txn_count     NUMBER;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- Test: tc_01_happy_path_with_balance — Successfully close ACTIVE account with positive balance
  BEGIN
    pkg_account_mgmt.close_account(100000, 'Customer request', 2000, v_final_balance);
    SELECT status, balance INTO v_status_after, v_balance_after
    FROM   accounts WHERE account_id = 100000;
    ROLLBACK;
    IF v_status_after = 'CLOSED' AND v_balance_after = 0 AND v_final_balance = 5000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path_with_balance|OK|final_balance:' || v_final_balance);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path_with_balance|FAIL|status:' || v_status_after || ' balance:' || v_balance_after || ' final:' || v_final_balance);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path_with_balance|FAIL|' || SQLERRM);
  END;

  -- Test: tc_02_happy_path_zero_balance — Successfully close ACTIVE account with zero balance (no withdrawal txn)
  BEGIN
    UPDATE accounts SET balance = 0, available_balance = 0 WHERE account_id = 100002;
    pkg_account_mgmt.close_account(100002, 'Customer request', 2000, v_final_balance);
    SELECT status, balance INTO v_status_after, v_balance_after
    FROM   accounts WHERE account_id = 100002;
    ROLLBACK;
    IF v_status_after = 'CLOSED' AND v_balance_after = 0 AND v_final_balance = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_happy_path_zero_balance|OK|final_balance:' || v_final_balance);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_happy_path_zero_balance|FAIL|status:' || v_status_after || ' balance:' || v_balance_after || ' final:' || v_final_balance);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_happy_path_zero_balance|FAIL|' || SQLERRM);
  END;

  -- Test: tc_03_already_closed — Raise -20003 when account is already CLOSED
  BEGIN
    UPDATE accounts SET status = 'CLOSED' WHERE account_id = 100003;
    pkg_account_mgmt.close_account(100003, 'Customer request', 2000, v_final_balance);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_already_closed|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20003 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_already_closed|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_already_closed|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_04_active_holds — Raise -20017 when account has active holds
  BEGIN
    UPDATE accounts SET hold_amount = 500, available_balance = 4500 WHERE account_id = 100000;
    pkg_account_mgmt.close_account(100000, 'Customer request', 2000, v_final_balance);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_active_holds|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20017 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_active_holds|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_active_holds|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_05_active_loans — Raise -20018 when account has active loans
  BEGIN
    INSERT INTO loans (
        loan_number, customer_id, account_id, branch_id, loan_type,
        principal_amount, outstanding_balance, interest_rate,
        term_months, monthly_payment, status
    ) VALUES (
        'LN-CLOSE-TEST', 1000, 100000, 10, 'PERSONAL',
        10000, 8000, 5.5, 36, 300, 'ACTIVE'
    );
    pkg_account_mgmt.close_account(100000, 'Customer request', 2000, v_final_balance);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_active_loans|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20018 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_active_loans|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_active_loans|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_06_withdrawal_txn_created — Withdrawal transaction inserted when balance > 0
  BEGIN
    pkg_account_mgmt.close_account(100001, 'Customer request', 2001, v_final_balance); -- balance 15,000
    SELECT COUNT(*) INTO v_txn_count
    FROM   transactions
    WHERE  account_id       = 100001
    AND    transaction_type = 'WITHDRAWAL'
    AND    amount           = 15000
    AND    balance_after    = 0
    AND    status           = 'COMPLETED';
    ROLLBACK;
    IF v_txn_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_withdrawal_txn_created|OK|txn_count:' || v_txn_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_withdrawal_txn_created|FAIL|expected:1 got:' || v_txn_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_withdrawal_txn_created|FAIL|' || SQLERRM);
  END;

  -- Test: tc_07_no_txn_on_zero_balance — No withdrawal transaction inserted when balance = 0
  BEGIN
    UPDATE accounts SET balance = 0, available_balance = 0 WHERE account_id = 100004;
    pkg_account_mgmt.close_account(100004, 'Customer request', 2002, v_final_balance);
    SELECT COUNT(*) INTO v_txn_count
    FROM   transactions WHERE account_id = 100004;
    ROLLBACK;
    IF v_txn_count = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_no_txn_on_zero_balance|OK|txn_count:' || v_txn_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_no_txn_on_zero_balance|FAIL|expected:0 got:' || v_txn_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_no_txn_on_zero_balance|FAIL|' || SQLERRM);
  END;

  -- Test: tc_08_final_balance_returned — p_final_balance equals pre-close balance
  BEGIN
    pkg_account_mgmt.close_account(100003, 'Customer request', 2001, v_final_balance); -- balance 50,000
    ROLLBACK;
    IF v_final_balance = 50000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_final_balance_returned|OK|final_balance:' || v_final_balance);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_final_balance_returned|FAIL|expected:50000 got:' || v_final_balance);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_final_balance_returned|FAIL|' || SQLERRM);
  END;

  -- Test: tc_09_balance_zeroed — balance and available_balance set to 0 after closure
  BEGIN
    pkg_account_mgmt.close_account(100005, 'Customer request', 2000, v_final_balance); -- balance 125,000
    SELECT balance INTO v_balance_after FROM accounts WHERE account_id = 100005;
    ROLLBACK;
    IF v_balance_after = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_balance_zeroed|OK|balance:' || v_balance_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_balance_zeroed|FAIL|expected:0 got:' || v_balance_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_balance_zeroed|FAIL|' || SQLERRM);
  END;

  -- Test: tc_10_closed_date_set — closed_date is set to SYSDATE after closure
  DECLARE
    v_closed_date DATE;
  BEGIN
    pkg_account_mgmt.close_account(100006, 'Customer request', 2003, v_final_balance);
    SELECT closed_date INTO v_closed_date FROM accounts WHERE account_id = 100006;
    ROLLBACK;
    IF TRUNC(v_closed_date) = TRUNC(SYSDATE) THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_closed_date_set|OK|closed_date:' || v_closed_date);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_closed_date_set|FAIL|expected:' || TRUNC(SYSDATE) || ' got:' || v_closed_date);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_closed_date_set|FAIL|' || SQLERRM);
  END;

  -- Test: tc_11_nonexistent_account — NO_DATA_FOUND for account_id that does not exist
  BEGIN
    pkg_account_mgmt.close_account(999999, 'Customer request', 2000, v_final_balance);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_nonexistent_account|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = 100 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_nonexistent_account|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_nonexistent_account|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_12_null_account_id — NO_DATA_FOUND for NULL account_id
  BEGIN
    pkg_account_mgmt.close_account(NULL, 'Customer request', 2000, v_final_balance);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_null_account_id|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = 100 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_null_account_id|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_null_account_id|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_13_paid_off_loan_no_block — PAID_OFF loan does not block account closure
  BEGIN
    INSERT INTO loans (
        loan_number, customer_id, account_id, branch_id, loan_type,
        principal_amount, outstanding_balance, interest_rate,
        term_months, monthly_payment, status
    ) VALUES (
        'LN-PAIDOFF-TEST', 1001, 100002, 10, 'PERSONAL',
        5000, 0, 5.5, 24, 220, 'PAID_OFF'
    );
    UPDATE accounts SET balance = 0, available_balance = 0 WHERE account_id = 100002;
    pkg_account_mgmt.close_account(100002, 'Customer request', 2001, v_final_balance);
    SELECT status INTO v_status_after FROM accounts WHERE account_id = 100002;
    ROLLBACK;
    IF v_status_after = 'CLOSED' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_paid_off_loan_no_block|OK|status:' || v_status_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_paid_off_loan_no_block|FAIL|expected:CLOSED got:' || v_status_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_paid_off_loan_no_block|FAIL|' || SQLERRM);
  END;

END;
/