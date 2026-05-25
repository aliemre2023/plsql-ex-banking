DECLARE
  v_result NUMBER;
  v_txn_id NUMBER;
  v_ref    VARCHAR2(50);
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: Transaction yokken 0 döner (NVL devreye girer)
  BEGIN
    v_result := pkg_transactions.get_customer_daily_deposits(1000);
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_no_deposits|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_no_deposits|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_no_deposits|FAIL|' || SQLERRM);
  END;

  -- tc_02: Tek deposit → doğru toplam döner
  BEGIN
    pkg_transactions.deposit(100000, 1500, 'Daily test', 'BRANCH', 2000, v_txn_id, v_ref);
    v_result := pkg_transactions.get_customer_daily_deposits(1000); -- Alice customer_id=1000
    ROLLBACK;
    IF v_result = 1500 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_single_deposit|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_single_deposit|FAIL|expected:1500 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_single_deposit|FAIL|' || SQLERRM);
  END;

  -- tc_03: Aynı müşterinin birden fazla account'ına deposit → toplam döner
  -- Alice'in iki hesabı var: 100000 ve 100001
  BEGIN
    pkg_transactions.deposit(100000, 1000, 'Multi acct A', 'BRANCH', 2000, v_txn_id, v_ref);
    pkg_transactions.deposit(100001, 2000, 'Multi acct B', 'BRANCH', 2000, v_txn_id, v_ref);
    v_result := pkg_transactions.get_customer_daily_deposits(1000);
    ROLLBACK;
    IF v_result = 3000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_multi_account_sum|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_multi_account_sum|FAIL|expected:3000 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_multi_account_sum|FAIL|' || SQLERRM);
  END;

  -- tc_04: WITHDRAWAL tipi hariç tutulur — sadece DEPOSIT sayılır
  BEGIN
    pkg_transactions.deposit(100002, 1000, 'Deposit only', 'BRANCH', 2000, v_txn_id, v_ref);
    pkg_transactions.withdraw(100002, 200, 'Withdrawal exclude', 'BRANCH', 2000, v_txn_id, v_ref);
    v_result := pkg_transactions.get_customer_daily_deposits(1001); -- Bob customer_id=1001
    ROLLBACK;
    IF v_result = 1000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_excludes_withdrawal|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_excludes_withdrawal|FAIL|expected:1000 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_excludes_withdrawal|FAIL|' || SQLERRM);
  END;

  -- tc_05: Dünkü deposit sayılmaz — sadece bugün
  BEGIN
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, transaction_date
    ) VALUES (
        100003, 'DEPOSIT', 5000, 50000, 55000,
        'TC05-YEST', 'BRANCH', 'COMPLETED',
        TRUNC(SYSDATE) - 1 + INTERVAL '10' HOUR
    );
    v_result := pkg_transactions.get_customer_daily_deposits(1002); -- Carol customer_id=1002
    ROLLBACK;
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_excludes_yesterday|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_excludes_yesterday|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_excludes_yesterday|FAIL|' || SQLERRM);
  END;

  -- tc_06: FAILED status hariç tutulur
  BEGIN
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, transaction_date
    ) VALUES (
        100003, 'DEPOSIT', 3000, 50000, 53000,
        'TC06-FAIL', 'BRANCH', 'FAILED',
        TRUNC(SYSDATE) + INTERVAL '10' HOUR
    );
    v_result := pkg_transactions.get_customer_daily_deposits(1002);
    ROLLBACK;
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_excludes_failed|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_excludes_failed|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_excludes_failed|FAIL|' || SQLERRM);
  END;

  -- tc_07: Var olmayan customer_id → 0 döner (NVL)
  BEGIN
    v_result := pkg_transactions.get_customer_daily_deposits(999999);
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_nonexistent_customer|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_nonexistent_customer|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_nonexistent_customer|FAIL|' || SQLERRM);
  END;

  -- tc_08: NULL customer_id → 0 döner (NVL)
  BEGIN
    v_result := pkg_transactions.get_customer_daily_deposits(NULL);
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_null_customer_id|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_null_customer_id|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_null_customer_id|FAIL|' || SQLERRM);
  END;

  -- tc_09: Farklı müşterinin deposit'i sayılmaz (izolasyon)
  BEGIN
    pkg_transactions.deposit(100004, 2000, 'Other customer', 'BRANCH', 2002, v_txn_id, v_ref);
    v_result := pkg_transactions.get_customer_daily_deposits(1002); -- Carol, Bob'un değil
    ROLLBACK;
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_customer_isolation|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_customer_isolation|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_customer_isolation|FAIL|' || SQLERRM);
  END;

  -- tc_10: VIP müşteri (Eve) — iki account'a büyük deposit → toplam doğru
  -- Eve: customer_id=1004, account_id=100005 ve 100006
  BEGIN
    pkg_transactions.deposit(100005, 30000, 'Eve acct1', 'BRANCH', 2000, v_txn_id, v_ref);
    pkg_transactions.deposit(100006, 20000, 'Eve acct2', 'BRANCH', 2000, v_txn_id, v_ref);
    v_result := pkg_transactions.get_customer_daily_deposits(1004);
    ROLLBACK;
    IF v_result = 50000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_vip_multi_account|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_vip_multi_account|FAIL|expected:50000 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_vip_multi_account|FAIL|' || SQLERRM);
  END;

END;
/