DECLARE
  v_loan_id     NUMBER;
  v_loan_number VARCHAR2(50);
  v_monthly_pay NUMBER;
  v_decision    VARCHAR2(20);
  v_count       NUMBER;
  v_status      VARCHAR2(20);
  v_rate        NUMBER;
  v_balance     NUMBER;

  PROCEDURE originate(
    p_customer_id IN NUMBER,
    p_account_id  IN NUMBER,
    p_loan_type   IN VARCHAR2,
    p_amount      IN NUMBER,
    p_term        IN NUMBER
  ) IS
  BEGIN
    pkg_loan_mgmt.originate_loan(
        p_customer_id     => p_customer_id,
        p_account_id      => p_account_id,
        p_branch_id       => 10,
        p_loan_type       => p_loan_type,
        p_amount          => p_amount,
        p_term_months     => p_term,
        p_collateral_type => NULL,
        p_collateral_val  => NULL,
        p_employee_id     => 2000,
        p_loan_id         => v_loan_id,
        p_loan_number     => v_loan_number,
        p_monthly_payment => v_monthly_pay,
        p_decision        => v_decision
    );
  END;

BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: APPROVED → loan kaydı oluşur, status=APPROVED
  BEGIN
    originate(1000, 100000, 'PERSONAL', 5000, 12);
    SELECT status INTO v_status FROM loans WHERE loan_id = v_loan_id;
    ROLLBACK;
    IF v_status = 'APPROVED' AND v_decision = 'APPROVED' AND v_loan_id IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_approved|OK|loan_id:' || v_loan_id || ' status:' || v_status);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_approved|FAIL|status:' || v_status || ' decision:' || v_decision);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_approved|FAIL|' || SQLERRM);
  END;

  -- tc_02: REVIEW decision → status=PENDING
  -- David risk_level=HIGH → REVIEW
  BEGIN
    originate(1003, 100004, 'PERSONAL', 3000, 12);
    SELECT status INTO v_status FROM loans WHERE loan_id = v_loan_id;
    ROLLBACK;
    IF v_status = 'PENDING' AND v_decision = 'REVIEW' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_review_pending|OK|status:PENDING decision:REVIEW');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_review_pending|FAIL|status:' || v_status || ' decision:' || v_decision);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_review_pending|FAIL|' || SQLERRM);
  END;

  -- tc_03: REJECTED → status=REJECTED
  BEGIN
    UPDATE customers SET credit_score = 400 WHERE customer_id = 1001;
    originate(1001, 100002, 'PERSONAL', 5000, 12);
    SELECT status INTO v_status FROM loans WHERE loan_id = v_loan_id;
    ROLLBACK;
    IF v_status = 'REJECTED' AND v_decision = 'REJECTED' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_rejected|OK|status:REJECTED');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_rejected|FAIL|status:' || v_status || ' decision:' || v_decision);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_rejected|FAIL|' || SQLERRM);
  END;

  -- tc_04: Loan number formatı '{LOAN_TYPE}-{8 haneli seq}'
  BEGIN
    originate(1000, 100000, 'PERSONAL', 5000, 12);
    ROLLBACK;
    IF REGEXP_LIKE(v_loan_number, '^PERSONAL-\d{8}$') THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_loan_number_format|OK|loan_number:' || v_loan_number);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_loan_number_format|FAIL|unexpected:' || v_loan_number);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_loan_number_format|FAIL|' || SQLERRM);
  END;

  -- tc_05: monthly_payment doğru hesaplanır
  -- Alice (780) → PERSONAL 12 ay → rate = determine_interest_rate(780,'PERSONAL',12)
  BEGIN
    v_rate := pkg_loan_mgmt.determine_interest_rate(780, 'PERSONAL', 12);
    originate(1000, 100000, 'PERSONAL', 5000, 12);
    ROLLBACK;
    IF v_monthly_pay = pkg_loan_mgmt.calc_monthly_payment(5000, v_rate, 12) THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_monthly_payment_correct|OK|payment:' || v_monthly_pay);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_monthly_payment_correct|FAIL|expected:' ||
        pkg_loan_mgmt.calc_monthly_payment(5000, v_rate, 12) || ' got:' || v_monthly_pay);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_monthly_payment_correct|FAIL|' || SQLERRM);
  END;

  -- tc_06: principal_amount = outstanding_balance = p_amount
  BEGIN
    originate(1000, 100000, 'AUTO', 20000, 36);
    SELECT COUNT(*) INTO v_count
    FROM   loans
    WHERE  loan_id           = v_loan_id
    AND    principal_amount  = 20000
    AND    outstanding_balance = 20000;
    ROLLBACK;
    IF v_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_balance_equals_amount|OK|principal=outstanding=20000');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_balance_equals_amount|FAIL|expected:1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_balance_equals_amount|FAIL|' || SQLERRM);
  END;

  -- tc_07: maturity_date = ADD_MONTHS(SYSDATE, term_months)
  BEGIN
    originate(1000, 100000, 'PERSONAL', 5000, 24);
    SELECT COUNT(*) INTO v_count
    FROM   loans
    WHERE  loan_id      = v_loan_id
    AND    TRUNC(maturity_date) = TRUNC(ADD_MONTHS(SYSDATE, 24));
    ROLLBACK;
    IF v_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_maturity_date|OK|maturity:24 months from now');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_maturity_date|FAIL|expected:1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_maturity_date|FAIL|' || SQLERRM);
  END;

  -- tc_08: credit_score_at_origination kaydedilir
  BEGIN
    originate(1000, 100000, 'PERSONAL', 5000, 12);
    SELECT COUNT(*) INTO v_count
    FROM   loans
    WHERE  loan_id                   = v_loan_id
    AND    credit_score_at_origination = 780;
    ROLLBACK;
    IF v_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_credit_score_saved|OK|score:780');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_credit_score_saved|FAIL|expected:1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_credit_score_saved|FAIL|' || SQLERRM);
  END;

  -- tc_09: collateral_type ve collateral_value kaydedilir
  BEGIN
    pkg_loan_mgmt.originate_loan(
        p_customer_id     => 1000,
        p_account_id      => 100000,
        p_branch_id       => 10,
        p_loan_type       => 'MORTGAGE',
        p_amount          => 150000,
        p_term_months     => 360,
        p_collateral_type => 'REAL_ESTATE',
        p_collateral_val  => 200000,
        p_employee_id     => 2000,
        p_loan_id         => v_loan_id,
        p_loan_number     => v_loan_number,
        p_monthly_payment => v_monthly_pay,
        p_decision        => v_decision
    );
    SELECT COUNT(*) INTO v_count
    FROM   loans
    WHERE  loan_id         = v_loan_id
    AND    collateral_type = 'REAL_ESTATE'
    AND    collateral_value = 200000;
    ROLLBACK;
    IF v_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_collateral_saved|OK|type:REAL_ESTATE val:200000');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_collateral_saved|FAIL|expected:1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_collateral_saved|FAIL|' || SQLERRM);
  END;

  -- tc_10: approved_by = p_employee_id
  BEGIN
    originate(1000, 100000, 'PERSONAL', 5000, 12);
    SELECT COUNT(*) INTO v_count
    FROM   loans
    WHERE  loan_id     = v_loan_id
    AND    approved_by = 2000;
    ROLLBACK;
    IF v_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_approved_by|OK|employee:2000');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_approved_by|FAIL|expected:1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_approved_by|FAIL|' || SQLERRM);
  END;

  -- tc_11: Audit log kaydı oluşur (AUTONOMOUS)
  DECLARE
    v_marker TIMESTAMP := SYSTIMESTAMP;
  BEGIN
    originate(1000, 100000, 'PERSONAL', 5000, 12);
    SELECT COUNT(*) INTO v_count
    FROM   audit_log
    WHERE  table_name  = 'LOANS'
    AND    record_id   = v_loan_id
    AND    action      = 'INSERT'
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

  -- tc_12: Var olmayan customer_id → exception (customers tablosundan)
  BEGIN
    pkg_loan_mgmt.originate_loan(
        p_customer_id => 999999, p_account_id => 100000,
        p_branch_id   => 10, p_loan_type => 'PERSONAL',
        p_amount      => 5000, p_term_months => 12,
        p_employee_id => 2000,
        p_loan_id => v_loan_id, p_loan_number => v_loan_number,
        p_monthly_payment => v_monthly_pay, p_decision => v_decision
    );
    ROLLBACK;
    -- loan_eligibility_check NO_DATA_FOUND → REJECTED → loan yine oluşabilir
    IF v_decision = 'REJECTED' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_nonexistent_customer|OK|decision:REJECTED');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_nonexistent_customer|FAIL|decision:' || v_decision);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = 100 OR SQLCODE = -1403 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_nonexistent_customer|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_nonexistent_customer|FAIL|' || SQLERRM);
      END IF;
  END;

END;
/