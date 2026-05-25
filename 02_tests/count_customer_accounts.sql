DECLARE
  v_result NUMBER;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- Test: tc_01_single_active_account — Return 1 for customer with one ACTIVE account (Bob)
  BEGIN
    v_result := pkg_account_mgmt.count_customer_accounts(1001);
    IF v_result = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_single_active_account|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_single_active_account|FAIL|expected:1 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_single_active_account|FAIL|' || SQLERRM);
  END;

  -- Test: tc_02_two_active_accounts — Return 2 for customer with two ACTIVE accounts (Alice)
  BEGIN
    v_result := pkg_account_mgmt.count_customer_accounts(1000);
    IF v_result = 2 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_two_active_accounts|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_two_active_accounts|FAIL|expected:2 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_two_active_accounts|FAIL|' || SQLERRM);
  END;

  -- Test: tc_03_explicit_active_status — Explicit p_status='ACTIVE' returns same as default
  BEGIN
    v_result := pkg_account_mgmt.count_customer_accounts(1000, 'ACTIVE');
    IF v_result = 2 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_explicit_active_status|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_explicit_active_status|FAIL|expected:2 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_explicit_active_status|FAIL|' || SQLERRM);
  END;

  -- Test: tc_04_all_status — p_status='ALL' returns total account count regardless of status (Alice)
  DECLARE
    v_before NUMBER;
    v_after  NUMBER;
  BEGIN
    v_before := pkg_account_mgmt.count_customer_accounts(1000, 'ALL'); -- tüm ACTIVE: 2
    UPDATE accounts SET status = 'CLOSED' WHERE account_id = 100001;
    v_after := pkg_account_mgmt.count_customer_accounts(1000, 'ALL');  -- CLOSED dahil: hâlâ 2
    ROLLBACK;
    IF v_before = 2 AND v_after = 2 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_all_status|OK|before:' || v_before || ' after:' || v_after);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_all_status|FAIL|before:' || v_before || ' after:' || v_after);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_all_status|FAIL|' || SQLERRM);
  END;

  -- Test: tc_05_inactive_status_filter — Return count of only INACTIVE accounts
  BEGIN
    UPDATE accounts SET status = 'INACTIVE' WHERE account_id = 100001; -- Alice SAVINGS
    v_result := pkg_account_mgmt.count_customer_accounts(1000, 'INACTIVE');
    ROLLBACK;
    IF v_result = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_inactive_status_filter|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_inactive_status_filter|FAIL|expected:1 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_inactive_status_filter|FAIL|' || SQLERRM);
  END;

  -- Test: tc_06_frozen_status_filter — Return count of only FROZEN accounts
  BEGIN
    UPDATE accounts SET status = 'FROZEN' WHERE account_id = 100005; -- Eve PREMIUM
    v_result := pkg_account_mgmt.count_customer_accounts(1004, 'FROZEN');
    ROLLBACK;
    IF v_result = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_frozen_status_filter|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_frozen_status_filter|FAIL|expected:1 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_frozen_status_filter|FAIL|' || SQLERRM);
  END;

  -- Test: tc_07_no_matching_status — Return 0 when no accounts match the given status
  BEGIN
    v_result := pkg_account_mgmt.count_customer_accounts(1001, 'CLOSED'); -- Bob'un CLOSED account'ı yok
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_no_matching_status|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_no_matching_status|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_no_matching_status|FAIL|' || SQLERRM);
  END;

  -- Test: tc_08_nonexistent_customer — Return 0 for a customer_id that does not exist
  BEGIN
    v_result := pkg_account_mgmt.count_customer_accounts(999999);
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_nonexistent_customer|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_nonexistent_customer|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_nonexistent_customer|FAIL|' || SQLERRM);
  END;

  -- Test: tc_09_null_customer_id — Return 0 for NULL customer_id
  BEGIN
    v_result := pkg_account_mgmt.count_customer_accounts(NULL);
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_null_customer_id|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_null_customer_id|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_null_customer_id|FAIL|' || SQLERRM);
  END;

  -- Test: tc_10_null_status — NULL p_status matches no accounts (OR condition fails both sides)
  BEGIN
    v_result := pkg_account_mgmt.count_customer_accounts(1000, NULL);
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_null_status|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_null_status|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_null_status|FAIL|' || SQLERRM);
  END;

  -- Test: tc_11_all_status_nonexistent_customer — p_status='ALL' returns 0 for non-existent customer
  BEGIN
    v_result := pkg_account_mgmt.count_customer_accounts(999999, 'ALL');
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_all_status_nonexistent_customer|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_all_status_nonexistent_customer|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_11_all_status_nonexistent_customer|FAIL|' || SQLERRM);
  END;

END;
/