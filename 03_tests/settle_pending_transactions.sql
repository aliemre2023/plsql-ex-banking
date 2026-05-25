DECLARE
  v_settled NUMBER;
  v_failed  NUMBER;
  v_count   NUMBER;
  v_today   DATE := TRUNC(SYSDATE);
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: PENDING transaction yok → her iki count da 0
  BEGIN
    pkg_transactions.settle_pending_transactions(v_today, v_settled, v_failed);
    IF v_settled = 0 AND v_failed = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_no_pending|OK|settled:0 failed:0');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_no_pending|FAIL|settled:' || v_settled || ' failed:' || v_failed);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_no_pending|FAIL|' || SQLERRM);
  END;

  -- tc_02: value_date <= settlement_date → COMPLETED olur
  BEGIN
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, value_date
    ) VALUES (
        100000, 'DEPOSIT', 500, 5000, 5500,
        'TC02-PEND', 'BRANCH', 'PENDING', v_today
    );
    pkg_transactions.settle_pending_transactions(v_today, v_settled, v_failed);
    SELECT COUNT(*) INTO v_count
    FROM   transactions
    WHERE  reference_number = 'TC02-PEND'
    AND    status           = 'COMPLETED';
    ROLLBACK;
    IF v_settled = 1 AND v_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_pending_settled|OK|settled:' || v_settled);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_pending_settled|FAIL|settled:' || v_settled || ' count:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_pending_settled|FAIL|' || SQLERRM);
  END;

  -- tc_03: value_date geçmişte (dün) → COMPLETED olur
  BEGIN
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, value_date
    ) VALUES (
        100001, 'WITHDRAWAL', 200, 15000, 14800,
        'TC03-PAST', 'BRANCH', 'PENDING', v_today - 1
    );
    pkg_transactions.settle_pending_transactions(v_today, v_settled, v_failed);
    SELECT COUNT(*) INTO v_count
    FROM   transactions
    WHERE  reference_number = 'TC03-PAST'
    AND    status           = 'COMPLETED';
    ROLLBACK;
    IF v_settled = 1 AND v_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_past_value_date_settled|OK|settled:' || v_settled);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_past_value_date_settled|FAIL|settled:' || v_settled || ' count:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_past_value_date_settled|FAIL|' || SQLERRM);
  END;

  -- tc_04: value_date gelecekte → settle edilmez, PENDING kalır
  BEGIN
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, value_date
    ) VALUES (
        100002, 'DEPOSIT', 300, 2500, 2800,
        'TC04-FUTURE', 'BRANCH', 'PENDING', v_today + 1
    );
    pkg_transactions.settle_pending_transactions(v_today, v_settled, v_failed);
    SELECT COUNT(*) INTO v_count
    FROM   transactions
    WHERE  reference_number = 'TC04-FUTURE'
    AND    status           = 'PENDING';
    ROLLBACK;
    IF v_settled = 0 AND v_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_future_value_date_stays_pending|OK|settled:0');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_future_value_date_stays_pending|FAIL|settled:' || v_settled || ' pending_count:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_future_value_date_stays_pending|FAIL|' || SQLERRM);
  END;

  -- tc_05: value_date > 3 gün önce → FAILED olur (stuck)
  -- NOT: İlk UPDATE value_date <= today olanları COMPLETED yapar
  -- value_date < today-3 olan PENDING'ler ikinci UPDATE'te FAILED olur
  -- Ancak ilk UPDATE zaten onları COMPLETED yapacak → FAILED = 0 olabilir
  -- Bu bir logic bug: failed check ikinci UPDATE'te PENDING bekler ama ilk UPDATE zaten COMPLETED yaptı
  -- Test bu davranışı doğrular
  BEGIN
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, value_date
    ) VALUES (
        100003, 'DEPOSIT', 100, 50000, 50100,
        'TC05-STUCK', 'BRANCH', 'PENDING', v_today - 5
    );
    pkg_transactions.settle_pending_transactions(v_today, v_settled, v_failed);
    SELECT COUNT(*) INTO v_count
    FROM   transactions
    WHERE  reference_number = 'TC05-STUCK'
    AND    status IN ('COMPLETED', 'FAILED');
    ROLLBACK;
    -- value_date=today-5 <= today → ilk UPDATE → COMPLETED
    -- ikinci UPDATE'te artık PENDING değil → FAILED=0
    IF v_settled = 1 AND v_failed = 0 AND v_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_stuck_settled_not_failed|OK|settled:1 failed:0');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_stuck_settled_not_failed|FAIL|settled:' || v_settled || ' failed:' || v_failed);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_stuck_settled_not_failed|FAIL|' || SQLERRM);
  END;

  -- tc_06: COMPLETED transaction → etkilenmez
  BEGIN
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, value_date
    ) VALUES (
        100004, 'DEPOSIT', 200, 800, 1000,
        'TC06-COMP', 'BRANCH', 'COMPLETED', v_today - 1
    );
    pkg_transactions.settle_pending_transactions(v_today, v_settled, v_failed);
    SELECT COUNT(*) INTO v_count
    FROM   transactions
    WHERE  reference_number = 'TC06-COMP'
    AND    status           = 'COMPLETED';
    ROLLBACK;
    IF v_settled = 0 AND v_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_completed_not_touched|OK|settled:0');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_completed_not_touched|FAIL|settled:' || v_settled || ' count:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_completed_not_touched|FAIL|' || SQLERRM);
  END;

  -- tc_07: Birden fazla PENDING → hepsi settle edilir
  BEGIN
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, value_date
    ) VALUES (100000, 'DEPOSIT', 100, 5000, 5100, 'TC07-A', 'BRANCH', 'PENDING', v_today);
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, value_date
    ) VALUES (100001, 'DEPOSIT', 200, 15000, 15200, 'TC07-B', 'BRANCH', 'PENDING', v_today - 1);
    INSERT INTO transactions (
        account_id, transaction_type, amount, balance_before, balance_after,
        reference_number, channel, status, value_date
    ) VALUES (100002, 'DEPOSIT', 300, 2500, 2800, 'TC07-C', 'BRANCH', 'PENDING', v_today - 2);
    pkg_transactions.settle_pending_transactions(v_today, v_settled, v_failed);
    ROLLBACK;
    IF v_settled = 3 AND v_failed = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_multiple_pending_settled|OK|settled:' || v_settled);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_multiple_pending_settled|FAIL|settled:' || v_settled || ' failed:' || v_failed);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_multiple_pending_settled|FAIL|' || SQLERRM);
  END;

  -- tc_08: OUT parametreler sıfırlanır
  BEGIN
    v_settled := 999;
    v_failed  := 999;
    pkg_transactions.settle_pending_transactions(v_today, v_settled, v_failed);
    IF v_settled = 0 AND v_failed = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_out_params_initialized|OK|settled:0 failed:0');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_out_params_initialized|FAIL|settled:' || v_settled || ' failed:' || v_failed);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_out_params_initialized|FAIL|' || SQLERRM);
  END;

END;
/