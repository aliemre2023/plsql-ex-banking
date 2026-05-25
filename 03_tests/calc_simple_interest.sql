DECLARE
  v_result NUMBER;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: Standart hesaplama (1000 * 5% * 365/365 = 50.00)
  BEGIN
    v_result := pkg_transactions.calc_simple_interest(1000, 5, 365);
    IF v_result = 50.00 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_annual_full_year|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_annual_full_year|FAIL|expected:50.00 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_annual_full_year|FAIL|' || SQLERRM);
  END;

  -- tc_02: 30 günlük faiz (1000 * 5% * 30/365 = 4.11)
  BEGIN
    v_result := pkg_transactions.calc_simple_interest(1000, 5, 30);
    IF v_result = 4.11 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_30_days|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_30_days|FAIL|expected:4.11 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_30_days|FAIL|' || SQLERRM);
  END;

  -- tc_03: 1 günlük faiz (10000 * 2.5% * 1/365 = 0.68)
  BEGIN
    v_result := pkg_transactions.calc_simple_interest(10000, 2.5, 1);
    IF v_result = 0.68 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_one_day|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_one_day|FAIL|expected:0.68 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_one_day|FAIL|' || SQLERRM);
  END;

  -- tc_04: Yüksek bakiye (100000 * 3.5% * 365/365 = 3500.00)
  BEGIN
    v_result := pkg_transactions.calc_simple_interest(100000, 3.5, 365);
    IF v_result = 3500.00 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_high_balance|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_high_balance|FAIL|expected:3500.00 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_high_balance|FAIL|' || SQLERRM);
  END;

  -- tc_05: Sıfır ana para → 0 döner
  BEGIN
    v_result := pkg_transactions.calc_simple_interest(0, 5, 365);
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_zero_principal|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_zero_principal|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_zero_principal|FAIL|' || SQLERRM);
  END;

  -- tc_06: Sıfır faiz oranı → 0 döner
  BEGIN
    v_result := pkg_transactions.calc_simple_interest(1000, 0, 365);
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_zero_rate|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_zero_rate|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_zero_rate|FAIL|' || SQLERRM);
  END;

  -- tc_07: Sıfır gün → 0 döner
  BEGIN
    v_result := pkg_transactions.calc_simple_interest(1000, 5, 0);
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_zero_days|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_zero_days|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_zero_days|FAIL|' || SQLERRM);
  END;

  -- tc_08: ROUND(2) kontrolü — (1 * 1% * 1/365 = 0.00)
  BEGIN
    v_result := pkg_transactions.calc_simple_interest(1, 1, 1);
    IF v_result = 0.00 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_rounding_small|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_rounding_small|FAIL|expected:0.00 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_rounding_small|FAIL|' || SQLERRM);
  END;

  -- tc_09: account_types'taki SAVINGS rate (2.5%) ile 500 * 2.5% * 30/365 = 1.03
  BEGIN
    v_result := pkg_transactions.calc_simple_interest(500, 2.5, 30);
    IF v_result = 1.03 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_savings_rate|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_savings_rate|FAIL|expected:1.03 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_savings_rate|FAIL|' || SQLERRM);
  END;

  -- tc_10: account_types'taki CD rate (4.2%) ile 10000 * 4.2% * 90/365 = 103.56
  BEGIN
    v_result := pkg_transactions.calc_simple_interest(10000, 4.2, 90);
    IF v_result = 103.56 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_cd_rate|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_cd_rate|FAIL|expected:103.56 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_cd_rate|FAIL|' || SQLERRM);
  END;

  -- tc_11: NULL principal → NULL döner
  BEGIN
    v_result := pkg_transactions.calc_simple_interest(NULL, 5, 30);
    IF v_result IS NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_null_principal|OK|returned:NULL');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_null_principal|FAIL|expected:NULL got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_null_principal|FAIL|' || SQLERRM);
  END;

  -- tc_12: NULL rate → NULL döner
  BEGIN
    v_result := pkg_transactions.calc_simple_interest(1000, NULL, 30);
    IF v_result IS NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_null_rate|OK|returned:NULL');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_null_rate|FAIL|expected:NULL got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_null_rate|FAIL|' || SQLERRM);
  END;

END;
/