-- =============================================================================
-- PACKAGE 2: PKG_TRANSACTIONS
-- Transaction Processing Package
-- Handles: Deposits, Withdrawals, Transfers, Reversals, Fee Processing,
--          Interest Calculation, Currency Conversion
-- Depends on: PKG_ACCOUNT_MGMT
-- =============================================================================

CREATE OR REPLACE PACKAGE pkg_transactions AS

    -- Constants
    c_wire_fee              CONSTANT NUMBER := 25.00;
    c_atm_fee               CONSTANT NUMBER := 3.50;
    c_overdraft_fee         CONSTANT NUMBER := 35.00;
    c_nsf_fee               CONSTANT NUMBER := 35.00;
    c_foreign_txn_fee_pct   CONSTANT NUMBER := 0.03;  -- 3%
    c_tax_rate_interest      CONSTANT NUMBER := 0.30;  -- 30% withholding

    -- Custom Exceptions
    e_reversal_window        EXCEPTION;
    e_already_reversed       EXCEPTION;
    e_currency_mismatch      EXCEPTION;

    PRAGMA EXCEPTION_INIT(e_reversal_window,  -20030);
    PRAGMA EXCEPTION_INIT(e_already_reversed, -20031);
    PRAGMA EXCEPTION_INIT(e_currency_mismatch,-20032);

    -- -------------------------------------------------------------------------
    -- FUNCTIONS
    -- -------------------------------------------------------------------------

    -- Generates unique reference number
    FUNCTION generate_reference(p_type IN VARCHAR2) RETURN VARCHAR2;

    -- Returns transaction details as formatted string
    FUNCTION get_transaction_summary(p_transaction_id IN NUMBER) RETURN VARCHAR2;

    -- Checks if transaction is within reversal window (24 hrs)
    FUNCTION is_reversible(p_transaction_id IN NUMBER) RETURN BOOLEAN;

    -- Gets currency exchange rate
    FUNCTION get_exchange_rate(p_from IN VARCHAR2, p_to IN VARCHAR2) RETURN NUMBER;

    -- Converts amount between currencies
    FUNCTION convert_currency(p_amount IN NUMBER, p_from IN VARCHAR2, p_to IN VARCHAR2) RETURN NUMBER;

    -- Calculates simple interest for a period
    FUNCTION calc_simple_interest(
        p_principal     IN NUMBER,
        p_annual_rate   IN NUMBER,
        p_days          IN NUMBER
    ) RETURN NUMBER;

    -- Returns month-end accrued interest for an account
    FUNCTION calc_account_interest(
        p_account_id    IN NUMBER,
        p_period_start  IN DATE,
        p_period_end    IN DATE
    ) RETURN NUMBER;

    -- Returns total transaction count for account in date range
    FUNCTION get_transaction_count(
        p_account_id    IN NUMBER,
        p_from_date     IN DATE,
        p_to_date       IN DATE
    ) RETURN NUMBER;

    -- Returns whether a deposit amount triggers SAR reporting ($10,000+)
    FUNCTION requires_ctr_report(p_amount IN NUMBER) RETURN BOOLEAN;

    -- Get running total of deposits for customer today (structuring detection)
    FUNCTION get_customer_daily_deposits(p_customer_id IN NUMBER) RETURN NUMBER;

    -- -------------------------------------------------------------------------
    -- PROCEDURES
    -- -------------------------------------------------------------------------

    -- Deposits funds into an account
    PROCEDURE deposit(
        p_account_id     IN  NUMBER,
        p_amount         IN  NUMBER,
        p_description    IN  VARCHAR2 DEFAULT NULL,
        p_channel        IN  VARCHAR2 DEFAULT 'BRANCH',
        p_employee_id    IN  NUMBER   DEFAULT NULL,
        p_transaction_id OUT NUMBER,
        p_reference      OUT VARCHAR2
    );

    -- Withdraws funds from an account
    PROCEDURE withdraw(
        p_account_id     IN  NUMBER,
        p_amount         IN  NUMBER,
        p_description    IN  VARCHAR2 DEFAULT NULL,
        p_channel        IN  VARCHAR2 DEFAULT 'BRANCH',
        p_employee_id    IN  NUMBER   DEFAULT NULL,
        p_transaction_id OUT NUMBER,
        p_reference      OUT VARCHAR2
    );

    -- Transfers funds between two accounts (same or different customers)
    PROCEDURE transfer(
        p_from_account_id  IN  NUMBER,
        p_to_account_id    IN  NUMBER,
        p_amount           IN  NUMBER,
        p_description      IN  VARCHAR2 DEFAULT NULL,
        p_channel          IN  VARCHAR2 DEFAULT 'ONLINE',
        p_employee_id      IN  NUMBER   DEFAULT NULL,
        p_debit_txn_id     OUT NUMBER,
        p_credit_txn_id    OUT NUMBER,
        p_reference        OUT VARCHAR2
    );

    -- Reverses a transaction (within 24 hour window)
    PROCEDURE reverse_transaction(
        p_transaction_id IN  NUMBER,
        p_reason         IN  VARCHAR2,
        p_employee_id    IN  NUMBER,
        p_reversal_id    OUT NUMBER
    );

    -- Posts a fee to an account
    PROCEDURE post_fee(
        p_account_id     IN  NUMBER,
        p_fee_type       IN  VARCHAR2,
        p_amount         IN  NUMBER DEFAULT NULL,  -- NULL uses standard fee
        p_description    IN  VARCHAR2 DEFAULT NULL,
        p_employee_id    IN  NUMBER DEFAULT NULL,
        p_transaction_id OUT NUMBER
    );

    -- Waives a fee
    PROCEDURE waive_fee(
        p_fee_id         IN NUMBER,
        p_reason         IN VARCHAR2,
        p_employee_id    IN NUMBER
    );

    -- Posts monthly interest to accounts (batch process)
    PROCEDURE post_monthly_interest(
        p_posting_date   IN DATE DEFAULT SYSDATE,
        p_account_type   IN VARCHAR2 DEFAULT NULL,
        p_posted_count   OUT NUMBER,
        p_total_interest OUT NUMBER
    );

    -- Posts interest to a single account
    PROCEDURE post_account_interest(
        p_account_id     IN  NUMBER,
        p_period_start   IN  DATE,
        p_period_end     IN  DATE,
        p_posting_date   IN  DATE DEFAULT SYSDATE,
        p_transaction_id OUT NUMBER
    );

    -- Applies monthly fees to all qualifying accounts
    PROCEDURE apply_monthly_fees(
        p_fee_month      IN DATE DEFAULT SYSDATE,
        p_fees_applied   OUT NUMBER,
        p_total_fees     OUT NUMBER
    );

    -- Processes overdraft fee when account goes negative
    PROCEDURE process_overdraft_fee(
        p_account_id     IN NUMBER,
        p_transaction_id OUT NUMBER
    );

    -- Batch settlement: processes all PENDING transactions
    PROCEDURE settle_pending_transactions(
        p_settlement_date IN DATE DEFAULT SYSDATE,
        p_settled_count   OUT NUMBER,
        p_failed_count    OUT NUMBER
    );

END pkg_transactions;
/

CREATE OR REPLACE PACKAGE BODY pkg_transactions AS

    -- =========================================================================
    -- PRIVATE: Audit wrapper
    -- =========================================================================
    PROCEDURE p_audit(
        p_table  IN VARCHAR2,
        p_rec_id IN NUMBER,
        p_action IN VARCHAR2,
        p_old    IN VARCHAR2 DEFAULT NULL,
        p_new    IN VARCHAR2 DEFAULT NULL
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO audit_log (table_name, record_id, action, old_values, new_values, changed_by)
        VALUES (p_table, p_rec_id, p_action, p_old, p_new, SYS_CONTEXT('USERENV','SESSION_USER'));
        COMMIT;
    EXCEPTION WHEN OTHERS THEN NULL;
    END p_audit;

    -- =========================================================================
    -- PRIVATE: Check and raise fraud alert if needed
    -- =========================================================================
    PROCEDURE p_fraud_check(
        p_account_id    IN NUMBER,
        p_customer_id   IN NUMBER,
        p_transaction_id IN NUMBER,
        p_amount        IN NUMBER,
        p_txn_type      IN VARCHAR2
    ) IS
        v_daily_total    NUMBER;
        v_alert_severity VARCHAR2(10);
        v_alert_type     VARCHAR2(50);
        v_description    VARCHAR2(500);
    BEGIN
        -- Rule 1: Large single transaction > $9,999
        IF p_amount >= 9999 THEN
            v_alert_type     := 'LARGE_TRANSACTION';
            v_alert_severity := CASE WHEN p_amount >= 50000 THEN 'HIGH' ELSE 'MEDIUM' END;
            v_description    := 'Transaction amount ' || p_amount || ' triggers reporting threshold';

            INSERT INTO fraud_alerts (account_id, customer_id, transaction_id,
                                       alert_type, severity, description)
            VALUES (p_account_id, p_customer_id, p_transaction_id,
                    v_alert_type, v_alert_severity, v_description);
        END IF;

        -- Rule 2: Structuring detection (multiple deposits just under $10k)
        IF p_txn_type = 'DEPOSIT' THEN
            v_daily_total := pkg_transactions.get_customer_daily_deposits(p_customer_id);
            IF v_daily_total > 8000 AND v_daily_total < 10000 AND p_amount > 0 THEN
                INSERT INTO fraud_alerts (account_id, customer_id, transaction_id,
                                           alert_type, severity, description)
                VALUES (p_account_id, p_customer_id, p_transaction_id,
                        'STRUCTURING_SUSPICION', 'HIGH',
                        'Customer daily deposits reach ' || (v_daily_total + p_amount) ||
                        ' - possible structuring');
            END IF;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN NULL;  -- Never let fraud check break transaction
    END p_fraud_check;

    -- =========================================================================
    -- FUNCTION: generate_reference
    -- =========================================================================
    FUNCTION generate_reference(p_type IN VARCHAR2) RETURN VARCHAR2 IS
        v_prefix VARCHAR2(5);
        v_seq    NUMBER;
    BEGIN
        v_prefix := CASE p_type
            WHEN 'DEPOSIT'      THEN 'DEP'
            WHEN 'WITHDRAWAL'   THEN 'WDR'
            WHEN 'TRANSFER_OUT' THEN 'TRF'
            WHEN 'TRANSFER_IN'  THEN 'TRF'
            WHEN 'PAYMENT'      THEN 'PAY'
            WHEN 'FEE'          THEN 'FEE'
            WHEN 'INTEREST'     THEN 'INT'
            WHEN 'REVERSAL'     THEN 'REV'
            ELSE 'TXN'
        END;
        SELECT seq_transaction_id.NEXTVAL INTO v_seq FROM DUAL;
        RETURN v_prefix || '-' || TO_CHAR(SYSDATE,'YYYYMMDD') || '-' || LPAD(v_seq,8,'0');
    END generate_reference;

    -- =========================================================================
    -- FUNCTION: get_transaction_summary
    -- =========================================================================
    FUNCTION get_transaction_summary(p_transaction_id IN NUMBER) RETURN VARCHAR2 IS
        v_result VARCHAR2(500);
    BEGIN
        SELECT 'TXN#' || t.transaction_id ||
               ' | ' || t.transaction_type ||
               ' | Amt: ' || t.amount ||
               ' | Acct: ' || a.account_number ||
               ' | Date: ' || TO_CHAR(t.transaction_date, 'YYYY-MM-DD HH24:MI') ||
               ' | Status: ' || t.status
        INTO   v_result
        FROM   transactions t
        JOIN   accounts a ON t.account_id = a.account_id
        WHERE  t.transaction_id = p_transaction_id;
        RETURN v_result;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN 'Transaction not found: ' || p_transaction_id;
    END get_transaction_summary;

    -- =========================================================================
    -- FUNCTION: is_reversible
    -- =========================================================================
    FUNCTION is_reversible(p_transaction_id IN NUMBER) RETURN BOOLEAN IS
        v_txn_date  TIMESTAMP;
        v_status    VARCHAR2(20);
        v_txn_type  VARCHAR2(30);
    BEGIN
        SELECT transaction_date, status, transaction_type
        INTO   v_txn_date, v_status, v_txn_type
        FROM   transactions
        WHERE  transaction_id = p_transaction_id;

        -- Cannot reverse reversals, fees, or interest
        IF v_txn_type IN ('REVERSAL','FEE','INTEREST') THEN
            RETURN FALSE;
        END IF;

        -- Must be completed
        IF v_status != 'COMPLETED' THEN
            RETURN FALSE;
        END IF;

        -- Must be within 24 hours
        RETURN (SYSTIMESTAMP - v_txn_date) < INTERVAL '24' HOUR;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN FALSE;
    END is_reversible;

    -- =========================================================================
    -- FUNCTION: get_exchange_rate
    -- =========================================================================
    FUNCTION get_exchange_rate(p_from IN VARCHAR2, p_to IN VARCHAR2) RETURN NUMBER IS
        v_rate NUMBER;
    BEGIN
        IF p_from = p_to THEN RETURN 1; END IF;
        SELECT rate INTO v_rate
        FROM   exchange_rates
        WHERE  from_currency = UPPER(p_from)
        AND    to_currency   = UPPER(p_to)
        AND    effective_date = (
            SELECT MAX(effective_date)
            FROM   exchange_rates
            WHERE  from_currency = UPPER(p_from)
            AND    to_currency   = UPPER(p_to)
        );
        RETURN v_rate;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20032,
                'No exchange rate found for ' || p_from || ' to ' || p_to);
    END get_exchange_rate;

    -- =========================================================================
    -- FUNCTION: convert_currency
    -- =========================================================================
    FUNCTION convert_currency(p_amount IN NUMBER, p_from IN VARCHAR2, p_to IN VARCHAR2) RETURN NUMBER IS
    BEGIN
        RETURN ROUND(p_amount * get_exchange_rate(p_from, p_to), 2);
    END convert_currency;

    -- =========================================================================
    -- FUNCTION: calc_simple_interest
    -- =========================================================================
    FUNCTION calc_simple_interest(
        p_principal   IN NUMBER,
        p_annual_rate IN NUMBER,
        p_days        IN NUMBER
    ) RETURN NUMBER IS
    BEGIN
        -- Interest = Principal * Rate * Time
        -- Rate is annual %, convert to daily
        RETURN ROUND(p_principal * (p_annual_rate / 100) * (p_days / 365), 2);
    END calc_simple_interest;

    -- =========================================================================
    -- FUNCTION: calc_account_interest
    -- =========================================================================
    FUNCTION calc_account_interest(
        p_account_id   IN NUMBER,
        p_period_start IN DATE,
        p_period_end   IN DATE
    ) RETURN NUMBER IS
        v_avg_balance   NUMBER;
        v_interest_rate NUMBER;
        v_days          NUMBER;
        v_gross         NUMBER;
    BEGIN
        -- Calculate average daily balance using transactions
        WITH daily_balances AS (
            SELECT d.dt,
                   (SELECT balance_after
                    FROM   transactions t2
                    WHERE  t2.account_id = p_account_id
                    AND    TRUNC(t2.transaction_date) <= d.dt
                    ORDER BY t2.transaction_date DESC
                    FETCH FIRST 1 ROW ONLY) AS eod_balance
            FROM   (SELECT p_period_start + LEVEL - 1 AS dt
                    FROM   DUAL
                    CONNECT BY LEVEL <= (p_period_end - p_period_start + 1)) d
        )
        SELECT NVL(AVG(eod_balance), 0)
        INTO   v_avg_balance
        FROM   daily_balances;

        -- Get account's interest rate from account type
        SELECT NVL(at.interest_rate, 0)
        INTO   v_interest_rate
        FROM   accounts a
        JOIN   account_types at ON a.account_type = at.type_code
        WHERE  a.account_id = p_account_id;

        v_days  := p_period_end - p_period_start + 1;
        v_gross := calc_simple_interest(v_avg_balance, v_interest_rate, v_days);

        RETURN GREATEST(v_gross, 0);
    END calc_account_interest;

    -- =========================================================================
    -- FUNCTION: get_transaction_count
    -- =========================================================================
    FUNCTION get_transaction_count(
        p_account_id IN NUMBER,
        p_from_date  IN DATE,
        p_to_date    IN DATE
    ) RETURN NUMBER IS
        v_count NUMBER;
    BEGIN
        SELECT COUNT(*)
        INTO   v_count
        FROM   transactions
        WHERE  account_id       = p_account_id
        AND    TRUNC(transaction_date) BETWEEN p_from_date AND p_to_date
        AND    status           = 'COMPLETED';
        RETURN v_count;
    END get_transaction_count;

    -- =========================================================================
    -- FUNCTION: requires_ctr_report
    -- =========================================================================
    FUNCTION requires_ctr_report(p_amount IN NUMBER) RETURN BOOLEAN IS
    BEGIN
        RETURN p_amount >= 10000;
    END requires_ctr_report;

    -- =========================================================================
    -- FUNCTION: get_customer_daily_deposits
    -- =========================================================================
    FUNCTION get_customer_daily_deposits(p_customer_id IN NUMBER) RETURN NUMBER IS
        v_total NUMBER;
    BEGIN
        SELECT NVL(SUM(t.amount), 0)
        INTO   v_total
        FROM   transactions t
        JOIN   accounts a ON t.account_id = a.account_id
        WHERE  a.customer_id          = p_customer_id
        AND    t.transaction_type     = 'DEPOSIT'
        AND    TRUNC(t.transaction_date) = TRUNC(SYSDATE)
        AND    t.status               = 'COMPLETED';
        RETURN v_total;
    END get_customer_daily_deposits;

    -- =========================================================================
    -- PROCEDURE: deposit
    -- =========================================================================
    PROCEDURE deposit(
        p_account_id     IN  NUMBER,
        p_amount         IN  NUMBER,
        p_description    IN  VARCHAR2 DEFAULT NULL,
        p_channel        IN  VARCHAR2 DEFAULT 'BRANCH',
        p_employee_id    IN  NUMBER   DEFAULT NULL,
        p_transaction_id OUT NUMBER,
        p_reference      OUT VARCHAR2
    ) IS
        v_balance_before NUMBER;
        v_balance_after  NUMBER;
        v_customer_id    NUMBER;
    BEGIN
        IF p_amount <= 0 THEN
            RAISE_APPLICATION_ERROR(-20005, 'Deposit amount must be positive');
        END IF;

        v_balance_before := pkg_account_mgmt.get_balance(p_account_id);

        -- Validate account is active
        IF NOT pkg_account_mgmt.is_account_active(p_account_id) THEN
            RAISE_APPLICATION_ERROR(-20003,
                'Account ' || p_account_id || ' is not active for deposits');
        END IF;

        -- Update balance
        pkg_account_mgmt.update_balance(p_account_id, p_amount, 'CR');
        v_balance_after := v_balance_before + p_amount;

        p_reference := generate_reference('DEPOSIT');

        -- Insert transaction record
        INSERT INTO transactions (
            account_id, transaction_type, amount,
            balance_before, balance_after, description,
            reference_number, channel, status, processed_by
        ) VALUES (
            p_account_id, 'DEPOSIT', p_amount,
            v_balance_before, v_balance_after,
            NVL(p_description, 'Cash Deposit'),
            p_reference, p_channel, 'COMPLETED', p_employee_id
        ) RETURNING transaction_id INTO p_transaction_id;

        -- Get customer for fraud check
        SELECT customer_id INTO v_customer_id FROM accounts WHERE account_id = p_account_id;

        -- Fraud checks
        p_fraud_check(p_account_id, v_customer_id, p_transaction_id, p_amount, 'DEPOSIT');

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END deposit;

    -- =========================================================================
    -- PROCEDURE: withdraw
    -- =========================================================================
    PROCEDURE withdraw(
        p_account_id     IN  NUMBER,
        p_amount         IN  NUMBER,
        p_description    IN  VARCHAR2 DEFAULT NULL,
        p_channel        IN  VARCHAR2 DEFAULT 'BRANCH',
        p_employee_id    IN  NUMBER   DEFAULT NULL,
        p_transaction_id OUT NUMBER,
        p_reference      OUT VARCHAR2
    ) IS
        v_balance_before  NUMBER;
        v_balance_after   NUMBER;
        v_daily_total     NUMBER;
        v_customer_id     NUMBER;
    BEGIN
        IF p_amount <= 0 THEN
            RAISE_APPLICATION_ERROR(-20005, 'Withdrawal amount must be positive');
        END IF;

        -- Check daily withdrawal limit
        v_daily_total := pkg_account_mgmt.get_daily_withdrawal_total(p_account_id);
        IF v_daily_total + p_amount > pkg_account_mgmt.c_max_daily_withdrawal THEN
            RAISE_APPLICATION_ERROR(-20004,
                'Daily withdrawal limit exceeded. Used: ' || v_daily_total ||
                ', Limit: ' || pkg_account_mgmt.c_max_daily_withdrawal);
        END IF;

        v_balance_before := pkg_account_mgmt.get_balance(p_account_id);

        -- This will raise errors for frozen/closed/insufficient
        pkg_account_mgmt.update_balance(p_account_id, p_amount, 'DR');
        v_balance_after := v_balance_before - p_amount;

        p_reference := generate_reference('WITHDRAWAL');

        INSERT INTO transactions (
            account_id, transaction_type, amount,
            balance_before, balance_after, description,
            reference_number, channel, status, processed_by
        ) VALUES (
            p_account_id, 'WITHDRAWAL', p_amount,
            v_balance_before, v_balance_after,
            NVL(p_description, 'Cash Withdrawal'),
            p_reference, p_channel, 'COMPLETED', p_employee_id
        ) RETURNING transaction_id INTO p_transaction_id;

        -- Overdraft fee if balance went negative
        IF v_balance_after < 0 THEN
            DECLARE
                v_fee_txn NUMBER;
            BEGIN
                process_overdraft_fee(p_account_id, v_fee_txn);
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
        END IF;

        -- Fraud check
        SELECT customer_id INTO v_customer_id FROM accounts WHERE account_id = p_account_id;
        p_fraud_check(p_account_id, v_customer_id, p_transaction_id, p_amount, 'WITHDRAWAL');

    EXCEPTION
        WHEN pkg_account_mgmt.e_insufficient_funds THEN RAISE;
        WHEN pkg_account_mgmt.e_account_frozen      THEN RAISE;
        WHEN pkg_account_mgmt.e_account_closed      THEN RAISE;
        WHEN OTHERS THEN ROLLBACK; RAISE;
    END withdraw;

    -- =========================================================================
    -- PROCEDURE: transfer
    -- =========================================================================
    PROCEDURE transfer(
        p_from_account_id  IN  NUMBER,
        p_to_account_id    IN  NUMBER,
        p_amount           IN  NUMBER,
        p_description      IN  VARCHAR2 DEFAULT NULL,
        p_channel          IN  VARCHAR2 DEFAULT 'ONLINE',
        p_employee_id      IN  NUMBER   DEFAULT NULL,
        p_debit_txn_id     OUT NUMBER,
        p_credit_txn_id    OUT NUMBER,
        p_reference        OUT VARCHAR2
    ) IS
        v_from_bal_before NUMBER;
        v_to_bal_before   NUMBER;
        v_from_currency   VARCHAR2(3);
        v_to_currency     VARCHAR2(3);
        v_converted_amount NUMBER;
        v_daily_total     NUMBER;
    BEGIN
        IF p_amount <= 0 THEN
            RAISE_APPLICATION_ERROR(-20005, 'Transfer amount must be positive');
        END IF;

        IF p_from_account_id = p_to_account_id THEN
            RAISE_APPLICATION_ERROR(-20025, 'Cannot transfer to the same account');
        END IF;

        -- Check transfer limit
        IF p_amount > pkg_account_mgmt.c_max_transfer_limit THEN
            RAISE_APPLICATION_ERROR(-20004,
                'Transfer amount exceeds single-transfer limit of ' ||
                pkg_account_mgmt.c_max_transfer_limit);
        END IF;

        -- Check daily withdrawal limit on source
        v_daily_total := pkg_account_mgmt.get_daily_withdrawal_total(p_from_account_id);
        IF v_daily_total + p_amount > pkg_account_mgmt.c_max_daily_withdrawal THEN
            RAISE_APPLICATION_ERROR(-20004, 'Daily limit exceeded for source account');
        END IF;

        -- Lock accounts in consistent order to prevent deadlock
        DECLARE
            v_ignore NUMBER;
        BEGIN
            IF p_from_account_id < p_to_account_id THEN
                SELECT balance INTO v_from_bal_before FROM accounts
                WHERE account_id = p_from_account_id FOR UPDATE;
                SELECT balance INTO v_to_bal_before FROM accounts
                WHERE account_id = p_to_account_id FOR UPDATE;
            ELSE
                SELECT balance INTO v_to_bal_before FROM accounts
                WHERE account_id = p_to_account_id FOR UPDATE;
                SELECT balance INTO v_from_bal_before FROM accounts
                WHERE account_id = p_from_account_id FOR UPDATE;
            END IF;
        END;

        -- Get currencies
        SELECT currency INTO v_from_currency FROM accounts WHERE account_id = p_from_account_id;
        SELECT currency INTO v_to_currency   FROM accounts WHERE account_id = p_to_account_id;

        -- Handle FX if needed
        IF v_from_currency != v_to_currency THEN
            v_converted_amount := convert_currency(p_amount, v_from_currency, v_to_currency);
            -- Apply foreign transaction fee
            DECLARE v_fx_fee NUMBER; v_fx_txn NUMBER; BEGIN
                v_fx_fee := ROUND(p_amount * c_foreign_txn_fee_pct, 2);
                post_fee(p_from_account_id, 'FOREIGN_TXN_FEE', v_fx_fee,
                         'FX fee on transfer', p_employee_id, v_fx_txn);
            END;
        ELSE
            v_converted_amount := p_amount;
        END IF;

        p_reference := generate_reference('TRANSFER_OUT');

        -- Debit source
        pkg_account_mgmt.update_balance(p_from_account_id, p_amount, 'DR');

        INSERT INTO transactions (
            account_id, related_account_id, transaction_type, amount,
            balance_before, balance_after, description,
            reference_number, channel, status, processed_by
        ) VALUES (
            p_from_account_id, p_to_account_id, 'TRANSFER_OUT', p_amount,
            v_from_bal_before, v_from_bal_before - p_amount,
            NVL(p_description, 'Transfer to account ' || p_to_account_id),
            p_reference, p_channel, 'COMPLETED', p_employee_id
        ) RETURNING transaction_id INTO p_debit_txn_id;

        -- Credit destination
        pkg_account_mgmt.update_balance(p_to_account_id, v_converted_amount, 'CR');

        INSERT INTO transactions (
            account_id, related_account_id, transaction_type, amount,
            balance_before, balance_after, description,
            reference_number, channel, status, processed_by
        ) VALUES (
            p_to_account_id, p_from_account_id, 'TRANSFER_IN', v_converted_amount,
            v_to_bal_before, v_to_bal_before + v_converted_amount,
            NVL(p_description, 'Transfer from account ' || p_from_account_id),
            'IN-' || p_reference, p_channel, 'COMPLETED', p_employee_id
        ) RETURNING transaction_id INTO p_credit_txn_id;

    EXCEPTION
        WHEN OTHERS THEN ROLLBACK; RAISE;
    END transfer;

    -- =========================================================================
    -- PROCEDURE: reverse_transaction
    -- =========================================================================
    PROCEDURE reverse_transaction(
        p_transaction_id IN  NUMBER,
        p_reason         IN  VARCHAR2,
        p_employee_id    IN  NUMBER,
        p_reversal_id    OUT NUMBER
    ) IS
        v_account_id     NUMBER;
        v_amount         NUMBER;
        v_txn_type       VARCHAR2(30);
        v_balance_before NUMBER;
        v_balance_after  NUMBER;
        v_rev_count      NUMBER;
    BEGIN
        -- Check already reversed
        SELECT COUNT(*) INTO v_rev_count
        FROM   transactions
        WHERE  reversal_of = p_transaction_id AND status = 'COMPLETED';

        IF v_rev_count > 0 THEN
            RAISE_APPLICATION_ERROR(-20031, 'Transaction already reversed');
        END IF;

        IF NOT is_reversible(p_transaction_id) THEN
            RAISE_APPLICATION_ERROR(-20030,
                'Transaction cannot be reversed (outside window or invalid type)');
        END IF;

        SELECT account_id, amount, transaction_type
        INTO   v_account_id, v_amount, v_txn_type
        FROM   transactions
        WHERE  transaction_id = p_transaction_id;

        v_balance_before := pkg_account_mgmt.get_balance(v_account_id);

        -- Reverse the effect: credit if original was debit, debit if credit
        IF v_txn_type IN ('WITHDRAWAL','TRANSFER_OUT','PAYMENT','FEE') THEN
            pkg_account_mgmt.update_balance(v_account_id, v_amount, 'CR');
            v_balance_after := v_balance_before + v_amount;
        ELSIF v_txn_type IN ('DEPOSIT','TRANSFER_IN') THEN
            pkg_account_mgmt.update_balance(v_account_id, v_amount, 'DR');
            v_balance_after := v_balance_before - v_amount;
        ELSE
            RAISE_APPLICATION_ERROR(-20033, 'Cannot reverse transaction type: ' || v_txn_type);
        END IF;

        -- Mark original as reversed
         UPDATE transactions
         SET    status = 'REVERSED'
         WHERE  transaction_id = p_transaction_id;

        -- Insert reversal record
        INSERT INTO transactions (
            account_id, transaction_type, amount,
            balance_before, balance_after,
            description, reference_number, channel,
            status, processed_by, reversal_of
        ) VALUES (
            v_account_id, 'REVERSAL', v_amount,
            v_balance_before, v_balance_after,
            'Reversal of TXN#' || p_transaction_id || ' - ' || p_reason,
            generate_reference('REVERSAL'),
            'BRANCH', 'COMPLETED', p_employee_id, p_transaction_id
        ) RETURNING transaction_id INTO p_reversal_id;

        p_audit('TRANSACTIONS', p_transaction_id, 'UPDATE',
                'status=COMPLETED', 'status=REVERSED,reason=' || p_reason);
    END reverse_transaction;

    -- =========================================================================
    -- PROCEDURE: post_fee
    -- =========================================================================
    PROCEDURE post_fee(
        p_account_id     IN  NUMBER,
        p_fee_type       IN  VARCHAR2,
        p_amount         IN  NUMBER DEFAULT NULL,
        p_description    IN  VARCHAR2 DEFAULT NULL,
        p_employee_id    IN  NUMBER DEFAULT NULL,
        p_transaction_id OUT NUMBER
    ) IS
        v_fee_amount     NUMBER;
        v_balance_before NUMBER;
        v_balance_after  NUMBER;
        v_ref            VARCHAR2(50);
    BEGIN
        -- Determine fee amount
        IF p_amount IS NOT NULL THEN
            v_fee_amount := p_amount;
        ELSIF p_fee_type = 'OVERDRAFT_FEE' THEN
            v_fee_amount := c_overdraft_fee;
        ELSIF p_fee_type = 'NSF_FEE' THEN
            v_fee_amount := c_nsf_fee;
        ELSIF p_fee_type = 'WIRE_FEE' THEN
            v_fee_amount := c_wire_fee;
        ELSIF p_fee_type = 'ATM_FEE' THEN
            v_fee_amount := c_atm_fee;
        ELSE
            SELECT NVL(monthly_fee, 0)
            INTO   v_fee_amount
            FROM   account_types a
            JOIN   accounts acc ON a.type_code = acc.account_type
            WHERE  acc.account_id = p_account_id;
        END IF;

        IF NVL(v_fee_amount, 0) <= 0 THEN
            RETURN;  -- No fee to apply
        END IF;

        v_balance_before := pkg_account_mgmt.get_balance(p_account_id);

        -- Post fee (allow even if balance goes negative for mandatory fees)
        UPDATE accounts
        SET    balance           = balance - v_fee_amount,
             available_balance = available_balance - v_fee_amount
        WHERE  account_id = p_account_id;

        v_balance_after := v_balance_before - v_fee_amount;
        v_ref           := generate_reference('FEE');

        INSERT INTO transactions (
            account_id, transaction_type, amount,
            balance_before, balance_after, description,
            reference_number, channel, status, processed_by
        ) VALUES (
            p_account_id, 'FEE', v_fee_amount,
            v_balance_before, v_balance_after,
            NVL(p_description, p_fee_type || ' charged'),
            v_ref, 'SYSTEM', 'COMPLETED', p_employee_id
        ) RETURNING transaction_id INTO p_transaction_id;

        -- Record in fee ledger
        INSERT INTO fee_ledger (account_id, fee_type, fee_amount, transaction_id)
        VALUES (p_account_id, p_fee_type, v_fee_amount, p_transaction_id);
    END post_fee;

    -- =========================================================================
    -- PROCEDURE: waive_fee
    -- =========================================================================
    PROCEDURE waive_fee(
        p_fee_id      IN NUMBER,
        p_reason      IN VARCHAR2,
        p_employee_id IN NUMBER
    ) IS
        v_account_id NUMBER;
        v_fee_amount NUMBER;
        v_txn_id     NUMBER;
        v_waived     CHAR(1);
        v_txn_out    NUMBER;
    BEGIN
        SELECT account_id, fee_amount, transaction_id, waived
        INTO   v_account_id, v_fee_amount, v_txn_id, v_waived
        FROM   fee_ledger
        WHERE  fee_id = p_fee_id;

        IF v_waived = 'Y' THEN
            RAISE_APPLICATION_ERROR(-20035, 'Fee already waived');
        END IF;

        -- Reverse the fee transaction
        reverse_transaction(v_txn_id, 'Fee waived: ' || p_reason, p_employee_id, v_txn_out);

        -- Update fee ledger
        UPDATE fee_ledger
        SET    waived       = 'Y',
               waived_by    = p_employee_id,
               waived_reason = p_reason
        WHERE  fee_id = p_fee_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20036, 'Fee record not found: ' || p_fee_id);
    END waive_fee;

    -- =========================================================================
    -- PROCEDURE: post_account_interest
    -- =========================================================================
    PROCEDURE post_account_interest(
        p_account_id     IN  NUMBER,
        p_period_start   IN  DATE,
        p_period_end     IN  DATE,
        p_posting_date   IN  DATE DEFAULT SYSDATE,
        p_transaction_id OUT NUMBER
    ) IS
        v_gross_interest NUMBER;
        v_tax_withheld   NUMBER;
        v_net_interest   NUMBER;
        v_avg_balance    NUMBER;
        v_rate           NUMBER;
        v_bal_before     NUMBER;
        v_posting_exists NUMBER;
    BEGIN
        -- Check if already posted for this period
        SELECT COUNT(*)
        INTO   v_posting_exists
        FROM   interest_postings
        WHERE  account_id   = p_account_id
        AND    period_start = p_period_start
        AND    period_end   = p_period_end;

        IF v_posting_exists > 0 THEN
            RAISE_APPLICATION_ERROR(-20037,
                'Interest already posted for this period on account ' || p_account_id);
        END IF;

        v_gross_interest := calc_account_interest(p_account_id, p_period_start, p_period_end);

        IF v_gross_interest <= 0 THEN
            p_transaction_id := NULL;
            RETURN;
        END IF;

        v_tax_withheld := ROUND(v_gross_interest * c_tax_rate_interest, 2);
        v_net_interest := v_gross_interest - v_tax_withheld;
        v_bal_before   := pkg_account_mgmt.get_balance(p_account_id);

        -- Get rate for record
        SELECT NVL(at.interest_rate, 0)
        INTO   v_rate
        FROM   accounts a JOIN account_types at ON a.account_type = at.type_code
        WHERE  a.account_id = p_account_id;

        -- Credit net interest
        pkg_account_mgmt.update_balance(p_account_id, v_net_interest, 'CR');

        -- Update accrued interest on account
        UPDATE accounts
         SET    interest_accrued = NVL(interest_accrued, 0) + v_gross_interest
        WHERE  account_id = p_account_id;

        INSERT INTO transactions (
            account_id, transaction_type, amount,
            balance_before, balance_after, description,
            reference_number, channel, status
        ) VALUES (
            p_account_id, 'INTEREST', v_net_interest,
            v_bal_before, v_bal_before + v_net_interest,
            'Interest posting ' || TO_CHAR(p_period_start,'MON-YYYY') ||
            ' | Gross: ' || v_gross_interest || ' | Tax: ' || v_tax_withheld,
            generate_reference('INTEREST'), 'SYSTEM', 'COMPLETED'
        ) RETURNING transaction_id INTO p_transaction_id;

        INSERT INTO interest_postings (
            account_id, posting_date, period_start, period_end,
            average_balance, interest_rate, gross_interest,
            tax_withheld, net_interest, transaction_id
        ) VALUES (
            p_account_id, p_posting_date, p_period_start, p_period_end,
            v_avg_balance, v_rate, v_gross_interest,
            v_tax_withheld, v_net_interest, p_transaction_id
        );
    END post_account_interest;

    -- =========================================================================
    -- PROCEDURE: post_monthly_interest
    -- =========================================================================
    PROCEDURE post_monthly_interest(
        p_posting_date   IN DATE DEFAULT SYSDATE,
        p_account_type   IN VARCHAR2 DEFAULT NULL,
        p_posted_count   OUT NUMBER,
        p_total_interest OUT NUMBER
    ) IS
        v_period_start  DATE;
        v_period_end    DATE;
        v_txn_id        NUMBER;
        v_interest      NUMBER;
        v_errors        NUMBER := 0;
    BEGIN
        p_posted_count   := 0;
        p_total_interest := 0;

        -- Period is previous month
        v_period_start := TRUNC(ADD_MONTHS(p_posting_date, -1), 'MM');
        v_period_end   := LAST_DAY(ADD_MONTHS(p_posting_date, -1));

        FOR acc IN (
            SELECT a.account_id
            FROM   accounts a
            JOIN   account_types at ON a.account_type = at.type_code
            WHERE  a.status     = 'ACTIVE'
            AND    at.interest_rate > 0
            AND    (p_account_type IS NULL OR a.account_type = p_account_type)
            AND    NOT EXISTS (
                SELECT 1 FROM interest_postings ip
                WHERE  ip.account_id   = a.account_id
                AND    ip.period_start = v_period_start
            )
        ) LOOP
            BEGIN
                post_account_interest(
                    acc.account_id, v_period_start, v_period_end,
                    p_posting_date, v_txn_id
                );
                IF v_txn_id IS NOT NULL THEN
                    v_interest := calc_account_interest(acc.account_id, v_period_start, v_period_end);
                    p_posted_count   := p_posted_count + 1;
                    p_total_interest := p_total_interest + NVL(v_interest, 0);
                END IF;
            EXCEPTION
                WHEN OTHERS THEN
                    v_errors := v_errors + 1;
                    DBMS_OUTPUT.PUT_LINE('Error posting interest for account ' ||
                                         acc.account_id || ': ' || SQLERRM);
            END;
        END LOOP;

        DBMS_OUTPUT.PUT_LINE('Interest posting complete: ' || p_posted_count ||
                              ' accounts, total: ' || p_total_interest ||
                              ', errors: ' || v_errors);
    END post_monthly_interest;

    -- =========================================================================
    -- PROCEDURE: apply_monthly_fees
    -- =========================================================================
    PROCEDURE apply_monthly_fees(
        p_fee_month   IN  DATE DEFAULT SYSDATE,
        p_fees_applied OUT NUMBER,
        p_total_fees  OUT NUMBER
    ) IS
        v_fee_month    DATE := TRUNC(p_fee_month, 'MM');
        v_already_fees NUMBER;
        v_txn_id       NUMBER;
        v_monthly_fee  NUMBER;
    BEGIN
        p_fees_applied := 0;
        p_total_fees   := 0;

        FOR acc IN (
            SELECT a.account_id, at.monthly_fee, at.min_balance, a.balance
            FROM   accounts a
            JOIN   account_types at ON a.account_type = at.type_code
            WHERE  a.status       = 'ACTIVE'
            AND    at.monthly_fee > 0
        ) LOOP
            BEGIN
                -- Waive fee if balance >= minimum balance
                IF acc.balance >= acc.min_balance * 5 THEN
                    CONTINUE;  -- Waive for high-balance customers
                END IF;

                -- Check not already charged this month
                SELECT COUNT(*) INTO v_already_fees
                FROM   fee_ledger fl
                WHERE  fl.account_id = acc.account_id
                AND    fl.fee_type   = 'MONTHLY_FEE'
                AND    TRUNC(fl.fee_date, 'MM') = v_fee_month
                AND    fl.waived    = 'N';

                IF v_already_fees = 0 THEN
                    post_fee(acc.account_id, 'MONTHLY_FEE', acc.monthly_fee,
                             'Monthly maintenance fee ' || TO_CHAR(p_fee_month,'MON-YYYY'),
                             NULL, v_txn_id);
                    p_fees_applied := p_fees_applied + 1;
                    p_total_fees   := p_total_fees + acc.monthly_fee;
                END IF;
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
        END LOOP;
    END apply_monthly_fees;

    -- =========================================================================
    -- PROCEDURE: process_overdraft_fee
    -- =========================================================================
    PROCEDURE process_overdraft_fee(p_account_id IN NUMBER, p_transaction_id OUT NUMBER) IS
        v_already_today NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_already_today
        FROM   fee_ledger
        WHERE  account_id = p_account_id
        AND    fee_type   = 'OVERDRAFT_FEE'
        AND    TRUNC(fee_date) = TRUNC(SYSDATE);

        IF v_already_today = 0 THEN
            post_fee(p_account_id, 'OVERDRAFT_FEE', c_overdraft_fee,
                     'Overdraft fee', NULL, p_transaction_id);
        ELSE
            p_transaction_id := NULL;
        END IF;
    END process_overdraft_fee;

    -- =========================================================================
    -- PROCEDURE: settle_pending_transactions
    -- =========================================================================
    PROCEDURE settle_pending_transactions(
        p_settlement_date IN  DATE DEFAULT SYSDATE,
        p_settled_count   OUT NUMBER,
        p_failed_count    OUT NUMBER
    ) IS
    BEGIN
        p_settled_count := 0;
        p_failed_count  := 0;

        -- Settle all pending that are past their value date
        UPDATE transactions
        SET    status = 'COMPLETED'
        WHERE  status     = 'PENDING'
        AND    value_date <= p_settlement_date;

        p_settled_count := SQL%ROWCOUNT;

        -- Mark as failed if pending > 3 days (stuck)
        UPDATE transactions
        SET    status = 'FAILED'
        WHERE  status     = 'PENDING'
        AND    value_date < p_settlement_date - 3;

        p_failed_count := SQL%ROWCOUNT;

        DBMS_OUTPUT.PUT_LINE('Settlement complete: settled=' || p_settled_count ||
                              ', failed=' || p_failed_count);
    END settle_pending_transactions;

END pkg_transactions;
/

SHOW ERRORS PACKAGE BODY pkg_transactions;
