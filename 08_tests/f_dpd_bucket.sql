DECLARE
  -- f_dpd_bucket, run_delinquency_migration_analysis içinde NESTED bir
  -- fonksiyondur; pakette spec'te olmadığı için harness onu STANDALONE deploy
  -- eder ve bare isimle çağrılır. Saf (deterministik) bir fonksiyondur.
  -- Mantık: önce status (DEFAULTED/WRITTEN_OFF, PAID_OFF/CLOSED) kontrol edilir,
  -- ardından NVL(dpd,0) kovaları. Status, dpd'ye göre önceliklidir.
  v_result VARCHAR2(30);
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: status DEFAULTED -> 'D - DEFAULT'
  BEGIN
    v_result := f_dpd_bucket(10, 'DEFAULTED');
    IF v_result = 'D - DEFAULT' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_defaulted|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_defaulted|FAIL|expected:D - DEFAULT got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_defaulted|FAIL|' || SQLERRM);
  END;

  -- tc_02: status WRITTEN_OFF -> 'D - DEFAULT'
  BEGIN
    v_result := f_dpd_bucket(0, 'WRITTEN_OFF');
    IF v_result = 'D - DEFAULT' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_written_off|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_written_off|FAIL|expected:D - DEFAULT got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_written_off|FAIL|' || SQLERRM);
  END;

  -- tc_03: status PAID_OFF -> 'PAID_OFF'
  BEGIN
    v_result := f_dpd_bucket(0, 'PAID_OFF');
    IF v_result = 'PAID_OFF' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_paid_off|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_paid_off|FAIL|expected:PAID_OFF got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_paid_off|FAIL|' || SQLERRM);
  END;

  -- tc_04: status CLOSED -> 'PAID_OFF'
  BEGIN
    v_result := f_dpd_bucket(0, 'CLOSED');
    IF v_result = 'PAID_OFF' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_closed|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_closed|FAIL|expected:PAID_OFF got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_closed|FAIL|' || SQLERRM);
  END;

  -- tc_05: dpd 0, status ACTIVE -> 'A - CURRENT'
  BEGIN
    v_result := f_dpd_bucket(0, 'ACTIVE');
    IF v_result = 'A - CURRENT' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_current|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_current|FAIL|expected:A - CURRENT got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_current|FAIL|' || SQLERRM);
  END;

  -- tc_06: dpd 15 -> 'B - 1-30DPD'
  BEGIN
    v_result := f_dpd_bucket(15, 'ACTIVE');
    IF v_result = 'B - 1-30DPD' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_1_30dpd|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_1_30dpd|FAIL|expected:B - 1-30DPD got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_1_30dpd|FAIL|' || SQLERRM);
  END;

  -- tc_07: dpd 45 -> 'C - 31-60DPD'
  BEGIN
    v_result := f_dpd_bucket(45, 'ACTIVE');
    IF v_result = 'C - 31-60DPD' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_31_60dpd|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_31_60dpd|FAIL|expected:C - 31-60DPD got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_31_60dpd|FAIL|' || SQLERRM);
  END;

  -- tc_08: dpd 75 -> 'D - 61-90DPD'
  BEGIN
    v_result := f_dpd_bucket(75, 'ACTIVE');
    IF v_result = 'D - 61-90DPD' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_61_90dpd|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_61_90dpd|FAIL|expected:D - 61-90DPD got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_61_90dpd|FAIL|' || SQLERRM);
  END;

  -- tc_09: dpd 120 -> 'E - 91-180DPD'
  BEGIN
    v_result := f_dpd_bucket(120, 'ACTIVE');
    IF v_result = 'E - 91-180DPD' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_91_180dpd|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_91_180dpd|FAIL|expected:E - 91-180DPD got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_91_180dpd|FAIL|' || SQLERRM);
  END;

  -- tc_10: dpd 250 -> 'F - 180+DPD'
  BEGIN
    v_result := f_dpd_bucket(250, 'ACTIVE');
    IF v_result = 'F - 180+DPD' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_180_plus_dpd|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_180_plus_dpd|FAIL|expected:F - 180+DPD got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_180_plus_dpd|FAIL|' || SQLERRM);
  END;

  -- tc_11: NULL dpd, status ACTIVE -> NVL(dpd,0)=0 -> 'A - CURRENT'
  BEGIN
    v_result := f_dpd_bucket(NULL, 'ACTIVE');
    IF v_result = 'A - CURRENT' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_null_dpd|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_null_dpd|FAIL|expected:A - CURRENT got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_null_dpd|FAIL|' || SQLERRM);
  END;

  -- tc_12: status önceliği — yüksek dpd olsa bile PAID_OFF kazanır
  BEGIN
    v_result := f_dpd_bucket(200, 'PAID_OFF');
    IF v_result = 'PAID_OFF' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_status_precedence|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_status_precedence|FAIL|expected:PAID_OFF got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_status_precedence|FAIL|' || SQLERRM);
  END;

END;
/
