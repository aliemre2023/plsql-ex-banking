DECLARE
  v_audit_count  NUMBER;
  v_changed_at   TIMESTAMP;
  v_session_user VARCHAR2(100);
  v_before_time  TIMESTAMP;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);
  SELECT SYS_CONTEXT('USERENV','SESSION_USER') INTO v_session_user FROM DUAL;

  -- tc_01: freeze_account çağırınca audit_log'a kayıt düşer
  BEGIN
    v_before_time := SYSTIMESTAMP;
    pkg_account_mgmt.freeze_account(100000, 'audit test', 2000);
    SELECT COUNT(*) INTO v_audit_count
    FROM   audit_log
    WHERE  table_name = 'ACCOUNTS'
    AND    record_id  = 100000
    AND    action     = 'UPDATE'
    AND    changed_at >= v_before_time;
    ROLLBACK;
    IF v_audit_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_audit_on_freeze|OK|count:' || v_audit_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_audit_on_freeze|FAIL|expected:>=1 got:' || v_audit_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_audit_on_freeze|FAIL|' || SQLERRM);
  END;

  -- tc_02: unfreeze_account çağırınca audit_log'a kayıt düşer
  BEGIN
    v_before_time := SYSTIMESTAMP;
    UPDATE accounts SET status = 'FROZEN' WHERE account_id = 100001;
    pkg_account_mgmt.unfreeze_account(100001, 2000);
    SELECT COUNT(*) INTO v_audit_count
    FROM   audit_log
    WHERE  table_name = 'ACCOUNTS'
    AND    record_id  = 100001
    AND    action     = 'UPDATE'
    AND    changed_at >= v_before_time;
    ROLLBACK;
    IF v_audit_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_audit_on_unfreeze|OK|count:' || v_audit_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_audit_on_unfreeze|FAIL|expected:>=1 got:' || v_audit_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_audit_on_unfreeze|FAIL|' || SQLERRM);
  END;

  -- tc_03: reactivate_account çağırınca audit_log'a kayıt düşer
  BEGIN
    v_before_time := SYSTIMESTAMP;
    UPDATE accounts SET status = 'DORMANT' WHERE account_id = 100002;
    pkg_account_mgmt.reactivate_account(100002, 2000);
    SELECT COUNT(*) INTO v_audit_count
    FROM   audit_log
    WHERE  table_name = 'ACCOUNTS'
    AND    record_id  = 100002
    AND    action     = 'UPDATE'
    AND    changed_at >= v_before_time;
    ROLLBACK;
    IF v_audit_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_audit_on_reactivate|OK|count:' || v_audit_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_audit_on_reactivate|FAIL|expected:>=1 got:' || v_audit_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_audit_on_reactivate|FAIL|' || SQLERRM);
  END;

  -- tc_04: changed_by session user ile doluyor
  BEGIN
    v_before_time := SYSTIMESTAMP;
    pkg_account_mgmt.freeze_account(100003, 'session user test', 2001);
    SELECT COUNT(*) INTO v_audit_count
    FROM   audit_log
    WHERE  table_name  = 'ACCOUNTS'
    AND    record_id   = 100003
    AND    changed_by  = v_session_user
    AND    changed_at >= v_before_time;
    ROLLBACK;
    IF v_audit_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_changed_by_session|OK|changed_by:' || v_session_user);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_changed_by_session|FAIL|session_user:' || v_session_user);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_changed_by_session|FAIL|' || SQLERRM);
  END;

  -- tc_05: autonomous transaction — caller rollback sonrası audit kayıt kalır
  BEGIN
    v_before_time := SYSTIMESTAMP;
    pkg_account_mgmt.freeze_account(100004, 'rollback test', 2000);
    ROLLBACK; -- accounts değişikliği geri alınır ama audit kalır
    SELECT COUNT(*) INTO v_audit_count
    FROM   audit_log
    WHERE  table_name  = 'ACCOUNTS'
    AND    record_id   = 100004
    AND    changed_at >= v_before_time;
    IF v_audit_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_autonomous_survives_rollback|OK|count:' || v_audit_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_autonomous_survives_rollback|FAIL|expected:>=1 got:' || v_audit_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_autonomous_survives_rollback|FAIL|' || SQLERRM);
  END;

  -- tc_06: close_account INSERT action ile audit düşer
  BEGIN
    v_before_time := SYSTIMESTAMP;
    DECLARE v_final NUMBER; BEGIN
      pkg_account_mgmt.close_account(100002, 'audit test', 2000, v_final);
    END;
    SELECT COUNT(*) INTO v_audit_count
    FROM   audit_log
    WHERE  table_name  = 'ACCOUNTS'
    AND    record_id   = 100002
    AND    action      = 'UPDATE'
    AND    changed_at >= v_before_time;
    ROLLBACK;
    IF v_audit_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_audit_on_close|OK|count:' || v_audit_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_audit_on_close|FAIL|expected:>=1 got:' || v_audit_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_audit_on_close|FAIL|' || SQLERRM);
  END;

END;
/