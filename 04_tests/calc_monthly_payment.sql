DECLARE
  v_result NUMBER;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: Standart amortisman (10000, %6, 12 ay)
  -- M = 10000 * (0.005 * 1.005^12) / (1.005^12 - 1) = 860.66
  BEGIN
    v_result := pkg_loan_mgmt.calc_monthly_payment(10000, 6, 12);
    IF v_result = 860.66 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_standard_loan|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_standard_loan|FAIL|expected:860.66 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_standard_loan|FAIL|' || SQLERRM);
  END;

  -- tc_02: Sıfır faiz → basit bölme (6000 / 12 = 500.00)
  BEGIN
    v_result := pkg_loan_mgmt.calc_monthly_payment(6000, 0, 12);
    IF v_result = 500.00 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_zero_rate|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_zero_rate|FAIL|expected:500.00 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_zero_rate|FAIL|' || SQLERRM);
  END;

  -- tc_03: Uzun vadeli mortgage (200000, %7, 360 ay = 30 yıl)
  -- M = 200000 * (0.005833 * 1.005833^360) / (1.005833^360 - 1) = 1330.60
  BEGIN
    v_result := pkg_loan_mgmt.calc_monthly_payment(200000, 7, 360);
    IF v_result = 1330.60 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_mortgage_30yr|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_mortgage_30yr|FAIL|expected:1330.60 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_mortgage_30yr|FAIL|' || SQLERRM);
  END;

  -- tc_04: Kısa vadeli yüksek faiz (5000, %18, 6 ay)
  -- M = 5000 * (0.015 * 1.015^6) / (1.015^6 - 1) = 877.63
  BEGIN
    v_result := pkg_loan_mgmt.calc_monthly_payment(5000, 18, 6);
    IF v_result = 877.63 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_short_high_rate|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_short_high_rate|FAIL|expected:877.63 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_short_high_rate|FAIL|' || SQLERRM);
  END;

  -- tc_05: Tek aylık ödeme (1000, %12, 1 ay)
  -- M = 1000 * (0.01 * 1.01) / (1.01 - 1) = 1010.00
  BEGIN
    v_result := pkg_loan_mgmt.calc_monthly_payment(1000, 12, 1);
    IF v_result = 1010.00 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_single_month|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_single_month|FAIL|expected:1010.00 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_single_month|FAIL|' || SQLERRM);
  END;

  -- tc_06: ROUND(2) kontrolü — sonuç iki ondalık hane
  BEGIN
    v_result := pkg_loan_mgmt.calc_monthly_payment(7500, 9.5, 36);
    IF v_result = ROUND(v_result, 2) AND v_result > 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_rounding|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_rounding|FAIL|unrounded:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_rounding|FAIL|' || SQLERRM);
  END;

  -- tc_07: Yüksek anapara (500000, %5.5, 240 ay = 20 yıl)
  -- c_prime_rate=5.5 → gerçekçi mortgage senaryosu
  BEGIN
    v_result := pkg_loan_mgmt.calc_monthly_payment(500000, 5.5, 240);
    IF v_result > 0 AND v_result < 10000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_large_principal|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_large_principal|FAIL|unexpected:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_large_principal|FAIL|' || SQLERRM);
  END;

  -- tc_08: Çok düşük faiz (1000, %0.1, 12 ay)
  -- M ≈ 1000/12 + küçük faiz ≈ 83.79
  BEGIN
    v_result := pkg_loan_mgmt.calc_monthly_payment(1000, 0.1, 12);
    IF v_result > 83 AND v_result < 85 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_very_low_rate|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_very_low_rate|FAIL|unexpected:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_very_low_rate|FAIL|' || SQLERRM);
  END;

  -- tc_09: Sıfır faiz - bölme doğru (12000, 0, 24 ay = 500.00)
  BEGIN
    v_result := pkg_loan_mgmt.calc_monthly_payment(12000, 0, 24);
    IF v_result = 500.00 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_zero_rate_24mo|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_zero_rate_24mo|FAIL|expected:500.00 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_zero_rate_24mo|FAIL|' || SQLERRM);
  END;

  -- tc_10: Sonuç her zaman pozitif
  BEGIN
    v_result := pkg_loan_mgmt.calc_monthly_payment(25000, 8.5, 48);
    IF v_result > 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_always_positive|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_always_positive|FAIL|non_positive:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_always_positive|FAIL|' || SQLERRM);
  END;

  -- tc_11: Aylık ödeme anapara/vade oranından büyük (faiz var)
  BEGIN
    v_result := pkg_loan_mgmt.calc_monthly_payment(10000, 10, 12);
    IF v_result > ROUND(10000/12, 2) THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_payment_exceeds_principal_div|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_payment_exceeds_principal_div|FAIL|unexpected:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_payment_exceeds_principal_div|FAIL|' || SQLERRM);
  END;

END;
/