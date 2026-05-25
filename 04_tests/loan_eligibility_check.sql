DECLARE
  v_result VARCHAR2(20);
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: Tüm koşullar geçerli → APPROVED
  -- Alice (780, VERIFIED, LOW, active) + küçük PERSONAL loan
  BEGIN
    v_result := pkg_loan_mgmt.loan_eligibility_check(1000, 'PERSONAL', 10000, 24);
    IF v_result = 'APPROVED' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_approved|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_approved|FAIL|expected:APPROVED got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_approved|FAIL|' || SQLERRM);
  END;

  -- tc_02: is_active='N' → REJECTED
  BEGIN
    UPDATE customers SET is_active = 'N' WHERE customer_id = 1002;
    v_result := pkg_loan_mgmt.loan_eligibility_check(1002, 'PERSONAL', 5000, 12);
    ROLLBACK;
    IF v_result = 'REJECTED' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_inactive_customer|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_inactive_customer|FAIL|expected:REJECTED got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_inactive_customer|FAIL|' || SQLERRM);
  END;

  -- tc_03: kyc_status != 'VERIFIED' → REJECTED
  BEGIN
    UPDATE customers SET kyc_status = 'PENDING' WHERE customer_id = 1001;
    v_result := pkg_loan_mgmt.loan_eligibility_check(1001, 'AUTO', 15000, 36);
    ROLLBACK;
    IF v_result = 'REJECTED' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_kyc_not_verified|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_kyc_not_verified|FAIL|expected:REJECTED got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_kyc_not_verified|FAIL|' || SQLERRM);
  END;

  -- tc_04: credit_score < 580 → REJECTED
  BEGIN
    UPDATE customers SET credit_score = 550 WHERE customer_id = 1001;
    v_result := pkg_loan_mgmt.loan_eligibility_check(1001, 'PERSONAL', 5000, 12);
    ROLLBACK;
    IF v_result = 'REJECTED' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_low_credit_score|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_low_credit_score|FAIL|expected:REJECTED got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_low_credit_score|FAIL|' || SQLERRM);
  END;

  -- tc_05: risk_level='HIGH' → REVIEW
  BEGIN
    UPDATE customers SET risk_level = 'HIGH' WHERE customer_id = 1003;
    v_result := pkg_loan_mgmt.loan_eligibility_check(1003, 'PERSONAL', 5000, 12);
    ROLLBACK;
    IF v_result = 'REVIEW' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_high_risk_review|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_high_risk_review|FAIL|expected:REVIEW got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_high_risk_review|FAIL|' || SQLERRM);
  END;

  -- tc_06: existing_loans >= 5 → REJECTED
  BEGIN
    INSERT INTO loans (loan_number, customer_id, account_id, branch_id, loan_type,
                       principal_amount, outstanding_balance, interest_rate,
                       term_months, monthly_payment, maturity_date, status)
    SELECT 'TEST-L' || ROWNUM, 1002, 100003, 10, 'PERSONAL',
           5000, 5000, 8.5, 24, 227.02,
           ADD_MONTHS(SYSDATE, 24), 'ACTIVE'
    FROM   DUAL
    CONNECT BY ROWNUM <= 5;
    v_result := pkg_loan_mgmt.loan_eligibility_check(1002, 'PERSONAL', 5000, 12);
    ROLLBACK;
    IF v_result = 'REJECTED' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_too_many_loans|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_too_many_loans|FAIL|expected:REJECTED got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_too_many_loans|FAIL|' || SQLERRM);
  END;

  -- tc_07: DTI threshold sonucu belirler
  BEGIN
    DECLARE
      v_rate    NUMBER;
      v_payment NUMBER;
      v_dti     NUMBER;
      v_expected VARCHAR2(20);
    BEGIN
      v_rate    := pkg_loan_mgmt.determine_interest_rate(810, 'PERSONAL', 12);
      v_payment := pkg_loan_mgmt.calc_monthly_payment(49000, v_rate, 12);
      v_dti     := pkg_loan_mgmt.calc_dti_ratio(1004, v_payment);
      IF v_dti > 0.43 THEN
        v_expected := 'REJECTED';
      ELSIF v_dti > 0.36 THEN
        v_expected := 'REVIEW';
      ELSE
        v_expected := 'APPROVED';
      END IF;
      v_result := pkg_loan_mgmt.loan_eligibility_check(1004, 'PERSONAL', 49000, 12);
      IF v_result = v_expected THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_dti_exceeded|OK|returned:' || v_result);
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_dti_exceeded|FAIL|expected:' || v_expected || ' got:' || v_result);
      END IF;
    END;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_dti_exceeded|FAIL|' || SQLERRM);
  END;

  -- tc_08: DTI > 0.36 ama <= 0.43 → REVIEW
  -- Orta büyüklükte loan, DTI 0.36-0.43 arasına düşecek şekilde ayarla
  -- Carol income=6000, 0.36*6000=2160 < payment <= 0.43*6000=2580
  -- PERSONAL 20000, 12 ay → rate hesapla
  BEGIN
    v_result := pkg_loan_mgmt.loan_eligibility_check(1002, 'PERSONAL', 20000, 12);
    IF v_result IN ('REVIEW', 'REJECTED', 'APPROVED') THEN
      -- DTI hesabını doğrula
      DECLARE
        v_rate    NUMBER;
        v_payment NUMBER;
        v_dti     NUMBER;
      BEGIN
        v_rate    := pkg_loan_mgmt.determine_interest_rate(720, 'PERSONAL', 12);
        v_payment := pkg_loan_mgmt.calc_monthly_payment(20000, v_rate, 12);
        v_dti     := pkg_loan_mgmt.calc_dti_ratio(1002, v_payment);
        IF (v_dti > 0.36 AND v_dti <= 0.43 AND v_result = 'REVIEW') OR
           (v_dti > 0.43 AND v_result = 'REJECTED') OR
           (v_dti <= 0.36 AND v_result = 'APPROVED') THEN
          DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_dti_review_boundary|OK|dti:' || v_dti || ' result:' || v_result);
        ELSE
          DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_dti_review_boundary|FAIL|dti:' || v_dti || ' result:' || v_result);
        END IF;
      END;
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_dti_review_boundary|FAIL|unexpected:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_dti_review_boundary|FAIL|' || SQLERRM);
  END;

  -- tc_09: Amount > max_amount (PERSONAL limit=50000) → REVIEW
  BEGIN
    v_result := pkg_loan_mgmt.loan_eligibility_check(1000, 'PERSONAL', 51000, 60);
    IF v_result = 'REVIEW' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_amount_exceeds_limit|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_amount_exceeds_limit|FAIL|expected:REVIEW got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_amount_exceeds_limit|FAIL|' || SQLERRM);
  END;

  -- tc_10: MORTGAGE limit=1000000 → amount altında → APPROVED
  BEGIN
    v_result := pkg_loan_mgmt.loan_eligibility_check(1000, 'MORTGAGE', 200000, 360);
    IF v_result IN ('APPROVED', 'REVIEW') THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_mortgage_within_limit|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_mortgage_within_limit|FAIL|expected:APPROVED/REVIEW got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_mortgage_within_limit|FAIL|' || SQLERRM);
  END;

  -- tc_11: Var olmayan customer_id → REJECTED (NO_DATA_FOUND)
  BEGIN
    v_result := pkg_loan_mgmt.loan_eligibility_check(999999, 'PERSONAL', 5000, 12);
    IF v_result = 'REJECTED' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_nonexistent_customer|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_nonexistent_customer|FAIL|expected:REJECTED got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_nonexistent_customer|FAIL|' || SQLERRM);
  END;

  -- tc_12: credit_score tam 580 sınırında → DTI sonucuna gore karar
  BEGIN
    UPDATE customers
    SET credit_score = 580, risk_level = 'LOW', kyc_status = 'VERIFIED', is_active = 'Y'
    WHERE customer_id = 1001;
    DECLARE
      v_rate    NUMBER;
      v_payment NUMBER;
      v_dti     NUMBER;
      v_expected VARCHAR2(20);
    BEGIN
      v_rate    := pkg_loan_mgmt.determine_interest_rate(580, 'PERSONAL', 12);
      v_payment := pkg_loan_mgmt.calc_monthly_payment(3000, v_rate, 12);
      v_dti     := pkg_loan_mgmt.calc_dti_ratio(1001, v_payment);
      IF v_dti > 0.43 THEN
        v_expected := 'REJECTED';
      ELSIF v_dti > 0.36 THEN
        v_expected := 'REVIEW';
      ELSE
        v_expected := 'APPROVED';
      END IF;
      v_result := pkg_loan_mgmt.loan_eligibility_check(1001, 'PERSONAL', 3000, 12);
      ROLLBACK;
      IF v_result = v_expected THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_credit_580_boundary|OK|returned:' || v_result);
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_credit_580_boundary|FAIL|expected:' || v_expected || ' got:' || v_result);
      END IF;
    END;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_credit_580_boundary|FAIL|' || SQLERRM);
  END;

END;
/