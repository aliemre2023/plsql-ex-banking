DECLARE
  v_result NUMBER;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- Test: tc_01_checking_zero_min — Return 0 for CHECKING (no minimum balance)
  BEGIN
    v_result := pkg_account_mgmt.get_min_balance('CHECKING');
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_checking_zero_min|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_checking_zero_min|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_checking_zero_min|FAIL|' || SQLERRM);
  END;

  -- Test: tc_02_savings_min — Return 500 for SAVINGS
  BEGIN
    v_result := pkg_account_mgmt.get_min_balance('SAVINGS');
    IF v_result = 500 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_savings_min|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_savings_min|FAIL|expected:500 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_savings_min|FAIL|' || SQLERRM);
  END;

  -- Test: tc_03_money_mkt_min — Return 10000 for MONEY_MKT
  BEGIN
    v_result := pkg_account_mgmt.get_min_balance('MONEY_MKT');
    IF v_result = 10000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_money_mkt_min|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_money_mkt_min|FAIL|expected:10000 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_money_mkt_min|FAIL|' || SQLERRM);
  END;

  -- Test: tc_04_cd_min — Return 1000 for CD
  BEGIN
    v_result := pkg_account_mgmt.get_min_balance('CD');
    IF v_result = 1000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_cd_min|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_cd_min|FAIL|expected:1000 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_cd_min|FAIL|' || SQLERRM);
  END;

  -- Test: tc_05_business_min — Return 2500 for BUSINESS
  BEGIN
    v_result := pkg_account_mgmt.get_min_balance('BUSINESS');
    IF v_result = 2500 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_business_min|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_business_min|FAIL|expected:2500 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_business_min|FAIL|' || SQLERRM);
  END;

  -- Test: tc_06_premium_min — Return 25000 for PREMIUM
  BEGIN
    v_result := pkg_account_mgmt.get_min_balance('PREMIUM');
    IF v_result = 25000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_premium_min|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_premium_min|FAIL|expected:25000 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_premium_min|FAIL|' || SQLERRM);
  END;

  -- Test: tc_07_nonexistent_type — Return 0 for unknown type (NO_DATA_FOUND handler)
  BEGIN
    v_result := pkg_account_mgmt.get_min_balance('UNKNOWN');
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_nonexistent_type|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_nonexistent_type|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_nonexistent_type|FAIL|' || SQLERRM);
  END;

  -- Test: tc_08_null_type — Return 0 for NULL input (NO_DATA_FOUND handler)
  BEGIN
    v_result := pkg_account_mgmt.get_min_balance(NULL);
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_null_type|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_null_type|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_null_type|FAIL|' || SQLERRM);
  END;

  -- Test: tc_09_lowercase_type — Return 0 for lowercase input (case-sensitive match fails)
  BEGIN
    v_result := pkg_account_mgmt.get_min_balance('checking');
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_lowercase_type|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_lowercase_type|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_lowercase_type|FAIL|' || SQLERRM);
  END;

END;
/