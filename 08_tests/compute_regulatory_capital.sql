DECLARE
  v_tier1         NUMBER;
  v_tier2         NUMBER;
  v_rwa           NUMBER;
  v_car           NUMBER;
  v_t1_ratio      NUMBER;
  v_compliant     VARCHAR2(1);
  v_shortfall     NUMBER;
  v_cursor        SYS_REFCURSOR;
  v_loan_id       NUMBER;
  v_loan_number   VARCHAR2(50);
  v_monthly_pay   NUMBER;
  v_decision      VARCHAR2(20);
  v_count         NUMBER;
  v_dummy_num     NUMBER;
  v_dummy_str     VARCHAR2(200);

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
    make_active_loan(1000, 100000, 15000);
    pkg_advanced_risk_engine.compute_regulatory_capital(
        NULL, SYSDATE,
        v_tier1, v_tier2, v_rwa, v_car, v_t1_ratio,
        v_compliant, v_shortfall, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    IF v_tier1 IS NOT NULL AND v_car IS NOT NULL AND v_compliant IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_all_out_params|OK|car:' || ROUND(v_car*100,4)||'%');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_all_out_params|FAIL|null_output');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_all_out_params|FAIL|' || SQLERRM);
  END;

  -- tc_02: Tier1 ve Tier2 >= 0
  BEGIN
    make_active_loan(1000, 100000, 10000);
    pkg_advanced_risk_engine.compute_regulatory_capital(
        NULL, SYSDATE,
        v_tier1, v_tier2, v_rwa, v_car, v_t1_ratio,
        v_compliant, v_shortfall, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    IF v_tier1 >= 0 AND v_tier2 >= 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_tier_capital_non_negative|OK|t1:' || v_tier1 || ' t2:' || v_tier2);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_tier_capital_non_negative|FAIL|t1:' || v_tier1 || ' t2:' || v_tier2);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_tier_capital_non_negative|FAIL|' || SQLERRM);
  END;

  -- tc_03: Total RWA > 0 (aktif portföy varken)
  BEGIN
    make_active_loan(1000, 100000, 20000, 'PERSONAL');
    make_active_loan(1001, 100002, 30000, 'MORTGAGE');
    pkg_advanced_risk_engine.compute_regulatory_capital(
        NULL, SYSDATE,
        v_tier1, v_tier2, v_rwa, v_car, v_t1_ratio,
        v_compliant, v_shortfall, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    IF v_rwa > 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_rwa_positive|OK|rwa:' || ROUND(v_rwa,2));
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_rwa_positive|FAIL|rwa:' || v_rwa);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_rwa_positive|FAIL|' || SQLERRM);
  END;

  -- tc_04: CAR > 0
  BEGIN
    make_active_loan(1000, 100000, 10000);
    pkg_advanced_risk_engine.compute_regulatory_capital(
        NULL, SYSDATE,
        v_tier1, v_tier2, v_rwa, v_car, v_t1_ratio,
        v_compliant, v_shortfall, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    IF v_car > 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_car_positive|OK|car:' || ROUND(v_car*100,4)||'%');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_car_positive|FAIL|car:' || v_car);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_car_positive|FAIL|' || SQLERRM);
  END;

  -- tc_05: is_compliant Y veya N değeri alır
  BEGIN
    make_active_loan(1000, 100000, 10000);
    pkg_advanced_risk_engine.compute_regulatory_capital(
        NULL, SYSDATE,
        v_tier1, v_tier2, v_rwa, v_car, v_t1_ratio,
        v_compliant, v_shortfall, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    IF v_compliant IN ('Y','N') THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_compliant_yn|OK|compliant:' || v_compliant);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_compliant_yn|FAIL|invalid:' || v_compliant);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_compliant_yn|FAIL|' || SQLERRM);
  END;

  -- tc_06: shortfall >= 0 (negatif olamaz)
  BEGIN
    make_active_loan(1000, 100000, 10000);
    pkg_advanced_risk_engine.compute_regulatory_capital(
        NULL, SYSDATE,
        v_tier1, v_tier2, v_rwa, v_car, v_t1_ratio,
        v_compliant, v_shortfall, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    IF v_shortfall >= 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_shortfall_non_negative|OK|shortfall:' || v_shortfall);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_shortfall_non_negative|FAIL|negative:' || v_shortfall);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_shortfall_non_negative|FAIL|' || SQLERRM);
  END;

  -- tc_07: Mortgage RWA < PERSONAL RWA (daha düşük risk ağırlığı)
  -- Aynı tutar, farklı loan type → mortgage'ın RWA katkısı daha düşük
  DECLARE
    v_rwa_personal NUMBER;
    v_rwa_mortgage NUMBER;
    v_tier1_p NUMBER; v_tier2_p NUMBER; v_car_p NUMBER; v_t1_p NUMBER;
    v_comp_p VARCHAR2(1); v_sfall_p NUMBER; v_cur_p SYS_REFCURSOR;
    v_tier1_m NUMBER; v_tier2_m NUMBER; v_car_m NUMBER; v_t1_m NUMBER;
    v_comp_m VARCHAR2(1); v_sfall_m NUMBER; v_cur_m SYS_REFCURSOR;
  BEGIN
    UPDATE loans SET status = 'PAID_OFF' WHERE status = 'ACTIVE';
    make_active_loan(1000, 100000, 50000, 'PERSONAL');
    pkg_advanced_risk_engine.compute_regulatory_capital(
        NULL, SYSDATE, v_tier1_p, v_tier2_p, v_rwa_personal,
        v_car_p, v_t1_p, v_comp_p, v_sfall_p, v_cur_p
    );
    IF v_cur_p%ISOPEN THEN CLOSE v_cur_p; END IF;
    ROLLBACK;

    UPDATE loans SET status = 'PAID_OFF' WHERE status = 'ACTIVE';
    make_active_loan(1000, 100000, 50000, 'MORTGAGE');
    UPDATE loans SET collateral_type = 'REAL_ESTATE', collateral_value = 70000
    WHERE loan_id = v_loan_id;
    pkg_advanced_risk_engine.compute_regulatory_capital(
        NULL, SYSDATE, v_tier1_m, v_tier2_m, v_rwa_mortgage,
        v_car_m, v_t1_m, v_comp_m, v_sfall_m, v_cur_m
    );
    IF v_cur_m%ISOPEN THEN CLOSE v_cur_m; END IF;
    ROLLBACK;

    IF v_rwa_personal >= v_rwa_mortgage THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_mortgage_lower_rwa|OK|personal:' ||
        ROUND(v_rwa_personal,2) || ' mortgage:' || ROUND(v_rwa_mortgage,2));
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_mortgage_lower_rwa|FAIL|personal:' ||
        ROUND(v_rwa_personal,2) || ' mortgage:' || ROUND(v_rwa_mortgage,2));
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_mortgage_lower_rwa|FAIL|' || SQLERRM);
  END;

  -- tc_08: detail_cursor satır döndürür
  BEGIN
    make_active_loan(1000, 100000, 10000, 'PERSONAL');
    make_active_loan(1001, 100002, 30000, 'MORTGAGE');
    pkg_advanced_risk_engine.compute_regulatory_capital(
        NULL, SYSDATE,
        v_tier1, v_tier2, v_rwa, v_car, v_t1_ratio,
        v_compliant, v_shortfall, v_cursor
    );
    v_count := 0;
    LOOP
      FETCH v_cursor INTO v_dummy_str, v_dummy_str, v_dummy_str,
            v_dummy_num, v_dummy_num, v_dummy_num, v_dummy_num,
            v_dummy_num, v_dummy_num;
      EXIT WHEN v_cursor%NOTFOUND;
      v_count := v_count + 1;
    END LOOP;
    CLOSE v_cursor;
    ROLLBACK;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_cursor_has_rows|OK|rows:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_cursor_has_rows|FAIL|no_rows');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_cursor_has_rows|FAIL|' || SQLERRM);
  END;

  -- tc_09: branch_id filtresiyle çalışır
  BEGIN
    make_active_loan(1000, 100000, 10000);
    pkg_advanced_risk_engine.compute_regulatory_capital(
        10, SYSDATE,
        v_tier1, v_tier2, v_rwa, v_car, v_t1_ratio,
        v_compliant, v_shortfall, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    IF v_car IS NOT NULL AND v_car >= 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_branch_filter|OK|car:' || ROUND(v_car*100,4)||'%');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_branch_filter|FAIL|car:' || v_car);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_branch_filter|FAIL|' || SQLERRM);
  END;

  -- tc_10: Audit log oluşur
  DECLARE
    v_marker TIMESTAMP := SYSTIMESTAMP;
  BEGIN
    make_active_loan(1000, 100000, 10000);
    pkg_advanced_risk_engine.compute_regulatory_capital(
        NULL, SYSDATE,
        v_tier1, v_tier2, v_rwa, v_car, v_t1_ratio,
        v_compliant, v_shortfall, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    SELECT COUNT(*) INTO v_count
    FROM   audit_log
    WHERE  new_values LIKE 'RISK_ENGINE|EVENT=REGULATORY_CAPITAL%'
      AND  changed_at >= v_marker;
    ROLLBACK;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_audit_log|OK|count:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_audit_log|FAIL|expected:>=1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_audit_log|FAIL|' || SQLERRM);
  END;

END;
/
