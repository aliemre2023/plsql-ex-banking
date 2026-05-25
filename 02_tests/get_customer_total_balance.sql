DECLARE
  v_result NUMBER;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- Test: tc_01_single_account_customer — Return correct total for customer with one account (Bob)
  BEGIN
    v_result := pkg_account_mgmt.get_customer_total_balance(1001);
    IF v_result = 2500.00 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_single_account_customer|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_single_account_customer|FAIL|expected:2500.00 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_single_account_customer|FAIL|' || SQLERRM);
  END;

  -- Test: tc_02_two_accounts_customer — Return correct sum for customer with two accounts (Alice)
  BEGIN
    v_result := pkg_account_mgmt.get_customer_total_balance(1000);
    IF v_result = 20000.00 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_two_accounts_customer|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_two_accounts_customer|FAIL|expected:20000.00 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_two_accounts_customer|FAIL|' || SQLERRM);
  END;

  -- Test: tc_03_high_value_customer — Return correct sum for VIP customer with two accounts (Eve)
  BEGIN
    v_result := pkg_account_mgmt.get_customer_total_balance(1004);
    IF v_result = 200000.00 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_high_value_customer|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_high_value_customer|FAIL|expected:200000.00 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_high_value_customer|FAIL|' || SQLERRM);
  END;

  -- Test: tc_04_nonexistent_customer — Return 0 for a customer_id that does not exist (NVL kicks in)
  BEGIN
    v_result := pkg_account_mgmt.get_customer_total_balance(999999);
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_nonexistent_customer|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_nonexistent_customer|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_nonexistent_customer|FAIL|' || SQLERRM);
  END;

  -- Test: tc_05_null_customer_id — Return 0 for NULL customer_id (NVL kicks in)
  BEGIN
    v_result := pkg_account_mgmt.get_customer_total_balance(NULL);
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_null_customer_id|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_null_customer_id|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_null_customer_id|FAIL|' || SQLERRM);
  END;

  -- Test: tc_06_excludes_inactive_accounts — Only ACTIVE accounts are summed (INACTIVE excluded)
  DECLARE
    v_before NUMBER;
    v_after  NUMBER;
  BEGIN
    v_before := pkg_account_mgmt.get_customer_total_balance(1000); -- Alice: 20,000
    UPDATE accounts SET status = 'INACTIVE' WHERE account_id = 100001; -- Alice SAVINGS 15,000
    v_after := pkg_account_mgmt.get_customer_total_balance(1000);
    ROLLBACK;
    IF v_before = 20000.00 AND v_after = 5000.00 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_excludes_inactive_accounts|OK|before:' || v_before || ' after:' || v_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_excludes_inactive_accounts|FAIL|before:' || v_before || ' after:' || v_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_excludes_inactive_accounts|FAIL|' || SQLERRM);
  END;

  -- Test: tc_07_excludes_closed_accounts — CLOSED accounts are not included in total
  DECLARE
    v_before NUMBER;
    v_after  NUMBER;
  BEGIN
    v_before := pkg_account_mgmt.get_customer_total_balance(1004); -- Eve: 200,000
    UPDATE accounts SET status = 'CLOSED' WHERE account_id = 100006; -- Eve MONEY_MKT 75,000
    v_after := pkg_account_mgmt.get_customer_total_balance(1004);
    ROLLBACK;
    IF v_before = 200000.00 AND v_after = 125000.00 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_excludes_closed_accounts|OK|before:' || v_before || ' after:' || v_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_excludes_closed_accounts|FAIL|before:' || v_before || ' after:' || v_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_excludes_closed_accounts|FAIL|' || SQLERRM);
  END;

  -- Test: tc_08_all_accounts_inactive — Return 0 when all customer accounts are inactive
  DECLARE
    v_result NUMBER;
  BEGIN
    UPDATE accounts SET status = 'INACTIVE' WHERE customer_id = 1001; -- Bob: 1 account
    v_result := pkg_account_mgmt.get_customer_total_balance(1001);
    ROLLBACK;
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_all_accounts_inactive|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_all_accounts_inactive|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_all_accounts_inactive|FAIL|' || SQLERRM);
  END;

END;
/