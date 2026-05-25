DECLARE
  v_result NUMBER;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: USD → EUR dönüşümü (1000 * 0.921 = 921.00)
  BEGIN
    v_result := pkg_transactions.convert_currency(1000, 'USD', 'EUR');
    IF v_result = 921.00 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_usd_to_eur|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_usd_to_eur|FAIL|expected:921.00 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_usd_to_eur|FAIL|' || SQLERRM);
  END;

  -- tc_02: USD → GBP dönüşümü (1000 * 0.787 = 787.00)
  BEGIN
    v_result := pkg_transactions.convert_currency(1000, 'USD', 'GBP');
    IF v_result = 787.00 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_usd_to_gbp|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_usd_to_gbp|FAIL|expected:787.00 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_usd_to_gbp|FAIL|' || SQLERRM);
  END;

  -- tc_03: USD → JPY dönüşümü (100 * 154.32 = 15432.00)
  BEGIN
    v_result := pkg_transactions.convert_currency(100, 'USD', 'JPY');
    IF v_result = 15432.00 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_usd_to_jpy|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_usd_to_jpy|FAIL|expected:15432.00 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_usd_to_jpy|FAIL|' || SQLERRM);
  END;

  -- tc_04: EUR → USD dönüşümü (500 * 1.085 = 542.50)
  BEGIN
    v_result := pkg_transactions.convert_currency(500, 'EUR', 'USD');
    IF v_result = 542.50 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_eur_to_usd|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_eur_to_usd|FAIL|expected:542.50 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_eur_to_usd|FAIL|' || SQLERRM);
  END;

  -- tc_05: Aynı para birimi → amount değişmez (1000 * 1 = 1000.00)
  BEGIN
    v_result := pkg_transactions.convert_currency(1000, 'USD', 'USD');
    IF v_result = 1000.00 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_same_currency|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_same_currency|FAIL|expected:1000.00 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_same_currency|FAIL|' || SQLERRM);
  END;

  -- tc_06: ROUND(2) kontrolü — ondalık doğru yuvarlanıyor mu (1 * 0.921 = 0.92)
  BEGIN
    v_result := pkg_transactions.convert_currency(1, 'USD', 'EUR');
    IF v_result = 0.92 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_rounding|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_rounding|FAIL|expected:0.92 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_rounding|FAIL|' || SQLERRM);
  END;

  -- tc_07: Sıfır tutar → 0 döner (0 * rate = 0)
  BEGIN
    v_result := pkg_transactions.convert_currency(0, 'USD', 'EUR');
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_zero_amount|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_zero_amount|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_zero_amount|FAIL|' || SQLERRM);
  END;

  -- tc_08: Var olmayan kur çifti → -20032 exception (get_exchange_rate'den gelir)
  BEGIN
    v_result := pkg_transactions.convert_currency(100, 'USD', 'TRY');
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_nonexistent_pair|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -20032 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_nonexistent_pair|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_nonexistent_pair|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_09: Küçük harf input → UPPER ile eşleşir (get_exchange_rate devralıyor)
  BEGIN
    v_result := pkg_transactions.convert_currency(1000, 'usd', 'eur');
    IF v_result = 921.00 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_lowercase_input|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_lowercase_input|FAIL|expected:921.00 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_lowercase_input|FAIL|' || SQLERRM);
  END;

  -- tc_10: NULL amount → NULL döner (NULL * rate = NULL → ROUND(NULL,2) = NULL)
  BEGIN
    v_result := pkg_transactions.convert_currency(NULL, 'USD', 'EUR');
    IF v_result IS NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_null_amount|OK|returned:NULL');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_null_amount|FAIL|expected:NULL got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_null_amount|FAIL|' || SQLERRM);
  END;

END;
/