DECLARE
  v_result NUMBER;
  v_loan_id NUMBER;
  v_loan_number VARCHAR2(50);
  v_monthly_pay NUMBER;
  v_decision VARCHAR2(20);

  PROCEDURE make_loan(
    p_status IN VARCHAR2,
    p_balance IN NUMBER
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
           outstanding_balance = p_balance
    WHERE  loan_id = v_loan_id;
  END;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: ACTIVE loan → doğru bakiye döner
  BEGIN
    make_loan('ACTIVE', 18500);
    v_result := pkg_loan_mgmt.get_outstanding_balance(v_loan_id);
    ROLLBACK;
    IF v_result = 18500.00 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_active_loan|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_active_loan|FAIL|expected:18500.00 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_active_loan|FAIL|' || SQLERRM);
  END;

  -- tc_02: PAID_OFF loan → 0 döner
  BEGIN
    make_loan('PAID_OFF', 0);
    v_result := pkg_loan_mgmt.get_outstanding_balance(v_loan_id);
    ROLLBACK;
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_paid_off_zero|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_paid_off_zero|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_paid_off_zero|FAIL|' || SQLERRM);
  END;

  -- tc_03: Yüksek bakiyeli ACTIVE loan
  BEGIN
    make_loan('ACTIVE', 142000);
    v_result := pkg_loan_mgmt.get_outstanding_balance(v_loan_id);
    ROLLBACK;
    IF v_result = 142000.00 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_high_balance|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_high_balance|FAIL|expected:142000.00 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_high_balance|FAIL|' || SQLERRM);
  END;

  -- tc_04: PENDING loan → bakiye döner
  BEGIN
    make_loan('PENDING', 8000);
    v_result := pkg_loan_mgmt.get_outstanding_balance(v_loan_id);
    ROLLBACK;
    IF v_result = 8000.00 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_pending_loan|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_pending_loan|FAIL|expected:8000.00 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_pending_loan|FAIL|' || SQLERRM);
  END;

  -- tc_05: Var olmayan loan_id → -1 döner (NO_DATA_FOUND handler)
  BEGIN
    v_result := pkg_loan_mgmt.get_outstanding_balance(999999);
    IF v_result = -1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_nonexistent_loan|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_nonexistent_loan|FAIL|expected:-1 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_nonexistent_loan|FAIL|' || SQLERRM);
  END;

  -- tc_06: NULL loan_id → -1 döner
  BEGIN
    v_result := pkg_loan_mgmt.get_outstanding_balance(NULL);
    IF v_result = -1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_null_loan_id|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_null_loan_id|FAIL|expected:-1 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_null_loan_id|FAIL|' || SQLERRM);
  END;

  -- tc_07: outstanding_balance=0 → 0 döner
  BEGIN
    make_loan('ACTIVE', 0);
    v_result := pkg_loan_mgmt.get_outstanding_balance(v_loan_id);
    ROLLBACK;
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_null_balance_nvl|OK|returned:0');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_null_balance_nvl|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_zero_balance|FAIL|' || SQLERRM);
  END;

  -- tc_08: Bakiye değiştirilince doğru yeni değer döner
  BEGIN
    make_loan('ACTIVE', 18500);
    UPDATE loans SET outstanding_balance = 17000 WHERE loan_id = v_loan_id;
    v_result := pkg_loan_mgmt.get_outstanding_balance(v_loan_id);
    ROLLBACK;
    IF v_result = 17000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_updated_balance|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_updated_balance|FAIL|expected:17000 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_updated_balance|FAIL|' || SQLERRM);
  END;

END;
/