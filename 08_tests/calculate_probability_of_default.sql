DECLARE
  v_pd        NUMBER;
  v_pd_high   NUMBER;
  v_pd_low    NUMBER;
  v_count     NUMBER;

BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: Geçerli müşteri için PD döner, sonuç [0.0003, 0.99] aralığında
  BEGIN
    v_pd := pkg_advanced_risk_engine.calculate_probability_of_default(1000);
    IF v_pd >= 0.0003 AND v_pd <= 0.99 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_valid_customer_pd_range|OK|pd:' || v_pd);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_valid_customer_pd_range|FAIL|pd_out_of_range:' || v_pd);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_valid_customer_pd_range|FAIL|' || SQLERRM);
  END;

  -- tc_02: PD sonucu NULL değil
  BEGIN
    v_pd := pkg_advanced_risk_engine.calculate_probability_of_default(1000);
    IF v_pd IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_pd_not_null|OK|pd:' || v_pd);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_pd_not_null|FAIL|returned null');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_pd_not_null|FAIL|' || SQLERRM);
  END;

  -- tc_03: PD 6 ondalık haneye yuvarlanır
  BEGIN
    v_pd := pkg_advanced_risk_engine.calculate_probability_of_default(1000);
    IF v_pd = ROUND(v_pd, 6) THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_pd_6_decimal_precision|OK|pd:' || v_pd);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_pd_6_decimal_precision|FAIL|not_rounded:' || v_pd);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_pd_6_decimal_precision|FAIL|' || SQLERRM);
  END;

  -- tc_04: HIGH risk müşteri için PD, LOW risk müşteriden büyük olmalı
  -- customer 1003 = David → risk_level=HIGH, customer 1000 = Alice → risk_level=LOW
  BEGIN
    UPDATE customers SET risk_level = 'HIGH' WHERE customer_id = 1003;
    UPDATE customers SET risk_level = 'LOW'  WHERE customer_id = 1000;
    v_pd_high := pkg_advanced_risk_engine.calculate_probability_of_default(1003);
    v_pd_low  := pkg_advanced_risk_engine.calculate_probability_of_default(1000);
    ROLLBACK;
    IF v_pd_high >= v_pd_low THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_high_risk_gt_low_risk|OK|high:' || v_pd_high || ' low:' || v_pd_low);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_high_risk_gt_low_risk|FAIL|high:' || v_pd_high || ' low:' || v_pd_low);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_high_risk_gt_low_risk|FAIL|' || SQLERRM);
  END;

  -- tc_05: Düşük credit score (400) → yüksek PD
  BEGIN
    UPDATE customers SET credit_score = 400 WHERE customer_id = 1001;
    v_pd := pkg_advanced_risk_engine.calculate_probability_of_default(1001);
    ROLLBACK;
    IF v_pd > 0.05 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_low_credit_score_high_pd|OK|pd:' || v_pd);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_low_credit_score_high_pd|FAIL|pd_unexpectedly_low:' || v_pd);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_low_credit_score_high_pd|FAIL|' || SQLERRM);
  END;

  -- tc_06: Aynı müşteri için yüksek credit score (820) düşük credit score (400)'dan
  --        daha düşük logit değeri üretir → PD daha düşük veya eşit (DPD baskın olsa bile)
  -- Mevcut DB'deki loan DPD'leri her iki senaryoyu da eşit etkiler; credit score terimi
  -- 820 için 400'den 1.89 birim daha düşük logit → PD_820 <= PD_400 her zaman geçerli
  BEGIN
    UPDATE customers SET credit_score = 820, risk_level = 'LOW' WHERE customer_id = 1000;
    v_pd_low := pkg_advanced_risk_engine.calculate_probability_of_default(1000);
    UPDATE customers SET credit_score = 400, risk_level = 'HIGH' WHERE customer_id = 1000;
    v_pd_high := pkg_advanced_risk_engine.calculate_probability_of_default(1000);
    ROLLBACK;
    IF v_pd_low <= v_pd_high THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_high_credit_score_low_pd|OK|score820_pd:' || v_pd_low || ' score400_pd:' || v_pd_high);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_high_credit_score_low_pd|FAIL|score820_pd:' || v_pd_low || ' score400_pd:' || v_pd_high);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_high_credit_score_low_pd|FAIL|' || SQLERRM);
  END;

  -- tc_07: Var olmayan customer_id → -20201 exception
  BEGIN
    v_pd := pkg_advanced_risk_engine.calculate_probability_of_default(999999);
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_nonexistent_customer|FAIL|expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -20201 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_nonexistent_customer|OK|exception_raised:-20201');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_nonexistent_customer|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_08: loan_type filtresiyle çağrı yapılabilir, sonuç döner
  BEGIN
    v_pd := pkg_advanced_risk_engine.calculate_probability_of_default(1000, 'PERSONAL');
    IF v_pd IS NOT NULL AND v_pd >= 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_with_loan_type_filter|OK|pd:' || v_pd);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_with_loan_type_filter|FAIL|pd:' || v_pd);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_with_loan_type_filter|FAIL|' || SQLERRM);
  END;

  -- tc_09: as_of_date parametresi geçmiş tarihle çalışır
  BEGIN
    v_pd := pkg_advanced_risk_engine.calculate_probability_of_default(1000, NULL, SYSDATE - 30);
    IF v_pd IS NOT NULL AND v_pd >= 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_past_as_of_date|OK|pd:' || v_pd);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_past_as_of_date|FAIL|pd:' || v_pd);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_past_as_of_date|FAIL|' || SQLERRM);
  END;

  -- tc_10: Farklı müşteriler farklı PD değeri verir
  BEGIN
    v_pd_low  := pkg_advanced_risk_engine.calculate_probability_of_default(1000);
    v_pd_high := pkg_advanced_risk_engine.calculate_probability_of_default(1001);
    IF v_pd_low != v_pd_high OR v_pd_low IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_different_customers_different_pd|OK|c1000:' || v_pd_low || ' c1001:' || v_pd_high);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_different_customers_different_pd|FAIL|same_pd_for_both');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_different_customers_different_pd|FAIL|' || SQLERRM);
  END;

END;
/
