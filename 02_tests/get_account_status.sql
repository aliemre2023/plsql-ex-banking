DECLARE
  v_result VARCHAR2(20);
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- Test: tc_01_active_checking — Return ACTIVE for Alice's checking account
  BEGIN
    v_result := pkg_account_mgmt.get_account_status(100000);
    IF v_result = 'ACTIVE' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_active_checking|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_active_checking|FAIL|expected:ACTIVE got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_active_checking|FAIL|' || SQLERRM);
  END;

  -- Test: tc_02_active_savings — Return ACTIVE for Alice's savings account
  BEGIN
    v_result := pkg_account_mgmt.get_account_status(100001);
    IF v_result = 'ACTIVE' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_active_savings|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_active_savings|FAIL|expected:ACTIVE got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_active_savings|FAIL|' || SQLERRM);
  END;

  -- Test: tc_03_active_premium — Return ACTIVE for Eve's premium account
  BEGIN
    v_result := pkg_account_mgmt.get_account_status(100005);
    IF v_result = 'ACTIVE' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_active_premium|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_active_premium|FAIL|expected:ACTIVE got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_active_premium|FAIL|' || SQLERRM);
  END;

  -- Test: tc_04_inactive_status — Return INACTIVE for an inactive account
  BEGIN
    UPDATE accounts SET status = 'INACTIVE' WHERE account_id = 100002;
    v_result := pkg_account_mgmt.get_account_status(100002);
    ROLLBACK;
    IF v_result = 'INACTIVE' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_inactive_status|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_inactive_status|FAIL|expected:INACTIVE got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_inactive_status|FAIL|' || SQLERRM);
  END;

  -- Test: tc_05_frozen_status — Return FROZEN for a frozen account
  BEGIN
    UPDATE accounts SET status = 'FROZEN' WHERE account_id = 100002;
    v_result := pkg_account_mgmt.get_account_status(100002);
    ROLLBACK;
    IF v_result = 'FROZEN' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_frozen_status|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_frozen_status|FAIL|expected:FROZEN got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_frozen_status|FAIL|' || SQLERRM);
  END;

  -- Test: tc_06_closed_status — Return CLOSED for a closed account
  BEGIN
    UPDATE accounts SET status = 'CLOSED' WHERE account_id = 100002;
    v_result := pkg_account_mgmt.get_account_status(100002);
    ROLLBACK;
    IF v_result = 'CLOSED' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_closed_status|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_closed_status|FAIL|expected:CLOSED got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_closed_status|FAIL|' || SQLERRM);
  END;

  -- Test: tc_07_dormant_status — Return DORMANT for a dormant account
  BEGIN
    UPDATE accounts SET status = 'DORMANT' WHERE account_id = 100002;
    v_result := pkg_account_mgmt.get_account_status(100002);
    ROLLBACK;
    IF v_result = 'DORMANT' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_dormant_status|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_dormant_status|FAIL|expected:DORMANT got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_dormant_status|FAIL|' || SQLERRM);
  END;

  -- Test: tc_08_nonexistent_account — Return NOT_FOUND for a non-existent account_id
  BEGIN
    v_result := pkg_account_mgmt.get_account_status(999999);
    IF v_result = 'NOT_FOUND' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_nonexistent_account|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_nonexistent_account|FAIL|expected:NOT_FOUND got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_nonexistent_account|FAIL|' || SQLERRM);
  END;

  -- Test: tc_09_null_account_id — Return NOT_FOUND for NULL account_id (NO_DATA_FOUND handler)
  BEGIN
    v_result := pkg_account_mgmt.get_account_status(NULL);
    IF v_result = 'NOT_FOUND' THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_null_account_id|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_null_account_id|FAIL|expected:NOT_FOUND got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_null_account_id|FAIL|' || SQLERRM);
  END;

END;
/