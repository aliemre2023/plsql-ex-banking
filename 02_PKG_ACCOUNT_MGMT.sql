-- =============================================================================
-- PACKAGE 1: PKG_ACCOUNT_MGMT
-- Account Management Package
-- Handles: Account creation, maintenance, balance ops, holds, closures
-- =============================================================================

CREATE OR REPLACE PACKAGE pkg_account_mgmt AS

    -- Constants
    c_max_daily_withdrawal  CONSTANT NUMBER := 10000;
    c_max_transfer_limit    CONSTANT NUMBER := 50000;
    c_dormancy_days         CONSTANT NUMBER := 365;
    c_min_balance_warning   CONSTANT NUMBER := 100;

    -- Custom Exceptions
    e_insufficient_funds    EXCEPTION;
    e_account_frozen        EXCEPTION;
    e_account_closed        EXCEPTION;
    e_daily_limit_exceeded  EXCEPTION;
    e_invalid_amount        EXCEPTION;
    e_duplicate_account     EXCEPTION;

    PRAGMA EXCEPTION_INIT(e_insufficient_funds,  -20001);
    PRAGMA EXCEPTION_INIT(e_account_frozen,      -20002);
    PRAGMA EXCEPTION_INIT(e_account_closed,      -20003);
    PRAGMA EXCEPTION_INIT(e_daily_limit_exceeded,-20004);
    PRAGMA EXCEPTION_INIT(e_invalid_amount,      -20005);
    PRAGMA EXCEPTION_INIT(e_duplicate_account,   -20006);

    -- -------------------------------------------------------------------------
    -- FUNCTIONS
    -- -------------------------------------------------------------------------

    -- Returns account balance
    FUNCTION get_balance(p_account_id IN NUMBER) RETURN NUMBER;

    -- Returns available balance (balance - holds)
    FUNCTION get_available_balance(p_account_id IN NUMBER) RETURN NUMBER;

    -- Checks if account exists and is active
    FUNCTION is_account_active(p_account_id IN NUMBER) RETURN BOOLEAN;

    -- Generates unique account number
    FUNCTION generate_account_number(p_branch_code IN VARCHAR2, p_type IN VARCHAR2) RETURN VARCHAR2;

    -- Gets total customer exposure (sum of all accounts)
    FUNCTION get_customer_total_balance(p_customer_id IN NUMBER) RETURN NUMBER;

    -- Calculates minimum required balance for an account type
    FUNCTION get_min_balance(p_account_type IN VARCHAR2) RETURN NUMBER;

    -- Returns daily withdrawal total for an account
    FUNCTION get_daily_withdrawal_total(p_account_id IN NUMBER, p_date IN DATE DEFAULT SYSDATE) RETURN NUMBER;

    -- Returns account status
    FUNCTION get_account_status(p_account_id IN NUMBER) RETURN VARCHAR2;

    -- Checks if account would breach minimum balance after a debit
    FUNCTION check_min_balance_breach(p_account_id IN NUMBER, p_debit_amount IN NUMBER) RETURN BOOLEAN;

    -- Returns count of accounts for a customer
    FUNCTION count_customer_accounts(p_customer_id IN NUMBER, p_status IN VARCHAR2 DEFAULT 'ACTIVE') RETURN NUMBER;

    -- Returns account age in days
    FUNCTION get_account_age_days(p_account_id IN NUMBER) RETURN NUMBER;

    -- -------------------------------------------------------------------------
    -- PROCEDURES
    -- -------------------------------------------------------------------------

    -- Creates a new account
    PROCEDURE create_account(
        p_customer_id   IN  NUMBER,
        p_branch_id     IN  NUMBER,
        p_account_type  IN  VARCHAR2,
        p_initial_deposit IN NUMBER DEFAULT 0,
        p_currency      IN  VARCHAR2 DEFAULT 'USD',
        p_account_id    OUT NUMBER,
        p_account_number OUT VARCHAR2
    );

    -- Updates account balance (internal use - called by transactions)
    PROCEDURE update_balance(
        p_account_id    IN NUMBER,
        p_amount        IN NUMBER,
        p_direction     IN VARCHAR2  -- 'CR' or 'DR'
    );

    -- Places a hold on funds
    PROCEDURE place_hold(
        p_account_id    IN NUMBER,
        p_amount        IN NUMBER,
        p_reason        IN VARCHAR2,
        p_hold_id       OUT NUMBER
    );

    -- Releases a fund hold
    PROCEDURE release_hold(
        p_account_id    IN NUMBER,
        p_amount        IN NUMBER
    );

    -- Freezes an account
    PROCEDURE freeze_account(
        p_account_id    IN NUMBER,
        p_reason        IN VARCHAR2,
        p_employee_id   IN NUMBER
    );

    -- Unfreezes an account
    PROCEDURE unfreeze_account(
        p_account_id    IN NUMBER,
        p_employee_id   IN NUMBER
    );

    -- Closes an account
    PROCEDURE close_account(
        p_account_id    IN NUMBER,
        p_reason        IN VARCHAR2,
        p_employee_id   IN NUMBER,
        p_final_balance OUT NUMBER
    );

    -- Marks dormant accounts (called by scheduler)
    PROCEDURE mark_dormant_accounts;

    -- Reactivates a dormant account
    PROCEDURE reactivate_account(
        p_account_id    IN NUMBER,
        p_employee_id   IN NUMBER
    );

    -- Updates available balance after hold changes
    PROCEDURE sync_available_balance(p_account_id IN NUMBER);

    -- Bulk update account statuses
    PROCEDURE bulk_update_status(
        p_account_ids   IN t_number_list,
        p_new_status    IN VARCHAR2,
        p_reason        IN VARCHAR2,
        p_employee_id   IN NUMBER,
        p_updated_count OUT NUMBER
    );

END pkg_account_mgmt;
/

CREATE OR REPLACE PACKAGE BODY pkg_account_mgmt AS

    -- =========================================================================
    -- PRIVATE HELPER: Write to audit log
    -- =========================================================================
    PROCEDURE p_audit(
        p_table    IN VARCHAR2,
        p_rec_id   IN NUMBER,
        p_action   IN VARCHAR2,
        p_old      IN VARCHAR2 DEFAULT NULL,
        p_new      IN VARCHAR2 DEFAULT NULL
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO audit_log (table_name, record_id, action, old_values, new_values, changed_by, changed_at)
        VALUES (p_table, p_rec_id, p_action, p_old, p_new, SYS_CONTEXT('USERENV','SESSION_USER'), SYSTIMESTAMP);
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN NULL;  -- Never let audit failure break business logic
    END p_audit;

    -- =========================================================================
    -- FUNCTION: get_balance
    -- =========================================================================
    FUNCTION get_balance(p_account_id IN NUMBER) RETURN NUMBER IS
        v_balance NUMBER;
    BEGIN
        SELECT balance INTO v_balance
        FROM   accounts
        WHERE  account_id = p_account_id;
        RETURN NVL(v_balance, 0);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20099, 'Account ' || p_account_id || ' not found');
    END get_balance;

    -- =========================================================================
    -- FUNCTION: get_available_balance
    -- =========================================================================
    FUNCTION get_available_balance(p_account_id IN NUMBER) RETURN NUMBER IS
        v_available NUMBER;
    BEGIN
        SELECT available_balance INTO v_available
        FROM   accounts
        WHERE  account_id = p_account_id;
        RETURN NVL(v_available, 0);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20099, 'Account ' || p_account_id || ' not found');
    END get_available_balance;

    -- =========================================================================
    -- FUNCTION: is_account_active
    -- =========================================================================
    FUNCTION is_account_active(p_account_id IN NUMBER) RETURN BOOLEAN IS
        v_status VARCHAR2(20);
    BEGIN
        SELECT status INTO v_status
        FROM   accounts
        WHERE  account_id = p_account_id;
        RETURN (v_status = 'ACTIVE');
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN FALSE;
    END is_account_active;

    -- =========================================================================
    -- FUNCTION: generate_account_number
    -- =========================================================================
    FUNCTION generate_account_number(p_branch_code IN VARCHAR2, p_type IN VARCHAR2) RETURN VARCHAR2 IS
        v_type_prefix VARCHAR2(3);
        v_seq         NUMBER;
        v_acc_num     VARCHAR2(20);
        v_exists      NUMBER;
    BEGIN
        v_type_prefix := CASE p_type
            WHEN 'CHECKING'  THEN 'CHK'
            WHEN 'SAVINGS'   THEN 'SAV'
            WHEN 'MONEY_MKT' THEN 'MMK'
            WHEN 'CD'        THEN 'CD_'
            WHEN 'BUSINESS'  THEN 'BUS'
            WHEN 'PREMIUM'   THEN 'PRE'
            ELSE 'ACC'
        END;

        LOOP
            SELECT seq_account_id.NEXTVAL INTO v_seq FROM DUAL;
            v_acc_num := v_type_prefix || '-' || LPAD(v_seq, 8, '0');
            SELECT COUNT(*) INTO v_exists FROM accounts WHERE account_number = v_acc_num;
            EXIT WHEN v_exists = 0;
        END LOOP;

        RETURN v_acc_num;
    END generate_account_number;

    -- =========================================================================
    -- FUNCTION: get_customer_total_balance
    -- =========================================================================
    FUNCTION get_customer_total_balance(p_customer_id IN NUMBER) RETURN NUMBER IS
        v_total NUMBER;
    BEGIN
        SELECT NVL(SUM(balance), 0)
        INTO   v_total
        FROM   accounts
        WHERE  customer_id = p_customer_id
        AND    status       = 'ACTIVE';
        RETURN v_total;
    END get_customer_total_balance;

    -- =========================================================================
    -- FUNCTION: get_min_balance
    -- =========================================================================
    FUNCTION get_min_balance(p_account_type IN VARCHAR2) RETURN NUMBER IS
        v_min NUMBER;
    BEGIN
        SELECT NVL(min_balance, 0)
        INTO   v_min
        FROM   account_types
        WHERE  type_code = p_account_type;
        RETURN v_min;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN 0;
    END get_min_balance;

    -- =========================================================================
    -- FUNCTION: get_daily_withdrawal_total
    -- =========================================================================
    FUNCTION get_daily_withdrawal_total(p_account_id IN NUMBER, p_date IN DATE DEFAULT SYSDATE) RETURN NUMBER IS
        v_total NUMBER;
    BEGIN
        SELECT NVL(SUM(amount), 0)
        INTO   v_total
        FROM   transactions
        WHERE  account_id        = p_account_id
        AND    transaction_type  IN ('WITHDRAWAL','TRANSFER_OUT')
        AND    TRUNC(transaction_date) = TRUNC(p_date)
        AND    status            = 'COMPLETED';
        RETURN v_total;
    END get_daily_withdrawal_total;

    -- =========================================================================
    -- FUNCTION: get_account_status
    -- =========================================================================
    FUNCTION get_account_status(p_account_id IN NUMBER) RETURN VARCHAR2 IS
        v_status VARCHAR2(20);
    BEGIN
        SELECT status INTO v_status FROM accounts WHERE account_id = p_account_id;
        RETURN v_status;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN 'NOT_FOUND';
    END get_account_status;

    -- =========================================================================
    -- FUNCTION: check_min_balance_breach
    -- =========================================================================
    FUNCTION check_min_balance_breach(p_account_id IN NUMBER, p_debit_amount IN NUMBER) RETURN BOOLEAN IS
        v_balance     NUMBER;
        v_acc_type    VARCHAR2(20);
        v_min_balance NUMBER;
    BEGIN
        SELECT a.balance, a.account_type, NVL(at.min_balance, 0)
        INTO   v_balance, v_acc_type, v_min_balance
        FROM   accounts a
        JOIN   account_types at ON a.account_type = at.type_code
        WHERE  a.account_id = p_account_id;

        RETURN (v_balance - p_debit_amount) < v_min_balance;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN TRUE;
    END check_min_balance_breach;

    -- =========================================================================
    -- FUNCTION: count_customer_accounts
    -- =========================================================================
    FUNCTION count_customer_accounts(p_customer_id IN NUMBER, p_status IN VARCHAR2 DEFAULT 'ACTIVE') RETURN NUMBER IS
        v_count NUMBER;
    BEGIN
        SELECT COUNT(*)
        INTO   v_count
        FROM   accounts
        WHERE  customer_id = p_customer_id
        AND    (p_status = 'ALL' OR status = p_status);
        RETURN v_count;
    END count_customer_accounts;

    -- =========================================================================
    -- FUNCTION: get_account_age_days
    -- =========================================================================
    FUNCTION get_account_age_days(p_account_id IN NUMBER) RETURN NUMBER IS
        v_opened DATE;
    BEGIN
        SELECT opened_date INTO v_opened FROM accounts WHERE account_id = p_account_id;
        RETURN TRUNC(SYSDATE - v_opened);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN -1;
    END get_account_age_days;

    -- =========================================================================
    -- PROCEDURE: create_account
    -- =========================================================================
    PROCEDURE create_account(
        p_customer_id    IN  NUMBER,
        p_branch_id      IN  NUMBER,
        p_account_type   IN  VARCHAR2,
        p_initial_deposit IN NUMBER DEFAULT 0,
        p_currency       IN  VARCHAR2 DEFAULT 'USD',
        p_account_id     OUT NUMBER,
        p_account_number OUT VARCHAR2
    ) IS
        v_branch_code VARCHAR2(10);
        v_cust_status VARCHAR2(20);
        v_min_balance NUMBER;
        v_type_exists NUMBER;
    BEGIN
        -- Validate customer
        SELECT kyc_status INTO v_cust_status
        FROM   customers
        WHERE  customer_id = p_customer_id AND is_active = 'Y';

        IF v_cust_status NOT IN ('VERIFIED') THEN
            RAISE_APPLICATION_ERROR(-20010, 'Customer KYC not verified');
        END IF;

        -- Validate account type
        SELECT COUNT(*), NVL(MIN(min_balance),0)
        INTO   v_type_exists, v_min_balance
        FROM   account_types
        WHERE  type_code  = p_account_type
        AND    is_active   = 'Y';

        IF v_type_exists = 0 THEN
            RAISE_APPLICATION_ERROR(-20011, 'Invalid account type: ' || p_account_type);
        END IF;

        -- Check initial deposit meets minimum
        IF p_initial_deposit < v_min_balance THEN
            RAISE_APPLICATION_ERROR(-20012,
                'Initial deposit ' || p_initial_deposit ||
                ' is below minimum balance ' || v_min_balance);
        END IF;

        -- Get branch code for account number generation
        SELECT branch_code INTO v_branch_code
        FROM   branches
        WHERE  branch_id  = p_branch_id
        AND    is_active   = 'Y';

        -- Generate account number
        p_account_number := generate_account_number(v_branch_code, p_account_type);

        -- Insert account
        INSERT INTO accounts (
            account_number, customer_id, branch_id, account_type,
            balance, available_balance, currency, status, opened_date
        ) VALUES (
            p_account_number, p_customer_id, p_branch_id, p_account_type,
            p_initial_deposit, p_initial_deposit, p_currency, 'ACTIVE', SYSDATE
        )
        RETURNING account_id INTO p_account_id;

        -- Record initial deposit as transaction if > 0
        IF p_initial_deposit > 0 THEN
            INSERT INTO transactions (
                account_id, transaction_type, amount,
                balance_before, balance_after,
                description, reference_number, channel, status
            ) VALUES (
                p_account_id, 'DEPOSIT', p_initial_deposit,
                0, p_initial_deposit,
                'Initial deposit on account opening',
                'INIT-' || p_account_id || '-' || TO_CHAR(SYSDATE,'YYYYMMDD'),
                'BRANCH', 'COMPLETED'
            );
        END IF;

        -- Audit
        p_audit('ACCOUNTS', p_account_id, 'INSERT',
                NULL,
                'customer_id=' || p_customer_id ||
                ',type=' || p_account_type ||
                ',balance=' || p_initial_deposit);

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20013, 'Customer or Branch not found / inactive');
        WHEN DUP_VAL_ON_INDEX THEN
            RAISE_APPLICATION_ERROR(-20006, 'Duplicate account number generated');
    END create_account;

    -- =========================================================================
    -- PROCEDURE: update_balance
    -- =========================================================================
    PROCEDURE update_balance(
        p_account_id IN NUMBER,
        p_amount     IN NUMBER,
        p_direction  IN VARCHAR2
    ) IS
        v_balance         NUMBER;
        v_avail           NUMBER;
        v_status          VARCHAR2(20);
        v_acc_type        VARCHAR2(20);
        v_overdraft_limit NUMBER;
    BEGIN
        IF p_amount <= 0 THEN
            RAISE_APPLICATION_ERROR(-20005, 'Amount must be positive');
        END IF;

        SELECT a.balance, a.available_balance, a.status, a.account_type,
               NVL(at.overdraft_limit, 0)
        INTO   v_balance, v_avail, v_status, v_acc_type, v_overdraft_limit
        FROM   accounts a
        JOIN   account_types at ON a.account_type = at.type_code
        WHERE  a.account_id = p_account_id
        FOR UPDATE;

        IF v_status = 'CLOSED' THEN
            RAISE_APPLICATION_ERROR(-20003, 'Account is closed');
        END IF;

        IF v_status = 'FROZEN' THEN
            RAISE_APPLICATION_ERROR(-20002, 'Account is frozen');
        END IF;

        IF UPPER(p_direction) = 'DR' THEN
            IF v_avail + v_overdraft_limit < p_amount THEN
                RAISE_APPLICATION_ERROR(-20001,
                    'Insufficient funds. Available: ' || v_avail ||
                    ', Overdraft: ' || v_overdraft_limit ||
                    ', Requested: ' || p_amount);
            END IF;
            UPDATE accounts
            SET    balance               = balance - p_amount,
                   available_balance     = available_balance - p_amount,
                   last_transaction_date = SYSDATE,
                   updated_at            = SYSTIMESTAMP
            WHERE  account_id = p_account_id;
        ELSIF UPPER(p_direction) = 'CR' THEN
            UPDATE accounts
            SET    balance               = balance + p_amount,
                   available_balance     = available_balance + p_amount,
                   last_transaction_date = SYSDATE,
                   updated_at            = SYSTIMESTAMP
            WHERE  account_id = p_account_id;
        ELSE
            RAISE_APPLICATION_ERROR(-20014, 'Invalid direction. Use CR or DR');
        END IF;
    END update_balance;

    -- =========================================================================
    -- PROCEDURE: place_hold
    -- =========================================================================
    PROCEDURE place_hold(
        p_account_id IN NUMBER,
        p_amount     IN NUMBER,
        p_reason     IN VARCHAR2,
        p_hold_id    OUT NUMBER
    ) IS
        v_avail NUMBER;
    BEGIN
        SELECT available_balance INTO v_avail
        FROM   accounts
        WHERE  account_id = p_account_id
        FOR UPDATE;

        IF v_avail < p_amount THEN
            RAISE_APPLICATION_ERROR(-20001, 'Insufficient available balance to place hold');
        END IF;

        UPDATE accounts
        SET    available_balance = available_balance - p_amount,
               hold_amount       = NVL(hold_amount, 0) + p_amount,
               updated_at        = SYSTIMESTAMP
        WHERE  account_id = p_account_id;

        -- Return hold reference (use transaction sequence as hold ID)
        SELECT seq_transaction_id.NEXTVAL INTO p_hold_id FROM DUAL;

        p_audit('ACCOUNTS', p_account_id, 'UPDATE',
                'available=' || v_avail,
                'hold_placed=' || p_amount || ',reason=' || p_reason);
    END place_hold;

    -- =========================================================================
    -- PROCEDURE: release_hold
    -- =========================================================================
    PROCEDURE release_hold(p_account_id IN NUMBER, p_amount IN NUMBER) IS
        v_hold NUMBER;
    BEGIN
        SELECT NVL(hold_amount, 0) INTO v_hold
        FROM   accounts WHERE account_id = p_account_id FOR UPDATE;

        IF v_hold < p_amount THEN
            RAISE_APPLICATION_ERROR(-20015,
                'Hold amount ' || v_hold || ' less than release amount ' || p_amount);
        END IF;

        UPDATE accounts
        SET    available_balance = available_balance + p_amount,
               hold_amount       = hold_amount - p_amount,
               updated_at        = SYSTIMESTAMP
        WHERE  account_id = p_account_id;
    END release_hold;

    -- =========================================================================
    -- PROCEDURE: freeze_account
    -- =========================================================================
    PROCEDURE freeze_account(
        p_account_id  IN NUMBER,
        p_reason      IN VARCHAR2,
        p_employee_id IN NUMBER
    ) IS
        v_old_status VARCHAR2(20);
    BEGIN
        SELECT status INTO v_old_status
        FROM   accounts
        WHERE  account_id = p_account_id
        FOR UPDATE;

        IF v_old_status = 'CLOSED' THEN
            RAISE_APPLICATION_ERROR(-20003, 'Cannot freeze a closed account');
        END IF;

        UPDATE accounts
        SET    status     = 'FROZEN',
               updated_at = SYSTIMESTAMP
        WHERE  account_id = p_account_id;

        p_audit('ACCOUNTS', p_account_id, 'UPDATE',
                'status=' || v_old_status,
                'status=FROZEN,reason=' || p_reason || ',by=' || p_employee_id);
    END freeze_account;

    -- =========================================================================
    -- PROCEDURE: unfreeze_account
    -- =========================================================================
    PROCEDURE unfreeze_account(p_account_id IN NUMBER, p_employee_id IN NUMBER) IS
    BEGIN
        UPDATE accounts
        SET    status     = 'ACTIVE',
               updated_at = SYSTIMESTAMP
        WHERE  account_id = p_account_id
        AND    status      = 'FROZEN';

        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20016, 'Account not frozen or not found');
        END IF;

        p_audit('ACCOUNTS', p_account_id, 'UPDATE',
                'status=FROZEN',
                'status=ACTIVE,unfrozen_by=' || p_employee_id);
    END unfreeze_account;

    -- =========================================================================
    -- PROCEDURE: close_account
    -- =========================================================================
    PROCEDURE close_account(
        p_account_id   IN  NUMBER,
        p_reason       IN  VARCHAR2,
        p_employee_id  IN  NUMBER,
        p_final_balance OUT NUMBER
    ) IS
        v_balance NUMBER;
        v_status  VARCHAR2(20);
        v_holds   NUMBER;
    BEGIN
        SELECT balance, status, NVL(hold_amount, 0)
        INTO   v_balance, v_status, v_holds
        FROM   accounts
        WHERE  account_id = p_account_id
        FOR UPDATE;

        IF v_status = 'CLOSED' THEN
            RAISE_APPLICATION_ERROR(-20003, 'Account already closed');
        END IF;

        IF v_holds > 0 THEN
            RAISE_APPLICATION_ERROR(-20017, 'Cannot close account with active holds: ' || v_holds);
        END IF;

        -- Check no active loans tied to account
        DECLARE
            v_loan_count NUMBER;
        BEGIN
            SELECT COUNT(*) INTO v_loan_count
            FROM   loans
            WHERE  account_id = p_account_id
            AND    status = 'ACTIVE';
            IF v_loan_count > 0 THEN
                RAISE_APPLICATION_ERROR(-20018, 'Cannot close account with active loans');
            END IF;
        END;

        p_final_balance := v_balance;

        -- If balance > 0, create a final withdrawal transaction
        IF v_balance > 0 THEN
            INSERT INTO transactions (
                account_id, transaction_type, amount,
                balance_before, balance_after, description,
                reference_number, channel, status
            ) VALUES (
                p_account_id, 'WITHDRAWAL', v_balance,
                v_balance, 0,
                'Account closure - ' || p_reason,
                'CLOSE-' || p_account_id || '-' || TO_CHAR(SYSDATE,'YYYYMMDD'),
                'BRANCH', 'COMPLETED'
            );
        END IF;

        UPDATE accounts
        SET    status      = 'CLOSED',
               balance     = 0,
               available_balance = 0,
               closed_date = SYSDATE,
               updated_at  = SYSTIMESTAMP
        WHERE  account_id = p_account_id;

        p_audit('ACCOUNTS', p_account_id, 'UPDATE',
                'status=' || v_status || ',balance=' || v_balance,
                'status=CLOSED,reason=' || p_reason || ',closed_by=' || p_employee_id);
    END close_account;

    -- =========================================================================
    -- PROCEDURE: mark_dormant_accounts
    -- =========================================================================
    PROCEDURE mark_dormant_accounts IS
        v_count NUMBER := 0;
    BEGIN
        UPDATE accounts
        SET    status     = 'DORMANT',
               updated_at = SYSTIMESTAMP
        WHERE  status     = 'ACTIVE'
        AND    (last_transaction_date IS NULL AND opened_date < SYSDATE - c_dormancy_days)
            OR (last_transaction_date < SYSDATE - c_dormancy_days);

        v_count := SQL%ROWCOUNT;

        -- Log the operation
        INSERT INTO audit_log (table_name, record_id, action, new_values, changed_by)
        VALUES ('ACCOUNTS', -1, 'UPDATE',
                'Dormancy batch: ' || v_count || ' accounts marked DORMANT on ' || SYSDATE,
                'SYSTEM');

        DBMS_OUTPUT.PUT_LINE('Marked ' || v_count || ' accounts as dormant.');
    END mark_dormant_accounts;

    -- =========================================================================
    -- PROCEDURE: reactivate_account
    -- =========================================================================
    PROCEDURE reactivate_account(p_account_id IN NUMBER, p_employee_id IN NUMBER) IS
        v_status VARCHAR2(20);
    BEGIN
        SELECT status INTO v_status
        FROM   accounts WHERE account_id = p_account_id FOR UPDATE;

        IF v_status NOT IN ('DORMANT','INACTIVE') THEN
            RAISE_APPLICATION_ERROR(-20019,
                'Account cannot be reactivated from status: ' || v_status);
        END IF;

        UPDATE accounts
        SET    status     = 'ACTIVE',
               updated_at = SYSTIMESTAMP
        WHERE  account_id = p_account_id;

        p_audit('ACCOUNTS', p_account_id, 'UPDATE',
                'status=' || v_status,
                'status=ACTIVE,reactivated_by=' || p_employee_id);
    END reactivate_account;

    -- =========================================================================
    -- PROCEDURE: sync_available_balance
    -- =========================================================================
    PROCEDURE sync_available_balance(p_account_id IN NUMBER) IS
    BEGIN
        UPDATE accounts
        SET    available_balance = balance - NVL(hold_amount, 0),
               updated_at        = SYSTIMESTAMP
        WHERE  account_id = p_account_id;
    END sync_available_balance;

    -- =========================================================================
    -- PROCEDURE: bulk_update_status
    -- =========================================================================
    PROCEDURE bulk_update_status(
        p_account_ids   IN  t_number_list,
        p_new_status    IN  VARCHAR2,
        p_reason        IN  VARCHAR2,
        p_employee_id   IN  NUMBER,
        p_updated_count OUT NUMBER
    ) IS
        v_valid_statuses t_varchar_list := t_varchar_list('ACTIVE','INACTIVE','FROZEN','DORMANT');
        v_valid_count    NUMBER;
    BEGIN
        -- Validate status
        SELECT COUNT(*) INTO v_valid_count
        FROM   TABLE(v_valid_statuses)
        WHERE  COLUMN_VALUE = p_new_status;

        IF v_valid_count = 0 THEN
            RAISE_APPLICATION_ERROR(-20020, 'Invalid status: ' || p_new_status);
        END IF;

        -- Prevent bulk close (safety measure)
        IF p_new_status = 'CLOSED' THEN
            RAISE_APPLICATION_ERROR(-20021, 'Bulk close not permitted. Use close_account individually.');
        END IF;

        UPDATE accounts
        SET    status     = p_new_status,
               updated_at = SYSTIMESTAMP
        WHERE  account_id IN (SELECT COLUMN_VALUE FROM TABLE(p_account_ids))
        AND    status     != 'CLOSED';

        p_updated_count := SQL%ROWCOUNT;

        -- Audit the batch
        FOR i IN 1..p_account_ids.COUNT LOOP
            p_audit('ACCOUNTS', p_account_ids(i), 'UPDATE',
                    NULL,
                    'bulk_status=' || p_new_status || ',reason=' || p_reason ||
                    ',by=' || p_employee_id);
        END LOOP;
    END bulk_update_status;

END pkg_account_mgmt;
/

SHOW ERRORS PACKAGE BODY pkg_account_mgmt;
