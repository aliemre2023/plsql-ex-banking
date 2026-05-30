DECLARE
  v_raroc       NUMBER;
  v_raroc2      NUMBER;
  v_loan_id     NUMBER;
  v_loan_number VARCHAR2(50);
  v_monthly_pay NUMBER;
  v_decision    VARCHAR2(20);

  PROCEDURE make_active_loan(
    p_customer_id IN NUMBER,
    p_account_id  IN NUMBER,
    p_amount      IN NUMBER,
    p_type        IN VARCHAR2 DEFAULT 'PERSONAL',
    p_rate_override IN NUMBER DEFAULT NULL
  ) IS
  BEGIN
    pkg_loan_mgmt.originate_loan(
        p_customer_id => p_customer_id, p_account_id => p_account_id,
        p_branch_id => 10, p_loan_type => p_type,
        p_amount => p_amount, p_term_months => 24,
        p_employee_id => 2000,
        p_loan_id => v_loan_id, p_loan_number => v_loan_number,
        p_monthly_payment => v_monthly_pay, p_decision => v_decision
    );
    UPDATE loans SET status = 'ACTIVE', disbursement_date = SYSDATE
    WHERE loan_id = v_loan_id;
    IF p_rate_override IS NOT NULL THEN
      UPDATE loans SET interest_rate = p_rate_override WHERE loan_id = v_loan_id;
    END IF;
  END;

BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: Geçerli aktif loan için RAROC sonuç döner (NULL değil)
  BEGIN
    make_active_loan(1000, 100000, 10000, 'PERSONAL');
    v_raroc := pkg_advanced_risk_engine.calculate_raroc(v_loan_id, SYSDATE);
    ROLLBACK;
    IF v_raroc IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_raroc_not_null|OK|raroc:' || v_raroc);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_raroc_not_null|FAIL|returned null');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_raroc_not_null|FAIL|' || SQLERRM);
  END;

  -- tc_02: RAROC sayısal değer (ROUND(4) kontrolü)
  BEGIN
    make_active_loan(1000, 100000, 10000, 'PERSONAL');
    v_raroc := pkg_advanced_risk_engine.calculate_raroc(v_loan_id, SYSDATE);
    ROLLBACK;
    IF v_raroc = ROUND(v_raroc, 4) THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_raroc_4dp_precision|OK|raroc:' || v_raroc);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_raroc_4dp_precision|FAIL|not_rounded:' || v_raroc);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_raroc_4dp_precision|FAIL|' || SQLERRM);
  END;

  -- tc_03: Yüksek faizli loan → düşük faizliden daha yüksek RAROC
  BEGIN
    make_active_loan(1000, 100000, 10000, 'PERSONAL', 18.0);
    v_raroc := pkg_advanced_risk_engine.calculate_raroc(v_loan_id, SYSDATE);
    ROLLBACK;
    make_active_loan(1000, 100000, 10000, 'PERSONAL', 5.0);
    v_raroc2 := pkg_advanced_risk_engine.calculate_raroc(v_loan_id, SYSDATE);
    ROLLBACK;
    IF v_raroc > v_raroc2 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_high_rate_higher_raroc|OK|rate18:' || v_raroc || ' rate5:' || v_raroc2);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_high_rate_higher_raroc|FAIL|rate18:' || v_raroc || ' rate5:' || v_raroc2);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_high_rate_higher_raroc|FAIL|' || SQLERRM);
  END;

  -- tc_04: Mortgage (teminatlı) → düşük LGD → economic capital daha düşük → RAROC yüksek olabilir
  BEGIN
    make_active_loan(1000, 100000, 50000, 'MORTGAGE', 6.5);
    UPDATE loans SET collateral_type = 'REAL_ESTATE', collateral_value = 80000
    WHERE loan_id = v_loan_id;
    v_raroc := pkg_advanced_risk_engine.calculate_raroc(v_loan_id, SYSDATE);
    ROLLBACK;
    IF v_raroc IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_mortgage_raroc_computed|OK|raroc:' || v_raroc);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_mortgage_raroc_computed|FAIL|returned null');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_mortgage_raroc_computed|FAIL|' || SQLERRM);
  END;

  -- tc_05: Var olmayan loan_id → -20200 exception
  BEGIN
    v_raroc := pkg_advanced_risk_engine.calculate_raroc(999999, SYSDATE);
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_nonexistent_loan|FAIL|expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -20200 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_nonexistent_loan|OK|exception_raised:-20200');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_nonexistent_loan|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_06: DEFAULTED loan → PD=1 → EL yüksek → RAROC düşük (negatif olabilir)
  BEGIN
    make_active_loan(1001, 100002, 10000, 'PERSONAL', 8.0);
    UPDATE loans SET status = 'DEFAULTED' WHERE loan_id = v_loan_id;
    v_raroc := pkg_advanced_risk_engine.calculate_raroc(v_loan_id, SYSDATE);
    ROLLBACK;
    IF v_raroc IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_defaulted_loan_raroc|OK|raroc:' || v_raroc);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_defaulted_loan_raroc|FAIL|returned null');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_defaulted_loan_raroc|FAIL|' || SQLERRM);
  END;

  -- tc_07: Düşük riskli müşteri için RAROC, yüksek riskli müşteriden büyük olmalı
  -- Aynı faiz oranı, aynı tutar; alice (810, LOW) vs bob (420, HIGH)
  -- Her iki update + her iki loan aynı transaction'da → tek ROLLBACK
  BEGIN
    UPDATE customers SET credit_score = 810, risk_level = 'LOW'  WHERE customer_id = 1000;
    UPDATE customers SET credit_score = 420, risk_level = 'HIGH' WHERE customer_id = 1001;
    make_active_loan(1000, 100000, 10000, 'PERSONAL', 10.0);
    v_raroc := pkg_advanced_risk_engine.calculate_raroc(v_loan_id, SYSDATE);
    make_active_loan(1001, 100002, 10000, 'PERSONAL', 10.0);
    v_raroc2 := pkg_advanced_risk_engine.calculate_raroc(v_loan_id, SYSDATE);
    ROLLBACK;
    IF v_raroc >= v_raroc2 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_low_risk_higher_raroc|OK|low_risk:' || v_raroc || ' high_risk:' || v_raroc2);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_low_risk_higher_raroc|FAIL|low_risk:' || v_raroc || ' high_risk:' || v_raroc2);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_low_risk_higher_raroc|FAIL|' || SQLERRM);
  END;

  -- tc_08: as_of_date parametresiyle geçmiş tarih çalışır
  BEGIN
    make_active_loan(1000, 100000, 10000, 'PERSONAL');
    v_raroc := pkg_advanced_risk_engine.calculate_raroc(v_loan_id, SYSDATE - 30);
    ROLLBACK;
    IF v_raroc IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_past_as_of_date|OK|raroc:' || v_raroc);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_past_as_of_date|FAIL|returned null');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_past_as_of_date|FAIL|' || SQLERRM);
  END;

END;
/
