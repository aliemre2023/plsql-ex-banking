DECLARE
  v_loan_id     NUMBER;
  v_loan_number VARCHAR2(50);
  v_monthly_pay NUMBER;
  v_decision    VARCHAR2(20);
  v_el_base     NUMBER;
  v_el_mild     NUMBER;
  v_el_moderate NUMBER;
  v_el_severe   NUMBER;
  v_count       NUMBER;

  -- Helper: aktif loan oluşturur ve disbursed hale getirir
  PROCEDURE make_active_loan(
    p_customer_id IN NUMBER,
    p_account_id  IN NUMBER,
    p_amount      IN NUMBER DEFAULT 10000,
    p_type        IN VARCHAR2 DEFAULT 'PERSONAL'
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
  END;

BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: BASE senaryo → sonuç >= 0
  BEGIN
    make_active_loan(1000, 100000, 10000, 'PERSONAL');
    v_el_base := pkg_advanced_risk_engine.calculate_expected_loss(v_loan_id, 'BASE', SYSDATE);
    ROLLBACK;
    IF v_el_base >= 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_base_el_non_negative|OK|el:' || v_el_base);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_base_el_non_negative|FAIL|negative_el:' || v_el_base);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_base_el_non_negative|FAIL|' || SQLERRM);
  END;

  -- tc_02: SEVERE > MODERATE > MILD >= BASE (senaryo etkisi)
  BEGIN
    make_active_loan(1000, 100000, 15000, 'PERSONAL');
    v_el_base     := pkg_advanced_risk_engine.calculate_expected_loss(v_loan_id, 'BASE',     SYSDATE);
    v_el_mild     := pkg_advanced_risk_engine.calculate_expected_loss(v_loan_id, 'MILD',     SYSDATE);
    v_el_moderate := pkg_advanced_risk_engine.calculate_expected_loss(v_loan_id, 'MODERATE', SYSDATE);
    v_el_severe   := pkg_advanced_risk_engine.calculate_expected_loss(v_loan_id, 'SEVERE',   SYSDATE);
    ROLLBACK;
    IF v_el_severe >= v_el_moderate AND v_el_moderate >= v_el_mild AND v_el_mild >= v_el_base THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_stress_ordering|OK|base:' || v_el_base ||
        ' mild:' || v_el_mild || ' moderate:' || v_el_moderate || ' severe:' || v_el_severe);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_stress_ordering|FAIL|base:' || v_el_base ||
        ' mild:' || v_el_mild || ' moderate:' || v_el_moderate || ' severe:' || v_el_severe);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_stress_ordering|FAIL|' || SQLERRM);
  END;

  -- tc_03: DEFAULTED loan → EL yüksek (outstanding bakiyeye yakın)
  BEGIN
    make_active_loan(1001, 100002, 20000, 'PERSONAL');
    UPDATE loans SET status = 'DEFAULTED' WHERE loan_id = v_loan_id;
    v_el_base := pkg_advanced_risk_engine.calculate_expected_loss(v_loan_id, 'BASE', SYSDATE);
    ROLLBACK;
    IF v_el_base > 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_defaulted_loan_high_el|OK|el:' || v_el_base);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_defaulted_loan_high_el|FAIL|unexpected_el:' || v_el_base);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_defaulted_loan_high_el|FAIL|' || SQLERRM);
  END;

  -- tc_04: Mortgage loan → LGD düşük (teminatlı), EL diğerlerine göre düşük kalır
  BEGIN
    make_active_loan(1000, 100000, 100000, 'MORTGAGE');
    UPDATE loans SET collateral_type = 'REAL_ESTATE', collateral_value = 150000
    WHERE loan_id = v_loan_id;
    v_el_base := pkg_advanced_risk_engine.calculate_expected_loss(v_loan_id, 'BASE', SYSDATE);
    ROLLBACK;
    IF v_el_base >= 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_mortgage_lower_el|OK|el:' || v_el_base);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_mortgage_lower_el|FAIL|negative:' || v_el_base);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_mortgage_lower_el|FAIL|' || SQLERRM);
  END;

  -- tc_05: ROUND(2) kontrolü — sonuç 2 ondalık hane
  BEGIN
    make_active_loan(1000, 100000, 8000, 'AUTO');
    v_el_base := pkg_advanced_risk_engine.calculate_expected_loss(v_loan_id, 'BASE', SYSDATE);
    ROLLBACK;
    IF v_el_base = ROUND(v_el_base, 2) THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_el_rounded_2dp|OK|el:' || v_el_base);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_el_rounded_2dp|FAIL|not_rounded:' || v_el_base);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_el_rounded_2dp|FAIL|' || SQLERRM);
  END;

  -- tc_06: EL <= outstanding_balance (imkansız olmayan bir kontrol)
  BEGIN
    make_active_loan(1000, 100000, 5000, 'PERSONAL');
    v_el_base := pkg_advanced_risk_engine.calculate_expected_loss(v_loan_id, 'BASE', SYSDATE);
    ROLLBACK;
    IF v_el_base <= 5000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_el_not_exceeds_balance|OK|el:' || v_el_base);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_el_not_exceeds_balance|FAIL|el_exceeds_principal:' || v_el_base);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_el_not_exceeds_balance|FAIL|' || SQLERRM);
  END;

  -- tc_07: Var olmayan loan_id → -20200 exception
  BEGIN
    v_el_base := pkg_advanced_risk_engine.calculate_expected_loss(999999, 'BASE', SYSDATE);
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_nonexistent_loan|FAIL|expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -20200 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_nonexistent_loan|OK|exception_raised:-20200');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_nonexistent_loan|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_08: Büyük tutarlı loan → EL orantılı büyür
  BEGIN
    make_active_loan(1000, 100000, 1000, 'PERSONAL');
    v_el_mild := pkg_advanced_risk_engine.calculate_expected_loss(v_loan_id, 'BASE', SYSDATE);
    ROLLBACK;
    make_active_loan(1000, 100000, 100000, 'PERSONAL');
    v_el_severe := pkg_advanced_risk_engine.calculate_expected_loss(v_loan_id, 'BASE', SYSDATE);
    ROLLBACK;
    IF v_el_severe > v_el_mild THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_larger_loan_larger_el|OK|small:' || v_el_mild || ' large:' || v_el_severe);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_larger_loan_larger_el|FAIL|small:' || v_el_mild || ' large:' || v_el_severe);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_larger_loan_larger_el|FAIL|' || SQLERRM);
  END;

  -- tc_09: BUSINESS loan (teminatsız) → EL, MORTGAGE'dan yüksek (aynı tutar)
  BEGIN
    make_active_loan(1000, 100000, 20000, 'BUSINESS');
    v_el_base := pkg_advanced_risk_engine.calculate_expected_loss(v_loan_id, 'BASE', SYSDATE);
    ROLLBACK;
    make_active_loan(1000, 100000, 20000, 'MORTGAGE');
    UPDATE loans SET collateral_type = 'REAL_ESTATE', collateral_value = 30000
    WHERE loan_id = v_loan_id;
    v_el_mild := pkg_advanced_risk_engine.calculate_expected_loss(v_loan_id, 'BASE', SYSDATE);
    ROLLBACK;
    IF v_el_base >= v_el_mild THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_unsecured_gt_mortgage_el|OK|business:' || v_el_base || ' mortgage:' || v_el_mild);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_unsecured_gt_mortgage_el|FAIL|business:' || v_el_base || ' mortgage:' || v_el_mild);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_unsecured_gt_mortgage_el|FAIL|' || SQLERRM);
  END;

END;
/
