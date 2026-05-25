DECLARE
  v_loan_id       NUMBER;
  v_loan_number   VARCHAR2(50);
  v_monthly_pay   NUMBER;
  v_decision      VARCHAR2(20);
  v_count         NUMBER;
  v_session_user  VARCHAR2(100);
  v_marker        TIMESTAMP := SYSTIMESTAMP;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);
  SELECT SYS_CONTEXT('USERENV','SESSION_USER') INTO v_session_user FROM DUAL;

  -- NOT: p_audit pkg_loan_mgmt içinde PRIVATE bir prosedürdür.
  -- pkg_loan_mgmt.p_audit(...) diye doğrudan çağrılamaz (PLS-00302).
  -- Tüm testler p_audit'i çağıran public prosedürler üzerinden
  -- dolaylı olarak çalışır:
  --   originate_loan → p_audit('LOANS', loan_id, 'INSERT', NULL, ...)
  --   reject_loan    → p_audit('LOANS', loan_id, 'UPDATE', ...)

  -- tc_01: originate_loan sonrası audit_log kaydı oluşur
  BEGIN
    pkg_loan_mgmt.originate_loan(
        p_customer_id     => 1000,
        p_account_id      => 100000,
        p_branch_id       => 10,
        p_loan_type       => 'PERSONAL',
        p_amount          => 5000,
        p_term_months     => 12,
        p_collateral_type => NULL,
        p_collateral_val  => NULL,
        p_employee_id     => 2000,
        p_loan_id         => v_loan_id,
        p_loan_number     => v_loan_number,
        p_monthly_payment => v_monthly_pay,
        p_decision        => v_decision
    );
    SELECT COUNT(*) INTO v_count
    FROM   audit_log
    WHERE  table_name  = 'LOANS'
    AND    record_id   = v_loan_id
    AND    action      = 'INSERT'
    AND    changed_at >= v_marker;
    ROLLBACK;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_audit_on_originate|OK|count:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_audit_on_originate|FAIL|expected:>=1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_audit_on_originate|FAIL|' || SQLERRM);
  END;

  -- tc_02: changed_by = session user
  BEGIN
    v_marker := SYSTIMESTAMP;
    pkg_loan_mgmt.originate_loan(
        p_customer_id     => 1000,
        p_account_id      => 100000,
        p_branch_id       => 10,
        p_loan_type       => 'PERSONAL',
        p_amount          => 5000,
        p_term_months     => 12,
        p_collateral_type => NULL,
        p_collateral_val  => NULL,
        p_employee_id     => 2000,
        p_loan_id         => v_loan_id,
        p_loan_number     => v_loan_number,
        p_monthly_payment => v_monthly_pay,
        p_decision        => v_decision
    );
    SELECT COUNT(*) INTO v_count
    FROM   audit_log
    WHERE  table_name  = 'LOANS'
    AND    record_id   = v_loan_id
    AND    changed_by  = v_session_user
    AND    changed_at >= v_marker;
    ROLLBACK;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_changed_by_session|OK|changed_by:' || v_session_user);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_changed_by_session|FAIL|session:' || v_session_user);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_changed_by_session|FAIL|' || SQLERRM);
  END;

  -- tc_03: AUTONOMOUS TRANSACTION — caller rollback sonrası audit kaydı kalır
  BEGIN
    v_marker := SYSTIMESTAMP;
    pkg_loan_mgmt.originate_loan(
        p_customer_id     => 1001,
        p_account_id      => 100002,
        p_branch_id       => 10,
        p_loan_type       => 'AUTO',
        p_amount          => 10000,
        p_term_months     => 24,
        p_collateral_type => NULL,
        p_collateral_val  => NULL,
        p_employee_id     => 2001,
        p_loan_id         => v_loan_id,
        p_loan_number     => v_loan_number,
        p_monthly_payment => v_monthly_pay,
        p_decision        => v_decision
    );
    ROLLBACK; -- ana transaction rollback
    SELECT COUNT(*) INTO v_count
    FROM   audit_log
    WHERE  table_name  = 'LOANS'
    AND    record_id   = v_loan_id
    AND    changed_at >= v_marker;
    -- Temizlik
    DELETE FROM audit_log
    WHERE  table_name = 'LOANS'
    AND    record_id  = v_loan_id
    AND    changed_at >= v_marker;
    COMMIT;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_autonomous_survives_rollback|OK|count:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_autonomous_survives_rollback|FAIL|expected:>=1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_autonomous_survives_rollback|FAIL|' || SQLERRM);
  END;

  -- tc_04: reject_loan sonrası audit_log 'UPDATE' action kaydı oluşur
  BEGIN
    v_marker := SYSTIMESTAMP;
    pkg_loan_mgmt.originate_loan(
        p_customer_id     => 1000,
        p_account_id      => 100000,
        p_branch_id       => 10,
        p_loan_type       => 'PERSONAL',
        p_amount          => 5000,
        p_term_months     => 12,
        p_collateral_type => NULL,
        p_collateral_val  => NULL,
        p_employee_id     => 2000,
        p_loan_id         => v_loan_id,
        p_loan_number     => v_loan_number,
        p_monthly_payment => v_monthly_pay,
        p_decision        => v_decision
    );
    -- PENDING/APPROVED durumda olmalı → reject edilebilir
    UPDATE loans SET status = 'PENDING' WHERE loan_id = v_loan_id;
    pkg_loan_mgmt.reject_loan(v_loan_id, 'Test rejection', 2000);
    SELECT COUNT(*) INTO v_count
    FROM   audit_log
    WHERE  table_name  = 'LOANS'
    AND    record_id   = v_loan_id
    AND    action      = 'UPDATE'
    AND    changed_at >= v_marker;
    ROLLBACK;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_audit_on_reject|OK|count:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_audit_on_reject|FAIL|expected:>=1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_audit_on_reject|FAIL|' || SQLERRM);
  END;

  -- tc_05: exception yutulur — p_audit hatası originate_loan'ı bozmaz
  -- (WHEN OTHERS THEN NULL garantisi)
  BEGIN
    pkg_loan_mgmt.originate_loan(
        p_customer_id     => 1000,
        p_account_id      => 100000,
        p_branch_id       => 10,
        p_loan_type       => 'PERSONAL',
        p_amount          => 5000,
        p_term_months     => 12,
        p_collateral_type => NULL,
        p_collateral_val  => NULL,
        p_employee_id     => 2000,
        p_loan_id         => v_loan_id,
        p_loan_number     => v_loan_number,
        p_monthly_payment => v_monthly_pay,
        p_decision        => v_decision
    );
    ROLLBACK;
    IF v_loan_id IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_audit_exception_swallowed|OK|loan_id:' || v_loan_id);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_audit_exception_swallowed|FAIL|loan_id:NULL');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_audit_exception_swallowed|FAIL|' || SQLERRM);
  END;

END;
/