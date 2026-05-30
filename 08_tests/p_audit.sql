DECLARE
  v_count      NUMBER;
  v_loan_id    NUMBER;
  v_loan_number VARCHAR2(50);
  v_monthly_pay NUMBER;
  v_decision   VARCHAR2(20);
  v_marker     TIMESTAMP;

  -- Risk Engine prosedürü çağırır, audit_log kontrolü yapar
  PROCEDURE make_active_loan(
    p_customer_id IN NUMBER,
    p_account_id  IN NUMBER,
    p_amount      IN NUMBER DEFAULT 10000
  ) IS
  BEGIN
    pkg_loan_mgmt.originate_loan(
        p_customer_id => p_customer_id, p_account_id => p_account_id,
        p_branch_id => 10, p_loan_type => 'PERSONAL',
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

  -- tc_01: perform_credit_risk_assessment → audit_log'a CREDIT_ASSESSMENT kaydı düşer
  DECLARE
    v_rs NUMBER; v_rb VARCHAR2(20); v_pd NUMBER; v_lgd NUMBER;
    v_ead NUMBER; v_el NUMBER; v_rec VARCHAR2(500); v_cur SYS_REFCURSOR;
  BEGIN
    v_marker := SYSTIMESTAMP;
    make_active_loan(1000, 100000);
    pkg_advanced_risk_engine.perform_credit_risk_assessment(
        1000, NULL, SYSDATE, v_rs, v_rb, v_pd, v_lgd, v_ead, v_el, v_rec, v_cur
    );
    IF v_cur%ISOPEN THEN CLOSE v_cur; END IF;
    SELECT COUNT(*) INTO v_count
    FROM   audit_log
    WHERE  table_name  = 'CUSTOMERS'
      AND  record_id   = 1000
      AND  new_values  LIKE '%CREDIT_ASSESSMENT%'
      AND  changed_at >= v_marker;
    ROLLBACK;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_credit_assessment_audit|OK|count:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_credit_assessment_audit|FAIL|expected:>=1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_credit_assessment_audit|FAIL|' || SQLERRM);
  END;

  -- tc_02: run_portfolio_stress_test → audit_log'a STRESS_TEST kaydı düşer
  DECLARE
    v_la NUMBER; v_pre NUMBER; v_post NUMBER; v_ci NUMBER; v_bc NUMBER;
    v_cur SYS_REFCURSOR;
  BEGIN
    v_marker := SYSTIMESTAMP;
    make_active_loan(1000, 100000, 15000);
    make_active_loan(1001, 100002, 20000);
    pkg_advanced_risk_engine.run_portfolio_stress_test(
        'MILD', NULL, SYSDATE, v_la, v_pre, v_post, v_ci, v_bc, v_cur
    );
    IF v_cur%ISOPEN THEN CLOSE v_cur; END IF;
    SELECT COUNT(*) INTO v_count
    FROM   audit_log
    WHERE  new_values LIKE '%STRESS_TEST_MILD%'
      AND  changed_at >= v_marker;
    ROLLBACK;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_stress_test_audit|OK|count:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_stress_test_audit|FAIL|expected:>=1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_stress_test_audit|FAIL|' || SQLERRM);
  END;

  -- tc_03: compute_regulatory_capital → audit_log'a REGULATORY_CAPITAL kaydı düşer
  DECLARE
    v_t1 NUMBER; v_t2 NUMBER; v_rwa NUMBER; v_car NUMBER; v_t1r NUMBER;
    v_comp VARCHAR2(1); v_sf NUMBER; v_cur SYS_REFCURSOR;
  BEGIN
    v_marker := SYSTIMESTAMP;
    make_active_loan(1000, 100000, 10000);
    pkg_advanced_risk_engine.compute_regulatory_capital(
        NULL, SYSDATE, v_t1, v_t2, v_rwa, v_car, v_t1r, v_comp, v_sf, v_cur
    );
    IF v_cur%ISOPEN THEN CLOSE v_cur; END IF;
    SELECT COUNT(*) INTO v_count
    FROM   audit_log
    WHERE  new_values LIKE '%REGULATORY_CAPITAL%'
      AND  changed_at >= v_marker;
    ROLLBACK;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_regulatory_capital_audit|OK|count:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_regulatory_capital_audit|FAIL|expected:>=1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_regulatory_capital_audit|FAIL|' || SQLERRM);
  END;

  -- tc_04: assess_liquidity_risk → audit_log'a LIQUIDITY_ASSESSMENT kaydı düşer
  DECLARE
    v_lcr NUMBER; v_nsfr NUMBER; v_g30 NUMBER; v_g90 NUMBER;
    v_hqla NUMBER; v_comp VARCHAR2(1); v_cur SYS_REFCURSOR;
  BEGIN
    v_marker := SYSTIMESTAMP;
    pkg_advanced_risk_engine.assess_liquidity_risk(
        NULL, SYSDATE, v_lcr, v_nsfr, v_g30, v_g90, v_hqla, v_comp, v_cur
    );
    IF v_cur%ISOPEN THEN CLOSE v_cur; END IF;
    SELECT COUNT(*) INTO v_count
    FROM   audit_log
    WHERE  new_values LIKE '%LIQUIDITY_ASSESSMENT%'
      AND  changed_at >= v_marker;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_liquidity_audit|OK|count:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_liquidity_audit|FAIL|expected:>=1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_liquidity_audit|FAIL|' || SQLERRM);
  END;

  -- tc_05: detect_concentration_risk → audit_log'a CONCENTRATION_RISK kaydı düşer
  DECLARE
    v_ht NUMBER; v_hg NUMBER; v_hc NUMBER; v_tp NUMBER;
    v_al VARCHAR2(20); v_cur SYS_REFCURSOR;
  BEGIN
    v_marker := SYSTIMESTAMP;
    make_active_loan(1000, 100000, 10000);
    pkg_advanced_risk_engine.detect_concentration_risk(
        SYSDATE, NULL, v_ht, v_hg, v_hc, v_tp, v_al, v_cur
    );
    IF v_cur%ISOPEN THEN CLOSE v_cur; END IF;
    SELECT COUNT(*) INTO v_count
    FROM   audit_log
    WHERE  new_values LIKE '%CONCENTRATION_RISK%'
      AND  changed_at >= v_marker;
    ROLLBACK;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_concentration_audit|OK|count:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_concentration_audit|FAIL|expected:>=1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_concentration_audit|FAIL|' || SQLERRM);
  END;

  -- tc_06: generate_risk_scorecard → audit_log'a RISK_SCORECARD kaydı düşer
  DECLARE
    v_ov NUMBER; v_cr NUMBER; v_li NUMBER; v_ma NUMBER; v_op NUMBER;
    v_bd VARCHAR2(20); v_cur SYS_REFCURSOR;
  BEGIN
    v_marker := SYSTIMESTAMP;
    make_active_loan(1000, 100000, 10000);
    pkg_advanced_risk_engine.generate_risk_scorecard(
        NULL, SYSDATE, v_ov, v_cr, v_li, v_ma, v_op, v_bd, v_cur
    );
    IF v_cur%ISOPEN THEN CLOSE v_cur; END IF;
    SELECT COUNT(*) INTO v_count
    FROM   audit_log
    WHERE  new_values LIKE '%RISK_SCORECARD%'
      AND  changed_at >= v_marker;
    ROLLBACK;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_scorecard_audit|OK|count:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_scorecard_audit|FAIL|expected:>=1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_scorecard_audit|FAIL|' || SQLERRM);
  END;

  -- tc_07: Audit kayıtları AUTONOMOUS_TRANSACTION ile yazılır →
  -- ROLLBACK sonrasında bile audit log'da kalır
  DECLARE
    v_rs NUMBER; v_rb VARCHAR2(20); v_pd NUMBER; v_lgd NUMBER;
    v_ead NUMBER; v_el NUMBER; v_rec VARCHAR2(500); v_cur SYS_REFCURSOR;
    v_before_count NUMBER;
  BEGIN
    v_marker := SYSTIMESTAMP;
    SELECT COUNT(*) INTO v_before_count FROM audit_log WHERE changed_at >= v_marker;
    make_active_loan(1000, 100000, 10000);
    pkg_advanced_risk_engine.perform_credit_risk_assessment(
        1000, NULL, SYSDATE, v_rs, v_rb, v_pd, v_lgd, v_ead, v_el, v_rec, v_cur
    );
    IF v_cur%ISOPEN THEN CLOSE v_cur; END IF;
    ROLLBACK;
    SELECT COUNT(*) INTO v_count
    FROM   audit_log
    WHERE  new_values LIKE '%CREDIT_ASSESSMENT%'
      AND  changed_at >= v_marker;
    IF v_count > v_before_count THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_audit_survives_rollback|OK|before:' ||
        v_before_count || ' after:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_audit_survives_rollback|FAIL|before:' ||
        v_before_count || ' after:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_audit_survives_rollback|FAIL|' || SQLERRM);
  END;

END;
/
