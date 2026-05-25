DECLARE
  v_loan_id     NUMBER;
  v_loan_number VARCHAR2(50);
  v_monthly_pay NUMBER;
  v_decision    VARCHAR2(20);
  v_status      VARCHAR2(20);
  v_count       NUMBER;

  -- Helper: ACTIVE + istenen DPD'ye sahip loan oluşturur
  PROCEDURE make_active_loan_dpd(
    p_customer_id IN NUMBER,
    p_account_id  IN NUMBER,
    p_dpd         IN NUMBER,
    p_amount      IN NUMBER DEFAULT 10000
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
    UPDATE loans
    SET    status        = 'ACTIVE',
           days_past_due = p_dpd
    WHERE  loan_id = v_loan_id;
  END;

BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: DPD >= 180 + ACTIVE → WRITTEN_OFF olur
  BEGIN
    make_active_loan_dpd(1000, 100000, 180);
    pkg_loan_mgmt.charge_off_loan(v_loan_id, 'Uncollectible', 2000);
    SELECT status INTO v_status FROM loans WHERE loan_id = v_loan_id;
    ROLLBACK;
    IF v_status = 'WRITTEN_OFF' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_written_off|OK|status:WRITTEN_OFF');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_written_off|FAIL|expected:WRITTEN_OFF got:' || v_status);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_written_off|FAIL|' || SQLERRM);
  END;

  -- tc_02: DPD < 180 → -20059 exception
  BEGIN
    make_active_loan_dpd(1000, 100000, 179);
    pkg_loan_mgmt.charge_off_loan(v_loan_id, 'Too early', 2000);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_dpd_below_threshold|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20059 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_dpd_below_threshold|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_dpd_below_threshold|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_03: DPD tam 180 (sınır) → başarılı
  BEGIN
    make_active_loan_dpd(1002, 100003, 180);
    pkg_loan_mgmt.charge_off_loan(v_loan_id, 'Boundary test', 2001);
    SELECT status INTO v_status FROM loans WHERE loan_id = v_loan_id;
    ROLLBACK;
    IF v_status = 'WRITTEN_OFF' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_dpd_exactly_180|OK|status:WRITTEN_OFF');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_dpd_exactly_180|FAIL|expected:WRITTEN_OFF got:' || v_status);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_dpd_exactly_180|FAIL|' || SQLERRM);
  END;

  -- tc_04: PAID_OFF loan → -20058 exception
  BEGIN
    pkg_loan_mgmt.charge_off_loan(2, 'Paid off test', 2000); -- loan_id=2 PAID_OFF
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_paid_off_cannot_charge|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20058 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_paid_off_cannot_charge|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_paid_off_cannot_charge|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_05: PENDING loan → -20058 exception
  BEGIN
    pkg_loan_mgmt.originate_loan(
        p_customer_id => 1003, p_account_id => 100004,
        p_branch_id => 10, p_loan_type => 'PERSONAL',
        p_amount => 5000, p_term_months => 12,
        p_employee_id => 2000,
        p_loan_id => v_loan_id, p_loan_number => v_loan_number,
        p_monthly_payment => v_monthly_pay, p_decision => v_decision
    );
    UPDATE loans SET status = 'PENDING', days_past_due = 200 WHERE loan_id = v_loan_id;
    pkg_loan_mgmt.charge_off_loan(v_loan_id, 'Pending test', 2000);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_pending_cannot_charge|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20058 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_pending_cannot_charge|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_pending_cannot_charge|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_06: SCHEDULED + OVERDUE payments → WAIVED olur
  BEGIN
    make_active_loan_dpd(1000, 100000, 180);
    -- Birkaç SCHEDULED kayıt oluştur
    INSERT INTO loan_payments (payment_id, loan_id, due_date, scheduled_amount,
                               principal_portion, interest_portion, status)
    VALUES (seq_payment_id.NEXTVAL, v_loan_id, SYSDATE + 30, v_monthly_pay, 800, v_monthly_pay-800, 'SCHEDULED');
    INSERT INTO loan_payments (payment_id, loan_id, due_date, scheduled_amount,
                               principal_portion, interest_portion, status)
    VALUES (seq_payment_id.NEXTVAL, v_loan_id, SYSDATE - 30, v_monthly_pay, 800, v_monthly_pay-800, 'OVERDUE');
    pkg_loan_mgmt.charge_off_loan(v_loan_id, 'Waive test', 2000);
    SELECT COUNT(*) INTO v_count
    FROM   loan_payments
    WHERE  loan_id = v_loan_id AND status = 'WAIVED';
    ROLLBACK;
    IF v_count = 2 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_payments_waived|OK|waived:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_payments_waived|FAIL|expected:2 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_payments_waived|FAIL|' || SQLERRM);
  END;

  -- tc_07: PAID payments → WAIVED olmaz (sadece SCHEDULED+OVERDUE)
  BEGIN
    make_active_loan_dpd(1000, 100000, 180);
    INSERT INTO loan_payments (payment_id, loan_id, due_date, scheduled_amount,
                               paid_amount, principal_portion, interest_portion, status)
    VALUES (seq_payment_id.NEXTVAL, v_loan_id, SYSDATE - 60, v_monthly_pay,
            v_monthly_pay, 800, v_monthly_pay-800, 'PAID');
    pkg_loan_mgmt.charge_off_loan(v_loan_id, 'Paid preserve test', 2000);
    SELECT COUNT(*) INTO v_count
    FROM   loan_payments
    WHERE  loan_id = v_loan_id AND status = 'PAID';
    ROLLBACK;
    IF v_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_paid_not_waived|OK|paid_preserved:1');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_paid_not_waived|FAIL|expected:1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_paid_not_waived|FAIL|' || SQLERRM);
  END;

  -- tc_08: fraud_alert oluşur (LOAN_CHARGE_OFF, HIGH severity)
  BEGIN
    make_active_loan_dpd(1002, 100003, 200);
    pkg_loan_mgmt.charge_off_loan(v_loan_id, 'Fraud alert test', 2001);
     -- Daha guvenli kontrol:
    SELECT COUNT(*) INTO v_count
    FROM   fraud_alerts
    WHERE  alert_type = 'LOAN_CHARGE_OFF'
    AND    severity   = 'HIGH'
    AND    account_id = (SELECT account_id FROM loans WHERE loan_id = v_loan_id);
    ROLLBACK;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_fraud_alert_created|OK|count:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_fraud_alert_created|FAIL|expected:>=1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_fraud_alert_created|FAIL|' || SQLERRM);
  END;

  -- tc_09: fraud_alert description reason içeriyor
  BEGIN
    make_active_loan_dpd(1000, 100000, 180);
    pkg_loan_mgmt.charge_off_loan(v_loan_id, 'Bankruptcy filed', 2000);
    SELECT COUNT(*) INTO v_count
    FROM   fraud_alerts
    WHERE  alert_type   = 'LOAN_CHARGE_OFF'
    AND    description  LIKE '%Bankruptcy filed%'
    AND    account_id   = 100000;
    ROLLBACK;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_alert_description|OK|reason_in_description');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_alert_description|FAIL|expected:>=1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_alert_description|FAIL|' || SQLERRM);
  END;

  -- tc_10: Audit log oluşur
  DECLARE
    v_marker TIMESTAMP := SYSTIMESTAMP;
  BEGIN
    make_active_loan_dpd(1000, 100000, 180);
    pkg_loan_mgmt.charge_off_loan(v_loan_id, 'Audit test', 2000);
    SELECT COUNT(*) INTO v_count
    FROM   audit_log
    WHERE  table_name  = 'LOANS'
    AND    record_id   = v_loan_id
    AND    action      = 'UPDATE'
    AND    changed_at >= v_marker;
    ROLLBACK;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_audit_log|OK|count:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_audit_log|FAIL|expected:>=1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_audit_log|FAIL|' || SQLERRM);
  END;

  -- tc_11: Var olmayan loan_id → NO_DATA_FOUND
  BEGIN
    pkg_loan_mgmt.charge_off_loan(999999, 'Ghost loan', 2000);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_nonexistent_loan|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_nonexistent_loan|OK|no_data_found');
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_nonexistent_loan|FAIL|wrong_exception:' || SQLCODE);
  END;

END;
/