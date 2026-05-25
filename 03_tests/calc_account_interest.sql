DECLARE
  v_result       NUMBER;
  v_period_start DATE := TRUNC(SYSDATE) - 30;
  v_period_end   DATE := TRUNC(SYSDATE) - 1;
  v_txn_id       NUMBER;
  v_ref          VARCHAR2(50);
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: Transaction yokken avg_balance=0 → faiz=0
  BEGIN
    v_result := pkg_transactions.calc_account_interest(100001, v_period_start, v_period_end);
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_no_transactions_zero_interest|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_no_transactions_zero_interest|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_no_transactions_zero_interest|FAIL|' || SQLERRM);
  END;

  -- tc_02: Transaction varken doğru faiz hesaplanır
  -- SAVINGS rate=2.5%, 30 gün, balance_after=15000
  -- avg=15000, interest=15000*(2.5/100)*(30/365)=30.82
  BEGIN
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, transaction_date
    ) VALUES (
        100001, 'DEPOSIT', 15000, 0, 15000,
        'TC02-TEST', 'BRANCH', 'COMPLETED',
        v_period_start + INTERVAL '1' HOUR
    );
    v_result := pkg_transactions.calc_account_interest(100001, v_period_start, v_period_end);
    ROLLBACK;
    IF v_result = 30.82 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_savings_interest|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_savings_interest|FAIL|expected:30.82 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_savings_interest|FAIL|' || SQLERRM);
  END;

  -- tc_03: CHECKING rate=0.01% → çok düşük faiz (neredeyse 0)
  -- 5000 * (0.01/100) * (30/365) = 0.04
  BEGIN
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, transaction_date
    ) VALUES (
        100000, 'DEPOSIT', 5000, 0, 5000,
        'TC03-TEST', 'BRANCH', 'COMPLETED',
        v_period_start + INTERVAL '1' HOUR
    );
    v_result := pkg_transactions.calc_account_interest(100000, v_period_start, v_period_end);
    ROLLBACK;
    IF v_result = 0.04 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_checking_low_rate|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_checking_low_rate|FAIL|expected:0.04 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_checking_low_rate|FAIL|' || SQLERRM);
  END;

  -- tc_04: GREATEST(0) garantisi — negatif faiz olmaz
  -- Balance 0 olsa bile 0 döner
  BEGIN
    v_result := pkg_transactions.calc_account_interest(100000, v_period_start, v_period_end);
    IF v_result >= 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_never_negative|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_never_negative|FAIL|negative_interest:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_never_negative|FAIL|' || SQLERRM);
  END;

  -- tc_05: Tek günlük periyot (start = end)
  -- SAVINGS 15000 * 2.5% * 1/365 = 1.03
  BEGIN
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, transaction_date
    ) VALUES (
        100001, 'DEPOSIT', 15000, 0, 15000,
        'TC05-TEST', 'BRANCH', 'COMPLETED',
        TRUNC(SYSDATE) - 5 + INTERVAL '1' HOUR
    );
    v_result := pkg_transactions.calc_account_interest(
        100001,
        TRUNC(SYSDATE) - 5,
        TRUNC(SYSDATE) - 5
    );
    ROLLBACK;
    IF v_result = 1.03 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_single_day_period|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_single_day_period|FAIL|expected:1.03 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_single_day_period|FAIL|' || SQLERRM);
  END;

  -- tc_06: Var olmayan account_id → NO_DATA_FOUND (accounts JOIN)
  BEGIN
    v_result := pkg_transactions.calc_account_interest(999999, v_period_start, v_period_end);
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_nonexistent_account|FAIL|Expected exception not raised got:' || v_result);
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_nonexistent_account|OK|exception_raised');
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_nonexistent_account|FAIL|wrong_exception:' || SQLCODE);
  END;

  -- tc_07: MONEY_MKT rate=3.5% — yüksek rate doğru hesaplanır
  -- 75000 * 3.5% * 30/365 = 216.44
  BEGIN
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, transaction_date
    ) VALUES (
        100006, 'DEPOSIT', 75000, 0, 75000,
        'TC07-TEST', 'BRANCH', 'COMPLETED',
        v_period_start + INTERVAL '1' HOUR
    );
    v_result := pkg_transactions.calc_account_interest(100006, v_period_start, v_period_end);
    ROLLBACK;
    IF v_result = 216.44 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_money_mkt_rate|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_money_mkt_rate|FAIL|expected:216.44 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_money_mkt_rate|FAIL|' || SQLERRM);
  END;

  -- tc_08: Periyot başında ve sonunda farklı balance — ortalama kullanılır
  -- Başta 10000, ortada 20000 olursa avg != sabit bir değer
  BEGIN
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, transaction_date
    ) VALUES (
        100003, 'DEPOSIT', 10000, 0, 10000,
        'TC08A-TEST', 'BRANCH', 'COMPLETED',
        v_period_start + INTERVAL '1' HOUR
    );
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, transaction_date
    ) VALUES (
        100003, 'DEPOSIT', 10000, 10000, 20000,
        'TC08B-TEST', 'BRANCH', 'COMPLETED',
        v_period_start + 15 + INTERVAL '1' HOUR
    );
    v_result := pkg_transactions.calc_account_interest(100003, v_period_start, v_period_end);
    ROLLBACK;
    -- İlk 15 gün 10000, sonraki 15 gün 20000 → avg ≈ 15000 → 15000*2.5%*30/365 = 30.82
    IF v_result > 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_changing_balance_avg|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_changing_balance_avg|FAIL|expected:>0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_changing_balance_avg|FAIL|' || SQLERRM);
  END;

END;
/