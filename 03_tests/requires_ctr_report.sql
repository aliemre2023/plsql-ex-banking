DECLARE
  v_result BOOLEAN;

  PROCEDURE print_bool(p_test VARCHAR2, p_result BOOLEAN, p_expected BOOLEAN) IS
  BEGIN
    IF p_result = p_expected THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|' || p_test || '|OK|returned:' ||
        CASE p_result WHEN TRUE THEN 'TRUE' ELSE 'FALSE' END);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|' || p_test || '|FAIL|expected:' ||
        CASE p_expected WHEN TRUE THEN 'TRUE' ELSE 'FALSE' END ||
        ' got:' ||
        CASE p_result WHEN TRUE THEN 'TRUE' ELSE 'FALSE' END);
    END IF;
  END;

BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: Tam 10000 → TRUE (>= 10000)
  BEGIN
    v_result := pkg_transactions.requires_ctr_report(10000);
    print_bool('tc_01_exact_10000', v_result, TRUE);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_exact_10000|FAIL|' || SQLERRM);
  END;

  -- tc_02: 10000 üstü → TRUE
  BEGIN
    v_result := pkg_transactions.requires_ctr_report(10001);
    print_bool('tc_02_above_10000', v_result, TRUE);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_above_10000|FAIL|' || SQLERRM);
  END;

  -- tc_03: 9999 → FALSE (< 10000)
  BEGIN
    v_result := pkg_transactions.requires_ctr_report(9999);
    print_bool('tc_03_just_below_10000', v_result, FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_just_below_10000|FAIL|' || SQLERRM);
  END;

  -- tc_04: 0 → FALSE
  BEGIN
    v_result := pkg_transactions.requires_ctr_report(0);
    print_bool('tc_04_zero', v_result, FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_zero|FAIL|' || SQLERRM);
  END;

  -- tc_05: Negatif tutar → FALSE
  BEGIN
    v_result := pkg_transactions.requires_ctr_report(-1);
    print_bool('tc_05_negative', v_result, FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_negative|FAIL|' || SQLERRM);
  END;

  -- tc_06: Çok büyük tutar → TRUE
  BEGIN
    v_result := pkg_transactions.requires_ctr_report(999999);
    print_bool('tc_06_very_large', v_result, TRUE);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_very_large|FAIL|' || SQLERRM);
  END;

  -- tc_07: 50000 → TRUE (Eve'in premium hesabı büyüklüğünde)
  BEGIN
    v_result := pkg_transactions.requires_ctr_report(50000);
    print_bool('tc_07_50000', v_result, TRUE);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_50000|FAIL|' || SQLERRM);
  END;

  -- tc_08: 9999.99 → FALSE (ondalıklı, hâlâ altında)
  BEGIN
    v_result := pkg_transactions.requires_ctr_report(9999.99);
    print_bool('tc_08_just_below_decimal', v_result, FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_just_below_decimal|FAIL|' || SQLERRM);
  END;

  -- tc_09: 10000.01 → TRUE (ondalıklı, üstünde)
  BEGIN
    v_result := pkg_transactions.requires_ctr_report(10000.01);
    print_bool('tc_09_just_above_decimal', v_result, TRUE);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_just_above_decimal|FAIL|' || SQLERRM);
  END;

  -- tc_10: NULL → NULL karşılaştırması (NULL >= 10000 = NULL → ne TRUE ne FALSE)
  -- Fonksiyon NULL dönebilir — davranışı verify et
  BEGIN
    v_result := pkg_transactions.requires_ctr_report(NULL);
    IF v_result IS NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_null_amount|OK|returned:NULL');
    ELSIF v_result = FALSE THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_null_amount|OK|returned:FALSE');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_null_amount|FAIL|unexpected:TRUE');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_null_amount|FAIL|' || SQLERRM);
  END;

END;
/