DECLARE
  v_result NUMBER;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- Test: tc_01_happy_path_checking — Return correct available_balance for a checking account
  BEGIN
    v_result := pkg_account_mgmt.get_available_balance(100000);
    IF v_result = 5000.00 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path_checking|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path_checking|FAIL|expected:5000.00 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path_checking|FAIL|' || SQLERRM);
  END;

  -- Test: tc_02_happy_path_savings — Return correct available_balance for a savings account
  BEGIN
    v_result := pkg_account_mgmt.get_available_balance(100001);
    IF v_result = 15000.00 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_happy_path_savings|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_happy_path_savings|FAIL|expected:15000.00 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_happy_path_savings|FAIL|' || SQLERRM);
  END;

  -- Test: tc_03_happy_path_premium — Return correct available_balance for a premium account
  BEGIN
    v_result := pkg_account_mgmt.get_available_balance(100005);
    IF v_result = 125000.00 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_happy_path_premium|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_happy_path_premium|FAIL|expected:125000.00 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_happy_path_premium|FAIL|' || SQLERRM);
  END;

  -- Test: tc_04_available_equals_balance — available_balance matches balance for accounts with no holds
  DECLARE
    v_available NUMBER;
    v_balance   NUMBER;
  BEGIN
    v_available := pkg_account_mgmt.get_available_balance(100002);
    SELECT balance INTO v_balance FROM accounts WHERE account_id = 100002;
    IF v_available = v_balance THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_available_equals_balance|OK|available:' || v_available || ' balance:' || v_balance);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_available_equals_balance|FAIL|available:' || v_available || ' balance:' || v_balance);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_available_equals_balance|FAIL|' || SQLERRM);
  END;

  -- Test: tc_05_happy_path_money_mkt — Return correct available_balance for a money market account
  BEGIN
    v_result := pkg_account_mgmt.get_available_balance(100006);
    IF v_result = 75000.00 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_happy_path_money_mkt|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_happy_path_money_mkt|FAIL|expected:75000.00 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_happy_path_money_mkt|FAIL|' || SQLERRM);
  END;

  -- Test: tc_06_account_not_found — Raise -20099 for a non-existent account_id
  BEGIN
    v_result := pkg_account_mgmt.get_available_balance(999999);
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_account_not_found|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -20099 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_account_not_found|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_account_not_found|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_07_null_account_id — Raise -20099 when account_id is NULL (no row matches)
  BEGIN
    v_result := pkg_account_mgmt.get_available_balance(NULL);
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_null_account_id|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -20099 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_null_account_id|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_null_account_id|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_08_same_customer_two_accounts — Both accounts of same customer return distinct available balances
  DECLARE
    v_bal_a NUMBER;
    v_bal_b NUMBER;
  BEGIN
    v_bal_a := pkg_account_mgmt.get_available_balance(100005); -- Eve PREMIUM   125,000
    v_bal_b := pkg_account_mgmt.get_available_balance(100006); -- Eve MONEY_MKT  75,000
    IF v_bal_a = 125000.00 AND v_bal_b = 75000.00 AND v_bal_a != v_bal_b THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_same_customer_two_accounts|OK|premium:' || v_bal_a || ' money_mkt:' || v_bal_b);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_same_customer_two_accounts|FAIL|premium:' || v_bal_a || ' money_mkt:' || v_bal_b);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_same_customer_two_accounts|FAIL|' || SQLERRM);
  END;

END;
/