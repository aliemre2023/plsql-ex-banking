-- =============================================================================
-- TEST: calculate_herfindahl_index
-- Package: pkg_advanced_risk_engine
-- =============================================================================
-- Seed data (01_DDL_SCHEMA.sql):
--   customer_id 1000=Alice | account_id 100000=CHECKING | branch_id=10
--   customer_id 1001=Bob   | account_id 100002=CHECKING | branch_id=10
--   customer_id 1002=Carol | account_id 100003=SAVINGS  | branch_id=11
--   customer_id 1003=David | account_id 100004=CHECKING | branch_id=11
--   customer_id 1004=Eve   | account_id 100005=PREMIUM  | branch_id=10
-- =============================================================================

DECLARE
  v_hhi        NUMBER;
  v_loan_id    NUMBER;
  v_loan_number VARCHAR2(50);
  v_monthly_pay NUMBER;
  v_decision   VARCHAR2(20);

  PROCEDURE make_loan(
    p_customer_id IN NUMBER,
    p_account_id  IN NUMBER,
    p_branch_id   IN NUMBER,
    p_amount      IN NUMBER,
    p_type        IN VARCHAR2
  ) IS
  BEGIN
    pkg_loan_mgmt.originate_loan(
        p_customer_id => p_customer_id,
        p_account_id  => p_account_id,
        p_branch_id   => p_branch_id,
        p_loan_type   => p_type,
        p_amount      => p_amount,
        p_term_months => 24,
        p_employee_id => 2000,
        p_loan_id         => v_loan_id,
        p_loan_number     => v_loan_number,
        p_monthly_payment => v_monthly_pay,
        p_decision        => v_decision
    );
    UPDATE loans SET status = 'ACTIVE', disbursement_date = SYSDATE
    WHERE loan_id = v_loan_id;
  END;

BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: LOAN_TYPE boyutu → sonuç 0-1 aralığında
  BEGIN
    v_hhi := pkg_advanced_risk_engine.calculate_herfindahl_index('LOAN_TYPE');
    IF v_hhi >= 0 AND v_hhi <= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_loan_type_range|OK|hhi:' || v_hhi);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_loan_type_range|FAIL|out_of_range:' || v_hhi);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_loan_type_range|FAIL|' || SQLERRM);
  END;

  -- tc_02: GEOGRAPHY boyutu → sonuç 0-1 aralığında
  BEGIN
    v_hhi := pkg_advanced_risk_engine.calculate_herfindahl_index('GEOGRAPHY');
    IF v_hhi >= 0 AND v_hhi <= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_geography_range|OK|hhi:' || v_hhi);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_geography_range|FAIL|out_of_range:' || v_hhi);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_geography_range|FAIL|' || SQLERRM);
  END;

  -- tc_03: CUSTOMER boyutu → sonuç 0-1 aralığında
  BEGIN
    v_hhi := pkg_advanced_risk_engine.calculate_herfindahl_index('CUSTOMER');
    IF v_hhi >= 0 AND v_hhi <= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_customer_range|OK|hhi:' || v_hhi);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_customer_range|FAIL|out_of_range:' || v_hhi);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_customer_range|FAIL|' || SQLERRM);
  END;

  -- tc_04: Geçersiz boyut → -1 döner
  BEGIN
    v_hhi := pkg_advanced_risk_engine.calculate_herfindahl_index('INVALID_DIM');
    IF v_hhi = -1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_invalid_dimension_minus1|OK|returned:-1');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_invalid_dimension_minus1|FAIL|expected:-1 got:' || v_hhi);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_invalid_dimension_minus1|FAIL|' || SQLERRM);
  END;

  -- tc_05: Tüm portföy tek tür loan → HHI = 1.0 (maksimum konsantrasyon)
  BEGIN
    -- Mevcut aktif loanları kapat, sonra sadece PERSONAL ekle
    UPDATE loans SET status = 'PAID_OFF' WHERE status IN ('ACTIVE','DEFAULTED');
    make_loan(1000, 100000, 10, 50000, 'PERSONAL'); -- Alice, branch10
    make_loan(1001, 100002, 10, 30000, 'PERSONAL'); -- Bob, branch10
    make_loan(1002, 100003, 11, 20000, 'PERSONAL'); -- Carol, branch11
    v_hhi := pkg_advanced_risk_engine.calculate_herfindahl_index('LOAN_TYPE');
    ROLLBACK;
    IF v_hhi = 1.0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_single_type_hhi_equals_1|OK|hhi:' || v_hhi);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_single_type_hhi_equals_1|FAIL|expected:1 got:' || v_hhi);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_single_type_hhi_equals_1|FAIL|' || SQLERRM);
  END;

  -- tc_06: branch_id filtresiyle çağrı yapılabilir
  BEGIN
    v_hhi := pkg_advanced_risk_engine.calculate_herfindahl_index('LOAN_TYPE', 10);
    IF v_hhi >= 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_branch_filter|OK|hhi:' || v_hhi);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_branch_filter|FAIL|hhi:' || v_hhi);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_branch_filter|FAIL|' || SQLERRM);
  END;

  -- tc_07: Sonuç 6 ondalık haneye yuvarlanır
  BEGIN
    v_hhi := pkg_advanced_risk_engine.calculate_herfindahl_index('LOAN_TYPE');
    IF v_hhi = ROUND(v_hhi, 6) THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_hhi_6_decimal_precision|OK|hhi:' || v_hhi);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_hhi_6_decimal_precision|FAIL|not_rounded:' || v_hhi);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_hhi_6_decimal_precision|FAIL|' || SQLERRM);
  END;

  -- tc_08: Aktif loan yoksa HHI = 0
  BEGIN
    UPDATE loans SET status = 'PAID_OFF' WHERE status IN ('ACTIVE','DEFAULTED');
    v_hhi := pkg_advanced_risk_engine.calculate_herfindahl_index('LOAN_TYPE');
    ROLLBACK;
    IF v_hhi = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_no_active_loans_hhi_zero|OK|hhi:0');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_no_active_loans_hhi_zero|FAIL|expected:0 got:' || v_hhi);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_no_active_loans_hhi_zero|FAIL|' || SQLERRM);
  END;

  -- tc_09: Çeşitlendirilmiş portföyde HHI < 0.5 (eşit dağılım → düşük konsantrasyon)
  BEGIN
    UPDATE loans SET status = 'PAID_OFF' WHERE status IN ('ACTIVE','DEFAULTED');
    make_loan(1000, 100000, 10, 20000, 'PERSONAL');  -- Alice, branch10
    make_loan(1000, 100001, 10, 20000, 'MORTGAGE');  -- Alice savings, branch10
    make_loan(1001, 100002, 10, 20000, 'AUTO');      -- Bob, branch10
    make_loan(1002, 100003, 11, 20000, 'BUSINESS');  -- Carol, branch11
    make_loan(1003, 100004, 11, 20000, 'STUDENT');   -- David, branch11
    v_hhi := pkg_advanced_risk_engine.calculate_herfindahl_index('LOAN_TYPE');
    ROLLBACK;
    IF v_hhi < 0.5 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_diversified_hhi_lt_half|OK|hhi:' || v_hhi);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_diversified_hhi_lt_half|FAIL|hhi_too_high:' || v_hhi);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_diversified_hhi_lt_half|FAIL|' || SQLERRM);
  END;

END;
/
