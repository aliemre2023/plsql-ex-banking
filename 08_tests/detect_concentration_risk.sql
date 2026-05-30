-- Seed: 1000=Alice(100000/branch10), 1001=Bob(100002/branch10), 1002=Carol(100003/branch11), 1003=David(100004/branch11), 1004=Eve(100005/branch10)
DECLARE
  v_hhi_type    NUMBER;
  v_hhi_geo     NUMBER;
  v_hhi_cust    NUMBER;
  v_top5_pct    NUMBER;
  v_alert_lvl   VARCHAR2(20);
  v_cursor      SYS_REFCURSOR;
  v_count       NUMBER;
  v_loan_id     NUMBER;
  v_loan_number VARCHAR2(50);
  v_monthly_pay NUMBER;
  v_decision    VARCHAR2(20);
  v_dummy_num   NUMBER;
  v_dummy_str   VARCHAR2(200);

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

  -- tc_01: Tüm OUT parametreler dolu döner
  BEGIN
    make_active_loan(1000, 100000, 10, 10000, 'PERSONAL');
    pkg_advanced_risk_engine.detect_concentration_risk(
        SYSDATE, NULL,
        v_hhi_type, v_hhi_geo, v_hhi_cust, v_top5_pct, v_alert_lvl, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    IF v_hhi_type IS NOT NULL AND v_hhi_geo IS NOT NULL AND
       v_hhi_cust IS NOT NULL AND v_alert_lvl IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_all_out_params|OK|alert:' || v_alert_lvl);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_all_out_params|FAIL|null_output');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_all_out_params|FAIL|' || SQLERRM);
  END;

  -- tc_02: HHI loan type 0-1 aralığında
  BEGIN
    make_active_loan(1000, 100000, 10, 10000, 'PERSONAL');
    make_active_loan(1001, 100002, 10, 20000, 'MORTGAGE');
    pkg_advanced_risk_engine.detect_concentration_risk(
        SYSDATE, NULL,
        v_hhi_type, v_hhi_geo, v_hhi_cust, v_top5_pct, v_alert_lvl, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    IF v_hhi_type >= 0 AND v_hhi_type <= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_hhi_type_range|OK|hhi_type:' || v_hhi_type);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_hhi_type_range|FAIL|out_of_range:' || v_hhi_type);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_hhi_type_range|FAIL|' || SQLERRM);
  END;

  -- tc_03: top_exposure_pct 0-100 aralığında
  BEGIN
    make_active_loan(1000, 100000, 10, 10000);
    make_active_loan(1001, 100002, 10, 20000, 'AUTO');
    pkg_advanced_risk_engine.detect_concentration_risk(
        SYSDATE, NULL,
        v_hhi_type, v_hhi_geo, v_hhi_cust, v_top5_pct, v_alert_lvl, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    IF v_top5_pct >= 0 AND v_top5_pct <= 100 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_top5_pct_range|OK|top5:' || ROUND(v_top5_pct,4));
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_top5_pct_range|FAIL|out_of_range:' || v_top5_pct);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_top5_pct_range|FAIL|' || SQLERRM);
  END;

  -- tc_04: alert_level geçerli değer alır
  BEGIN
    make_active_loan(1000, 100000, 10, 10000);
    pkg_advanced_risk_engine.detect_concentration_risk(
        SYSDATE, NULL,
        v_hhi_type, v_hhi_geo, v_hhi_cust, v_top5_pct, v_alert_lvl, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    IF v_alert_lvl IN ('LOW','MEDIUM','HIGH','CRITICAL','NO_DATA') THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_alert_level_valid|OK|level:' || v_alert_lvl);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_alert_level_valid|FAIL|invalid:' || v_alert_lvl);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_alert_level_valid|FAIL|' || SQLERRM);
  END;

  -- tc_05: Tek loan type → hhi_type = 1 (tam konsantrasyon)
  BEGIN
    UPDATE loans SET status = 'PAID_OFF' WHERE status = 'ACTIVE';
    make_active_loan(1000, 100000, 10, 30000, 'PERSONAL');
    make_active_loan(1001, 100002, 10, 20000, 'PERSONAL');
    make_active_loan(1002, 100003, 11, 10000, 'PERSONAL');
    pkg_advanced_risk_engine.detect_concentration_risk(
        SYSDATE, NULL,
        v_hhi_type, v_hhi_geo, v_hhi_cust, v_top5_pct, v_alert_lvl, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    IF v_hhi_type = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_single_type_hhi_1|OK|hhi_type:' || v_hhi_type);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_single_type_hhi_1|FAIL|expected:1 got:' || v_hhi_type);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_single_type_hhi_1|FAIL|' || SQLERRM);
  END;

  -- tc_06: Çeşitlendirilmiş loan type portföyü → hhi_type düşük (<0.4) olmalı
  -- (Seed'de customer state NULL → coğrafya her zaman 'UNKNOWN' → hhi_geo=1, bu normal)
  BEGIN
    UPDATE loans SET status = 'PAID_OFF' WHERE status = 'ACTIVE';
    make_active_loan(1000, 100000, 10, 20000, 'PERSONAL');
    make_active_loan(1000, 100000, 10, 20000, 'MORTGAGE');
    make_active_loan(1001, 100002, 10, 20000, 'AUTO');
    make_active_loan(1001, 100002, 10, 20000, 'BUSINESS');
    make_active_loan(1002, 100003, 11, 20000, 'STUDENT');
    pkg_advanced_risk_engine.detect_concentration_risk(
        SYSDATE, NULL,
        v_hhi_type, v_hhi_geo, v_hhi_cust, v_top5_pct, v_alert_lvl, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    -- 5 loan tipine eşit dağılım → hhi_type = 5*(0.2^2) = 0.2
    IF v_hhi_type < 0.4 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_diversified_loan_type_low_hhi|OK|hhi_type:' || v_hhi_type);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_diversified_loan_type_low_hhi|FAIL|hhi_too_high:' || v_hhi_type);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_diversified_loan_type_low_hhi|FAIL|' || SQLERRM);
  END;

  -- tc_07: Aktif loan yoksa → NO_DATA döner
  BEGIN
    UPDATE loans SET status = 'PAID_OFF' WHERE status = 'ACTIVE';
    pkg_advanced_risk_engine.detect_concentration_risk(
        SYSDATE, NULL,
        v_hhi_type, v_hhi_geo, v_hhi_cust, v_top5_pct, v_alert_lvl, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    IF v_alert_lvl = 'NO_DATA' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_no_data_flag|OK|level:NO_DATA');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_no_data_flag|FAIL|expected:NO_DATA got:' || v_alert_lvl);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_no_data_flag|FAIL|' || SQLERRM);
  END;

  -- tc_08: detail_cursor satır döndürür
  BEGIN
    make_active_loan(1000, 100000, 10, 10000);
    make_active_loan(1001, 100002, 10, 20000, 'AUTO');
    pkg_advanced_risk_engine.detect_concentration_risk(
        SYSDATE, NULL,
        v_hhi_type, v_hhi_geo, v_hhi_cust, v_top5_pct, v_alert_lvl, v_cursor
    );
    v_count := 0;
    LOOP
      FETCH v_cursor INTO v_dummy_str, v_dummy_str, v_dummy_num,
            v_dummy_num, v_dummy_num, v_dummy_num, v_dummy_num, v_dummy_str;
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
    make_active_loan(1000, 100000, 10, 10000);
    pkg_advanced_risk_engine.detect_concentration_risk(
        SYSDATE, 10,
        v_hhi_type, v_hhi_geo, v_hhi_cust, v_top5_pct, v_alert_lvl, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    IF v_alert_lvl IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_branch_filter|OK|level:' || v_alert_lvl);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_branch_filter|FAIL|null_result');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_branch_filter|FAIL|' || SQLERRM);
  END;

END;
/
