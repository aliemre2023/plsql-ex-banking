DECLARE
  v_loan_id     NUMBER;
  v_loan_number VARCHAR2(50);
  v_monthly_pay NUMBER;
  v_decision    VARCHAR2(20);
  v_new_payment NUMBER;
  v_count       NUMBER;
  v_rate        NUMBER;
  v_term        NUMBER;
  v_balance     NUMBER;
  v_date        DATE;
  v_marker      TIMESTAMP;

  -- Helper: ACTIVE loan oluşturur
  PROCEDURE make_active_loan(
    p_customer_id IN NUMBER,
    p_account_id  IN NUMBER,
    p_amount      IN NUMBER DEFAULT 10000,
    p_term        IN NUMBER DEFAULT 12
  ) IS
  BEGIN
    pkg_loan_mgmt.originate_loan(
        p_customer_id => p_customer_id, p_account_id => p_account_id,
        p_branch_id => 10, p_loan_type => 'PERSONAL',
        p_amount => p_amount, p_term_months => p_term,
        p_employee_id => 2000,
        p_loan_id => v_loan_id, p_loan_number => v_loan_number,
        p_monthly_payment => v_monthly_pay, p_decision => v_decision
    );
    UPDATE loans SET status = 'PENDING' WHERE loan_id = v_loan_id;
    pkg_loan_mgmt.approve_and_disburse(v_loan_id, 2000, p_account_id);
  END;

BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: ACTIVE loan → interest_rate güncellenir
  BEGIN
    make_active_loan(1000, 100000, 10000, 12);
    pkg_loan_mgmt.restructure_loan(v_loan_id, 5.0, 24, 'Hardship', 2000, v_new_payment);
    SELECT interest_rate INTO v_rate FROM loans WHERE loan_id = v_loan_id;
    ROLLBACK;
    IF v_rate = 5.0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_rate_updated|OK|rate:' || v_rate);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_rate_updated|FAIL|expected:5.0 got:' || v_rate);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_rate_updated|FAIL|' || SQLERRM);
  END;

  -- tc_02: term_months güncellenir
  BEGIN
    make_active_loan(1000, 100000, 10000, 12);
    pkg_loan_mgmt.restructure_loan(v_loan_id, 5.0, 36, 'Extension', 2000, v_new_payment);
    SELECT term_months INTO v_term FROM loans WHERE loan_id = v_loan_id;
    ROLLBACK;
    IF v_term = 36 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_term_updated|OK|term:' || v_term);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_term_updated|FAIL|expected:36 got:' || v_term);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_term_updated|FAIL|' || SQLERRM);
  END;

  -- tc_03: monthly_payment = calc_monthly_payment(outstanding, new_rate, new_term)
  BEGIN
    make_active_loan(1000, 100000, 10000, 12);
    SELECT outstanding_balance INTO v_balance FROM loans WHERE loan_id = v_loan_id;
    pkg_loan_mgmt.restructure_loan(v_loan_id, 6.0, 24, 'Rate reduction', 2000, v_new_payment);
    ROLLBACK;
    IF v_new_payment = pkg_loan_mgmt.calc_monthly_payment(v_balance, 6.0, 24) THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_payment_recalculated|OK|payment:' || v_new_payment);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_payment_recalculated|FAIL|expected:' ||
        pkg_loan_mgmt.calc_monthly_payment(v_balance, 6.0, 24) || ' got:' || v_new_payment);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_payment_recalculated|FAIL|' || SQLERRM);
  END;

  -- tc_04: maturity_date = ADD_MONTHS(SYSDATE, new_term)
  BEGIN
    make_active_loan(1000, 100000, 10000, 12);
    pkg_loan_mgmt.restructure_loan(v_loan_id, 5.0, 24, 'Maturity check', 2000, v_new_payment);
    SELECT maturity_date INTO v_date FROM loans WHERE loan_id = v_loan_id;
    ROLLBACK;
    IF TRUNC(v_date) = TRUNC(ADD_MONTHS(SYSDATE, 24)) THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_maturity_date_updated|OK|maturity:' ||
        TO_CHAR(v_date,'YYYY-MM-DD'));
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_maturity_date_updated|FAIL|expected:' ||
        TO_CHAR(ADD_MONTHS(SYSDATE,24),'YYYY-MM-DD') || ' got:' || TO_CHAR(v_date,'YYYY-MM-DD'));
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_maturity_date_updated|FAIL|' || SQLERRM);
  END;

  -- tc_05: Yeni amortization schedule oluşur (new_term kadar SCHEDULED)
  BEGIN
    make_active_loan(1000, 100000, 10000, 12);
    pkg_loan_mgmt.restructure_loan(v_loan_id, 5.0, 24, 'Schedule regen', 2000, v_new_payment);
    SELECT COUNT(*) INTO v_count
    FROM   loan_payments
    WHERE  loan_id = v_loan_id AND status = 'SCHEDULED';
    ROLLBACK;
    IF v_count = 24 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_schedule_regenerated|OK|count:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_schedule_regenerated|FAIL|expected:24 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_schedule_regenerated|FAIL|' || SQLERRM);
  END;

  -- tc_06: Eski oran farklıysa yeni oran değişti
  BEGIN
    make_active_loan(1000, 100000, 10000, 12);
    SELECT interest_rate INTO v_rate FROM loans WHERE loan_id = v_loan_id;
    -- Farklı bir rate ver
    DECLARE v_new_rate NUMBER := v_rate - 1; BEGIN
      pkg_loan_mgmt.restructure_loan(v_loan_id, v_new_rate, 12, 'Rate cut', 2000, v_new_payment);
      SELECT interest_rate INTO v_rate FROM loans WHERE loan_id = v_loan_id;
      ROLLBACK;
      IF v_rate = v_new_rate THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_rate_changed|OK|new_rate:' || v_rate);
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_rate_changed|FAIL|expected:' ||
          v_new_rate || ' got:' || v_rate);
      END IF;
    END;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_rate_changed|FAIL|' || SQLERRM);
  END;

  -- tc_07: PAID_OFF loan → -20050 exception
  BEGIN
    pkg_loan_mgmt.restructure_loan(2, 5.0, 24, 'Paid off test', 2000, v_new_payment);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_paid_off_cannot_restructure|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20050 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_paid_off_cannot_restructure|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_paid_off_cannot_restructure|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_08: PENDING loan → -20050 exception
  BEGIN
    pkg_loan_mgmt.originate_loan(
        p_customer_id => 1003, p_account_id => 100004,
        p_branch_id => 10, p_loan_type => 'PERSONAL',
        p_amount => 3000, p_term_months => 12,
        p_employee_id => 2000,
        p_loan_id => v_loan_id, p_loan_number => v_loan_number,
        p_monthly_payment => v_monthly_pay, p_decision => v_decision
    );
    UPDATE loans SET status = 'PENDING' WHERE loan_id = v_loan_id;
    pkg_loan_mgmt.restructure_loan(v_loan_id, 5.0, 24, 'Pending test', 2000, v_new_payment);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_pending_cannot_restructure|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20050 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_pending_cannot_restructure|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_pending_cannot_restructure|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_09: Audit log oluşur, old_values rate+term içerir
  BEGIN
    v_marker := SYSTIMESTAMP;
    make_active_loan(1000, 100000, 10000, 12);
    SELECT interest_rate, term_months INTO v_rate, v_term
    FROM   loans WHERE loan_id = v_loan_id;
    pkg_loan_mgmt.restructure_loan(v_loan_id, 5.0, 24, 'Audit test', 2000, v_new_payment);
    SELECT COUNT(*) INTO v_count
    FROM   audit_log
    WHERE  table_name          = 'LOANS'
    AND    record_id           = v_loan_id
    AND    action              = 'UPDATE'
    AND    TO_CHAR(old_values) LIKE '%rate=' || v_rate || '%'
    AND    changed_at         >= v_marker;
    ROLLBACK;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_audit_old_values|OK|count:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_audit_old_values|FAIL|expected:>=1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_audit_old_values|FAIL|' || SQLERRM);
  END;

  -- tc_10: Audit new_values reason içerir
  BEGIN
    v_marker := SYSTIMESTAMP;
    make_active_loan(1000, 100000, 10000, 12);
    pkg_loan_mgmt.restructure_loan(v_loan_id, 5.0, 24, 'Bankruptcy plan', 2000, v_new_payment);
    SELECT COUNT(*) INTO v_count
    FROM   audit_log
    WHERE  table_name          = 'LOANS'
    AND    record_id           = v_loan_id
    AND    TO_CHAR(new_values) LIKE '%Bankruptcy plan%'
    AND    changed_at         >= v_marker;
    ROLLBACK;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_audit_reason|OK|reason_in_new_values');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_audit_reason|FAIL|expected:>=1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_audit_reason|FAIL|' || SQLERRM);
  END;

  -- tc_11: Daha düşük rate → daha düşük aylık ödeme
  BEGIN
    make_active_loan(1000, 100000, 10000, 12);
    SELECT outstanding_balance INTO v_balance FROM loans WHERE loan_id = v_loan_id;
    SELECT interest_rate INTO v_rate FROM loans WHERE loan_id = v_loan_id;
    DECLARE
      v_high_pay NUMBER;
      v_low_pay  NUMBER;
    BEGIN
      pkg_loan_mgmt.restructure_loan(v_loan_id, v_rate + 3, 12, 'High rate', 2000, v_high_pay);
      ROLLBACK;
      make_active_loan(1000, 100000, 10000, 12);
      pkg_loan_mgmt.restructure_loan(v_loan_id, v_rate - 2, 12, 'Low rate', 2000, v_low_pay);
      ROLLBACK;
      IF v_low_pay < v_high_pay THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_lower_rate_lower_payment|OK|low:' ||
          v_low_pay || ' high:' || v_high_pay);
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_lower_rate_lower_payment|FAIL|low:' ||
          v_low_pay || ' high:' || v_high_pay);
      END IF;
    END;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_lower_rate_lower_payment|FAIL|' || SQLERRM);
  END;

  -- tc_12: Var olmayan loan_id → NO_DATA_FOUND
  BEGIN
    pkg_loan_mgmt.restructure_loan(999999, 5.0, 24, 'Ghost', 2000, v_new_payment);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_nonexistent_loan|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_nonexistent_loan|OK|no_data_found');
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_nonexistent_loan|FAIL|wrong_exception:' || SQLCODE);
  END;

END;
/