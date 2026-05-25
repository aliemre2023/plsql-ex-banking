DECLARE
  v_txn_id    NUMBER;
  v_ref       VARCHAR2(50);
  v_rev_id    NUMBER;
  v_balance   NUMBER;
  v_status    VARCHAR2(20);
  v_count     NUMBER;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: DEPOSIT reverse → balance azalır, orijinal REVERSED olur
  BEGIN
    pkg_transactions.deposit(100000, 1000, 'Reverse test', 'BRANCH', 2000, v_txn_id, v_ref);
    pkg_transactions.reverse_transaction(v_txn_id, 'Test reason', 2000, v_rev_id);
    SELECT balance INTO v_balance FROM accounts WHERE account_id = 100000;
    SELECT status  INTO v_status  FROM transactions WHERE transaction_id = v_txn_id;
    ROLLBACK;
    IF v_balance = 5000 AND v_status = 'REVERSED' AND v_rev_id IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_reverse_deposit|OK|balance:' || v_balance || ' status:' || v_status);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_reverse_deposit|FAIL|balance:' || v_balance || ' status:' || v_status);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_reverse_deposit|FAIL|' || SQLERRM);
  END;

  -- tc_02: WITHDRAWAL reverse → balance artar
  BEGIN
    pkg_transactions.withdraw(100001, 500, 'Reverse withdraw', 'BRANCH', 2000, v_txn_id, v_ref);
    pkg_transactions.reverse_transaction(v_txn_id, 'Reverse test', 2000, v_rev_id);
    SELECT balance INTO v_balance FROM accounts WHERE account_id = 100001;
    ROLLBACK;
    IF v_balance = 15000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_reverse_withdrawal|OK|balance:' || v_balance);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_reverse_withdrawal|FAIL|expected:15000 got:' || v_balance);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_reverse_withdrawal|FAIL|' || SQLERRM);
  END;

  -- tc_03: Reversal transaction kaydı doğru oluşur
  BEGIN
    pkg_transactions.deposit(100002, 300, 'Rev fields test', 'BRANCH', 2001, v_txn_id, v_ref);
    pkg_transactions.reverse_transaction(v_txn_id, 'Field check', 2001, v_rev_id);
    SELECT COUNT(*) INTO v_count
    FROM   transactions
    WHERE  transaction_id   = v_rev_id
    AND    transaction_type = 'REVERSAL'
    AND    reversal_of      = v_txn_id
    AND    status           = 'COMPLETED'
    AND    processed_by     = 2001
    AND    reference_number LIKE 'REV-%';
    ROLLBACK;
    IF v_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_reversal_record|OK|all_fields_correct');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_reversal_record|FAIL|expected:1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_reversal_record|FAIL|' || SQLERRM);
  END;

  -- tc_04: Description 'Reversal of TXN#X - reason' formatında
  BEGIN
    pkg_transactions.deposit(100003, 200, 'Desc test', 'BRANCH', 2001, v_txn_id, v_ref);
    pkg_transactions.reverse_transaction(v_txn_id, 'My reason', 2001, v_rev_id);
    SELECT COUNT(*) INTO v_count
    FROM   transactions
    WHERE  transaction_id = v_rev_id
    AND    description    = 'Reversal of TXN#' || v_txn_id || ' - My reason';
    ROLLBACK;
    IF v_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_description_format|OK|description_correct');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_description_format|FAIL|expected:1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_description_format|FAIL|' || SQLERRM);
  END;

  -- tc_05: Zaten reverse edilmiş → -20031 exception
  BEGIN
    pkg_transactions.deposit(100004, 500, 'Already rev test', 'BRANCH', 2002, v_txn_id, v_ref);
    pkg_transactions.reverse_transaction(v_txn_id, 'First reversal', 2002, v_rev_id);
    pkg_transactions.reverse_transaction(v_txn_id, 'Second reversal', 2002, v_rev_id);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_already_reversed|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20031 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_already_reversed|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_already_reversed|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_06: 24 saat penceresi dışı → -20030 exception
  BEGIN
    pkg_transactions.deposit(100005, 500, 'Old txn test', 'BRANCH', 2000, v_txn_id, v_ref);
    UPDATE transactions
    SET    transaction_date = SYSTIMESTAMP - INTERVAL '25' HOUR
    WHERE  transaction_id = v_txn_id;
    pkg_transactions.reverse_transaction(v_txn_id, 'Too old', 2000, v_rev_id);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_outside_window|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20030 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_outside_window|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_outside_window|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_07: REVERSAL tipi reverse edilemez → -20030 exception
  BEGIN
    pkg_transactions.deposit(100006, 500, 'Rev type test', 'BRANCH', 2000, v_txn_id, v_ref);
    UPDATE transactions SET transaction_type = 'REVERSAL' WHERE transaction_id = v_txn_id;
    pkg_transactions.reverse_transaction(v_txn_id, 'Reverse reversal', 2000, v_rev_id);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_reversal_type|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20030 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_reversal_type|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_reversal_type|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_08: FEE tipi reverse edilemez → -20030 exception
  BEGIN
    pkg_transactions.deposit(100000, 500, 'Fee type test', 'BRANCH', 2000, v_txn_id, v_ref);
    UPDATE transactions SET transaction_type = 'FEE' WHERE transaction_id = v_txn_id;
    pkg_transactions.reverse_transaction(v_txn_id, 'Reverse fee', 2000, v_rev_id);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_fee_type|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20030 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_fee_type|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_fee_type|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_09: INTEREST tipi reverse edilemez → -20030 exception
  BEGIN
    pkg_transactions.deposit(100001, 500, 'Interest type test', 'BRANCH', 2000, v_txn_id, v_ref);
    UPDATE transactions SET transaction_type = 'INTEREST' WHERE transaction_id = v_txn_id;
    pkg_transactions.reverse_transaction(v_txn_id, 'Reverse interest', 2000, v_rev_id);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_interest_type|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20030 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_interest_type|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_interest_type|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_10: Var olmayan transaction_id → -20030 exception (is_reversible FALSE döner)
  BEGIN
    pkg_transactions.reverse_transaction(999999, 'Ghost txn', 2000, v_rev_id);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_nonexistent_txn|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20030 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_nonexistent_txn|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_nonexistent_txn|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_11: TRANSFER_OUT reverse → balance artar (CR yapılır)
  DECLARE
    v_debit_id  NUMBER;
    v_credit_id NUMBER;
  BEGIN
    pkg_transactions.transfer(100000, 100002, 500, NULL, 'ONLINE', 2000,
                              v_debit_id, v_credit_id, v_ref);
    pkg_transactions.reverse_transaction(v_debit_id, 'Transfer reverse', 2000, v_rev_id);
    SELECT balance INTO v_balance FROM accounts WHERE account_id = 100000;
    ROLLBACK;
    IF v_balance = 5000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_reverse_transfer_out|OK|balance:' || v_balance);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_reverse_transfer_out|FAIL|expected:5000 got:' || v_balance);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_reverse_transfer_out|FAIL|' || SQLERRM);
  END;

  -- tc_12: Audit log kaydı oluşur (AUTONOMOUS TRANSACTION)
  DECLARE
    v_marker TIMESTAMP := SYSTIMESTAMP;
  BEGIN
    pkg_transactions.deposit(100003, 400, 'Audit test', 'BRANCH', 2001, v_txn_id, v_ref);
    pkg_transactions.reverse_transaction(v_txn_id, 'Audit check', 2001, v_rev_id);
    SELECT COUNT(*) INTO v_count
    FROM   audit_log
    WHERE  table_name  = 'TRANSACTIONS'
    AND    record_id   = v_txn_id
    AND    action      = 'UPDATE'
    AND    changed_at >= v_marker;
    ROLLBACK;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_audit_log_created|OK|count:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_audit_log_created|FAIL|expected:>=1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_audit_log_created|FAIL|' || SQLERRM);
  END;

END;
/