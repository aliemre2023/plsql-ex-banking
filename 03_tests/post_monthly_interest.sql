DECLARE
  v_posted_count   NUMBER;
  v_total_interest NUMBER;
  v_period_start   DATE := TRUNC(ADD_MONTHS(SYSDATE, -1), 'MM');
  v_period_end     DATE := LAST_DAY(ADD_MONTHS(SYSDATE, -1));
  v_count          NUMBER;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: Transaction yokken posted_count=0, total_interest=0
  BEGIN
    pkg_transactions.post_monthly_interest(SYSDATE, NULL, v_posted_count, v_total_interest);
    IF v_posted_count = 0 AND v_total_interest = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_no_balance_zero_posted|OK|count:' || v_posted_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_no_balance_zero_posted|FAIL|count:' || v_posted_count || ' total:' || v_total_interest);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_no_balance_zero_posted|FAIL|' || SQLERRM);
  END;

  -- tc_02: SAVINGS account için önceki ay transaction var → posted_count=1
  -- 100001 SAVINGS rate=2.5%
  BEGIN
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, transaction_date
    ) VALUES (
        100001, 'DEPOSIT', 15000, 0, 15000,
        'TC02-PMI', 'BRANCH', 'COMPLETED',
        v_period_start + INTERVAL '1' HOUR
    );
    pkg_transactions.post_monthly_interest(SYSDATE, NULL, v_posted_count, v_total_interest);
    ROLLBACK;
    IF v_posted_count >= 1 AND v_total_interest > 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_savings_posted|OK|count:' || v_posted_count || ' total:' || v_total_interest);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_savings_posted|FAIL|count:' || v_posted_count || ' total:' || v_total_interest);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_savings_posted|FAIL|' || SQLERRM);
  END;

  -- tc_03: p_account_type filtresi çalışır — sadece SAVINGS işlenir
  BEGIN
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, transaction_date
    ) VALUES (
        100001, 'DEPOSIT', 15000, 0, 15000,
        'TC03-SAV', 'BRANCH', 'COMPLETED',
        v_period_start + INTERVAL '1' HOUR
    );
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, transaction_date
    ) VALUES (
        100006, 'DEPOSIT', 75000, 0, 75000,
        'TC03-MMK', 'BRANCH', 'COMPLETED',
        v_period_start + INTERVAL '1' HOUR
    );
    pkg_transactions.post_monthly_interest(SYSDATE, 'SAVINGS', v_posted_count, v_total_interest);
    -- Sadece SAVINGS account'lar (100001, 100003) işlenmeli
    -- 100006 MONEY_MKT → işlenmemeli
    SELECT COUNT(*) INTO v_count
    FROM   interest_postings
    WHERE  account_id   IN (100001, 100003)
    AND    period_start = v_period_start;
    DECLARE
      v_mmk_count NUMBER;
    BEGIN
      SELECT COUNT(*) INTO v_mmk_count
      FROM   interest_postings
      WHERE  account_id   = 100006
      AND    period_start = v_period_start;
      ROLLBACK;
      IF v_mmk_count = 0 AND v_posted_count >= 1 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_account_type_filter|OK|savings_only mmk_excluded');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_account_type_filter|FAIL|mmk_count:' || v_mmk_count || ' posted:' || v_posted_count);
      END IF;
    END;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_account_type_filter|FAIL|' || SQLERRM);
  END;

  -- tc_04: CHECKING rate=0.01% → interest_rate > 0 koşulunu sağlar ama çok küçük faiz
  -- 100000 CHECKING rate=0.01%
  BEGIN
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, transaction_date
    ) VALUES (
        100000, 'DEPOSIT', 5000, 0, 5000,
        'TC04-CHK', 'BRANCH', 'COMPLETED',
        v_period_start + INTERVAL '1' HOUR
    );
    pkg_transactions.post_monthly_interest(SYSDATE, 'CHECKING', v_posted_count, v_total_interest);
    ROLLBACK;
    -- CHECKING rate=0.01% → gross çok küçük ama > 0 → posted_count >= 1
    IF v_posted_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_checking_posted|OK|count:' || v_posted_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_checking_posted|FAIL|expected:>=1 got:' || v_posted_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_checking_posted|FAIL|' || SQLERRM);
  END;

  -- tc_05: Zaten postalanmış account → tekrar işlenmez (NOT EXISTS koşulu)
  BEGIN
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, transaction_date
    ) VALUES (
        100001, 'DEPOSIT', 15000, 0, 15000,
        'TC05-SKIP', 'BRANCH', 'COMPLETED',
        v_period_start + INTERVAL '1' HOUR
    );
    -- İlk çalıştırma
    pkg_transactions.post_monthly_interest(SYSDATE, 'SAVINGS', v_posted_count, v_total_interest);
    DECLARE
      v_first_count NUMBER := v_posted_count;
    BEGIN
      -- İkinci çalıştırma — aynı periyot, aynı account → atlanmalı
      pkg_transactions.post_monthly_interest(SYSDATE, 'SAVINGS', v_posted_count, v_total_interest);
      ROLLBACK;
      IF v_posted_count = 0 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_skip_already_posted|OK|second_run_count:' || v_posted_count);
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_skip_already_posted|FAIL|expected:0 got:' || v_posted_count);
      END IF;
    END;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_skip_already_posted|FAIL|' || SQLERRM);
  END;

  -- tc_06: INACTIVE account → işlenmez (WHERE status = 'ACTIVE')
  BEGIN
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, transaction_date
    ) VALUES (
        100001, 'DEPOSIT', 15000, 0, 15000,
        'TC06-INACT', 'BRANCH', 'COMPLETED',
        v_period_start + INTERVAL '1' HOUR
    );
    UPDATE accounts SET status = 'INACTIVE' WHERE account_id = 100001;
    pkg_transactions.post_monthly_interest(SYSDATE, 'SAVINGS', v_posted_count, v_total_interest);
    SELECT COUNT(*) INTO v_count
    FROM   interest_postings
    WHERE  account_id   = 100001
    AND    period_start = v_period_start;
    ROLLBACK;
    IF v_count = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_inactive_skipped|OK|inactive_not_posted');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_inactive_skipped|FAIL|expected:0 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_inactive_skipped|FAIL|' || SQLERRM);
  END;

  -- tc_07: p_posted_count ve p_total_interest OUT parametreleri başlangıçta 0
  BEGIN
    v_posted_count   := 999;
    v_total_interest := 999;
    pkg_transactions.post_monthly_interest(SYSDATE, NULL, v_posted_count, v_total_interest);
    IF v_posted_count = 0 AND v_total_interest = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_out_params_initialized|OK|count:0 total:0');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_out_params_initialized|FAIL|count:' || v_posted_count || ' total:' || v_total_interest);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_out_params_initialized|FAIL|' || SQLERRM);
  END;

  -- tc_08: Periyot önceki ay — bugünkü transaction sayılmaz
  BEGIN
    -- Bugünkü transaction ekle (önceki ay değil)
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, transaction_date
    ) VALUES (
        100001, 'DEPOSIT', 15000, 0, 15000,
        'TC08-TODAY', 'BRANCH', 'COMPLETED',
        TRUNC(SYSDATE) + INTERVAL '1' HOUR
    );
    pkg_transactions.post_monthly_interest(SYSDATE, 'SAVINGS', v_posted_count, v_total_interest);
    ROLLBACK;
    -- Bugünkü deposit önceki aya ait avg_balance hesabına girmez → posted_count=0
    IF v_posted_count = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_current_month_txn_excluded|OK|count:' || v_posted_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_current_month_txn_excluded|FAIL|expected:0 got:' || v_posted_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_current_month_txn_excluded|FAIL|' || SQLERRM);
  END;

END;
/