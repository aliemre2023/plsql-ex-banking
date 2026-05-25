DECLARE
  v_result    VARCHAR2(500);
  v_txn_id    NUMBER;
  v_ref       VARCHAR2(50);
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: Var olan transaction → doğru format döner
  BEGIN
    pkg_transactions.deposit(100000, 1000, 'Summary test', 'BRANCH', 2000, v_txn_id, v_ref);
    v_result := pkg_transactions.get_transaction_summary(v_txn_id);
    ROLLBACK;
    IF v_result LIKE 'TXN#' || v_txn_id || ' | DEPOSIT | Amt: 1000 | Acct: ACC-100001 | Date: %' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path_deposit|OK|' || SUBSTR(v_result,1,80));
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path_deposit|FAIL|unexpected:' || SUBSTR(v_result,1,100));
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_happy_path_deposit|FAIL|' || SQLERRM);
  END;

  -- tc_02: TXN# ile başlıyor mu
  BEGIN
    pkg_transactions.deposit(100001, 500, 'Prefix test', 'BRANCH', 2000, v_txn_id, v_ref);
    v_result := pkg_transactions.get_transaction_summary(v_txn_id);
    ROLLBACK;
    IF v_result LIKE 'TXN#%' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_starts_with_txn|OK|prefix:TXN#');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_starts_with_txn|FAIL|result:' || SUBSTR(v_result,1,50));
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_starts_with_txn|FAIL|' || SQLERRM);
  END;

  -- tc_03: transaction_type DEPOSIT içeriyor mu
  BEGIN
    pkg_transactions.deposit(100002, 750, 'Type test', 'BRANCH', 2001, v_txn_id, v_ref);
    v_result := pkg_transactions.get_transaction_summary(v_txn_id);
    ROLLBACK;
    IF INSTR(v_result, 'DEPOSIT') > 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_contains_txn_type|OK|type:DEPOSIT');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_contains_txn_type|FAIL|result:' || SUBSTR(v_result,1,100));
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_contains_txn_type|FAIL|' || SQLERRM);
  END;

  -- tc_04: Amount doğru içeriyor mu
  BEGIN
    pkg_transactions.deposit(100003, 2500, 'Amount test', 'BRANCH', 2001, v_txn_id, v_ref);
    v_result := pkg_transactions.get_transaction_summary(v_txn_id);
    ROLLBACK;
    IF INSTR(v_result, 'Amt: 2500') > 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_contains_amount|OK|amount:2500');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_contains_amount|FAIL|result:' || SUBSTR(v_result,1,100));
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_contains_amount|FAIL|' || SQLERRM);
  END;

  -- tc_05: Status COMPLETED içeriyor mu
  BEGIN
    pkg_transactions.deposit(100004, 300, 'Status test', 'BRANCH', 2002, v_txn_id, v_ref);
    v_result := pkg_transactions.get_transaction_summary(v_txn_id);
    ROLLBACK;
    IF INSTR(v_result, 'Status: COMPLETED') > 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_contains_status|OK|status:COMPLETED');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_contains_status|FAIL|result:' || SUBSTR(v_result,1,100));
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_contains_status|FAIL|' || SQLERRM);
  END;

  -- tc_06: Date formatı YYYY-MM-DD HH24:MI içeriyor mu
  BEGIN
    pkg_transactions.deposit(100005, 1000, 'Date format test', 'BRANCH', 2000, v_txn_id, v_ref);
    v_result := pkg_transactions.get_transaction_summary(v_txn_id);
    ROLLBACK;
    IF REGEXP_LIKE(v_result, 'Date: \d{4}-\d{2}-\d{2} \d{2}:\d{2}') THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_date_format|OK|date_format_correct');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_date_format|FAIL|result:' || SUBSTR(v_result,1,100));
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_date_format|FAIL|' || SQLERRM);
  END;

  -- tc_07: Var olmayan transaction_id → 'Transaction not found: X' döner
  BEGIN
    v_result := pkg_transactions.get_transaction_summary(999999);
    IF v_result = 'Transaction not found: 999999' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_not_found|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_not_found|FAIL|expected:Transaction not found: 999999 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_not_found|FAIL|' || SQLERRM);
  END;

  -- tc_08: NULL transaction_id → 'Transaction not found: ' döner
  BEGIN
    v_result := pkg_transactions.get_transaction_summary(NULL);
    IF v_result = 'Transaction not found: ' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_null_txn_id|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_null_txn_id|FAIL|got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_null_txn_id|FAIL|' || SQLERRM);
  END;

  -- tc_09: Account number doğru içeriyor mu (ACC-100001 → account_id=100000)
  BEGIN
    pkg_transactions.deposit(100000, 100, 'Acct number test', 'BRANCH', 2000, v_txn_id, v_ref);
    v_result := pkg_transactions.get_transaction_summary(v_txn_id);
    ROLLBACK;
    IF INSTR(v_result, 'Acct: ACC-100001') > 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_account_number|OK|acct:ACC-100001');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_account_number|FAIL|result:' || SUBSTR(v_result,1,100));
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_account_number|FAIL|' || SQLERRM);
  END;

  -- tc_10: WITHDRAWAL tipi de doğru döner
  BEGIN
    pkg_transactions.withdraw(100000, 100, 'Withdrawal summary', 'BRANCH', 2000, v_txn_id, v_ref);
    v_result := pkg_transactions.get_transaction_summary(v_txn_id);
    ROLLBACK;
    IF INSTR(v_result, 'WITHDRAWAL') > 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_withdrawal_type|OK|type:WITHDRAWAL');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_withdrawal_type|FAIL|result:' || SUBSTR(v_result,1,100));
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_withdrawal_type|FAIL|' || SQLERRM);
  END;

END;
/