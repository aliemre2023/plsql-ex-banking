DECLARE
  v_txn_id  NUMBER;
  v_balance NUMBER;
  v_count   NUMBER;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: İlk overdraft fee → uygulanır, txn_id döner
  BEGIN
    pkg_transactions.process_overdraft_fee(100000, v_txn_id);
    SELECT balance INTO v_balance FROM accounts WHERE account_id = 100000;
    ROLLBACK;
    IF v_txn_id IS NOT NULL AND v_balance = 4965 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_first_overdraft_fee|OK|txn_id:' || v_txn_id || ' balance:' || v_balance);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_first_overdraft_fee|FAIL|txn_id:' || v_txn_id || ' balance:' || v_balance);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_first_overdraft_fee|FAIL|' || SQLERRM);
  END;

  -- tc_02: Aynı gün ikinci overdraft → txn_id NULL döner, fee uygulanmaz
  BEGIN
    pkg_transactions.process_overdraft_fee(100001, v_txn_id); -- ilk
    DECLARE
      v_txn_id_2 NUMBER;
    BEGIN
      pkg_transactions.process_overdraft_fee(100001, v_txn_id_2); -- ikinci
      SELECT balance INTO v_balance FROM accounts WHERE account_id = 100001;
      ROLLBACK;
      IF v_txn_id_2 IS NULL AND v_balance = 14965 THEN
        -- sadece bir kez 35 düşmüş
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_same_day_no_duplicate|OK|txn_id_2:NULL balance:' || v_balance);
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_same_day_no_duplicate|FAIL|txn_id_2:' || v_txn_id_2 || ' balance:' || v_balance);
      END IF;
    END;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_same_day_no_duplicate|FAIL|' || SQLERRM);
  END;

  -- tc_03: Dünkü overdraft fee var → bugün yeni fee uygulanır
  BEGIN
    INSERT INTO fee_ledger (account_id, fee_type, fee_amount, fee_date, transaction_id)
    VALUES (100002, 'OVERDRAFT_FEE', 35, TRUNC(SYSDATE) - 1, NULL);
    pkg_transactions.process_overdraft_fee(100002, v_txn_id);
    ROLLBACK;
    IF v_txn_id IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_yesterday_fee_new_today|OK|txn_id:' || v_txn_id);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_yesterday_fee_new_today|FAIL|txn_id:NULL');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_yesterday_fee_new_today|FAIL|' || SQLERRM);
  END;

  -- tc_04: fee_ledger kaydı oluşur
  BEGIN
    pkg_transactions.process_overdraft_fee(100003, v_txn_id);
    SELECT COUNT(*) INTO v_count
    FROM   fee_ledger
    WHERE  account_id        = 100003
    AND    fee_type          = 'OVERDRAFT_FEE'
    AND    fee_amount        = 35
    AND    TRUNC(fee_date)   = TRUNC(SYSDATE)
    AND    transaction_id    = v_txn_id;
    ROLLBACK;
    IF v_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_fee_ledger_created|OK|count:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_fee_ledger_created|FAIL|expected:1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_fee_ledger_created|FAIL|' || SQLERRM);
  END;

  -- tc_05: Transaction FEE tipiyle SYSTEM channel'da oluşur
  BEGIN
    pkg_transactions.process_overdraft_fee(100004, v_txn_id);
    SELECT COUNT(*) INTO v_count
    FROM   transactions
    WHERE  transaction_id   = v_txn_id
    AND    transaction_type = 'FEE'
    AND    channel          = 'SYSTEM'
    AND    amount           = 35
    AND    status           = 'COMPLETED';
    ROLLBACK;
    IF v_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_txn_fields_correct|OK|fee:35 channel:SYSTEM');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_txn_fields_correct|FAIL|expected:1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_txn_fields_correct|FAIL|' || SQLERRM);
  END;

  -- tc_06: Farklı account'ların günlük sayacı birbirinden bağımsız
  BEGIN
    pkg_transactions.process_overdraft_fee(100000, v_txn_id); -- 100000 fee aldı
    DECLARE
      v_txn_id_other NUMBER;
    BEGIN
      pkg_transactions.process_overdraft_fee(100005, v_txn_id_other); -- 100005 ilk kez
      ROLLBACK;
      IF v_txn_id IS NOT NULL AND v_txn_id_other IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_account_isolation|OK|both_charged');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_account_isolation|FAIL|txn1:' || v_txn_id || ' txn2:' || v_txn_id_other);
      END IF;
    END;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_account_isolation|FAIL|' || SQLERRM);
  END;

  -- tc_07: Fee sonrası balance 35 azalır, available_balance de azalır
  BEGIN
    pkg_transactions.process_overdraft_fee(100005, v_txn_id);
    SELECT balance INTO v_balance FROM accounts WHERE account_id = 100005;
    ROLLBACK;
    IF v_balance = 124965 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_balance_reduced|OK|balance:' || v_balance);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_balance_reduced|FAIL|expected:124965 got:' || v_balance);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_balance_reduced|FAIL|' || SQLERRM);
  END;

  -- tc_08: Var olmayan account_id → exception (post_fee içinden)
  BEGIN
    pkg_transactions.process_overdraft_fee(999999, v_txn_id);
    ROLLBACK;
    -- post_fee içinde get_balance -20099 fırlatır ama EXCEPTION WHEN OTHERS THEN NULL yok
    -- burada exception beklenir
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_nonexistent_account|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20099 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_nonexistent_account|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_nonexistent_account|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

END;
/