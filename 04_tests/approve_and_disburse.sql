DECLARE
  v_loan_id     NUMBER;
  v_loan_number VARCHAR2(50);
  v_monthly_pay NUMBER;
  v_decision    VARCHAR2(20);
  v_status      VARCHAR2(20);
  v_balance     NUMBER;
  v_count       NUMBER;
  v_acct_bal    NUMBER;

  -- Helper: PENDING loan oluşturur
  PROCEDURE make_pending_loan(
    p_customer_id IN NUMBER,
    p_account_id  IN NUMBER,
    p_amount      IN NUMBER DEFAULT 5000
  ) IS
  BEGIN
    pkg_loan_mgmt.originate_loan(
        p_customer_id => p_customer_id, p_account_id => p_account_id,
        p_branch_id => 10, p_loan_type => 'PERSONAL',
        p_amount => p_amount, p_term_months => 12,
        p_employee_id => 2000,
        p_loan_id => v_loan_id, p_loan_number => v_loan_number,
        p_monthly_payment => v_monthly_pay, p_decision => v_decision
    );
    -- David'i PENDING yapıyoruz (HIGH risk → REVIEW → PENDING)
    UPDATE loans SET status = 'PENDING' WHERE loan_id = v_loan_id;
  END;

BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: PENDING → disburse → status=ACTIVE
  BEGIN
    make_pending_loan(1003, 100004);
    pkg_loan_mgmt.approve_and_disburse(v_loan_id, 2000, NULL);
    SELECT status INTO v_status FROM loans WHERE loan_id = v_loan_id;
    ROLLBACK;
    IF v_status = 'ACTIVE' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_pending_to_active|OK|status:ACTIVE');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_pending_to_active|FAIL|expected:ACTIVE got:' || v_status);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_pending_to_active|FAIL|' || SQLERRM);
  END;

  -- tc_02: APPROVED → disburse → status=ACTIVE
  BEGIN
    make_pending_loan(1000, 100000);
    UPDATE loans SET status = 'APPROVED' WHERE loan_id = v_loan_id;
    pkg_loan_mgmt.approve_and_disburse(v_loan_id, 2000, NULL);
    SELECT status INTO v_status FROM loans WHERE loan_id = v_loan_id;
    ROLLBACK;
    IF v_status = 'ACTIVE' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_approved_to_active|OK|status:ACTIVE');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_approved_to_active|FAIL|expected:ACTIVE got:' || v_status);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_approved_to_active|FAIL|' || SQLERRM);
  END;

  -- tc_03: ACTIVE loan → -20055 exception
  BEGIN
    make_pending_loan(1003, 100004);
    UPDATE loans SET status = 'ACTIVE' WHERE loan_id = v_loan_id;
    pkg_loan_mgmt.approve_and_disburse(v_loan_id, 2000, NULL);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_active_cannot_disburse|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20055 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_active_cannot_disburse|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_active_cannot_disburse|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_04: REJECTED loan → -20055 exception
  BEGIN
    make_pending_loan(1003, 100004);
    UPDATE loans SET status = 'REJECTED' WHERE loan_id = v_loan_id;
    pkg_loan_mgmt.approve_and_disburse(v_loan_id, 2000, NULL);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_rejected_cannot_disburse|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20055 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_rejected_cannot_disburse|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_rejected_cannot_disburse|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_05: Loan proceeds loan.account_id'ye deposit edilir
  BEGIN
    make_pending_loan(1003, 100004, 3000);
    SELECT balance INTO v_acct_bal FROM accounts WHERE account_id = 100004;
    pkg_loan_mgmt.approve_and_disburse(v_loan_id, 2000, NULL);
    SELECT balance INTO v_balance FROM accounts WHERE account_id = 100004;
    ROLLBACK;
    IF v_balance = v_acct_bal + 3000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_proceeds_deposited|OK|balance_increased:3000');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_proceeds_deposited|FAIL|expected:' ||
        (v_acct_bal+3000) || ' got:' || v_balance);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_proceeds_deposited|FAIL|' || SQLERRM);
  END;

  -- tc_06: p_disbursement_account != NULL → o account'a deposit edilir
  BEGIN
    make_pending_loan(1003, 100004, 2000);
    SELECT balance INTO v_acct_bal FROM accounts WHERE account_id = 100003;
    pkg_loan_mgmt.approve_and_disburse(v_loan_id, 2000, 100003);
    SELECT balance INTO v_balance FROM accounts WHERE account_id = 100003;
    ROLLBACK;
    IF v_balance = v_acct_bal + 2000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_custom_disbursement_account|OK|deposited_to:100003');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_custom_disbursement_account|FAIL|expected:' ||
        (v_acct_bal+2000) || ' got:' || v_balance);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_custom_disbursement_account|FAIL|' || SQLERRM);
  END;

  -- tc_07: disbursement_date = SYSDATE olarak kaydedilir
  BEGIN
    make_pending_loan(1003, 100004);
    pkg_loan_mgmt.approve_and_disburse(v_loan_id, 2000, NULL);
    SELECT COUNT(*) INTO v_count
    FROM   loans
    WHERE  loan_id           = v_loan_id
    AND    TRUNC(disbursement_date) = TRUNC(SYSDATE);
    ROLLBACK;
    IF v_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_disbursement_date|OK|date:today');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_disbursement_date|FAIL|expected:1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_disbursement_date|FAIL|' || SQLERRM);
  END;

  -- tc_08: approved_by = p_employee_id olarak güncellenir
  BEGIN
    make_pending_loan(1003, 100004);
    pkg_loan_mgmt.approve_and_disburse(v_loan_id, 2001, NULL);
    SELECT COUNT(*) INTO v_count
    FROM   loans
    WHERE  loan_id     = v_loan_id
    AND    approved_by = 2001;
    ROLLBACK;
    IF v_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_approved_by_updated|OK|approved_by:2001');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_approved_by_updated|FAIL|expected:1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_approved_by_updated|FAIL|' || SQLERRM);
  END;

  -- tc_09: Amortization schedule oluşturulur (term_months kadar kayıt)
  BEGIN
    make_pending_loan(1003, 100004);
    pkg_loan_mgmt.approve_and_disburse(v_loan_id, 2000, NULL);
    SELECT COUNT(*) INTO v_count
    FROM   loan_payments
    WHERE  loan_id = v_loan_id
    AND    status  = 'SCHEDULED';
    ROLLBACK;
    IF v_count = 12 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_amortization_created|OK|scheduled_count:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_amortization_created|FAIL|expected:12 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_amortization_created|FAIL|' || SQLERRM);
  END;

  -- tc_10: Var olmayan loan_id → NO_DATA_FOUND
  BEGIN
    pkg_loan_mgmt.approve_and_disburse(999999, 2000, NULL);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_nonexistent_loan|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = 100 OR SQLCODE = -1403 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_nonexistent_loan|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_nonexistent_loan|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_11: Audit log oluşur
  DECLARE
    v_marker TIMESTAMP := SYSTIMESTAMP;
  BEGIN
    make_pending_loan(1003, 100004);
    pkg_loan_mgmt.approve_and_disburse(v_loan_id, 2000, NULL);
    SELECT COUNT(*) INTO v_count
    FROM   audit_log
    WHERE  table_name  = 'LOANS'
    AND    record_id   = v_loan_id
    AND    action      = 'UPDATE'
    AND    changed_at >= v_marker;
    ROLLBACK;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_audit_log|OK|count:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_audit_log|FAIL|expected:>=1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_audit_log|FAIL|' || SQLERRM);
  END;

END;
/