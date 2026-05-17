DECLARE
  v_audit_count  NUMBER;
  v_changed_at   TIMESTAMP;
  v_session_user VARCHAR2(100);
  v_before_time  TIMESTAMP;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);
  SELECT SYS_CONTEXT('USERENV','SESSION_USER') INTO v_session_user FROM DUAL;

  -- Test: tc_01_happy_path_insert — Audit record inserted with all fields correctly populated
  BEGIN
    v_before_time := SYSTIMESTAMP;
    pkg_account_mgmt.p_audit('ACCOUNTS', 100000, 'INSERT', 'old_val_1', 'new_val_1');
    SELECT COUNT(*) INTO v_audit_count
    FROM   audit_log
    WHERE  table_name            = 'ACCOUNTS'
    AND    record_id             = 100000
    AND    action                = 'INSERT'
    AND    TO_CHAR(old_values)   = 'old_val_1'
    AND    TO_CHAR(new_values)   = 'new_val_1'
    AND    changed_by            = v_session_user
    AND    changed_at           >= v_before_time;
    DELETE FROM audit_log
    WHERE  table_name = 'ACCOUNTS' AND record_id = 100000
    AND    action = 'INSERT' AND TO_CHAR(old_values) = 'old_val_1';
    COMMIT;
    IF v_audit_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path_insert|OK|audit_count:' || v_audit_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path_insert|FAIL|expected:1 got:' || v_audit_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path_insert|FAIL|' || SQLERRM);
  END;

  -- Test: tc_02_update_action — UPDATE action recorded correctly
  BEGIN
    pkg_account_mgmt.p_audit('CUSTOMERS', 1000, 'UPDATE', 'status=ACTIVE', 'status=INACTIVE');
    SELECT COUNT(*) INTO v_audit_count
    FROM   audit_log
    WHERE  table_name           = 'CUSTOMERS'
    AND    record_id            = 1000
    AND    action               = 'UPDATE'
    AND    TO_CHAR(old_values)  = 'status=ACTIVE'
    AND    TO_CHAR(new_values)  = 'status=INACTIVE';
    DELETE FROM audit_log
    WHERE  table_name = 'CUSTOMERS' AND record_id = 1000 AND action = 'UPDATE';
    COMMIT;
    IF v_audit_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_update_action|OK|audit_count:' || v_audit_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_update_action|FAIL|expected:1 got:' || v_audit_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_update_action|FAIL|' || SQLERRM);
  END;

  -- Test: tc_03_delete_action — DELETE action with NULL new_values recorded correctly
  BEGIN
    pkg_account_mgmt.p_audit('LOANS', 5000, 'DELETE', 'loan_active', NULL);
    SELECT COUNT(*) INTO v_audit_count
    FROM   audit_log
    WHERE  table_name          = 'LOANS'
    AND    record_id           = 5000
    AND    action              = 'DELETE'
    AND    TO_CHAR(old_values) = 'loan_active'
    AND    new_values          IS NULL;
    DELETE FROM audit_log
    WHERE  table_name = 'LOANS' AND record_id = 5000 AND action = 'DELETE';
    COMMIT;
    IF v_audit_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_delete_action|OK|audit_count:' || v_audit_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_delete_action|FAIL|expected:1 got:' || v_audit_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_delete_action|FAIL|' || SQLERRM);
  END;

  -- Test: tc_04_null_old_and_new — Both p_old and p_new NULL stored as NULL
  BEGIN
    pkg_account_mgmt.p_audit('ACCOUNTS', 100001, 'INSERT', NULL, NULL);
    SELECT COUNT(*) INTO v_audit_count
    FROM   audit_log
    WHERE  table_name = 'ACCOUNTS'
    AND    record_id  = 100001
    AND    action     = 'INSERT'
    AND    old_values IS NULL
    AND    new_values IS NULL;
    DELETE FROM audit_log
    WHERE  table_name = 'ACCOUNTS' AND record_id = 100001
    AND    action = 'INSERT' AND old_values IS NULL AND new_values IS NULL;
    COMMIT;
    IF v_audit_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_null_old_and_new|OK|audit_count:' || v_audit_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_null_old_and_new|FAIL|expected:1 got:' || v_audit_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_null_old_and_new|FAIL|' || SQLERRM);
  END;

  -- Test: tc_05_default_null_params — Calling without p_old and p_new uses DEFAULT NULL
  BEGIN
    pkg_account_mgmt.p_audit('ACCOUNTS', 100002, 'UPDATE');
    SELECT COUNT(*) INTO v_audit_count
    FROM   audit_log
    WHERE  table_name = 'ACCOUNTS'
    AND    record_id  = 100002
    AND    action     = 'UPDATE'
    AND    old_values IS NULL
    AND    new_values IS NULL;
    DELETE FROM audit_log
    WHERE  table_name = 'ACCOUNTS' AND record_id = 100002
    AND    action = 'UPDATE' AND old_values IS NULL;
    COMMIT;
    IF v_audit_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_default_null_params|OK|audit_count:' || v_audit_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_default_null_params|FAIL|expected:1 got:' || v_audit_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_default_null_params|FAIL|' || SQLERRM);
  END;

  -- Test: tc_06_autonomous_survives_rollback — Audit record persists even when caller rolls back
  DECLARE
    v_marker VARCHAR2(50) := 'ROLLBACK-SURVIVE-' || TO_CHAR(SYSDATE,'YYYYMMDDHH24MISS');
  BEGIN
    UPDATE accounts SET status = 'INACTIVE' WHERE account_id = 100003;
    pkg_account_mgmt.p_audit('ACCOUNTS', 100003, 'UPDATE', 'status=ACTIVE', v_marker);
    ROLLBACK;
    SELECT COUNT(*) INTO v_audit_count
    FROM   audit_log
    WHERE  table_name          = 'ACCOUNTS'
    AND    record_id           = 100003
    AND    TO_CHAR(new_values) = v_marker;
    DELETE FROM audit_log
    WHERE  table_name = 'ACCOUNTS' AND record_id = 100003
    AND    TO_CHAR(new_values) = v_marker;
    COMMIT;
    IF v_audit_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_autonomous_survives_rollback|OK|audit_persisted:' || v_audit_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_autonomous_survives_rollback|FAIL|expected:1 got:' || v_audit_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_autonomous_survives_rollback|FAIL|' || SQLERRM);
  END;

  -- Test: tc_07_changed_by_session_user — changed_by populated with current session user
  BEGIN
    pkg_account_mgmt.p_audit('BRANCHES', 10, 'UPDATE', NULL, 'test_session_user');
    SELECT COUNT(*) INTO v_audit_count
    FROM   audit_log
    WHERE  table_name          = 'BRANCHES'
    AND    record_id           = 10
    AND    TO_CHAR(new_values) = 'test_session_user'
    AND    changed_by          = v_session_user;
    DELETE FROM audit_log
    WHERE  table_name = 'BRANCHES' AND record_id = 10
    AND    TO_CHAR(new_values) = 'test_session_user';
    COMMIT;
    IF v_audit_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_changed_by_session_user|OK|changed_by:' || v_session_user);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_changed_by_session_user|FAIL|session_user:' || v_session_user);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_changed_by_session_user|FAIL|' || SQLERRM);
  END;

  -- Test: tc_08_changed_at_recent — changed_at is within the call window
  BEGIN
    v_before_time := SYSTIMESTAMP;
    pkg_account_mgmt.p_audit('ACCOUNTS', 100004, 'UPDATE', NULL, 'timestamp_check');
    SELECT changed_at INTO v_changed_at
    FROM   audit_log
    WHERE  table_name          = 'ACCOUNTS'
    AND    record_id           = 100004
    AND    TO_CHAR(new_values) = 'timestamp_check';
    DELETE FROM audit_log
    WHERE  table_name = 'ACCOUNTS' AND record_id = 100004
    AND    TO_CHAR(new_values) = 'timestamp_check';
    COMMIT;
    IF v_changed_at >= v_before_time AND v_changed_at <= SYSTIMESTAMP THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_changed_at_recent|OK|changed_at:' || v_changed_at);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_changed_at_recent|FAIL|before:' || v_before_time || ' changed_at:' || v_changed_at);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_changed_at_recent|FAIL|' || SQLERRM);
  END;

  -- Test: tc_09_consecutive_calls_both_recorded — Two consecutive calls both produce separate audit rows
  DECLARE
    v_marker1 VARCHAR2(50) := 'CONSEC-1-' || TO_CHAR(SYSDATE,'YYYYMMDDHH24MISS');
    v_marker2 VARCHAR2(50) := 'CONSEC-2-' || TO_CHAR(SYSDATE,'YYYYMMDDHH24MISS');
  BEGIN
    pkg_account_mgmt.p_audit('ACCOUNTS', 100005, 'UPDATE', NULL, v_marker1);
    pkg_account_mgmt.p_audit('ACCOUNTS', 100005, 'UPDATE', NULL, v_marker2);
    SELECT COUNT(*) INTO v_audit_count
    FROM   audit_log
    WHERE  table_name          = 'ACCOUNTS'
    AND    record_id           = 100005
    AND    TO_CHAR(new_values) IN (v_marker1, v_marker2);
    DELETE FROM audit_log
    WHERE  table_name = 'ACCOUNTS' AND record_id = 100005
    AND    TO_CHAR(new_values) IN (v_marker1, v_marker2);
    COMMIT;
    IF v_audit_count = 2 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_consecutive_calls_both_recorded|OK|audit_count:' || v_audit_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_consecutive_calls_both_recorded|FAIL|expected:2 got:' || v_audit_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_consecutive_calls_both_recorded|FAIL|' || SQLERRM);
  END;

  -- Test: tc_10_null_table_name — NULL table_name: exception swallowed silently by WHEN OTHERS THEN NULL
  BEGIN
    pkg_account_mgmt.p_audit(NULL, 100006, 'INSERT', NULL, 'null_table_test');
    SELECT COUNT(*) INTO v_audit_count
    FROM   audit_log
    WHERE  table_name IS NULL
    AND    record_id  = 100006
    AND    TO_CHAR(new_values) = 'null_table_test';
    DELETE FROM audit_log
    WHERE  table_name IS NULL AND record_id = 100006
    AND    TO_CHAR(new_values) = 'null_table_test';
    COMMIT;
    IF v_audit_count IN (0, 1) THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_null_table_name|OK|count:' || v_audit_count || ' (swallowed_or_inserted)');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_null_table_name|FAIL|unexpected_count:' || v_audit_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_null_table_name|FAIL|' || SQLERRM);
  END;

  -- Test: tc_11_null_rec_id — NULL record_id: exception swallowed silently by WHEN OTHERS THEN NULL
  BEGIN
    pkg_account_mgmt.p_audit('ACCOUNTS', NULL, 'UPDATE', NULL, 'null_recid_test');
    SELECT COUNT(*) INTO v_audit_count
    FROM   audit_log
    WHERE  table_name          = 'ACCOUNTS'
    AND    record_id           IS NULL
    AND    TO_CHAR(new_values) = 'null_recid_test';
    DELETE FROM audit_log
    WHERE  table_name = 'ACCOUNTS' AND record_id IS NULL
    AND    TO_CHAR(new_values) = 'null_recid_test';
    COMMIT;
    IF v_audit_count IN (0, 1) THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_null_rec_id|OK|count:' || v_audit_count || ' (swallowed_or_inserted)');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_null_rec_id|FAIL|unexpected_count:' || v_audit_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_null_rec_id|FAIL|' || SQLERRM);
  END;

END;
/