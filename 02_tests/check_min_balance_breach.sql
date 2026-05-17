DECLARE
  v_result BOOLEAN;

  PROCEDURE print_bool_result(p_test VARCHAR2, p_result BOOLEAN, p_expected BOOLEAN) IS
  BEGIN
    IF p_result = p_expected THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|' || p_test || '|OK|returned:' ||
        CASE p_result WHEN TRUE THEN 'TRUE' ELSE 'FALSE' END);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|' || p_test || '|FAIL|expected:' ||
        CASE p_expected WHEN TRUE THEN 'TRUE' ELSE 'FALSE' END ||
        ' got:' ||
        CASE p_result WHEN TRUE THEN 'TRUE' ELSE 'FALSE' END);
    END IF;
  END;

BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- Test: tc_01_no_breach_checking — CHECKING min=0, balance=5000, debit=4999 → no breach (5000-4999=1 >= 0)
  BEGIN
    v_result := pkg_account_mgmt.check_min_balance_breach(100000, 4999);
    print_bool_result('tc_01_no_breach_checking', v_result, FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_no_breach_checking|FAIL|' || SQLERRM);
  END;

  -- Test: tc_02_exact_min_checking — CHECKING min=0, balance=5000, debit=5000 → no breach (5000-5000=0 >= 0)
  BEGIN
    v_result := pkg_account_mgmt.check_min_balance_breach(100000, 5000);
    print_bool_result('tc_02_exact_min_checking', v_result, FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_exact_min_checking|FAIL|' || SQLERRM);
  END;

  -- Test: tc_03_breach_checking — CHECKING min=0, balance=5000, debit=5001 → breach (5000-5001=-1 < 0)
  BEGIN
    v_result := pkg_account_mgmt.check_min_balance_breach(100000, 5001);
    print_bool_result('tc_03_breach_checking', v_result, TRUE);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_breach_checking|FAIL|' || SQLERRM);
  END;

  -- Test: tc_04_no_breach_savings — SAVINGS min=500, balance=15000, debit=14499 → no breach (15000-14499=501 >= 500)
  BEGIN
    v_result := pkg_account_mgmt.check_min_balance_breach(100001, 14499);
    print_bool_result('tc_04_no_breach_savings', v_result, FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_no_breach_savings|FAIL|' || SQLERRM);
  END;

  -- Test: tc_05_exact_min_savings — SAVINGS min=500, balance=15000, debit=14500 → no breach (15000-14500=500 >= 500)
  BEGIN
    v_result := pkg_account_mgmt.check_min_balance_breach(100001, 14500);
    print_bool_result('tc_05_exact_min_savings', v_result, FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_exact_min_savings|FAIL|' || SQLERRM);
  END;

  -- Test: tc_06_breach_savings — SAVINGS min=500, balance=15000, debit=14501 → breach (15000-14501=499 < 500)
  BEGIN
    v_result := pkg_account_mgmt.check_min_balance_breach(100001, 14501);
    print_bool_result('tc_06_breach_savings', v_result, TRUE);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_breach_savings|FAIL|' || SQLERRM);
  END;

  -- Test: tc_07_no_breach_premium — PREMIUM min=25000, balance=125000, debit=99999 → no breach (125000-99999=25001 >= 25000)
  BEGIN
    v_result := pkg_account_mgmt.check_min_balance_breach(100005, 99999);
    print_bool_result('tc_07_no_breach_premium', v_result, FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_no_breach_premium|FAIL|' || SQLERRM);
  END;

  -- Test: tc_08_breach_premium — PREMIUM min=25000, balance=125000, debit=100001 → breach (125000-100001=24999 < 25000)
  BEGIN
    v_result := pkg_account_mgmt.check_min_balance_breach(100005, 100001);
    print_bool_result('tc_08_breach_premium', v_result, TRUE);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_breach_premium|FAIL|' || SQLERRM);
  END;

  -- Test: tc_09_breach_money_mkt — MONEY_MKT min=10000, balance=75000, debit=65001 → breach (75000-65001=9999 < 10000)
  BEGIN
    v_result := pkg_account_mgmt.check_min_balance_breach(100006, 65001);
    print_bool_result('tc_09_breach_money_mkt', v_result, TRUE);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_breach_money_mkt|FAIL|' || SQLERRM);
  END;

  -- Test: tc_10_zero_debit — Debit amount 0 never causes breach
  BEGIN
    v_result := pkg_account_mgmt.check_min_balance_breach(100001, 0);
    print_bool_result('tc_10_zero_debit', v_result, FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_zero_debit|FAIL|' || SQLERRM);
  END;

  -- Test: tc_11_nonexistent_account — Return TRUE for non-existent account (NO_DATA_FOUND handler)
  BEGIN
    v_result := pkg_account_mgmt.check_min_balance_breach(999999, 100);
    print_bool_result('tc_11_nonexistent_account', v_result, TRUE);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_nonexistent_account|FAIL|' || SQLERRM);
  END;

  -- Test: tc_12_null_account_id — Return TRUE for NULL account_id (NO_DATA_FOUND handler)
  BEGIN
    v_result := pkg_account_mgmt.check_min_balance_breach(NULL, 100);
    print_bool_result('tc_12_null_account_id', v_result, TRUE);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_null_account_id|FAIL|' || SQLERRM);
  END;

  -- Test: tc_13_null_debit_amount — NULL debit causes (balance - NULL) = NULL < min → NULL comparison returns TRUE
  BEGIN
    v_result := pkg_account_mgmt.check_min_balance_breach(100000, NULL);
    print_bool_result('tc_13_null_debit_amount', v_result, TRUE);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_null_debit_amount|FAIL|' || SQLERRM);
  END;

END;
/