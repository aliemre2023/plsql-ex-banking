DECLARE
  v_loan_id     NUMBER;
  v_loan_number VARCHAR2(50);
  v_monthly_pay NUMBER;
  v_decision    VARCHAR2(20);
  v_pay_id      NUMBER;
  v_principal   NUMBER;
  v_interest    NUMBER;
  v_remaining   NUMBER;
  v_status      VARCHAR2(20);
  v_balance     NUMBER;
  v_count       NUMBER;

  -- Helper: ACTIVE loan oluşturur (approve_and_disburse ile)
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

  -- tc_01: Normal ödeme → outstanding_balance azalır
  BEGIN
    make_active_loan(1000, 100000, 10000, 12);
    SELECT outstanding_balance INTO v_balance FROM loans WHERE loan_id = v_loan_id;
    pkg_loan_mgmt.process_loan_payment(v_loan_id, v_monthly_pay, 100000,
                                       2000, v_pay_id, v_principal, v_interest, v_remaining);
    DECLARE v_new_bal NUMBER; BEGIN
      SELECT outstanding_balance INTO v_new_bal FROM loans WHERE loan_id = v_loan_id;
      ROLLBACK;
      IF v_new_bal < v_balance AND v_pay_id IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_balance_decreases|OK|before:' || v_balance || ' after:' || v_new_bal);
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_balance_decreases|FAIL|before:' || v_balance || ' after:' || v_new_bal);
      END IF;
    END;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_balance_decreases|FAIL|' || SQLERRM);
  END;

  -- tc_02: principal_paid + interest_paid = payment_amount
  BEGIN
    make_active_loan(1002, 100003, 10000, 12);
    pkg_loan_mgmt.process_loan_payment(v_loan_id, v_monthly_pay, 100003,
                                       2001, v_pay_id, v_principal, v_interest, v_remaining);
    ROLLBACK;
    IF ROUND(v_principal + v_interest, 2) = ROUND(v_monthly_pay, 2) THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_split_sum_correct|OK|principal:' || v_principal || ' interest:' || v_interest);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_split_sum_correct|FAIL|sum:' || (v_principal+v_interest) || ' payment:' || v_monthly_pay);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_split_sum_correct|FAIL|' || SQLERRM);
  END;

  -- tc_03: payment_amount >= scheduled_amount → loan_payment status=PAID
  BEGIN
    make_active_loan(1000, 100000, 10000, 12);
    pkg_loan_mgmt.process_loan_payment(v_loan_id, v_monthly_pay, 100000,
                                       2000, v_pay_id, v_principal, v_interest, v_remaining);
    SELECT status INTO v_status FROM loan_payments WHERE payment_id = v_pay_id;
    ROLLBACK;
    IF v_status = 'PAID' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_payment_status_paid|OK|status:PAID');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_payment_status_paid|FAIL|expected:PAID got:' || v_status);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_payment_status_paid|FAIL|' || SQLERRM);
  END;

  -- tc_04: payment_amount < scheduled_amount → status=PARTIAL
  BEGIN
    make_active_loan(1000, 100000, 10000, 12);
    pkg_loan_mgmt.process_loan_payment(v_loan_id, v_monthly_pay / 2, 100000,
                                       2000, v_pay_id, v_principal, v_interest, v_remaining);
    SELECT status INTO v_status FROM loan_payments WHERE payment_id = v_pay_id;
    ROLLBACK;
    IF v_status = 'PARTIAL' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_partial_payment|OK|status:PARTIAL');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_partial_payment|FAIL|expected:PARTIAL got:' || v_status);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_partial_payment|FAIL|' || SQLERRM);
  END;

  -- tc_05: days_past_due = 0 olarak sıfırlanır
  BEGIN
    make_active_loan(1000, 100000, 10000, 12);
    UPDATE loans SET days_past_due = 30 WHERE loan_id = v_loan_id;
    pkg_loan_mgmt.process_loan_payment(v_loan_id, v_monthly_pay, 100000,
                                       2000, v_pay_id, v_principal, v_interest, v_remaining);
    SELECT COUNT(*) INTO v_count FROM loans
    WHERE  loan_id = v_loan_id AND days_past_due = 0;
    ROLLBACK;
    IF v_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_dpd_reset_zero|OK|days_past_due:0');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_dpd_reset_zero|FAIL|expected:1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_dpd_reset_zero|FAIL|' || SQLERRM);
  END;

  -- tc_06: PAID_OFF loan → -20053 exception
  BEGIN
    pkg_loan_mgmt.process_loan_payment(2, 500, 100002,
                                       2000, v_pay_id, v_principal, v_interest, v_remaining);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_paid_off_loan|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20053 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_paid_off_loan|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_paid_off_loan|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_07: PENDING loan → -20050 exception
  BEGIN
    pkg_loan_mgmt.originate_loan(
        p_customer_id => 1003, p_account_id => 100004,
        p_branch_id => 10, p_loan_type => 'PERSONAL',
        p_amount => 5000, p_term_months => 12,
        p_employee_id => 2000,
        p_loan_id => v_loan_id, p_loan_number => v_loan_number,
        p_monthly_payment => v_monthly_pay, p_decision => v_decision
    );
    UPDATE loans SET status = 'PENDING' WHERE loan_id = v_loan_id;
    pkg_loan_mgmt.process_loan_payment(v_loan_id, 500, 100004,
                                       2000, v_pay_id, v_principal, v_interest, v_remaining);
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

  -- tc_08: Payment account'tan para çekilir (withdraw)
  BEGIN
    make_active_loan(1000, 100000, 10000, 12);
    SELECT balance INTO v_balance FROM accounts WHERE account_id = 100000;
    pkg_loan_mgmt.process_loan_payment(v_loan_id, v_monthly_pay, 100000,
                                       2000, v_pay_id, v_principal, v_interest, v_remaining);
    DECLARE v_new_bal NUMBER; BEGIN
      SELECT balance INTO v_new_bal FROM accounts WHERE account_id = 100000;
      ROLLBACK;
      IF v_new_bal = v_balance - v_monthly_pay THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_account_debited|OK|debited:' || v_monthly_pay);
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_account_debited|FAIL|expected:' ||
          (v_balance-v_monthly_pay) || ' got:' || v_new_bal);
      END IF;
    END;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_account_debited|FAIL|' || SQLERRM);
  END;

  -- tc_09: Grace period geçmişse late fee oluşur
  -- due_date'i 20 gün (grace=15) önceye çek
  BEGIN
    make_active_loan(1000, 100000, 10000, 12);
    UPDATE loan_payments
    SET    due_date = TRUNC(SYSDATE) - 20
    WHERE  loan_id  = v_loan_id
    AND    due_date = (SELECT MIN(due_date) FROM loan_payments
                      WHERE loan_id = v_loan_id AND status = 'SCHEDULED');
    pkg_loan_mgmt.process_loan_payment(v_loan_id, v_monthly_pay, 100000,
                                       2000, v_pay_id, v_principal, v_interest, v_remaining);
    SELECT COUNT(*) INTO v_count
    FROM   fee_ledger
    WHERE  account_id = 100000 AND fee_type = 'LATE_FEE';
    ROLLBACK;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_late_fee_applied|OK|count:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_late_fee_applied|FAIL|expected:>=1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_late_fee_applied|FAIL|' || SQLERRM);
  END;

  -- tc_10: Grace period içindeyse late fee yok
  BEGIN
    make_active_loan(1000, 100000, 10000, 12);
    -- Due date bugünden 5 gün önce (grace=15 → içinde)
    UPDATE loan_payments
    SET    due_date = TRUNC(SYSDATE) - 5
    WHERE  loan_id  = v_loan_id
    AND    due_date = (SELECT MIN(due_date) FROM loan_payments
                      WHERE loan_id = v_loan_id AND status = 'SCHEDULED');
    pkg_loan_mgmt.process_loan_payment(v_loan_id, v_monthly_pay, 100000,
                                       2000, v_pay_id, v_principal, v_interest, v_remaining);
    SELECT COUNT(*) INTO v_count
    FROM   fee_ledger
    WHERE  account_id = 100000 AND fee_type = 'LATE_FEE';
    ROLLBACK;
    IF v_count = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_no_late_fee_grace_period|OK|no_late_fee');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_no_late_fee_grace_period|FAIL|expected:0 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_no_late_fee_grace_period|FAIL|' || SQLERRM);
  END;

  -- tc_11: Son ödeme → loan status=PAID_OFF, remaining=0
  BEGIN
    make_active_loan(1000, 100000, 10000, 12);
    SELECT outstanding_balance INTO v_balance FROM loans WHERE loan_id = v_loan_id;
    -- Tek seferde tüm bakiyeyi öde
    pkg_loan_mgmt.process_loan_payment(v_loan_id, v_balance + 1000, 100000,
                                       2000, v_pay_id, v_principal, v_interest, v_remaining);
    SELECT status INTO v_status FROM loans WHERE loan_id = v_loan_id;
    ROLLBACK;
    IF v_status = 'PAID_OFF' AND v_remaining = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_loan_paid_off|OK|status:PAID_OFF remaining:0');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_loan_paid_off|FAIL|status:' || v_status || ' remaining:' || v_remaining);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_loan_paid_off|FAIL|' || SQLERRM);
  END;

  -- tc_12: No outstanding payments → -20057 exception
  BEGIN
    make_active_loan(1000, 100000, 10000, 12);
    DELETE FROM loan_payments WHERE loan_id = v_loan_id AND status = 'SCHEDULED';
    pkg_loan_mgmt.process_loan_payment(v_loan_id, v_monthly_pay, 100000,
                                       2000, v_pay_id, v_principal, v_interest, v_remaining);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_no_payments|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20057 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_no_payments|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_no_payments|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_13: Audit log oluşur
  DECLARE
    v_marker TIMESTAMP := SYSTIMESTAMP;
  BEGIN
    make_active_loan(1002, 100003, 10000, 12);
    pkg_loan_mgmt.process_loan_payment(v_loan_id, v_monthly_pay, 100003,
                                       2001, v_pay_id, v_principal, v_interest, v_remaining);
    SELECT COUNT(*) INTO v_count
    FROM   audit_log
    WHERE  table_name  = 'LOANS'
    AND    record_id   = v_loan_id
    AND    action      = 'UPDATE'
    AND    changed_at >= v_marker;
    ROLLBACK;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_audit_log|OK|count:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_audit_log|FAIL|expected:>=1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_audit_log|FAIL|' || SQLERRM);
  END;

END;
/