DECLARE
  -- f_resolve_lgd PRIVATE bir fonksiyondur VE paket seviyesi sabitlere bağımlıdır
  -- (c_lgd_mortgage=0.20, c_lgd_secured=0.35, c_lgd_unsecured=0.65).
  -- Bu yüzden raw gövdesi STANDALONE deploy edilemez (PLS-00201) — bu test
  -- dosyası ancak harness, standalone deploy'a paket sabitlerini enjekte
  -- edebildiğinde (ya da fonksiyon spec'e açıldığında) çalışır. Çağrı bare
  -- isimle yapılır. Beklenen değerler sabitlerin spec'teki değerlerine göredir.
  --
  -- Mantık: temel LGD loan_type'a göre seçilir; teminat kapsamı (cover =
  -- LEAST(collateral_value/outstanding, 1)) varsa LGD *= (1 - cover*0.40);
  -- sonuç GREATEST(LEAST(lgd,0.99),0.01) ile [0.01, 0.99] aralığına sıkıştırılır.
  v_result NUMBER;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: MORTGAGE, teminatsız -> 0.20
  BEGIN
    v_result := f_resolve_lgd('MORTGAGE', 'NONE', 0, 1000);
    IF v_result = 0.20 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_mortgage|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_mortgage|FAIL|expected:0.2 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_mortgage|FAIL|' || SQLERRM);
  END;

  -- tc_02: HELOC -> c_lgd_secured + 0.05 = 0.40
  BEGIN
    v_result := f_resolve_lgd('HELOC', 'NONE', 0, 1000);
    IF v_result = 0.40 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_heloc|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_heloc|FAIL|expected:0.4 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_heloc|FAIL|' || SQLERRM);
  END;

  -- tc_03: AUTO -> 0.35
  BEGIN
    v_result := f_resolve_lgd('AUTO', 'NONE', 0, 1000);
    IF v_result = 0.35 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_auto|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_auto|FAIL|expected:0.35 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_auto|FAIL|' || SQLERRM);
  END;

  -- tc_04: BUSINESS, teminat NONE -> c_lgd_unsecured = 0.65
  BEGIN
    v_result := f_resolve_lgd('BUSINESS', 'NONE', 0, 1000);
    IF v_result = 0.65 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_business_unsecured|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_business_unsecured|FAIL|expected:0.65 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_business_unsecured|FAIL|' || SQLERRM);
  END;

  -- tc_05: BUSINESS, teminat var (değer 0 -> cover yok) -> c_lgd_secured = 0.35
  BEGIN
    v_result := f_resolve_lgd('BUSINESS', 'REAL_ESTATE', 0, 1000);
    IF v_result = 0.35 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_business_secured|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_business_secured|FAIL|expected:0.35 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_business_secured|FAIL|' || SQLERRM);
  END;

  -- tc_06: bilinmeyen tip (ELSE) -> c_lgd_unsecured = 0.65
  BEGIN
    v_result := f_resolve_lgd('PERSONAL', 'NONE', 0, 1000);
    IF v_result = 0.65 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_default_unsecured|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_default_unsecured|FAIL|expected:0.65 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_default_unsecured|FAIL|' || SQLERRM);
  END;

  -- tc_07: kısmi teminat kapsamı — MORTGAGE, cover=0.5 -> 0.20*(1-0.5*0.40)=0.16
  BEGIN
    v_result := f_resolve_lgd('MORTGAGE', 'REAL_ESTATE', 500, 1000);
    IF v_result = 0.16 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_partial_collateral|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_partial_collateral|FAIL|expected:0.16 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_partial_collateral|FAIL|' || SQLERRM);
  END;

  -- tc_08: aşırı teminat — cover LEAST(2,1)=1; AUTO -> 0.35*(1-1*0.40)=0.21
  BEGIN
    v_result := f_resolve_lgd('AUTO', 'VEHICLE', 2000, 1000);
    IF v_result = 0.21 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_full_collateral_capped|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_full_collateral_capped|FAIL|expected:0.21 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_full_collateral_capped|FAIL|' || SQLERRM);
  END;

  -- tc_09: sonuç her zaman [0.01, 0.99] aralığında
  BEGIN
    v_result := f_resolve_lgd('AUTO', 'VEHICLE', 2000, 1000);
    IF v_result BETWEEN 0.01 AND 0.99 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_within_bounds|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_within_bounds|FAIL|out of bounds:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_within_bounds|FAIL|' || SQLERRM);
  END;

  -- tc_10: outstanding 0 -> cover hesabı atlanır (sıfıra bölme yok), MORTGAGE -> 0.20
  BEGIN
    v_result := f_resolve_lgd('MORTGAGE', 'REAL_ESTATE', 500, 0);
    IF v_result = 0.20 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_zero_outstanding|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_zero_outstanding|FAIL|expected:0.2 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_zero_outstanding|FAIL|' || SQLERRM);
  END;

END;
/
