DECLARE
  v_loan_id     NUMBER;
  v_loan_number VARCHAR2(50);
  v_monthly_pay NUMBER;
  v_decision    VARCHAR2(20);
  v_status      VARCHAR2(20);
  v_count       NUMBER;

  -- Helper: belirli status'ta loan oluşturur
  PROCEDURE make_loan(
    p_customer_id IN NUMBER,
    p_account_id  IN NUMBER,
    p_status      IN VARCHAR2 DEFAULT 'PENDING'
  ) IS
  BEGIN
    pkg_loan_mgmt.originate_loan(
        p_customer_id => p_customer_id, p_account_id => p_account_id,
        p_branch_id => 10, p_loan_type => 'PERSONAL',
        p_amount => 5000, p_term_months => 12,
        p_employee_id => 2000,
        p_loan_id => v_loan_id, p_loan_number => v_loan_number,
        p_monthly_payment => v_monthly_pay, p_decision => v_decision
    );
    UPDATE loans SET status = p_status WHERE loan_id = v_loan_id;
  END;

BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: PENDING → reject → status=REJECTED
  BEGIN
    make_loan(1003, 100004, 'PENDING');
    pkg_loan_mgmt.reject_loan(v_loan_id, 'Credit risk', 2000);
    SELECT status INTO v_status FROM loans WHERE loan_id = v_loan_id;
    ROLLBACK;
    IF v_status = 'REJECTED' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_pending_rejected|OK|status:REJECTED');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_pending_rejected|FAIL|expected:REJECTED got:' || v_status);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_pending_rejected|FAIL|' || SQLERRM);
  END;

  -- tc_02: APPROVED → reject → status=REJECTED
  BEGIN
    make_loan(1000, 100000, 'APPROVED');
    pkg_loan_mgmt.reject_loan(v_loan_id, 'Policy exception', 2001);
    SELECT status INTO v_status FROM loans WHERE loan_id = v_loan_id;
    ROLLBACK;
    IF v_status = 'REJECTED' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_approved_rejected|OK|status:REJECTED');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_approved_rejected|FAIL|expected:REJECTED got:' || v_status);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_approved_rejected|FAIL|' || SQLERRM);
  END;

  -- tc_03: ACTIVE loan → -20056 exception
  BEGIN
    make_loan(1003, 100004, 'ACTIVE');
    pkg_loan_mgmt.reject_loan(v_loan_id, 'Test', 2000);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_active_cannot_reject|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20056 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_active_cannot_reject|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_active_cannot_reject|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_04: REJECTED loan → -20056 exception (zaten rejected)
  BEGIN
    make_loan(1003, 100004, 'REJECTED');
    pkg_loan_mgmt.reject_loan(v_loan_id, 'Double reject', 2000);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_rejected_cannot_reject|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20056 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_rejected_cannot_reject|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_rejected_cannot_reject|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_05: PAID_OFF loan → -20056 exception
  BEGIN
    make_loan(1000, 100000, 'PAID_OFF');
    pkg_loan_mgmt.reject_loan(v_loan_id, 'Test', 2000);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_paid_off_cannot_reject|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20056 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_paid_off_cannot_reject|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_paid_off_cannot_reject|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_06: updated_at güncellenir
  BEGIN
    make_loan(1003, 100004, 'PENDING');
    DECLARE v_before TIMESTAMP;
    BEGIN
      SELECT updated_at INTO v_before FROM loans WHERE loan_id = v_loan_id;
      DBMS_LOCK.SLEEP(1); -- 1 sn bekle
      pkg_loan_mgmt.reject_loan(v_loan_id, 'Timestamp test', 2000);
      SELECT COUNT(*) INTO v_count
      FROM   loans
      WHERE  loan_id    = v_loan_id
      AND    updated_at > v_before;
      ROLLBACK;
      IF v_count = 1 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_updated_at_changed|OK|updated_at_newer');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_updated_at_changed|FAIL|expected:1 got:' || v_count);
      END IF;
    END;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_updated_at_changed|FAIL|' || SQLERRM);
  END;

  -- tc_07: Audit log oluşur, old_values='status=PENDING'
  DECLARE
    v_marker TIMESTAMP := SYSTIMESTAMP;
  BEGIN
    make_loan(1003, 100004, 'PENDING');
    pkg_loan_mgmt.reject_loan(v_loan_id, 'Audit check', 2000);
    SELECT COUNT(*) INTO v_count
    FROM   audit_log
    WHERE  table_name          = 'LOANS'
    AND    record_id           = v_loan_id
    AND    action              = 'UPDATE'
    AND    TO_CHAR(old_values) = 'status=PENDING'
    AND    changed_at         >= v_marker;
    ROLLBACK;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_audit_old_values|OK|count:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_audit_old_values|FAIL|expected:>=1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_audit_old_values|FAIL|' || SQLERRM);
  END;

  -- tc_08: Audit new_values reason ve employee içeriyor
  DECLARE
    v_marker TIMESTAMP := SYSTIMESTAMP;
  BEGIN
    make_loan(1000, 100000, 'APPROVED');
    pkg_loan_mgmt.reject_loan(v_loan_id, 'DTI too high', 2001);
    SELECT COUNT(*) INTO v_count
    FROM   audit_log
    WHERE  table_name          = 'LOANS'
    AND    record_id           = v_loan_id
    AND    TO_CHAR(new_values) LIKE '%DTI too high%'
    AND    TO_CHAR(new_values) LIKE '%2001%'
    AND    changed_at         >= v_marker;
    ROLLBACK;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_audit_new_values|OK|reason_and_employee_in_log');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_audit_new_values|FAIL|expected:>=1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_audit_new_values|FAIL|' || SQLERRM);
  END;

  -- tc_09: Var olmayan loan_id → NO_DATA_FOUND
  BEGIN
    pkg_loan_mgmt.reject_loan(999999, 'Ghost loan', 2000);
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

  -- tc_10: NULL loan_id → NO_DATA_FOUND
  BEGIN
    pkg_loan_mgmt.reject_loan(NULL, 'Null test', 2000);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_null_loan_id|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_null_loan_id|OK|no_data_found');
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_null_loan_id|FAIL|wrong_exception:' || SQLCODE);
  END;

END;
/