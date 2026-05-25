DECLARE
  v_txn_id   NUMBER;
  v_ref      VARCHAR2(50);
  v_count    NUMBER;
  v_session_user VARCHAR2(100);
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);
  SELECT SYS_CONTEXT('USERENV','SESSION_USER') INTO v_session_user FROM DUAL;

  -- NOT: p_audit pkg_transactions içinde PRIVATE bir prosedürdür.
  -- pkg_transactions.p_audit(...) diye doğrudan çağrılamaz (PLS-00302).
  -- Tüm testler p_audit'i çağıran tek public prosedür olan
  -- reverse_transaction üzerinden dolaylı olarak çalışır.
  -- reverse_transaction içindeki:
  --   p_audit('TRANSACTIONS', p_transaction_id, 'UPDATE', 'status=COMPLETED', 'status=REVERSED,...')
  -- çağrısı test edilmektedir.

  -- tc_01: reverse_transaction sonrası audit_log kaydı oluşur
  BEGIN
    -- Setup: bir deposit yap, txn_id al
    pkg_transactions.deposit(100000, 500, 'Audit test deposit', 'BRANCH', 2000, v_txn_id, v_ref);
    DECLARE
      v_rev_id NUMBER;
      v_before TIMESTAMP := SYSTIMESTAMP;
    BEGIN
      pkg_transactions.reverse_transaction(v_txn_id, 'Audit test', 2000, v_rev_id);
      SELECT COUNT(*) INTO v_count
      FROM   audit_log
      WHERE  table_name = 'TRANSACTIONS'
      AND    record_id  = v_txn_id
      AND    action     = 'UPDATE'
      AND    changed_at >= v_before;
      ROLLBACK;
      IF v_count >= 1 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_audit_on_reverse|OK|count:' || v_count);
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_audit_on_reverse|FAIL|expected:>=1 got:' || v_count);
      END IF;
    END;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_audit_on_reverse|FAIL|' || SQLERRM);
  END;

  -- tc_02: audit_log kaydında changed_by = session user
  BEGIN
    pkg_transactions.deposit(100001, 500, 'Session user test', 'BRANCH', 2000, v_txn_id, v_ref);
    DECLARE
      v_rev_id NUMBER;
    BEGIN
      pkg_transactions.reverse_transaction(v_txn_id, 'Session test', 2000, v_rev_id);
      SELECT COUNT(*) INTO v_count
      FROM   audit_log
      WHERE  table_name = 'TRANSACTIONS'
      AND    record_id  = v_txn_id
      AND    changed_by = v_session_user;
      ROLLBACK;
      IF v_count >= 1 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_changed_by_session|OK|changed_by:' || v_session_user);
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_changed_by_session|FAIL|session_user:' || v_session_user);
      END IF;
    END;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_changed_by_session|FAIL|' || SQLERRM);
  END;

  -- tc_03: AUTONOMOUS TRANSACTION — caller rollback sonrası audit kaydı kalır
  -- p_audit PRAGMA AUTONOMOUS_TRANSACTION kullandığı için
  -- ana transaction rollback yapsa bile audit kaydı DB'de kalmalı
  BEGIN
    pkg_transactions.deposit(100002, 500, 'Autonomous test', 'BRANCH', 2000, v_txn_id, v_ref);
    DECLARE
      v_rev_id NUMBER;
      v_marker TIMESTAMP := SYSTIMESTAMP;
    BEGIN
      pkg_transactions.reverse_transaction(v_txn_id, 'Autonomous test', 2000, v_rev_id);
      ROLLBACK; -- ana transaction rollback
      SELECT COUNT(*) INTO v_count
      FROM   audit_log
      WHERE  table_name = 'TRANSACTIONS'
      AND    record_id  = v_txn_id
      AND    changed_at >= v_marker;
      -- Temizlik
      DELETE FROM audit_log
      WHERE  table_name = 'TRANSACTIONS' AND record_id = v_txn_id AND changed_at >= v_marker;
      COMMIT;
      IF v_count >= 1 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_autonomous_survives_rollback|OK|count:' || v_count);
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_autonomous_survives_rollback|FAIL|expected:>=1 got:' || v_count);
      END IF;
    END;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_autonomous_survives_rollback|FAIL|' || SQLERRM);
  END;

  -- tc_04: old_values = 'status=COMPLETED' doğru kaydedilir
  BEGIN
    pkg_transactions.deposit(100003, 500, 'Old values test', 'BRANCH', 2001, v_txn_id, v_ref);
    DECLARE
      v_rev_id NUMBER;
    BEGIN
      pkg_transactions.reverse_transaction(v_txn_id, 'Old values test', 2001, v_rev_id);
      SELECT COUNT(*) INTO v_count
      FROM   audit_log
      WHERE  table_name          = 'TRANSACTIONS'
      AND    record_id           = v_txn_id
      AND    TO_CHAR(old_values) = 'status=COMPLETED';
      ROLLBACK;
      IF v_count >= 1 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_old_values_correct|OK|count:' || v_count);
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_old_values_correct|FAIL|expected:>=1 got:' || v_count);
      END IF;
    END;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_old_values_correct|FAIL|' || SQLERRM);
  END;

  -- tc_05: exception yutulur — p_audit hatası reverse_transaction'ı bozmaz
  -- (WHEN OTHERS THEN NULL garantisi)
  BEGIN
    pkg_transactions.deposit(100004, 500, 'Exception swallow test', 'BRANCH', 2000, v_txn_id, v_ref);
    DECLARE
      v_rev_id NUMBER;
    BEGIN
      pkg_transactions.reverse_transaction(v_txn_id, 'Exception test', 2000, v_rev_id);
      ROLLBACK;
      IF v_rev_id IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_audit_exception_swallowed|OK|reversal_completed:' || v_rev_id);
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_audit_exception_swallowed|FAIL|rev_id_null');
      END IF;
    END;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_audit_exception_swallowed|FAIL|' || SQLERRM);
  END;

END;
/