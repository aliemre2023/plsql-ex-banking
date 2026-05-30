DECLARE
  -- p_log_risk_event PRIVATE bir prosedür (pakette spec'te yok), bu yüzden
  -- harness onu STANDALONE (paketsiz) deploy eder ve bare isimle çağrılır.
  -- Prosedür PRAGMA AUTONOMOUS_TRANSACTION + COMMIT içerir ve TÜM hataları
  -- WHEN OTHERS THEN NULL ile yutar; dolayısıyla gözlemlenebilir tek davranış
  -- audit_log tablosuna eklenen satırdır. Doğrulama delta (önce/sonra sayım)
  -- tabanlıdır, böylece tekrar çalıştırmalarda da güvenlidir.
  v_before     NUMBER;
  v_after      NUMBER;
  v_action     audit_log.action%TYPE;
  v_table      audit_log.table_name%TYPE;
  v_changed_by audit_log.changed_by%TYPE;
  v_nv         VARCHAR2(4000);
  v_len        NUMBER;
  v_cnt        NUMBER;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: temel çağrı tam olarak bir satır ekler
  BEGIN
    SELECT COUNT(*) INTO v_before FROM audit_log WHERE record_id = 990001;
    p_log_risk_event('CREDIT_CHECK', 990001, 'CUSTOMERS', 'score=720');
    SELECT COUNT(*) INTO v_after FROM audit_log WHERE record_id = 990001;
    IF v_after = v_before + 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_basic_insert|OK|rows_added:' || (v_after - v_before));
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_basic_insert|FAIL|expected +1 got ' || (v_after - v_before));
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_basic_insert|FAIL|' || SQLERRM);
  END;

  -- tc_02: action her zaman 'UPDATE'
  BEGIN
    p_log_risk_event('EVT2', 990002, 'LOANS', 'd2');
    SELECT action INTO v_action FROM audit_log WHERE record_id = 990002 AND ROWNUM = 1;
    IF v_action = 'UPDATE' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_action_is_update|OK|action:' || v_action);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_action_is_update|FAIL|expected:UPDATE got:' || v_action);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_action_is_update|FAIL|' || SQLERRM);
  END;

  -- tc_03: new_values 'RISK_ENGINE|EVENT=<type>|' önekiyle başlar
  BEGIN
    p_log_risk_event('EVT3', 990003, 'ACCOUNTS', 'detail3');
    SELECT DBMS_LOB.SUBSTR(new_values, 200, 1) INTO v_nv FROM audit_log WHERE record_id = 990003 AND ROWNUM = 1;
    IF v_nv LIKE 'RISK_ENGINE|EVENT=EVT3|%' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_event_marker|OK|prefix_present');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_event_marker|FAIL|got:' || v_nv);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_event_marker|FAIL|' || SQLERRM);
  END;

  -- tc_04: new_values p_details içeriğini taşır
  BEGIN
    p_log_risk_event('EVT4', 990004, 'ACCOUNTS', 'unique_detail_4242');
    SELECT DBMS_LOB.SUBSTR(new_values, 400, 1) INTO v_nv FROM audit_log WHERE record_id = 990004 AND ROWNUM = 1;
    IF v_nv LIKE '%unique_detail_4242%' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_contains_details|OK|details_present');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_contains_details|FAIL|got:' || v_nv);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_contains_details|FAIL|' || SQLERRM);
  END;

  -- tc_05: table_name = p_entity_type
  BEGIN
    p_log_risk_event('EVT5', 990005, 'TRANSACTIONS', 'd5');
    SELECT table_name INTO v_table FROM audit_log WHERE record_id = 990005 AND ROWNUM = 1;
    IF v_table = 'TRANSACTIONS' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_table_name_mapping|OK|table:' || v_table);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_table_name_mapping|FAIL|expected:TRANSACTIONS got:' || v_table);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_table_name_mapping|FAIL|' || SQLERRM);
  END;

  -- tc_06: changed_by doldurulur (SYS_CONTEXT session_user)
  BEGIN
    p_log_risk_event('EVT6', 990006, 'CUSTOMERS', 'd6');
    SELECT changed_by INTO v_changed_by FROM audit_log WHERE record_id = 990006 AND ROWNUM = 1;
    IF v_changed_by IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_changed_by_not_null|OK|changed_by:' || v_changed_by);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_changed_by_not_null|FAIL|changed_by is null');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_changed_by_not_null|FAIL|' || SQLERRM);
  END;

  -- tc_07: NULL p_details ile çağrı yine satır ekler, hata fırlatmaz
  BEGIN
    SELECT COUNT(*) INTO v_before FROM audit_log WHERE record_id = 990007;
    p_log_risk_event('EVT7', 990007, 'CUSTOMERS', NULL);
    SELECT COUNT(*) INTO v_after FROM audit_log WHERE record_id = 990007;
    IF v_after = v_before + 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_null_details_inserts|OK|rows_added:' || (v_after - v_before));
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_null_details_inserts|FAIL|expected +1 got ' || (v_after - v_before));
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_null_details_inserts|FAIL|' || SQLERRM);
  END;

  -- tc_08: çok uzun p_details SUBSTR ile 3900 karaktere kesilir
  BEGIN
    p_log_risk_event('EVT8', 990008, 'CUSTOMERS', RPAD('X', 5000, 'X'));
    SELECT DBMS_LOB.GETLENGTH(new_values) INTO v_len FROM audit_log WHERE record_id = 990008 AND ROWNUM = 1;
    IF v_len <= 3900 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_long_details_truncated|OK|len:' || v_len);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_long_details_truncated|FAIL|len ' || v_len || ' > 3900');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_long_details_truncated|FAIL|' || SQLERRM);
  END;

  -- tc_09: NULL p_entity_id (record_id NOT NULL) -> insert iç hatayı yutar,
  --        çağrı hata fırlatmaz ve satır eklenmez
  BEGIN
    p_log_risk_event('EVT9UNIQ', NULL, 'CUSTOMERS', 'd9');
    SELECT COUNT(*) INTO v_cnt FROM audit_log WHERE DBMS_LOB.INSTR(new_values, 'EVENT=EVT9UNIQ') > 0;
    IF v_cnt = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_null_id_swallowed|OK|no_raise_no_row');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_null_id_swallowed|FAIL|unexpected_rows:' || v_cnt);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_null_id_swallowed|FAIL|raised:' || SQLERRM);
  END;

  -- tc_10: aynı record_id ile iki çağrı iki ayrı satır üretir (audit izi append-only)
  BEGIN
    SELECT COUNT(*) INTO v_before FROM audit_log WHERE record_id = 990010;
    p_log_risk_event('EVT10A', 990010, 'CUSTOMERS', 'first');
    p_log_risk_event('EVT10B', 990010, 'CUSTOMERS', 'second');
    SELECT COUNT(*) INTO v_after FROM audit_log WHERE record_id = 990010;
    IF v_after = v_before + 2 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_append_only|OK|rows_added:' || (v_after - v_before));
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_append_only|FAIL|expected +2 got ' || (v_after - v_before));
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_append_only|FAIL|' || SQLERRM);
  END;

END;
/
