-- =============================================================================
-- TEST: calculate_var_exposure
-- Package: pkg_advanced_risk_engine
-- Seed: 1000=Alice(100000 CHECKING branch10), 1001=Bob(100002 CHECKING branch10),
--       1002=Carol(100003 SAVINGS branch11), 1003=David(100004 CHECKING branch11),
--       1004=Eve(100005 PREMIUM branch10)  | employee 2000=John(MANAGER branch10)
-- =============================================================================
DECLARE
  v_var_99   NUMBER;
  v_var_95   NUMBER;
  v_var_1d   NUMBER;
  v_var_10d  NUMBER;
  v_loan_id  NUMBER;
  v_loan_number VARCHAR2(50);
  v_monthly_pay NUMBER;
  v_decision    VARCHAR2(20);

  PROCEDURE make_active_loan(
    p_customer_id IN NUMBER,
    p_account_id  IN NUMBER,
    p_branch_id   IN NUMBER,
    p_amount      IN NUMBER,
    p_type        IN VARCHAR2 DEFAULT 'PERSONAL'
  ) IS
  BEGIN
    pkg_loan_mgmt.originate_loan(
        p_customer_id => p_customer_id,
        p_account_id  => p_account_id,
        p_branch_id   => p_branch_id,
        p_loan_type   => p_type,
        p_amount      => p_amount,
        p_term_months => 24,
        p_employee_id => 2000,
        p_loan_id         => v_loan_id,
        p_loan_number     => v_loan_number,
        p_monthly_payment => v_monthly_pay,
        p_decision        => v_decision
    );
    UPDATE loans SET status = 'ACTIVE', disbursement_date = SYSDATE
    WHERE loan_id = v_loan_id;
  END;

BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: VaR >= 0 (negatif olamaz)
  BEGIN
    make_active_loan(1000, 100000, 10, 10000);
    v_var_99 := pkg_advanced_risk_engine.calculate_var_exposure('ALL', NULL, 0.99, 1);
    ROLLBACK;
    IF v_var_99 >= 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_var_non_negative|OK|var99:' || v_var_99);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_var_non_negative|FAIL|negative_var:' || v_var_99);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_var_non_negative|FAIL|' || SQLERRM);
  END;

  -- tc_02: VaR(99%) >= VaR(95%) (daha yüksek güven aralığı → daha yüksek VaR)
  BEGIN
    make_active_loan(1000, 100000, 10, 20000);
    make_active_loan(1001, 100002, 10, 15000);
    make_active_loan(1002, 100003, 11, 10000);
    make_active_loan(1002, 100003, 11, 8000, 'AUTO');
    make_active_loan(1000, 100000, 10, 5000, 'MORTGAGE');
    v_var_99 := pkg_advanced_risk_engine.calculate_var_exposure('ALL', NULL, 0.99, 1);
    v_var_95 := pkg_advanced_risk_engine.calculate_var_exposure('ALL', NULL, 0.95, 1);
    ROLLBACK;
    IF v_var_99 >= v_var_95 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_var99_gte_var95|OK|var99:' || v_var_99 || ' var95:' || v_var_95);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_var99_gte_var95|FAIL|var99:' || v_var_99 || ' var95:' || v_var_95);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_var99_gte_var95|FAIL|' || SQLERRM);
  END;

  -- tc_03: 10 günlük horizon → 1 günlükten büyük (sqrt(t) skalası)
  BEGIN
    make_active_loan(1000, 100000, 10, 20000);
    make_active_loan(1001, 100002, 10, 15000);
    make_active_loan(1002, 100003, 11, 10000);
    make_active_loan(1002, 100003, 11, 8000, 'AUTO');
    make_active_loan(1000, 100000, 10, 5000, 'BUSINESS');
    v_var_1d  := pkg_advanced_risk_engine.calculate_var_exposure('ALL', NULL, 0.99, 1);
    v_var_10d := pkg_advanced_risk_engine.calculate_var_exposure('ALL', NULL, 0.99, 10);
    ROLLBACK;
    IF v_var_10d > v_var_1d THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_horizon_scaling|OK|1d:' || v_var_1d || ' 10d:' || v_var_10d);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_horizon_scaling|FAIL|1d:' || v_var_1d || ' 10d:' || v_var_10d);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_horizon_scaling|FAIL|' || SQLERRM);
  END;

  -- tc_04: RETAIL scope → ALL scope'tan küçük veya eşit
  BEGIN
    make_active_loan(1000, 100000, 10, 20000, 'PERSONAL');
    make_active_loan(1001, 100002, 10, 15000, 'AUTO');
    make_active_loan(1002, 100003, 11, 50000, 'MORTGAGE');
    make_active_loan(1002, 100003, 11, 30000, 'BUSINESS');
    v_var_99 := pkg_advanced_risk_engine.calculate_var_exposure('ALL',    NULL, 0.99, 1);
    v_var_95 := pkg_advanced_risk_engine.calculate_var_exposure('RETAIL', NULL, 0.99, 1);
    ROLLBACK;
    IF v_var_99 >= v_var_95 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_retail_lte_all|OK|all:' || v_var_99 || ' retail:' || v_var_95);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_retail_lte_all|FAIL|all:' || v_var_99 || ' retail:' || v_var_95);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_retail_lte_all|FAIL|' || SQLERRM);
  END;

  -- tc_05: Yetersiz veri (< 5 loan) → 0 döner
  BEGIN
    UPDATE loans SET status = 'PAID_OFF' WHERE status IN ('ACTIVE','DEFAULTED');
    make_active_loan(1000, 100000, 10, 5000);
    v_var_99 := pkg_advanced_risk_engine.calculate_var_exposure('ALL', NULL, 0.99, 1);
    ROLLBACK;
    IF v_var_99 = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_insufficient_data_zero|OK|var:0');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_insufficient_data_zero|FAIL|expected:0 got:' || v_var_99);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_insufficient_data_zero|FAIL|' || SQLERRM);
  END;

  -- tc_06: branch_id filtresiyle çağrı yapılabilir
  BEGIN
    make_active_loan(1000, 100000, 10, 10000);
    v_var_99 := pkg_advanced_risk_engine.calculate_var_exposure('ALL', 10, 0.99, 1);
    ROLLBACK;
    IF v_var_99 >= 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_branch_filter|OK|var:' || v_var_99);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_branch_filter|FAIL|var:' || v_var_99);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_branch_filter|FAIL|' || SQLERRM);
  END;

  -- tc_07: Büyük portföyde VaR küçük portföyden büyük olmalı
  BEGIN
    make_active_loan(1000, 100000, 10, 1000);
    make_active_loan(1001, 100002, 10, 1000);
    make_active_loan(1002, 100003, 11, 1000);
    make_active_loan(1002, 100003, 11, 1000, 'AUTO');
    make_active_loan(1000, 100000, 10, 1000, 'BUSINESS');
    v_var_1d := pkg_advanced_risk_engine.calculate_var_exposure('ALL', NULL, 0.99, 1);
    ROLLBACK;
    make_active_loan(1000, 100000, 10, 100000);
    make_active_loan(1001, 100002, 10, 100000);
    make_active_loan(1002, 100003, 11, 100000);
    make_active_loan(1002, 100003, 11, 100000, 'AUTO');
    make_active_loan(1000, 100000, 10, 100000, 'BUSINESS');
    v_var_10d := pkg_advanced_risk_engine.calculate_var_exposure('ALL', NULL, 0.99, 1);
    ROLLBACK;
    IF v_var_10d > v_var_1d THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_large_portfolio_higher_var|OK|small:' || v_var_1d || ' large:' || v_var_10d);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_large_portfolio_higher_var|FAIL|small:' || v_var_1d || ' large:' || v_var_10d);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_large_portfolio_higher_var|FAIL|' || SQLERRM);
  END;

END;
/
