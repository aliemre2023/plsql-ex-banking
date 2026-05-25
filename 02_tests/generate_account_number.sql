DECLARE
  v_result  VARCHAR2(20);
  v_exists  NUMBER;

  PROCEDURE assert_format(p_test VARCHAR2, p_result VARCHAR2, p_expected_prefix VARCHAR2) IS
  BEGIN
    IF p_result IS NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|' || p_test || '|FAIL|returned NULL');
    ELSIF p_result LIKE p_expected_prefix || '-________' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|' || p_test || '|OK|returned:' || p_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|' || p_test || '|FAIL|unexpected_format:' || p_result);
    END IF;
  END;

BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- Test: tc_01_checking_prefix — CHECKING type returns CHK- prefix
  BEGIN
    v_result := pkg_account_mgmt.generate_account_number('HQ001', 'CHECKING');
    assert_format('tc_01_checking_prefix', v_result, 'CHK');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_checking_prefix|FAIL|' || SQLERRM);
  END;

  -- Test: tc_02_savings_prefix — SAVINGS type returns SAV- prefix
  BEGIN
    v_result := pkg_account_mgmt.generate_account_number('HQ001', 'SAVINGS');
    assert_format('tc_02_savings_prefix', v_result, 'SAV');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_savings_prefix|FAIL|' || SQLERRM);
  END;

  -- Test: tc_03_money_mkt_prefix — MONEY_MKT type returns MMK- prefix
  BEGIN
    v_result := pkg_account_mgmt.generate_account_number('BR002', 'MONEY_MKT');
    assert_format('tc_03_money_mkt_prefix', v_result, 'MMK');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_money_mkt_prefix|FAIL|' || SQLERRM);
  END;

  -- Test: tc_04_cd_prefix — CD type returns CD_- prefix
  BEGIN
    v_result := pkg_account_mgmt.generate_account_number('BR002', 'CD');
    assert_format('tc_04_cd_prefix', v_result, 'CD_');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_cd_prefix|FAIL|' || SQLERRM);
  END;

  -- Test: tc_05_business_prefix — BUSINESS type returns BUS- prefix
  BEGIN
    v_result := pkg_account_mgmt.generate_account_number('BR003', 'BUSINESS');
    assert_format('tc_05_business_prefix', v_result, 'BUS');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_business_prefix|FAIL|' || SQLERRM);
  END;

  -- Test: tc_06_premium_prefix — PREMIUM type returns PRE- prefix
  BEGIN
    v_result := pkg_account_mgmt.generate_account_number('BR003', 'PREMIUM');
    assert_format('tc_06_premium_prefix', v_result, 'PRE');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_premium_prefix|FAIL|' || SQLERRM);
  END;

  -- Test: tc_07_unknown_type_prefix — Unknown type falls back to ACC- prefix
  BEGIN
    v_result := pkg_account_mgmt.generate_account_number('HQ001', 'UNKNOWN');
    assert_format('tc_07_unknown_type_prefix', v_result, 'ACC');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_unknown_type_prefix|FAIL|' || SQLERRM);
  END;

  -- Test: tc_08_null_type_prefix — NULL type falls back to ACC- prefix
  BEGIN
    v_result := pkg_account_mgmt.generate_account_number('HQ001', NULL);
    assert_format('tc_08_null_type_prefix', v_result, 'ACC');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_null_type_prefix|FAIL|' || SQLERRM);
  END;

  -- Test: tc_09_unique_per_call — Two consecutive calls return different account numbers
  DECLARE
    v_first  VARCHAR2(20);
    v_second VARCHAR2(20);
  BEGIN
    v_first  := pkg_account_mgmt.generate_account_number('HQ001', 'CHECKING');
    v_second := pkg_account_mgmt.generate_account_number('HQ001', 'CHECKING');
    IF v_first <> v_second THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_unique_per_call|OK|first:' || v_first || ' second:' || v_second);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_unique_per_call|FAIL|duplicate:' || v_first);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_unique_per_call|FAIL|' || SQLERRM);
  END;

  -- Test: tc_10_not_in_accounts — Generated number does not already exist in accounts table
  BEGIN
    v_result := pkg_account_mgmt.generate_account_number('HQ001', 'SAVINGS');
    SELECT COUNT(*) INTO v_exists FROM accounts WHERE account_number = v_result;
    IF v_exists = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_not_in_accounts|OK|no_collision:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_not_in_accounts|FAIL|collision_found:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_not_in_accounts|FAIL|' || SQLERRM);
  END;

  -- Test: tc_11_length_constraint — Returned account number length does not exceed 20 chars
  BEGIN
    v_result := pkg_account_mgmt.generate_account_number('BR003', 'PREMIUM');
    IF LENGTH(v_result) <= 20 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_length_constraint|OK|length:' || LENGTH(v_result) || ' value:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_length_constraint|FAIL|length_exceeded:' || LENGTH(v_result));
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_length_constraint|FAIL|' || SQLERRM);
  END;

  -- Test: tc_12_different_branch_same_type — Different branch codes produce same-prefixed unique numbers
  DECLARE
    v_hq  VARCHAR2(20);
    v_br  VARCHAR2(20);
  BEGIN
    v_hq := pkg_account_mgmt.generate_account_number('HQ001', 'CHECKING');
    v_br := pkg_account_mgmt.generate_account_number('BR002', 'CHECKING');
    IF v_hq LIKE 'CHK-%' AND v_br LIKE 'CHK-%' AND v_hq <> v_br THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_different_branch_same_type|OK|hq:' || v_hq || ' br:' || v_br);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_different_branch_same_type|FAIL|hq:' || v_hq || ' br:' || v_br);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_different_branch_same_type|FAIL|' || SQLERRM);
  END;

END;
/