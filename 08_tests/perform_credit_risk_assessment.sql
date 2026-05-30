DECLARE
  v_risk_score     NUMBER;
  v_risk_band      VARCHAR2(20);
  v_pd             NUMBER;
  v_lgd            NUMBER;
  v_ead            NUMBER;
  v_el             NUMBER;
  v_recommendation VARCHAR2(500);
  v_cursor         SYS_REFCURSOR;
  v_loan_id        NUMBER;
  v_loan_number    VARCHAR2(50);
  v_monthly_pay    NUMBER;
  v_decision       VARCHAR2(20);
  v_count          NUMBER;
  v_pending_score  NUMBER;
  v_rec_loan_id    NUMBER;
  v_rec_loan_type  VARCHAR2(30);
  v_dummy_num      NUMBER;
  v_dummy_str      VARCHAR2(200);

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

  -- tc_01: Geçerli müşteri için tüm OUT parametreler dolu gelir
  BEGIN
    make_active_loan(1000, 100000, 10000, 'PERSONAL');
    pkg_advanced_risk_engine.perform_credit_risk_assessment(
        p_customer_id    => 1000,
        p_loan_id        => NULL,
        p_as_of_date     => SYSDATE,
        p_risk_score     => v_risk_score,
        p_risk_band      => v_risk_band,
        p_pd             => v_pd,
        p_lgd            => v_lgd,
        p_ead            => v_ead,
        p_expected_loss  => v_el,
        p_recommendation => v_recommendation,
        p_detail_cursor  => v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    IF v_risk_score IS NOT NULL AND v_risk_band IS NOT NULL AND
       v_pd IS NOT NULL AND v_recommendation IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_all_out_params_populated|OK|score:' ||
        v_risk_score || ' band:' || v_risk_band);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_all_out_params_populated|FAIL|null_output_params');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_all_out_params_populated|FAIL|' || SQLERRM);
  END;

  -- tc_02: risk_score 0-100 aralığında
  BEGIN
    make_active_loan(1000, 100000, 10000);
    pkg_advanced_risk_engine.perform_credit_risk_assessment(
        1000, NULL, SYSDATE,
        v_risk_score, v_risk_band, v_pd, v_lgd, v_ead, v_el, v_recommendation, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    IF v_risk_score >= 0 AND v_risk_score <= 100 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_score_0_100_range|OK|score:' || v_risk_score);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_score_0_100_range|FAIL|out_of_range:' || v_risk_score);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_score_0_100_range|FAIL|' || SQLERRM);
  END;

  -- tc_03: risk_band geçerli değerlerden biri
  BEGIN
    make_active_loan(1000, 100000, 10000);
    pkg_advanced_risk_engine.perform_credit_risk_assessment(
        1000, NULL, SYSDATE,
        v_risk_score, v_risk_band, v_pd, v_lgd, v_ead, v_el, v_recommendation, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    IF v_risk_band IN ('AAA','AA','A','BBB','BB','B','CCC','D','UNRATED') THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_risk_band_valid|OK|band:' || v_risk_band);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_risk_band_valid|FAIL|invalid_band:' || v_risk_band);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_risk_band_valid|FAIL|' || SQLERRM);
  END;

  -- tc_04: PD [0.0003, 0.99] aralığında
  BEGIN
    make_active_loan(1000, 100000, 10000);
    pkg_advanced_risk_engine.perform_credit_risk_assessment(
        1000, NULL, SYSDATE,
        v_risk_score, v_risk_band, v_pd, v_lgd, v_ead, v_el, v_recommendation, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    IF v_pd >= 0.0003 AND v_pd <= 0.99 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_pd_in_valid_range|OK|pd:' || v_pd);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_pd_in_valid_range|FAIL|pd_out_of_range:' || v_pd);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_pd_in_valid_range|FAIL|' || SQLERRM);
  END;

  -- tc_05: expected_loss >= 0
  BEGIN
    make_active_loan(1000, 100000, 10000);
    pkg_advanced_risk_engine.perform_credit_risk_assessment(
        1000, NULL, SYSDATE,
        v_risk_score, v_risk_band, v_pd, v_lgd, v_ead, v_el, v_recommendation, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    IF v_el >= 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_el_non_negative|OK|el:' || v_el);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_el_non_negative|FAIL|negative_el:' || v_el);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_el_non_negative|FAIL|' || SQLERRM);
  END;

  -- tc_06: detail_cursor açık döner ve en az bir satır var
  BEGIN
    make_active_loan(1000, 100000, 10000);
    pkg_advanced_risk_engine.perform_credit_risk_assessment(
        1000, NULL, SYSDATE,
        v_risk_score, v_risk_band, v_pd, v_lgd, v_ead, v_el, v_recommendation, v_cursor
    );
    v_count := 0;
    LOOP
      FETCH v_cursor INTO v_rec_loan_id, v_dummy_str, v_rec_loan_type,
            v_dummy_num, v_dummy_num, v_dummy_str,
            v_dummy_num, v_dummy_num, v_dummy_num, v_dummy_num, v_dummy_num;
      EXIT WHEN v_cursor%NOTFOUND;
      v_count := v_count + 1;
    END LOOP;
    CLOSE v_cursor;
    ROLLBACK;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_cursor_has_rows|OK|rows:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_cursor_has_rows|FAIL|no_rows_returned');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_cursor_has_rows|FAIL|' || SQLERRM);
  END;

  -- tc_07: Var olmayan customer_id → -20201 exception
  BEGIN
    pkg_advanced_risk_engine.perform_credit_risk_assessment(
        999999, NULL, SYSDATE,
        v_risk_score, v_risk_band, v_pd, v_lgd, v_ead, v_el, v_recommendation, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_nonexistent_customer|FAIL|expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -20201 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_nonexistent_customer|OK|exception_raised:-20201');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_nonexistent_customer|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_08: İnaktif müşteri için risk_score = 100 (maksimum risk)
  BEGIN
    make_active_loan(1001, 100002, 5000);
    UPDATE customers SET is_active = 'N' WHERE customer_id = 1001;
    pkg_advanced_risk_engine.perform_credit_risk_assessment(
        1001, NULL, SYSDATE,
        v_risk_score, v_risk_band, v_pd, v_lgd, v_ead, v_el, v_recommendation, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;
    IF v_risk_score = 100 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_inactive_customer_max_score|OK|score:' || v_risk_score);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_inactive_customer_max_score|FAIL|expected:100 got:' || v_risk_score);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_inactive_customer_max_score|FAIL|' || SQLERRM);
  END;

  -- tc_09: KYC REJECTED → risk_score artar (penalty uygulanır)
  BEGIN
    make_active_loan(1000, 100000, 10000);
    UPDATE customers SET kyc_status = 'PENDING' WHERE customer_id = 1000;
    pkg_advanced_risk_engine.perform_credit_risk_assessment(
        1000, NULL, SYSDATE,
        v_risk_score, v_risk_band, v_pd, v_lgd, v_ead, v_el, v_recommendation, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    v_pending_score := v_risk_score;   -- PENDING KYC skorunu ayrı değişkende sakla
    -- kyc REJECTED yapıp aynı transaction'da tekrar ölç
    UPDATE customers SET kyc_status = 'REJECTED' WHERE customer_id = 1000;
    pkg_advanced_risk_engine.perform_credit_risk_assessment(
        1000, NULL, SYSDATE,
        v_risk_score, v_risk_band, v_pd, v_lgd, v_ead, v_el, v_recommendation, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    ROLLBACK;

    IF v_risk_score >= v_pending_score THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_rejected_kyc_higher_score|OK|pending:' ||
        v_pending_score || ' rejected:' || v_risk_score);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_rejected_kyc_higher_score|FAIL|pending:' ||
        v_pending_score || ' rejected:' || v_risk_score);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_rejected_kyc_higher_score|FAIL|' || SQLERRM);
  END;

  -- tc_10: loan_id filtresiyle çağrıldığında sadece o loan değerlenir
  BEGIN
    make_active_loan(1000, 100000, 5000, 'PERSONAL');
    DECLARE v_specific_loan_id NUMBER := v_loan_id; BEGIN
      make_active_loan(1000, 100000, 50000, 'MORTGAGE');
      pkg_advanced_risk_engine.perform_credit_risk_assessment(
          1000, v_specific_loan_id, SYSDATE,
          v_risk_score, v_risk_band, v_pd, v_lgd, v_ead, v_el, v_recommendation, v_cursor
      );
      IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
      ROLLBACK;
      IF v_ead <= 5500 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_loan_id_filter|OK|ead:' || v_ead);
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_loan_id_filter|FAIL|ead_too_large:' || v_ead);
      END IF;
    END;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_loan_id_filter|FAIL|' || SQLERRM);
  END;

  -- tc_11: Audit log kaydı oluşur (AUTONOMOUS)
  DECLARE
    v_marker TIMESTAMP := SYSTIMESTAMP;
  BEGIN
    make_active_loan(1000, 100000, 10000);
    pkg_advanced_risk_engine.perform_credit_risk_assessment(
        1000, NULL, SYSDATE,
        v_risk_score, v_risk_band, v_pd, v_lgd, v_ead, v_el, v_recommendation, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    SELECT COUNT(*) INTO v_count
    FROM   audit_log
    WHERE  table_name  = 'CUSTOMERS'
      AND  record_id   = 1000
      AND  new_values  LIKE 'RISK_ENGINE|EVENT=CREDIT_ASSESSMENT%'
      AND  changed_at >= v_marker;
    ROLLBACK;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_audit_log_created|OK|count:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_audit_log_created|FAIL|expected:>=1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_audit_log_created|FAIL|' || SQLERRM);
  END;

END;
/
