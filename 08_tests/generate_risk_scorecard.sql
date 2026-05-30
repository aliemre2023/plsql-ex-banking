DECLARE
  v_overall       NUMBER;
  v_credit        NUMBER;
  v_liquidity     NUMBER;
  v_market        NUMBER;
  v_operational   NUMBER;
  v_band          VARCHAR2(20);
  v_cursor        SYS_REFCURSOR;
  v_count         NUMBER;
  v_loan_id       NUMBER;
  v_loan_number   VARCHAR2(50);
  v_monthly_pay   NUMBER;
  v_decision      VARCHAR2(20);
  v_dim           VARCHAR2(50);
  v_score         NUMBER;
  v_weight        NUMBER;
  v_wscore        NUMBER;
  v_band_col      VARCHAR2(20);
  v_metrics       VARCHAR2(500);

  PROCEDURE make_active_loan(
    p_customer_id IN NUMBER,
    p_account_id  IN NUMBER,
    p_amount      IN NUMBER,
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

  -- tc_01: Tüm OUT parametreler dolu döner
  BEGIN
    make_active_loan(1000, 100000, 10000);
    pkg_advanced_risk_engine.generate_risk_scorecard(
        NULL, SYSDATE,
        v_overall, v_credit, v_liquidity, v_market, v_operational, v_band, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    IF v_overall IS NOT NULL AND v_credit IS NOT NULL AND
       v_liquidity IS NOT NULL AND v_band IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_all_out_params|OK|overall:' || v_overall || ' band:' || v_band);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_all_out_params|FAIL|null_output');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_all_out_params|FAIL|' || SQLERRM);
  END;

  -- tc_02: overall_score 0-100 aralığında
  BEGIN
    make_active_loan(1000, 100000, 10000);
    pkg_advanced_risk_engine.generate_risk_scorecard(
        NULL, SYSDATE,
        v_overall, v_credit, v_liquidity, v_market, v_operational, v_band, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    IF v_overall >= 0 AND v_overall <= 100 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_overall_score_range|OK|score:' || v_overall);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_overall_score_range|FAIL|out_of_range:' || v_overall);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_overall_score_range|FAIL|' || SQLERRM);
  END;

  -- tc_03: Her alt skor 0-100 aralığında
  BEGIN
    make_active_loan(1000, 100000, 10000);
    pkg_advanced_risk_engine.generate_risk_scorecard(
        NULL, SYSDATE,
        v_overall, v_credit, v_liquidity, v_market, v_operational, v_band, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    IF v_credit    BETWEEN 0 AND 100
    AND v_liquidity BETWEEN 0 AND 100
    AND v_market    BETWEEN 0 AND 100
    AND v_operational BETWEEN 0 AND 100 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_all_subscore_ranges|OK|cr:' ||
        v_credit || ' liq:' || v_liquidity || ' mkt:' || v_market || ' op:' || v_operational);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_all_subscore_ranges|FAIL|cr:' ||
        v_credit || ' liq:' || v_liquidity || ' mkt:' || v_market || ' op:' || v_operational);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_all_subscore_ranges|FAIL|' || SQLERRM);
  END;

  -- tc_04: composite_band geçerli değer
  BEGIN
    make_active_loan(1000, 100000, 10000);
    pkg_advanced_risk_engine.generate_risk_scorecard(
        NULL, SYSDATE,
        v_overall, v_credit, v_liquidity, v_market, v_operational, v_band, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    IF v_band IN ('AAA','AA','A','BBB','BB','B','CCC','D','UNRATED') THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_valid_band|OK|band:' || v_band);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_valid_band|FAIL|invalid:' || v_band);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_valid_band|FAIL|' || SQLERRM);
  END;

  -- tc_05: Cursor tam olarak 5 satır döndürür (4 boyut + composite)
  BEGIN
    make_active_loan(1000, 100000, 10000);
    pkg_advanced_risk_engine.generate_risk_scorecard(
        NULL, SYSDATE,
        v_overall, v_credit, v_liquidity, v_market, v_operational, v_band, v_cursor
    );
    v_count := 0;
    LOOP
      FETCH v_cursor INTO v_dim, v_score, v_weight, v_wscore, v_band_col, v_metrics;
      EXIT WHEN v_cursor%NOTFOUND;
      v_count := v_count + 1;
    END LOOP;
    CLOSE v_cursor;
    ROLLBACK;
    IF v_count = 5 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_cursor_5_rows|OK|rows:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_cursor_5_rows|FAIL|expected:5 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_cursor_5_rows|FAIL|' || SQLERRM);
  END;

  -- tc_06: overall_score, ağırlıklı alt skorların toplamına yakın
  -- overall ≈ credit*0.40 + liquidity*0.25 + market*0.20 + operational*0.15
  BEGIN
    make_active_loan(1000, 100000, 10000);
    pkg_advanced_risk_engine.generate_risk_scorecard(
        NULL, SYSDATE,
        v_overall, v_credit, v_liquidity, v_market, v_operational, v_band, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    DECLARE
      v_expected NUMBER := ROUND(v_credit*0.40 + v_liquidity*0.25 + v_market*0.20 + v_operational*0.15, 2);
    BEGIN
      IF ABS(v_overall - v_expected) <= 0.02 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_weighted_sum_formula|OK|overall:' || v_overall || ' expected:' || v_expected);
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_weighted_sum_formula|FAIL|overall:' || v_overall || ' expected:' || v_expected);
      END IF;
    END;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_weighted_sum_formula|FAIL|' || SQLERRM);
  END;

  -- tc_07: branch_id filtresiyle çalışır
  BEGIN
    make_active_loan(1000, 100000, 10000);
    pkg_advanced_risk_engine.generate_risk_scorecard(
        10, SYSDATE,
        v_overall, v_credit, v_liquidity, v_market, v_operational, v_band, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    IF v_overall IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_branch_filter|OK|score:' || v_overall);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_branch_filter|FAIL|null_score');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_branch_filter|FAIL|' || SQLERRM);
  END;

  -- tc_08: Kötü portföy → skor yükselir (daha riskli)
  DECLARE
    v_good_score NUMBER;
    v_bad_score  NUMBER;
    v_dummy_cur  SYS_REFCURSOR;
    v_v2 NUMBER; v_v3 NUMBER; v_v4 NUMBER; v_v5 NUMBER; v_v6 VARCHAR2(20);
  BEGIN
    -- İyi portföy: iyi kredi skoru, düşük DPD
    UPDATE customers SET credit_score = 800, risk_level = 'LOW'
    WHERE customer_id IN (1000, 1001, 1002);
    make_active_loan(1000, 100000, 10000, 'PERSONAL');
    make_active_loan(1001, 100002, 15000, 'MORTGAGE');
    pkg_advanced_risk_engine.generate_risk_scorecard(
        NULL, SYSDATE, v_good_score, v_v2, v_v3, v_v4, v_v5, v_v6, v_dummy_cur
    );
    IF v_dummy_cur%ISOPEN THEN CLOSE v_dummy_cur; END IF;
    ROLLBACK;

    -- Kötü portföy: düşük kredi skoru, yüksek DPD
    UPDATE customers SET credit_score = 400, risk_level = 'HIGH'
    WHERE customer_id IN (1000, 1001, 1002);
    make_active_loan(1000, 100000, 10000, 'PERSONAL');
    make_active_loan(1001, 100002, 15000, 'PERSONAL');
    UPDATE loans SET days_past_due = 120, times_90_dpd = 3 WHERE status = 'ACTIVE';
    pkg_advanced_risk_engine.generate_risk_scorecard(
        NULL, SYSDATE, v_bad_score, v_v2, v_v3, v_v4, v_v5, v_v6, v_dummy_cur
    );
    IF v_dummy_cur%ISOPEN THEN CLOSE v_dummy_cur; END IF;
    ROLLBACK;

    IF v_bad_score >= v_good_score THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_bad_portfolio_higher_score|OK|good:' ||
        v_good_score || ' bad:' || v_bad_score);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_bad_portfolio_higher_score|FAIL|good:' ||
        v_good_score || ' bad:' || v_bad_score);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_bad_portfolio_higher_score|FAIL|' || SQLERRM);
  END;

  -- tc_09: Audit log oluşur
  DECLARE
    v_marker TIMESTAMP := SYSTIMESTAMP;
  BEGIN
    make_active_loan(1000, 100000, 10000);
    pkg_advanced_risk_engine.generate_risk_scorecard(
        NULL, SYSDATE,
        v_overall, v_credit, v_liquidity, v_market, v_operational, v_band, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    SELECT COUNT(*) INTO v_count
    FROM   audit_log
    WHERE  new_values LIKE 'RISK_ENGINE|EVENT=RISK_SCORECARD%'
      AND  changed_at >= v_marker;
    ROLLBACK;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_audit_log|OK|count:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_audit_log|FAIL|expected:>=1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_audit_log|FAIL|' || SQLERRM);
  END;

END;
/
