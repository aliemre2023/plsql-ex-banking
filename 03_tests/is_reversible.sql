DECLARE
  v_result  BOOLEAN;
  v_txn_id  NUMBER;
  v_ref     VARCHAR2(50);

  PROCEDURE print_bool(p_test VARCHAR2, p_result BOOLEAN, p_expected BOOLEAN) IS
  BEGIN
    IF p_result = p_expected THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|' || p_test || '|OK|returned:' ||
        CASE p_result WHEN TRUE THEN 'TRUE' ELSE 'FALSE' END);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|' || p_test || '|FAIL|expected:' ||
        CASE p_expected WHEN TRUE THEN 'TRUE' ELSE 'FALSE' END ||
        ' got:' ||
        CASE p_result WHEN TRUE THEN 'TRUE' ELSE 'FALSE' END);
    END IF;
  END;

BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: Yeni DEPOSIT → TRUE (şimdi oluşturuldu, 24 saat içinde)
  BEGIN
    pkg_transactions.deposit(100000, 500, 'Reversible test', 'BRANCH', 2000, v_txn_id, v_ref);
    v_result := pkg_transactions.is_reversible(v_txn_id);
    ROLLBACK;
    print_bool('tc_01_recent_deposit_reversible', v_result, TRUE);
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_recent_deposit_reversible|FAIL|' || SQLERRM);
  END;

  -- tc_02: Yeni WITHDRAWAL → TRUE
  BEGIN
    pkg_transactions.withdraw(100000, 100, 'Reversible withdrawal', 'BRANCH', 2000, v_txn_id, v_ref);
    v_result := pkg_transactions.is_reversible(v_txn_id);
    ROLLBACK;
    print_bool('tc_02_recent_withdrawal_reversible', v_result, TRUE);
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_recent_withdrawal_reversible|FAIL|' || SQLERRM);
  END;

  -- tc_03: 24 saatten eski transaction → FALSE
  BEGIN
    pkg_transactions.deposit(100001, 500, 'Old txn test', 'BRANCH', 2000, v_txn_id, v_ref);
    UPDATE transactions
    SET    transaction_date = SYSTIMESTAMP - INTERVAL '25' HOUR
    WHERE  transaction_id = v_txn_id;
    v_result := pkg_transactions.is_reversible(v_txn_id);
    ROLLBACK;
    print_bool('tc_03_old_txn_not_reversible', v_result, FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_old_txn_not_reversible|FAIL|' || SQLERRM);
  END;

  -- tc_04: Tam 24 saat → FALSE (< 24 HOUR, eşit dahil değil)
  BEGIN
    pkg_transactions.deposit(100002, 500, 'Boundary test', 'BRANCH', 2001, v_txn_id, v_ref);
    UPDATE transactions
    SET    transaction_date = SYSTIMESTAMP - INTERVAL '24' HOUR
    WHERE  transaction_id = v_txn_id;
    v_result := pkg_transactions.is_reversible(v_txn_id);
    ROLLBACK;
    print_bool('tc_04_exactly_24h_not_reversible', v_result, FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_exactly_24h_not_reversible|FAIL|' || SQLERRM);
  END;

  -- tc_05: REVERSAL tipi → FALSE
  BEGIN
    pkg_transactions.deposit(100003, 500, 'Rev type test', 'BRANCH', 2001, v_txn_id, v_ref);
    UPDATE transactions
    SET    transaction_type = 'REVERSAL'
    WHERE  transaction_id = v_txn_id;
    v_result := pkg_transactions.is_reversible(v_txn_id);
    ROLLBACK;
    print_bool('tc_05_reversal_type_not_reversible', v_result, FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_reversal_type_not_reversible|FAIL|' || SQLERRM);
  END;

  -- tc_06: FEE tipi → FALSE
  BEGIN
    pkg_transactions.deposit(100004, 500, 'Fee type test', 'BRANCH', 2002, v_txn_id, v_ref);
    UPDATE transactions
    SET    transaction_type = 'FEE'
    WHERE  transaction_id = v_txn_id;
    v_result := pkg_transactions.is_reversible(v_txn_id);
    ROLLBACK;
    print_bool('tc_06_fee_type_not_reversible', v_result, FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_fee_type_not_reversible|FAIL|' || SQLERRM);
  END;

  -- tc_07: INTEREST tipi → FALSE
  BEGIN
    pkg_transactions.deposit(100005, 500, 'Interest type test', 'BRANCH', 2000, v_txn_id, v_ref);
    UPDATE transactions
    SET    transaction_type = 'INTEREST'
    WHERE  transaction_id = v_txn_id;
    v_result := pkg_transactions.is_reversible(v_txn_id);
    ROLLBACK;
    print_bool('tc_07_interest_type_not_reversible', v_result, FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_interest_type_not_reversible|FAIL|' || SQLERRM);
  END;

  -- tc_08: Status PENDING → FALSE (COMPLETED değil)
  BEGIN
    pkg_transactions.deposit(100000, 500, 'Pending status test', 'BRANCH', 2000, v_txn_id, v_ref);
    UPDATE transactions
    SET    status = 'PENDING'
    WHERE  transaction_id = v_txn_id;
    v_result := pkg_transactions.is_reversible(v_txn_id);
    ROLLBACK;
    print_bool('tc_08_pending_not_reversible', v_result, FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_pending_not_reversible|FAIL|' || SQLERRM);
  END;

  -- tc_09: Status FAILED → FALSE
  BEGIN
    pkg_transactions.deposit(100001, 500, 'Failed status test', 'BRANCH', 2000, v_txn_id, v_ref);
    UPDATE transactions
    SET    status = 'FAILED'
    WHERE  transaction_id = v_txn_id;
    v_result := pkg_transactions.is_reversible(v_txn_id);
    ROLLBACK;
    print_bool('tc_09_failed_not_reversible', v_result, FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_failed_not_reversible|FAIL|' || SQLERRM);
  END;

  -- tc_10: Status REVERSED → FALSE
  BEGIN
    pkg_transactions.deposit(100002, 500, 'Reversed status test', 'BRANCH', 2001, v_txn_id, v_ref);
    UPDATE transactions
    SET    status = 'REVERSED'
    WHERE  transaction_id = v_txn_id;
    v_result := pkg_transactions.is_reversible(v_txn_id);
    ROLLBACK;
    print_bool('tc_10_reversed_status_not_reversible', v_result, FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_reversed_status_not_reversible|FAIL|' || SQLERRM);
  END;

  -- tc_11: Var olmayan transaction_id → FALSE (NO_DATA_FOUND handler)
  BEGIN
    v_result := pkg_transactions.is_reversible(999999);
    print_bool('tc_11_nonexistent_txn', v_result, FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_nonexistent_txn|FAIL|' || SQLERRM);
  END;

  -- tc_12: NULL transaction_id → FALSE (NO_DATA_FOUND handler)
  BEGIN
    v_result := pkg_transactions.is_reversible(NULL);
    print_bool('tc_12_null_txn_id', v_result, FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_null_txn_id|FAIL|' || SQLERRM);
  END;

  -- tc_13: 23 saat 59 dakika önce → hâlâ TRUE (24 saat dolmamış)
  BEGIN
    pkg_transactions.deposit(100003, 500, 'Just under 24h', 'BRANCH', 2001, v_txn_id, v_ref);
    UPDATE transactions
    SET    transaction_date = SYSTIMESTAMP - INTERVAL '23' HOUR - INTERVAL '59' MINUTE
    WHERE  transaction_id = v_txn_id;
    v_result := pkg_transactions.is_reversible(v_txn_id);
    ROLLBACK;
    print_bool('tc_13_just_under_24h_reversible', v_result, TRUE);
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_just_under_24h_reversible|FAIL|' || SQLERRM);
  END;

END;
/