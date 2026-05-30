-- =============================================================================
-- TEST: run_portfolio_stress_test
-- Package: pkg_advanced_risk_engine
-- =============================================================================
-- Seed data (01_DDL_SCHEMA.sql):
--   customer_id 1000=Alice | account_id 100000=CHECKING | branch_id=10
--   customer_id 1001=Bob   | account_id 100002=CHECKING | branch_id=10
--   customer_id 1002=Carol | account_id 100003=SAVINGS  | branch_id=11
--   customer_id 1003=David | account_id 100004=CHECKING | branch_id=11
--   employee_id 2000=John Smith (MANAGER, branch 10)
-- =============================================================================

DECLARE
  v_loans_affected  NUMBER;
  v_pre_el          NUMBER;
  v_post_el_mild    NUMBER;
  v_post_el_mod     NUMBER;
  v_post_el_sev     NUMBER;
  v_cap_impact      NUMBER;
  v_breach_mild     NUMBER;
  v_breach_moderate NUMBER;
  v_breach_severe   NUMBER;
  v_cursor          SYS_REFCURSOR;
  v_loan_id         NUMBER;
  v_loan_number     VARCHAR2(50);
  v_monthly_pay     NUMBER;
  v_decision        VARCHAR2(20);
  v_count           NUMBER;
  v_dummy_num       NUMBER;
  v_dummy_str       VARCHAR2(200);

  PROCEDURE make_loan(
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

  PROCEDURE build_portfolio IS
  BEGIN
    make_loan(1000, 100000, 10, 15000, 'PERSONAL'); -- Alice, branch10
    make_loan(1001, 100002, 10, 25000, 'AUTO');     -- Bob,   branch10
    make_loan(1002, 100003, 11, 80000, 'MORTGAGE'); -- Carol, branch11
    make_loan(1002, 100003, 11, 20000, 'BUSINESS'); -- Carol, branch11
  END;

BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: MILD senaryo çalışır, loans_affected > 0
  BEGIN
    build_portfolio;
    pkg_advanced_risk_engine.run_portfolio_stress_test(
        'MILD', NULL, SYSDATE,
        v_loans_affected, v_pre_el, v_post_el_mild, v_cap_impact, v_breach_mild, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    IF v_loans_affected > 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_mild_loans_affected|OK|count:' || v_loans_affected);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_mild_loans_affected|FAIL|expected:>0 got:' || v_loans_affected);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_mild_loans_affected|FAIL|' || SQLERRM);
  END;

  -- tc_02: Post-stres EL >= pre-stres EL
  BEGIN
    build_portfolio;
    pkg_advanced_risk_engine.run_portfolio_stress_test(
        'MODERATE', NULL, SYSDATE,
        v_loans_affected, v_pre_el, v_post_el_mod, v_cap_impact, v_breach_moderate, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    IF v_post_el_mod >= v_pre_el THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_post_el_gte_pre_el|OK|pre:' || v_pre_el || ' post:' || v_post_el_mod);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_post_el_gte_pre_el|FAIL|pre:' || v_pre_el || ' post:' || v_post_el_mod);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_post_el_gte_pre_el|FAIL|' || SQLERRM);
  END;

  -- tc_03: SEVERE >= MODERATE >= MILD (EL sıralaması)
  BEGIN
    build_portfolio;
    pkg_advanced_risk_engine.run_portfolio_stress_test(
        'MILD', NULL, SYSDATE,
        v_loans_affected, v_pre_el, v_post_el_mild, v_cap_impact, v_breach_mild, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    pkg_advanced_risk_engine.run_portfolio_stress_test(
        'MODERATE', NULL, SYSDATE,
        v_loans_affected, v_pre_el, v_post_el_mod, v_cap_impact, v_breach_moderate, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    pkg_advanced_risk_engine.run_portfolio_stress_test(
        'SEVERE', NULL, SYSDATE,
        v_loans_affected, v_pre_el, v_post_el_sev, v_cap_impact, v_breach_severe, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    IF v_post_el_sev >= v_post_el_mod AND v_post_el_mod >= v_post_el_mild THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_severe_gte_moderate_gte_mild|OK|mild:' ||
        v_post_el_mild || ' mod:' || v_post_el_mod || ' sev:' || v_post_el_sev);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_severe_gte_moderate_gte_mild|FAIL|mild:' ||
        v_post_el_mild || ' mod:' || v_post_el_mod || ' sev:' || v_post_el_sev);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_severe_gte_moderate_gte_mild|FAIL|' || SQLERRM);
  END;

  -- tc_04: Geçersiz senaryo adı → -20202 exception
  BEGIN
    build_portfolio;
    pkg_advanced_risk_engine.run_portfolio_stress_test(
        'APOCALYPSE', NULL, SYSDATE,
        v_loans_affected, v_pre_el, v_post_el_mild, v_cap_impact, v_breach_mild, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_invalid_scenario|FAIL|expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20202 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_invalid_scenario|OK|exception_raised:-20202');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_invalid_scenario|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_05: breach_count >= 0 (negatif olamaz)
  BEGIN
    build_portfolio;
    pkg_advanced_risk_engine.run_portfolio_stress_test(
        'SEVERE', NULL, SYSDATE,
        v_loans_affected, v_pre_el, v_post_el_sev, v_cap_impact, v_breach_severe, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    IF v_breach_severe >= 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_breach_count_non_negative|OK|breaches:' || v_breach_severe);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_breach_count_non_negative|FAIL|negative:' || v_breach_severe);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_breach_count_non_negative|FAIL|' || SQLERRM);
  END;

  -- tc_06: capital_impact >= 0
  BEGIN
    build_portfolio;
    pkg_advanced_risk_engine.run_portfolio_stress_test(
        'MODERATE', NULL, SYSDATE,
        v_loans_affected, v_pre_el, v_post_el_mod, v_cap_impact, v_breach_moderate, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    IF v_cap_impact >= 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_capital_impact_non_negative|OK|impact:' || v_cap_impact);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_capital_impact_non_negative|FAIL|negative:' || v_cap_impact);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_capital_impact_non_negative|FAIL|' || SQLERRM);
  END;

  -- tc_07: results_cursor satır döndürür
  -- Cursor 14 kolon: NUMBER, VARCHAR2, VARCHAR2, VARCHAR2, VARCHAR2,
  --                  NUMBER, NUMBER, NUMBER, NUMBER, NUMBER, NUMBER, NUMBER, VARCHAR2, NUMBER
  BEGIN
    build_portfolio;
    pkg_advanced_risk_engine.run_portfolio_stress_test(
        'MILD', NULL, SYSDATE,
        v_loans_affected, v_pre_el, v_post_el_mild, v_cap_impact, v_breach_mild, v_cursor
    );
    v_count := 0;
    LOOP
      FETCH v_cursor INTO
            v_dummy_num,  -- 1  loan_id
            v_dummy_str,  -- 2  loan_number
            v_dummy_str,  -- 3  customer_code
            v_dummy_str,  -- 4  customer_name
            v_dummy_str,  -- 5  loan_type
            v_dummy_num,  -- 6  outstanding_balance
            v_dummy_num,  -- 7  days_past_due
            v_dummy_num,  -- 8  el_base
            v_dummy_num,  -- 9  el_stress
            v_dummy_num,  -- 10 el_delta
            v_dummy_num,  -- 11 stressed_pd_pct
            v_dummy_num,  -- 12 raroc_pct
            v_dummy_str,  -- 13 breach_flag
            v_dummy_num;  -- 14 risk_rank
      EXIT WHEN v_cursor%NOTFOUND;
      v_count := v_count + 1;
    END LOOP;
    CLOSE v_cursor;
    ROLLBACK;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_cursor_has_rows|OK|rows:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_cursor_has_rows|FAIL|no_rows');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_cursor_has_rows|FAIL|' || SQLERRM);
  END;

  -- tc_08: branch_id=10 filtresiyle çalışır (Alice+Bob loanları)
  BEGIN
    make_loan(1000, 100000, 10, 15000, 'PERSONAL');
    make_loan(1001, 100002, 10, 20000, 'AUTO');
    pkg_advanced_risk_engine.run_portfolio_stress_test(
        'MILD', 10, SYSDATE,
        v_loans_affected, v_pre_el, v_post_el_mild, v_cap_impact, v_breach_mild, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    IF v_loans_affected >= 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_branch_filter|OK|affected:' || v_loans_affected);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_branch_filter|FAIL|loans_affected:' || v_loans_affected);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_branch_filter|FAIL|' || SQLERRM);
  END;

  -- tc_09: Audit log oluşur (AUTONOMOUS_TRANSACTION)
  DECLARE
    v_marker TIMESTAMP := SYSTIMESTAMP;
  BEGIN
    build_portfolio;
    pkg_advanced_risk_engine.run_portfolio_stress_test(
        'SEVERE', NULL, SYSDATE,
        v_loans_affected, v_pre_el, v_post_el_sev, v_cap_impact, v_breach_severe, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    SELECT COUNT(*) INTO v_count
    FROM   audit_log
    WHERE  new_values LIKE 'RISK_ENGINE|EVENT=STRESS_TEST_SEVERE%'
      AND  changed_at >= v_marker;
    ROLLBACK;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_stress_audit_log|OK|count:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_stress_audit_log|FAIL|expected:>=1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_stress_audit_log|FAIL|' || SQLERRM);
  END;

END;
/
