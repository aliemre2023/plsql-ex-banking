DECLARE
  v_result BOOLEAN;

  PROCEDURE print_bool_result(p_test VARCHAR2, p_result BOOLEAN, p_expected BOOLEAN) IS
  BEGIN
    IF p_result IS NULL AND p_expected IS NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|' || p_test || '|OK|returned:NULL');
    ELSIF p_result = p_expected THEN
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

  -- Test: tc_01_active_checking — Return TRUE for an active checking account
  BEGIN
    v_result := pkg_account_mgmt.is_account_active(100000); -- ACC-100001, Alice, CHECKING, ACTIVE
    print_bool_result('tc_01_active_checking', v_result, TRUE);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_active_checking|FAIL|' || SQLERRM);
  END;

  -- Test: tc_02_active_savings — Return TRUE for an active savings account
  BEGIN
    v_result := pkg_account_mgmt.is_account_active(100001); -- ACC-100002, Alice, SAVINGS, ACTIVE
    print_bool_result('tc_02_active_savings', v_result, TRUE);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_active_savings|FAIL|' || SQLERRM);
  END;

  -- Test: tc_03_active_premium — Return TRUE for an active premium account
  BEGIN
    v_result := pkg_account_mgmt.is_account_active(100005); -- ACC-100006, Eve, PREMIUM, ACTIVE
    print_bool_result('tc_03_active_premium', v_result, TRUE);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_active_premium|FAIL|' || SQLERRM);
  END;

  -- Test: tc_04_inactive_account — Return FALSE for an INACTIVE account
  BEGIN
    UPDATE accounts SET status = 'INACTIVE' WHERE account_id = 100003;
    v_result := pkg_account_mgmt.is_account_active(100003); -- ACC-100004, Carol, SAVINGS
    ROLLBACK;
    print_bool_result('tc_04_inactive_account', v_result, FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_inactive_account|FAIL|' || SQLERRM);
  END;

  -- Test: tc_05_frozen_account — Return FALSE for a FROZEN account
  BEGIN
    UPDATE accounts SET status = 'FROZEN' WHERE account_id = 100003;
    v_result := pkg_account_mgmt.is_account_active(100003); -- ACC-100004, Carol, SAVINGS
    ROLLBACK;
    print_bool_result('tc_05_frozen_account', v_result, FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_frozen_account|FAIL|' || SQLERRM);
  END;

  -- Test: tc_06_closed_account — Return FALSE for a CLOSED account
  BEGIN
    UPDATE accounts SET status = 'CLOSED' WHERE account_id = 100003;
    v_result := pkg_account_mgmt.is_account_active(100003);
    ROLLBACK;
    print_bool_result('tc_06_closed_account', v_result, FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_closed_account|FAIL|' || SQLERRM);
  END;

  -- Test: tc_07_dormant_account — Return FALSE for a DORMANT account
  BEGIN
    UPDATE accounts SET status = 'DORMANT' WHERE account_id = 100003;
    v_result := pkg_account_mgmt.is_account_active(100003);
    ROLLBACK;
    print_bool_result('tc_07_dormant_account', v_result, FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_dormant_account|FAIL|' || SQLERRM);
  END;

  -- Test: tc_08_nonexistent_account — Return FALSE (NO_DATA_FOUND) for non-existent account_id
  BEGIN
    v_result := pkg_account_mgmt.is_account_active(999999);
    print_bool_result('tc_08_nonexistent_account', v_result, FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_nonexistent_account|FAIL|' || SQLERRM);
  END;

  -- Test: tc_09_null_account_id — Return FALSE (NO_DATA_FOUND) when account_id is NULL
  BEGIN
    v_result := pkg_account_mgmt.is_account_active(NULL);
    print_bool_result('tc_09_null_account_id', v_result, FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_null_account_id|FAIL|' || SQLERRM);
  END;

  -- Test: tc_10_active_money_mkt — Return TRUE for an active money market account
  BEGIN
    v_result := pkg_account_mgmt.is_account_active(100006); -- ACC-100007, Eve, MONEY_MKT, ACTIVE
    print_bool_result('tc_10_active_money_mkt', v_result, TRUE);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_active_money_mkt|FAIL|' || SQLERRM);
  END;

END;
/