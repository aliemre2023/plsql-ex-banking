DECLARE
  v_txn_id    NUMBER;
  v_ref       VARCHAR2(50);
  v_balance   NUMBER;
  v_avail     NUMBER;
  v_txn_count NUMBER;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: Normal withdraw → balance azalır, transaction oluşur
  BEGIN
    pkg_transactions.withdraw(100000, 1000, 'Test withdraw', 'BRANCH', 2000, v_txn_id, v_ref);
    SELECT balance INTO v_balance FROM accounts WHERE account_id = 100000;
    ROLLBACK;
    IF v_txn_id IS NOT NULL AND v_balance = 4000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path|OK|txn_id:' || v_txn_id || ' balance:' || v_balance);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path|FAIL|txn_id:' || v_txn_id || ' balance:' || v_balance);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path|FAIL|' || SQLERRM);
  END;

  -- tc_02: Transaction alanları doğru kaydedilir
  BEGIN
    pkg_transactions.withdraw(100001, 500, 'Field check', 'ONLINE', 2001, v_txn_id, v_ref);
    SELECT COUNT(*) INTO v_txn_count
    FROM   transactions
    WHERE  transaction_id   = v_txn_id
    AND    account_id       = 100001
    AND    transaction_type = 'WITHDRAWAL'
    AND    amount           = 500
    AND    balance_before   = 15000
    AND    balance_after    = 14500
    AND    channel          = 'ONLINE'
    AND    status           = 'COMPLETED'
    AND    processed_by     = 2001;
    ROLLBACK;
    IF v_txn_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_transaction_fields|OK|all_fields_correct');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_transaction_fields|FAIL|expected:1 got:' || v_txn_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_transaction_fields|FAIL|' || SQLERRM);
  END;

  -- tc_03: Reference WDR- prefix ile döner
  BEGIN
    pkg_transactions.withdraw(100002, 100, NULL, 'BRANCH', 2000, v_txn_id, v_ref);
    ROLLBACK;
    IF v_ref LIKE 'WDR-%' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_reference_prefix|OK|ref:' || v_ref);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_reference_prefix|FAIL|unexpected_ref:' || v_ref);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_reference_prefix|FAIL|' || SQLERRM);
  END;

  -- tc_04: NULL description → 'Cash Withdrawal' default
  BEGIN
    pkg_transactions.withdraw(100003, 200, NULL, 'BRANCH', 2001, v_txn_id, v_ref);
    SELECT COUNT(*) INTO v_txn_count
    FROM   transactions
    WHERE  transaction_id = v_txn_id
    AND    description    = 'Cash Withdrawal';
    ROLLBACK;
    IF v_txn_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_default_description|OK|description:Cash Withdrawal');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_default_description|FAIL|expected:1 got:' || v_txn_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_default_description|FAIL|' || SQLERRM);
  END;

  -- tc_05: Sıfır tutar → -20005 exception
  BEGIN
    pkg_transactions.withdraw(100000, 0, NULL, 'BRANCH', 2000, v_txn_id, v_ref);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_zero_amount|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20005 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_zero_amount|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_zero_amount|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_06: Negatif tutar → -20005 exception
  BEGIN
    pkg_transactions.withdraw(100000, -100, NULL, 'BRANCH', 2000, v_txn_id, v_ref);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_negative_amount|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20005 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_negative_amount|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_negative_amount|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_07: Yetersiz bakiye → -20001 exception
  BEGIN
    pkg_transactions.withdraw(100004, 9999, NULL, 'BRANCH', 2002, v_txn_id, v_ref);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_insufficient_funds|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20001 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_insufficient_funds|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_insufficient_funds|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_08: FROZEN account → -20002 exception
  BEGIN
    UPDATE accounts SET status = 'FROZEN' WHERE account_id = 100002;
    pkg_transactions.withdraw(100002, 100, NULL, 'BRANCH', 2000, v_txn_id, v_ref);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_frozen_account|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20002 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_frozen_account|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_frozen_account|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_09: CLOSED account → -20003 exception
  BEGIN
    UPDATE accounts SET status = 'CLOSED' WHERE account_id = 100002;
    pkg_transactions.withdraw(100002, 100, NULL, 'BRANCH', 2000, v_txn_id, v_ref);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_closed_account|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20003 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_closed_account|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_closed_account|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_10: Günlük limit aşımı → -20004 exception (limit=10000)
  -- 9500 + 600 = 10100 > 10000
  BEGIN
    pkg_transactions.withdraw(100005, 9500, 'First big withdrawal', 'BRANCH', 2000, v_txn_id, v_ref);
    pkg_transactions.withdraw(100005, 600, 'Limit exceed', 'BRANCH', 2000, v_txn_id, v_ref);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_daily_limit_exceeded|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20004 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_daily_limit_exceeded|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_daily_limit_exceeded|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_11: Tam günlük limitte (10000) → başarılı
  BEGIN
    pkg_transactions.withdraw(100005, 10000, 'Exact limit', 'BRANCH', 2000, v_txn_id, v_ref);
    ROLLBACK;
    IF v_txn_id IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_exact_daily_limit|OK|txn_id:' || v_txn_id);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_exact_daily_limit|FAIL|txn_id_null');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_exact_daily_limit|FAIL|' || SQLERRM);
  END;

  -- tc_12: Overdraft kullanımı → balance negatife düşer, overdraft fee oluşur
  -- CHECKING overdraft_limit=500, balance=800 → 800+500=1300 çekebilir
  BEGIN
    pkg_transactions.withdraw(100000, 1200, 'Overdraft test', 'BRANCH', 2000, v_txn_id, v_ref);
    SELECT balance INTO v_balance FROM accounts WHERE account_id = 100000;
    SELECT COUNT(*) INTO v_txn_count
    FROM   fee_ledger
    WHERE  account_id = 100000
    AND    fee_type   = 'OVERDRAFT_FEE';
    ROLLBACK;
    IF v_balance = 3800 AND v_txn_count = 0 THEN
      -- balance 5000-1200=3800, overdraft fee yok (negatife düşmedi)
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_within_balance_no_overdraft|OK|balance:' || v_balance);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_within_balance_no_overdraft|FAIL|balance:' || v_balance || ' fee_count:' || v_txn_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_within_balance_no_overdraft|FAIL|' || SQLERRM);
  END;

  -- tc_13: Balance negatife düşünce overdraft fee eklenir
  -- CHECKING balance=800, overdraft=500 → 5000+500=5500 max → 5300 çek → balance=-300
  BEGIN
    pkg_transactions.withdraw(100000, 5300, 'Overdraft fee test', 'BRANCH', 2000, v_txn_id, v_ref);
    SELECT balance INTO v_balance FROM accounts WHERE account_id = 100000;
    SELECT COUNT(*) INTO v_txn_count
    FROM   fee_ledger
    WHERE  account_id = 100000
    AND    fee_type   = 'OVERDRAFT_FEE';
    ROLLBACK;
    IF v_balance = -300 AND v_txn_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_overdraft_fee_charged|OK|balance:' || v_balance || ' fee_count:' || v_txn_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_overdraft_fee_charged|FAIL|balance:' || v_balance || ' fee_count:' || v_txn_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_overdraft_fee_charged|FAIL|' || SQLERRM);
  END;

  -- tc_14: available_balance de azalır
  BEGIN
    pkg_transactions.withdraw(100006, 5000, 'Avail test', 'BRANCH', 2000, v_txn_id, v_ref);
    SELECT available_balance INTO v_avail FROM accounts WHERE account_id = 100006;
    ROLLBACK;
    IF v_avail = 70000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_14_available_balance_updated|OK|available:' || v_avail);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_14_available_balance_updated|FAIL|expected:70000 got:' || v_avail);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_14_available_balance_updated|FAIL|' || SQLERRM);
  END;

  -- tc_15: Var olmayan account_id → exception (-20099)
  BEGIN
    pkg_transactions.withdraw(999999, 100, NULL, 'BRANCH', 2000, v_txn_id, v_ref);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_15_nonexistent_account|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20099 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_15_nonexistent_account|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_15_nonexistent_account|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

END;
/