DECLARE
  v_result NUMBER;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: USD → EUR doğru rate döner
  BEGIN
    v_result := pkg_transactions.get_exchange_rate('USD', 'EUR');
    IF v_result = 0.921000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_usd_eur|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_usd_eur|FAIL|expected:0.921000 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_usd_eur|FAIL|' || SQLERRM);
  END;

  -- tc_02: USD → GBP doğru rate döner
  BEGIN
    v_result := pkg_transactions.get_exchange_rate('USD', 'GBP');
    IF v_result = 0.787000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_usd_gbp|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_usd_gbp|FAIL|expected:0.787000 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_usd_gbp|FAIL|' || SQLERRM);
  END;

  -- tc_03: USD → JPY doğru rate döner
  BEGIN
    v_result := pkg_transactions.get_exchange_rate('USD', 'JPY');
    IF v_result = 154.32000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_usd_jpy|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_usd_jpy|FAIL|expected:154.32000 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_usd_jpy|FAIL|' || SQLERRM);
  END;

  -- tc_04: EUR → USD doğru rate döner
  BEGIN
    v_result := pkg_transactions.get_exchange_rate('EUR', 'USD');
    IF v_result = 1.085000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_eur_usd|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_eur_usd|FAIL|expected:1.085000 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_eur_usd|FAIL|' || SQLERRM);
  END;

  -- tc_05: GBP → USD doğru rate döner
  BEGIN
    v_result := pkg_transactions.get_exchange_rate('GBP', 'USD');
    IF v_result = 1.270000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_gbp_usd|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_gbp_usd|FAIL|expected:1.270000 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_gbp_usd|FAIL|' || SQLERRM);
  END;

  -- tc_06: JPY → USD doğru rate döner
  BEGIN
    v_result := pkg_transactions.get_exchange_rate('JPY', 'USD');
    IF v_result = 0.006480 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_jpy_usd|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_jpy_usd|FAIL|expected:0.006480 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_jpy_usd|FAIL|' || SQLERRM);
  END;

  -- tc_07: Aynı para birimi → 1 döner (DB'ye gitmeden)
  BEGIN
    v_result := pkg_transactions.get_exchange_rate('USD', 'USD');
    IF v_result = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_same_currency|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_same_currency|FAIL|expected:1 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_same_currency|FAIL|' || SQLERRM);
  END;

  -- tc_08: EUR → EUR → 1 döner
  BEGIN
    v_result := pkg_transactions.get_exchange_rate('EUR', 'EUR');
    IF v_result = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_same_currency_eur|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_same_currency_eur|FAIL|expected:1 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_same_currency_eur|FAIL|' || SQLERRM);
  END;

  -- tc_09: Var olmayan çift → -20032 exception
  BEGIN
    v_result := pkg_transactions.get_exchange_rate('USD', 'TRY');
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_nonexistent_pair|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -20032 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_nonexistent_pair|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_nonexistent_pair|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_10: Küçük harf input → UPPER ile eşleşir, doğru rate döner
  BEGIN
    v_result := pkg_transactions.get_exchange_rate('usd', 'eur');
    IF v_result = 0.921000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_lowercase_input|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_lowercase_input|FAIL|expected:0.921000 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_lowercase_input|FAIL|' || SQLERRM);
  END;

  -- tc_11: NULL from → -20032 exception (UPPER(NULL) = NULL → eşleşme yok)
  BEGIN
    v_result := pkg_transactions.get_exchange_rate(NULL, 'USD');
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_null_from|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -20032 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_null_from|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_null_from|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_12: NULL to → -20032 exception
  BEGIN
    v_result := pkg_transactions.get_exchange_rate('USD', NULL);
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_null_to|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -20032 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_null_to|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_null_to|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_13: En son effective_date kullanılır — eski rate değil
  BEGIN
    INSERT INTO exchange_rates VALUES ('USD', 'EUR', 0.999000, SYSDATE + 1, SYSTIMESTAMP);
    v_result := pkg_transactions.get_exchange_rate('USD', 'EUR');
    ROLLBACK;
    IF v_result = 0.999000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_latest_effective_date|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_latest_effective_date|FAIL|expected:0.999000 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_latest_effective_date|FAIL|' || SQLERRM);
  END;

END;
/