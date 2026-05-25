DECLARE
  v_result VARCHAR2(500);
  v_loan_id NUMBER;
  v_loan_number VARCHAR2(50);
  v_monthly_pay NUMBER;
  v_decision VARCHAR2(20);

  PROCEDURE make_loan(
    p_status IN VARCHAR2,
    p_balance IN NUMBER,
    p_dpd IN NUMBER
  ) IS
  BEGIN
    pkg_loan_mgmt.originate_loan(
        p_customer_id => 1000, p_account_id => 100000,
        p_branch_id => 10, p_loan_type => 'PERSONAL',
        p_amount => 5000, p_term_months => 12,
        p_employee_id => 2000,
        p_loan_id => v_loan_id, p_loan_number => v_loan_number,
        p_monthly_payment => v_monthly_pay, p_decision => v_decision
    );
    UPDATE loans
    SET    status = p_status,
           outstanding_balance = p_balance,
           days_past_due = p_dpd
    WHERE  loan_id = v_loan_id;
  END;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: ACTIVE loan → doğru format döner
  BEGIN
    make_loan('ACTIVE', 18500, 0);
    v_result := pkg_loan_mgmt.get_loan_status_desc(v_loan_id);
    IF v_result = 'Loan #' || v_loan_id || ' | Status: ACTIVE | DPD: 0 | Balance: $' ||
                  TO_CHAR(18500, '999,999.99') THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_active_loan|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_active_loan|FAIL|unexpected:' || v_result);
    END IF;
    ROLLBACK;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_active_loan|FAIL|' || SQLERRM);
  END;

  -- tc_02: PAID_OFF loan → balance=0, DPD=0
  BEGIN
    make_loan('PAID_OFF', 0, 0);
    v_result := pkg_loan_mgmt.get_loan_status_desc(v_loan_id);
    IF v_result = 'Loan #' || v_loan_id || ' | Status: PAID_OFF | DPD: 0 | Balance: $' ||
                  TO_CHAR(0, '999,999.99') THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_paid_off_loan|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_paid_off_loan|FAIL|unexpected:' || v_result);
    END IF;
    ROLLBACK;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_paid_off_loan|FAIL|' || SQLERRM);
  END;

  -- tc_03: ACTIVE loan DPD=45 → DPD doğru yansıtılır
  BEGIN
    make_loan('ACTIVE', 142000, 45);
    v_result := pkg_loan_mgmt.get_loan_status_desc(v_loan_id);
    IF INSTR(v_result, 'DPD: 45') > 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_dpd_reflected|OK|dpd:45');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_dpd_reflected|FAIL|result:' || v_result);
    END IF;
    ROLLBACK;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_dpd_reflected|FAIL|' || SQLERRM);
  END;

  -- tc_04: 'Loan #' prefix ile başlıyor
  BEGIN
    make_loan('ACTIVE', 5000, 0);
    v_result := pkg_loan_mgmt.get_loan_status_desc(v_loan_id);
    IF v_result LIKE 'Loan #%' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_starts_with_loan_prefix|OK|prefix:Loan #');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_starts_with_loan_prefix|FAIL|result:' || v_result);
    END IF;
    ROLLBACK;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_starts_with_loan_prefix|FAIL|' || SQLERRM);
  END;

  -- tc_05: Status alanı sonuçta mevcut
  BEGIN
    make_loan('ACTIVE', 5000, 0);
    v_result := pkg_loan_mgmt.get_loan_status_desc(v_loan_id);
    IF INSTR(v_result, 'Status: ACTIVE') > 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_contains_status|OK|status:ACTIVE');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_contains_status|FAIL|result:' || v_result);
    END IF;
    ROLLBACK;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_contains_status|FAIL|' || SQLERRM);
  END;

  -- tc_06: Balance '$' ile başlayan formatlı string içeriyor
  BEGIN
    make_loan('ACTIVE', 5000, 0);
    v_result := pkg_loan_mgmt.get_loan_status_desc(v_loan_id);
    IF INSTR(v_result, 'Balance: $') > 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_balance_format|OK|contains:Balance: $');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_balance_format|FAIL|result:' || v_result);
    END IF;
    ROLLBACK;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_balance_format|FAIL|' || SQLERRM);
  END;

  -- tc_07: PENDING loan → status doğru yansıtılır
  BEGIN
    make_loan('PENDING', 8000, 0);
    v_result := pkg_loan_mgmt.get_loan_status_desc(v_loan_id);
    IF INSTR(v_result, 'Status: PENDING') > 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_pending_status|OK|status:PENDING');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_pending_status|FAIL|result:' || v_result);
    END IF;
    ROLLBACK;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_pending_status|FAIL|' || SQLERRM);
  END;

  -- tc_08: Var olmayan loan_id → 'Loan not found' döner
  BEGIN
    v_result := pkg_loan_mgmt.get_loan_status_desc(999999);
    IF v_result = 'Loan not found' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_not_found|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_not_found|FAIL|expected:Loan not found got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_not_found|FAIL|' || SQLERRM);
  END;

  -- tc_09: NULL loan_id → 'Loan not found' döner
  BEGIN
    v_result := pkg_loan_mgmt.get_loan_status_desc(NULL);
    IF v_result = 'Loan not found' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_null_loan_id|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_null_loan_id|FAIL|expected:Loan not found got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_null_loan_id|FAIL|' || SQLERRM);
  END;

  -- tc_10: loan_id değeri sonuçta yer alıyor
  BEGIN
    make_loan('ACTIVE', 5000, 0);
    v_result := pkg_loan_mgmt.get_loan_status_desc(v_loan_id);
    IF INSTR(v_result, 'Loan #' || v_loan_id) > 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_loan_id_in_result|OK|contains:Loan #' || v_loan_id);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_loan_id_in_result|FAIL|result:' || v_result);
    END IF;
    ROLLBACK;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_loan_id_in_result|FAIL|' || SQLERRM);
  END;

END;
/