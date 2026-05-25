DECLARE
  v_txn_id   NUMBER;
  v_ref      VARCHAR2(50);
  v_count    NUMBER;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: Büyük tutar (>= 9999) → LARGE_TRANSACTION alert oluşur
  BEGIN
    pkg_transactions.deposit(100003, 9999, 'Large deposit test', 'BRANCH', 2000, v_txn_id, v_ref);
    SELECT COUNT(*) INTO v_count
    FROM   fraud_alerts
    WHERE  account_id    = 100003
    AND    alert_type    = 'LARGE_TRANSACTION'
    AND    transaction_id = v_txn_id;
    ROLLBACK;
    IF v_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_large_txn_alert|OK|alert_created');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_large_txn_alert|FAIL|expected:1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_large_txn_alert|FAIL|' || SQLERRM);
  END;

  -- tc_02: Çok büyük tutar (>= 50000) → severity HIGH olur
  BEGIN
    pkg_transactions.deposit(100005, 50000, 'Very large deposit', 'BRANCH', 2000, v_txn_id, v_ref);
    SELECT COUNT(*) INTO v_count
    FROM   fraud_alerts
    WHERE  account_id    = 100005
    AND    alert_type    = 'LARGE_TRANSACTION'
    AND    severity      = 'HIGH'
    AND    transaction_id = v_txn_id;
    ROLLBACK;
    IF v_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_high_severity_alert|OK|severity:HIGH');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_high_severity_alert|FAIL|expected:1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_high_severity_alert|FAIL|' || SQLERRM);
  END;

  -- tc_03: 9999 < tutar < 50000 → severity MEDIUM olur
  BEGIN
    pkg_transactions.deposit(100003, 10000, 'Medium large deposit', 'BRANCH', 2000, v_txn_id, v_ref);
    SELECT COUNT(*) INTO v_count
    FROM   fraud_alerts
    WHERE  account_id    = 100003
    AND    alert_type    = 'LARGE_TRANSACTION'
    AND    severity      = 'MEDIUM'
    AND    transaction_id = v_txn_id;
    ROLLBACK;
    IF v_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_medium_severity_alert|OK|severity:MEDIUM');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_medium_severity_alert|FAIL|expected:1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_medium_severity_alert|FAIL|' || SQLERRM);
  END;

  -- tc_04: Küçük tutar (< 9999) → LARGE_TRANSACTION alert oluşmaz
  BEGIN
    pkg_transactions.deposit(100002, 500, 'Small deposit', 'BRANCH', 2000, v_txn_id, v_ref);
    SELECT COUNT(*) INTO v_count
    FROM   fraud_alerts
    WHERE  transaction_id = v_txn_id
    AND    alert_type     = 'LARGE_TRANSACTION';
    ROLLBACK;
    IF v_count = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_no_alert_small_amount|OK|no_alert_created');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_no_alert_small_amount|FAIL|expected:0 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_no_alert_small_amount|FAIL|' || SQLERRM);
  END;

  -- tc_05: Structuring — günlük deposit 8000-10000 arası → STRUCTURING_SUSPICION alert
  BEGIN
    -- Önce 8500 yatır (8000 üstü yapmak için)
    pkg_transactions.deposit(100002, 8500, 'First deposit', 'BRANCH', 2000, v_txn_id, v_ref);
    -- İkinci deposit → structuring tetiklenmeli
    pkg_transactions.deposit(100002, 500, 'Second deposit structuring', 'BRANCH', 2000, v_txn_id, v_ref);
    SELECT COUNT(*) INTO v_count
    FROM   fraud_alerts
    WHERE  account_id = 100002
    AND    alert_type = 'STRUCTURING_SUSPICION';
    ROLLBACK;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_structuring_alert|OK|alert_count:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_structuring_alert|FAIL|expected:>=1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_structuring_alert|FAIL|' || SQLERRM);
  END;

  -- tc_06: WITHDRAWAL tipi → structuring kuralı tetiklenmez (sadece DEPOSIT için)
  BEGIN
    pkg_transactions.deposit(100004, 8500, 'Setup deposit', 'BRANCH', 2000, v_txn_id, v_ref);
    pkg_transactions.withdraw(100004, 500, 'Withdrawal test', 'BRANCH', 2000, v_txn_id, v_ref);
    SELECT COUNT(*) INTO v_count
    FROM   fraud_alerts
    WHERE  account_id = 100004
    AND    alert_type = 'STRUCTURING_SUSPICION'
    AND    transaction_id = v_txn_id;
    ROLLBACK;
    IF v_count = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_no_structuring_on_withdrawal|OK|no_structuring_alert');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_no_structuring_on_withdrawal|FAIL|expected:0 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_no_structuring_on_withdrawal|FAIL|' || SQLERRM);
  END;

  -- tc_07: Fraud check exception yutulur — deposit başarıyla tamamlanır
  -- (WHEN OTHERS THEN NULL garantisi)
  BEGIN
    pkg_transactions.deposit(100000, 9999, 'Fraud check swallow test', 'BRANCH', 2000, v_txn_id, v_ref);
    ROLLBACK;
    IF v_txn_id IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_fraud_exception_swallowed|OK|txn_completed:' || v_txn_id);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_fraud_exception_swallowed|FAIL|txn_id_null');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_fraud_exception_swallowed|FAIL|' || SQLERRM);
  END;

END;
/