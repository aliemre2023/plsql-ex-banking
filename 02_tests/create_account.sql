DECLARE
  v_account_id     NUMBER;
  v_account_number VARCHAR2(20);
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- Test: tc_01_happy_path_no_deposit — Successfully create CHECKING account with 0 deposit (min_balance=0)
  BEGIN
    pkg_account_mgmt.create_account(1001, 10, 'CHECKING', 0, 'USD', v_account_id, v_account_number);
    IF v_account_id IS NOT NULL AND v_account_number LIKE 'CHK-%' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path_no_deposit|OK|account_id:' || v_account_id || ' number:' || v_account_number);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path_no_deposit|FAIL|account_id:' || v_account_id || ' number:' || v_account_number);
    END IF;
    ROLLBACK;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path_no_deposit|FAIL|' || SQLERRM);
  END;

  -- Test: tc_02_happy_path_with_deposit — Successfully create SAVINGS account with deposit above minimum (min=500)
  BEGIN
    pkg_account_mgmt.create_account(1000, 10, 'SAVINGS', 1000, 'USD', v_account_id, v_account_number);
    IF v_account_id IS NOT NULL AND v_account_number LIKE 'SAV-%' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_happy_path_with_deposit|OK|account_id:' || v_account_id || ' number:' || v_account_number);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_happy_path_with_deposit|FAIL|account_id:' || v_account_id || ' number:' || v_account_number);
    END IF;
    ROLLBACK;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_happy_path_with_deposit|FAIL|' || SQLERRM);
  END;

  -- Test: tc_03_exact_min_deposit — Successfully create SAVINGS account with deposit exactly at minimum (min=500)
  BEGIN
    pkg_account_mgmt.create_account(1002, 11, 'SAVINGS', 500, 'USD', v_account_id, v_account_number);
    IF v_account_id IS NOT NULL AND v_account_number LIKE 'SAV-%' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_exact_min_deposit|OK|account_id:' || v_account_id || ' number:' || v_account_number);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_exact_min_deposit|FAIL|account_id:' || v_account_id || ' number:' || v_account_number);
    END IF;
    ROLLBACK;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_exact_min_deposit|FAIL|' || SQLERRM);
  END;

  -- Test: tc_04_deposit_below_minimum — Raise -20012 when initial deposit < min_balance (SAVINGS min=500)
  BEGIN
    pkg_account_mgmt.create_account(1000, 10, 'SAVINGS', 499, 'USD', v_account_id, v_account_number);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_deposit_below_minimum|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20012 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_deposit_below_minimum|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_deposit_below_minimum|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_05_deposit_below_minimum_premium — Raise -20012 when deposit < min_balance (PREMIUM min=25000)
  BEGIN
    pkg_account_mgmt.create_account(1004, 10, 'PREMIUM', 24999, 'USD', v_account_id, v_account_number);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_deposit_below_minimum_premium|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20012 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_deposit_below_minimum_premium|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_deposit_below_minimum_premium|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_06_invalid_account_type — Raise -20011 for unknown account type
  BEGIN
    pkg_account_mgmt.create_account(1000, 10, 'INVALID_TYPE', 0, 'USD', v_account_id, v_account_number);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_invalid_account_type|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20011 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_invalid_account_type|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_invalid_account_type|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_07_nonexistent_customer — Raise -20013 when customer_id does not exist
  BEGIN
    pkg_account_mgmt.create_account(999999, 10, 'CHECKING', 0, 'USD', v_account_id, v_account_number);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_nonexistent_customer|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20013 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_nonexistent_customer|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_nonexistent_customer|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_08_inactive_customer — Raise -20013 when customer is_active = 'N'
  BEGIN
    UPDATE customers SET is_active = 'N' WHERE customer_id = 1003;
    pkg_account_mgmt.create_account(1003, 10, 'CHECKING', 0, 'USD', v_account_id, v_account_number);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_inactive_customer|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20013 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_inactive_customer|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_inactive_customer|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_09_kyc_not_verified — Raise -20010 when customer KYC status is not VERIFIED
  BEGIN
    UPDATE customers SET kyc_status = 'PENDING' WHERE customer_id = 1003;
    pkg_account_mgmt.create_account(1003, 10, 'CHECKING', 0, 'USD', v_account_id, v_account_number);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_kyc_not_verified|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20010 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_kyc_not_verified|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_kyc_not_verified|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_10_nonexistent_branch — Raise -20013 when branch_id does not exist
  BEGIN
    pkg_account_mgmt.create_account(1000, 999999, 'CHECKING', 0, 'USD', v_account_id, v_account_number);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_nonexistent_branch|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20013 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_nonexistent_branch|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_nonexistent_branch|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_11_inactive_branch — Raise -20013 when branch is_active = 'N'
  BEGIN
    UPDATE branches SET is_active = 'N' WHERE branch_id = 12;
    pkg_account_mgmt.create_account(1000, 12, 'CHECKING', 0, 'USD', v_account_id, v_account_number);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_inactive_branch|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20013 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_inactive_branch|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_inactive_branch|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_12_transaction_created_with_deposit — Verify transaction record inserted when deposit > 0
  DECLARE
    v_txn_count NUMBER;
  BEGIN
    pkg_account_mgmt.create_account(1001, 10, 'CHECKING', 500, 'USD', v_account_id, v_account_number);
    SELECT COUNT(*) INTO v_txn_count
    FROM   transactions
    WHERE  account_id        = v_account_id
    AND    transaction_type  = 'DEPOSIT'
    AND    amount            = 500;
    ROLLBACK;
    IF v_txn_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_transaction_created_with_deposit|OK|txn_count:' || v_txn_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_transaction_created_with_deposit|FAIL|expected:1 got:' || v_txn_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_transaction_created_with_deposit|FAIL|' || SQLERRM);
  END;

  -- Test: tc_13_no_transaction_without_deposit — Verify no transaction record inserted when deposit = 0
  DECLARE
    v_txn_count NUMBER;
  BEGIN
    pkg_account_mgmt.create_account(1001, 10, 'CHECKING', 0, 'USD', v_account_id, v_account_number);
    SELECT COUNT(*) INTO v_txn_count
    FROM   transactions
    WHERE  account_id = v_account_id;
    ROLLBACK;
    IF v_txn_count = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_no_transaction_without_deposit|OK|txn_count:' || v_txn_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_no_transaction_without_deposit|FAIL|expected:0 got:' || v_txn_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_no_transaction_without_deposit|FAIL|' || SQLERRM);
  END;

  -- Test: tc_14_account_active_on_creation — Created account has status ACTIVE
  DECLARE
    v_status VARCHAR2(20);
  BEGIN
    pkg_account_mgmt.create_account(1002, 11, 'CHECKING', 0, 'USD', v_account_id, v_account_number);
    SELECT status INTO v_status FROM accounts WHERE account_id = v_account_id;
    ROLLBACK;
    IF v_status = 'ACTIVE' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_14_account_active_on_creation|OK|status:' || v_status);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_14_account_active_on_creation|FAIL|expected:ACTIVE got:' || v_status);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_14_account_active_on_creation|FAIL|' || SQLERRM);
  END;

  -- Test: tc_15_balance_equals_deposit — Created account balance matches initial deposit
  DECLARE
    v_balance NUMBER;
  BEGIN
    pkg_account_mgmt.create_account(1003, 10, 'CHECKING', 750, 'USD', v_account_id, v_account_number);
    SELECT balance INTO v_balance FROM accounts WHERE account_id = v_account_id;
    ROLLBACK;
    IF v_balance = 750 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_15_balance_equals_deposit|OK|balance:' || v_balance);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_15_balance_equals_deposit|FAIL|expected:750 got:' || v_balance);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_15_balance_equals_deposit|FAIL|' || SQLERRM);
  END;

END;
/