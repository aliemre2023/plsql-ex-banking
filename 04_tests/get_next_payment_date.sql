DECLARE
  v_result DATE;
  v_today  DATE := TRUNC(SYSDATE);
  v_loan_id NUMBER;

  FUNCTION create_loan RETURN NUMBER IS
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
    UPDATE loans SET status = 'ACTIVE' WHERE loan_id = v_id;
    RETURN v_id;
  END;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: SCHEDULED kayıt var → en yakın due_date döner
  BEGIN
    v_loan_id := create_loan;
    INSERT INTO loan_payments (payment_id, loan_id, due_date, scheduled_amount,
                               principal_portion, interest_portion, status)
    VALUES (seq_payment_id.NEXTVAL, v_loan_id, v_today + 10, 500, 450, 50, 'SCHEDULED');
    v_result := pkg_loan_mgmt.get_next_payment_date(v_loan_id);
    ROLLBACK;
    IF v_result IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_scheduled_exists|OK|returned:' || TO_CHAR(v_result,'YYYY-MM-DD'));
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_scheduled_exists|FAIL|returned:NULL');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_scheduled_exists|FAIL|' || SQLERRM);
  END;

  -- tc_02: MIN(due_date) kullanılır — en yakın tarih seçilir
  BEGIN
    v_loan_id := create_loan;
    INSERT INTO loan_payments (payment_id, loan_id, due_date, scheduled_amount,
                               principal_portion, interest_portion, status)
    VALUES (seq_payment_id.NEXTVAL, v_loan_id, v_today + 10, 500, 450, 50, 'SCHEDULED');
    INSERT INTO loan_payments (payment_id, loan_id, due_date, scheduled_amount,
                               principal_portion, interest_portion, status)
    VALUES (seq_payment_id.NEXTVAL, v_loan_id, v_today + 30, 500, 450, 50, 'SCHEDULED');
    v_result := pkg_loan_mgmt.get_next_payment_date(v_loan_id);
    ROLLBACK;
    IF v_result = v_today + 10 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_min_date_used|OK|returned:' || TO_CHAR(v_result,'YYYY-MM-DD'));
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_min_date_used|FAIL|expected:' ||
        TO_CHAR(v_today+10,'YYYY-MM-DD') || ' got:' || TO_CHAR(v_result,'YYYY-MM-DD'));
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_min_date_used|FAIL|' || SQLERRM);
  END;

  -- tc_03: Sadece OVERDUE kayıt var → NULL döner (SCHEDULED/PARTIAL yok)
  BEGIN
    v_loan_id := create_loan;
    INSERT INTO loan_payments (payment_id, loan_id, due_date, scheduled_amount,
                               principal_portion, interest_portion, status)
    VALUES (seq_payment_id.NEXTVAL, v_loan_id, v_today - 5, 500, 450, 50, 'OVERDUE');
    v_result := pkg_loan_mgmt.get_next_payment_date(v_loan_id);
    ROLLBACK;
    IF v_result IS NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_only_overdue_null|OK|returned:NULL');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_only_overdue_null|FAIL|expected:NULL got:' ||
        TO_CHAR(v_result,'YYYY-MM-DD'));
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_only_overdue_null|FAIL|' || SQLERRM);
  END;

  -- tc_04: PARTIAL status → sayılır, tarih döner
  BEGIN
    v_loan_id := create_loan;
    INSERT INTO loan_payments (payment_id, loan_id, due_date, scheduled_amount,
                               paid_amount, principal_portion, interest_portion, status)
    VALUES (seq_payment_id.NEXTVAL, v_loan_id, v_today + 5, 500, 200, 450, 50, 'PARTIAL');
    v_result := pkg_loan_mgmt.get_next_payment_date(v_loan_id);
    ROLLBACK;
    IF v_result = v_today + 5 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_partial_counted|OK|returned:' ||
        TO_CHAR(v_result,'YYYY-MM-DD'));
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_partial_counted|FAIL|expected:' ||
        TO_CHAR(v_today+5,'YYYY-MM-DD') || ' got:' || TO_CHAR(v_result,'YYYY-MM-DD'));
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_partial_counted|FAIL|' || SQLERRM);
  END;

  -- tc_05: PAID status → sayılmaz
  BEGIN
    v_loan_id := create_loan;
    INSERT INTO loan_payments (payment_id, loan_id, due_date, scheduled_amount,
                               paid_amount, principal_portion, interest_portion, status)
    VALUES (seq_payment_id.NEXTVAL, v_loan_id, v_today + 15, 500, 500, 450, 50, 'PAID');
    v_result := pkg_loan_mgmt.get_next_payment_date(v_loan_id);
    ROLLBACK;
    IF v_result IS NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_paid_not_counted|OK|returned:NULL');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_paid_not_counted|FAIL|expected:NULL got:' ||
        TO_CHAR(v_result,'YYYY-MM-DD'));
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_paid_not_counted|FAIL|' || SQLERRM);
  END;

  -- tc_06: WAIVED status → sayılmaz
  BEGIN
    v_loan_id := create_loan;
    INSERT INTO loan_payments (payment_id, loan_id, due_date, scheduled_amount,
                               principal_portion, interest_portion, status)
    VALUES (seq_payment_id.NEXTVAL, v_loan_id, v_today + 5, 500, 450, 50, 'WAIVED');
    v_result := pkg_loan_mgmt.get_next_payment_date(v_loan_id);
    ROLLBACK;
    IF v_result IS NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_waived_not_counted|OK|returned:NULL');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_waived_not_counted|FAIL|expected:NULL got:' ||
        TO_CHAR(v_result,'YYYY-MM-DD'));
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_waived_not_counted|FAIL|' || SQLERRM);
  END;

  -- tc_07: Var olmayan loan_id → NULL döner
  BEGIN
    v_result := pkg_loan_mgmt.get_next_payment_date(999999);
    IF v_result IS NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_nonexistent_loan|OK|returned:NULL');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_nonexistent_loan|FAIL|expected:NULL got:' ||
        TO_CHAR(v_result,'YYYY-MM-DD'));
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_nonexistent_loan|FAIL|' || SQLERRM);
  END;

  -- tc_08: NULL loan_id → NULL döner
  BEGIN
    v_result := pkg_loan_mgmt.get_next_payment_date(NULL);
    IF v_result IS NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_null_loan_id|OK|returned:NULL');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_null_loan_id|FAIL|expected:NULL got:' ||
        TO_CHAR(v_result,'YYYY-MM-DD'));
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_null_loan_id|FAIL|' || SQLERRM);
  END;

  -- tc_09: PARTIAL + SCHEDULED birlikte → MIN döner
  BEGIN
    v_loan_id := create_loan;
    INSERT INTO loan_payments (payment_id, loan_id, due_date, scheduled_amount,
                               paid_amount, principal_portion, interest_portion, status)
    VALUES (seq_payment_id.NEXTVAL, v_loan_id, v_today + 20, 500, 200, 450, 50, 'PARTIAL');
    INSERT INTO loan_payments (payment_id, loan_id, due_date, scheduled_amount,
                               principal_portion, interest_portion, status)
    VALUES (seq_payment_id.NEXTVAL, v_loan_id, v_today + 5, 500, 450, 50, 'SCHEDULED');
    v_result := pkg_loan_mgmt.get_next_payment_date(v_loan_id);
    ROLLBACK;
    IF v_result = v_today + 5 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_partial_and_scheduled_min|OK|returned:' ||
        TO_CHAR(v_result,'YYYY-MM-DD'));
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_partial_and_scheduled_min|FAIL|expected:' ||
        TO_CHAR(v_today+5,'YYYY-MM-DD') || ' got:' || TO_CHAR(v_result,'YYYY-MM-DD'));
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_partial_and_scheduled_min|FAIL|' || SQLERRM);
  END;

END;
/