DECLARE
  v_txn_id       NUMBER;
  v_ref          VARCHAR2(50);
  v_balance      NUMBER;
  v_txn_count    NUMBER;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: Normal deposit → transaction oluşur, bakiye artar
  BEGIN
    pkg_transactions.deposit(100000, 1000, 'Test deposit', 'BRANCH', 2000, v_txn_id, v_ref);
    SELECT balance INTO v_balance FROM accounts WHERE account_id = 100000;
    ROLLBACK;
    IF v_txn_id IS NOT NULL AND v_balance = 6000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path|OK|txn_id:' || v_txn_id || ' balance:' || v_balance);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path|FAIL|txn_id:' || v_txn_id || ' balance:' || v_balance);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path|FAIL|' || SQLERRM);
  END;

  -- tc_02: Transaction kaydı doğru alanlarla oluşur
  BEGIN
    pkg_transactions.deposit(100001, 500, 'Field check', 'ONLINE', 2001, v_txn_id, v_ref);
    SELECT COUNT(*) INTO v_txn_count
    FROM   transactions
    WHERE  transaction_id   = v_txn_id
    AND    account_id       = 100001
    AND    transaction_type = 'DEPOSIT'
    AND    amount           = 500
    AND    balance_before   = 15000
    AND    balance_after    = 15500
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

  -- tc_03: Reference number DEP- prefix ile döner
  BEGIN
    pkg_transactions.deposit(100002, 300, NULL, 'BRANCH', 2000, v_txn_id, v_ref);
    ROLLBACK;
    IF v_ref LIKE 'DEP-%' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_reference_prefix|OK|ref:' || v_ref);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_reference_prefix|FAIL|unexpected_ref:' || v_ref);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_reference_prefix|FAIL|' || SQLERRM);
  END;

  -- tc_04: NULL description → 'Cash Deposit' default kullanılır
  BEGIN
    pkg_transactions.deposit(100003, 200, NULL, 'BRANCH', 2001, v_txn_id, v_ref);
    SELECT COUNT(*) INTO v_txn_count
    FROM   transactions
    WHERE  transaction_id = v_txn_id
    AND    description    = 'Cash Deposit';
    ROLLBACK;
    IF v_txn_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_default_description|OK|description:Cash Deposit');
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
    pkg_transactions.deposit(100000, 0, NULL, 'BRANCH', 2000, v_txn_id, v_ref);
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
    pkg_transactions.deposit(100000, -500, NULL, 'BRANCH', 2000, v_txn_id, v_ref);
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

  -- tc_07: FROZEN account → -20003 exception
  BEGIN
    UPDATE accounts SET status = 'FROZEN' WHERE account_id = 100004;
    pkg_transactions.deposit(100004, 500, NULL, 'BRANCH', 2000, v_txn_id, v_ref);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_frozen_account|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20003 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_frozen_account|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_frozen_account|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_08: CLOSED account → -20003 exception
  BEGIN
    UPDATE accounts SET status = 'CLOSED' WHERE account_id = 100004;
    pkg_transactions.deposit(100004, 500, NULL, 'BRANCH', 2000, v_txn_id, v_ref);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_closed_account|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20003 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_closed_account|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_closed_account|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_09: Var olmayan account_id → exception (get_balance'dan -20099)
  BEGIN
    pkg_transactions.deposit(999999, 500, NULL, 'BRANCH', 2000, v_txn_id, v_ref);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_nonexistent_account|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20099 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_nonexistent_account|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_nonexistent_account|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_10: available_balance de güncellenir
  DECLARE
    v_avail NUMBER;
  BEGIN
    pkg_transactions.deposit(100005, 5000, 'Avail test', 'BRANCH', 2000, v_txn_id, v_ref);
    SELECT available_balance INTO v_avail FROM accounts WHERE account_id = 100005;
    ROLLBACK;
    IF v_avail = 130000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_available_balance_updated|OK|available:' || v_avail);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_available_balance_updated|FAIL|expected:130000 got:' || v_avail);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_available_balance_updated|FAIL|' || SQLERRM);
  END;

  -- tc_11: NULL employee_id geçerli (default NULL)
  BEGIN
    pkg_transactions.deposit(100006, 1000, NULL, 'MOBILE', NULL, v_txn_id, v_ref);
    SELECT COUNT(*) INTO v_txn_count
    FROM   transactions
    WHERE  transaction_id = v_txn_id
    AND    processed_by   IS NULL;
    ROLLBACK;
    IF v_txn_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_null_employee_id|OK|processed_by:NULL');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_null_employee_id|FAIL|expected:1 got:' || v_txn_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_null_employee_id|FAIL|' || SQLERRM);
  END;

  -- tc_12: Büyük tutar (>= 9999) → fraud alert oluşur
  BEGIN
    pkg_transactions.deposit(100003, 9999, 'Large deposit', 'BRANCH', 2001, v_txn_id, v_ref);
    SELECT COUNT(*) INTO v_txn_count
    FROM   fraud_alerts
    WHERE  transaction_id = v_txn_id
    AND    alert_type     = 'LARGE_TRANSACTION';
    ROLLBACK;
    IF v_txn_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_fraud_alert_large|OK|alert_created');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_fraud_alert_large|FAIL|expected:1 got:' || v_txn_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_fraud_alert_large|FAIL|' || SQLERRM);
  END;

  -- tc_13: Farklı channel değerleri geçerli (ATM, ONLINE, MOBILE)
  BEGIN
    pkg_transactions.deposit(100000, 100, 'ATM deposit', 'ATM', NULL, v_txn_id, v_ref);
    SELECT COUNT(*) INTO v_txn_count
    FROM   transactions
    WHERE  transaction_id = v_txn_id
    AND    channel        = 'ATM';
    ROLLBACK;
    IF v_txn_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_atm_channel|OK|channel:ATM');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_atm_channel|FAIL|expected:1 got:' || v_txn_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_atm_channel|FAIL|' || SQLERRM);
  END;

END;
/