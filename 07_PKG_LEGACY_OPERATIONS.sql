-- =============================================================================
-- FILE 07: PKG_LEGACY_OPERATIONS
-- Legacy Banking Operations - Supplemental Packages
-- Oracle PL/SQL -- Banking Core System v1.0 (circa 2003)
-- Contains 10 complex legacy-style PL/SQL packages
-- =============================================================================

-- =============================================================================
-- PACKAGE 1: PKG_KYC_VERIFICATION
-- Know Your Customer Verification Package
-- =============================================================================

CREATE OR REPLACE PACKAGE pkg_kyc_verification AS
    c_kyc_expiry_months   CONSTANT NUMBER := 24;
    c_max_risk_score      CONSTANT NUMBER := 100;

    e_kyc_already_verified  EXCEPTION;
    e_kyc_documents_missing EXCEPTION;
    e_kyc_expired           EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_kyc_already_verified,  -20100);
    PRAGMA EXCEPTION_INIT(e_kyc_documents_missing, -20101);
    PRAGMA EXCEPTION_INIT(e_kyc_expired,           -20102);

    FUNCTION  get_kyc_status(p_customer_id IN NUMBER) RETURN VARCHAR2;
    FUNCTION  is_kyc_valid(p_customer_id IN NUMBER) RETURN BOOLEAN;
    FUNCTION  calculate_kyc_risk_score(p_customer_id IN NUMBER) RETURN NUMBER;
    FUNCTION  get_days_since_verification(p_customer_id IN NUMBER) RETURN NUMBER;
    FUNCTION  count_pending_kyc_customers RETURN NUMBER;

    PROCEDURE verify_customer_identity(
        p_customer_id IN NUMBER, p_employee_id IN NUMBER,
        p_doc_type IN VARCHAR2, p_doc_number IN VARCHAR2, p_result OUT VARCHAR2);
    PROCEDURE update_kyc_status(
        p_customer_id IN NUMBER, p_new_status IN VARCHAR2,
        p_reason IN VARCHAR2, p_employee_id IN NUMBER);
    PROCEDURE expire_overdue_kyc_records(p_expired_count OUT NUMBER);
    PROCEDURE run_kyc_batch_recheck(
        p_branch_id IN NUMBER DEFAULT NULL, p_checked_count OUT NUMBER,
        p_updated_count OUT NUMBER, p_flagged_count OUT NUMBER);
    PROCEDURE generate_kyc_compliance_report(
        p_as_of_date IN DATE DEFAULT SYSDATE, p_report OUT SYS_REFCURSOR);
END pkg_kyc_verification;
/

CREATE OR REPLACE PACKAGE BODY pkg_kyc_verification AS

    PROCEDURE p_log_kyc_event(p_customer_id IN NUMBER, p_event IN VARCHAR2, p_details IN VARCHAR2) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO audit_log(table_name,record_id,action,new_values,changed_by,changed_at)
        VALUES('CUSTOMERS',p_customer_id,'UPDATE',
               'KYC_EVENT='||p_event||'|'||SUBSTR(p_details,1,3500),
               SYS_CONTEXT('USERENV','SESSION_USER'),SYSTIMESTAMP);
        COMMIT;
    EXCEPTION WHEN OTHERS THEN NULL;
    END p_log_kyc_event;

    -- -------------------------------------------------------------------------
    FUNCTION get_kyc_status(p_customer_id IN NUMBER) RETURN VARCHAR2 IS
        v_kyc_status  VARCHAR2(20);
        v_is_active   CHAR(1);
        v_cust_code   VARCHAR2(20);
        v_cust_name   VARCHAR2(200);
    BEGIN
        BEGIN
            SELECT c.kyc_status, c.is_active, c.customer_code,
                   c.first_name||' '||c.last_name
            INTO   v_kyc_status, v_is_active, v_cust_code, v_cust_name
            FROM   customers c
            WHERE  c.customer_id = p_customer_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN RETURN 'NOT_FOUND';
            WHEN TOO_MANY_ROWS THEN RETURN 'DATA_ERROR';
        END;
        IF v_is_active = 'N' THEN RETURN 'INACTIVE_CUSTOMER'; END IF;
        DBMS_OUTPUT.PUT_LINE('KYC Query: '||v_cust_code||' '||v_cust_name||' => '||v_kyc_status);
        RETURN NVL(v_kyc_status, 'UNKNOWN');
    END get_kyc_status;

    -- -------------------------------------------------------------------------
    FUNCTION is_kyc_valid(p_customer_id IN NUMBER) RETURN BOOLEAN IS
        v_status       VARCHAR2(20);
        v_updated_at   TIMESTAMP;
        v_months_since NUMBER;
    BEGIN
        BEGIN
            SELECT kyc_status, updated_at
            INTO   v_status, v_updated_at
            FROM   customers
            WHERE  customer_id = p_customer_id AND is_active = 'Y';
        EXCEPTION WHEN NO_DATA_FOUND THEN RETURN FALSE;
        END;
        IF v_status = 'VERIFIED' THEN
            v_months_since := MONTHS_BETWEEN(SYSDATE, TRUNC(v_updated_at));
            IF v_months_since <= c_kyc_expiry_months THEN
                RETURN TRUE;
            ELSE
                DBMS_OUTPUT.PUT_LINE('WARNING: KYC expired for '||p_customer_id||
                    ' - '||ROUND(v_months_since,1)||' months old');
                RETURN FALSE;
            END IF;
        ELSIF v_status = 'PENDING' THEN
            DBMS_OUTPUT.PUT_LINE('INFO: KYC pending for '||p_customer_id);
            RETURN FALSE;
        ELSIF v_status = 'REJECTED' THEN
            DBMS_OUTPUT.PUT_LINE('WARNING: KYC rejected for '||p_customer_id);
            RETURN FALSE;
        END IF;
        RETURN FALSE;
    END is_kyc_valid;

    -- -------------------------------------------------------------------------
    FUNCTION calculate_kyc_risk_score(p_customer_id IN NUMBER) RETURN NUMBER IS
        v_risk_level      VARCHAR2(10);
        v_customer_type   VARCHAR2(20);
        v_credit_score    NUMBER;
        v_country         VARCHAR2(100);
        v_score           NUMBER := 0;
        v_risk_base       NUMBER := 0;
        v_type_factor     NUMBER := 0;
        v_credit_factor   NUMBER := 0;
        v_geo_factor      NUMBER := 0;
        v_activity_factor NUMBER := 0;
        v_dormant_count   NUMBER := 0;
        v_high_bal_count  NUMBER := 0;

        CURSOR c_accounts IS
            SELECT account_type, balance, status, opened_date, last_transaction_date
            FROM   accounts
            WHERE  customer_id = p_customer_id
            AND    status IN ('ACTIVE','DORMANT');
        v_acc_rec c_accounts%ROWTYPE;
    BEGIN
        BEGIN
            SELECT risk_level, customer_type, NVL(credit_score,600), NVL(country,'US')
            INTO   v_risk_level, v_customer_type, v_credit_score, v_country
            FROM   customers WHERE customer_id = p_customer_id;
        EXCEPTION WHEN NO_DATA_FOUND THEN RETURN c_max_risk_score;
        END;

        v_risk_base := CASE v_risk_level
            WHEN 'LOW'    THEN 10
            WHEN 'MEDIUM' THEN 40
            WHEN 'HIGH'   THEN 80
            ELSE               50 END;

        v_type_factor := CASE v_customer_type
            WHEN 'RETAIL'   THEN 5
            WHEN 'PREMIUM'  THEN 3
            WHEN 'VIP'      THEN 2
            WHEN 'BUSINESS' THEN 15
            ELSE                 10 END;

        IF    v_credit_score >= 750 THEN v_credit_factor := 0;
        ELSIF v_credit_score >= 700 THEN v_credit_factor := 5;
        ELSIF v_credit_score >= 650 THEN v_credit_factor := 10;
        ELSIF v_credit_score >= 600 THEN v_credit_factor := 15;
        ELSE                              v_credit_factor := 25;
        END IF;

        IF    v_country = 'US'                          THEN v_geo_factor := 0;
        ELSIF v_country IN ('CA','GB','AU','DE','FR')   THEN v_geo_factor := 3;
        ELSE                                                 v_geo_factor := 10;
        END IF;

        OPEN c_accounts;
        LOOP
            FETCH c_accounts INTO v_acc_rec;
            EXIT WHEN c_accounts%NOTFOUND;
            IF v_acc_rec.status = 'DORMANT'          THEN v_dormant_count  := v_dormant_count  + 1; END IF;
            IF NVL(v_acc_rec.balance,0) > 100000     THEN v_high_bal_count := v_high_bal_count + 1; END IF;
        END LOOP;
        CLOSE c_accounts;

        IF v_dormant_count   > 2 THEN v_activity_factor := v_activity_factor + 10; END IF;
        IF v_high_bal_count  > 0 THEN v_activity_factor := v_activity_factor + 5;  END IF;

        v_score := LEAST(v_risk_base+v_type_factor+v_credit_factor+v_geo_factor+v_activity_factor,
                         c_max_risk_score);
        DBMS_OUTPUT.PUT_LINE('KYC Risk Score ['||p_customer_id||']: '||v_score||
            ' base='||v_risk_base||' type='||v_type_factor||
            ' credit='||v_credit_factor||' geo='||v_geo_factor||' act='||v_activity_factor);
        RETURN v_score;
    EXCEPTION WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('ERROR calc_kyc_risk: '||SQLERRM);
        RETURN c_max_risk_score;
    END calculate_kyc_risk_score;

    -- -------------------------------------------------------------------------
    FUNCTION get_days_since_verification(p_customer_id IN NUMBER) RETURN NUMBER IS
        v_updated_at TIMESTAMP;
    BEGIN
        SELECT updated_at INTO v_updated_at
        FROM   customers WHERE customer_id = p_customer_id AND kyc_status = 'VERIFIED';
        RETURN TRUNC(SYSDATE - TRUNC(v_updated_at));
    EXCEPTION WHEN NO_DATA_FOUND THEN RETURN -1;
    WHEN OTHERS THEN RETURN -999;
    END get_days_since_verification;

    -- -------------------------------------------------------------------------
    FUNCTION count_pending_kyc_customers RETURN NUMBER IS
        v_count NUMBER := 0;
    BEGIN
        SELECT COUNT(*) INTO v_count FROM customers WHERE kyc_status='PENDING' AND is_active='Y';
        RETURN NVL(v_count,0);
    END count_pending_kyc_customers;

    -- -------------------------------------------------------------------------
    PROCEDURE verify_customer_identity(
        p_customer_id IN NUMBER, p_employee_id IN NUMBER,
        p_doc_type    IN VARCHAR2, p_doc_number  IN VARCHAR2, p_result OUT VARCHAR2
    ) IS
        v_current_status VARCHAR2(20);
        v_customer_name  VARCHAR2(200);
        v_customer_type  VARCHAR2(20);
        v_risk_level     VARCHAR2(10);
        v_date_of_birth  DATE;
        v_is_active      CHAR(1);
        v_risk_score     NUMBER;
        v_employee_role  VARCHAR2(50);
        v_branch_id      NUMBER;
        v_doc_valid_flag CHAR(1) := 'Y';
        v_error_msg      VARCHAR2(500) := NULL;
        v_new_status     VARCHAR2(20);
        v_age_years      NUMBER;
    BEGIN
        BEGIN
            SELECT role, branch_id INTO v_employee_role, v_branch_id
            FROM   employees WHERE employee_id = p_employee_id AND is_active = 'Y';
        EXCEPTION WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20110,'Employee not found or inactive: '||p_employee_id);
        END;

        IF v_employee_role NOT IN ('MANAGER','ANALYST','ADMIN') THEN
            RAISE_APPLICATION_ERROR(-20111,
                'Employee role '||v_employee_role||' not authorized for KYC');
        END IF;

        BEGIN
            SELECT kyc_status, first_name||' '||last_name, customer_type,
                   risk_level, date_of_birth, is_active
            INTO   v_current_status, v_customer_name, v_customer_type,
                   v_risk_level, v_date_of_birth, v_is_active
            FROM   customers WHERE customer_id = p_customer_id;
        EXCEPTION WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20112,'Customer not found: '||p_customer_id);
        END;

        IF v_is_active = 'N' THEN
            RAISE_APPLICATION_ERROR(-20113,'Cannot verify KYC for inactive customer');
        END IF;

        v_age_years := TRUNC(MONTHS_BETWEEN(SYSDATE, v_date_of_birth)/12);
        IF v_age_years < 18 THEN
            v_doc_valid_flag := 'N';
            v_error_msg := 'Customer under 18 ('||v_age_years||' yrs)';
            GOTO set_result;
        END IF;

        IF p_doc_type NOT IN ('PASSPORT','DRIVERS_LICENSE','STATE_ID','MILITARY_ID','NATIONAL_ID') THEN
            v_doc_valid_flag := 'N';
            v_error_msg := 'Invalid document type: '||p_doc_type;
            GOTO set_result;
        END IF;

        IF p_doc_number IS NULL OR LENGTH(TRIM(p_doc_number)) < 5 THEN
            v_doc_valid_flag := 'N';
            v_error_msg := 'Invalid document number format';
            GOTO set_result;
        END IF;

        v_risk_score := calculate_kyc_risk_score(p_customer_id);

        IF    v_risk_score >= 70 THEN v_new_status := 'PENDING';  v_doc_valid_flag := 'R';
              v_error_msg := 'High risk ('||v_risk_score||') - manual review required';
        ELSIF v_risk_score >= 40 THEN v_new_status := 'VERIFIED'; v_doc_valid_flag := 'Y';
        ELSE                          v_new_status := 'VERIFIED'; v_doc_valid_flag := 'Y';
        END IF;

        <<set_result>>
        IF v_doc_valid_flag IN ('Y','R') THEN
            UPDATE customers SET kyc_status=v_new_status, updated_at=SYSTIMESTAMP
            WHERE  customer_id=p_customer_id;
            IF SQL%ROWCOUNT = 0 THEN
                RAISE_APPLICATION_ERROR(-20114,'Failed to update KYC status');
            END IF;
            p_result := v_new_status||'|'||NVL(v_error_msg,'Verification successful');
        ELSE
            UPDATE customers SET kyc_status='REJECTED', updated_at=SYSTIMESTAMP
            WHERE  customer_id=p_customer_id;
            p_result := 'REJECTED|'||v_error_msg;
        END IF;

        p_log_kyc_event(p_customer_id,'VERIFICATION_ATTEMPT',
            'Emp='||p_employee_id||'|Doc='||p_doc_type||
            '|Num='||SUBSTR(p_doc_number,1,4)||'****'||
            '|Score='||v_risk_score||'|Result='||p_result);
        DBMS_OUTPUT.PUT_LINE('KYC Done: '||v_customer_name||' => '||p_result);
    EXCEPTION WHEN OTHERS THEN
        ROLLBACK;
        p_result := 'ERROR|'||SQLERRM;
        p_log_kyc_event(p_customer_id,'VERIFICATION_ERROR',SQLERRM);
        RAISE;
    END verify_customer_identity;

    -- -------------------------------------------------------------------------
    PROCEDURE update_kyc_status(
        p_customer_id IN NUMBER, p_new_status IN VARCHAR2,
        p_reason      IN VARCHAR2, p_employee_id IN NUMBER
    ) IS
        v_old_status VARCHAR2(20);
        v_cust_name  VARCHAR2(200);
    BEGIN
        BEGIN
            SELECT kyc_status, first_name||' '||last_name
            INTO   v_old_status, v_cust_name
            FROM   customers WHERE customer_id=p_customer_id AND is_active='Y';
        EXCEPTION WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20115,'Customer not found: '||p_customer_id);
        END;

        IF p_new_status NOT IN ('PENDING','VERIFIED','REJECTED','EXPIRED') THEN
            RAISE_APPLICATION_ERROR(-20116,'Invalid KYC status: '||p_new_status);
        END IF;

        IF p_new_status IN ('REJECTED','EXPIRED') AND
           (p_reason IS NULL OR LENGTH(TRIM(p_reason)) < 5) THEN
            RAISE_APPLICATION_ERROR(-20117,'Reason required (>=5 chars) for: '||p_new_status);
        END IF;

        UPDATE customers SET kyc_status=p_new_status, updated_at=SYSTIMESTAMP
        WHERE  customer_id=p_customer_id;

        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20118,'No rows updated for customer: '||p_customer_id);
        END IF;

        INSERT INTO audit_log(table_name,record_id,action,old_values,new_values,changed_by,changed_at)
        VALUES('CUSTOMERS',p_customer_id,'UPDATE',
               'kyc_status='||v_old_status,
               'kyc_status='||p_new_status||',reason='||NVL(p_reason,'N/A')||',by_emp='||p_employee_id,
               SYS_CONTEXT('USERENV','SESSION_USER'),SYSTIMESTAMP);

        DBMS_OUTPUT.PUT_LINE('KYC Updated: '||v_cust_name||
            ' ['||v_old_status||' -> '||p_new_status||'] Reason: '||NVL(p_reason,'N/A'));
    EXCEPTION WHEN OTHERS THEN ROLLBACK; RAISE;
    END update_kyc_status;

    -- -------------------------------------------------------------------------
    PROCEDURE expire_overdue_kyc_records(p_expired_count OUT NUMBER) IS
        v_customer_id  NUMBER;
        v_full_name    VARCHAR2(200);
        v_updated_at   TIMESTAMP;
        v_months_old   NUMBER;

        CURSOR c_verified IS
            SELECT customer_id, first_name||' '||last_name AS full_name, updated_at
            FROM   customers
            WHERE  kyc_status = 'VERIFIED' AND is_active = 'Y'
            ORDER BY updated_at ASC;
    BEGIN
        p_expired_count := 0;
        DBMS_OUTPUT.PUT_LINE('KYC Expiry Job Start: '||TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS'));
        DBMS_OUTPUT.PUT_LINE('Threshold: '||c_kyc_expiry_months||' months');

        OPEN c_verified;
        LOOP
            FETCH c_verified INTO v_customer_id, v_full_name, v_updated_at;
            EXIT WHEN c_verified%NOTFOUND;
            v_months_old := MONTHS_BETWEEN(SYSDATE, TRUNC(v_updated_at));
            IF v_months_old > c_kyc_expiry_months THEN
                BEGIN
                    UPDATE customers SET kyc_status='EXPIRED', updated_at=SYSTIMESTAMP
                    WHERE  customer_id=v_customer_id;
                    p_log_kyc_event(v_customer_id,'KYC_EXPIRED',
                        'Months old='||ROUND(v_months_old,1)||' Threshold='||c_kyc_expiry_months);
                    p_expired_count := p_expired_count + 1;
                    DBMS_OUTPUT.PUT_LINE('Expired: '||v_full_name||
                        ' (ID='||v_customer_id||') '||ROUND(v_months_old,1)||'mo old');
                EXCEPTION WHEN OTHERS THEN
                    DBMS_OUTPUT.PUT_LINE('ERR expiring '||v_customer_id||': '||SQLERRM);
                END;
            END IF;
        END LOOP;
        CLOSE c_verified;
        DBMS_OUTPUT.PUT_LINE('KYC Expiry Done. Expired='||p_expired_count);
    EXCEPTION WHEN OTHERS THEN
        IF c_verified%ISOPEN THEN CLOSE c_verified; END IF;
        RAISE;
    END expire_overdue_kyc_records;

    -- -------------------------------------------------------------------------
    PROCEDURE run_kyc_batch_recheck(
        p_branch_id     IN  NUMBER DEFAULT NULL,
        p_checked_count OUT NUMBER,
        p_updated_count OUT NUMBER,
        p_flagged_count OUT NUMBER
    ) IS
        v_risk_score   NUMBER;
        v_current_risk VARCHAR2(10);
        v_new_risk     VARCHAR2(10);
        v_customer_id  NUMBER;
        v_cust_code    VARCHAR2(20);
        v_cust_type    VARCHAR2(20);

        CURSOR c_customers IS
            SELECT DISTINCT c.customer_id, c.customer_code, c.risk_level, c.customer_type
            FROM   customers c
            JOIN   accounts  a ON c.customer_id = a.customer_id
            WHERE  c.is_active  = 'Y'
            AND    c.kyc_status = 'VERIFIED'
            AND    (p_branch_id IS NULL OR a.branch_id = p_branch_id)
            ORDER  BY c.customer_id;
    BEGIN
        p_checked_count := 0; p_updated_count := 0; p_flagged_count := 0;
        DBMS_OUTPUT.PUT_LINE('===== KYC Batch Recheck Start '||
            TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS')||' =====');

        OPEN c_customers;
        LOOP
            FETCH c_customers INTO v_customer_id, v_cust_code, v_current_risk, v_cust_type;
            EXIT WHEN c_customers%NOTFOUND;
            p_checked_count := p_checked_count + 1;
            BEGIN
                v_risk_score := calculate_kyc_risk_score(v_customer_id);
                v_new_risk   := CASE WHEN v_risk_score >= 70 THEN 'HIGH'
                                     WHEN v_risk_score >= 40 THEN 'MEDIUM'
                                     ELSE                        'LOW' END;
                IF v_new_risk != v_current_risk THEN
                    UPDATE customers SET risk_level=v_new_risk, updated_at=SYSTIMESTAMP
                    WHERE  customer_id=v_customer_id;
                    p_updated_count := p_updated_count + 1;
                    DBMS_OUTPUT.PUT_LINE('Risk Changed: '||v_cust_code||
                        ' ['||v_current_risk||'->'||v_new_risk||'] score='||v_risk_score);
                END IF;
                IF v_risk_score >= 70 THEN
                    p_flagged_count := p_flagged_count + 1;
                    p_log_kyc_event(v_customer_id,'HIGH_RISK_FLAG',
                        'score='||v_risk_score||' type='||v_cust_type||
                        ' prev_risk='||v_current_risk||' new_risk='||v_new_risk);
                END IF;
            EXCEPTION WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('ERR recheck '||v_customer_id||': '||SQLERRM);
            END;
        END LOOP;
        CLOSE c_customers;
        DBMS_OUTPUT.PUT_LINE('KYC Recheck Done: checked='||p_checked_count||
            ' updated='||p_updated_count||' flagged='||p_flagged_count);
    EXCEPTION WHEN OTHERS THEN
        IF c_customers%ISOPEN THEN CLOSE c_customers; END IF;
        RAISE;
    END run_kyc_batch_recheck;

    -- -------------------------------------------------------------------------
    PROCEDURE generate_kyc_compliance_report(
        p_as_of_date IN DATE DEFAULT SYSDATE, p_report OUT SYS_REFCURSOR
    ) IS
    BEGIN
        OPEN p_report FOR
            SELECT
                c.kyc_status,
                c.risk_level,
                c.customer_type,
                COUNT(*)                                                   AS customer_count,
                COUNT(CASE WHEN c.is_active='Y' THEN 1 END)               AS active_count,
                ROUND(AVG(MONTHS_BETWEEN(p_as_of_date,TRUNC(c.updated_at))),1)
                                                                           AS avg_months_since_update,
                COUNT(CASE WHEN MONTHS_BETWEEN(p_as_of_date,TRUNC(c.updated_at))
                                > c_kyc_expiry_months THEN 1 END)         AS near_expiry_count,
                ROUND(COUNT(CASE WHEN MONTHS_BETWEEN(p_as_of_date,TRUNC(c.updated_at))
                                      > c_kyc_expiry_months THEN 1 END) /
                      NULLIF(COUNT(*),0) * 100, 2)                        AS expiry_rate_pct,
                p_as_of_date                                               AS report_date
            FROM   customers c
            WHERE  c.is_active = 'Y'
            GROUP  BY c.kyc_status, c.risk_level, c.customer_type
            ORDER  BY DECODE(c.risk_level,'HIGH',1,'MEDIUM',2,'LOW',3,4),
                      DECODE(c.kyc_status,'REJECTED',1,'EXPIRED',2,'PENDING',3,'VERIFIED',4,5);
    END generate_kyc_compliance_report;

END pkg_kyc_verification;
/
SHOW ERRORS PACKAGE BODY pkg_kyc_verification;

-- =============================================================================
-- PACKAGE 2: PKG_AML_COMPLIANCE
-- Anti-Money Laundering Compliance Package
-- =============================================================================

CREATE OR REPLACE PACKAGE pkg_aml_compliance AS
    c_ctr_threshold       CONSTANT NUMBER := 10000;
    c_structuring_low     CONSTANT NUMBER := 8000;
    c_rapid_move_threshold CONSTANT NUMBER := 5000;
    c_max_daily_cash      CONSTANT NUMBER := 25000;
    c_velocity_window_hrs CONSTANT NUMBER := 24;

    e_ctr_required       EXCEPTION;
    e_structuring_alert  EXCEPTION;
    e_watchlist_hit      EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_ctr_required,      -20200);
    PRAGMA EXCEPTION_INIT(e_structuring_alert, -20201);
    PRAGMA EXCEPTION_INIT(e_watchlist_hit,     -20202);

    FUNCTION  calculate_aml_risk_score(p_customer_id IN NUMBER) RETURN NUMBER;
    FUNCTION  get_customer_30day_volume(p_customer_id IN NUMBER) RETURN NUMBER;
    FUNCTION  get_customer_daily_cash(p_customer_id IN NUMBER, p_date IN DATE DEFAULT SYSDATE) RETURN NUMBER;
    FUNCTION  count_open_aml_alerts(p_customer_id IN NUMBER) RETURN NUMBER;
    FUNCTION  is_structuring_pattern(p_customer_id IN NUMBER, p_date IN DATE DEFAULT SYSDATE) RETURN BOOLEAN;

    PROCEDURE screen_transaction_aml(
        p_transaction_id IN NUMBER, p_account_id IN NUMBER,
        p_customer_id IN NUMBER, p_amount IN NUMBER,
        p_txn_type IN VARCHAR2, p_alert_raised OUT BOOLEAN, p_alert_id OUT NUMBER);
    PROCEDURE run_daily_aml_scan(
        p_scan_date IN DATE DEFAULT SYSDATE,
        p_scanned_count OUT NUMBER, p_alerts_raised OUT NUMBER);
    PROCEDURE resolve_aml_alert(
        p_alert_id IN NUMBER, p_resolution IN VARCHAR2,
        p_notes IN VARCHAR2, p_employee_id IN NUMBER);
    PROCEDURE generate_aml_summary_report(
        p_from_date IN DATE, p_to_date IN DATE, p_report OUT SYS_REFCURSOR);
    PROCEDURE escalate_high_risk_alerts(
        p_as_of_date IN DATE DEFAULT SYSDATE, p_escalated_count OUT NUMBER);
END pkg_aml_compliance;
/

CREATE OR REPLACE PACKAGE BODY pkg_aml_compliance AS

    PROCEDURE p_raise_alert(
        p_account_id IN NUMBER, p_customer_id IN NUMBER,
        p_txn_id IN NUMBER, p_type IN VARCHAR2,
        p_severity IN VARCHAR2, p_desc IN VARCHAR2, p_alert_id OUT NUMBER
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO fraud_alerts(account_id,customer_id,transaction_id,
                                  alert_type,severity,description,status,created_at)
        VALUES(p_account_id,p_customer_id,p_txn_id,p_type,p_severity,SUBSTR(p_desc,1,1000),'OPEN',SYSTIMESTAMP)
        RETURNING alert_id INTO p_alert_id;
        COMMIT;
    EXCEPTION WHEN OTHERS THEN p_alert_id := -1;
    END p_raise_alert;

    -- -------------------------------------------------------------------------
    FUNCTION calculate_aml_risk_score(p_customer_id IN NUMBER) RETURN NUMBER IS
        v_risk_level     VARCHAR2(10);
        v_customer_type  VARCHAR2(20);
        v_open_alerts    NUMBER := 0;
        v_vol_30day      NUMBER := 0;
        v_score          NUMBER := 0;
        v_base           NUMBER := 0;
        v_vol_factor     NUMBER := 0;
        v_alert_factor   NUMBER := 0;
        v_type_factor    NUMBER := 0;
    BEGIN
        BEGIN
            SELECT risk_level, customer_type INTO v_risk_level, v_customer_type
            FROM   customers WHERE customer_id = p_customer_id AND is_active = 'Y';
        EXCEPTION WHEN NO_DATA_FOUND THEN RETURN 100;
        END;

        v_base := CASE v_risk_level WHEN 'HIGH' THEN 60 WHEN 'MEDIUM' THEN 30 ELSE 10 END;
        v_type_factor := CASE v_customer_type
            WHEN 'BUSINESS' THEN 20 WHEN 'VIP' THEN 5 WHEN 'PREMIUM' THEN 5
            WHEN 'RETAIL'   THEN 10 ELSE 15 END;

        v_vol_30day  := get_customer_30day_volume(p_customer_id);
        v_open_alerts := count_open_aml_alerts(p_customer_id);

        IF    v_vol_30day > 500000 THEN v_vol_factor := 25;
        ELSIF v_vol_30day > 100000 THEN v_vol_factor := 15;
        ELSIF v_vol_30day > 50000  THEN v_vol_factor := 10;
        ELSIF v_vol_30day > 10000  THEN v_vol_factor := 5;
        ELSE                            v_vol_factor := 0; END IF;

        IF    v_open_alerts >= 5  THEN v_alert_factor := 30;
        ELSIF v_open_alerts >= 3  THEN v_alert_factor := 20;
        ELSIF v_open_alerts >= 1  THEN v_alert_factor := 10;
        ELSE                           v_alert_factor := 0; END IF;

        v_score := LEAST(v_base + v_type_factor + v_vol_factor + v_alert_factor, 100);
        DBMS_OUTPUT.PUT_LINE('AML Score ['||p_customer_id||']: '||v_score||
            ' base='||v_base||' vol='||v_vol_factor||' alerts='||v_alert_factor);
        RETURN v_score;
    EXCEPTION WHEN OTHERS THEN RETURN 100;
    END calculate_aml_risk_score;

    -- -------------------------------------------------------------------------
    FUNCTION get_customer_30day_volume(p_customer_id IN NUMBER) RETURN NUMBER IS
        v_total NUMBER := 0;
    BEGIN
        SELECT NVL(SUM(t.amount),0)
        INTO   v_total
        FROM   transactions t
        JOIN   accounts a ON t.account_id = a.account_id
        WHERE  a.customer_id      = p_customer_id
        AND    t.transaction_date >= SYSDATE - 30
        AND    t.status           = 'COMPLETED';
        RETURN v_total;
    EXCEPTION WHEN OTHERS THEN RETURN 0;
    END get_customer_30day_volume;

    -- -------------------------------------------------------------------------
    FUNCTION get_customer_daily_cash(p_customer_id IN NUMBER, p_date IN DATE DEFAULT SYSDATE)
    RETURN NUMBER IS
        v_total NUMBER := 0;
    BEGIN
        SELECT NVL(SUM(t.amount),0)
        INTO   v_total
        FROM   transactions t
        JOIN   accounts a ON t.account_id = a.account_id
        WHERE  a.customer_id           = p_customer_id
        AND    t.transaction_type      IN ('DEPOSIT','WITHDRAWAL')
        AND    TRUNC(t.transaction_date) = TRUNC(p_date)
        AND    t.channel               IN ('BRANCH','ATM')
        AND    t.status                = 'COMPLETED';
        RETURN v_total;
    EXCEPTION WHEN OTHERS THEN RETURN 0;
    END get_customer_daily_cash;

    -- -------------------------------------------------------------------------
    FUNCTION count_open_aml_alerts(p_customer_id IN NUMBER) RETURN NUMBER IS
        v_count NUMBER := 0;
    BEGIN
        SELECT COUNT(*) INTO v_count FROM fraud_alerts
        WHERE  customer_id = p_customer_id AND status = 'OPEN';
        RETURN NVL(v_count,0);
    EXCEPTION WHEN OTHERS THEN RETURN 0;
    END count_open_aml_alerts;

    -- -------------------------------------------------------------------------
    FUNCTION is_structuring_pattern(p_customer_id IN NUMBER, p_date IN DATE DEFAULT SYSDATE)
    RETURN BOOLEAN IS
        v_txn_count   NUMBER := 0;
        v_max_single  NUMBER := 0;
        v_daily_total NUMBER := 0;
    BEGIN
        SELECT COUNT(*), NVL(MAX(t.amount),0), NVL(SUM(t.amount),0)
        INTO   v_txn_count, v_max_single, v_daily_total
        FROM   transactions t
        JOIN   accounts a ON t.account_id = a.account_id
        WHERE  a.customer_id             = p_customer_id
        AND    t.transaction_type        = 'DEPOSIT'
        AND    TRUNC(t.transaction_date) = TRUNC(p_date)
        AND    t.status                  = 'COMPLETED';

        -- Structuring: Multiple transactions, none crossing $10k, total > $8k
        IF v_txn_count >= 2 AND v_max_single < c_ctr_threshold
           AND v_daily_total >= c_structuring_low THEN
            RETURN TRUE;
        END IF;
        RETURN FALSE;
    EXCEPTION WHEN OTHERS THEN RETURN FALSE;
    END is_structuring_pattern;

    -- -------------------------------------------------------------------------
    PROCEDURE screen_transaction_aml(
        p_transaction_id IN NUMBER, p_account_id IN NUMBER,
        p_customer_id    IN NUMBER, p_amount     IN NUMBER,
        p_txn_type       IN VARCHAR2, p_alert_raised OUT BOOLEAN, p_alert_id OUT NUMBER
    ) IS
        v_daily_cash      NUMBER;
        v_alert_id_tmp    NUMBER;
        v_is_structuring  BOOLEAN;
        v_alert_raised    BOOLEAN := FALSE;
        v_combined_id     NUMBER  := -1;
    BEGIN
        p_alert_raised := FALSE;
        p_alert_id     := NULL;

        -- Rule 1: CTR Threshold
        IF p_txn_type IN ('DEPOSIT','WITHDRAWAL') AND p_amount >= c_ctr_threshold THEN
            p_raise_alert(p_account_id, p_customer_id, p_transaction_id,
                'CTR_REQUIRED',
                CASE WHEN p_amount >= 50000 THEN 'HIGH' ELSE 'MEDIUM' END,
                'Cash transaction '||p_amount||' >= CTR threshold '||c_ctr_threshold,
                v_alert_id_tmp);
            p_alert_raised := TRUE;
            p_alert_id     := v_alert_id_tmp;
            DBMS_OUTPUT.PUT_LINE('CTR Alert raised for TXN#'||p_transaction_id||' amt='||p_amount);
        END IF;

        -- Rule 2: Structuring detection
        IF p_txn_type = 'DEPOSIT' THEN
            v_is_structuring := is_structuring_pattern(p_customer_id, SYSDATE);
            IF v_is_structuring THEN
                p_raise_alert(p_account_id, p_customer_id, p_transaction_id,
                    'STRUCTURING_POSSIBLE', 'HIGH',
                    'Possible structuring detected. Daily deposits near $10k threshold.',
                    v_alert_id_tmp);
                p_alert_raised := TRUE;
                IF p_alert_id IS NULL THEN p_alert_id := v_alert_id_tmp; END IF;
                DBMS_OUTPUT.PUT_LINE('Structuring alert raised for customer '||p_customer_id);
            END IF;
        END IF;

        -- Rule 3: Daily cash limit
        v_daily_cash := get_customer_daily_cash(p_customer_id, SYSDATE);
        IF v_daily_cash + p_amount > c_max_daily_cash THEN
            p_raise_alert(p_account_id, p_customer_id, p_transaction_id,
                'DAILY_CASH_LIMIT_BREACH', 'HIGH',
                'Daily cash total would reach '||(v_daily_cash+p_amount)||
                ' exceeding limit '||c_max_daily_cash,
                v_alert_id_tmp);
            p_alert_raised := TRUE;
            IF p_alert_id IS NULL THEN p_alert_id := v_alert_id_tmp; END IF;
            DBMS_OUTPUT.PUT_LINE('Daily cash limit breach: cust='||p_customer_id||
                ' total='||(v_daily_cash+p_amount));
        END IF;

    EXCEPTION WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('AML screen error TXN#'||p_transaction_id||': '||SQLERRM);
        p_alert_raised := FALSE;
    END screen_transaction_aml;

    -- -------------------------------------------------------------------------
    PROCEDURE run_daily_aml_scan(
        p_scan_date     IN  DATE DEFAULT SYSDATE,
        p_scanned_count OUT NUMBER,
        p_alerts_raised OUT NUMBER
    ) IS
        v_cust_id       NUMBER;
        v_cust_code     VARCHAR2(20);
        v_risk_score    NUMBER;
        v_alert_id      NUMBER;
        v_open_alerts   NUMBER;
        v_vol           NUMBER;
        v_flag          BOOLEAN;

        CURSOR c_active_customers IS
            SELECT DISTINCT c.customer_id, c.customer_code
            FROM   customers c
            JOIN   accounts  a ON c.customer_id = a.customer_id
            WHERE  c.is_active = 'Y'
            AND    a.status    = 'ACTIVE'
            ORDER  BY c.customer_id;
    BEGIN
        p_scanned_count := 0;
        p_alerts_raised := 0;
        DBMS_OUTPUT.PUT_LINE('Daily AML Scan Start: '||TO_CHAR(p_scan_date,'YYYY-MM-DD'));

        OPEN c_active_customers;
        LOOP
            FETCH c_active_customers INTO v_cust_id, v_cust_code;
            EXIT WHEN c_active_customers%NOTFOUND;
            p_scanned_count := p_scanned_count + 1;
            BEGIN
                v_risk_score  := calculate_aml_risk_score(v_cust_id);
                v_open_alerts := count_open_aml_alerts(v_cust_id);
                v_vol         := get_customer_30day_volume(v_cust_id);

                -- Flag customers with extreme risk
                IF v_risk_score >= 85 AND v_open_alerts = 0 THEN
                    DECLARE v_dummy_acct NUMBER;
                    BEGIN
                        SELECT MIN(account_id) INTO v_dummy_acct
                        FROM   accounts WHERE customer_id=v_cust_id AND status='ACTIVE';
                        p_raise_alert(v_dummy_acct, v_cust_id, NULL,
                            'HIGH_RISK_CUSTOMER','HIGH',
                            'AML daily scan: risk score='||v_risk_score||
                            ' 30day_vol='||v_vol||' cust='||v_cust_code,
                            v_alert_id);
                        p_alerts_raised := p_alerts_raised + 1;
                        DBMS_OUTPUT.PUT_LINE('AML flag: '||v_cust_code||' score='||v_risk_score);
                    EXCEPTION WHEN OTHERS THEN
                        DBMS_OUTPUT.PUT_LINE('ERR flagging '||v_cust_id||': '||SQLERRM);
                    END;
                END IF;

                -- Check structuring
                v_flag := is_structuring_pattern(v_cust_id, p_scan_date);
                IF v_flag THEN
                    DECLARE v_dummy_acct2 NUMBER;
                    BEGIN
                        SELECT MIN(account_id) INTO v_dummy_acct2
                        FROM   accounts WHERE customer_id=v_cust_id AND status='ACTIVE';
                        p_raise_alert(v_dummy_acct2, v_cust_id, NULL,
                            'STRUCTURING_DAILY_SCAN','HIGH',
                            'Daily scan structuring pattern: cust='||v_cust_code||
                            ' date='||TO_CHAR(p_scan_date,'YYYY-MM-DD'),
                            v_alert_id);
                        p_alerts_raised := p_alerts_raised + 1;
                    EXCEPTION WHEN OTHERS THEN NULL;
                    END;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('ERR scanning '||v_cust_id||': '||SQLERRM);
            END;
        END LOOP;
        CLOSE c_active_customers;
        DBMS_OUTPUT.PUT_LINE('AML Scan Done: scanned='||p_scanned_count||' alerts='||p_alerts_raised);
    EXCEPTION WHEN OTHERS THEN
        IF c_active_customers%ISOPEN THEN CLOSE c_active_customers; END IF;
        RAISE;
    END run_daily_aml_scan;

    -- -------------------------------------------------------------------------
    PROCEDURE resolve_aml_alert(
        p_alert_id IN NUMBER, p_resolution IN VARCHAR2,
        p_notes IN VARCHAR2, p_employee_id IN NUMBER
    ) IS
        v_current_status VARCHAR2(20);
        v_account_id     NUMBER;
        v_customer_id    NUMBER;
    BEGIN
        BEGIN
            SELECT status, account_id, customer_id
            INTO   v_current_status, v_account_id, v_customer_id
            FROM   fraud_alerts WHERE alert_id = p_alert_id;
        EXCEPTION WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20210,'Alert not found: '||p_alert_id);
        END;

        IF v_current_status = 'RESOLVED' THEN
            RAISE_APPLICATION_ERROR(-20211,'Alert already resolved: '||p_alert_id);
        END IF;

        IF p_resolution NOT IN ('RESOLVED','FALSE_POSITIVE','INVESTIGATING') THEN
            RAISE_APPLICATION_ERROR(-20212,'Invalid resolution: '||p_resolution);
        END IF;

        UPDATE fraud_alerts
        SET    status      = p_resolution,
               description = description || ' | RESOLUTION: ' || NVL(p_notes,'N/A') ||
                             ' | By: ' || p_employee_id,
               resolved_by = p_employee_id,
               resolved_at = SYSTIMESTAMP
        WHERE  alert_id = p_alert_id;

        INSERT INTO audit_log(table_name,record_id,action,old_values,new_values,changed_by,changed_at)
        VALUES('FRAUD_ALERTS',p_alert_id,'UPDATE',
               'status='||v_current_status,
               'status='||p_resolution||',notes='||SUBSTR(NVL(p_notes,''),1,200),
               SYS_CONTEXT('USERENV','SESSION_USER'),SYSTIMESTAMP);

        DBMS_OUTPUT.PUT_LINE('Alert #'||p_alert_id||' resolved as '||p_resolution||
            ' by emp='||p_employee_id);
    EXCEPTION WHEN OTHERS THEN ROLLBACK; RAISE;
    END resolve_aml_alert;

    -- -------------------------------------------------------------------------
    PROCEDURE generate_aml_summary_report(
        p_from_date IN DATE, p_to_date IN DATE, p_report OUT SYS_REFCURSOR
    ) IS
    BEGIN
        OPEN p_report FOR
            SELECT
                fa.alert_type,
                fa.severity,
                COUNT(*)                                           AS total_alerts,
                COUNT(CASE WHEN fa.status='OPEN' THEN 1 END)      AS open_alerts,
                COUNT(CASE WHEN fa.status='RESOLVED' THEN 1 END)  AS resolved_alerts,
                COUNT(CASE WHEN fa.status='FALSE_POSITIVE' THEN 1 END) AS false_positives,
                ROUND(COUNT(CASE WHEN fa.status='FALSE_POSITIVE' THEN 1 END)/
                      NULLIF(COUNT(*),0)*100,2)                    AS false_positive_pct,
                COUNT(DISTINCT fa.customer_id)                    AS unique_customers,
                COUNT(DISTINCT fa.account_id)                     AS unique_accounts,
                MIN(fa.created_at)                                AS first_alert_date,
                MAX(fa.created_at)                                AS last_alert_date
            FROM   fraud_alerts fa
            WHERE  TRUNC(fa.created_at) BETWEEN p_from_date AND p_to_date
            GROUP  BY fa.alert_type, fa.severity
            ORDER  BY DECODE(fa.severity,'CRITICAL',1,'HIGH',2,'MEDIUM',3,'LOW',4,5),
                      total_alerts DESC;
    END generate_aml_summary_report;

    -- -------------------------------------------------------------------------
    PROCEDURE escalate_high_risk_alerts(
        p_as_of_date IN DATE DEFAULT SYSDATE, p_escalated_count OUT NUMBER
    ) IS
        v_alert_id    NUMBER;
        v_created_at  TIMESTAMP;
        v_hours_open  NUMBER;
        v_acct_id     NUMBER;
        v_cust_id     NUMBER;

        CURSOR c_open_high IS
            SELECT alert_id, created_at, account_id, customer_id
            FROM   fraud_alerts
            WHERE  status   = 'OPEN'
            AND    severity IN ('HIGH','CRITICAL')
            ORDER  BY created_at ASC;
    BEGIN
        p_escalated_count := 0;
        DBMS_OUTPUT.PUT_LINE('Alert Escalation Run: '||TO_CHAR(p_as_of_date,'YYYY-MM-DD'));

        OPEN c_open_high;
        LOOP
            FETCH c_open_high INTO v_alert_id, v_created_at, v_acct_id, v_cust_id;
            EXIT WHEN c_open_high%NOTFOUND;
            v_hours_open := (SYSDATE - TRUNC(v_created_at)) * 24;

            IF v_hours_open >= 48 THEN
                BEGIN
                    UPDATE fraud_alerts
                    SET    status      = 'INVESTIGATING',
                           description = description || ' | ESCALATED after '||
                                         ROUND(v_hours_open,1)||' hours open'
                    WHERE  alert_id = v_alert_id;

                    INSERT INTO audit_log(table_name,record_id,action,new_values,changed_by,changed_at)
                    VALUES('FRAUD_ALERTS',v_alert_id,'UPDATE',
                           'AUTO_ESCALATED|hours_open='||ROUND(v_hours_open,1),
                           'SYSTEM',SYSTIMESTAMP);

                    p_escalated_count := p_escalated_count + 1;
                    DBMS_OUTPUT.PUT_LINE('Escalated alert #'||v_alert_id||
                        ' (open '||ROUND(v_hours_open,1)||'h)');
                EXCEPTION WHEN OTHERS THEN
                    DBMS_OUTPUT.PUT_LINE('ERR escalating #'||v_alert_id||': '||SQLERRM);
                END;
            END IF;
        END LOOP;
        CLOSE c_open_high;
        DBMS_OUTPUT.PUT_LINE('Escalation Done: '||p_escalated_count||' alerts escalated');
    EXCEPTION WHEN OTHERS THEN
        IF c_open_high%ISOPEN THEN CLOSE c_open_high; END IF;
        RAISE;
    END escalate_high_risk_alerts;

END pkg_aml_compliance;
/
SHOW ERRORS PACKAGE BODY pkg_aml_compliance;

-- =============================================================================
-- PACKAGE 3: PKG_CARD_OPERATIONS
-- Card Issuance and Operations Management Package
-- =============================================================================

CREATE OR REPLACE PACKAGE pkg_card_operations AS
    c_default_daily_limit   CONSTANT NUMBER := 5000;
    c_default_credit_limit  CONSTANT NUMBER := 10000;
    c_max_card_per_account  CONSTANT NUMBER := 3;
    c_expiry_years          CONSTANT NUMBER := 4;

    e_card_expired          EXCEPTION;
    e_card_blocked          EXCEPTION;
    e_limit_exceeded        EXCEPTION;
    e_max_cards_reached     EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_card_expired,      -20300);
    PRAGMA EXCEPTION_INIT(e_card_blocked,      -20301);
    PRAGMA EXCEPTION_INIT(e_limit_exceeded,    -20302);
    PRAGMA EXCEPTION_INIT(e_max_cards_reached, -20303);

    FUNCTION  is_card_valid(p_card_id IN NUMBER) RETURN BOOLEAN;
    FUNCTION  get_card_status(p_card_id IN NUMBER) RETURN VARCHAR2;
    FUNCTION  get_available_credit(p_card_id IN NUMBER) RETURN NUMBER;
    FUNCTION  count_active_cards(p_account_id IN NUMBER) RETURN NUMBER;
    FUNCTION  get_card_daily_spend(p_card_id IN NUMBER, p_date IN DATE DEFAULT SYSDATE) RETURN NUMBER;
    FUNCTION  days_until_expiry(p_card_id IN NUMBER) RETURN NUMBER;

    PROCEDURE issue_card(
        p_account_id IN NUMBER, p_customer_id IN NUMBER,
        p_card_type  IN VARCHAR2, p_card_network IN VARCHAR2 DEFAULT 'VISA',
        p_credit_limit IN NUMBER DEFAULT NULL,
        p_card_id OUT NUMBER, p_masked_number OUT VARCHAR2);
    PROCEDURE activate_card(p_card_id IN NUMBER, p_employee_id IN NUMBER);
    PROCEDURE block_card(
        p_card_id IN NUMBER, p_reason IN VARCHAR2, p_employee_id IN NUMBER);
    PROCEDURE unblock_card(p_card_id IN NUMBER, p_employee_id IN NUMBER);
    PROCEDURE update_card_limits(
        p_card_id IN NUMBER, p_new_daily_limit IN NUMBER,
        p_new_credit_limit IN NUMBER DEFAULT NULL, p_employee_id IN NUMBER);
    PROCEDURE expire_old_cards(p_as_of_date IN DATE DEFAULT SYSDATE, p_expired_count OUT NUMBER);
    PROCEDURE renew_expiring_cards(
        p_days_before_expiry IN NUMBER DEFAULT 60,
        p_renewed_count OUT NUMBER, p_failed_count OUT NUMBER);
    PROCEDURE generate_card_activity_report(
        p_from_date IN DATE, p_to_date IN DATE, p_report OUT SYS_REFCURSOR);
END pkg_card_operations;
/

CREATE OR REPLACE PACKAGE BODY pkg_card_operations AS

    PROCEDURE p_card_audit(p_card_id IN NUMBER, p_action IN VARCHAR2,
                           p_old IN VARCHAR2, p_new IN VARCHAR2) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO audit_log(table_name,record_id,action,old_values,new_values,changed_by,changed_at)
        VALUES('CARDS',p_card_id,p_action,p_old,p_new,
               SYS_CONTEXT('USERENV','SESSION_USER'),SYSTIMESTAMP);
        COMMIT;
    EXCEPTION WHEN OTHERS THEN NULL;
    END p_card_audit;

    -- -------------------------------------------------------------------------
    FUNCTION is_card_valid(p_card_id IN NUMBER) RETURN BOOLEAN IS
        v_status     VARCHAR2(20);
        v_expiry     DATE;
    BEGIN
        SELECT status, expiry_date INTO v_status, v_expiry
        FROM   cards WHERE card_id = p_card_id;
        IF v_status != 'ACTIVE'  THEN RETURN FALSE; END IF;
        IF v_expiry < SYSDATE    THEN RETURN FALSE; END IF;
        RETURN TRUE;
    EXCEPTION WHEN NO_DATA_FOUND THEN RETURN FALSE;
    END is_card_valid;

    -- -------------------------------------------------------------------------
    FUNCTION get_card_status(p_card_id IN NUMBER) RETURN VARCHAR2 IS
        v_status VARCHAR2(20);
    BEGIN
        SELECT status INTO v_status FROM cards WHERE card_id = p_card_id;
        RETURN v_status;
    EXCEPTION WHEN NO_DATA_FOUND THEN RETURN 'NOT_FOUND';
    END get_card_status;

    -- -------------------------------------------------------------------------
    FUNCTION get_available_credit(p_card_id IN NUMBER) RETURN NUMBER IS
        v_avail NUMBER;
        v_type  VARCHAR2(20);
    BEGIN
        SELECT NVL(available_credit,0), card_type INTO v_avail, v_type
        FROM   cards WHERE card_id = p_card_id;
        IF v_type != 'CREDIT' THEN RETURN -1; END IF;
        RETURN v_avail;
    EXCEPTION WHEN NO_DATA_FOUND THEN RETURN -1;
    END get_available_credit;

    -- -------------------------------------------------------------------------
    FUNCTION count_active_cards(p_account_id IN NUMBER) RETURN NUMBER IS
        v_count NUMBER := 0;
    BEGIN
        SELECT COUNT(*) INTO v_count FROM cards
        WHERE  account_id = p_account_id AND status = 'ACTIVE';
        RETURN NVL(v_count,0);
    END count_active_cards;

    -- -------------------------------------------------------------------------
    FUNCTION get_card_daily_spend(p_card_id IN NUMBER, p_date IN DATE DEFAULT SYSDATE)
    RETURN NUMBER IS
        v_account_id NUMBER;
        v_total      NUMBER := 0;
    BEGIN
        SELECT account_id INTO v_account_id FROM cards WHERE card_id = p_card_id;
        SELECT NVL(SUM(t.amount),0)
        INTO   v_total
        FROM   transactions t
        WHERE  t.account_id             = v_account_id
        AND    t.transaction_type       IN ('WITHDRAWAL','PAYMENT','TRANSFER_OUT')
        AND    TRUNC(t.transaction_date) = TRUNC(p_date)
        AND    t.status                  = 'COMPLETED';
        RETURN v_total;
    EXCEPTION WHEN NO_DATA_FOUND THEN RETURN 0;
    WHEN OTHERS THEN RETURN 0;
    END get_card_daily_spend;

    -- -------------------------------------------------------------------------
    FUNCTION days_until_expiry(p_card_id IN NUMBER) RETURN NUMBER IS
        v_expiry DATE;
    BEGIN
        SELECT expiry_date INTO v_expiry FROM cards WHERE card_id = p_card_id;
        RETURN TRUNC(v_expiry - SYSDATE);
    EXCEPTION WHEN NO_DATA_FOUND THEN RETURN -9999;
    END days_until_expiry;

    -- -------------------------------------------------------------------------
    PROCEDURE issue_card(
        p_account_id    IN  NUMBER,
        p_customer_id   IN  NUMBER,
        p_card_type     IN  VARCHAR2,
        p_card_network  IN  VARCHAR2 DEFAULT 'VISA',
        p_credit_limit  IN  NUMBER DEFAULT NULL,
        p_card_id       OUT NUMBER,
        p_masked_number OUT VARCHAR2
    ) IS
        v_active_count   NUMBER;
        v_account_status VARCHAR2(20);
        v_cust_status    VARCHAR2(20);
        v_last_four      VARCHAR2(4);
        v_card_hash      VARCHAR2(64);
        v_expiry         DATE;
        v_credit_lim     NUMBER;
        v_daily_lim      NUMBER := c_default_daily_limit;
        v_raw_number     VARCHAR2(16);
        v_seq            NUMBER;
    BEGIN
        -- Validate account
        BEGIN
            SELECT status INTO v_account_status FROM accounts
            WHERE  account_id = p_account_id AND customer_id = p_customer_id;
        EXCEPTION WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20310,
                'Account '||p_account_id||' not found or does not belong to customer '||p_customer_id);
        END;

        IF v_account_status != 'ACTIVE' THEN
            RAISE_APPLICATION_ERROR(-20311,'Account is not active: '||v_account_status);
        END IF;

        -- Check customer KYC
        BEGIN
            SELECT kyc_status INTO v_cust_status FROM customers WHERE customer_id=p_customer_id;
        EXCEPTION WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20312,'Customer not found: '||p_customer_id);
        END;

        IF v_cust_status != 'VERIFIED' THEN
            RAISE_APPLICATION_ERROR(-20313,'Customer KYC not verified: '||v_cust_status);
        END IF;

        -- Check card count limit
        v_active_count := count_active_cards(p_account_id);
        IF v_active_count >= c_max_card_per_account THEN
            RAISE_APPLICATION_ERROR(-20303,
                'Maximum '||c_max_card_per_account||' active cards allowed per account');
        END IF;

        -- Validate card type
        IF p_card_type NOT IN ('DEBIT','CREDIT','PREPAID') THEN
            RAISE_APPLICATION_ERROR(-20314,'Invalid card type: '||p_card_type);
        END IF;

        -- Generate card number (simplified for demo - real systems use Luhn algorithm)
        SELECT seq_card_id.NEXTVAL INTO v_seq FROM DUAL;
        v_raw_number := LPAD(TO_CHAR(v_seq),16,'4') ;
        v_last_four  := SUBSTR(v_raw_number,-4,4);
        v_card_hash  := STANDARD_HASH(v_raw_number||TO_CHAR(SYSTIMESTAMP),'SHA256');

        -- Set expiry and credit limit
        v_expiry := ADD_MONTHS(LAST_DAY(SYSDATE), c_expiry_years * 12);
        IF p_card_type = 'CREDIT' THEN
            v_credit_lim  := NVL(p_credit_limit, c_default_credit_limit);
            v_daily_lim   := LEAST(v_credit_lim, c_default_daily_limit * 2);
        ELSE
            v_credit_lim  := NULL;
        END IF;

        -- Insert card record (status BLOCKED until activated)
        INSERT INTO cards(
            card_number_hash, card_last_four, account_id, customer_id,
            card_type, card_network, credit_limit, available_credit,
            expiry_date, status, daily_limit, issued_date, created_at
        ) VALUES(
            v_card_hash, v_last_four, p_account_id, p_customer_id,
            p_card_type, p_card_network, v_credit_lim, v_credit_lim,
            v_expiry, 'BLOCKED', v_daily_lim, SYSDATE, SYSTIMESTAMP
        ) RETURNING card_id INTO p_card_id;

        p_masked_number := '****-****-****-'||v_last_four;

        p_card_audit(p_card_id,'INSERT',NULL,
            'type='||p_card_type||',network='||p_card_network||
            ',account='||p_account_id||',expiry='||TO_CHAR(v_expiry,'MM/YYYY'));

        DBMS_OUTPUT.PUT_LINE('Card issued: ID='||p_card_id||' '||p_masked_number||
            ' type='||p_card_type||' expires='||TO_CHAR(v_expiry,'MM/YYYY'));
    EXCEPTION WHEN OTHERS THEN ROLLBACK; RAISE;
    END issue_card;

    -- -------------------------------------------------------------------------
    PROCEDURE activate_card(p_card_id IN NUMBER, p_employee_id IN NUMBER) IS
        v_status   VARCHAR2(20);
        v_expiry   DATE;
        v_emp_role VARCHAR2(50);
    BEGIN
        BEGIN
            SELECT role INTO v_emp_role FROM employees
            WHERE  employee_id=p_employee_id AND is_active='Y';
        EXCEPTION WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20320,'Employee not found: '||p_employee_id);
        END;

        BEGIN
            SELECT status, expiry_date INTO v_status, v_expiry
            FROM   cards WHERE card_id = p_card_id FOR UPDATE;
        EXCEPTION WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20321,'Card not found: '||p_card_id);
        END;

        IF v_status = 'ACTIVE'    THEN
            RAISE_APPLICATION_ERROR(-20322,'Card already active');
        END IF;
        IF v_status = 'CANCELLED' THEN
            RAISE_APPLICATION_ERROR(-20323,'Cannot activate a cancelled card');
        END IF;
        IF v_expiry < SYSDATE THEN
            RAISE_APPLICATION_ERROR(-20300,'Card is expired');
        END IF;

        UPDATE cards SET status='ACTIVE', updated_at=SYSTIMESTAMP WHERE card_id=p_card_id;

        p_card_audit(p_card_id,'UPDATE','status='||v_status,
            'status=ACTIVE,activated_by='||p_employee_id);
        DBMS_OUTPUT.PUT_LINE('Card activated: ID='||p_card_id||' by emp='||p_employee_id);
    EXCEPTION WHEN OTHERS THEN ROLLBACK; RAISE;
    END activate_card;

    -- -------------------------------------------------------------------------
    PROCEDURE block_card(p_card_id IN NUMBER, p_reason IN VARCHAR2, p_employee_id IN NUMBER) IS
        v_status VARCHAR2(20);
    BEGIN
        SELECT status INTO v_status FROM cards WHERE card_id=p_card_id FOR UPDATE;

        IF v_status = 'CANCELLED' THEN
            RAISE_APPLICATION_ERROR(-20330,'Cannot block a cancelled card');
        END IF;
        IF v_status = 'BLOCKED' THEN
            RAISE_APPLICATION_ERROR(-20301,'Card already blocked');
        END IF;

        UPDATE cards SET status='BLOCKED', updated_at=SYSTIMESTAMP WHERE card_id=p_card_id;

        p_card_audit(p_card_id,'UPDATE','status='||v_status,
            'status=BLOCKED,reason='||NVL(p_reason,'N/A')||',by='||p_employee_id);
        DBMS_OUTPUT.PUT_LINE('Card blocked: ID='||p_card_id||' reason='||NVL(p_reason,'N/A'));
    EXCEPTION WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20331,'Card not found: '||p_card_id);
    WHEN OTHERS THEN ROLLBACK; RAISE;
    END block_card;

    -- -------------------------------------------------------------------------
    PROCEDURE unblock_card(p_card_id IN NUMBER, p_employee_id IN NUMBER) IS
        v_expiry DATE;
    BEGIN
        SELECT expiry_date INTO v_expiry FROM cards WHERE card_id=p_card_id AND status='BLOCKED'
        FOR UPDATE;

        IF v_expiry < SYSDATE THEN
            RAISE_APPLICATION_ERROR(-20300,'Cannot unblock an expired card');
        END IF;

        UPDATE cards SET status='ACTIVE', updated_at=SYSTIMESTAMP WHERE card_id=p_card_id;
        p_card_audit(p_card_id,'UPDATE','status=BLOCKED','status=ACTIVE,unblocked_by='||p_employee_id);
        DBMS_OUTPUT.PUT_LINE('Card unblocked: ID='||p_card_id);
    EXCEPTION WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20332,'Card not found or not in BLOCKED status: '||p_card_id);
    WHEN OTHERS THEN ROLLBACK; RAISE;
    END unblock_card;

    -- -------------------------------------------------------------------------
    PROCEDURE update_card_limits(
        p_card_id         IN NUMBER,
        p_new_daily_limit IN NUMBER,
        p_new_credit_limit IN NUMBER DEFAULT NULL,
        p_employee_id     IN NUMBER
    ) IS
        v_card_type     VARCHAR2(20);
        v_old_daily     NUMBER;
        v_old_credit    NUMBER;
        v_status        VARCHAR2(20);
    BEGIN
        SELECT card_type, daily_limit, NVL(credit_limit,0), status
        INTO   v_card_type, v_old_daily, v_old_credit, v_status
        FROM   cards WHERE card_id=p_card_id FOR UPDATE;

        IF v_status IN ('CANCELLED','EXPIRED') THEN
            RAISE_APPLICATION_ERROR(-20340,'Cannot update limits on '||v_status||' card');
        END IF;
        IF p_new_daily_limit <= 0 THEN
            RAISE_APPLICATION_ERROR(-20341,'Daily limit must be positive');
        END IF;
        IF p_new_daily_limit > 50000 THEN
            RAISE_APPLICATION_ERROR(-20342,'Daily limit cannot exceed 50,000');
        END IF;

        IF v_card_type = 'CREDIT' AND p_new_credit_limit IS NOT NULL THEN
            IF p_new_credit_limit <= 0 THEN
                RAISE_APPLICATION_ERROR(-20343,'Credit limit must be positive');
            END IF;
            UPDATE cards
            SET    daily_limit    = p_new_daily_limit,
                   credit_limit   = p_new_credit_limit,
                   available_credit = available_credit + (p_new_credit_limit - v_old_credit),
                   updated_at     = SYSTIMESTAMP
            WHERE  card_id = p_card_id;
        ELSE
            UPDATE cards
            SET    daily_limit = p_new_daily_limit,
                   updated_at  = SYSTIMESTAMP
            WHERE  card_id = p_card_id;
        END IF;

        p_card_audit(p_card_id,'UPDATE',
            'daily_limit='||v_old_daily||',credit_limit='||v_old_credit,
            'daily_limit='||p_new_daily_limit||
            ',credit_limit='||NVL(TO_CHAR(p_new_credit_limit),'unchanged')||
            ',by='||p_employee_id);
        DBMS_OUTPUT.PUT_LINE('Card limits updated: ID='||p_card_id||
            ' daily='||p_new_daily_limit);
    EXCEPTION WHEN OTHERS THEN ROLLBACK; RAISE;
    END update_card_limits;

    -- -------------------------------------------------------------------------
    PROCEDURE expire_old_cards(p_as_of_date IN DATE DEFAULT SYSDATE, p_expired_count OUT NUMBER) IS
        v_card_id    NUMBER;
        v_account_id NUMBER;
        v_last_four  VARCHAR2(4);

        CURSOR c_expiring IS
            SELECT card_id, account_id, card_last_four
            FROM   cards
            WHERE  status      = 'ACTIVE'
            AND    expiry_date < p_as_of_date
            ORDER  BY expiry_date ASC;
    BEGIN
        p_expired_count := 0;
        DBMS_OUTPUT.PUT_LINE('Card Expiry Job: '||TO_CHAR(p_as_of_date,'YYYY-MM-DD'));

        OPEN c_expiring;
        LOOP
            FETCH c_expiring INTO v_card_id, v_account_id, v_last_four;
            EXIT WHEN c_expiring%NOTFOUND;
            BEGIN
                UPDATE cards SET status='EXPIRED', updated_at=SYSTIMESTAMP
                WHERE  card_id = v_card_id;

                p_card_audit(v_card_id,'UPDATE','status=ACTIVE',
                    'status=EXPIRED,auto_expired='||TO_CHAR(p_as_of_date,'YYYY-MM-DD'));
                p_expired_count := p_expired_count + 1;
                DBMS_OUTPUT.PUT_LINE('Card expired: ID='||v_card_id||' ****'||v_last_four);
            EXCEPTION WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('ERR expiring card '||v_card_id||': '||SQLERRM);
            END;
        END LOOP;
        CLOSE c_expiring;
        DBMS_OUTPUT.PUT_LINE('Card Expiry Done: '||p_expired_count||' expired');
    EXCEPTION WHEN OTHERS THEN
        IF c_expiring%ISOPEN THEN CLOSE c_expiring; END IF;
        RAISE;
    END expire_old_cards;

    -- -------------------------------------------------------------------------
    PROCEDURE renew_expiring_cards(
        p_days_before_expiry IN NUMBER DEFAULT 60,
        p_renewed_count      OUT NUMBER,
        p_failed_count       OUT NUMBER
    ) IS
        v_card_id      NUMBER;
        v_account_id   NUMBER;
        v_customer_id  NUMBER;
        v_card_type    VARCHAR2(20);
        v_network      VARCHAR2(20);
        v_credit_limit NUMBER;
        v_daily_limit  NUMBER;
        v_new_card_id  NUMBER;
        v_masked       VARCHAR2(20);

        CURSOR c_renew IS
            SELECT card_id, account_id, customer_id, card_type,
                   card_network, credit_limit, daily_limit
            FROM   cards
            WHERE  status      = 'ACTIVE'
            AND    expiry_date BETWEEN SYSDATE AND SYSDATE + p_days_before_expiry
            AND    card_type  != 'PREPAID'
            ORDER  BY expiry_date ASC;
    BEGIN
        p_renewed_count := 0;
        p_failed_count  := 0;
        DBMS_OUTPUT.PUT_LINE('Card Renewal Job: expiring within '||p_days_before_expiry||' days');

        OPEN c_renew;
        LOOP
            FETCH c_renew INTO v_card_id, v_account_id, v_customer_id,
                               v_card_type, v_network, v_credit_limit, v_daily_limit;
            EXIT WHEN c_renew%NOTFOUND;
            BEGIN
                issue_card(v_account_id, v_customer_id, v_card_type, v_network,
                           v_credit_limit, v_new_card_id, v_masked);

                UPDATE cards SET status='CANCELLED', updated_at=SYSTIMESTAMP
                WHERE  card_id = v_card_id;

                p_card_audit(v_card_id,'UPDATE','status=ACTIVE',
                    'status=CANCELLED,renewed_by_card='||v_new_card_id);

                p_renewed_count := p_renewed_count + 1;
                DBMS_OUTPUT.PUT_LINE('Card renewed: old='||v_card_id||' new='||v_new_card_id);
            EXCEPTION WHEN OTHERS THEN
                p_failed_count := p_failed_count + 1;
                DBMS_OUTPUT.PUT_LINE('ERR renewing card '||v_card_id||': '||SQLERRM);
            END;
        END LOOP;
        CLOSE c_renew;
        DBMS_OUTPUT.PUT_LINE('Renewal Done: renewed='||p_renewed_count||' failed='||p_failed_count);
    EXCEPTION WHEN OTHERS THEN
        IF c_renew%ISOPEN THEN CLOSE c_renew; END IF;
        RAISE;
    END renew_expiring_cards;

    -- -------------------------------------------------------------------------
    PROCEDURE generate_card_activity_report(
        p_from_date IN DATE, p_to_date IN DATE, p_report OUT SYS_REFCURSOR
    ) IS
    BEGIN
        OPEN p_report FOR
            SELECT
                c.card_id,
                c.card_last_four,
                c.card_type,
                c.card_network,
                c.status                                          AS card_status,
                c.daily_limit,
                c.credit_limit,
                c.expiry_date,
                a.account_number,
                cu.first_name||' '||cu.last_name                 AS cardholder_name,
                cu.customer_type,
                COUNT(t.transaction_id)                          AS total_transactions,
                NVL(SUM(CASE WHEN t.transaction_type IN ('WITHDRAWAL','PAYMENT')
                         THEN t.amount END),0)                    AS total_spend,
                NVL(SUM(CASE WHEN t.transaction_type = 'DEPOSIT'
                         THEN t.amount END),0)                    AS total_payments_received,
                NVL(MAX(t.amount),0)                              AS largest_transaction,
                ROUND(NVL(AVG(t.amount),0),2)                    AS avg_transaction_amt,
                COUNT(DISTINCT TRUNC(t.transaction_date))        AS active_days,
                COUNT(DISTINCT t.channel)                        AS channels_used
            FROM   cards   c
            JOIN   accounts  a  ON c.account_id  = a.account_id
            JOIN   customers cu ON c.customer_id = cu.customer_id
            LEFT JOIN transactions t ON t.account_id = c.account_id
                AND TRUNC(t.transaction_date) BETWEEN p_from_date AND p_to_date
                AND t.status = 'COMPLETED'
            GROUP  BY c.card_id, c.card_last_four, c.card_type, c.card_network,
                      c.status, c.daily_limit, c.credit_limit, c.expiry_date,
                      a.account_number, cu.first_name, cu.last_name, cu.customer_type
            ORDER  BY total_spend DESC NULLS LAST;
    END generate_card_activity_report;

END pkg_card_operations;
/
SHOW ERRORS PACKAGE BODY pkg_card_operations;

-- =============================================================================
-- PACKAGE 4: PKG_COLLECTIONS_MGMT
-- Debt Collections Management Package
-- =============================================================================

CREATE OR REPLACE PACKAGE pkg_collections_mgmt AS
    c_soft_collection_days   CONSTANT NUMBER := 30;
    c_hard_collection_days   CONSTANT NUMBER := 90;
    c_legal_referral_days    CONSTANT NUMBER := 180;
    c_recovery_fee_pct       CONSTANT NUMBER := 0.15;
    c_settlement_min_pct     CONSTANT NUMBER := 0.50;

    e_case_already_closed    EXCEPTION;
    e_insufficient_settlement EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_case_already_closed,      -20400);
    PRAGMA EXCEPTION_INIT(e_insufficient_settlement,  -20401);

    FUNCTION  get_total_past_due(p_customer_id IN NUMBER) RETURN NUMBER;
    FUNCTION  get_collection_score(p_customer_id IN NUMBER) RETURN NUMBER;
    FUNCTION  calc_settlement_minimum(p_loan_id IN NUMBER) RETURN NUMBER;
    FUNCTION  count_delinquent_loans(p_customer_id IN NUMBER) RETURN NUMBER;
    FUNCTION  get_days_delinquent(p_loan_id IN NUMBER) RETURN NUMBER;

    PROCEDURE run_collection_batch(
        p_as_of_date IN DATE DEFAULT SYSDATE,
        p_soft_count OUT NUMBER, p_hard_count OUT NUMBER, p_legal_count OUT NUMBER);
    PROCEDURE process_collection_payment(
        p_loan_id IN NUMBER, p_payment_amount IN NUMBER,
        p_payment_account IN NUMBER, p_employee_id IN NUMBER,
        p_payment_id OUT NUMBER, p_remaining OUT NUMBER);
    PROCEDURE negotiate_settlement(
        p_loan_id IN NUMBER, p_offered_amount IN NUMBER,
        p_employee_id IN NUMBER, p_accepted OUT BOOLEAN, p_final_amount OUT NUMBER);
    PROCEDURE write_off_collection_case(
        p_loan_id IN NUMBER, p_reason IN VARCHAR2,
        p_employee_id IN NUMBER, p_written_off_amount OUT NUMBER);
    PROCEDURE generate_collections_report(
        p_as_of_date IN DATE DEFAULT SYSDATE, p_report OUT SYS_REFCURSOR);
END pkg_collections_mgmt;
/

CREATE OR REPLACE PACKAGE BODY pkg_collections_mgmt AS

    PROCEDURE p_coll_audit(p_table IN VARCHAR2, p_id IN NUMBER,
                           p_action IN VARCHAR2, p_old IN VARCHAR2, p_new IN VARCHAR2) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO audit_log(table_name,record_id,action,old_values,new_values,changed_by,changed_at)
        VALUES(p_table,p_id,p_action,p_old,p_new,SYS_CONTEXT('USERENV','SESSION_USER'),SYSTIMESTAMP);
        COMMIT;
    EXCEPTION WHEN OTHERS THEN NULL;
    END p_coll_audit;

    -- -------------------------------------------------------------------------
    FUNCTION get_total_past_due(p_customer_id IN NUMBER) RETURN NUMBER IS
        v_total NUMBER := 0;
    BEGIN
        SELECT NVL(SUM(lp.scheduled_amount - NVL(lp.paid_amount,0)),0)
        INTO   v_total
        FROM   loan_payments lp
        JOIN   loans l ON lp.loan_id = l.loan_id
        WHERE  l.customer_id = p_customer_id
        AND    l.status      = 'ACTIVE'
        AND    lp.status     = 'OVERDUE'
        AND    lp.scheduled_amount > NVL(lp.paid_amount,0);
        RETURN v_total;
    EXCEPTION WHEN OTHERS THEN RETURN 0;
    END get_total_past_due;

    -- -------------------------------------------------------------------------
    FUNCTION get_collection_score(p_customer_id IN NUMBER) RETURN NUMBER IS
        v_credit_score    NUMBER;
        v_risk_level      VARCHAR2(10);
        v_total_past_due  NUMBER;
        v_delinq_loans    NUMBER;
        v_max_dpd         NUMBER;
        v_score           NUMBER := 0;
    BEGIN
        BEGIN
            SELECT NVL(credit_score,500), risk_level
            INTO   v_credit_score, v_risk_level
            FROM   customers WHERE customer_id=p_customer_id;
        EXCEPTION WHEN NO_DATA_FOUND THEN RETURN 100;
        END;

        SELECT NVL(MAX(days_past_due),0), COUNT(CASE WHEN days_past_due>0 THEN 1 END)
        INTO   v_max_dpd, v_delinq_loans
        FROM   loans WHERE customer_id=p_customer_id AND status='ACTIVE';

        v_total_past_due := get_total_past_due(p_customer_id);

        -- Score: higher = harder to collect
        v_score := 0;
        IF v_credit_score < 550     THEN v_score := v_score + 30;
        ELSIF v_credit_score < 620  THEN v_score := v_score + 20;
        ELSIF v_credit_score < 680  THEN v_score := v_score + 10;
        ELSE                             v_score := v_score + 0; END IF;

        IF v_risk_level = 'HIGH'    THEN v_score := v_score + 25;
        ELSIF v_risk_level='MEDIUM' THEN v_score := v_score + 10;
        ELSE                             v_score := v_score + 0; END IF;

        IF v_max_dpd >= 180 THEN v_score := v_score + 30;
        ELSIF v_max_dpd >= 90  THEN v_score := v_score + 20;
        ELSIF v_max_dpd >= 60  THEN v_score := v_score + 10;
        ELSIF v_max_dpd >= 30  THEN v_score := v_score + 5; END IF;

        IF v_delinq_loans >= 3 THEN v_score := v_score + 15;
        ELSIF v_delinq_loans >= 2 THEN v_score := v_score + 8; END IF;

        IF v_total_past_due > 10000 THEN v_score := v_score + 10; END IF;

        RETURN LEAST(v_score, 100);
    EXCEPTION WHEN OTHERS THEN RETURN 50;
    END get_collection_score;

    -- -------------------------------------------------------------------------
    FUNCTION calc_settlement_minimum(p_loan_id IN NUMBER) RETURN NUMBER IS
        v_balance NUMBER;
        v_dpd     NUMBER;
        v_pct     NUMBER;
    BEGIN
        SELECT outstanding_balance, days_past_due
        INTO   v_balance, v_dpd
        FROM   loans WHERE loan_id=p_loan_id AND status='ACTIVE';

        IF    v_dpd >= 180 THEN v_pct := 0.40;
        ELSIF v_dpd >= 120 THEN v_pct := 0.50;
        ELSIF v_dpd >= 90  THEN v_pct := 0.60;
        ELSIF v_dpd >= 60  THEN v_pct := 0.70;
        ELSE                    v_pct := c_settlement_min_pct; END IF;

        RETURN ROUND(v_balance * v_pct, 2);
    EXCEPTION WHEN NO_DATA_FOUND THEN RETURN -1;
    END calc_settlement_minimum;

    -- -------------------------------------------------------------------------
    FUNCTION count_delinquent_loans(p_customer_id IN NUMBER) RETURN NUMBER IS
        v_count NUMBER := 0;
    BEGIN
        SELECT COUNT(*) INTO v_count FROM loans
        WHERE  customer_id=p_customer_id AND status='ACTIVE' AND days_past_due>0;
        RETURN NVL(v_count,0);
    END count_delinquent_loans;

    -- -------------------------------------------------------------------------
    FUNCTION get_days_delinquent(p_loan_id IN NUMBER) RETURN NUMBER IS
        v_dpd NUMBER;
    BEGIN
        SELECT NVL(days_past_due,0) INTO v_dpd FROM loans WHERE loan_id=p_loan_id;
        RETURN v_dpd;
    EXCEPTION WHEN NO_DATA_FOUND THEN RETURN -1;
    END get_days_delinquent;

    -- -------------------------------------------------------------------------
    PROCEDURE run_collection_batch(
        p_as_of_date IN  DATE DEFAULT SYSDATE,
        p_soft_count OUT NUMBER,
        p_hard_count OUT NUMBER,
        p_legal_count OUT NUMBER
    ) IS
        v_loan_id       NUMBER;
        v_customer_id   NUMBER;
        v_dpd           NUMBER;
        v_balance       NUMBER;
        v_loan_type     VARCHAR2(30);
        v_loan_number   VARCHAR2(20);
        v_coll_score    NUMBER;

        CURSOR c_delinquent IS
            SELECT l.loan_id, l.customer_id, l.days_past_due,
                   l.outstanding_balance, l.loan_type, l.loan_number
            FROM   loans l
            WHERE  l.status = 'ACTIVE'
            AND    l.days_past_due > 0
            ORDER  BY l.days_past_due DESC, l.outstanding_balance DESC;
    BEGIN
        p_soft_count  := 0;
        p_hard_count  := 0;
        p_legal_count := 0;
        DBMS_OUTPUT.PUT_LINE('===== Collections Batch: '||TO_CHAR(p_as_of_date,'YYYY-MM-DD')||' =====');

        OPEN c_delinquent;
        LOOP
            FETCH c_delinquent INTO v_loan_id, v_customer_id, v_dpd,
                                    v_balance, v_loan_type, v_loan_number;
            EXIT WHEN c_delinquent%NOTFOUND;
            BEGIN
                v_coll_score := get_collection_score(v_customer_id);

                IF v_dpd >= c_legal_referral_days THEN
                    p_legal_count := p_legal_count + 1;
                    INSERT INTO fraud_alerts(account_id,customer_id,alert_type,
                                             severity,description,status,created_at)
                    SELECT NVL(account_id,0), v_customer_id,
                           'LEGAL_REFERRAL','CRITICAL',
                           'Loan '||v_loan_number||' DPD='||v_dpd||
                           ' Balance=$'||TO_CHAR(v_balance,'FM999,999.99')||
                           ' CollScore='||v_coll_score,
                           'OPEN', SYSTIMESTAMP
                    FROM   loans WHERE loan_id=v_loan_id;

                    DBMS_OUTPUT.PUT_LINE('[LEGAL] Loan '||v_loan_number||
                        ' DPD='||v_dpd||' Bal='||v_balance);

                ELSIF v_dpd >= c_hard_collection_days THEN
                    p_hard_count := p_hard_count + 1;
                    DBMS_OUTPUT.PUT_LINE('[HARD] Loan '||v_loan_number||
                        ' DPD='||v_dpd||' Bal='||v_balance);

                ELSIF v_dpd >= c_soft_collection_days THEN
                    p_soft_count := p_soft_count + 1;
                    DBMS_OUTPUT.PUT_LINE('[SOFT] Loan '||v_loan_number||
                        ' DPD='||v_dpd||' Bal='||v_balance);
                END IF;

                p_coll_audit('LOANS',v_loan_id,'UPDATE',
                    'dpd='||v_dpd,
                    'collection_stage='||
                    CASE WHEN v_dpd>=c_legal_referral_days THEN 'LEGAL'
                         WHEN v_dpd>=c_hard_collection_days THEN 'HARD'
                         ELSE 'SOFT' END);
            EXCEPTION WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('ERR processing loan '||v_loan_id||': '||SQLERRM);
            END;
        END LOOP;
        CLOSE c_delinquent;
        DBMS_OUTPUT.PUT_LINE('Collections Done: soft='||p_soft_count||
            ' hard='||p_hard_count||' legal='||p_legal_count);
    EXCEPTION WHEN OTHERS THEN
        IF c_delinquent%ISOPEN THEN CLOSE c_delinquent; END IF;
        RAISE;
    END run_collection_batch;

    -- -------------------------------------------------------------------------
    PROCEDURE process_collection_payment(
        p_loan_id        IN  NUMBER,
        p_payment_amount IN  NUMBER,
        p_payment_account IN NUMBER,
        p_employee_id    IN  NUMBER,
        p_payment_id     OUT NUMBER,
        p_remaining      OUT NUMBER
    ) IS
        v_loan           loans%ROWTYPE;
        v_recovery_fee   NUMBER;
        v_net_payment    NUMBER;
        v_fee_txn        NUMBER;
        v_txn_id         NUMBER;
        v_ref            VARCHAR2(50);
        v_prin_paid      NUMBER;
        v_int_paid       NUMBER;
    BEGIN
        SELECT * INTO v_loan FROM loans WHERE loan_id=p_loan_id AND status='ACTIVE' FOR UPDATE;

        IF v_loan.days_past_due = 0 THEN
            RAISE_APPLICATION_ERROR(-20410,
                'Loan '||p_loan_id||' is current - use regular payment procedure');
        END IF;

        IF p_payment_amount <= 0 THEN
            RAISE_APPLICATION_ERROR(-20411,'Payment amount must be positive');
        END IF;

        -- Calculate collection recovery fee
        v_recovery_fee := ROUND(p_payment_amount * c_recovery_fee_pct, 2);
        v_net_payment  := p_payment_amount - v_recovery_fee;

        DBMS_OUTPUT.PUT_LINE('Collection payment: loan='||v_loan.loan_number||
            ' amount='||p_payment_amount||' fee='||v_recovery_fee||
            ' net='||v_net_payment);

        -- Debit the payment account
        pkg_account_mgmt.update_balance(p_payment_account, p_payment_amount, 'DR');

        -- Record transaction
        SELECT seq_transaction_id.NEXTVAL INTO v_txn_id FROM DUAL;
        v_ref := 'COLL-'||v_loan.loan_number||'-'||TO_CHAR(SYSDATE,'YYYYMMDD');

        INSERT INTO transactions(account_id,transaction_type,amount,
            balance_before,balance_after,description,reference_number,channel,status,processed_by)
        SELECT p_payment_account,'PAYMENT',p_payment_amount,
               balance+p_payment_amount, balance,
               'Collection payment for loan '||v_loan.loan_number,
               v_ref,'BRANCH','COMPLETED',p_employee_id
        FROM   accounts WHERE account_id=p_payment_account
        RETURNING transaction_id INTO v_txn_id;

        -- Reduce outstanding balance
        v_prin_paid := LEAST(v_net_payment, v_loan.outstanding_balance);
        UPDATE loans
        SET    outstanding_balance = outstanding_balance - v_prin_paid,
               days_past_due       = 0,
               updated_at          = SYSTIMESTAMP
        WHERE  loan_id = p_loan_id;

        p_remaining := v_loan.outstanding_balance - v_prin_paid;

        -- Update payment record
        UPDATE loan_payments
        SET    paid_amount  = NVL(paid_amount,0) + v_net_payment,
               payment_date = SYSDATE,
               status       = CASE WHEN (NVL(paid_amount,0)+v_net_payment) >= scheduled_amount
                                   THEN 'PAID' ELSE 'PARTIAL' END,
               transaction_id = v_txn_id
        WHERE  loan_id  = p_loan_id
        AND    status   IN ('OVERDUE','PARTIAL')
        AND    ROWNUM   = 1
        RETURNING payment_id INTO p_payment_id;

        -- Post recovery fee
        INSERT INTO fee_ledger(account_id,fee_type,fee_amount,fee_date,transaction_id)
        SELECT p_payment_account,'LATE_FEE',v_recovery_fee,SYSDATE,v_txn_id
        FROM   DUAL;

        IF p_remaining <= 0.01 THEN
            UPDATE loans SET status='PAID_OFF',outstanding_balance=0,updated_at=SYSTIMESTAMP
            WHERE  loan_id=p_loan_id;
            p_remaining := 0;
        END IF;

        p_coll_audit('LOANS',p_loan_id,'UPDATE',
            'balance='||v_loan.outstanding_balance||',dpd='||v_loan.days_past_due,
            'collection_payment='||p_payment_amount||',new_balance='||p_remaining);
    EXCEPTION WHEN OTHERS THEN ROLLBACK; RAISE;
    END process_collection_payment;

    -- -------------------------------------------------------------------------
    PROCEDURE negotiate_settlement(
        p_loan_id       IN  NUMBER,
        p_offered_amount IN  NUMBER,
        p_employee_id   IN  NUMBER,
        p_accepted      OUT BOOLEAN,
        p_final_amount  OUT NUMBER
    ) IS
        v_loan        loans%ROWTYPE;
        v_minimum     NUMBER;
        v_emp_role    VARCHAR2(50);
    BEGIN
        BEGIN
            SELECT role INTO v_emp_role FROM employees WHERE employee_id=p_employee_id AND is_active='Y';
        EXCEPTION WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20420,'Employee not found: '||p_employee_id);
        END;

        IF v_emp_role NOT IN ('MANAGER','LOAN_OFFICER','ADMIN') THEN
            RAISE_APPLICATION_ERROR(-20421,'Only managers/loan officers can approve settlements');
        END IF;

        SELECT * INTO v_loan FROM loans WHERE loan_id=p_loan_id AND status='ACTIVE' FOR UPDATE;

        IF v_loan.days_past_due < 60 THEN
            RAISE_APPLICATION_ERROR(-20422,
                'Settlement only available for loans 60+ DPD. Current: '||v_loan.days_past_due);
        END IF;

        v_minimum := calc_settlement_minimum(p_loan_id);
        DBMS_OUTPUT.PUT_LINE('Settlement negotiation: loan='||v_loan.loan_number||
            ' balance='||v_loan.outstanding_balance||
            ' offered='||p_offered_amount||' minimum='||v_minimum);

        IF p_offered_amount >= v_minimum THEN
            p_accepted     := TRUE;
            p_final_amount := p_offered_amount;
            DBMS_OUTPUT.PUT_LINE('Settlement ACCEPTED: '||p_final_amount);
        ELSE
            p_accepted     := FALSE;
            p_final_amount := v_minimum;
            DBMS_OUTPUT.PUT_LINE('Settlement REJECTED. Minimum: '||v_minimum);
        END IF;

        p_coll_audit('LOANS',p_loan_id,'UPDATE',
            'balance='||v_loan.outstanding_balance,
            'settlement_offer='||p_offered_amount||
            ',minimum='||v_minimum||',accepted='||
            CASE WHEN p_accepted THEN 'Y' ELSE 'N' END||
            ',by='||p_employee_id);
    EXCEPTION WHEN OTHERS THEN ROLLBACK; RAISE;
    END negotiate_settlement;

    -- -------------------------------------------------------------------------
    PROCEDURE write_off_collection_case(
        p_loan_id            IN  NUMBER,
        p_reason             IN  VARCHAR2,
        p_employee_id        IN  NUMBER,
        p_written_off_amount OUT NUMBER
    ) IS
        v_loan      loans%ROWTYPE;
        v_emp_role  VARCHAR2(50);
    BEGIN
        BEGIN
            SELECT role INTO v_emp_role FROM employees WHERE employee_id=p_employee_id AND is_active='Y';
        EXCEPTION WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20430,'Employee not found: '||p_employee_id);
        END;

        IF v_emp_role NOT IN ('MANAGER','ADMIN') THEN
            RAISE_APPLICATION_ERROR(-20431,'Only managers can write off loans');
        END IF;

        SELECT * INTO v_loan FROM loans WHERE loan_id=p_loan_id FOR UPDATE;

        IF v_loan.status NOT IN ('ACTIVE','DEFAULTED') THEN
            RAISE_APPLICATION_ERROR(-20432,
                'Cannot write off loan in status: '||v_loan.status);
        END IF;

        IF v_loan.days_past_due < 120 THEN
            RAISE_APPLICATION_ERROR(-20433,
                'Write-off requires 120+ DPD. Current: '||v_loan.days_past_due);
        END IF;

        p_written_off_amount := v_loan.outstanding_balance;

        UPDATE loans
        SET    status     = 'WRITTEN_OFF',
               updated_at = SYSTIMESTAMP
        WHERE  loan_id = p_loan_id;

        UPDATE loan_payments
        SET    status = 'WAIVED'
        WHERE  loan_id = p_loan_id AND status IN ('SCHEDULED','OVERDUE','PARTIAL');

        INSERT INTO fraud_alerts(account_id,customer_id,alert_type,severity,description,status,created_at)
        SELECT NVL(account_id,0), customer_id,
               'WRITE_OFF','HIGH',
               'Loan '||v_loan.loan_number||' written off. Amount=$'||
               TO_CHAR(p_written_off_amount,'FM999,999.99')||
               ' DPD='||v_loan.days_past_due||' Reason: '||p_reason,
               'OPEN',SYSTIMESTAMP
        FROM   loans WHERE loan_id=p_loan_id;

        p_coll_audit('LOANS',p_loan_id,'UPDATE',
            'status='||v_loan.status||',balance='||v_loan.outstanding_balance,
            'status=WRITTEN_OFF,reason='||p_reason||
            ',amount='||p_written_off_amount||',by='||p_employee_id);

        DBMS_OUTPUT.PUT_LINE('Loan written off: '||v_loan.loan_number||
            ' amount='||p_written_off_amount);
    EXCEPTION WHEN OTHERS THEN ROLLBACK; RAISE;
    END write_off_collection_case;

    -- -------------------------------------------------------------------------
    PROCEDURE generate_collections_report(
        p_as_of_date IN DATE DEFAULT SYSDATE, p_report OUT SYS_REFCURSOR
    ) IS
    BEGIN
        OPEN p_report FOR
            SELECT
                CASE
                    WHEN l.days_past_due = 0       THEN 'CURRENT'
                    WHEN l.days_past_due < 30      THEN '1-29 DPD'
                    WHEN l.days_past_due < 60      THEN '30-59 DPD (SOFT)'
                    WHEN l.days_past_due < 90      THEN '60-89 DPD (SOFT)'
                    WHEN l.days_past_due < 180     THEN '90-179 DPD (HARD)'
                    ELSE                                '180+ DPD (LEGAL)'
                END                                           AS collection_bucket,
                l.loan_type,
                COUNT(*)                                      AS loan_count,
                ROUND(SUM(l.outstanding_balance),2)           AS total_outstanding,
                ROUND(AVG(l.outstanding_balance),2)           AS avg_outstanding,
                ROUND(AVG(l.days_past_due),1)                 AS avg_dpd,
                MAX(l.days_past_due)                          AS max_dpd,
                ROUND(SUM(
                    SELECT NVL(SUM(lp2.scheduled_amount-NVL(lp2.paid_amount,0)),0)
                    FROM   loan_payments lp2
                    WHERE  lp2.loan_id=l.loan_id AND lp2.status='OVERDUE'
                ),2)                                          AS total_past_due_amt,
                ROUND(AVG(pkg_collections_mgmt.get_collection_score(l.customer_id)),1)
                                                              AS avg_collection_score
            FROM   loans l
            WHERE  l.status = 'ACTIVE'
            GROUP  BY CASE
                    WHEN l.days_past_due = 0       THEN 'CURRENT'
                    WHEN l.days_past_due < 30      THEN '1-29 DPD'
                    WHEN l.days_past_due < 60      THEN '30-59 DPD (SOFT)'
                    WHEN l.days_past_due < 90      THEN '60-89 DPD (SOFT)'
                    WHEN l.days_past_due < 180     THEN '90-179 DPD (HARD)'
                    ELSE                                '180+ DPD (LEGAL)' END,
                      l.loan_type
            ORDER  BY MIN(l.days_past_due) DESC, l.loan_type;
    END generate_collections_report;

END pkg_collections_mgmt;
/
SHOW ERRORS PACKAGE BODY pkg_collections_mgmt;

-- =============================================================================
-- PACKAGE 5: PKG_BATCH_PROCESSING
-- End-of-Day and End-of-Month Batch Processing Package
-- =============================================================================

CREATE OR REPLACE PACKAGE pkg_batch_processing AS
    c_eod_cutoff_hour    CONSTANT NUMBER := 23;
    c_stale_txn_days     CONSTANT NUMBER := 5;
    c_purge_audit_months CONSTANT NUMBER := 84;  -- 7 years

    PROCEDURE run_end_of_day(
        p_processing_date IN DATE DEFAULT SYSDATE,
        p_settled_txns    OUT NUMBER,
        p_failed_txns     OUT NUMBER,
        p_interest_posted OUT NUMBER,
        p_fees_applied    OUT NUMBER);
    PROCEDURE run_end_of_month(
        p_processing_date IN DATE DEFAULT SYSDATE,
        p_interest_total  OUT NUMBER,
        p_fees_total      OUT NUMBER,
        p_dormant_marked  OUT NUMBER,
        p_delinquent_upd  OUT NUMBER);
    PROCEDURE reconcile_account_balances(
        p_as_of_date IN DATE DEFAULT SYSDATE,
        p_mismatches_found OUT NUMBER, p_corrected_count OUT NUMBER);
    PROCEDURE purge_old_audit_records(
        p_cutoff_date IN DATE, p_purged_count OUT NUMBER);
    PROCEDURE run_nightly_reports(p_report_date IN DATE DEFAULT SYSDATE);
    PROCEDURE reprocess_failed_transactions(
        p_from_date IN DATE, p_reprocessed OUT NUMBER, p_still_failed OUT NUMBER);
END pkg_batch_processing;
/

CREATE OR REPLACE PACKAGE BODY pkg_batch_processing AS

    PROCEDURE p_batch_log(p_job IN VARCHAR2, p_msg IN VARCHAR2) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO audit_log(table_name,record_id,action,new_values,changed_by,changed_at)
        VALUES('BATCH_JOB',-1,'INSERT',
               'JOB='||p_job||'|MSG='||SUBSTR(p_msg,1,3500),
               'BATCH_SYSTEM',SYSTIMESTAMP);
        COMMIT;
    EXCEPTION WHEN OTHERS THEN NULL;
    END p_batch_log;

    -- -------------------------------------------------------------------------
    PROCEDURE run_end_of_day(
        p_processing_date IN  DATE DEFAULT SYSDATE,
        p_settled_txns    OUT NUMBER,
        p_failed_txns     OUT NUMBER,
        p_interest_posted OUT NUMBER,
        p_fees_applied    OUT NUMBER
    ) IS
        v_start_time   TIMESTAMP := SYSTIMESTAMP;
        v_elapsed      NUMBER;
        v_fee_count    NUMBER;
        v_total_fees   NUMBER;
        v_int_count    NUMBER;
        v_total_int    NUMBER;
        v_kyc_expired  NUMBER;
    BEGIN
        p_settled_txns    := 0;
        p_failed_txns     := 0;
        p_interest_posted := 0;
        p_fees_applied    := 0;

        DBMS_OUTPUT.PUT_LINE(RPAD('=',70,'='));
        DBMS_OUTPUT.PUT_LINE('EOD BATCH START: '||TO_CHAR(SYSTIMESTAMP,'YYYY-MM-DD HH24:MI:SS.FF3'));
        DBMS_OUTPUT.PUT_LINE('Processing Date: '||TO_CHAR(p_processing_date,'YYYY-MM-DD'));
        DBMS_OUTPUT.PUT_LINE(RPAD('-',70,'-'));

        -- Step 1: Settle pending transactions
        DBMS_OUTPUT.PUT_LINE('Step 1: Settling pending transactions...');
        BEGIN
            pkg_transactions.settle_pending_transactions(p_processing_date,
                p_settled_txns, p_failed_txns);
            DBMS_OUTPUT.PUT_LINE('  Settled: '||p_settled_txns||' Failed: '||p_failed_txns);
            p_batch_log('EOD_SETTLE','settled='||p_settled_txns||' failed='||p_failed_txns);
        EXCEPTION WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('  ERROR in settlement: '||SQLERRM);
            p_batch_log('EOD_SETTLE_ERROR',SQLERRM);
        END;

        -- Step 2: Mark dormant accounts
        DBMS_OUTPUT.PUT_LINE('Step 2: Marking dormant accounts...');
        BEGIN
            pkg_account_mgmt.mark_dormant_accounts;
            DBMS_OUTPUT.PUT_LINE('  Dormancy check complete');
            p_batch_log('EOD_DORMANCY','Dormancy check executed');
        EXCEPTION WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('  ERROR in dormancy: '||SQLERRM);
        END;

        -- Step 3: Update loan delinquency
        DBMS_OUTPUT.PUT_LINE('Step 3: Updating delinquency status...');
        DECLARE
            v_delinq_count NUMBER;
            v_dpd_bal      NUMBER;
        BEGIN
            pkg_loan_mgmt.update_delinquency_status(p_processing_date, v_delinq_count, v_dpd_bal);
            DBMS_OUTPUT.PUT_LINE('  Delinquent loans: '||v_delinq_count||
                ' Total DPD balance: '||NVL(v_dpd_bal,0));
            p_batch_log('EOD_DELINQUENCY','count='||v_delinq_count||' balance='||NVL(v_dpd_bal,0));
        EXCEPTION WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('  ERROR in delinquency: '||SQLERRM);
        END;

        -- Step 4: Late fees for delinquent loans
        DBMS_OUTPUT.PUT_LINE('Step 4: Applying late fees...');
        DECLARE
            v_lf_count NUMBER;
            v_lf_total NUMBER;
        BEGIN
            pkg_loan_mgmt.apply_late_fees(p_processing_date, v_lf_count, v_lf_total);
            p_fees_applied    := p_fees_applied + v_lf_count;
            DBMS_OUTPUT.PUT_LINE('  Late fees applied: '||v_lf_count||' total='||NVL(v_lf_total,0));
            p_batch_log('EOD_LATE_FEES','count='||v_lf_count||' total='||NVL(v_lf_total,0));
        EXCEPTION WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('  ERROR applying late fees: '||SQLERRM);
        END;

        -- Step 5: Run collections batch
        DBMS_OUTPUT.PUT_LINE('Step 5: Collections batch...');
        DECLARE
            v_soft NUMBER; v_hard NUMBER; v_legal NUMBER;
        BEGIN
            pkg_collections_mgmt.run_collection_batch(p_processing_date, v_soft, v_hard, v_legal);
            DBMS_OUTPUT.PUT_LINE('  Collections: soft='||v_soft||' hard='||v_hard||' legal='||v_legal);
        EXCEPTION WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('  ERROR in collections: '||SQLERRM);
        END;

        -- Step 6: AML daily scan
        DBMS_OUTPUT.PUT_LINE('Step 6: AML daily scan...');
        DECLARE
            v_scanned NUMBER; v_alerts NUMBER;
        BEGIN
            pkg_aml_compliance.run_daily_aml_scan(p_processing_date, v_scanned, v_alerts);
            DBMS_OUTPUT.PUT_LINE('  AML: scanned='||v_scanned||' alerts='||v_alerts);
            p_batch_log('EOD_AML','scanned='||v_scanned||' alerts='||v_alerts);
        EXCEPTION WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('  ERROR in AML scan: '||SQLERRM);
        END;

        -- Step 7: Expire AML alerts
        DBMS_OUTPUT.PUT_LINE('Step 7: Escalating stale AML alerts...');
        DECLARE v_esc NUMBER;
        BEGIN
            pkg_aml_compliance.escalate_high_risk_alerts(p_processing_date, v_esc);
            DBMS_OUTPUT.PUT_LINE('  Escalated: '||v_esc||' alerts');
        EXCEPTION WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('  ERROR escalating alerts: '||SQLERRM);
        END;

        v_elapsed := (SYSTIMESTAMP - v_start_time) * 86400;
        DBMS_OUTPUT.PUT_LINE(RPAD('-',70,'-'));
        DBMS_OUTPUT.PUT_LINE('EOD COMPLETE. Elapsed: '||ROUND(v_elapsed,2)||'s');
        DBMS_OUTPUT.PUT_LINE(RPAD('=',70,'='));
        p_batch_log('EOD_COMPLETE','elapsed='||ROUND(v_elapsed,2)||
            's settled='||p_settled_txns||' failed='||p_failed_txns);
        COMMIT;
    EXCEPTION WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('FATAL EOD ERROR: '||SQLERRM);
        p_batch_log('EOD_FATAL_ERROR',SQLERRM);
        RAISE;
    END run_end_of_day;

    -- -------------------------------------------------------------------------
    PROCEDURE run_end_of_month(
        p_processing_date IN  DATE DEFAULT SYSDATE,
        p_interest_total  OUT NUMBER,
        p_fees_total      OUT NUMBER,
        p_dormant_marked  OUT NUMBER,
        p_delinquent_upd  OUT NUMBER
    ) IS
        v_start_time   TIMESTAMP := SYSTIMESTAMP;
        v_int_count    NUMBER;
        v_fee_count    NUMBER;
        v_elapsed      NUMBER;
    BEGIN
        p_interest_total := 0;
        p_fees_total     := 0;
        p_dormant_marked := 0;
        p_delinquent_upd := 0;

        DBMS_OUTPUT.PUT_LINE(RPAD('=',70,'='));
        DBMS_OUTPUT.PUT_LINE('EOM BATCH START: '||TO_CHAR(SYSTIMESTAMP,'YYYY-MM-DD HH24:MI:SS.FF3'));
        DBMS_OUTPUT.PUT_LINE(RPAD('-',70,'-'));

        -- Step 1: Post monthly interest
        DBMS_OUTPUT.PUT_LINE('Step 1: Posting monthly interest...');
        BEGIN
            pkg_transactions.post_monthly_interest(p_processing_date, NULL, v_int_count, p_interest_total);
            DBMS_OUTPUT.PUT_LINE('  Interest posted: '||v_int_count||' accounts, total='||p_interest_total);
            p_batch_log('EOM_INTEREST','count='||v_int_count||' total='||p_interest_total);
        EXCEPTION WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('  ERROR posting interest: '||SQLERRM);
            p_batch_log('EOM_INTEREST_ERROR',SQLERRM);
        END;

        -- Step 2: Apply monthly fees
        DBMS_OUTPUT.PUT_LINE('Step 2: Applying monthly fees...');
        BEGIN
            pkg_transactions.apply_monthly_fees(p_processing_date, v_fee_count, p_fees_total);
            DBMS_OUTPUT.PUT_LINE('  Fees applied: '||v_fee_count||' accounts, total='||p_fees_total);
            p_batch_log('EOM_FEES','count='||v_fee_count||' total='||p_fees_total);
        EXCEPTION WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('  ERROR applying fees: '||SQLERRM);
        END;

        -- Step 3: Mark dormant accounts
        DBMS_OUTPUT.PUT_LINE('Step 3: Dormancy check...');
        BEGIN
            SELECT COUNT(*) INTO p_dormant_marked FROM accounts WHERE status='DORMANT';
            pkg_account_mgmt.mark_dormant_accounts;
            DBMS_OUTPUT.PUT_LINE('  Dormancy processing complete');
        EXCEPTION WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('  ERROR in dormancy: '||SQLERRM);
        END;

        -- Step 4: Update delinquency
        DBMS_OUTPUT.PUT_LINE('Step 4: Delinquency refresh...');
        DECLARE v_dpd_bal NUMBER;
        BEGIN
            pkg_loan_mgmt.update_delinquency_status(p_processing_date,p_delinquent_upd,v_dpd_bal);
            DBMS_OUTPUT.PUT_LINE('  Delinquent: '||p_delinquent_upd||' loans');
        EXCEPTION WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('  ERROR in delinquency: '||SQLERRM);
        END;

        -- Step 5: KYC expiry check
        DBMS_OUTPUT.PUT_LINE('Step 5: KYC expiry check...');
        DECLARE v_kyc_exp NUMBER;
        BEGIN
            pkg_kyc_verification.expire_overdue_kyc_records(v_kyc_exp);
            DBMS_OUTPUT.PUT_LINE('  KYC expired: '||v_kyc_exp||' records');
        EXCEPTION WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('  ERROR in KYC expiry: '||SQLERRM);
        END;

        -- Step 6: Card expiry
        DBMS_OUTPUT.PUT_LINE('Step 6: Card expiry check...');
        DECLARE v_card_exp NUMBER;
        BEGIN
            pkg_card_operations.expire_old_cards(p_processing_date, v_card_exp);
            DBMS_OUTPUT.PUT_LINE('  Cards expired: '||v_card_exp);
        EXCEPTION WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('  ERROR in card expiry: '||SQLERRM);
        END;

        v_elapsed := (SYSTIMESTAMP - v_start_time) * 86400;
        DBMS_OUTPUT.PUT_LINE(RPAD('-',70,'-'));
        DBMS_OUTPUT.PUT_LINE('EOM COMPLETE. Elapsed: '||ROUND(v_elapsed,2)||'s');
        DBMS_OUTPUT.PUT_LINE(RPAD('=',70,'='));
        p_batch_log('EOM_COMPLETE','elapsed='||ROUND(v_elapsed,2)||
            's interest='||p_interest_total||' fees='||p_fees_total);
        COMMIT;
    EXCEPTION WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('FATAL EOM ERROR: '||SQLERRM);
        p_batch_log('EOM_FATAL_ERROR',SQLERRM);
        RAISE;
    END run_end_of_month;

    -- -------------------------------------------------------------------------
    PROCEDURE reconcile_account_balances(
        p_as_of_date       IN  DATE DEFAULT SYSDATE,
        p_mismatches_found OUT NUMBER,
        p_corrected_count  OUT NUMBER
    ) IS
        v_account_id      NUMBER;
        v_account_number  VARCHAR2(20);
        v_ledger_balance  NUMBER;
        v_calc_balance    NUMBER;
        v_difference      NUMBER;

        CURSOR c_accounts IS
            SELECT account_id, account_number, balance
            FROM   accounts
            WHERE  status != 'CLOSED'
            ORDER  BY account_id;
    BEGIN
        p_mismatches_found := 0;
        p_corrected_count  := 0;
        DBMS_OUTPUT.PUT_LINE('Balance Reconciliation: '||TO_CHAR(p_as_of_date,'YYYY-MM-DD'));

        OPEN c_accounts;
        LOOP
            FETCH c_accounts INTO v_account_id, v_account_number, v_ledger_balance;
            EXIT WHEN c_accounts%NOTFOUND;
            BEGIN
                -- Calculate balance from transactions
                SELECT NVL(
                    (SELECT t2.balance_after FROM transactions t2
                     WHERE  t2.account_id = v_account_id
                     AND    t2.status     = 'COMPLETED'
                     AND    TRUNC(t2.transaction_date) <= p_as_of_date
                     ORDER  BY t2.transaction_date DESC, t2.transaction_id DESC
                     FETCH FIRST 1 ROW ONLY),
                    0)
                INTO v_calc_balance FROM DUAL;

                v_difference := ABS(v_ledger_balance - v_calc_balance);

                IF v_difference > 0.01 THEN
                    p_mismatches_found := p_mismatches_found + 1;
                    DBMS_OUTPUT.PUT_LINE('MISMATCH: Acct='||v_account_number||
                        ' Ledger='||v_ledger_balance||
                        ' Calc='||v_calc_balance||
                        ' Diff='||v_difference);

                    INSERT INTO audit_log(table_name,record_id,action,old_values,new_values,changed_by,changed_at)
                    VALUES('ACCOUNTS',v_account_id,'UPDATE',
                           'balance='||v_ledger_balance,
                           'RECON_MISMATCH|calc_balance='||v_calc_balance||
                           '|difference='||v_difference,
                           'RECONCILIATION',SYSTIMESTAMP);
                END IF;
            EXCEPTION WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('ERR reconciling '||v_account_id||': '||SQLERRM);
            END;
        END LOOP;
        CLOSE c_accounts;
        DBMS_OUTPUT.PUT_LINE('Reconciliation Done: mismatches='||p_mismatches_found);
    EXCEPTION WHEN OTHERS THEN
        IF c_accounts%ISOPEN THEN CLOSE c_accounts; END IF;
        RAISE;
    END reconcile_account_balances;

    -- -------------------------------------------------------------------------
    PROCEDURE purge_old_audit_records(p_cutoff_date IN DATE, p_purged_count OUT NUMBER) IS
        v_cutoff_check DATE;
        v_emp_confirm  VARCHAR2(1) := 'Y';
    BEGIN
        -- Safety check: never purge less than 7 years old
        v_cutoff_check := ADD_MONTHS(SYSDATE, -(c_purge_audit_months));
        IF p_cutoff_date > v_cutoff_check THEN
            RAISE_APPLICATION_ERROR(-20500,
                'Purge cutoff date '||TO_CHAR(p_cutoff_date,'YYYY-MM-DD')||
                ' is more recent than '||c_purge_audit_months||' months. Rejected.');
        END IF;

        DBMS_OUTPUT.PUT_LINE('Purging audit records before: '||
            TO_CHAR(p_cutoff_date,'YYYY-MM-DD'));

        DELETE FROM audit_log
        WHERE  TRUNC(changed_at) < p_cutoff_date
        AND    action NOT IN ('DELETE');  -- Preserve delete audit records longer

        p_purged_count := SQL%ROWCOUNT;

        DBMS_OUTPUT.PUT_LINE('Purged '||p_purged_count||' audit records');
        p_batch_log('AUDIT_PURGE',
            'cutoff='||TO_CHAR(p_cutoff_date,'YYYY-MM-DD')||' purged='||p_purged_count);
        COMMIT;
    EXCEPTION WHEN OTHERS THEN ROLLBACK; RAISE;
    END purge_old_audit_records;

    -- -------------------------------------------------------------------------
    PROCEDURE run_nightly_reports(p_report_date IN DATE DEFAULT SYSDATE) IS
        v_dummy SYS_REFCURSOR;
    BEGIN
        DBMS_OUTPUT.PUT_LINE('Nightly Reports: '||TO_CHAR(p_report_date,'YYYY-MM-DD'));
        -- In a real system these would write to report tables
        -- Here we open/close ref cursors to validate queries execute
        BEGIN
            pkg_reporting.generate_delinquency_report(p_report_date, v_dummy);
            CLOSE v_dummy;
            DBMS_OUTPUT.PUT_LINE('  Delinquency report: OK');
        EXCEPTION WHEN OTHERS THEN
            IF v_dummy%ISOPEN THEN CLOSE v_dummy; END IF;
            DBMS_OUTPUT.PUT_LINE('  Delinquency report ERR: '||SQLERRM);
        END;

        p_batch_log('NIGHTLY_REPORTS','date='||TO_CHAR(p_report_date,'YYYY-MM-DD')||' done');
    END run_nightly_reports;

    -- -------------------------------------------------------------------------
    PROCEDURE reprocess_failed_transactions(
        p_from_date     IN  DATE,
        p_reprocessed   OUT NUMBER,
        p_still_failed  OUT NUMBER
    ) IS
        v_txn_id      NUMBER;
        v_account_id  NUMBER;
        v_amount      NUMBER;
        v_txn_type    VARCHAR2(30);
        v_value_date  DATE;

        CURSOR c_failed IS
            SELECT transaction_id, account_id, amount, transaction_type, value_date
            FROM   transactions
            WHERE  status     = 'FAILED'
            AND    value_date >= p_from_date
            AND    value_date < SYSDATE - c_stale_txn_days
            ORDER  BY transaction_id;
    BEGIN
        p_reprocessed  := 0;
        p_still_failed := 0;
        DBMS_OUTPUT.PUT_LINE('Reprocessing failed transactions from: '||
            TO_CHAR(p_from_date,'YYYY-MM-DD'));

        OPEN c_failed;
        LOOP
            FETCH c_failed INTO v_txn_id, v_account_id, v_amount, v_txn_type, v_value_date;
            EXIT WHEN c_failed%NOTFOUND;
            BEGIN
                -- Simply mark as completed if account is still active
                DECLARE v_acct_status VARCHAR2(20);
                BEGIN
                    SELECT status INTO v_acct_status FROM accounts WHERE account_id=v_account_id;
                    IF v_acct_status = 'ACTIVE' THEN
                        UPDATE transactions SET status='COMPLETED' WHERE transaction_id=v_txn_id;
                        p_reprocessed := p_reprocessed + 1;
                        DBMS_OUTPUT.PUT_LINE('  Reprocessed TXN#'||v_txn_id);
                    ELSE
                        p_still_failed := p_still_failed + 1;
                        DBMS_OUTPUT.PUT_LINE('  Cannot reprocess TXN#'||v_txn_id||
                            ' - account status: '||v_acct_status);
                    END IF;
                EXCEPTION WHEN NO_DATA_FOUND THEN
                    p_still_failed := p_still_failed + 1;
                    DBMS_OUTPUT.PUT_LINE('  TXN#'||v_txn_id||' - account not found');
                END;
            EXCEPTION WHEN OTHERS THEN
                p_still_failed := p_still_failed + 1;
                DBMS_OUTPUT.PUT_LINE('  ERR reprocessing TXN#'||v_txn_id||': '||SQLERRM);
            END;
        END LOOP;
        CLOSE c_failed;
        DBMS_OUTPUT.PUT_LINE('Reprocess Done: reprocessed='||p_reprocessed||
            ' still_failed='||p_still_failed);
        COMMIT;
    EXCEPTION WHEN OTHERS THEN
        IF c_failed%ISOPEN THEN CLOSE c_failed; END IF;
        ROLLBACK; RAISE;
    END reprocess_failed_transactions;

END pkg_batch_processing;
/
SHOW ERRORS PACKAGE BODY pkg_batch_processing;

-- =============================================================================
-- PACKAGE 6: PKG_INTEREST_ENGINE
-- Complex Interest Calculation and Accrual Engine
-- =============================================================================

CREATE OR REPLACE PACKAGE pkg_interest_engine AS
    c_days_in_year        CONSTANT NUMBER := 365;
    c_days_in_year_leap   CONSTANT NUMBER := 366;
    c_compounding_freq    CONSTANT NUMBER := 12;   -- Monthly
    c_penalty_rate_mult   CONSTANT NUMBER := 1.50; -- 150% of normal rate for penalties

    FUNCTION  calc_compound_interest(
        p_principal IN NUMBER, p_annual_rate IN NUMBER,
        p_periods IN NUMBER, p_frequency IN NUMBER DEFAULT 12) RETURN NUMBER;
    FUNCTION  calc_apy(p_nominal_rate IN NUMBER, p_frequency IN NUMBER DEFAULT 12) RETURN NUMBER;
    FUNCTION  calc_apr(p_nominal_rate IN NUMBER, p_fees IN NUMBER, p_principal IN NUMBER,
                       p_term_months IN NUMBER) RETURN NUMBER;
    FUNCTION  calc_daily_accrual(p_account_id IN NUMBER, p_accrual_date IN DATE DEFAULT SYSDATE)
              RETURN NUMBER;
    FUNCTION  get_effective_rate(p_account_id IN NUMBER) RETURN NUMBER;
    FUNCTION  calc_penalty_interest(p_loan_id IN NUMBER, p_days_overdue IN NUMBER) RETURN NUMBER;
    FUNCTION  is_leap_year(p_year IN NUMBER) RETURN BOOLEAN;
    FUNCTION  days_in_year(p_date IN DATE DEFAULT SYSDATE) RETURN NUMBER;

    PROCEDURE accrue_daily_interest_all(
        p_accrual_date IN DATE DEFAULT SYSDATE,
        p_accrued_count OUT NUMBER, p_total_accrued OUT NUMBER);
    PROCEDURE post_quarterly_interest(
        p_quarter_end IN DATE, p_posted_count OUT NUMBER, p_total_posted OUT NUMBER);
    PROCEDURE adjust_interest_rates(
        p_account_type IN VARCHAR2, p_rate_change IN NUMBER,
        p_effective_date IN DATE DEFAULT SYSDATE,
        p_accounts_updated OUT NUMBER);
    PROCEDURE recalculate_loan_schedule_rate(
        p_loan_id IN NUMBER, p_new_rate IN NUMBER, p_employee_id IN NUMBER,
        p_new_payment OUT NUMBER);
    PROCEDURE generate_interest_accrual_report(
        p_from_date IN DATE, p_to_date IN DATE, p_report OUT SYS_REFCURSOR);
END pkg_interest_engine;
/

CREATE OR REPLACE PACKAGE BODY pkg_interest_engine AS

    FUNCTION is_leap_year(p_year IN NUMBER) RETURN BOOLEAN IS
    BEGIN
        IF MOD(p_year,400) = 0 THEN RETURN TRUE;
        ELSIF MOD(p_year,100) = 0 THEN RETURN FALSE;
        ELSIF MOD(p_year,4) = 0 THEN RETURN TRUE;
        ELSE RETURN FALSE; END IF;
    END is_leap_year;

    FUNCTION days_in_year(p_date IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
        v_year NUMBER;
    BEGIN
        v_year := TO_NUMBER(TO_CHAR(p_date,'YYYY'));
        IF is_leap_year(v_year) THEN RETURN c_days_in_year_leap;
        ELSE RETURN c_days_in_year; END IF;
    END days_in_year;

    -- -------------------------------------------------------------------------
    FUNCTION calc_compound_interest(
        p_principal  IN NUMBER, p_annual_rate IN NUMBER,
        p_periods    IN NUMBER, p_frequency   IN NUMBER DEFAULT 12
    ) RETURN NUMBER IS
        v_rate_per_period NUMBER;
        v_future_value    NUMBER;
        v_interest        NUMBER;
    BEGIN
        IF p_annual_rate = 0 OR p_principal = 0 THEN RETURN 0; END IF;
        v_rate_per_period := (p_annual_rate / 100) / p_frequency;
        v_future_value    := p_principal * POWER(1 + v_rate_per_period, p_periods);
        v_interest        := v_future_value - p_principal;
        RETURN ROUND(GREATEST(v_interest, 0), 2);
    EXCEPTION WHEN OTHERS THEN RETURN 0;
    END calc_compound_interest;

    -- -------------------------------------------------------------------------
    FUNCTION calc_apy(p_nominal_rate IN NUMBER, p_frequency IN NUMBER DEFAULT 12) RETURN NUMBER IS
        v_apy NUMBER;
    BEGIN
        IF p_nominal_rate = 0 THEN RETURN 0; END IF;
        v_apy := POWER(1 + (p_nominal_rate/100)/p_frequency, p_frequency) - 1;
        RETURN ROUND(v_apy * 100, 4);
    EXCEPTION WHEN OTHERS THEN RETURN p_nominal_rate;
    END calc_apy;

    -- -------------------------------------------------------------------------
    FUNCTION calc_apr(
        p_nominal_rate IN NUMBER, p_fees      IN NUMBER,
        p_principal    IN NUMBER, p_term_months IN NUMBER
    ) RETURN NUMBER IS
        v_total_cost NUMBER;
        v_apr        NUMBER;
    BEGIN
        IF p_principal <= 0 OR p_term_months <= 0 THEN RETURN p_nominal_rate; END IF;
        v_total_cost := (p_nominal_rate/100) * p_principal * (p_term_months/12) + NVL(p_fees,0);
        v_apr        := (v_total_cost / p_principal) / (p_term_months/12) * 100;
        RETURN ROUND(v_apr, 4);
    EXCEPTION WHEN OTHERS THEN RETURN p_nominal_rate;
    END calc_apr;

    -- -------------------------------------------------------------------------
    FUNCTION get_effective_rate(p_account_id IN NUMBER) RETURN NUMBER IS
        v_rate  NUMBER;
        v_type  VARCHAR2(20);
    BEGIN
        SELECT at.interest_rate, a.account_type
        INTO   v_rate, v_type
        FROM   accounts a JOIN account_types at ON a.account_type=at.type_code
        WHERE  a.account_id = p_account_id;
        RETURN NVL(v_rate, 0);
    EXCEPTION WHEN NO_DATA_FOUND THEN RETURN 0;
    END get_effective_rate;

    -- -------------------------------------------------------------------------
    FUNCTION calc_daily_accrual(p_account_id IN NUMBER, p_accrual_date IN DATE DEFAULT SYSDATE)
    RETURN NUMBER IS
        v_balance   NUMBER;
        v_rate      NUMBER;
        v_days      NUMBER;
        v_accrual   NUMBER;
    BEGIN
        SELECT NVL(a.balance,0)
        INTO   v_balance
        FROM   accounts a WHERE a.account_id=p_account_id AND a.status='ACTIVE';

        v_rate  := get_effective_rate(p_account_id);
        v_days  := days_in_year(p_accrual_date);

        IF v_rate = 0 OR v_balance <= 0 THEN RETURN 0; END IF;

        v_accrual := ROUND(v_balance * (v_rate/100) / v_days, 6);
        RETURN v_accrual;
    EXCEPTION WHEN NO_DATA_FOUND THEN RETURN 0;
    WHEN OTHERS THEN RETURN 0;
    END calc_daily_accrual;

    -- -------------------------------------------------------------------------
    FUNCTION calc_penalty_interest(p_loan_id IN NUMBER, p_days_overdue IN NUMBER) RETURN NUMBER IS
        v_balance  NUMBER;
        v_rate     NUMBER;
        v_penalty  NUMBER;
    BEGIN
        SELECT outstanding_balance, interest_rate INTO v_balance, v_rate
        FROM   loans WHERE loan_id=p_loan_id AND status='ACTIVE';

        v_penalty := ROUND(v_balance *
                     (v_rate * c_penalty_rate_mult / 100) *
                     (p_days_overdue / c_days_in_year), 2);
        RETURN GREATEST(v_penalty, 0);
    EXCEPTION WHEN NO_DATA_FOUND THEN RETURN 0;
    END calc_penalty_interest;

    -- -------------------------------------------------------------------------
    PROCEDURE accrue_daily_interest_all(
        p_accrual_date  IN  DATE DEFAULT SYSDATE,
        p_accrued_count OUT NUMBER,
        p_total_accrued OUT NUMBER
    ) IS
        v_account_id  NUMBER;
        v_acc_number  VARCHAR2(20);
        v_acc_type    VARCHAR2(20);
        v_balance     NUMBER;
        v_rate        NUMBER;
        v_accrual     NUMBER;

        CURSOR c_accounts IS
            SELECT a.account_id, a.account_number, a.account_type, a.balance,
                   at.interest_rate
            FROM   accounts a JOIN account_types at ON a.account_type=at.type_code
            WHERE  a.status         = 'ACTIVE'
            AND    at.interest_rate > 0
            AND    a.balance        > 0
            ORDER  BY a.account_id;
    BEGIN
        p_accrued_count := 0;
        p_total_accrued := 0;
        DBMS_OUTPUT.PUT_LINE('Daily Accrual: '||TO_CHAR(p_accrual_date,'YYYY-MM-DD'));

        OPEN c_accounts;
        LOOP
            FETCH c_accounts INTO v_account_id, v_acc_number, v_acc_type, v_balance, v_rate;
            EXIT WHEN c_accounts%NOTFOUND;
            BEGIN
                v_accrual := calc_daily_accrual(v_account_id, p_accrual_date);
                IF v_accrual > 0 THEN
                    -- Accumulate to interest_accrued field (not posted yet, just tracking)
                    UPDATE accounts
                    SET    interest_accrued = NVL(interest_accrued,0) + v_accrual,
                           updated_at       = SYSTIMESTAMP
                    WHERE  account_id = v_account_id;

                    p_accrued_count := p_accrued_count + 1;
                    p_total_accrued := p_total_accrued + v_accrual;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('ERR accruing '||v_account_id||': '||SQLERRM);
            END;
        END LOOP;
        CLOSE c_accounts;
        DBMS_OUTPUT.PUT_LINE('Daily Accrual Done: accounts='||p_accrued_count||
            ' total='||ROUND(p_total_accrued,2));
    EXCEPTION WHEN OTHERS THEN
        IF c_accounts%ISOPEN THEN CLOSE c_accounts; END IF;
        RAISE;
    END accrue_daily_interest_all;

    -- -------------------------------------------------------------------------
    PROCEDURE post_quarterly_interest(
        p_quarter_end    IN  DATE,
        p_posted_count   OUT NUMBER,
        p_total_posted   OUT NUMBER
    ) IS
        v_quarter_start  DATE;
        v_account_id     NUMBER;
        v_acc_type       VARCHAR2(20);
        v_balance        NUMBER;
        v_rate           NUMBER;
        v_gross          NUMBER;
        v_net            NUMBER;
        v_tax            NUMBER;
        v_txn_id         NUMBER;
        v_bal_before     NUMBER;
        v_already_posted NUMBER;

        CURSOR c_eligible IS
            SELECT a.account_id, a.account_type, a.balance, at.interest_rate
            FROM   accounts a JOIN account_types at ON a.account_type=at.type_code
            WHERE  a.status         = 'ACTIVE'
            AND    at.interest_rate > 0
            ORDER  BY a.account_id;
    BEGIN
        p_posted_count := 0;
        p_total_posted := 0;

        -- Determine quarter start
        v_quarter_start := TRUNC(p_quarter_end,'Q');
        DBMS_OUTPUT.PUT_LINE('Quarterly Interest Posting: '||
            TO_CHAR(v_quarter_start,'YYYY-MM-DD')||' to '||TO_CHAR(p_quarter_end,'YYYY-MM-DD'));

        OPEN c_eligible;
        LOOP
            FETCH c_eligible INTO v_account_id, v_acc_type, v_balance, v_rate;
            EXIT WHEN c_eligible%NOTFOUND;
            BEGIN
                -- Check if already posted
                SELECT COUNT(*) INTO v_already_posted
                FROM   interest_postings
                WHERE  account_id   = v_account_id
                AND    period_start  = v_quarter_start
                AND    period_end    = p_quarter_end;

                IF v_already_posted > 0 THEN
                    DBMS_OUTPUT.PUT_LINE('  Skip acct '||v_account_id||' - already posted');
                    GOTO next_account;
                END IF;

                -- Calculate quarterly interest
                v_gross := ROUND(v_balance * (v_rate/100) *
                           ((p_quarter_end - v_quarter_start + 1)/c_days_in_year), 2);

                IF v_gross <= 0 THEN GOTO next_account; END IF;

                v_tax       := ROUND(v_gross * 0.30, 2);
                v_net       := v_gross - v_tax;
                v_bal_before := v_balance;

                -- Credit interest
                UPDATE accounts
                SET    balance           = balance + v_net,
                       available_balance = available_balance + v_net,
                       interest_accrued  = 0,
                       updated_at        = SYSTIMESTAMP
                WHERE  account_id = v_account_id;

                -- Record transaction
                INSERT INTO transactions(account_id,transaction_type,amount,
                    balance_before,balance_after,description,reference_number,channel,status)
                VALUES(v_account_id,'INTEREST',v_net,
                    v_bal_before, v_bal_before+v_net,
                    'Quarterly interest Q'||TO_CHAR(v_quarter_start,'Q')||
                    '-'||TO_CHAR(v_quarter_start,'YYYY')||
                    ' Gross='||v_gross||' Tax='||v_tax,
                    'QINT-'||v_account_id||'-'||TO_CHAR(p_quarter_end,'YYYYMMDD'),
                    'SYSTEM','COMPLETED')
                RETURNING transaction_id INTO v_txn_id;

                -- Record posting
                INSERT INTO interest_postings(account_id,posting_date,period_start,period_end,
                    average_balance,interest_rate,gross_interest,tax_withheld,net_interest,transaction_id)
                VALUES(v_account_id,p_quarter_end,v_quarter_start,p_quarter_end,
                    v_balance,v_rate,v_gross,v_tax,v_net,v_txn_id);

                p_posted_count := p_posted_count + 1;
                p_total_posted := p_total_posted + v_net;

                <<next_account>> NULL;
            EXCEPTION WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('ERR posting interest acct '||v_account_id||': '||SQLERRM);
            END;
        END LOOP;
        CLOSE c_eligible;
        DBMS_OUTPUT.PUT_LINE('Quarterly Interest Done: posted='||p_posted_count||
            ' total='||ROUND(p_total_posted,2));
        COMMIT;
    EXCEPTION WHEN OTHERS THEN
        IF c_eligible%ISOPEN THEN CLOSE c_eligible; END IF;
        ROLLBACK; RAISE;
    END post_quarterly_interest;

    -- -------------------------------------------------------------------------
    PROCEDURE adjust_interest_rates(
        p_account_type    IN  VARCHAR2,
        p_rate_change     IN  NUMBER,
        p_effective_date  IN  DATE DEFAULT SYSDATE,
        p_accounts_updated OUT NUMBER
    ) IS
        v_old_rate    NUMBER;
        v_new_rate    NUMBER;
        v_type_name   VARCHAR2(100);
    BEGIN
        IF ABS(p_rate_change) > 5 THEN
            RAISE_APPLICATION_ERROR(-20600,'Rate change exceeds maximum of 5%: '||p_rate_change);
        END IF;

        BEGIN
            SELECT interest_rate, type_name INTO v_old_rate, v_type_name
            FROM   account_types WHERE type_code=p_account_type;
        EXCEPTION WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20601,'Account type not found: '||p_account_type);
        END;

        v_new_rate := ROUND(v_old_rate + p_rate_change, 4);

        IF v_new_rate < 0 THEN
            RAISE_APPLICATION_ERROR(-20602,'Resulting rate cannot be negative: '||v_new_rate);
        END IF;

        UPDATE account_types SET interest_rate=v_new_rate WHERE type_code=p_account_type;

        SELECT COUNT(*) INTO p_accounts_updated
        FROM   accounts WHERE account_type=p_account_type AND status='ACTIVE';

        INSERT INTO audit_log(table_name,record_id,action,old_values,new_values,changed_by,changed_at)
        VALUES('ACCOUNT_TYPES',-1,'UPDATE',
               'type='||p_account_type||',rate='||v_old_rate,
               'type='||p_account_type||',rate='||v_new_rate||
               ',change='||p_rate_change||',effective='||TO_CHAR(p_effective_date,'YYYY-MM-DD'),
               SYS_CONTEXT('USERENV','SESSION_USER'),SYSTIMESTAMP);

        DBMS_OUTPUT.PUT_LINE('Rate adjusted: '||v_type_name||' '||v_old_rate||'% -> '||
            v_new_rate||'% (change='||p_rate_change||'%) affects '||p_accounts_updated||' accounts');
        COMMIT;
    EXCEPTION WHEN OTHERS THEN ROLLBACK; RAISE;
    END adjust_interest_rates;

    -- -------------------------------------------------------------------------
    PROCEDURE recalculate_loan_schedule_rate(
        p_loan_id     IN  NUMBER, p_new_rate  IN  NUMBER,
        p_employee_id IN  NUMBER, p_new_payment OUT NUMBER
    ) IS
        v_loan loans%ROWTYPE;
    BEGIN
        SELECT * INTO v_loan FROM loans WHERE loan_id=p_loan_id AND status='ACTIVE' FOR UPDATE;

        IF p_new_rate <= 0 OR p_new_rate > 50 THEN
            RAISE_APPLICATION_ERROR(-20610,'Invalid rate: '||p_new_rate);
        END IF;

        p_new_payment := pkg_loan_mgmt.calc_monthly_payment(
            v_loan.outstanding_balance, p_new_rate,
            v_loan.term_months - MONTHS_BETWEEN(SYSDATE, v_loan.disbursement_date));

        UPDATE loans SET interest_rate=p_new_rate, monthly_payment=p_new_payment,
               updated_at=SYSTIMESTAMP WHERE loan_id=p_loan_id;

        pkg_loan_mgmt.generate_amortization_schedule(p_loan_id, SYSDATE);

        INSERT INTO audit_log(table_name,record_id,action,old_values,new_values,changed_by,changed_at)
        VALUES('LOANS',p_loan_id,'UPDATE',
               'rate='||v_loan.interest_rate||',payment='||v_loan.monthly_payment,
               'rate='||p_new_rate||',payment='||p_new_payment||',by='||p_employee_id,
               SYS_CONTEXT('USERENV','SESSION_USER'),SYSTIMESTAMP);

        DBMS_OUTPUT.PUT_LINE('Loan rate updated: '||v_loan.loan_number||
            ' '||v_loan.interest_rate||'% -> '||p_new_rate||'%'||
            ' new payment='||p_new_payment);
        COMMIT;
    EXCEPTION WHEN OTHERS THEN ROLLBACK; RAISE;
    END recalculate_loan_schedule_rate;

    -- -------------------------------------------------------------------------
    PROCEDURE generate_interest_accrual_report(
        p_from_date IN DATE, p_to_date IN DATE, p_report OUT SYS_REFCURSOR
    ) IS
    BEGIN
        OPEN p_report FOR
            SELECT
                a.account_type,
                at.type_name,
                at.interest_rate                                   AS current_rate,
                pkg_interest_engine.calc_apy(at.interest_rate,12)  AS apy,
                COUNT(ip.posting_id)                               AS postings_count,
                COUNT(DISTINCT ip.account_id)                      AS accounts_posted,
                ROUND(SUM(ip.gross_interest),2)                    AS total_gross_interest,
                ROUND(SUM(ip.tax_withheld),2)                      AS total_tax_withheld,
                ROUND(SUM(ip.net_interest),2)                      AS total_net_interest,
                ROUND(AVG(ip.average_balance),2)                   AS avg_balance_posted,
                ROUND(SUM(ip.gross_interest)/NULLIF(SUM(ip.average_balance),0)*100,4)
                                                                   AS effective_yield_pct,
                MIN(ip.posting_date)                               AS first_posting,
                MAX(ip.posting_date)                               AS last_posting
            FROM   interest_postings ip
            JOIN   accounts     a  ON ip.account_id  = a.account_id
            JOIN   account_types at ON a.account_type = at.type_code
            WHERE  ip.posting_date BETWEEN p_from_date AND p_to_date
            GROUP  BY a.account_type, at.type_name, at.interest_rate
            ORDER  BY total_net_interest DESC;
    END generate_interest_accrual_report;

END pkg_interest_engine;
/
SHOW ERRORS PACKAGE BODY pkg_interest_engine;

-- =============================================================================
-- PACKAGE 7: PKG_RISK_SCORING
-- Customer and Portfolio Risk Scoring Engine
-- =============================================================================

CREATE OR REPLACE PACKAGE pkg_risk_scoring AS
    c_score_high_threshold   CONSTANT NUMBER := 70;
    c_score_medium_threshold CONSTANT NUMBER := 40;
    c_score_review_flag      CONSTANT NUMBER := 85;
    c_max_score              CONSTANT NUMBER := 100;

    FUNCTION  calc_behavioral_score(p_customer_id IN NUMBER) RETURN NUMBER;
    FUNCTION  calc_transaction_risk(p_transaction_id IN NUMBER) RETURN NUMBER;
    FUNCTION  calc_portfolio_concentration(p_branch_id IN NUMBER DEFAULT NULL) RETURN NUMBER;
    FUNCTION  get_customer_overall_risk(p_customer_id IN NUMBER) RETURN VARCHAR2;
    FUNCTION  count_high_risk_customers(p_branch_id IN NUMBER DEFAULT NULL) RETURN NUMBER;
    FUNCTION  calc_expected_loss(p_loan_id IN NUMBER) RETURN NUMBER;

    PROCEDURE recalculate_all_risk_scores(
        p_branch_id IN NUMBER DEFAULT NULL,
        p_processed OUT NUMBER, p_updated OUT NUMBER, p_escalated OUT NUMBER);
    PROCEDURE flag_anomalous_transactions(
        p_from_date IN DATE, p_to_date IN DATE,
        p_flagged_count OUT NUMBER);
    PROCEDURE generate_portfolio_risk_summary(
        p_as_of_date IN DATE DEFAULT SYSDATE, p_report OUT SYS_REFCURSOR);
    PROCEDURE generate_customer_risk_profile(
        p_customer_id IN NUMBER, p_report OUT SYS_REFCURSOR);
    PROCEDURE run_stress_test_scenario(
        p_scenario IN VARCHAR2,
        p_rate_shock IN NUMBER DEFAULT 0,
        p_default_rate_increase IN NUMBER DEFAULT 0,
        p_report OUT SYS_REFCURSOR);
END pkg_risk_scoring;
/

CREATE OR REPLACE PACKAGE BODY pkg_risk_scoring AS

    PROCEDURE p_risk_log(p_customer_id IN NUMBER, p_event IN VARCHAR2, p_detail IN VARCHAR2) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO audit_log(table_name,record_id,action,new_values,changed_by,changed_at)
        VALUES('RISK_ENGINE',p_customer_id,'UPDATE',
               'EVENT='||p_event||'|'||SUBSTR(p_detail,1,3000),
               'RISK_ENGINE',SYSTIMESTAMP);
        COMMIT;
    EXCEPTION WHEN OTHERS THEN NULL;
    END p_risk_log;

    -- -------------------------------------------------------------------------
    FUNCTION calc_behavioral_score(p_customer_id IN NUMBER) RETURN NUMBER IS
        v_txn_count_90d   NUMBER := 0;
        v_avg_txn_amt     NUMBER := 0;
        v_nsf_count       NUMBER := 0;
        v_return_count    NUMBER := 0;
        v_channel_variety NUMBER := 0;
        v_off_hour_txns   NUMBER := 0;
        v_score           NUMBER := 0;
        v_base            NUMBER := 20;
    BEGIN
        SELECT COUNT(t.transaction_id),
               NVL(AVG(t.amount),0),
               COUNT(CASE WHEN t.transaction_type='REVERSAL' THEN 1 END),
               COUNT(DISTINCT t.channel),
               COUNT(CASE WHEN TO_NUMBER(TO_CHAR(t.transaction_date,'HH24')) BETWEEN 0 AND 5
                          THEN 1 END)
        INTO   v_txn_count_90d, v_avg_txn_amt, v_return_count, v_channel_variety, v_off_hour_txns
        FROM   transactions t
        JOIN   accounts a ON t.account_id=a.account_id
        WHERE  a.customer_id        = p_customer_id
        AND    t.transaction_date   >= SYSDATE - 90
        AND    t.status             = 'COMPLETED';

        SELECT COUNT(*) INTO v_nsf_count
        FROM   fee_ledger fl
        JOIN   accounts a ON fl.account_id=a.account_id
        WHERE  a.customer_id = p_customer_id
        AND    fl.fee_type   = 'NSF_FEE'
        AND    fl.fee_date   >= SYSDATE - 90;

        -- Low transaction activity = higher behavioral risk
        IF    v_txn_count_90d = 0   THEN v_score := v_score + 20;
        ELSIF v_txn_count_90d < 5   THEN v_score := v_score + 10;
        ELSIF v_txn_count_90d > 100 THEN v_score := v_score + 5;   -- Too many txns
        END IF;

        -- NSF fees = payment problems
        IF    v_nsf_count >= 5 THEN v_score := v_score + 25;
        ELSIF v_nsf_count >= 3 THEN v_score := v_score + 15;
        ELSIF v_nsf_count >= 1 THEN v_score := v_score + 8; END IF;

        -- Reversals indicate disputes
        IF    v_return_count >= 5 THEN v_score := v_score + 15;
        ELSIF v_return_count >= 2 THEN v_score := v_score + 8; END IF;

        -- Off-hours transactions can indicate fraud
        IF v_off_hour_txns > 10 THEN v_score := v_score + 10;
        ELSIF v_off_hour_txns > 5 THEN v_score := v_score + 5; END IF;

        RETURN LEAST(v_base + v_score, c_max_score);
    EXCEPTION WHEN OTHERS THEN RETURN 50;
    END calc_behavioral_score;

    -- -------------------------------------------------------------------------
    FUNCTION calc_transaction_risk(p_transaction_id IN NUMBER) RETURN NUMBER IS
        v_amount      NUMBER;
        v_txn_type    VARCHAR2(30);
        v_channel     VARCHAR2(20);
        v_account_id  NUMBER;
        v_customer_id NUMBER;
        v_cust_risk   VARCHAR2(10);
        v_txn_hour    NUMBER;
        v_score       NUMBER := 0;
    BEGIN
        SELECT t.amount, t.transaction_type, t.channel,
               t.account_id, a.customer_id,
               TO_NUMBER(TO_CHAR(t.transaction_date,'HH24'))
        INTO   v_amount, v_txn_type, v_channel,
               v_account_id, v_customer_id, v_txn_hour
        FROM   transactions t JOIN accounts a ON t.account_id=a.account_id
        WHERE  t.transaction_id=p_transaction_id;

        SELECT NVL(risk_level,'MEDIUM') INTO v_cust_risk
        FROM   customers WHERE customer_id=v_customer_id;

        -- Amount-based risk
        IF    v_amount >= 50000 THEN v_score := v_score + 30;
        ELSIF v_amount >= 10000 THEN v_score := v_score + 20;
        ELSIF v_amount >= 5000  THEN v_score := v_score + 10;
        ELSIF v_amount >= 1000  THEN v_score := v_score + 5; END IF;

        -- Transaction type risk
        IF v_txn_type IN ('TRANSFER_OUT','WITHDRAWAL') THEN v_score := v_score + 10; END IF;

        -- Channel risk
        IF    v_channel = 'API'    THEN v_score := v_score + 15;
        ELSIF v_channel = 'ONLINE' THEN v_score := v_score + 5;
        ELSIF v_channel = 'ATM'    THEN v_score := v_score + 8; END IF;

        -- Off hours
        IF v_txn_hour BETWEEN 0 AND 5 THEN v_score := v_score + 10; END IF;

        -- Customer risk
        IF    v_cust_risk = 'HIGH'   THEN v_score := v_score + 20;
        ELSIF v_cust_risk = 'MEDIUM' THEN v_score := v_score + 10; END IF;

        RETURN LEAST(v_score, c_max_score);
    EXCEPTION WHEN NO_DATA_FOUND THEN RETURN 50;
    WHEN OTHERS THEN RETURN 50;
    END calc_transaction_risk;

    -- -------------------------------------------------------------------------
    FUNCTION calc_portfolio_concentration(p_branch_id IN NUMBER DEFAULT NULL) RETURN NUMBER IS
        v_total_loans     NUMBER;
        v_max_single_type NUMBER;
        v_concentration   NUMBER;
    BEGIN
        SELECT NVL(SUM(outstanding_balance),0)
        INTO   v_total_loans
        FROM   loans WHERE status='ACTIVE'
        AND    (p_branch_id IS NULL OR branch_id=p_branch_id);

        SELECT NVL(MAX(type_total),0)
        INTO   v_max_single_type
        FROM   (SELECT loan_type, SUM(outstanding_balance) AS type_total
                FROM   loans WHERE status='ACTIVE'
                AND    (p_branch_id IS NULL OR branch_id=p_branch_id)
                GROUP  BY loan_type);

        IF v_total_loans = 0 THEN RETURN 0; END IF;
        v_concentration := ROUND(v_max_single_type / v_total_loans * 100, 2);
        RETURN v_concentration;
    EXCEPTION WHEN OTHERS THEN RETURN 0;
    END calc_portfolio_concentration;

    -- -------------------------------------------------------------------------
    FUNCTION get_customer_overall_risk(p_customer_id IN NUMBER) RETURN VARCHAR2 IS
        v_kyc_score       NUMBER;
        v_behavioral_score NUMBER;
        v_aml_score       NUMBER;
        v_composite       NUMBER;
    BEGIN
        v_kyc_score        := pkg_kyc_verification.calculate_kyc_risk_score(p_customer_id);
        v_behavioral_score := calc_behavioral_score(p_customer_id);
        v_aml_score        := pkg_aml_compliance.calculate_aml_risk_score(p_customer_id);

        v_composite := ROUND((v_kyc_score * 0.30 + v_behavioral_score * 0.40 +
                               v_aml_score * 0.30), 0);

        IF    v_composite >= c_score_high_threshold   THEN RETURN 'HIGH';
        ELSIF v_composite >= c_score_medium_threshold THEN RETURN 'MEDIUM';
        ELSE                                               RETURN 'LOW'; END IF;
    EXCEPTION WHEN OTHERS THEN RETURN 'UNKNOWN';
    END get_customer_overall_risk;

    -- -------------------------------------------------------------------------
    FUNCTION count_high_risk_customers(p_branch_id IN NUMBER DEFAULT NULL) RETURN NUMBER IS
        v_count NUMBER := 0;
    BEGIN
        SELECT COUNT(DISTINCT c.customer_id) INTO v_count
        FROM   customers c JOIN accounts a ON c.customer_id=a.customer_id
        WHERE  c.risk_level = 'HIGH' AND c.is_active='Y'
        AND    (p_branch_id IS NULL OR a.branch_id=p_branch_id);
        RETURN NVL(v_count,0);
    END count_high_risk_customers;

    -- -------------------------------------------------------------------------
    FUNCTION calc_expected_loss(p_loan_id IN NUMBER) RETURN NUMBER IS
        v_balance  NUMBER;
        v_dpd      NUMBER;
        v_pd       NUMBER;   -- Probability of Default
        v_lgd      NUMBER;   -- Loss Given Default
        v_ead      NUMBER;   -- Exposure at Default
        v_el       NUMBER;   -- Expected Loss
        v_loan_type VARCHAR2(30);
    BEGIN
        SELECT outstanding_balance, days_past_due, loan_type
        INTO   v_balance, v_dpd, v_loan_type
        FROM   loans WHERE loan_id=p_loan_id;

        v_ead := v_balance;

        -- PD based on DPD
        IF    v_dpd >= 180 THEN v_pd := 0.90;
        ELSIF v_dpd >= 90  THEN v_pd := 0.60;
        ELSIF v_dpd >= 60  THEN v_pd := 0.30;
        ELSIF v_dpd >= 30  THEN v_pd := 0.15;
        ELSIF v_dpd >= 1   THEN v_pd := 0.05;
        ELSE                    v_pd := 0.01; END IF;

        -- LGD based on loan type and collateral
        v_lgd := CASE v_loan_type
            WHEN 'MORTGAGE' THEN 0.25
            WHEN 'AUTO'     THEN 0.35
            WHEN 'HELOC'    THEN 0.30
            WHEN 'BUSINESS' THEN 0.50
            WHEN 'PERSONAL' THEN 0.75
            WHEN 'STUDENT'  THEN 0.60
            ELSE 0.65 END;

        v_el := ROUND(v_pd * v_lgd * v_ead, 2);
        RETURN v_el;
    EXCEPTION WHEN NO_DATA_FOUND THEN RETURN 0;
    END calc_expected_loss;

    -- -------------------------------------------------------------------------
    PROCEDURE recalculate_all_risk_scores(
        p_branch_id  IN  NUMBER DEFAULT NULL,
        p_processed  OUT NUMBER,
        p_updated    OUT NUMBER,
        p_escalated  OUT NUMBER
    ) IS
        v_customer_id  NUMBER;
        v_cust_code    VARCHAR2(20);
        v_old_risk     VARCHAR2(10);
        v_new_risk     VARCHAR2(10);
        v_composite    NUMBER;

        CURSOR c_customers IS
            SELECT DISTINCT c.customer_id, c.customer_code, c.risk_level
            FROM   customers c JOIN accounts a ON c.customer_id=a.customer_id
            WHERE  c.is_active = 'Y'
            AND    (p_branch_id IS NULL OR a.branch_id=p_branch_id)
            ORDER  BY c.customer_id;
    BEGIN
        p_processed := 0; p_updated := 0; p_escalated := 0;
        DBMS_OUTPUT.PUT_LINE('Risk Score Recalculation Start: '||
            TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS'));

        OPEN c_customers;
        LOOP
            FETCH c_customers INTO v_customer_id, v_cust_code, v_old_risk;
            EXIT WHEN c_customers%NOTFOUND;
            p_processed := p_processed + 1;
            BEGIN
                v_new_risk := get_customer_overall_risk(v_customer_id);

                IF v_new_risk != NVL(v_old_risk,'LOW') THEN
                    UPDATE customers SET risk_level=v_new_risk, updated_at=SYSTIMESTAMP
                    WHERE  customer_id=v_customer_id;
                    p_updated := p_updated + 1;

                    DBMS_OUTPUT.PUT_LINE('Risk Changed: '||v_cust_code||
                        ' ['||v_old_risk||'->'||v_new_risk||']');

                    IF v_new_risk='HIGH' AND NVL(v_old_risk,'LOW')!='HIGH' THEN
                        p_escalated := p_escalated + 1;
                        p_risk_log(v_customer_id,'RISK_ESCALATED',
                            'old='||v_old_risk||' new=HIGH cust='||v_cust_code);
                    END IF;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('ERR scoring '||v_customer_id||': '||SQLERRM);
            END;
        END LOOP;
        CLOSE c_customers;
        DBMS_OUTPUT.PUT_LINE('Risk Recalc Done: processed='||p_processed||
            ' updated='||p_updated||' escalated='||p_escalated);
        COMMIT;
    EXCEPTION WHEN OTHERS THEN
        IF c_customers%ISOPEN THEN CLOSE c_customers; END IF;
        ROLLBACK; RAISE;
    END recalculate_all_risk_scores;

    -- -------------------------------------------------------------------------
    PROCEDURE flag_anomalous_transactions(
        p_from_date     IN  DATE,
        p_to_date       IN  DATE,
        p_flagged_count OUT NUMBER
    ) IS
        v_txn_id       NUMBER;
        v_account_id   NUMBER;
        v_customer_id  NUMBER;
        v_amount       NUMBER;
        v_risk_score   NUMBER;
        v_alert_id     NUMBER;

        CURSOR c_txns IS
            SELECT t.transaction_id, t.account_id, a.customer_id, t.amount
            FROM   transactions t JOIN accounts a ON t.account_id=a.account_id
            WHERE  TRUNC(t.transaction_date) BETWEEN p_from_date AND p_to_date
            AND    t.status       = 'COMPLETED'
            AND    t.amount       >= 1000
            AND    NOT EXISTS (
                SELECT 1 FROM fraud_alerts fa
                WHERE  fa.transaction_id = t.transaction_id AND fa.status='OPEN')
            ORDER  BY t.amount DESC;
    BEGIN
        p_flagged_count := 0;
        DBMS_OUTPUT.PUT_LINE('Anomalous Transaction Scan: '||
            TO_CHAR(p_from_date,'YYYY-MM-DD')||' to '||TO_CHAR(p_to_date,'YYYY-MM-DD'));

        OPEN c_txns;
        LOOP
            FETCH c_txns INTO v_txn_id, v_account_id, v_customer_id, v_amount;
            EXIT WHEN c_txns%NOTFOUND;
            BEGIN
                v_risk_score := calc_transaction_risk(v_txn_id);
                IF v_risk_score >= c_score_review_flag THEN
                    INSERT INTO fraud_alerts(account_id,customer_id,transaction_id,
                        alert_type,severity,description,status,created_at)
                    VALUES(v_account_id,v_customer_id,v_txn_id,
                        'ANOMALOUS_TRANSACTION',
                        CASE WHEN v_risk_score>=90 THEN 'CRITICAL'
                             WHEN v_risk_score>=75 THEN 'HIGH' ELSE 'MEDIUM' END,
                        'Risk score='||v_risk_score||' amount='||v_amount,
                        'OPEN',SYSTIMESTAMP)
                    RETURNING alert_id INTO v_alert_id;
                    p_flagged_count := p_flagged_count + 1;
                    DBMS_OUTPUT.PUT_LINE('Flagged TXN#'||v_txn_id||
                        ' score='||v_risk_score||' amt='||v_amount);
                END IF;
            EXCEPTION WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('ERR scanning TXN#'||v_txn_id||': '||SQLERRM);
            END;
        END LOOP;
        CLOSE c_txns;
        DBMS_OUTPUT.PUT_LINE('Anomaly Scan Done: flagged='||p_flagged_count);
        COMMIT;
    EXCEPTION WHEN OTHERS THEN
        IF c_txns%ISOPEN THEN CLOSE c_txns; END IF;
        ROLLBACK; RAISE;
    END flag_anomalous_transactions;

    -- -------------------------------------------------------------------------
    PROCEDURE generate_portfolio_risk_summary(
        p_as_of_date IN DATE DEFAULT SYSDATE, p_report OUT SYS_REFCURSOR
    ) IS
    BEGIN
        OPEN p_report FOR
            SELECT
                b.branch_name,
                c.risk_level,
                COUNT(DISTINCT c.customer_id)              AS customer_count,
                COUNT(DISTINCT a.account_id)               AS account_count,
                ROUND(SUM(a.balance),2)                    AS total_deposits,
                COUNT(DISTINCT l.loan_id)                  AS loan_count,
                ROUND(NVL(SUM(l.outstanding_balance),0),2) AS total_loans,
                ROUND(AVG(c.credit_score),0)               AS avg_credit_score,
                COUNT(CASE WHEN fa.status='OPEN' THEN fa.alert_id END)
                                                           AS open_alerts,
                COUNT(CASE WHEN l.days_past_due >= 30 THEN l.loan_id END)
                                                           AS loans_30dpd_plus,
                ROUND(COUNT(CASE WHEN l.days_past_due>=30 THEN l.loan_id END)/
                      NULLIF(COUNT(DISTINCT l.loan_id),0)*100,2)
                                                           AS delinquency_rate_pct,
                p_as_of_date                               AS report_date
            FROM   customers c
            JOIN   accounts  a  ON c.customer_id  = a.customer_id
            JOIN   branches  b  ON a.branch_id    = b.branch_id
            LEFT JOIN loans  l  ON c.customer_id  = l.customer_id AND l.status='ACTIVE'
            LEFT JOIN fraud_alerts fa ON c.customer_id = fa.customer_id
            WHERE  c.is_active = 'Y'
            AND    a.status   != 'CLOSED'
            GROUP  BY b.branch_name, c.risk_level
            ORDER  BY DECODE(c.risk_level,'HIGH',1,'MEDIUM',2,'LOW',3,4), b.branch_name;
    END generate_portfolio_risk_summary;

    -- -------------------------------------------------------------------------
    PROCEDURE generate_customer_risk_profile(
        p_customer_id IN NUMBER, p_report OUT SYS_REFCURSOR
    ) IS
    BEGIN
        OPEN p_report FOR
            SELECT
                c.customer_id,
                c.customer_code,
                c.first_name||' '||c.last_name              AS customer_name,
                c.customer_type,
                c.risk_level                                 AS current_risk_level,
                c.credit_score,
                c.kyc_status,
                pkg_kyc_verification.calculate_kyc_risk_score(c.customer_id)    AS kyc_risk_score,
                pkg_risk_scoring.calc_behavioral_score(c.customer_id)           AS behavioral_score,
                pkg_aml_compliance.calculate_aml_risk_score(c.customer_id)      AS aml_risk_score,
                pkg_risk_scoring.get_customer_overall_risk(c.customer_id)       AS composite_risk,
                COUNT(DISTINCT a.account_id)                 AS total_accounts,
                NVL(SUM(a.balance),0)                        AS total_deposits,
                COUNT(DISTINCT l.loan_id)                    AS active_loans,
                NVL(SUM(l.outstanding_balance),0)            AS total_loan_exposure,
                NVL(SUM(l.outstanding_balance),0)-NVL(SUM(a.balance),0) AS net_exposure,
                COUNT(DISTINCT fa.alert_id)                  AS total_fraud_alerts,
                COUNT(CASE WHEN fa.status='OPEN' THEN 1 END) AS open_fraud_alerts
            FROM   customers c
            LEFT JOIN accounts a ON c.customer_id=a.customer_id AND a.status='ACTIVE'
            LEFT JOIN loans    l ON c.customer_id=l.customer_id AND l.status='ACTIVE'
            LEFT JOIN fraud_alerts fa ON c.customer_id=fa.customer_id
            WHERE  c.customer_id = p_customer_id
            GROUP  BY c.customer_id, c.customer_code, c.first_name, c.last_name,
                      c.customer_type, c.risk_level, c.credit_score, c.kyc_status;
    END generate_customer_risk_profile;

    -- -------------------------------------------------------------------------
    PROCEDURE run_stress_test_scenario(
        p_scenario               IN  VARCHAR2,
        p_rate_shock             IN  NUMBER DEFAULT 0,
        p_default_rate_increase  IN  NUMBER DEFAULT 0,
        p_report                 OUT SYS_REFCURSOR
    ) IS
    BEGIN
        IF p_scenario NOT IN ('RATE_SHOCK','RECESSION','CREDIT_CRUNCH','LIQUIDITY_CRISIS') THEN
            RAISE_APPLICATION_ERROR(-20700,'Unknown stress scenario: '||p_scenario);
        END IF;

        OPEN p_report FOR
            SELECT
                p_scenario                                                AS scenario,
                l.loan_type,
                COUNT(*)                                                  AS loan_count,
                ROUND(SUM(l.outstanding_balance),2)                      AS current_exposure,
                -- Stressed interest income impact
                ROUND(SUM(l.outstanding_balance * (p_rate_shock/100)),2) AS rate_shock_impact,
                -- Stressed default losses (EL * default rate multiplier)
                ROUND(SUM(pkg_risk_scoring.calc_expected_loss(l.loan_id) *
                          (1 + p_default_rate_increase/100)),2)           AS stressed_expected_loss,
                -- Current NPL
                ROUND(SUM(CASE WHEN l.days_past_due>=90
                          THEN l.outstanding_balance ELSE 0 END),2)      AS current_npl,
                -- Stressed NPL (assume 2x for recession, 3x for credit crunch)
                ROUND(SUM(CASE WHEN l.days_past_due>=90
                          THEN l.outstanding_balance ELSE 0 END) *
                      CASE p_scenario WHEN 'RECESSION' THEN 2.0
                                      WHEN 'CREDIT_CRUNCH' THEN 3.0
                                      ELSE 1.5 END, 2)                   AS stressed_npl,
                ROUND(AVG(l.interest_rate),4)                            AS avg_rate,
                ROUND(AVG(l.interest_rate) + p_rate_shock, 4)           AS stressed_avg_rate,
                SYSDATE                                                   AS test_date
            FROM   loans l
            WHERE  l.status = 'ACTIVE'
            GROUP  BY l.loan_type
            ORDER  BY current_exposure DESC;
    END run_stress_test_scenario;

END pkg_risk_scoring;
/
SHOW ERRORS PACKAGE BODY pkg_risk_scoring;
