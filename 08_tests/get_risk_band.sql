DECLARE
  v_result VARCHAR2(20);
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: score < 10 → AAA
  BEGIN
    v_result := pkg_advanced_risk_engine.get_risk_band(5);
    IF v_result = 'AAA' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_score_5_aaa|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_score_5_aaa|FAIL|expected:AAA got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_score_5_aaa|FAIL|' || SQLERRM);
  END;

  -- tc_02: score 10-19 → AA
  BEGIN
    v_result := pkg_advanced_risk_engine.get_risk_band(15);
    IF v_result = 'AA' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_score_15_aa|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_score_15_aa|FAIL|expected:AA got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_score_15_aa|FAIL|' || SQLERRM);
  END;

  -- tc_03: score 20-29 → A
  BEGIN
    v_result := pkg_advanced_risk_engine.get_risk_band(25);
    IF v_result = 'A' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_score_25_a|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_score_25_a|FAIL|expected:A got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_score_25_a|FAIL|' || SQLERRM);
  END;

  -- tc_04: score 30-39 → BBB
  BEGIN
    v_result := pkg_advanced_risk_engine.get_risk_band(35);
    IF v_result = 'BBB' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_score_35_bbb|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_score_35_bbb|FAIL|expected:BBB got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_score_35_bbb|FAIL|' || SQLERRM);
  END;

  -- tc_05: score 40-54 → BB
  BEGIN
    v_result := pkg_advanced_risk_engine.get_risk_band(50);
    IF v_result = 'BB' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_score_50_bb|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_score_50_bb|FAIL|expected:BB got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_score_50_bb|FAIL|' || SQLERRM);
  END;

  -- tc_06: score 55-69 → B
  BEGIN
    v_result := pkg_advanced_risk_engine.get_risk_band(62);
    IF v_result = 'B' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_score_62_b|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_score_62_b|FAIL|expected:B got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_score_62_b|FAIL|' || SQLERRM);
  END;

  -- tc_07: score 70-84 → CCC
  BEGIN
    v_result := pkg_advanced_risk_engine.get_risk_band(75);
    IF v_result = 'CCC' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_score_75_ccc|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_score_75_ccc|FAIL|expected:CCC got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_score_75_ccc|FAIL|' || SQLERRM);
  END;

  -- tc_08: score >= 85 → D
  BEGIN
    v_result := pkg_advanced_risk_engine.get_risk_band(90);
    IF v_result = 'D' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_score_90_d|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_score_90_d|FAIL|expected:D got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_score_90_d|FAIL|' || SQLERRM);
  END;

  -- tc_09: NULL → UNRATED
  BEGIN
    v_result := pkg_advanced_risk_engine.get_risk_band(NULL);
    IF v_result = 'UNRATED' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_null_unrated|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_null_unrated|FAIL|expected:UNRATED got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_null_unrated|FAIL|' || SQLERRM);
  END;

  -- tc_10: score 0 → AAA (sınır değeri)
  BEGIN
    v_result := pkg_advanced_risk_engine.get_risk_band(0);
    IF v_result = 'AAA' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_score_0_boundary|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_score_0_boundary|FAIL|expected:AAA got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_score_0_boundary|FAIL|' || SQLERRM);
  END;

  -- tc_11: score 100 → D (maksimum skor)
  BEGIN
    v_result := pkg_advanced_risk_engine.get_risk_band(100);
    IF v_result = 'D' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_score_100_d|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_score_100_d|FAIL|expected:D got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_score_100_d|FAIL|' || SQLERRM);
  END;

  -- tc_12: Sonuç her zaman non-null (geçerli bir skor için)
  BEGIN
    v_result := pkg_advanced_risk_engine.get_risk_band(42);
    IF v_result IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_result_not_null|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_result_not_null|FAIL|returned null');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_result_not_null|FAIL|' || SQLERRM);
  END;

END;
/
