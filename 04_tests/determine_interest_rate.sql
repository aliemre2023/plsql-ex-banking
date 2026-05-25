DECLARE
  v_result NUMBER;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: MORTGAGE + excellent credit (>=800) + kısa vade (<=12)
  -- base=7.00, spread=-1.5, term=-0.25 → 5.25
  BEGIN
    v_result := pkg_loan_mgmt.determine_interest_rate(820, 'MORTGAGE', 12);
    IF v_result = 5.25 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_mortgage_excellent_short|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_mortgage_excellent_short|FAIL|expected:5.25 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_mortgage_excellent_short|FAIL|' || SQLERRM);
  END;

  -- tc_02: PERSONAL + fair credit (>=660) + orta vade (<=36)
  -- base=10.00, spread=0.0, term=0.00 → 10.00
  BEGIN
    v_result := pkg_loan_mgmt.determine_interest_rate(670, 'PERSONAL', 24);
    IF v_result = 10.00 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_personal_fair_medium|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_personal_fair_medium|FAIL|expected:10.00 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_personal_fair_medium|FAIL|' || SQLERRM);
  END;

  -- tc_03: AUTO + poor credit (>=620) + uzun vade (<=60)
  -- base=7.50, spread=1.5, term=0.25 → 9.25
  BEGIN
    v_result := pkg_loan_mgmt.determine_interest_rate(630, 'AUTO', 48);
    IF v_result = 9.25 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_auto_poor_long|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_auto_poor_long|FAIL|expected:9.25 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_auto_poor_long|FAIL|' || SQLERRM);
  END;

  -- tc_04: BUSINESS + very good (>=740) + medium-long (<=120)
  -- base=8.00, spread=-1.0, term=0.50 → 7.50
  BEGIN
    v_result := pkg_loan_mgmt.determine_interest_rate(750, 'BUSINESS', 84);
    IF v_result = 7.50 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_business_verygood_120|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_business_verygood_120|FAIL|expected:7.50 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_business_verygood_120|FAIL|' || SQLERRM);
  END;

  -- tc_05: STUDENT + good (>=700) + vade >120 ay
  -- base=6.50, spread=-0.5, term=0.75 → 6.75
  BEGIN
    v_result := pkg_loan_mgmt.determine_interest_rate(710, 'STUDENT', 180);
    IF v_result = 6.75 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_student_good_180|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_student_good_180|FAIL|expected:6.75 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_student_good_180|FAIL|' || SQLERRM);
  END;

  -- tc_06: HELOC + bad credit (>=580) + orta vade (<=36)
  -- base=7.30, spread=3.0, term=0.00 → 10.30
  BEGIN
    v_result := pkg_loan_mgmt.determine_interest_rate(590, 'HELOC', 36);
    IF v_result = 10.30 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_heloc_bad_medium|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_heloc_bad_medium|FAIL|expected:10.30 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_heloc_bad_medium|FAIL|' || SQLERRM);
  END;

  -- tc_07: Bilinmeyen loan type → ELSE (prime+5.0=10.50) + good + short
  -- base=10.50, spread=-0.5, term=-0.25 → 9.75
  BEGIN
    v_result := pkg_loan_mgmt.determine_interest_rate(700, 'UNKNOWN', 6);
    IF v_result = 9.75 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_unknown_type_fallback|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_unknown_type_fallback|FAIL|expected:9.75 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_unknown_type_fallback|FAIL|' || SQLERRM);
  END;

  -- tc_08: Çok düşük credit score (<580) → spread=5.0 (very bad)
  -- PERSONAL + <580 + <=36 → 10.00 + 5.0 + 0.00 = 15.00
  BEGIN
    v_result := pkg_loan_mgmt.determine_interest_rate(500, 'PERSONAL', 24);
    IF v_result = 15.00 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_very_bad_credit|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_very_bad_credit|FAIL|expected:15.00 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_very_bad_credit|FAIL|' || SQLERRM);
  END;

  -- tc_09: Tam sınır değerleri — credit=800 (excellent eşiği)
  -- MORTGAGE + 800 + <=36 → 7.00 + (-1.5) + 0.00 = 5.50
  BEGIN
    v_result := pkg_loan_mgmt.determine_interest_rate(800, 'MORTGAGE', 24);
    IF v_result = 5.50 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_credit_800_boundary|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_credit_800_boundary|FAIL|expected:5.50 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_credit_800_boundary|FAIL|' || SQLERRM);
  END;

  -- tc_10: Tam sınır — term=12 (<=12 eşiği, adj=-0.25)
  -- AUTO + fair(>=660) + 12 → 7.50 + 0.0 + (-0.25) = 7.25
  BEGIN
    v_result := pkg_loan_mgmt.determine_interest_rate(660, 'AUTO', 12);
    IF v_result = 7.25 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_term_12_boundary|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_term_12_boundary|FAIL|expected:7.25 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_term_12_boundary|FAIL|' || SQLERRM);
  END;

  -- tc_11: Tam sınır — term=13 (>12, <=36 eşiği, adj=0.00)
  -- AUTO + fair + 13 → 7.50 + 0.0 + 0.00 = 7.50
  BEGIN
    v_result := pkg_loan_mgmt.determine_interest_rate(660, 'AUTO', 13);
    IF v_result = 7.50 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_term_13_boundary|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_term_13_boundary|FAIL|expected:7.50 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_term_13_boundary|FAIL|' || SQLERRM);
  END;

  -- tc_12: Sonuç her zaman pozitif
  BEGIN
    v_result := pkg_loan_mgmt.determine_interest_rate(850, 'STUDENT', 6);
    IF v_result > 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_always_positive|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_always_positive|FAIL|non_positive:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_always_positive|FAIL|' || SQLERRM);
  END;

  -- tc_13: ROUND(2) kontrolü
  BEGIN
    v_result := pkg_loan_mgmt.determine_interest_rate(715, 'PERSONAL', 48);
    IF v_result = ROUND(v_result, 2) THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_rounding|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_rounding|FAIL|unexpected:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_rounding|FAIL|' || SQLERRM);
  END;

END;
/