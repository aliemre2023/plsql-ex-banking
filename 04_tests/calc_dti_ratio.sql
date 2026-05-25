DECLARE
  v_result NUMBER;
  v_loan_id     NUMBER;
  v_loan_number VARCHAR2(50);
  v_monthly_pay NUMBER;
  v_decision    VARCHAR2(20);
  v_credit_score NUMBER;
  v_estimated_income NUMBER;
  v_existing_debt NUMBER;

  FUNCTION estimated_income(p_credit_score IN NUMBER) RETURN NUMBER IS
  BEGIN
    RETURN CASE
      WHEN p_credit_score >= 750 THEN 8000
      WHEN p_credit_score >= 700 THEN 6000
      WHEN p_credit_score >= 650 THEN 4500
      WHEN p_credit_score >= 600 THEN 3500
      ELSE 2500
    END;
  END;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: DTI = (existing_debt + new_payment) / estimated_income
  BEGIN
    SELECT credit_score INTO v_credit_score
    FROM   customers WHERE customer_id = 1000;
    SELECT NVL(SUM(monthly_payment), 0) INTO v_existing_debt
    FROM   loans
    WHERE  customer_id = 1000 AND status = 'ACTIVE';
    v_estimated_income := estimated_income(v_credit_score);
    v_result := pkg_loan_mgmt.calc_dti_ratio(1000, 800);
    IF v_result = ROUND((v_existing_debt + 800) / v_estimated_income, 4) THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_no_active_loans|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_no_active_loans|FAIL|expected:' ||
        ROUND((v_existing_debt + 800) / v_estimated_income, 4) || ' got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_no_active_loans|FAIL|' || SQLERRM);
  END;

  -- tc_02: Active loan varken toplama eklenir
  BEGIN
    SELECT credit_score INTO v_credit_score
    FROM   customers WHERE customer_id = 1000;
    SELECT NVL(SUM(monthly_payment), 0) INTO v_existing_debt
    FROM   loans
    WHERE  customer_id = 1000 AND status = 'ACTIVE';
    v_estimated_income := estimated_income(v_credit_score);
    v_result := pkg_loan_mgmt.calc_dti_ratio(1000, 500);
    IF v_result = ROUND((v_existing_debt + 500) / v_estimated_income, 4) THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_with_existing_loans|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_with_existing_loans|FAIL|expected:' ||
        ROUND((v_existing_debt + 500) / v_estimated_income, 4) || ' got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_with_existing_loans|FAIL|' || SQLERRM);
  END;

  -- tc_03: DTI = (existing_debt + new_payment) / estimated_income
  BEGIN
    SELECT credit_score INTO v_credit_score
    FROM   customers WHERE customer_id = 1003;
    SELECT NVL(SUM(monthly_payment), 0) INTO v_existing_debt
    FROM   loans
    WHERE  customer_id = 1003 AND status = 'ACTIVE';
    v_estimated_income := estimated_income(v_credit_score);
    v_result := pkg_loan_mgmt.calc_dti_ratio(1003, 700);
    IF v_result = ROUND((v_existing_debt + 700) / v_estimated_income, 4) THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_credit_580_income_3500|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_credit_580_income_3500|FAIL|expected:' ||
        ROUND((v_existing_debt + 700) / v_estimated_income, 4) || ' got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_credit_580_income_3500|FAIL|' || SQLERRM);
  END;

  -- tc_04: DTI = (existing_debt + new_payment) / estimated_income
  BEGIN
    SELECT credit_score INTO v_credit_score
    FROM   customers WHERE customer_id = 1002;
    SELECT NVL(SUM(monthly_payment), 0) INTO v_existing_debt
    FROM   loans
    WHERE  customer_id = 1002 AND status = 'ACTIVE';
    v_estimated_income := estimated_income(v_credit_score);
    v_result := pkg_loan_mgmt.calc_dti_ratio(1002, 1200);
    IF v_result = ROUND((v_existing_debt + 1200) / v_estimated_income, 4) THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_credit_720_income_6000|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_credit_720_income_6000|FAIL|expected:' ||
        ROUND((v_existing_debt + 1200) / v_estimated_income, 4) || ' got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_credit_720_income_6000|FAIL|' || SQLERRM);
  END;

  -- tc_05: credit_score=650 → income=4500
  -- Bob, payment=900 → DTI = 900/4500 = 0.2000
  BEGIN
    v_result := pkg_loan_mgmt.calc_dti_ratio(1001, 900);
    IF v_result = 0.2000 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_credit_650_income_4500|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_credit_650_income_4500|FAIL|expected:0.2000 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_credit_650_income_4500|FAIL|' || SQLERRM);
  END;

  -- tc_06: credit_score=810 → income=8000
  -- Eve, payment=3440 → DTI = 3440/8000 = 0.4300
  -- (c_max_dti_ratio=0.43 sınırında)
  BEGIN
    v_result := pkg_loan_mgmt.calc_dti_ratio(1004, 3440);
    IF v_result = 0.4300 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_max_dti_boundary|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_max_dti_boundary|FAIL|expected:0.4300 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_max_dti_boundary|FAIL|' || SQLERRM);
  END;

  -- tc_07: Sıfır yeni ödeme → sadece mevcut debt / income
  BEGIN
    DECLARE v_existing NUMBER;
    BEGIN
      SELECT NVL(SUM(monthly_payment), 0) INTO v_existing
      FROM   loans WHERE customer_id = 1002 AND status = 'ACTIVE';
      v_result := pkg_loan_mgmt.calc_dti_ratio(1002, 0);
      IF v_result = ROUND(v_existing / 6000, 4) THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_zero_new_payment|OK|returned:' || v_result);
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_zero_new_payment|FAIL|expected:' ||
          ROUND(v_existing / 6000, 4) || ' got:' || v_result);
      END IF;
    END;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_zero_new_payment|FAIL|' || SQLERRM);
  END;

  -- tc_08: PAID_OFF loan monthly_payment sayılmaz
  -- Bob'un PAID_OFF loanu varsa aktif olmadığı için sayılmamalı
  BEGIN
    DECLARE
      v_active_debt NUMBER;
    BEGIN
      SELECT NVL(SUM(monthly_payment), 0) INTO v_active_debt
      FROM   loans WHERE customer_id = 1001 AND status = 'ACTIVE';
      v_result := pkg_loan_mgmt.calc_dti_ratio(1001, 0);
      IF v_result = ROUND(v_active_debt / 4500, 4) THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_paid_off_excluded|OK|returned:' || v_result);
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_paid_off_excluded|FAIL|expected:' ||
          ROUND(v_active_debt / 4500, 4) || ' got:' || v_result);
      END IF;
    END;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_paid_off_excluded|FAIL|' || SQLERRM);
  END;

  -- tc_09: ROUND(4) kontrolü — 4 ondalık hane
  BEGIN
    v_result := pkg_loan_mgmt.calc_dti_ratio(1000, 333);
    IF v_result = ROUND(v_result, 4) THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_rounding_4_decimals|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_rounding_4_decimals|FAIL|unexpected:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_rounding_4_decimals|FAIL|' || SQLERRM);
  END;

  -- tc_10: Yeni loan eklendikten sonra DTI artar
  BEGIN
    DECLARE
      v_before NUMBER;
      v_after  NUMBER;
    BEGIN
      v_before := pkg_loan_mgmt.calc_dti_ratio(1000, 0);
      v_after  := pkg_loan_mgmt.calc_dti_ratio(1000, 500);
      IF v_after > v_before THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_dti_increases_with_payment|OK|before:' || v_before || ' after:' || v_after);
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_dti_increases_with_payment|FAIL|before:' || v_before || ' after:' || v_after);
      END IF;
    END;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_dti_increases_with_payment|FAIL|' || SQLERRM);
  END;

  -- tc_11: Var olmayan customer_id → NO_DATA_FOUND (customers tablosundan)
  BEGIN
    v_result := pkg_loan_mgmt.calc_dti_ratio(999999, 500);
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_nonexistent_customer|FAIL|Expected exception not raised got:' || v_result);
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_nonexistent_customer|OK|exception_raised');
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_nonexistent_customer|FAIL|wrong_exception:' || SQLCODE);
  END;

END;
/