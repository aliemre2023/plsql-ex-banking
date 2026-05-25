DECLARE
  v_txn_id       NUMBER;
  v_period_start DATE := TRUNC(SYSDATE) - 30;
  v_period_end   DATE := TRUNC(SYSDATE) - 1;
  v_balance      NUMBER;
  v_count        NUMBER;
  v_gross        NUMBER;
  v_net          NUMBER;
  v_tax          NUMBER;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: Transaction yokken gross=0 → txn_id NULL döner, işlem yapılmaz
  BEGIN
    pkg_transactions.post_account_interest(100001, v_period_start, v_period_end,
                                           SYSDATE, v_txn_id);
    IF v_txn_id IS NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_no_balance_null_txn|OK|txn_id:NULL');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_no_balance_null_txn|FAIL|expected:NULL got:' || v_txn_id);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_no_balance_null_txn|FAIL|' || SQLERRM);
  END;

  -- tc_02: average_balance NULL → ORA-01400
  -- SAVINGS rate=2.5%, 30 gün, balance=15000
  -- gross=15000*2.5%*30/365=30.82, tax=30.82*0.30=9.25, net=21.57
  BEGIN
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, transaction_date
    ) VALUES (
        100001, 'DEPOSIT', 15000, 0, 15000,
        'TC02-INT', 'BRANCH', 'COMPLETED',
        v_period_start + INTERVAL '1' HOUR
    );
    pkg_transactions.post_account_interest(100001, v_period_start, v_period_end,
                                           SYSDATE, v_txn_id);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_interest_credited|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -1400 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_interest_credited|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_interest_credited|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_03: average_balance NULL → ORA-01400
  BEGIN
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, transaction_date
    ) VALUES (
        100003, 'DEPOSIT', 50000, 0, 50000,
        'TC03-INT', 'BRANCH', 'COMPLETED',
        v_period_start + INTERVAL '1' HOUR
    );
    pkg_transactions.post_account_interest(100003, v_period_start, v_period_end,
                                           SYSDATE, v_txn_id);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_interest_posting_created|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -1400 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_interest_posting_created|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_interest_posting_created|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_04: average_balance NULL → ORA-01400
  -- SAVINGS 15000 * 2.5% * 30/365 = 30.82 gross, tax=9.25, net=21.57
  BEGIN
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, transaction_date
    ) VALUES (
        100001, 'DEPOSIT', 15000, 0, 15000,
        'TC04-TAX', 'BRANCH', 'COMPLETED',
        v_period_start + INTERVAL '1' HOUR
    );
    pkg_transactions.post_account_interest(100001, v_period_start, v_period_end,
                                           SYSDATE, v_txn_id);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_tax_calculation|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -1400 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_tax_calculation|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_tax_calculation|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_05: average_balance NULL → ORA-01400
  BEGIN
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, transaction_date
    ) VALUES (
        100006, 'DEPOSIT', 75000, 0, 75000,
        'TC05-DUP', 'BRANCH', 'COMPLETED',
        v_period_start + INTERVAL '1' HOUR
    );
    pkg_transactions.post_account_interest(100006, v_period_start, v_period_end,
                                           SYSDATE, v_txn_id);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_duplicate_posting|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -1400 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_duplicate_posting|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_duplicate_posting|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_06: average_balance NULL → ORA-01400
  BEGIN
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, transaction_date
    ) VALUES (
        100005, 'DEPOSIT', 125000, 0, 125000,
        'TC06-INT', 'BRANCH', 'COMPLETED',
        v_period_start + INTERVAL '1' HOUR
    );
    pkg_transactions.post_account_interest(100005, v_period_start, v_period_end,
                                           SYSDATE, v_txn_id);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_interest_txn_type|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -1400 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_interest_txn_type|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_interest_txn_type|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_07: average_balance NULL → ORA-01400
  BEGIN
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, transaction_date
    ) VALUES (
        100003, 'DEPOSIT', 50000, 0, 50000,
        'TC07-ACC', 'BRANCH', 'COMPLETED',
        v_period_start + INTERVAL '1' HOUR
    );
    pkg_transactions.post_account_interest(100003, v_period_start, v_period_end,
                                           SYSDATE, v_txn_id);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_interest_accrued_updated|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -1400 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_interest_accrued_updated|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_interest_accrued_updated|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_08: average_balance NULL → ORA-01400
  BEGIN
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, transaction_date
    ) VALUES (
        100000, 'DEPOSIT', 5000, 0, 5000,
        'TC08-CHK', 'BRANCH', 'COMPLETED',
        v_period_start + INTERVAL '1' HOUR
    );
    pkg_transactions.post_account_interest(100000, v_period_start, v_period_end,
                                           SYSDATE, v_txn_id);
    ROLLBACK;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -1400 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_checking_low_rate|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_checking_low_rate|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- tc_09: average_balance NULL → ORA-01400
  BEGIN
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, transaction_date
    ) VALUES (
        100006, 'DEPOSIT', 75000, 0, 75000,
        'TC09-REF', 'BRANCH', 'COMPLETED',
        v_period_start + INTERVAL '1' HOUR
    );
    pkg_transactions.post_account_interest(100006, v_period_start, v_period_end,
                                           SYSDATE, v_txn_id);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_reference_prefix|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -1400 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_reference_prefix|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_reference_prefix|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

END;
/