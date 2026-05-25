DECLARE
  v_debit_id  NUMBER;
  v_credit_id NUMBER;
  v_ref       VARCHAR2(50);
  v_from_bal  NUMBER;
  v_to_bal    NUMBER;
  v_count     NUMBER;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: Normal transfer → kaynak azalır, hedef artar
  BEGIN
    pkg_transactions.transfer(100000, 100002, 1000, 'Test transfer', 'ONLINE', 2000,
                              v_debit_id, v_credit_id, v_ref);
    SELECT balance INTO v_from_bal FROM accounts WHERE account_id = 100000;
    SELECT balance INTO v_to_bal   FROM accounts WHERE account_id = 100002;
    ROLLBACK;
    IF v_from_bal = 4000 AND v_to_bal = 3500 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path|OK|from:' || v_from_bal || ' to:' || v_to_bal);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path|FAIL|from:' || v_from_bal || ' to:' || v_to_bal);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path|FAIL|' || SQLERRM);
  END;

  -- tc_02: İki transaction oluşur (TRANSFER_OUT + TRANSFER_IN)
  BEGIN
    pkg_transactions.transfer(100001, 100003, 500, NULL, 'ONLINE', 2001,
                              v_debit_id, v_credit_id, v_ref);
    SELECT COUNT(*) INTO v_count
    FROM   transactions
    WHERE  transaction_id IN (v_debit_id, v_credit_id);
    ROLLBACK;
    IF v_count = 2 AND v_debit_id IS NOT NULL AND v_credit_id IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_two_transactions|OK|debit:' || v_debit_id || ' credit:' || v_credit_id);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_two_transactions|FAIL|count:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_two_transactions|FAIL|' || SQLERRM);
  END;

  -- tc_03: TRANSFER_OUT ve TRANSFER_IN tipleri doğru kaydedilir
  BEGIN
    pkg_transactions.transfer(100000, 100002, 200, NULL, 'ONLINE', 2000,
                              v_debit_id, v_credit_id, v_ref);
    SELECT COUNT(*) INTO v_count
    FROM   transactions
    WHERE  transaction_id = v_debit_id AND transaction_type = 'TRANSFER_OUT'
    AND    account_id = 100000 AND related_account_id = 100002;
    ROLLBACK;
    IF v_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_txn_types_correct|OK|transfer_out_correct');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_txn_types_correct|FAIL|expected:1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_txn_types_correct|FAIL|' || SQLERRM);
  END;

  -- tc_04: Reference TRF- prefix, credit 'IN-TRF-' prefix
  BEGIN
    pkg_transactions.transfer(100003, 100004, 100, NULL, 'ONLINE', 2001,
                              v_debit_id, v_credit_id, v_ref);
    DECLARE
      v_credit_ref VARCHAR2(50);
    BEGIN
      SELECT reference_number INTO v_credit_ref
      FROM   transactions WHERE transaction_id = v_credit_id;
      ROLLBACK;
      IF v_ref LIKE 'TRF-%' AND v_credit_ref LIKE 'IN-TRF-%' THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_reference_format|OK|ref:' || v_ref);
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_reference_format|FAIL|ref:' || v_ref || ' credit_ref:' || v_credit_ref);
      END IF;
    END;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_reference_format|FAIL|' || SQLERRM);
  END;

  -- tc_05: Sıfır tutar → -20005 exception
  BEGIN
    pkg_transactions.transfer(100000, 100002, 0, NULL, 'ONLINE', 2000,
                              v_debit_id, v_credit_id, v_ref);
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

  -- tc_06: Aynı account → -20025 exception
  BEGIN
    pkg_transactions.transfer(100000, 100000, 500, NULL, 'ONLINE', 2000,
                              v_debit_id, v_credit_id, v_ref);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_same_account|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20025 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_same_account|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_same_account|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_07: Transfer limit aşımı (> 50000) → -20004 exception
  BEGIN
    pkg_transactions.transfer(100005, 100006, 50001, NULL, 'ONLINE', 2000,
                              v_debit_id, v_credit_id, v_ref);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_transfer_limit|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20004 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_transfer_limit|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_transfer_limit|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_08: Günlük limit aşımı → -20004 exception
  BEGIN
    pkg_transactions.withdraw(100005, 9500, 'Pre-withdraw', 'BRANCH', 2000, v_debit_id, v_ref);
    pkg_transactions.transfer(100005, 100006, 600, NULL, 'ONLINE', 2000,
                              v_debit_id, v_credit_id, v_ref);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_daily_limit|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20004 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_daily_limit|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_daily_limit|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_09: Yetersiz bakiye → -20001 exception
  BEGIN
    pkg_transactions.transfer(100004, 100002, 9000, NULL, 'ONLINE', 2002,
                              v_debit_id, v_credit_id, v_ref);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_insufficient_funds|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20001 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_insufficient_funds|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_insufficient_funds|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_10: FROZEN kaynak account → -20002 exception
  BEGIN
    UPDATE accounts SET status = 'FROZEN' WHERE account_id = 100002;
    pkg_transactions.transfer(100002, 100003, 500, NULL, 'ONLINE', 2000,
                              v_debit_id, v_credit_id, v_ref);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_frozen_source|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20002 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_frozen_source|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_frozen_source|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_11: NULL description → default mesaj kullanılır
  BEGIN
    pkg_transactions.transfer(100001, 100003, 300, NULL, 'ONLINE', 2001,
                              v_debit_id, v_credit_id, v_ref);
    SELECT COUNT(*) INTO v_count
    FROM   transactions
    WHERE  transaction_id = v_debit_id
    AND    description    = 'Transfer to account 100003';
    ROLLBACK;
    IF v_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_default_description|OK|description_correct');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_default_description|FAIL|expected:1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_default_description|FAIL|' || SQLERRM);
  END;

  -- tc_12: FX transfer — farklı currency → converted_amount farklı, FX fee oluşur
  BEGIN
    UPDATE accounts SET currency = 'EUR' WHERE account_id = 100002;
    pkg_transactions.transfer(100000, 100002, 1000, 'FX transfer', 'ONLINE', 2000,
                              v_debit_id, v_credit_id, v_ref);
    -- credit txn amount EUR cinsinden olmalı (1000 * 0.921 = 921.00)
    SELECT COUNT(*) INTO v_count
    FROM   transactions
    WHERE  transaction_id = v_credit_id
    AND    amount         = 921.00;
    -- FX fee oluşmuş mu
    DECLARE v_fee_count NUMBER; BEGIN
      SELECT COUNT(*) INTO v_fee_count
      FROM   fee_ledger
      WHERE  account_id = 100000
      AND    fee_type   = 'FOREIGN_TXN_FEE';
      ROLLBACK;
      IF v_count = 1 AND v_fee_count = 1 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_fx_transfer|OK|converted:921.00 fee_created');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_fx_transfer|FAIL|credit_match:' || v_count || ' fee:' || v_fee_count);
      END IF;
    END;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_fx_transfer|FAIL|' || SQLERRM);
  END;

  -- tc_13: Ters sıralı account ID'ler — deadlock prevention (from > to)
  -- 100003 > 100001 → önce 100001 lock alınır
  BEGIN
    pkg_transactions.transfer(100003, 100001, 200, 'Reverse order', 'ONLINE', 2001,
                              v_debit_id, v_credit_id, v_ref);
    SELECT balance INTO v_from_bal FROM accounts WHERE account_id = 100003;
    SELECT balance INTO v_to_bal   FROM accounts WHERE account_id = 100001;
    ROLLBACK;
    IF v_from_bal = 49800 AND v_to_bal = 15200 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_reverse_account_order|OK|from:' || v_from_bal || ' to:' || v_to_bal);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_reverse_account_order|FAIL|from:' || v_from_bal || ' to:' || v_to_bal);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_reverse_account_order|FAIL|' || SQLERRM);
  END;

END;
/