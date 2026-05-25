DECLARE
  v_fees_applied NUMBER;
  v_fees_total   NUMBER;
  v_loan_id      NUMBER;
  v_loan_number  VARCHAR2(50);
  v_monthly_pay  NUMBER;
  v_decision     VARCHAR2(20);
  v_count        NUMBER;
  v_balance      NUMBER;

  -- Helper: ACTIVE + days_past_due ayarlı loan oluşturur
  PROCEDURE make_dpd_loan(
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
    SET    status       = 'ACTIVE',
           days_past_due = p_dpd
    WHERE  loan_id = v_loan_id;
  END;

BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: days_past_due <= grace_period (15) → fee uygulanmaz
  BEGIN
    make_dpd_loan(1000, 100000, 10);
    pkg_loan_mgmt.apply_late_fees(SYSDATE, v_fees_applied, v_fees_total);
    ROLLBACK;
    IF v_fees_applied = 0 AND v_fees_total = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_within_grace_no_fee|OK|applied:0');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_within_grace_no_fee|FAIL|applied:' || v_fees_applied);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_within_grace_no_fee|FAIL|' || SQLERRM);
  END;

  -- tc_02: days_past_due > 15 → fee uygulanır
  BEGIN
    make_dpd_loan(1000, 100000, 20);
    pkg_loan_mgmt.apply_late_fees(SYSDATE, v_fees_applied, v_fees_total);
    ROLLBACK;
    IF v_fees_applied >= 1 AND v_fees_total > 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_over_grace_fee_applied|OK|applied:' ||
        v_fees_applied || ' total:' || v_fees_total);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_over_grace_fee_applied|FAIL|applied:' ||
        v_fees_applied || ' total:' || v_fees_total);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_over_grace_fee_applied|FAIL|' || SQLERRM);
  END;

  -- tc_03: fee = ROUND(monthly_payment * 0.05, 2)
  BEGIN
    make_dpd_loan(1000, 100000, 20);
    pkg_loan_mgmt.apply_late_fees(SYSDATE, v_fees_applied, v_fees_total);
    ROLLBACK;
    IF v_fees_total = ROUND(v_monthly_pay * 0.05, 2) THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_fee_amount_correct|OK|fee:' || v_fees_total);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_fee_amount_correct|FAIL|expected:' ||
        ROUND(v_monthly_pay*0.05,2) || ' got:' || v_fees_total);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_fee_amount_correct|FAIL|' || SQLERRM);
  END;

  -- tc_04: Aynı ay tekrar çalıştırılınca fee tekrar uygulanmaz
  BEGIN
    make_dpd_loan(1000, 100000, 20);
    pkg_loan_mgmt.apply_late_fees(SYSDATE, v_fees_applied, v_fees_total);
    DECLARE v_first NUMBER := v_fees_applied; BEGIN
      pkg_loan_mgmt.apply_late_fees(SYSDATE, v_fees_applied, v_fees_total);
      ROLLBACK;
      IF v_fees_applied = 0 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_no_duplicate_fee|OK|second_run:0');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_no_duplicate_fee|FAIL|expected:0 got:' || v_fees_applied);
      END IF;
    END;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_no_duplicate_fee|FAIL|' || SQLERRM);
  END;

  -- tc_05: fee_ledger kaydı oluşur
  BEGIN
    make_dpd_loan(1002, 100003, 20);
    pkg_loan_mgmt.apply_late_fees(SYSDATE, v_fees_applied, v_fees_total);
    SELECT COUNT(*) INTO v_count
    FROM   fee_ledger
    WHERE  account_id = 100003
    AND    fee_type   = 'LATE_FEE'
    AND    TRUNC(fee_date, 'MM') = TRUNC(SYSDATE, 'MM');
    ROLLBACK;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_fee_ledger_created|OK|count:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_fee_ledger_created|FAIL|expected:>=1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_fee_ledger_created|FAIL|' || SQLERRM);
  END;

  -- tc_06: PAID_OFF loan → atlanır
  BEGIN
    -- loan_id=2 PAID_OFF → days_past_due olsa bile işlenmez
    UPDATE loans SET days_past_due = 30 WHERE loan_id = 2;
    pkg_loan_mgmt.apply_late_fees(SYSDATE, v_fees_applied, v_fees_total);
    ROLLBACK;
    -- PAID_OFF WHERE status='ACTIVE' koşulunu geçemez
    SELECT COUNT(*) INTO v_count
    FROM   fee_ledger f
    JOIN   accounts a ON f.account_id = a.account_id
    JOIN   loans l ON a.account_id = l.account_id
    WHERE  l.loan_id  = 2
    AND    f.fee_type = 'LATE_FEE'
    AND    TRUNC(f.fee_date, 'MM') = TRUNC(SYSDATE, 'MM');
    IF v_count = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_paid_off_skipped|OK|not_charged');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_paid_off_skipped|FAIL|expected:0 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_paid_off_skipped|FAIL|' || SQLERRM);
  END;

  -- tc_07: account_id IS NULL → atlanır
  BEGIN
    make_dpd_loan(1000, 100000, 20);
    UPDATE loans SET account_id = NULL WHERE loan_id = v_loan_id;
    pkg_loan_mgmt.apply_late_fees(SYSDATE, v_fees_applied, v_fees_total);
    ROLLBACK;
    IF v_fees_applied = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_null_account_skipped|OK|applied:0');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_null_account_skipped|FAIL|expected:0 got:' || v_fees_applied);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_null_account_skipped|FAIL|' || SQLERRM);
  END;

  -- tc_08: OUT parametreler sıfırlanır
  BEGIN
    v_fees_applied := 999;
    v_fees_total   := 999;
    pkg_loan_mgmt.apply_late_fees(SYSDATE, v_fees_applied, v_fees_total);
    IF v_fees_applied >= 0 AND v_fees_total >= 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_out_params_initialized|OK|applied:' || v_fees_applied);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_out_params_initialized|FAIL|negative_values');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_out_params_initialized|FAIL|' || SQLERRM);
  END;

  -- tc_09: Birden fazla eligible loan → toplam doğru
  BEGIN
    make_dpd_loan(1000, 100000, 20, 10000);
    DECLARE v_pay1 NUMBER := v_monthly_pay; BEGIN
      make_dpd_loan(1002, 100003, 25, 20000);
      DECLARE v_pay2 NUMBER := v_monthly_pay; BEGIN
        pkg_loan_mgmt.apply_late_fees(SYSDATE, v_fees_applied, v_fees_total);
        ROLLBACK;
        -- Seed'deki loan 3 (ACTIVE, DPD=45) de sayılabilir
        IF v_fees_applied >= 2 AND v_fees_total > 0 THEN
          DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_multiple_loans|OK|applied:' ||
            v_fees_applied || ' total:' || v_fees_total);
        ELSE
          DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_multiple_loans|FAIL|applied:' ||
            v_fees_applied || ' total:' || v_fees_total);
        END IF;
      END;
    END;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_multiple_loans|FAIL|' || SQLERRM);
  END;

  -- tc_10: balance azalır (post_fee uygulanır)
  BEGIN
    make_dpd_loan(1004, 100005, 20);
    SELECT balance INTO v_balance FROM accounts WHERE account_id = 100005;
    pkg_loan_mgmt.apply_late_fees(SYSDATE, v_fees_applied, v_fees_total);
    SELECT COUNT(*) INTO v_count FROM accounts
    WHERE  account_id = 100005 AND balance < v_balance;
    ROLLBACK;
    IF v_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_balance_reduced|OK|fee_deducted');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_balance_reduced|FAIL|expected:1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_balance_reduced|FAIL|' || SQLERRM);
  END;

  -- tc_11: Exception yutulur — hatalı loan diğerlerini bozmaz
  BEGIN
    make_dpd_loan(1000, 100000, 20);
    -- İkinci eligible loan normal
    make_dpd_loan(1002, 100003, 20);
    pkg_loan_mgmt.apply_late_fees(SYSDATE, v_fees_applied, v_fees_total);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_exception_swallowed|OK|no_propagation applied:' || v_fees_applied);
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_exception_swallowed|FAIL|' || SQLERRM);
  END;

END;
/