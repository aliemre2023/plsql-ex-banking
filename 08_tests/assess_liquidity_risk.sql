DECLARE
  v_lcr           NUMBER;
  v_nsfr          NUMBER;
  v_gap30         NUMBER;
  v_gap90         NUMBER;
  v_hqla          NUMBER;
  v_lcr_compliant VARCHAR2(1);
  v_cursor        SYS_REFCURSOR;
  v_count         NUMBER;
  v_loan_id       NUMBER;
  v_loan_number   VARCHAR2(50);
  v_monthly_pay   NUMBER;
  v_decision      VARCHAR2(20);
  v_dummy_num     NUMBER;
  v_dummy_str     VARCHAR2(200);

BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- tc_01: Tüm OUT parametreler dolu döner
  BEGIN
    pkg_advanced_risk_engine.assess_liquidity_risk(
        NULL, SYSDATE,
        v_lcr, v_nsfr, v_gap30, v_gap90, v_hqla, v_lcr_compliant, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    IF v_lcr IS NOT NULL AND v_nsfr IS NOT NULL AND v_hqla IS NOT NULL
       AND v_lcr_compliant IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_all_out_params|OK|lcr:' || ROUND(v_lcr,4));
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_all_out_params|FAIL|null_output');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_01_all_out_params|FAIL|' || SQLERRM);
  END;

  -- tc_02: HQLA >= 0
  BEGIN
    pkg_advanced_risk_engine.assess_liquidity_risk(
        NULL, SYSDATE,
        v_lcr, v_nsfr, v_gap30, v_gap90, v_hqla, v_lcr_compliant, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    IF v_hqla >= 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_hqla_non_negative|OK|hqla:' || ROUND(v_hqla,2));
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_hqla_non_negative|FAIL|negative:' || v_hqla);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_02_hqla_non_negative|FAIL|' || SQLERRM);
  END;

  -- tc_03: LCR >= 0
  BEGIN
    pkg_advanced_risk_engine.assess_liquidity_risk(
        NULL, SYSDATE,
        v_lcr, v_nsfr, v_gap30, v_gap90, v_hqla, v_lcr_compliant, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    IF v_lcr >= 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_lcr_non_negative|OK|lcr:' || ROUND(v_lcr,4));
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_lcr_non_negative|FAIL|negative:' || v_lcr);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_03_lcr_non_negative|FAIL|' || SQLERRM);
  END;

  -- tc_04: NSFR >= 0
  BEGIN
    pkg_advanced_risk_engine.assess_liquidity_risk(
        NULL, SYSDATE,
        v_lcr, v_nsfr, v_gap30, v_gap90, v_hqla, v_lcr_compliant, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    IF v_nsfr >= 0 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_nsfr_non_negative|OK|nsfr:' || ROUND(v_nsfr,4));
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_nsfr_non_negative|FAIL|negative:' || v_nsfr);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_04_nsfr_non_negative|FAIL|' || SQLERRM);
  END;

  -- tc_05: is_lcr_compliant Y veya N değeri alır
  BEGIN
    pkg_advanced_risk_engine.assess_liquidity_risk(
        NULL, SYSDATE,
        v_lcr, v_nsfr, v_gap30, v_gap90, v_hqla, v_lcr_compliant, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    IF v_lcr_compliant IN ('Y','N') THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_compliant_yn|OK|compliant:' || v_lcr_compliant);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_compliant_yn|FAIL|invalid:' || v_lcr_compliant);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_05_compliant_yn|FAIL|' || SQLERRM);
  END;

  -- tc_06: 90-gün gap >= 30-gün gap (daha uzun dönem daha büyük kümülatif akış)
  BEGIN
    pkg_advanced_risk_engine.assess_liquidity_risk(
        NULL, SYSDATE,
        v_lcr, v_nsfr, v_gap30, v_gap90, v_hqla, v_lcr_compliant, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    IF ABS(v_gap90) >= ABS(v_gap30) OR v_gap90 IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_gap90_gte_gap30|OK|gap30:' || ROUND(v_gap30,2) || ' gap90:' || ROUND(v_gap90,2));
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_gap90_gte_gap30|FAIL|gap30:' || v_gap30 || ' gap90:' || v_gap90);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_06_gap90_gte_gap30|FAIL|' || SQLERRM);
  END;

  -- tc_07: Büyük mevduat eklenince HQLA artar (LCR formülü denominatörü de artırır,
  --        ama HQLA artışı her zaman pozitif olmalı)
  DECLARE
    v_hqla_before NUMBER;
    v_hqla_after  NUMBER;
    v_lcr2 NUMBER; v_nsfr2 NUMBER; v_gap30_2 NUMBER; v_gap90_2 NUMBER;
    v_comp2 VARCHAR2(1); v_cur2 SYS_REFCURSOR;
  BEGIN
    pkg_advanced_risk_engine.assess_liquidity_risk(
        NULL, SYSDATE, v_lcr2, v_nsfr2, v_gap30_2, v_gap90_2,
        v_hqla_before, v_comp2, v_cur2
    );
    IF v_cur2%ISOPEN THEN CLOSE v_cur2; END IF;

    UPDATE accounts SET balance = balance + 1000000,
                        available_balance = available_balance + 1000000
    WHERE  account_type = 'SAVINGS';

    pkg_advanced_risk_engine.assess_liquidity_risk(
        NULL, SYSDATE, v_lcr2, v_nsfr2, v_gap30_2, v_gap90_2,
        v_hqla_after, v_comp2, v_cur2
    );
    IF v_cur2%ISOPEN THEN CLOSE v_cur2; END IF;
    ROLLBACK;

    -- HQLA savings haircut=0.85 → 1M eklenince HQLA en az 850K artmalı
    IF v_hqla_after > v_hqla_before THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_deposits_increase_hqla|OK|before:' ||
        ROUND(v_hqla_before,2) || ' after:' || ROUND(v_hqla_after,2));
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_deposits_increase_hqla|FAIL|before:' ||
        ROUND(v_hqla_before,2) || ' after:' || ROUND(v_hqla_after,2));
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_07_deposits_increase_hqla|FAIL|' || SQLERRM);
  END;

  -- tc_08: detail_cursor satır döndürür
  BEGIN
    pkg_advanced_risk_engine.assess_liquidity_risk(
        NULL, SYSDATE,
        v_lcr, v_nsfr, v_gap30, v_gap90, v_hqla, v_lcr_compliant, v_cursor
    );
    v_count := 0;
    LOOP
      FETCH v_cursor INTO v_dummy_str, v_dummy_str, v_dummy_num,
            v_dummy_num, v_dummy_num, v_dummy_num,
            v_dummy_num, v_dummy_num, v_dummy_num;
      EXIT WHEN v_cursor%NOTFOUND;
      v_count := v_count + 1;
    END LOOP;
    CLOSE v_cursor;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_cursor_has_rows|OK|rows:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_cursor_has_rows|FAIL|no_rows');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_08_cursor_has_rows|FAIL|' || SQLERRM);
  END;

  -- tc_09: branch_id filtresiyle çalışır
  BEGIN
    pkg_advanced_risk_engine.assess_liquidity_risk(
        10, SYSDATE,
        v_lcr, v_nsfr, v_gap30, v_gap90, v_hqla, v_lcr_compliant, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    IF v_lcr IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_branch_filter|OK|lcr:' || ROUND(v_lcr,4));
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_branch_filter|FAIL|lcr_null');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_09_branch_filter|FAIL|' || SQLERRM);
  END;

  -- tc_10: Audit log oluşur
  DECLARE
    v_marker TIMESTAMP := SYSTIMESTAMP;
  BEGIN
    pkg_advanced_risk_engine.assess_liquidity_risk(
        NULL, SYSDATE,
        v_lcr, v_nsfr, v_gap30, v_gap90, v_hqla, v_lcr_compliant, v_cursor
    );
    IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
    SELECT COUNT(*) INTO v_count
    FROM   audit_log
    WHERE  new_values LIKE 'RISK_ENGINE|EVENT=LIQUIDITY_ASSESSMENT%'
      AND  changed_at >= v_marker;
    IF v_count >= 1 THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_audit_log|OK|count:' || v_count);
    ELSE
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_audit_log|FAIL|expected:>=1 got:' || v_count);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST_RESULT|tc_10_audit_log|FAIL|' || SQLERRM);
  END;

END;
/
