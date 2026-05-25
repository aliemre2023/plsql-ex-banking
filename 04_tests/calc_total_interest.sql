DECLARE
  v_result  NUMBER;
  v_monthly NUMBER;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: Standart (10000, %6, 12 ay)
  -- expected = monthly*term - principal
  BEGIN
    v_monthly := pkg_loan_mgmt.calc_monthly_payment(10000, 6, 12);
    v_result := pkg_loan_mgmt.calc_total_interest(10000, 6, 12);
    IF v_result = ROUND(v_monthly * 12 - 10000, 2) THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_standard_loan|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_standard_loan|FAIL|expected:' ||
        ROUND(v_monthly * 12 - 10000, 2) || ' got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_standard_loan|FAIL|' || SQLERRM);
  END;

  -- tc_02: Sıfır faiz → toplam faiz = 0
  -- monthly=500.00 → 500*12-6000=0
  BEGIN
    v_result := pkg_loan_mgmt.calc_total_interest(6000, 0, 12);
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_zero_rate|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_zero_rate|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_zero_rate|FAIL|' || SQLERRM);
  END;

  -- tc_03: Mortgage 30 yıl (200000, %7, 360 ay)
  -- expected = monthly*term - principal
  BEGIN
    v_monthly := pkg_loan_mgmt.calc_monthly_payment(200000, 7, 360);
    v_result := pkg_loan_mgmt.calc_total_interest(200000, 7, 360);
    IF v_result = ROUND(v_monthly * 360 - 200000, 2) THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_mortgage_30yr|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_mortgage_30yr|FAIL|expected:' ||
        ROUND(v_monthly * 360 - 200000, 2) || ' got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_mortgage_30yr|FAIL|' || SQLERRM);
  END;

  -- tc_04: Kısa vade yüksek faiz (5000, %18, 6 ay)
  -- expected = monthly*term - principal
  BEGIN
    v_monthly := pkg_loan_mgmt.calc_monthly_payment(5000, 18, 6);
    v_result := pkg_loan_mgmt.calc_total_interest(5000, 18, 6);
    IF v_result = ROUND(v_monthly * 6 - 5000, 2) THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_short_high_rate|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_short_high_rate|FAIL|expected:' ||
        ROUND(v_monthly * 6 - 5000, 2) || ' got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_short_high_rate|FAIL|' || SQLERRM);
  END;

  -- tc_05: Tek aylık ödeme (1000, %12, 1 ay)
  -- monthly=1010.00 → 1010*1-1000=10.00
  BEGIN
    v_result := pkg_loan_mgmt.calc_total_interest(1000, 12, 1);
    IF v_result = 10.00 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_single_month|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_single_month|FAIL|expected:10.00 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_single_month|FAIL|' || SQLERRM);
  END;

  -- tc_06: Toplam faiz her zaman >= 0 (faiz varsa pozitif)
  BEGIN
    v_result := pkg_loan_mgmt.calc_total_interest(25000, 8.5, 48);
    IF v_result >= 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_always_non_negative|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_always_non_negative|FAIL|negative:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_always_non_negative|FAIL|' || SQLERRM);
  END;

  -- tc_07: Toplam faiz = monthly*term - principal ile tutarlı
  BEGIN
    v_monthly := pkg_loan_mgmt.calc_monthly_payment(10000, 6, 12);
    v_result  := pkg_loan_mgmt.calc_total_interest(10000, 6, 12);
    IF v_result = ROUND(v_monthly * 12 - 10000, 2) THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_consistent_with_monthly|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_consistent_with_monthly|FAIL|expected:' ||
        ROUND(v_monthly * 12 - 10000, 2) || ' got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_consistent_with_monthly|FAIL|' || SQLERRM);
  END;

  -- tc_08: Daha uzun vade → daha yüksek toplam faiz (aynı rate, aynı anapara)
  DECLARE
    v_short NUMBER;
    v_long  NUMBER;
  BEGIN
    v_short := pkg_loan_mgmt.calc_total_interest(10000, 8, 12);
    v_long  := pkg_loan_mgmt.calc_total_interest(10000, 8, 36);
    IF v_long > v_short THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_longer_term_more_interest|OK|short:' || v_short || ' long:' || v_long);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_longer_term_more_interest|FAIL|short:' || v_short || ' long:' || v_long);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_longer_term_more_interest|FAIL|' || SQLERRM);
  END;

  -- tc_09: Daha yüksek faiz → daha yüksek toplam faiz (aynı vade, aynı anapara)
  DECLARE
    v_low  NUMBER;
    v_high NUMBER;
  BEGIN
    v_low  := pkg_loan_mgmt.calc_total_interest(10000, 5, 24);
    v_high := pkg_loan_mgmt.calc_total_interest(10000, 15, 24);
    IF v_high > v_low THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_higher_rate_more_interest|OK|low:' || v_low || ' high:' || v_high);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_higher_rate_more_interest|FAIL|low:' || v_low || ' high:' || v_high);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_higher_rate_more_interest|FAIL|' || SQLERRM);
  END;

  -- tc_10: ROUND(2) kontrolü
  BEGIN
    v_result := pkg_loan_mgmt.calc_total_interest(7500, 9.5, 36);
    IF v_result = ROUND(v_result, 2) AND v_result > 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_rounding|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_rounding|FAIL|unexpected:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_rounding|FAIL|' || SQLERRM);
  END;

END;
/