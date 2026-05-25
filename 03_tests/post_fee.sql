DECLARE
  v_txn_id    NUMBER;
  v_balance   NUMBER;
  v_avail     NUMBER;
  v_count     NUMBER;
  v_fee_amt   NUMBER;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: OVERDRAFT_FEE → sabit 35 uygulanır
  BEGIN
    pkg_transactions.post_fee(100000, 'OVERDRAFT_FEE', NULL, NULL, 2000, v_txn_id);
    SELECT balance INTO v_balance FROM accounts WHERE account_id = 100000;
    ROLLBACK;
    IF v_balance = 4965 AND v_txn_id IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_overdraft_fee|OK|balance:' || v_balance);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_overdraft_fee|FAIL|expected:4965 got:' || v_balance);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_overdraft_fee|FAIL|' || SQLERRM);
  END;

  -- tc_02: NSF_FEE → sabit 35 uygulanır
  BEGIN
    pkg_transactions.post_fee(100001, 'NSF_FEE', NULL, NULL, 2000, v_txn_id);
    SELECT balance INTO v_balance FROM accounts WHERE account_id = 100001;
    ROLLBACK;
    IF v_balance = 14965 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_nsf_fee|OK|balance:' || v_balance);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_nsf_fee|FAIL|expected:14965 got:' || v_balance);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_nsf_fee|FAIL|' || SQLERRM);
  END;

  -- tc_03: WIRE_FEE → sabit 25 uygulanır
  BEGIN
    pkg_transactions.post_fee(100002, 'WIRE_FEE', NULL, NULL, 2000, v_txn_id);
    SELECT balance INTO v_balance FROM accounts WHERE account_id = 100002;
    ROLLBACK;
    IF v_balance = 2475 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_wire_fee|OK|balance:' || v_balance);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_wire_fee|FAIL|expected:2475 got:' || v_balance);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_wire_fee|FAIL|' || SQLERRM);
  END;

  -- tc_04: ATM_FEE → sabit 3.50 uygulanır
  BEGIN
    pkg_transactions.post_fee(100003, 'ATM_FEE', NULL, NULL, 2001, v_txn_id);
    SELECT balance INTO v_balance FROM accounts WHERE account_id = 100003;
    ROLLBACK;
    IF v_balance = 49996.50 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_atm_fee|OK|balance:' || v_balance);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_atm_fee|FAIL|expected:49996.50 got:' || v_balance);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_atm_fee|FAIL|' || SQLERRM);
  END;

  -- tc_05: p_amount verilirse → custom fee uygulanır (sabit yerine)
  BEGIN
    pkg_transactions.post_fee(100000, 'OVERDRAFT_FEE', 10, NULL, 2000, v_txn_id);
    SELECT balance INTO v_balance FROM accounts WHERE account_id = 100000;
    ROLLBACK;
    IF v_balance = 4990 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_custom_amount|OK|balance:' || v_balance);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_custom_amount|FAIL|expected:4990 got:' || v_balance);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_custom_amount|FAIL|' || SQLERRM);
  END;

  -- tc_06: fee_ledger kaydı oluşur
  BEGIN
    pkg_transactions.post_fee(100004, 'WIRE_FEE', NULL, NULL, 2002, v_txn_id);
    SELECT COUNT(*) INTO v_count
    FROM   fee_ledger
    WHERE  account_id    = 100004
    AND    fee_type      = 'WIRE_FEE'
    AND    fee_amount    = 25
    AND    transaction_id = v_txn_id;
    ROLLBACK;
    IF v_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_fee_ledger_created|OK|count:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_fee_ledger_created|FAIL|expected:1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_fee_ledger_created|FAIL|' || SQLERRM);
  END;

  -- tc_07: Transaction FEE tipiyle SYSTEM channel'da oluşur
  BEGIN
    pkg_transactions.post_fee(100005, 'ATM_FEE', NULL, NULL, NULL, v_txn_id);
    SELECT COUNT(*) INTO v_count
    FROM   transactions
    WHERE  transaction_id   = v_txn_id
    AND    transaction_type = 'FEE'
    AND    channel          = 'SYSTEM'
    AND    status           = 'COMPLETED';
    ROLLBACK;
    IF v_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_txn_fee_type|OK|fee_txn_correct');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_txn_fee_type|FAIL|expected:1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_txn_fee_type|FAIL|' || SQLERRM);
  END;

  -- tc_08: NULL description → '{fee_type} charged' default
  BEGIN
    pkg_transactions.post_fee(100006, 'NSF_FEE', NULL, NULL, 2000, v_txn_id);
    SELECT COUNT(*) INTO v_count
    FROM   transactions
    WHERE  transaction_id = v_txn_id
    AND    description    = 'NSF_FEE charged';
    ROLLBACK;
    IF v_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_default_description|OK|description:NSF_FEE charged');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_default_description|FAIL|expected:1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_default_description|FAIL|' || SQLERRM);
  END;

  -- tc_09: available_balance de azalır
  BEGIN
    pkg_transactions.post_fee(100000, 'WIRE_FEE', NULL, NULL, 2000, v_txn_id);
    SELECT available_balance INTO v_avail FROM accounts WHERE account_id = 100000;
    ROLLBACK;
    IF v_avail = 4975 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_available_balance_updated|OK|available:' || v_avail);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_available_balance_updated|FAIL|expected:4975 got:' || v_avail);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_available_balance_updated|FAIL|' || SQLERRM);
  END;

  -- tc_10: CHECKING monthly_fee=5 → MONTHLY_FEE için account type'tan alınır
  BEGIN
    pkg_transactions.post_fee(100000, 'MONTHLY_FEE', NULL, NULL, 2000, v_txn_id);
    SELECT balance INTO v_balance FROM accounts WHERE account_id = 100000;
    ROLLBACK;
    IF v_balance = 4995 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_monthly_fee_checking|OK|balance:' || v_balance);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_monthly_fee_checking|FAIL|expected:4995 got:' || v_balance);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_monthly_fee_checking|FAIL|' || SQLERRM);
  END;

  -- tc_11: SAVINGS monthly_fee=0 → fee uygulanmaz, txn_id NULL döner
  BEGIN
    pkg_transactions.post_fee(100001, 'MONTHLY_FEE', NULL, NULL, 2000, v_txn_id);
    SELECT balance INTO v_balance FROM accounts WHERE account_id = 100001;
    ROLLBACK;
    IF v_balance = 15000 AND v_txn_id IS NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_zero_monthly_fee_savings|OK|balance:' || v_balance || ' txn_id:NULL');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_zero_monthly_fee_savings|FAIL|balance:' || v_balance || ' txn_id:' || v_txn_id);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_zero_monthly_fee_savings|FAIL|' || SQLERRM);
  END;

  -- tc_12: p_amount=0 → fee uygulanmaz (NVL guard)
  BEGIN
    pkg_transactions.post_fee(100002, 'OVERDRAFT_FEE', 0, NULL, 2000, v_txn_id);
    SELECT balance INTO v_balance FROM accounts WHERE account_id = 100002;
    ROLLBACK;
    IF v_balance = 2500 AND v_txn_id IS NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_zero_amount_no_fee|OK|balance_unchanged');
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_zero_amount_no_fee|FAIL|balance:' || v_balance);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_zero_amount_no_fee|FAIL|' || SQLERRM);
  END;

  -- tc_13: Negatif bakiyeye izin verilir (mandatory fee)
  -- David'in 800 bakiyesi var, 35 + 35 = 70 fee → balance=730 (negatife düşmez bu örnekte)
  -- Daha büyük fee test edelim: custom 900 → balance=-100
  BEGIN
    pkg_transactions.post_fee(100004, 'OVERDRAFT_FEE', 900, 'Force negative', 2002, v_txn_id);
    SELECT balance INTO v_balance FROM accounts WHERE account_id = 100004;
    ROLLBACK;
    IF v_balance = -100 AND v_txn_id IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_negative_balance_allowed|OK|balance:' || v_balance);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_negative_balance_allowed|FAIL|balance:' || v_balance);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_negative_balance_allowed|FAIL|' || SQLERRM);
  END;

END;
/