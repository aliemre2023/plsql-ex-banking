DECLARE
  v_result      NUMBER;
  v_today       DATE := TRUNC(SYSDATE);
  v_yesterday   DATE := TRUNC(SYSDATE) - 1;
  v_account_id  NUMBER := 100000; -- Alice CHECKING
  v_account_id2 NUMBER := 100001; -- Alice SAVINGS

BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- Setup: Insert test transactions
  -- Alice CHECKING: 2 withdrawal + 1 transfer_out + 1 deposit (today)
  -- Alice CHECKING: 1 withdrawal (yesterday)
  -- Alice SAVINGS:  1 withdrawal (today) — farklı account izolasyon testi için
  INSERT INTO transactions (account_id, transaction_type, amount, balance_before, balance_after,
                            reference_number, status, transaction_date)
  VALUES (v_account_id, 'WITHDRAWAL',   200.00, 5000.00, 4800.00, 'REF-TC-001', 'COMPLETED',
          v_today + INTERVAL '9' HOUR);

  INSERT INTO transactions (account_id, transaction_type, amount, balance_before, balance_after,
                            reference_number, status, transaction_date)
  VALUES (v_account_id, 'WITHDRAWAL',   300.00, 4800.00, 4500.00, 'REF-TC-002', 'COMPLETED',
          v_today + INTERVAL '10' HOUR);

  INSERT INTO transactions (account_id, transaction_type, amount, balance_before, balance_after,
                            reference_number, status, transaction_date)
  VALUES (v_account_id, 'TRANSFER_OUT', 500.00, 4500.00, 4000.00, 'REF-TC-003', 'COMPLETED',
          v_today + INTERVAL '11' HOUR);

  INSERT INTO transactions (account_id, transaction_type, amount, balance_before, balance_after,
                            reference_number, status, transaction_date)
  VALUES (v_account_id, 'DEPOSIT',      1000.00, 4000.00, 5000.00, 'REF-TC-004', 'COMPLETED',
          v_today + INTERVAL '12' HOUR);

  INSERT INTO transactions (account_id, transaction_type, amount, balance_before, balance_after,
                            reference_number, status, transaction_date)
  VALUES (v_account_id, 'WITHDRAWAL',   150.00, 5000.00, 4850.00, 'REF-TC-005', 'COMPLETED',
          v_yesterday + INTERVAL '9' HOUR);

  INSERT INTO transactions (account_id, transaction_type, amount, balance_before, balance_after,
                            reference_number, status, transaction_date)
  VALUES (v_account_id, 'WITHDRAWAL',   100.00, 4850.00, 4750.00, 'REF-TC-006', 'FAILED',
          v_today + INTERVAL '13' HOUR);

  INSERT INTO transactions (account_id, transaction_type, amount, balance_before, balance_after,
                            reference_number, status, transaction_date)
  VALUES (v_account_id2, 'WITHDRAWAL',  400.00, 15000.00, 14600.00, 'REF-TC-007', 'COMPLETED',
          v_today + INTERVAL '9' HOUR);

  -- Test: tc_01_sum_withdrawals_and_transfers — Sum WITHDRAWAL + TRANSFER_OUT for today (200+300+500=1000)
  BEGIN
    v_result := pkg_account_mgmt.get_daily_withdrawal_total(v_account_id, v_today);
    IF v_result = 1000.00 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_sum_withdrawals_and_transfers|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_sum_withdrawals_and_transfers|FAIL|expected:1000.00 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_sum_withdrawals_and_transfers|FAIL|' || SQLERRM);
  END;

  -- Test: tc_02_excludes_deposit — DEPOSIT type is not counted in daily total
  BEGIN
    v_result := pkg_account_mgmt.get_daily_withdrawal_total(v_account_id, v_today);
    IF v_result = 1000.00 THEN  -- deposit 1000 eklenmemeli, sonuç değişmemeli
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_excludes_deposit|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_excludes_deposit|FAIL|expected:1000.00 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_excludes_deposit|FAIL|' || SQLERRM);
  END;

  -- Test: tc_03_excludes_failed_status — FAILED transactions are not counted
  BEGIN
    v_result := pkg_account_mgmt.get_daily_withdrawal_total(v_account_id, v_today);
    IF v_result = 1000.00 THEN  -- FAILED withdrawal 100 dahil edilmemeli
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_excludes_failed_status|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_excludes_failed_status|FAIL|expected:1000.00 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_excludes_failed_status|FAIL|' || SQLERRM);
  END;

  -- Test: tc_04_excludes_yesterday — Yesterday's transactions not counted for today
  BEGIN
    v_result := pkg_account_mgmt.get_daily_withdrawal_total(v_account_id, v_today);
    IF v_result = 1000.00 THEN  -- dünkü 150 dahil edilmemeli
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_excludes_yesterday|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_excludes_yesterday|FAIL|expected:1000.00 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_excludes_yesterday|FAIL|' || SQLERRM);
  END;

  -- Test: tc_05_yesterday_total — Return correct total for a past date
  BEGIN
    v_result := pkg_account_mgmt.get_daily_withdrawal_total(v_account_id, v_yesterday);
    IF v_result = 150.00 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_yesterday_total|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_yesterday_total|FAIL|expected:150.00 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_yesterday_total|FAIL|' || SQLERRM);
  END;

  -- Test: tc_06_account_isolation — Different account returns its own total only
  BEGIN
    v_result := pkg_account_mgmt.get_daily_withdrawal_total(v_account_id2, v_today);
    IF v_result = 400.00 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_account_isolation|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_account_isolation|FAIL|expected:400.00 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_account_isolation|FAIL|' || SQLERRM);
  END;

  -- Test: tc_07_no_transactions_today — Return 0 when no transactions exist for the given date
  BEGIN
    v_result := pkg_account_mgmt.get_daily_withdrawal_total(v_account_id, v_today - 30);
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_no_transactions_today|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_no_transactions_today|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_no_transactions_today|FAIL|' || SQLERRM);
  END;

  -- Test: tc_08_nonexistent_account — Return 0 for account with no transactions (NVL kicks in)
  BEGIN
    v_result := pkg_account_mgmt.get_daily_withdrawal_total(999999, v_today);
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_nonexistent_account|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_nonexistent_account|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_nonexistent_account|FAIL|' || SQLERRM);
  END;

  -- Test: tc_09_null_account_id — Return 0 for NULL account_id (NVL kicks in)
  BEGIN
    v_result := pkg_account_mgmt.get_daily_withdrawal_total(NULL, v_today);
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_null_account_id|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_null_account_id|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_null_account_id|FAIL|' || SQLERRM);
  END;

  -- Test: tc_10_default_date_is_today — Calling without p_date returns same result as explicit SYSDATE
  DECLARE
    v_explicit NUMBER;
    v_default  NUMBER;
  BEGIN
    v_explicit := pkg_account_mgmt.get_daily_withdrawal_total(v_account_id, SYSDATE);
    v_default  := pkg_account_mgmt.get_daily_withdrawal_total(v_account_id);
    IF v_explicit = v_default THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_default_date_is_today|OK|explicit:' || v_explicit || ' default:' || v_default);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_default_date_is_today|FAIL|explicit:' || v_explicit || ' default:' || v_default);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_default_date_is_today|FAIL|' || SQLERRM);
  END;

  ROLLBACK;

END;
/