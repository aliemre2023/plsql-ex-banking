DECLARE
  v_result NUMBER;
  v_today  DATE := TRUNC(SYSDATE);
  v_loan_id NUMBER;

  FUNCTION create_loan(p_status IN VARCHAR2 DEFAULT 'ACTIVE') RETURN NUMBER IS
    v_id NUMBER;
    v_loan_number VARCHAR2(50);
    v_monthly_pay NUMBER;
    v_decision VARCHAR2(20);
  BEGIN
    pkg_loan_mgmt.originate_loan(
        p_customer_id => 1000, p_account_id => 100000,
        p_branch_id => 10, p_loan_type => 'PERSONAL',
        p_amount => 5000, p_term_months => 12,
        p_employee_id => 2000,
        p_loan_id => v_id, p_loan_number => v_loan_number,
        p_monthly_payment => v_monthly_pay, p_decision => v_decision
    );
    UPDATE loans SET status = p_status WHERE loan_id = v_id;
    RETURN v_id;
  END;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: OVERDUE + paid_amount < scheduled_amount → DPD = gün farkı
  BEGIN
    v_loan_id := create_loan('ACTIVE');
    INSERT INTO loan_payments (payment_id, loan_id, due_date, scheduled_amount,
                               paid_amount, principal_portion, interest_portion, status)
    VALUES (seq_payment_id.NEXTVAL, v_loan_id, v_today - 45, 500, 0, 450, 50, 'OVERDUE');
    v_result := pkg_loan_mgmt.calc_days_past_due(v_loan_id);
    ROLLBACK;
    IF v_result = 45 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_overdue_seed|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_overdue_seed|FAIL|expected:45 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_overdue_seed|FAIL|' || SQLERRM);
  END;

  -- tc_02: SCHEDULED status → sayılmaz, 0 döner
  BEGIN
    v_loan_id := create_loan('ACTIVE');
    INSERT INTO loan_payments (payment_id, loan_id, due_date, scheduled_amount,
                               principal_portion, interest_portion, status)
    VALUES (seq_payment_id.NEXTVAL, v_loan_id, v_today - 5, 500, 450, 50, 'SCHEDULED');
    v_result := pkg_loan_mgmt.calc_days_past_due(v_loan_id);
    ROLLBACK;
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_scheduled_not_counted|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_scheduled_not_counted|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_scheduled_not_counted|FAIL|' || SQLERRM);
  END;

  -- tc_03: overdue yokken → 0 döner
  BEGIN
    v_loan_id := create_loan('ACTIVE');
    INSERT INTO loan_payments (payment_id, loan_id, due_date, scheduled_amount,
                               principal_portion, interest_portion, status)
    VALUES (seq_payment_id.NEXTVAL, v_loan_id, v_today + 30, 500, 450, 50, 'SCHEDULED');
    v_result := pkg_loan_mgmt.calc_days_past_due(v_loan_id);
    ROLLBACK;
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_no_overdue_payments|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_no_overdue_payments|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_no_overdue_payments|FAIL|' || SQLERRM);
  END;

  -- tc_04: Var olmayan loan_id → 0 döner
  BEGIN
    v_result := pkg_loan_mgmt.calc_days_past_due(999999);
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_nonexistent_loan|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_nonexistent_loan|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_nonexistent_loan|FAIL|' || SQLERRM);
  END;

  -- tc_05: NULL loan_id → 0 döner
  BEGIN
    v_result := pkg_loan_mgmt.calc_days_past_due(NULL);
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_null_loan_id|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_null_loan_id|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_null_loan_id|FAIL|' || SQLERRM);
  END;

  -- tc_06: OVERDUE + paid_amount = scheduled_amount → sayılmaz (fully paid)
  BEGIN
    v_loan_id := create_loan('ACTIVE');
    INSERT INTO loan_payments (payment_id, loan_id, due_date, scheduled_amount,
                               paid_amount, principal_portion, interest_portion, status)
    VALUES (seq_payment_id.NEXTVAL, v_loan_id, v_today - 10, 450.50, 450.50, 400, 50.50, 'OVERDUE');
    v_result := pkg_loan_mgmt.calc_days_past_due(v_loan_id);
    ROLLBACK;
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_paid_overdue_not_counted|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_paid_overdue_not_counted|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_paid_overdue_not_counted|FAIL|' || SQLERRM);
  END;

  -- tc_07: PARTIAL status + paid_amount < scheduled_amount → sayılır
  BEGIN
    v_loan_id := create_loan('ACTIVE');
    INSERT INTO loan_payments (payment_id, loan_id, due_date, scheduled_amount,
                               paid_amount, principal_portion, interest_portion, status)
    VALUES (seq_payment_id.NEXTVAL, v_loan_id, v_today - 20, 500, 200, 450, 50, 'PARTIAL');
    v_result := pkg_loan_mgmt.calc_days_past_due(v_loan_id);
    ROLLBACK;
    IF v_result = 20 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_partial_counted|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_partial_counted|FAIL|expected:20 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_partial_counted|FAIL|' || SQLERRM);
  END;

  -- tc_08: Birden fazla OVERDUE → MIN(due_date) kullanılır (en eski)
  -- 30 gün ve 10 gün önce → MIN = 30 gün → DPD = 30
  BEGIN
    v_loan_id := create_loan('ACTIVE');
    INSERT INTO loan_payments (payment_id, loan_id, due_date, scheduled_amount,
                               paid_amount, principal_portion, interest_portion, status)
    VALUES (seq_payment_id.NEXTVAL, v_loan_id, v_today - 30, 500, 0, 450, 50, 'OVERDUE');
    INSERT INTO loan_payments (payment_id, loan_id, due_date, scheduled_amount,
                               paid_amount, principal_portion, interest_portion, status)
    VALUES (seq_payment_id.NEXTVAL, v_loan_id, v_today - 10, 500, 0, 450, 50, 'OVERDUE');
    v_result := pkg_loan_mgmt.calc_days_past_due(v_loan_id);
    ROLLBACK;
    IF v_result = 30 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_min_due_date_used|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_min_due_date_used|FAIL|expected:30 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_min_due_date_used|FAIL|' || SQLERRM);
  END;

  -- tc_09: GREATEST(0) garantisi — due_date gelecekte ise 0 döner
  BEGIN
    v_loan_id := create_loan('ACTIVE');
    INSERT INTO loan_payments (payment_id, loan_id, due_date, scheduled_amount,
                               paid_amount, principal_portion, interest_portion, status)
    VALUES (seq_payment_id.NEXTVAL, v_loan_id, v_today + 5, 500, 0, 450, 50, 'OVERDUE');
    v_result := pkg_loan_mgmt.calc_days_past_due(v_loan_id);
    ROLLBACK;
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_future_due_date_zero|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_future_due_date_zero|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_future_due_date_zero|FAIL|' || SQLERRM);
  END;

  -- tc_10: Tam bugün vadeli OVERDUE → DPD = 0
  BEGIN
    v_loan_id := create_loan('ACTIVE');
    INSERT INTO loan_payments (payment_id, loan_id, due_date, scheduled_amount,
                               paid_amount, principal_portion, interest_portion, status)
    VALUES (seq_payment_id.NEXTVAL, v_loan_id, v_today, 500, 0, 450, 50, 'OVERDUE');
    v_result := pkg_loan_mgmt.calc_days_past_due(v_loan_id);
    ROLLBACK;
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_today_due_date_zero|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_today_due_date_zero|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_today_due_date_zero|FAIL|' || SQLERRM);
  END;

END;
/