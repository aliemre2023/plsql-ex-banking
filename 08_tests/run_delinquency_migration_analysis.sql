-- =============================================================================
-- TEST: run_delinquency_migration_analysis
-- Package: pkg_advanced_risk_engine
-- =============================================================================
-- Seed data (01_DDL_SCHEMA.sql):
--   customer_id 1000 = Alice Johnson  | credit_score=720, LOW
--   customer_id 1001 = Bob Smith       | credit_score=680, LOW
--   customer_id 1002 = Carol Davis     | credit_score=760, LOW
--   customer_id 1003 = David Wilson    | credit_score=590, MEDIUM
--   customer_id 1004 = Eve Martinez    | credit_score=800, LOW
--
--   account_id 100000 = ACC-100001 | customer_id=1000 | branch_id=10 | CHECKING
--   account_id 100001 = ACC-100002 | customer_id=1000 | branch_id=10 | SAVINGS
--   account_id 100002 = ACC-100003 | customer_id=1001 | branch_id=10 | CHECKING
--   account_id 100003 = ACC-100004 | customer_id=1002 | branch_id=11 | SAVINGS
--   account_id 100004 = ACC-100005 | customer_id=1003 | branch_id=11 | CHECKING
--   account_id 100005 = ACC-100006 | customer_id=1004 | branch_id=10 | PREMIUM
--   account_id 100006 = ACC-100007 | customer_id=1004 | branch_id=10 | MONEY_MKT
--
--   branch_id  10 = HQ001  | employee_id 2000 (manager)
--   branch_id  11 = BR002  | employee_id 2001 (manager)
--   employee_id 2000 = John Smith (MANAGER)
--   employee_id 2001 = Jane Doe  (LOAN_OFFICER)
-- =============================================================================

DECLARE
  v_migration_cursor SYS_REFCURSOR;
  v_summary_cursor   SYS_REFCURSOR;
  v_count            NUMBER;
  v_loan_id          NUMBER;
  v_loan_number      VARCHAR2(50);
  v_monthly_pay      NUMBER;
  v_decision         VARCHAR2(20);
  v_dummy_num        NUMBER;
  v_dummy_str        VARCHAR2(200);
  v_dummy_date       DATE;
  v_found_default    BOOLEAN;

  -- Summary cursor returns 13 columns:
  --   1  current_bucket         VARCHAR2
  --   2  loan_count             NUMBER
  --   3  total_balance          NUMBER
  --   4  avg_balance            NUMBER
  --   5  pct_of_portfolio       NUMBER
  --   6  avg_dpd                NUMBER
  --   7  max_dpd                NUMBER
  --   8  total_30dpd_events     NUMBER
  --   9  total_60dpd_events     NUMBER
  --  10  total_90dpd_events     NUMBER
  --  11  analysis_period_months NUMBER
  --  12  period_from            DATE  ← DATE, not NUMBER
  --  13  period_to              DATE  ← DATE, not NUMBER

  -- Migration cursor returns 15 columns:
  --   1  loan_id          NUMBER
  --   2  loan_number      VARCHAR2
  --   3  loan_type        VARCHAR2
  --   4  bucket_start     VARCHAR2
  --   5  bucket_end       VARCHAR2
  --   6  balance_start    NUMBER
  --   7  balance_end      NUMBER
  --   8  balance_delta    NUMBER
  --   9  dpd_start        NUMBER
  --  10  dpd_end          NUMBER
  --  11  dpd_change       NUMBER
  --  12  total_paid       NUMBER
  --  13  overdue_count    NUMBER
  --  14  migration_dir    VARCHAR2
  --  15  rank             NUMBER

  PROCEDURE make_loan(
    p_customer_id IN NUMBER,
    p_account_id  IN NUMBER,
    p_branch_id   IN NUMBER,
    p_amount      IN NUMBER,
    p_type        IN VARCHAR2 DEFAULT 'PERSONAL',
    p_dpd         IN NUMBER   DEFAULT 0
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
    UPDATE loans
       SET status            = 'ACTIVE',
           disbursement_date = SYSDATE - 60,
           days_past_due     = p_dpd
     WHERE loan_id = v_loan_id;
  END;

BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: Geçerli tarih aralığında iki cursor açık döner
  BEGIN
    -- Alice (1000) checking (100000) branch10
    -- Bob   (1001) checking (100002) branch10
    make_loan(1000, 100000, 10, 10000);
    make_loan(1001, 100002, 10, 15000, 'AUTO', 30);
    pkg_advanced_risk_engine.run_delinquency_migration_analysis(
        SYSDATE - 90, SYSDATE, NULL,
        v_migration_cursor, v_summary_cursor
    );
    IF v_migration_cursor%ISOPEN AND v_summary_cursor%ISOPEN THEN
      CLOSE v_migration_cursor;
      CLOSE v_summary_cursor;
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_both_cursors_open|OK|both_open');
    ELSE
      IF v_migration_cursor%ISOPEN THEN CLOSE v_migration_cursor; END IF;
      IF v_summary_cursor%ISOPEN   THEN CLOSE v_summary_cursor;   END IF;
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_both_cursors_open|FAIL|cursor_not_open');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF v_migration_cursor%ISOPEN THEN CLOSE v_migration_cursor; END IF;
      IF v_summary_cursor%ISOPEN   THEN CLOSE v_summary_cursor;   END IF;
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_both_cursors_open|FAIL|' || SQLERRM);
  END;

  -- tc_02: NULL from_date → -20202 exception
  BEGIN
    pkg_advanced_risk_engine.run_delinquency_migration_analysis(
        NULL, SYSDATE, NULL,
        v_migration_cursor, v_summary_cursor
    );
    IF v_migration_cursor%ISOPEN THEN CLOSE v_migration_cursor; END IF;
    IF v_summary_cursor%ISOPEN   THEN CLOSE v_summary_cursor;   END IF;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_null_from_date|FAIL|expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -20202 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_null_from_date|OK|exception_raised:-20202');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_null_from_date|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_03: to_date <= from_date → -20202 exception
  BEGIN
    pkg_advanced_risk_engine.run_delinquency_migration_analysis(
        SYSDATE, SYSDATE - 10, NULL,
        v_migration_cursor, v_summary_cursor
    );
    IF v_migration_cursor%ISOPEN THEN CLOSE v_migration_cursor; END IF;
    IF v_summary_cursor%ISOPEN   THEN CLOSE v_summary_cursor;   END IF;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_to_before_from|FAIL|expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -20202 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_to_before_from|OK|exception_raised:-20202');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_to_before_from|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_04: summary_cursor DPD bucket satırları döndürür
  BEGIN
    -- Alice (1000/100000/branch10) dpd=0  → CURRENT bucket
    -- Bob   (1001/100002/branch10) dpd=45 → 31-60DPD bucket
    -- Carol (1002/100003/branch11) dpd=75 → 61-90DPD bucket
    make_loan(1000, 100000, 10, 10000, 'PERSONAL', 0);
    make_loan(1001, 100002, 10, 15000, 'AUTO',     45);
    make_loan(1002, 100003, 11, 20000, 'MORTGAGE', 75);
    pkg_advanced_risk_engine.run_delinquency_migration_analysis(
        SYSDATE - 90, SYSDATE, NULL,
        v_migration_cursor, v_summary_cursor
    );
    IF v_migration_cursor%ISOPEN THEN CLOSE v_migration_cursor; END IF;
    v_count := 0;
    LOOP
      -- 13 cols: VARCHAR2, 10×NUMBER, DATE, DATE
      FETCH v_summary_cursor INTO
            v_dummy_str,  -- 1  current_bucket
            v_dummy_num,  -- 2  loan_count
            v_dummy_num,  -- 3  total_balance
            v_dummy_num,  -- 4  avg_balance
            v_dummy_num,  -- 5  pct_of_portfolio
            v_dummy_num,  -- 6  avg_dpd
            v_dummy_num,  -- 7  max_dpd
            v_dummy_num,  -- 8  total_30dpd_events
            v_dummy_num,  -- 9  total_60dpd_events
            v_dummy_num,  -- 10 total_90dpd_events
            v_dummy_num,  -- 11 analysis_period_months
            v_dummy_date, -- 12 period_from  (DATE)
            v_dummy_date; -- 13 period_to    (DATE)
      EXIT WHEN v_summary_cursor%NOTFOUND;
      v_count := v_count + 1;
    END LOOP;
    CLOSE v_summary_cursor;
    ROLLBACK;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_summary_has_rows|OK|rows:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_summary_has_rows|FAIL|no_rows');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF v_migration_cursor%ISOPEN THEN CLOSE v_migration_cursor; END IF;
      IF v_summary_cursor%ISOPEN   THEN CLOSE v_summary_cursor;   END IF;
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_summary_has_rows|FAIL|' || SQLERRM);
  END;

  -- tc_05: Farklı DPD'li loanlar farklı bucket'lara düşer (en az 2 farklı bucket)
  BEGIN
    -- dpd=0 → CURRENT, dpd=45 → 31-60DPD, dpd=95 → 91-180DPD → 3 farklı bucket
    make_loan(1000, 100000, 10, 10000, 'PERSONAL', 0);
    make_loan(1001, 100002, 10, 15000, 'AUTO',     45);
    make_loan(1003, 100004, 11, 20000, 'BUSINESS', 95);
    SELECT COUNT(DISTINCT
        CASE
          WHEN l.days_past_due = 0         THEN 'CURRENT'
          WHEN l.days_past_due <= 30        THEN '1-30DPD'
          WHEN l.days_past_due <= 60        THEN '31-60DPD'
          WHEN l.days_past_due <= 90        THEN '61-90DPD'
          WHEN l.days_past_due <= 180       THEN '91-180DPD'
          ELSE                                   '180+DPD'
        END)
    INTO v_count
    FROM loans l
    WHERE l.status = 'ACTIVE';
    ROLLBACK;
    IF v_count >= 2 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_multiple_dpd_buckets|OK|distinct_buckets:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_multiple_dpd_buckets|FAIL|buckets:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_multiple_dpd_buckets|FAIL|' || SQLERRM);
  END;

  -- tc_06: branch_id=10 filtresiyle çalışır, exception çıkmaz
  BEGIN
    -- Alice ve Bob branch10'da → branch_id=10 filtresi bunları yakalar
    make_loan(1000, 100000, 10, 10000);
    make_loan(1001, 100002, 10, 12000, 'AUTO', 15);
    pkg_advanced_risk_engine.run_delinquency_migration_analysis(
        SYSDATE - 30, SYSDATE, 10,
        v_migration_cursor, v_summary_cursor
    );
    IF v_migration_cursor%ISOPEN THEN CLOSE v_migration_cursor; END IF;
    IF v_summary_cursor%ISOPEN   THEN CLOSE v_summary_cursor;   END IF;
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_branch_filter|OK|no_exception');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_branch_filter|FAIL|' || SQLERRM);
  END;

  -- tc_07: DEFAULTED loan → summary'de 'D - DEFAULT' bucket görünür
  BEGIN
    -- Bob (1001) defaulted loan
    make_loan(1001, 100002, 10, 20000, 'PERSONAL', 0);
    UPDATE loans SET status = 'DEFAULTED' WHERE loan_id = v_loan_id;
    pkg_advanced_risk_engine.run_delinquency_migration_analysis(
        SYSDATE - 60, SYSDATE, NULL,
        v_migration_cursor, v_summary_cursor
    );
    IF v_migration_cursor%ISOPEN THEN CLOSE v_migration_cursor; END IF;
    v_found_default := FALSE;
    LOOP
      FETCH v_summary_cursor INTO
            v_dummy_str,  -- 1  current_bucket  ← 'D - DEFAULT' bekleniyor
            v_dummy_num,  -- 2  loan_count
            v_dummy_num,  -- 3  total_balance
            v_dummy_num,  -- 4  avg_balance
            v_dummy_num,  -- 5  pct_of_portfolio
            v_dummy_num,  -- 6  avg_dpd
            v_dummy_num,  -- 7  max_dpd
            v_dummy_num,  -- 8  total_30dpd_events
            v_dummy_num,  -- 9  total_60dpd_events
            v_dummy_num,  -- 10 total_90dpd_events
            v_dummy_num,  -- 11 analysis_period_months
            v_dummy_date, -- 12 period_from  (DATE)
            v_dummy_date; -- 13 period_to    (DATE)
      EXIT WHEN v_summary_cursor%NOTFOUND;
      IF v_dummy_str = 'D - DEFAULT' THEN
        v_found_default := TRUE;
      END IF;
    END LOOP;
    CLOSE v_summary_cursor;
    ROLLBACK;
    IF v_found_default THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_defaulted_bucket|OK|found_default_bucket');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_defaulted_bucket|FAIL|default_bucket_not_found');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF v_migration_cursor%ISOPEN THEN CLOSE v_migration_cursor; END IF;
      IF v_summary_cursor%ISOPEN   THEN CLOSE v_summary_cursor;   END IF;
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_defaulted_bucket|FAIL|' || SQLERRM);
  END;

  -- tc_08: 1 yıllık analiz dönemi hata vermez
  BEGIN
    make_loan(1000, 100000, 10, 10000);
    pkg_advanced_risk_engine.run_delinquency_migration_analysis(
        ADD_MONTHS(SYSDATE, -12), SYSDATE, NULL,
        v_migration_cursor, v_summary_cursor
    );
    IF v_migration_cursor%ISOPEN THEN CLOSE v_migration_cursor; END IF;
    IF v_summary_cursor%ISOPEN   THEN CLOSE v_summary_cursor;   END IF;
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_full_year_period|OK|no_exception');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_full_year_period|FAIL|' || SQLERRM);
  END;

END;
/
