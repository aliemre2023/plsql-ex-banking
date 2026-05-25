DECLARE
  v_loan_id     NUMBER;
  v_loan_number VARCHAR2(50);
  v_monthly_pay NUMBER;
  v_decision    VARCHAR2(20);
  v_payoff_amt  NUMBER;
  v_status      VARCHAR2(20);
  v_balance     NUMBER;
  v_count       NUMBER;
  v_acct_bal    NUMBER;

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

  -- tc_01: ACTIVE loan → PAID_OFF olur
  BEGIN
    make_active_loan(1000, 100000, 5000, 12);
    pkg_loan_mgmt.pay_off_loan(v_loan_id, 100000, 2000, v_payoff_amt);
    SELECT status INTO v_status FROM loans WHERE loan_id = v_loan_id;
    ROLLBACK;
    IF v_status = 'PAID_OFF' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_loan_paid_off|OK|status:PAID_OFF');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_loan_paid_off|FAIL|expected:PAID_OFF got:' || v_status);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_loan_paid_off|FAIL|' || SQLERRM);
  END;

  -- tc_02: outstanding_balance = 0 olur
  BEGIN
    make_active_loan(1000, 100000, 5000, 12);
    pkg_loan_mgmt.pay_off_loan(v_loan_id, 100000, 2000, v_payoff_amt);
    SELECT outstanding_balance INTO v_balance FROM loans WHERE loan_id = v_loan_id;
    ROLLBACK;
    IF v_balance = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_balance_zero|OK|balance:0');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_balance_zero|FAIL|expected:0 got:' || v_balance);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_balance_zero|FAIL|' || SQLERRM);
  END;

  -- tc_03: p_payoff_amount = outstanding_balance + accrued_interest
  BEGIN
    make_active_loan(1000, 100000, 5000, 12);
    DECLARE
      v_outstanding NUMBER;
      v_rate        NUMBER;
      v_days        NUMBER;
      v_expected    NUMBER;
    BEGIN
      SELECT outstanding_balance, interest_rate INTO v_outstanding, v_rate
      FROM   loans WHERE loan_id = v_loan_id;
      v_days    := SYSDATE - TRUNC(SYSDATE, 'MM');
      v_expected := v_outstanding + pkg_transactions.calc_simple_interest(v_outstanding, v_rate, v_days);
      pkg_loan_mgmt.pay_off_loan(v_loan_id, 100000, 2000, v_payoff_amt);
      ROLLBACK;
      IF ROUND(v_payoff_amt, 2) = ROUND(v_expected, 2) THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_payoff_amount_correct|OK|amount:' || v_payoff_amt);
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_payoff_amount_correct|FAIL|expected:' ||
          ROUND(v_expected,2) || ' got:' || ROUND(v_payoff_amt,2));
      END IF;
    END;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_payoff_amount_correct|FAIL|' || SQLERRM);
  END;

  -- tc_04: Kalan SCHEDULED payments → WAIVED olur
  BEGIN
    make_active_loan(1000, 100000, 5000, 12);
    pkg_loan_mgmt.pay_off_loan(v_loan_id, 100000, 2000, v_payoff_amt);
    SELECT COUNT(*) INTO v_count
    FROM   loan_payments
    WHERE  loan_id = v_loan_id AND status = 'SCHEDULED';
    ROLLBACK;
    IF v_count = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_scheduled_waived|OK|no_scheduled_remain');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_scheduled_waived|FAIL|expected:0 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_scheduled_waived|FAIL|' || SQLERRM);
  END;

  -- tc_05: Payment account'tan payoff_amount çekilir
  BEGIN
    make_active_loan(1002, 100003, 5000, 12);
    SELECT balance INTO v_acct_bal FROM accounts WHERE account_id = 100003;
    pkg_loan_mgmt.pay_off_loan(v_loan_id, 100003, 2001, v_payoff_amt);
    DECLARE v_new_bal NUMBER; BEGIN
      SELECT balance INTO v_new_bal FROM accounts WHERE account_id = 100003;
      ROLLBACK;
      IF v_new_bal < v_acct_bal THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_account_debited|OK|debited:' || (v_acct_bal - v_new_bal));
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_account_debited|FAIL|balance_not_reduced');
      END IF;
    END;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_account_debited|FAIL|' || SQLERRM);
  END;

  -- tc_06: PAID_OFF loan → -20050 exception
  BEGIN
    pkg_loan_mgmt.pay_off_loan(2, 100002, 2000, v_payoff_amt); -- loan_id=2 PAID_OFF
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_already_paid_off|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20050 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_already_paid_off|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_already_paid_off|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_07: PENDING loan → -20050 exception
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
    pkg_loan_mgmt.pay_off_loan(v_loan_id, 100004, 2000, v_payoff_amt);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_pending_loan|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20050 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_pending_loan|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_pending_loan|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_08: payoff_amount > outstanding_balance (accrued interest eklendi)
  BEGIN
    make_active_loan(1000, 100000, 5000, 12);
    DECLARE v_outstanding NUMBER; BEGIN
      SELECT outstanding_balance INTO v_outstanding FROM loans WHERE loan_id = v_loan_id;
      pkg_loan_mgmt.pay_off_loan(v_loan_id, 100000, 2000, v_payoff_amt);
      ROLLBACK;
      IF v_payoff_amt >= v_outstanding THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_payoff_includes_interest|OK|payoff:' ||
          v_payoff_amt || ' outstanding:' || v_outstanding);
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_payoff_includes_interest|FAIL|payoff:' ||
          v_payoff_amt || ' outstanding:' || v_outstanding);
      END IF;
    END;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_payoff_includes_interest|FAIL|' || SQLERRM);
  END;

  -- tc_09: Var olmayan loan_id → NO_DATA_FOUND
  BEGIN
    pkg_loan_mgmt.pay_off_loan(999999, 100000, 2000, v_payoff_amt);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_nonexistent_loan|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_nonexistent_loan|OK|no_data_found');
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_nonexistent_loan|FAIL|wrong_exception:' || SQLCODE);
  END;

END;
/