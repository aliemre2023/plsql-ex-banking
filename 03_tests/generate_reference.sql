DECLARE
  v_result  VARCHAR2(50);
  v_today   VARCHAR2(8) := TO_CHAR(SYSDATE, 'YYYYMMDD');

  PROCEDURE assert_format(p_test VARCHAR2, p_result VARCHAR2, p_expected_prefix VARCHAR2) IS
  BEGIN
    IF p_result IS NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|' || p_test || '|FAIL|returned NULL');
    ELSIF p_result LIKE p_expected_prefix || '-' || v_today || '-________' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|' || p_test || '|OK|returned:' || p_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|' || p_test || '|FAIL|unexpected_format:' || p_result);
    END IF;
  END;

BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: DEPOSIT → DEP prefix
  BEGIN
    v_result := pkg_transactions.generate_reference('DEPOSIT');
    assert_format('tc_01_deposit_prefix', v_result, 'DEP');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_deposit_prefix|FAIL|' || SQLERRM);
  END;

  -- tc_02: WITHDRAWAL → WDR prefix
  BEGIN
    v_result := pkg_transactions.generate_reference('WITHDRAWAL');
    assert_format('tc_02_withdrawal_prefix', v_result, 'WDR');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_withdrawal_prefix|FAIL|' || SQLERRM);
  END;

  -- tc_03: TRANSFER_OUT → TRF prefix
  BEGIN
    v_result := pkg_transactions.generate_reference('TRANSFER_OUT');
    assert_format('tc_03_transfer_out_prefix', v_result, 'TRF');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_transfer_out_prefix|FAIL|' || SQLERRM);
  END;

  -- tc_04: TRANSFER_IN → TRF prefix (aynı prefix)
  BEGIN
    v_result := pkg_transactions.generate_reference('TRANSFER_IN');
    assert_format('tc_04_transfer_in_prefix', v_result, 'TRF');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_transfer_in_prefix|FAIL|' || SQLERRM);
  END;

  -- tc_05: PAYMENT → PAY prefix
  BEGIN
    v_result := pkg_transactions.generate_reference('PAYMENT');
    assert_format('tc_05_payment_prefix', v_result, 'PAY');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_payment_prefix|FAIL|' || SQLERRM);
  END;

  -- tc_06: FEE → FEE prefix
  BEGIN
    v_result := pkg_transactions.generate_reference('FEE');
    assert_format('tc_06_fee_prefix', v_result, 'FEE');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_fee_prefix|FAIL|' || SQLERRM);
  END;

  -- tc_07: INTEREST → INT prefix
  BEGIN
    v_result := pkg_transactions.generate_reference('INTEREST');
    assert_format('tc_07_interest_prefix', v_result, 'INT');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_interest_prefix|FAIL|' || SQLERRM);
  END;

  -- tc_08: REVERSAL → REV prefix
  BEGIN
    v_result := pkg_transactions.generate_reference('REVERSAL');
    assert_format('tc_08_reversal_prefix', v_result, 'REV');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_reversal_prefix|FAIL|' || SQLERRM);
  END;

  -- tc_09: Bilinmeyen tip → TXN fallback
  BEGIN
    v_result := pkg_transactions.generate_reference('UNKNOWN');
    assert_format('tc_09_unknown_fallback', v_result, 'TXN');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_unknown_fallback|FAIL|' || SQLERRM);
  END;

  -- tc_10: NULL tip → TXN fallback
  BEGIN
    v_result := pkg_transactions.generate_reference(NULL);
    assert_format('tc_10_null_type_fallback', v_result, 'TXN');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_null_type_fallback|FAIL|' || SQLERRM);
  END;

  -- tc_11: Ardışık iki çağrı farklı referans döner (unique)
  DECLARE
    v_first  VARCHAR2(50);
    v_second VARCHAR2(50);
  BEGIN
    v_first  := pkg_transactions.generate_reference('DEPOSIT');
    v_second := pkg_transactions.generate_reference('DEPOSIT');
    IF v_first <> v_second THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_unique_per_call|OK|first:' || v_first || ' second:' || v_second);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_unique_per_call|FAIL|duplicate:' || v_first);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_unique_per_call|FAIL|' || SQLERRM);
  END;

  -- tc_12: Tarih kısmı bugünün tarihi
  BEGIN
    v_result := pkg_transactions.generate_reference('DEPOSIT');
    IF SUBSTR(v_result, 5, 8) = v_today THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_date_is_today|OK|date:' || SUBSTR(v_result, 5, 8));
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_date_is_today|FAIL|expected:' || v_today || ' got:' || SUBSTR(v_result, 5, 8));
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_date_is_today|FAIL|' || SQLERRM);
  END;

  -- tc_13: Uzunluk <= 50 karakter (VARCHAR2(50) sınırı)
  BEGIN
    v_result := pkg_transactions.generate_reference('DEPOSIT');
    IF LENGTH(v_result) <= 50 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_length_constraint|OK|length:' || LENGTH(v_result));
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_length_constraint|FAIL|length_exceeded:' || LENGTH(v_result));
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_length_constraint|FAIL|' || SQLERRM);
  END;

END;
/