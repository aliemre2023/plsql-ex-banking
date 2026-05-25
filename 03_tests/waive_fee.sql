DECLARE
  v_txn_id  NUMBER;
  v_fee_id  NUMBER;
  v_balance NUMBER;
  v_waived  CHAR(1);
  v_count   NUMBER;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: FEE reversal tasarım gereği engellenir → -20030
  BEGIN
    pkg_transactions.post_fee(100000, 'WIRE_FEE', NULL, NULL, 2000, v_txn_id);
    SELECT fee_id INTO v_fee_id FROM fee_ledger
    WHERE  transaction_id = v_txn_id AND account_id = 100000;
    pkg_transactions.waive_fee(v_fee_id, 'Customer request', 2000);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20030 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_02: FEE reversal tasarım gereği engellenir → -20030
  BEGIN
    pkg_transactions.post_fee(100001, 'ATM_FEE', NULL, NULL, 2001, v_txn_id);
    SELECT fee_id INTO v_fee_id FROM fee_ledger
    WHERE  transaction_id = v_txn_id AND account_id = 100001;
    pkg_transactions.waive_fee(v_fee_id, 'Good customer', 2001);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_waive_fields_correct|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20030 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_waive_fields_correct|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_waive_fields_correct|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_03: FEE reversal tasarım gereği engellenir → -20030
  BEGIN
    pkg_transactions.post_fee(100002, 'NSF_FEE', NULL, NULL, 2000, v_txn_id);
    SELECT fee_id INTO v_fee_id FROM fee_ledger
    WHERE  transaction_id = v_txn_id AND account_id = 100002;
    pkg_transactions.waive_fee(v_fee_id, 'First waive', 2000);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_already_waived|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20030 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_already_waived|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_already_waived|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_04: Var olmayan fee_id → -20036 exception
  BEGIN
    pkg_transactions.waive_fee(999999, 'Ghost fee', 2000);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_nonexistent_fee|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20036 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_nonexistent_fee|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_nonexistent_fee|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_05: NULL fee_id → -20036 exception
  BEGIN
    pkg_transactions.waive_fee(NULL, 'Null fee', 2000);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_null_fee_id|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20036 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_null_fee_id|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_null_fee_id|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_06: FEE reversal tasarım gereği engellenir → -20030
  BEGIN
    pkg_transactions.post_fee(100003, 'OVERDRAFT_FEE', NULL, NULL, 2001, v_txn_id);
    SELECT fee_id INTO v_fee_id FROM fee_ledger
    WHERE  transaction_id = v_txn_id AND account_id = 100003;
    pkg_transactions.waive_fee(v_fee_id, 'Reversal check', 2001);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_reversal_created|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20030 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_reversal_created|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_reversal_created|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_07: FEE reversal tasarım gereği engellenir → -20030
  BEGIN
    pkg_transactions.post_fee(100004, 'ATM_FEE', NULL, NULL, 2002, v_txn_id);
    SELECT fee_id INTO v_fee_id FROM fee_ledger
    WHERE  transaction_id = v_txn_id AND account_id = 100004;
    pkg_transactions.waive_fee(v_fee_id, 'Status check', 2002);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_original_txn_reversed|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20030 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_original_txn_reversed|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_original_txn_reversed|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_08: FEE reversal tasarım gereği engellenir → -20030
  BEGIN
    pkg_transactions.post_fee(100005, 'OVERDRAFT_FEE', 500, 'Big fee', 2000, v_txn_id);
    SELECT fee_id INTO v_fee_id FROM fee_ledger
    WHERE  transaction_id = v_txn_id AND account_id = 100005;
    pkg_transactions.waive_fee(v_fee_id, 'Big waive', 2000);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_balance_fully_restored|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20030 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_balance_fully_restored|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_balance_fully_restored|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

END;
/