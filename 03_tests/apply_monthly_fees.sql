DECLARE
  v_fees_applied NUMBER;
  v_total_fees   NUMBER;
  v_count        NUMBER;
  v_balance      NUMBER;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: Tüm CHECKING min_balance=0 → balance>=0*5=0 → waived → 0 fee
  BEGIN
    pkg_transactions.apply_monthly_fees(SYSDATE, v_fees_applied, v_total_fees);
    IF v_fees_applied = 0 AND v_total_fees = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_checking_waived_zero_min|OK|applied:' || v_fees_applied);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_checking_waived_zero_min|FAIL|applied:' || v_fees_applied || ' total:' || v_total_fees);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_checking_waived_zero_min|FAIL|' || SQLERRM);
  END;

  -- tc_02: BUSINESS account (monthly_fee=15, min_balance=2500) eklenir
  -- balance=3000 → 3000 >= 2500*5=12500? HAYIR → fee uygulanır
  BEGIN
    INSERT INTO accounts (account_number, customer_id, branch_id, account_type,
                          balance, available_balance, status)
    VALUES ('TEST-BUS-001', 1000, 10, 'BUSINESS', 3000, 3000, 'ACTIVE');
    pkg_transactions.apply_monthly_fees(SYSDATE, v_fees_applied, v_total_fees);
    ROLLBACK;
    IF v_fees_applied = 1 AND v_total_fees = 15 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_business_fee_applied|OK|applied:' || v_fees_applied || ' total:' || v_total_fees);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_business_fee_applied|FAIL|applied:' || v_fees_applied || ' total:' || v_total_fees);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_business_fee_applied|FAIL|' || SQLERRM);
  END;

  -- tc_03: Yüksek balance → waived (balance >= min_balance*5)
  -- BUSINESS min_balance=2500, min*5=12500 → balance=15000 >= 12500 → waived
  BEGIN
    INSERT INTO accounts (account_number, customer_id, branch_id, account_type,
                          balance, available_balance, status)
    VALUES ('TEST-BUS-002', 1001, 10, 'BUSINESS', 15000, 15000, 'ACTIVE');
    pkg_transactions.apply_monthly_fees(SYSDATE, v_fees_applied, v_total_fees);
    ROLLBACK;
    IF v_fees_applied = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_high_balance_waived|OK|applied:' || v_fees_applied);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_high_balance_waived|FAIL|expected:0 got:' || v_fees_applied);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_high_balance_waived|FAIL|' || SQLERRM);
  END;

  -- tc_04: Aynı ay için tekrar çalıştırılınca fee tekrar uygulanmaz
  BEGIN
    INSERT INTO accounts (account_number, customer_id, branch_id, account_type,
                          balance, available_balance, status)
    VALUES ('TEST-BUS-003', 1002, 10, 'BUSINESS', 3000, 3000, 'ACTIVE');
    -- İlk çalıştırma
    pkg_transactions.apply_monthly_fees(SYSDATE, v_fees_applied, v_total_fees);
    DECLARE
      v_first NUMBER := v_fees_applied;
    BEGIN
      -- İkinci çalıştırma
      pkg_transactions.apply_monthly_fees(SYSDATE, v_fees_applied, v_total_fees);
      ROLLBACK;
      IF v_fees_applied = 0 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_no_duplicate_fee|OK|second_run:' || v_fees_applied);
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
    INSERT INTO accounts (account_number, customer_id, branch_id, account_type,
                          balance, available_balance, status)
    VALUES ('TEST-BUS-004', 1003, 11, 'BUSINESS', 3000, 3000, 'ACTIVE');
    pkg_transactions.apply_monthly_fees(SYSDATE, v_fees_applied, v_total_fees);
    SELECT COUNT(*) INTO v_count
    FROM   fee_ledger fl
    JOIN   accounts a ON fl.account_id = a.account_id
    WHERE  a.account_number = 'TEST-BUS-004'
    AND    fl.fee_type      = 'MONTHLY_FEE'
    AND    fl.fee_amount    = 15;
    ROLLBACK;
    IF v_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_fee_ledger_created|OK|count:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_fee_ledger_created|FAIL|expected:1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_fee_ledger_created|FAIL|' || SQLERRM);
  END;

  -- tc_06: INACTIVE account → fee uygulanmaz
  BEGIN
    INSERT INTO accounts (account_number, customer_id, branch_id, account_type,
                          balance, available_balance, status)
    VALUES ('TEST-BUS-005', 1004, 10, 'BUSINESS', 3000, 3000, 'INACTIVE');
    pkg_transactions.apply_monthly_fees(SYSDATE, v_fees_applied, v_total_fees);
    ROLLBACK;
    IF v_fees_applied = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_inactive_skipped|OK|applied:' || v_fees_applied);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_inactive_skipped|FAIL|expected:0 got:' || v_fees_applied);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_inactive_skipped|FAIL|' || SQLERRM);
  END;

  -- tc_07: p_fees_applied ve p_total_fees sıfırlanır
  BEGIN
    v_fees_applied := 999;
    v_total_fees   := 999;
    pkg_transactions.apply_monthly_fees(SYSDATE, v_fees_applied, v_total_fees);
    IF v_fees_applied = 0 AND v_total_fees = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_out_params_initialized|OK|applied:0 total:0');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_out_params_initialized|FAIL|applied:' || v_fees_applied || ' total:' || v_total_fees);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_out_params_initialized|FAIL|' || SQLERRM);
  END;

  -- tc_08: Balance fee sonrası azalır
  BEGIN
    INSERT INTO accounts (account_number, customer_id, branch_id, account_type,
                          balance, available_balance, status)
    VALUES ('TEST-BUS-006', 1000, 10, 'BUSINESS', 3000, 3000, 'ACTIVE');
    pkg_transactions.apply_monthly_fees(SYSDATE, v_fees_applied, v_total_fees);
    SELECT balance INTO v_balance
    FROM   accounts WHERE account_number = 'TEST-BUS-006';
    ROLLBACK;
    IF v_balance = 2985 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_balance_reduced|OK|balance:' || v_balance);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_balance_reduced|FAIL|expected:2985 got:' || v_balance);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_balance_reduced|FAIL|' || SQLERRM);
  END;

  -- tc_09: Birden fazla eligible account → toplam doğru
  BEGIN
    INSERT INTO accounts (account_number, customer_id, branch_id, account_type,
                          balance, available_balance, status)
    VALUES ('TEST-BUS-007', 1001, 10, 'BUSINESS', 3000, 3000, 'ACTIVE');
    INSERT INTO accounts (account_number, customer_id, branch_id, account_type,
                          balance, available_balance, status)
    VALUES ('TEST-BUS-008', 1002, 11, 'BUSINESS', 4000, 4000, 'ACTIVE');
    pkg_transactions.apply_monthly_fees(SYSDATE, v_fees_applied, v_total_fees);
    ROLLBACK;
    IF v_fees_applied = 2 AND v_total_fees = 30 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_multiple_accounts|OK|applied:' || v_fees_applied || ' total:' || v_total_fees);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_multiple_accounts|FAIL|applied:' || v_fees_applied || ' total:' || v_total_fees);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_multiple_accounts|FAIL|' || SQLERRM);
  END;

END;
/