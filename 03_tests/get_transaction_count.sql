DECLARE
  v_result  NUMBER;
  v_today   DATE := TRUNC(SYSDATE);
  v_txn_id  NUMBER;
  v_ref     VARCHAR2(50);
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: Transaction yokken 0 döner
  BEGIN
    v_result := pkg_transactions.get_transaction_count(100000, v_today - 30, v_today);
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_no_transactions|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_no_transactions|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_no_transactions|FAIL|' || SQLERRM);
  END;

  -- tc_02: Tek transaction → 1 döner
  BEGIN
    pkg_transactions.deposit(100000, 500, 'Count test 1', 'BRANCH', 2000, v_txn_id, v_ref);
    v_result := pkg_transactions.get_transaction_count(100000, v_today, v_today);
    ROLLBACK;
    IF v_result = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_single_transaction|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_single_transaction|FAIL|expected:1 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_single_transaction|FAIL|' || SQLERRM);
  END;

  -- tc_03: Birden fazla transaction → doğru sayı döner
  BEGIN
    pkg_transactions.deposit(100001, 100, 'Count test A', 'BRANCH', 2000, v_txn_id, v_ref);
    pkg_transactions.deposit(100001, 200, 'Count test B', 'BRANCH', 2000, v_txn_id, v_ref);
    pkg_transactions.deposit(100001, 300, 'Count test C', 'BRANCH', 2000, v_txn_id, v_ref);
    v_result := pkg_transactions.get_transaction_count(100001, v_today, v_today);
    ROLLBACK;
    IF v_result = 3 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_multiple_transactions|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_multiple_transactions|FAIL|expected:3 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_multiple_transactions|FAIL|' || SQLERRM);
  END;

  -- tc_04: Tarih aralığı dışındaki transaction sayılmaz
  BEGIN
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, transaction_date
    ) VALUES (
        100002, 'DEPOSIT', 500, 2500, 3000,
        'TC04-OLD', 'BRANCH', 'COMPLETED',
        v_today - 40
    );
    v_result := pkg_transactions.get_transaction_count(100002, v_today - 30, v_today);
    ROLLBACK;
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_outside_date_range|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_outside_date_range|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_outside_date_range|FAIL|' || SQLERRM);
  END;

  -- tc_05: FAILED status → sayılmaz
  BEGIN
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, transaction_date
    ) VALUES (
        100002, 'DEPOSIT', 500, 2500, 3000,
        'TC05-FAIL', 'BRANCH', 'FAILED',
        v_today
    );
    v_result := pkg_transactions.get_transaction_count(100002, v_today, v_today);
    ROLLBACK;
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_failed_not_counted|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_failed_not_counted|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_failed_not_counted|FAIL|' || SQLERRM);
  END;

  -- tc_06: PENDING status → sayılmaz
  BEGIN
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, transaction_date
    ) VALUES (
        100002, 'DEPOSIT', 500, 2500, 3000,
        'TC06-PEND', 'BRANCH', 'PENDING',
        v_today
    );
    v_result := pkg_transactions.get_transaction_count(100002, v_today, v_today);
    ROLLBACK;
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_pending_not_counted|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_pending_not_counted|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_pending_not_counted|FAIL|' || SQLERRM);
  END;

  -- tc_07: Tam tarih sınırında (from_date = to_date = bugün) → sayılır
  BEGIN
    pkg_transactions.deposit(100003, 500, 'Boundary test', 'BRANCH', 2001, v_txn_id, v_ref);
    v_result := pkg_transactions.get_transaction_count(100003, v_today, v_today);
    ROLLBACK;
    IF v_result = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_exact_date_boundary|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_exact_date_boundary|FAIL|expected:1 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_exact_date_boundary|FAIL|' || SQLERRM);
  END;

  -- tc_08: Farklı account'ın transaction'ları sayılmaz (izolasyon)
  BEGIN
    pkg_transactions.deposit(100004, 500, 'Isolation test', 'BRANCH', 2002, v_txn_id, v_ref);
    v_result := pkg_transactions.get_transaction_count(100005, v_today, v_today);
    ROLLBACK;
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_account_isolation|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_account_isolation|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_account_isolation|FAIL|' || SQLERRM);
  END;

  -- tc_09: Var olmayan account_id → 0 döner (COUNT her zaman satır döner)
  BEGIN
    v_result := pkg_transactions.get_transaction_count(999999, v_today - 30, v_today);
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_nonexistent_account|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_nonexistent_account|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_nonexistent_account|FAIL|' || SQLERRM);
  END;

  -- tc_10: NULL account_id → 0 döner
  BEGIN
    v_result := pkg_transactions.get_transaction_count(NULL, v_today - 30, v_today);
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_null_account_id|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_null_account_id|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_null_account_id|FAIL|' || SQLERRM);
  END;

  -- tc_11: Geniş tarih aralığında birden fazla gün — önceki + bugünkü birlikte sayılır
  BEGIN
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, transaction_date
    ) VALUES (
        100005, 'DEPOSIT', 1000, 125000, 126000,
        'TC11-OLD', 'BRANCH', 'COMPLETED',
        v_today - 10
    );
    pkg_transactions.deposit(100005, 500, 'TC11-TODAY', 'BRANCH', 2000, v_txn_id, v_ref);
    v_result := pkg_transactions.get_transaction_count(100005, v_today - 30, v_today);
    ROLLBACK;
    IF v_result = 2 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_wide_date_range|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_wide_date_range|FAIL|expected:2 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_wide_date_range|FAIL|' || SQLERRM);
  END;

END;
/