DECLARE
  v_result    SYS.ODCIVARCHAR2LIST;
  v_principal NUMBER;
  v_interest  NUMBER;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: Standart split (10000, %6, 860.66)
  -- interest = 10000 * (6/100/12) = 50.00
  -- principal = 860.66 - 50.00 = 810.66
  BEGIN
    v_result    := pkg_loan_mgmt.calc_payment_split(10000, 6, 860.66);
    v_principal := TO_NUMBER(v_result(1));
    v_interest  := TO_NUMBER(v_result(2));
    IF v_principal = 810.66 AND v_interest = 50.00 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_standard_split|OK|principal:' || v_principal || ' interest:' || v_interest);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_standard_split|FAIL|principal:' || v_principal || ' interest:' || v_interest);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_standard_split|FAIL|' || SQLERRM);
  END;

  -- tc_02: Sıfır faiz → tüm ödeme anaparaya gider
  -- interest = 0, principal = 500
  BEGIN
    v_result    := pkg_loan_mgmt.calc_payment_split(6000, 0, 500);
    v_principal := TO_NUMBER(v_result(1));
    v_interest  := TO_NUMBER(v_result(2));
    IF v_principal = 500 AND v_interest = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_zero_rate|OK|principal:' || v_principal || ' interest:' || v_interest);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_zero_rate|FAIL|principal:' || v_principal || ' interest:' || v_interest);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_zero_rate|FAIL|' || SQLERRM);
  END;

  -- tc_03: Ödeme faizi karşılamıyor → principal=0, interest=payment
  -- outstanding=100000, rate=12%, monthly_interest=1000
  -- payment=500 < 1000 → principal=0, interest=500
  BEGIN
    v_result    := pkg_loan_mgmt.calc_payment_split(100000, 12, 500);
    v_principal := TO_NUMBER(v_result(1));
    v_interest  := TO_NUMBER(v_result(2));
    IF v_principal = 0 AND v_interest = 500 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_payment_below_interest|OK|principal:0 interest:500');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_payment_below_interest|FAIL|principal:' || v_principal || ' interest:' || v_interest);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_payment_below_interest|FAIL|' || SQLERRM);
  END;

  -- tc_04: principal + interest = payment (toplam doğru)
  BEGIN
    v_result    := pkg_loan_mgmt.calc_payment_split(15000, 8, 700);
    v_principal := TO_NUMBER(v_result(1));
    v_interest  := TO_NUMBER(v_result(2));
    IF ROUND(v_principal + v_interest, 2) = 700 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_sum_equals_payment|OK|sum:' || (v_principal + v_interest));
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_sum_equals_payment|FAIL|expected:700 got:' || (v_principal + v_interest));
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_sum_equals_payment|FAIL|' || SQLERRM);
  END;

  -- tc_05: Tam faize eşit ödeme → principal=0, interest=payment
  -- outstanding=12000, rate=12% → monthly_interest=120
  -- payment=120 → principal=120-120=0
  BEGIN
    v_result    := pkg_loan_mgmt.calc_payment_split(12000, 12, 120);
    v_principal := TO_NUMBER(v_result(1));
    v_interest  := TO_NUMBER(v_result(2));
    IF v_principal = 0 AND v_interest = 120 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_exact_interest_payment|OK|principal:0 interest:120');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_exact_interest_payment|FAIL|principal:' || v_principal || ' interest:' || v_interest);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_exact_interest_payment|FAIL|' || SQLERRM);
  END;

  -- tc_06: Varray 2 eleman döner
  BEGIN
    v_result := pkg_loan_mgmt.calc_payment_split(10000, 6, 860.66);
    IF v_result.COUNT = 2 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_returns_two_elements|OK|count:' || v_result.COUNT);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_returns_two_elements|FAIL|expected:2 got:' || v_result.COUNT);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_returns_two_elements|FAIL|' || SQLERRM);
  END;

  -- tc_07: principal >= 0 her zaman (negatif principal olmaz)
  BEGIN
    v_result    := pkg_loan_mgmt.calc_payment_split(50000, 24, 100);
    v_principal := TO_NUMBER(v_result(1));
    IF v_principal >= 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_principal_never_negative|OK|principal:' || v_principal);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_principal_never_negative|FAIL|negative:' || v_principal);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_principal_never_negative|FAIL|' || SQLERRM);
  END;

  -- tc_08: ROUND(2) — interest 2 ondalık hane
  -- outstanding=10000, rate=7% → monthly_interest=10000*0.07/12=58.33
  BEGIN
    v_result   := pkg_loan_mgmt.calc_payment_split(10000, 7, 900);
    v_interest := TO_NUMBER(v_result(2));
    IF v_interest = 58.33 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_interest_rounding|OK|interest:' || v_interest);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_interest_rounding|FAIL|expected:58.33 got:' || v_interest);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_interest_rounding|FAIL|' || SQLERRM);
  END;

  -- tc_09: Yüksek ödeme → büyük principal, küçük interest
  -- outstanding=1000, rate=6% → interest=5.00, principal=9995.00 (payment=10000)
  BEGIN
    v_result    := pkg_loan_mgmt.calc_payment_split(1000, 6, 10000);
    v_principal := TO_NUMBER(v_result(1));
    v_interest  := TO_NUMBER(v_result(2));
    IF v_principal = 9995.00 AND v_interest = 5.00 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_large_payment|OK|principal:' || v_principal || ' interest:' || v_interest);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_large_payment|FAIL|principal:' || v_principal || ' interest:' || v_interest);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_large_payment|FAIL|' || SQLERRM);
  END;

  -- tc_10: Eleman string olarak dönüyor — TO_NUMBER dönüşümü çalışır
  BEGIN
    v_result := pkg_loan_mgmt.calc_payment_split(5000, 9, 400);
    BEGIN
      v_principal := TO_NUMBER(v_result(1));
      v_interest  := TO_NUMBER(v_result(2));
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_string_to_number_conversion|OK|principal:' || v_principal || ' interest:' || v_interest);
    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_string_to_number_conversion|FAIL|conversion_error:' || SQLERRM);
    END;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_string_to_number_conversion|FAIL|' || SQLERRM);
  END;

END;
/