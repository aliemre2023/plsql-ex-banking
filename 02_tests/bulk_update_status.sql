DECLARE
  v_updated_count NUMBER;
  v_status_after  VARCHAR2(20);
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- Test: tc_01_single_account_active_to_inactive — Update one account to INACTIVE
  BEGIN
    pkg_account_mgmt.bulk_update_status(t_number_list(100000), 'INACTIVE', 'Test reason', 2000, v_updated_count);
    SELECT status INTO v_status_after FROM accounts WHERE account_id = 100000;
    ROLLBACK;
    IF v_updated_count = 1 AND v_status_after = 'INACTIVE' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_single_account_active_to_inactive|OK|count:' || v_updated_count || ' status:' || v_status_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_single_account_active_to_inactive|FAIL|count:' || v_updated_count || ' status:' || v_status_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_single_account_active_to_inactive|FAIL|' || SQLERRM);
  END;

  -- Test: tc_02_multiple_accounts — Update multiple accounts to FROZEN
  DECLARE
    v_count_frozen NUMBER;
  BEGIN
    pkg_account_mgmt.bulk_update_status(t_number_list(100000, 100001, 100002), 'FROZEN', 'Compliance', 2001, v_updated_count);
    SELECT COUNT(*) INTO v_count_frozen FROM accounts
    WHERE  account_id IN (100000, 100001, 100002) AND status = 'FROZEN';
    ROLLBACK;
    IF v_updated_count = 3 AND v_count_frozen = 3 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_multiple_accounts|OK|count:' || v_updated_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_multiple_accounts|FAIL|updated:' || v_updated_count || ' frozen:' || v_count_frozen);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_multiple_accounts|FAIL|' || SQLERRM);
  END;

  -- Test: tc_03_all_valid_statuses_active — Update to ACTIVE succeeds
  BEGIN
    UPDATE accounts SET status = 'DORMANT' WHERE account_id = 100003;
    pkg_account_mgmt.bulk_update_status(t_number_list(100003), 'ACTIVE', 'Reactivation', 2000, v_updated_count);
    SELECT status INTO v_status_after FROM accounts WHERE account_id = 100003;
    ROLLBACK;
    IF v_updated_count = 1 AND v_status_after = 'ACTIVE' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_all_valid_statuses_active|OK|count:' || v_updated_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_all_valid_statuses_active|FAIL|count:' || v_updated_count || ' status:' || v_status_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_all_valid_statuses_active|FAIL|' || SQLERRM);
  END;

  -- Test: tc_04_dormant_status — Update to DORMANT succeeds
  BEGIN
    pkg_account_mgmt.bulk_update_status(t_number_list(100004), 'DORMANT', 'Dormancy batch', 2002, v_updated_count);
    SELECT status INTO v_status_after FROM accounts WHERE account_id = 100004;
    ROLLBACK;
    IF v_updated_count = 1 AND v_status_after = 'DORMANT' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_dormant_status|OK|count:' || v_updated_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_dormant_status|FAIL|count:' || v_updated_count || ' status:' || v_status_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_dormant_status|FAIL|' || SQLERRM);
  END;

  -- Test: tc_05_closed_status_blocked — Raise -20021 when p_new_status = 'CLOSED'
  BEGIN
    pkg_account_mgmt.bulk_update_status(t_number_list(100000), 'CLOSED', 'Bulk close', 2000, v_updated_count);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_closed_status_blocked|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20021 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_closed_status_blocked|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_closed_status_blocked|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_06_invalid_status — Raise -20020 for unrecognised status value
  BEGIN
    pkg_account_mgmt.bulk_update_status(t_number_list(100000), 'SUSPENDED', 'Test', 2000, v_updated_count);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_invalid_status|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20020 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_invalid_status|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_invalid_status|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_07_null_status — Raise -20020 for NULL p_new_status
  BEGIN
    pkg_account_mgmt.bulk_update_status(t_number_list(100000), NULL, 'Test', 2000, v_updated_count);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_null_status|FAIL|Expected exception not raised');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE = -20020 THEN
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_null_status|OK|exception_raised');
      ELSE
        DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_null_status|FAIL|wrong_exception:' || SQLCODE);
      END IF;
  END;

  -- Test: tc_08_skips_closed_accounts — CLOSED accounts excluded from update, count reflects only non-closed
  DECLARE
    v_status_closed  VARCHAR2(20);
    v_status_active  VARCHAR2(20);
  BEGIN
    UPDATE accounts SET status = 'CLOSED' WHERE account_id = 100005;
    pkg_account_mgmt.bulk_update_status(t_number_list(100005, 100006), 'INACTIVE', 'Test', 2001, v_updated_count);
    SELECT status INTO v_status_closed FROM accounts WHERE account_id = 100005;
    SELECT status INTO v_status_active FROM accounts WHERE account_id = 100006;
    ROLLBACK;
    IF v_updated_count = 1 AND v_status_closed = 'CLOSED' AND v_status_active = 'INACTIVE' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_skips_closed_accounts|OK|count:' || v_updated_count || ' closed_unchanged:' || v_status_closed);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_skips_closed_accounts|FAIL|count:' || v_updated_count || ' closed:' || v_status_closed || ' other:' || v_status_active);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_skips_closed_accounts|FAIL|' || SQLERRM);
  END;

  -- Test: tc_09_empty_list — Empty t_number_list results in 0 updates
  BEGIN
    pkg_account_mgmt.bulk_update_status(t_number_list(), 'INACTIVE', 'Empty list', 2000, v_updated_count);
    ROLLBACK;
    IF v_updated_count = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_empty_list|OK|count:' || v_updated_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_empty_list|FAIL|expected:0 got:' || v_updated_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_empty_list|FAIL|' || SQLERRM);
  END;

  -- Test: tc_10_nonexistent_ids — All IDs non-existent, 0 rows updated
  BEGIN
    pkg_account_mgmt.bulk_update_status(t_number_list(888888, 999999), 'INACTIVE', 'Ghost ids', 2000, v_updated_count);
    ROLLBACK;
    IF v_updated_count = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_nonexistent_ids|OK|count:' || v_updated_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_nonexistent_ids|FAIL|expected:0 got:' || v_updated_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_nonexistent_ids|FAIL|' || SQLERRM);
  END;

  -- Test: tc_11_mixed_valid_invalid_ids — Mix of valid and non-existent IDs, only valid ones updated
  BEGIN
    pkg_account_mgmt.bulk_update_status(t_number_list(100000, 999999), 'DORMANT', 'Mixed', 2003, v_updated_count);
    SELECT status INTO v_status_after FROM accounts WHERE account_id = 100000;
    ROLLBACK;
    IF v_updated_count = 1 AND v_status_after = 'DORMANT' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_mixed_valid_invalid_ids|OK|count:' || v_updated_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_mixed_valid_invalid_ids|FAIL|count:' || v_updated_count || ' status:' || v_status_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_mixed_valid_invalid_ids|FAIL|' || SQLERRM);
  END;

  -- Test: tc_12_same_status_update — Update account to its current status, row still updated (no guard)
  BEGIN
    pkg_account_mgmt.bulk_update_status(t_number_list(100001), 'ACTIVE', 'No-op test', 2000, v_updated_count);
    ROLLBACK;
    IF v_updated_count = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_same_status_update|OK|count:' || v_updated_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_same_status_update|FAIL|expected:1 got:' || v_updated_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_12_same_status_update|FAIL|' || SQLERRM);
  END;

  -- Test: tc_13_all_seven_accounts — Bulk update all seed accounts to FROZEN
  DECLARE
    v_frozen_count NUMBER;
  BEGIN
    pkg_account_mgmt.bulk_update_status(
      t_number_list(100000, 100001, 100002, 100003, 100004, 100005, 100006),
      'FROZEN', 'Full freeze', 2000, v_updated_count);
    SELECT COUNT(*) INTO v_frozen_count FROM accounts WHERE status = 'FROZEN';
    ROLLBACK;
    IF v_updated_count = 7 AND v_frozen_count = 7 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_all_seven_accounts|OK|count:' || v_updated_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_all_seven_accounts|FAIL|updated:' || v_updated_count || ' frozen:' || v_frozen_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_13_all_seven_accounts|FAIL|' || SQLERRM);
  END;

END;
/