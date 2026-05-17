DECLARE
  v_result NUMBER;
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- Test: tc_01_opened_today — Return 0 for account opened today (DEFAULT SYSDATE)
  BEGIN
    v_result := pkg_account_mgmt.get_account_age_days(100000); -- Alice CHECKING
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_opened_today|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_opened_today|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_opened_today|FAIL|' || SQLERRM);
  END;

  -- Test: tc_02_opened_30_days_ago — Return 30 for account opened 30 days ago
  BEGIN
    UPDATE accounts SET opened_date = TRUNC(SYSDATE) - 30 WHERE account_id = 100001;
    v_result := pkg_account_mgmt.get_account_age_days(100001);
    ROLLBACK;
    IF v_result = 30 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_opened_30_days_ago|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_opened_30_days_ago|FAIL|expected:30 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_opened_30_days_ago|FAIL|' || SQLERRM);
  END;

  -- Test: tc_03_opened_365_days_ago — Return 365 for account opened exactly one year ago
  BEGIN
    UPDATE accounts SET opened_date = TRUNC(SYSDATE) - 365 WHERE account_id = 100002;
    v_result := pkg_account_mgmt.get_account_age_days(100002);
    ROLLBACK;
    IF v_result = 365 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_opened_365_days_ago|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_opened_365_days_ago|FAIL|expected:365 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_opened_365_days_ago|FAIL|' || SQLERRM);
  END;

  -- Test: tc_04_opened_1_day_ago — Return 1 for account opened yesterday
  BEGIN
    UPDATE accounts SET opened_date = TRUNC(SYSDATE) - 1 WHERE account_id = 100003;
    v_result := pkg_account_mgmt.get_account_age_days(100003);
    ROLLBACK;
    IF v_result = 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_opened_1_day_ago|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_opened_1_day_ago|FAIL|expected:1 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_opened_1_day_ago|FAIL|' || SQLERRM);
  END;

  -- Test: tc_05_trunc_intraday — TRUNC ensures partial day is not counted (opened same day = 0)
  BEGIN
    UPDATE accounts SET opened_date = TRUNC(SYSDATE) WHERE account_id = 100004;
    v_result := pkg_account_mgmt.get_account_age_days(100004);
    ROLLBACK;
    IF v_result = 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_trunc_intraday|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_trunc_intraday|FAIL|expected:0 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_trunc_intraday|FAIL|' || SQLERRM);
  END;

  -- Test: tc_06_long_standing_account — Return correct age for account opened 10 years ago
  BEGIN
    UPDATE accounts SET opened_date = TRUNC(SYSDATE) - 3650 WHERE account_id = 100005;
    v_result := pkg_account_mgmt.get_account_age_days(100005);
    ROLLBACK;
    IF v_result = 3650 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_long_standing_account|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_long_standing_account|FAIL|expected:3650 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_long_standing_account|FAIL|' || SQLERRM);
  END;

  -- Test: tc_07_nonexistent_account — Return -1 for non-existent account_id (NO_DATA_FOUND handler)
  BEGIN
    v_result := pkg_account_mgmt.get_account_age_days(999999);
    IF v_result = -1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_nonexistent_account|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_nonexistent_account|FAIL|expected:-1 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_nonexistent_account|FAIL|' || SQLERRM);
  END;

  -- Test: tc_08_null_account_id — Return -1 for NULL account_id (NO_DATA_FOUND handler)
  BEGIN
    v_result := pkg_account_mgmt.get_account_age_days(NULL);
    IF v_result = -1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_null_account_id|OK|returned:' || v_result);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_null_account_id|FAIL|expected:-1 got:' || v_result);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_null_account_id|FAIL|' || SQLERRM);
  END;

  -- Test: tc_09_result_non_negative — Age is always >= 0 for existing accounts
  DECLARE
    v_age1 NUMBER;
    v_age2 NUMBER;
    v_age3 NUMBER;
  BEGIN
    v_age1 := pkg_account_mgmt.get_account_age_days(100000);
    v_age2 := pkg_account_mgmt.get_account_age_days(100003);
    v_age3 := pkg_account_mgmt.get_account_age_days(100006);
    IF v_age1 >= 0 AND v_age2 >= 0 AND v_age3 >= 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_result_non_negative|OK|ages:' || v_age1 || ',' || v_age2 || ',' || v_age3);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_result_non_negative|FAIL|ages:' || v_age1 || ',' || v_age2 || ',' || v_age3);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_result_non_negative|FAIL|' || SQLERRM);
  END;

END;
/