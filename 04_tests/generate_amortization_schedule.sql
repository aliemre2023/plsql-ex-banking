DECLARE
  v_loan_id     NUMBER;
  v_loan_number VARCHAR2(50);
  v_monthly_pay NUMBER;
  v_decision    VARCHAR2(20);
  v_count       NUMBER;
  v_amount      NUMBER;
  v_date1       DATE;
  v_date2       DATE;
  v_interest    NUMBER;
  v_principal   NUMBER;

  -- Helper: loan oluşturur
  PROCEDURE make_loan(
    p_customer_id IN NUMBER,
    p_account_id  IN NUMBER,
    p_amount      IN NUMBER DEFAULT 10000,
    p_term        IN NUMBER DEFAULT 12,
    p_type        IN VARCHAR2 DEFAULT 'PERSONAL'
  ) IS
  BEGIN
    pkg_loan_mgmt.originate_loan(
        p_customer_id => p_customer_id, p_account_id => p_account_id,
        p_branch_id => 10, p_loan_type => p_type,
        p_amount => p_amount, p_term_months => p_term,
        p_employee_id => 2000,
        p_loan_id => v_loan_id, p_loan_number => v_loan_number,
        p_monthly_payment => v_monthly_pay, p_decision => v_decision
    );
  END;

BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: term_months kadar SCHEDULED kayıt oluşur
  BEGIN
    make_loan(1000, 100000, 10000, 12);
    pkg_loan_mgmt.generate_amortization_schedule(v_loan_id, SYSDATE);
    SELECT COUNT(*) INTO v_count
    FROM   loan_payments
    WHERE  loan_id = v_loan_id AND status = 'SCHEDULED';
    ROLLBACK;
    IF v_count = 12 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_payment_count|OK|count:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_payment_count|FAIL|expected:12 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_payment_count|FAIL|' || SQLERRM);
  END;

  -- tc_02: scheduled_amount = loan.monthly_payment her satırda
  BEGIN
    make_loan(1000, 100000, 10000, 12);
    pkg_loan_mgmt.generate_amortization_schedule(v_loan_id, SYSDATE);
    SELECT COUNT(*) INTO v_count
    FROM   loan_payments
    WHERE  loan_id          = v_loan_id
    AND    status           = 'SCHEDULED'
    AND    scheduled_amount = v_monthly_pay;
    ROLLBACK;
    IF v_count = 12 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_scheduled_amount|OK|all_match:' || v_monthly_pay);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_scheduled_amount|FAIL|expected:12 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_scheduled_amount|FAIL|' || SQLERRM);
  END;

  -- tc_03: due_date aylık artar (ADD_MONTHS mantığı)
  BEGIN
    make_loan(1000, 100000, 10000, 3);
    pkg_loan_mgmt.generate_amortization_schedule(v_loan_id, SYSDATE);
    SELECT MIN(due_date), MAX(due_date) INTO v_date1, v_date2
    FROM   loan_payments
    WHERE  loan_id = v_loan_id AND status = 'SCHEDULED';
    ROLLBACK;
    IF v_date2 = ADD_MONTHS(v_date1, 2) THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_due_dates_monthly|OK|min:' ||
        TO_CHAR(v_date1,'YYYY-MM-DD') || ' max:' || TO_CHAR(v_date2,'YYYY-MM-DD'));
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_due_dates_monthly|FAIL|min:' ||
        TO_CHAR(v_date1,'YYYY-MM-DD') || ' max:' || TO_CHAR(v_date2,'YYYY-MM-DD'));
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_due_dates_monthly|FAIL|' || SQLERRM);
  END;

  -- tc_04: İlk ödeme due_date = TRUNC(start,'MM') + 28
  BEGIN
    make_loan(1000, 100000, 10000, 12);
    pkg_loan_mgmt.generate_amortization_schedule(v_loan_id, SYSDATE);
    SELECT MIN(due_date) INTO v_date1
    FROM   loan_payments
    WHERE  loan_id = v_loan_id AND status = 'SCHEDULED';
    ROLLBACK;
    IF v_date1 = TRUNC(SYSDATE, 'MM') + 28 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_first_due_date|OK|due:' || TO_CHAR(v_date1,'YYYY-MM-DD'));
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_first_due_date|FAIL|expected:' ||
        TO_CHAR(TRUNC(SYSDATE,'MM')+28,'YYYY-MM-DD') || ' got:' || TO_CHAR(v_date1,'YYYY-MM-DD'));
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_first_due_date|FAIL|' || SQLERRM);
  END;

  -- tc_05: principal_portion + interest_portion = scheduled_amount (ilk ödeme)
  BEGIN
    make_loan(1000, 100000, 10000, 12);
    pkg_loan_mgmt.generate_amortization_schedule(v_loan_id, SYSDATE);
    SELECT principal_portion + interest_portion INTO v_amount
    FROM   loan_payments
    WHERE  loan_id = v_loan_id AND status = 'SCHEDULED'
    ORDER BY due_date ASC
    FETCH FIRST 1 ROW ONLY;
    ROLLBACK;
    IF ROUND(v_amount, 2) = ROUND(v_monthly_pay, 2) THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_split_sum_equals_payment|OK|sum:' || v_amount);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_split_sum_equals_payment|FAIL|expected:' ||
        v_monthly_pay || ' got:' || v_amount);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_split_sum_equals_payment|FAIL|' || SQLERRM);
  END;

  -- tc_06: Son ödeme → principal = kalan bakiye (tam ödeme)
  BEGIN
    make_loan(1000, 100000, 10000, 12);
    pkg_loan_mgmt.generate_amortization_schedule(v_loan_id, SYSDATE);
    SELECT principal_portion INTO v_principal
    FROM   loan_payments
    WHERE  loan_id = v_loan_id AND status = 'SCHEDULED'
    ORDER BY due_date DESC
    FETCH FIRST 1 ROW ONLY;
    ROLLBACK;
    -- Son ödeme bakiye sıfırlamalı → pozitif olmalı
    IF v_principal > 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_last_payment_principal|OK|principal:' || v_principal);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_last_payment_principal|FAIL|non_positive:' || v_principal);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_last_payment_principal|FAIL|' || SQLERRM);
  END;

  -- tc_07: interest_portion azalır, principal_portion artar (amortisman mantığı)
  BEGIN
    make_loan(1000, 100000, 10000, 12);
    pkg_loan_mgmt.generate_amortization_schedule(v_loan_id, SYSDATE);
    DECLARE
      v_first_int  NUMBER;
      v_last_int   NUMBER;
      v_first_prin NUMBER;
      v_last_prin  NUMBER;
    BEGIN
      SELECT interest_portion, principal_portion INTO v_first_int, v_first_prin
      FROM   loan_payments WHERE loan_id = v_loan_id AND status = 'SCHEDULED'
      ORDER BY due_date ASC FETCH FIRST 1 ROW ONLY;
      -- Son ödeme özel case (v_principal = v_balance) → ikinci sonuncuyu alalım
      SELECT interest_portion, principal_portion INTO v_last_int, v_last_prin
      FROM   loan_payments WHERE loan_id = v_loan_id AND status = 'SCHEDULED'
      ORDER BY due_date DESC OFFSET 1 ROW FETCH NEXT 1 ROW ONLY;
      ROLLBACK;
      IF v_last_int < v_first_int AND v_last_prin > v_first_prin THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_amortization_pattern|OK|interest_decreases principal_increases');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_amortization_pattern|FAIL|first_int:' ||
          v_first_int || ' last_int:' || v_last_int);
      END IF;
    END;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_amortization_pattern|FAIL|' || SQLERRM);
  END;

  -- tc_08: Mevcut SCHEDULED kayıtlar silinir, yenileri oluşur
  BEGIN
    make_loan(1000, 100000, 10000, 12);
    pkg_loan_mgmt.generate_amortization_schedule(v_loan_id, SYSDATE);
    -- İkinci kez çağır
    pkg_loan_mgmt.generate_amortization_schedule(v_loan_id, SYSDATE);
    SELECT COUNT(*) INTO v_count
    FROM   loan_payments
    WHERE  loan_id = v_loan_id AND status = 'SCHEDULED';
    ROLLBACK;
    IF v_count = 12 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_existing_schedule_replaced|OK|count:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_existing_schedule_replaced|FAIL|expected:12 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_existing_schedule_replaced|FAIL|' || SQLERRM);
  END;

  -- tc_09: OVERDUE/PAID kayıtlar silinmez — sadece SCHEDULED silinir
  BEGIN
    make_loan(1000, 100000, 10000, 12);
    -- Manuel OVERDUE kayıt ekle
    INSERT INTO loan_payments (payment_id, loan_id, due_date, scheduled_amount,
                               principal_portion, interest_portion, status)
    VALUES (seq_payment_id.NEXTVAL, v_loan_id, SYSDATE - 30, 860.66, 810.66, 50, 'OVERDUE');
    -- Regenerate
    pkg_loan_mgmt.generate_amortization_schedule(v_loan_id, SYSDATE);
    SELECT COUNT(*) INTO v_count
    FROM   loan_payments
    WHERE  loan_id = v_loan_id AND status = 'OVERDUE';
    ROLLBACK;
    IF v_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_overdue_not_deleted|OK|overdue_preserved:1');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_overdue_not_deleted|FAIL|expected:1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_overdue_not_deleted|FAIL|' || SQLERRM);
  END;

  -- tc_10: 24 aylık loan → 24 SCHEDULED kayıt
  BEGIN
    make_loan(1002, 100003, 20000, 24);
    pkg_loan_mgmt.generate_amortization_schedule(v_loan_id, SYSDATE);
    SELECT COUNT(*) INTO v_count
    FROM   loan_payments
    WHERE  loan_id = v_loan_id AND status = 'SCHEDULED';
    ROLLBACK;
    IF v_count = 24 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_24_month_term|OK|count:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_24_month_term|FAIL|expected:24 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_24_month_term|FAIL|' || SQLERRM);
  END;

  -- tc_11: Var olmayan loan_id → NO_DATA_FOUND
  BEGIN
    pkg_loan_mgmt.generate_amortization_schedule(999999, SYSDATE);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_nonexistent_loan|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_nonexistent_loan|OK|no_data_found');
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_nonexistent_loan|FAIL|wrong_exception:' || SQLCODE);
  END;

END;
/