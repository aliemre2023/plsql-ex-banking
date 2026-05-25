-- =============================================================================
-- PACKAGE 3: PKG_LOAN_MGMT
-- Loan Management Package
-- Handles: Loan origination, amortization, payments, delinquency,
--          credit scoring, risk assessment, write-offs
-- Depends on: PKG_ACCOUNT_MGMT, PKG_TRANSACTIONS
-- =============================================================================

CREATE OR REPLACE PACKAGE pkg_loan_mgmt AS

    -- Constants
    c_max_dti_ratio         CONSTANT NUMBER := 0.43;   -- Max debt-to-income
    c_min_credit_score      CONSTANT NUMBER := 580;
    c_prime_rate            CONSTANT NUMBER := 5.50;   -- Current prime rate %
    c_late_fee_pct          CONSTANT NUMBER := 0.05;   -- 5% of payment
    c_grace_period_days     CONSTANT NUMBER := 15;
    c_charge_off_days       CONSTANT NUMBER := 180;    -- Days to charge-off

    -- Exceptions
    e_loan_not_eligible     EXCEPTION;
    e_credit_score_low      EXCEPTION;
    e_dti_exceeded          EXCEPTION;
    e_loan_already_paid     EXCEPTION;

    PRAGMA EXCEPTION_INIT(e_loan_not_eligible, -20050);
    PRAGMA EXCEPTION_INIT(e_credit_score_low,  -20051);
    PRAGMA EXCEPTION_INIT(e_dti_exceeded,      -20052);
    PRAGMA EXCEPTION_INIT(e_loan_already_paid, -20053);

    -- -------------------------------------------------------------------------
    -- FUNCTIONS
    -- -------------------------------------------------------------------------

    -- Calculates monthly payment using standard amortization
    FUNCTION calc_monthly_payment(
        p_principal     IN NUMBER,
        p_annual_rate   IN NUMBER,
        p_term_months   IN NUMBER
    ) RETURN NUMBER;

    -- Calculates total interest over loan life
    FUNCTION calc_total_interest(
        p_principal     IN NUMBER,
        p_annual_rate   IN NUMBER,
        p_term_months   IN NUMBER
    ) RETURN NUMBER;

    -- Splits a payment into principal and interest portions
    FUNCTION calc_payment_split(
        p_outstanding   IN NUMBER,
        p_annual_rate   IN NUMBER,
        p_payment       IN NUMBER
    ) RETURN SYS.ODCIVARCHAR2LIST;  -- Returns ('principal','interest')

    -- Determines interest rate based on credit score and loan type
    FUNCTION determine_interest_rate(
        p_credit_score  IN NUMBER,
        p_loan_type     IN VARCHAR2,
        p_term_months   IN NUMBER
    ) RETURN NUMBER;

    -- Calculates debt-to-income ratio for customer
    FUNCTION calc_dti_ratio(
        p_customer_id   IN NUMBER,
        p_new_payment   IN NUMBER
    ) RETURN NUMBER;

    -- Returns loan status description
    FUNCTION get_loan_status_desc(p_loan_id IN NUMBER) RETURN VARCHAR2;

    -- Computes days past due for a loan
    FUNCTION calc_days_past_due(p_loan_id IN NUMBER) RETURN NUMBER;

    -- Returns the next payment due date
    FUNCTION get_next_payment_date(p_loan_id IN NUMBER) RETURN DATE;

    -- Returns outstanding balance
    FUNCTION get_outstanding_balance(p_loan_id IN NUMBER) RETURN NUMBER;

    -- Checks if a customer qualifies for a loan
    FUNCTION loan_eligibility_check(
        p_customer_id   IN NUMBER,
        p_loan_type     IN VARCHAR2,
        p_amount        IN NUMBER,
        p_term_months   IN NUMBER
    ) RETURN VARCHAR2;  -- Returns 'APPROVED','REJECTED','REVIEW'

    -- -------------------------------------------------------------------------
    -- PROCEDURES
    -- -------------------------------------------------------------------------

    -- Originates (creates) a new loan application
    PROCEDURE originate_loan(
        p_customer_id     IN  NUMBER,
        p_account_id      IN  NUMBER,
        p_branch_id       IN  NUMBER,
        p_loan_type       IN  VARCHAR2,
        p_amount          IN  NUMBER,
        p_term_months     IN  NUMBER,
        p_collateral_type IN  VARCHAR2 DEFAULT NULL,
        p_collateral_val  IN  NUMBER DEFAULT NULL,
        p_employee_id     IN  NUMBER,
        p_loan_id         OUT NUMBER,
        p_loan_number     OUT VARCHAR2,
        p_monthly_payment OUT NUMBER,
        p_decision        OUT VARCHAR2
    );

    -- Approves a pending loan and disburses funds
    PROCEDURE approve_and_disburse(
        p_loan_id        IN NUMBER,
        p_employee_id    IN NUMBER,
        p_disbursement_account IN NUMBER DEFAULT NULL
    );

    -- Rejects a loan application
    PROCEDURE reject_loan(
        p_loan_id     IN NUMBER,
        p_reason      IN VARCHAR2,
        p_employee_id IN NUMBER
    );

    -- Generates amortization schedule for a loan
    PROCEDURE generate_amortization_schedule(
        p_loan_id     IN NUMBER,
        p_start_date  IN DATE DEFAULT SYSDATE
    );

    -- Processes a loan payment
    PROCEDURE process_loan_payment(
        p_loan_id           IN  NUMBER,
        p_payment_amount    IN  NUMBER,
        p_payment_account   IN  NUMBER,
        p_employee_id       IN  NUMBER DEFAULT NULL,
        p_payment_id        OUT NUMBER,
        p_principal_paid    OUT NUMBER,
        p_interest_paid     OUT NUMBER,
        p_remaining_balance OUT NUMBER
    );

    -- Updates delinquency status for all active loans (batch)
    PROCEDURE update_delinquency_status(
        p_as_of_date        IN DATE DEFAULT SYSDATE,
        p_delinquent_count  OUT NUMBER,
        p_total_dpd_balance OUT NUMBER
    );

    -- Processes late fees for overdue loans
    PROCEDURE apply_late_fees(
        p_as_of_date    IN  DATE DEFAULT SYSDATE,
        p_fees_applied  OUT NUMBER,
        p_total_fees    OUT NUMBER
    );

    -- Charges off a severely delinquent loan
    PROCEDURE charge_off_loan(
        p_loan_id      IN NUMBER,
        p_reason       IN VARCHAR2,
        p_employee_id  IN NUMBER
    );

    -- Marks a loan as paid off
    PROCEDURE pay_off_loan(
        p_loan_id         IN NUMBER,
        p_payoff_account  IN NUMBER,
        p_employee_id     IN NUMBER,
        p_payoff_amount   OUT NUMBER
    );

    -- Restructures a distressed loan
    PROCEDURE restructure_loan(
        p_loan_id         IN NUMBER,
        p_new_rate        IN NUMBER,
        p_new_term_months IN NUMBER,
        p_reason          IN VARCHAR2,
        p_employee_id     IN NUMBER,
        p_new_payment     OUT NUMBER
    );

END pkg_loan_mgmt;
/

CREATE OR REPLACE PACKAGE BODY pkg_loan_mgmt AS

    -- =========================================================================
    -- PRIVATE: Audit helper
    -- =========================================================================
    PROCEDURE p_audit(p_table IN VARCHAR2, p_rec IN NUMBER, p_action IN VARCHAR2,
                      p_old IN VARCHAR2, p_new IN VARCHAR2) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO audit_log(table_name,record_id,action,old_values,new_values,changed_by)
        VALUES(p_table,p_rec,p_action,p_old,p_new,SYS_CONTEXT('USERENV','SESSION_USER'));
        COMMIT;
    EXCEPTION WHEN OTHERS THEN NULL;
    END p_audit;

    -- =========================================================================
    -- FUNCTION: calc_monthly_payment
    -- Using standard amortization formula: M = P[r(1+r)^n]/[(1+r)^n-1]
    -- =========================================================================
    FUNCTION calc_monthly_payment(
        p_principal   IN NUMBER,
        p_annual_rate IN NUMBER,
        p_term_months IN NUMBER
    ) RETURN NUMBER IS
        v_monthly_rate NUMBER;
        v_payment      NUMBER;
    BEGIN
        IF p_annual_rate = 0 THEN
            RETURN ROUND(p_principal / p_term_months, 2);
        END IF;

        v_monthly_rate := (p_annual_rate / 100) / 12;
        v_payment := p_principal *
                     (v_monthly_rate * POWER(1 + v_monthly_rate, p_term_months)) /
                     (POWER(1 + v_monthly_rate, p_term_months) - 1);

        RETURN ROUND(v_payment, 2);
    END calc_monthly_payment;

    -- =========================================================================
    -- FUNCTION: calc_total_interest
    -- =========================================================================
    FUNCTION calc_total_interest(
        p_principal   IN NUMBER,
        p_annual_rate IN NUMBER,
        p_term_months IN NUMBER
    ) RETURN NUMBER IS
        v_monthly_payment NUMBER;
    BEGIN
        v_monthly_payment := calc_monthly_payment(p_principal, p_annual_rate, p_term_months);
        RETURN ROUND((v_monthly_payment * p_term_months) - p_principal, 2);
    END calc_total_interest;

    -- =========================================================================
    -- FUNCTION: calc_payment_split
    -- Returns varray of (principal_portion, interest_portion) as strings
    -- =========================================================================
    FUNCTION calc_payment_split(
        p_outstanding IN NUMBER,
        p_annual_rate IN NUMBER,
        p_payment     IN NUMBER
    ) RETURN SYS.ODCIVARCHAR2LIST IS
        v_monthly_rate    NUMBER;
        v_interest_charge NUMBER;
        v_principal_charge NUMBER;
        v_result          SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST();
    BEGIN
        v_monthly_rate     := (p_annual_rate / 100) / 12;
        v_interest_charge  := ROUND(p_outstanding * v_monthly_rate, 2);
        v_principal_charge := ROUND(p_payment - v_interest_charge, 2);

        -- If payment doesn't cover interest
        IF v_principal_charge < 0 THEN
            v_interest_charge  := p_payment;
            v_principal_charge := 0;
        END IF;

        v_result.EXTEND(2);
        v_result(1) := TO_CHAR(v_principal_charge);
        v_result(2) := TO_CHAR(v_interest_charge);
        RETURN v_result;
    END calc_payment_split;

    -- =========================================================================
    -- FUNCTION: determine_interest_rate
    -- Risk-based pricing
    -- =========================================================================
    FUNCTION determine_interest_rate(
        p_credit_score IN NUMBER,
        p_loan_type    IN VARCHAR2,
        p_term_months  IN NUMBER
    ) RETURN NUMBER IS
        v_base_rate  NUMBER;
        v_spread     NUMBER;
        v_term_adj   NUMBER;
    BEGIN
        -- Base rate by loan type
        v_base_rate := CASE p_loan_type
            WHEN 'MORTGAGE'  THEN c_prime_rate + 1.5
            WHEN 'AUTO'      THEN c_prime_rate + 2.0
            WHEN 'PERSONAL'  THEN c_prime_rate + 4.5
            WHEN 'BUSINESS'  THEN c_prime_rate + 2.5
            WHEN 'STUDENT'   THEN c_prime_rate + 1.0
            WHEN 'HELOC'     THEN c_prime_rate + 1.8
            ELSE c_prime_rate + 5.0
        END;

        -- Credit score spread (risk premium)
        v_spread := CASE
            WHEN p_credit_score >= 800 THEN -1.5   -- Excellent
            WHEN p_credit_score >= 740 THEN -1.0   -- Very good
            WHEN p_credit_score >= 700 THEN -0.5   -- Good
            WHEN p_credit_score >= 660 THEN  0.0   -- Fair
            WHEN p_credit_score >= 620 THEN  1.5   -- Poor
            WHEN p_credit_score >= 580 THEN  3.0   -- Bad
            ELSE  5.0                              -- Very bad
        END;

        -- Term adjustment (longer = higher risk)
        v_term_adj := CASE
            WHEN p_term_months <= 12  THEN -0.25
            WHEN p_term_months <= 36  THEN  0.00
            WHEN p_term_months <= 60  THEN  0.25
            WHEN p_term_months <= 120 THEN  0.50
            ELSE  0.75
        END;

        RETURN ROUND(v_base_rate + v_spread + v_term_adj, 2);
    END determine_interest_rate;

    -- =========================================================================
    -- FUNCTION: calc_dti_ratio
    -- Debt-to-Income ratio: total monthly debt payments / monthly gross income
    -- =========================================================================
    FUNCTION calc_dti_ratio(
        p_customer_id IN NUMBER,
        p_new_payment IN NUMBER
    ) RETURN NUMBER IS
        v_total_debt_payments NUMBER;
        v_monthly_income      NUMBER;
        v_estimated_income    NUMBER;
    BEGIN
        -- Sum all active loan monthly payments
        SELECT NVL(SUM(monthly_payment), 0)
        INTO   v_total_debt_payments
        FROM   loans
        WHERE  customer_id = p_customer_id
        AND    status      = 'ACTIVE';

        -- Estimate monthly income from credit score (simplified - normally from application)
        SELECT NVL(credit_score, 600)
        INTO   v_monthly_income  -- We'll use credit score proxy
        FROM   customers
        WHERE  customer_id = p_customer_id;

        -- Map credit score to estimated income (simplified proxy)
        v_estimated_income := CASE
            WHEN v_monthly_income >= 750 THEN 8000
            WHEN v_monthly_income >= 700 THEN 6000
            WHEN v_monthly_income >= 650 THEN 4500
            WHEN v_monthly_income >= 600 THEN 3500
            ELSE 2500
        END;

        IF v_estimated_income = 0 THEN RETURN 1; END IF;

        RETURN ROUND((v_total_debt_payments + p_new_payment) / v_estimated_income, 4);
    END calc_dti_ratio;

    -- =========================================================================
    -- FUNCTION: get_loan_status_desc
    -- =========================================================================
    FUNCTION get_loan_status_desc(p_loan_id IN NUMBER) RETURN VARCHAR2 IS
        v_status  VARCHAR2(20);
        v_dpd     NUMBER;
        v_balance NUMBER;
    BEGIN
        SELECT status, days_past_due, outstanding_balance
        INTO   v_status, v_dpd, v_balance
        FROM   loans WHERE loan_id = p_loan_id;

        RETURN 'Loan #' || p_loan_id ||
               ' | Status: ' || v_status ||
               ' | DPD: ' || v_dpd ||
               ' | Balance: $' || TO_CHAR(v_balance, '999,999.99');
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN 'Loan not found';
    END get_loan_status_desc;

    -- =========================================================================
    -- FUNCTION: calc_days_past_due
    -- =========================================================================
    FUNCTION calc_days_past_due(p_loan_id IN NUMBER) RETURN NUMBER IS
        v_due_date DATE;
    BEGIN
        SELECT MIN(due_date)
        INTO   v_due_date
        FROM   loan_payments
        WHERE  loan_id = p_loan_id
        AND    status IN ('OVERDUE','PARTIAL')
        AND    paid_amount < scheduled_amount;

        IF v_due_date IS NULL THEN RETURN 0; END IF;
        RETURN GREATEST(0, TRUNC(SYSDATE - v_due_date));
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN 0;
    END calc_days_past_due;

    -- =========================================================================
    -- FUNCTION: get_next_payment_date
    -- =========================================================================
    FUNCTION get_next_payment_date(p_loan_id IN NUMBER) RETURN DATE IS
        v_next_due DATE;
    BEGIN
        SELECT MIN(due_date)
        INTO   v_next_due
        FROM   loan_payments
        WHERE  loan_id = p_loan_id
        AND    status IN ('SCHEDULED','PARTIAL');
        RETURN v_next_due;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN NULL;
    END get_next_payment_date;

    -- =========================================================================
    -- FUNCTION: get_outstanding_balance
    -- =========================================================================
    FUNCTION get_outstanding_balance(p_loan_id IN NUMBER) RETURN NUMBER IS
        v_balance NUMBER;
    BEGIN
        SELECT outstanding_balance INTO v_balance
        FROM   loans WHERE loan_id = p_loan_id;
        RETURN NVL(v_balance, 0);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN -1;
    END get_outstanding_balance;

    -- =========================================================================
    -- FUNCTION: loan_eligibility_check
    -- =========================================================================
    FUNCTION loan_eligibility_check(
        p_customer_id IN NUMBER,
        p_loan_type   IN VARCHAR2,
        p_amount      IN NUMBER,
        p_term_months IN NUMBER
    ) RETURN VARCHAR2 IS
        v_credit_score  NUMBER;
        v_kyc_status    VARCHAR2(20);
        v_risk_level    VARCHAR2(10);
        v_is_active     CHAR(1);
        v_dti           NUMBER;
        v_rate          NUMBER;
        v_payment       NUMBER;
        v_existing_loans NUMBER;
    BEGIN
        -- Get customer info
        SELECT credit_score, kyc_status, risk_level, is_active
        INTO   v_credit_score, v_kyc_status, v_risk_level, v_is_active
        FROM   customers
        WHERE  customer_id = p_customer_id;

        -- Basic eligibility checks
        IF v_is_active = 'N' THEN RETURN 'REJECTED'; END IF;
        IF v_kyc_status != 'VERIFIED' THEN RETURN 'REJECTED'; END IF;
        IF v_credit_score < c_min_credit_score THEN RETURN 'REJECTED'; END IF;
        IF v_risk_level = 'HIGH' THEN RETURN 'REVIEW'; END IF;

        -- Count existing loans
        SELECT COUNT(*) INTO v_existing_loans
        FROM   loans
        WHERE  customer_id = p_customer_id AND status = 'ACTIVE';

        IF v_existing_loans >= 5 THEN RETURN 'REJECTED'; END IF;

        -- Calculate DTI
        v_rate    := determine_interest_rate(v_credit_score, p_loan_type, p_term_months);
        v_payment := calc_monthly_payment(p_amount, v_rate, p_term_months);
        v_dti     := calc_dti_ratio(p_customer_id, v_payment);

        IF v_dti > c_max_dti_ratio THEN RETURN 'REJECTED'; END IF;
        IF v_dti > 0.36 THEN RETURN 'REVIEW'; END IF;

        -- Amount limits by type
        DECLARE
            v_max_amount NUMBER;
        BEGIN
            v_max_amount := CASE p_loan_type
                WHEN 'PERSONAL'  THEN 50000
                WHEN 'AUTO'      THEN 75000
                WHEN 'MORTGAGE'  THEN 1000000
                WHEN 'BUSINESS'  THEN 500000
                WHEN 'STUDENT'   THEN 75000
                WHEN 'HELOC'     THEN 200000
                ELSE 25000
            END;
            IF p_amount > v_max_amount THEN RETURN 'REVIEW'; END IF;
        END;

        RETURN 'APPROVED';
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN 'REJECTED';
    END loan_eligibility_check;

    -- =========================================================================
    -- PROCEDURE: originate_loan
    -- =========================================================================
    PROCEDURE originate_loan(
        p_customer_id     IN  NUMBER,
        p_account_id      IN  NUMBER,
        p_branch_id       IN  NUMBER,
        p_loan_type       IN  VARCHAR2,
        p_amount          IN  NUMBER,
        p_term_months     IN  NUMBER,
        p_collateral_type IN  VARCHAR2 DEFAULT NULL,
        p_collateral_val  IN  NUMBER DEFAULT NULL,
        p_employee_id     IN  NUMBER,
        p_loan_id         OUT NUMBER,
        p_loan_number     OUT VARCHAR2,
        p_monthly_payment OUT NUMBER,
        p_decision        OUT VARCHAR2
    ) IS
        v_rate           NUMBER;
        v_credit_score   NUMBER;
        v_maturity_date  DATE;
        v_seq            NUMBER;
    BEGIN
        -- Run eligibility
        p_decision := loan_eligibility_check(p_customer_id, p_loan_type, p_amount, p_term_months);

        -- Get credit score for rate determination
        SELECT NVL(credit_score, 600) INTO v_credit_score
        FROM   customers WHERE customer_id = p_customer_id;

        v_rate            := determine_interest_rate(v_credit_score, p_loan_type, p_term_months);
        p_monthly_payment := calc_monthly_payment(p_amount, v_rate, p_term_months);

        SELECT seq_loan_id.NEXTVAL INTO v_seq FROM DUAL;
        p_loan_number := p_loan_type || '-' || LPAD(v_seq, 8, '0');

        -- Compute maturity
        v_maturity_date := ADD_MONTHS(SYSDATE, p_term_months);

        INSERT INTO loans (
            loan_number, customer_id, account_id, branch_id,
            loan_type, principal_amount, outstanding_balance,
            interest_rate, term_months, monthly_payment,
            maturity_date, status, collateral_type, collateral_value,
            credit_score_at_origination, approved_by
        ) VALUES (
            p_loan_number, p_customer_id, p_account_id, p_branch_id,
            p_loan_type, p_amount, p_amount,
            v_rate, p_term_months, p_monthly_payment,
            v_maturity_date,
            CASE p_decision WHEN 'APPROVED' THEN 'APPROVED'
                             WHEN 'REVIEW'   THEN 'PENDING'
                             ELSE 'REJECTED' END,
            p_collateral_type, p_collateral_val,
            v_credit_score, p_employee_id
        ) RETURNING loan_id INTO p_loan_id;

        p_audit('LOANS', p_loan_id, 'INSERT', NULL,
                'type=' || p_loan_type ||
                ',amount=' || p_amount ||
                ',decision=' || p_decision);
    EXCEPTION
        WHEN OTHERS THEN ROLLBACK; RAISE;
    END originate_loan;

    -- =========================================================================
    -- PROCEDURE: approve_and_disburse
    -- =========================================================================
    PROCEDURE approve_and_disburse(
        p_loan_id        IN NUMBER,
        p_employee_id    IN NUMBER,
        p_disbursement_account IN NUMBER DEFAULT NULL
    ) IS
        v_loan          loans%ROWTYPE;
        v_acct_id       NUMBER;
        v_txn_id        NUMBER;
        v_ref           VARCHAR2(50);
        v_disb_date     DATE := SYSDATE;
    BEGIN
        SELECT * INTO v_loan FROM loans WHERE loan_id = p_loan_id FOR UPDATE;

        IF v_loan.status NOT IN ('PENDING','APPROVED') THEN
            RAISE_APPLICATION_ERROR(-20055,
                'Loan cannot be disbursed from status: ' || v_loan.status);
        END IF;

        v_acct_id := NVL(p_disbursement_account, v_loan.account_id);

        -- Deposit loan proceeds to account
        pkg_transactions.deposit(
            v_acct_id, v_loan.principal_amount,
            'Loan disbursement - ' || v_loan.loan_number,
            'BRANCH', p_employee_id,
            v_txn_id, v_ref
        );

        UPDATE loans
        SET    status           = 'ACTIVE',
               disbursement_date = v_disb_date,
               approved_by      = p_employee_id,
               updated_at       = SYSTIMESTAMP
        WHERE  loan_id = p_loan_id;

        -- Generate amortization schedule
        generate_amortization_schedule(p_loan_id, v_disb_date);

        p_audit('LOANS', p_loan_id, 'UPDATE',
                'status=PENDING',
                'status=ACTIVE,disbursed_by=' || p_employee_id);
    END approve_and_disburse;

    -- =========================================================================
    -- PROCEDURE: reject_loan
    -- =========================================================================
    PROCEDURE reject_loan(
        p_loan_id     IN NUMBER,
        p_reason      IN VARCHAR2,
        p_employee_id IN NUMBER
    ) IS
        v_status VARCHAR2(20);
    BEGIN
        SELECT status INTO v_status FROM loans WHERE loan_id = p_loan_id FOR UPDATE;

        IF v_status NOT IN ('PENDING','APPROVED') THEN
            RAISE_APPLICATION_ERROR(-20056, 'Loan cannot be rejected from status: ' || v_status);
        END IF;

        UPDATE loans
        SET    status     = 'REJECTED',
               updated_at = SYSTIMESTAMP
        WHERE  loan_id = p_loan_id;

        p_audit('LOANS', p_loan_id, 'UPDATE',
                'status=' || v_status,
                'status=REJECTED,reason=' || p_reason || ',by=' || p_employee_id);
    END reject_loan;

    -- =========================================================================
    -- PROCEDURE: generate_amortization_schedule
    -- =========================================================================
    PROCEDURE generate_amortization_schedule(
        p_loan_id    IN NUMBER,
        p_start_date IN DATE DEFAULT SYSDATE
    ) IS
        v_loan        loans%ROWTYPE;
        v_balance     NUMBER;
        v_monthly_rate NUMBER;
        v_interest    NUMBER;
        v_principal   NUMBER;
        v_due_date    DATE;
        v_seq         NUMBER;
    BEGIN
        SELECT * INTO v_loan FROM loans WHERE loan_id = p_loan_id;

        v_balance      := v_loan.principal_amount;
        v_monthly_rate := (v_loan.interest_rate / 100) / 12;

        -- Delete existing schedule
        DELETE FROM loan_payments WHERE loan_id = p_loan_id AND status = 'SCHEDULED';

        FOR i IN 1..v_loan.term_months LOOP
            v_due_date := ADD_MONTHS(TRUNC(p_start_date, 'MM') + 28, i - 1);
            -- Last day of payment month, capped at day 28 for simplicity

            v_interest := ROUND(v_balance * v_monthly_rate, 2);
            v_principal := v_loan.monthly_payment - v_interest;

            -- Last payment adjustment
            IF i = v_loan.term_months THEN
                v_principal := v_balance;
            END IF;

            SELECT seq_payment_id.NEXTVAL INTO v_seq FROM DUAL;

            INSERT INTO loan_payments (
                payment_id, loan_id, due_date, scheduled_amount,
                principal_portion, interest_portion, status
            ) VALUES (
                v_seq, p_loan_id, v_due_date, v_loan.monthly_payment,
                v_principal, v_interest, 'SCHEDULED'
            );

            v_balance := v_balance - v_principal;
            IF v_balance < 0.01 THEN v_balance := 0; END IF;
        END LOOP;
    END generate_amortization_schedule;

    -- =========================================================================
    -- PROCEDURE: process_loan_payment
    -- =========================================================================
    PROCEDURE process_loan_payment(
        p_loan_id           IN  NUMBER,
        p_payment_amount    IN  NUMBER,
        p_payment_account   IN  NUMBER,
        p_employee_id       IN  NUMBER DEFAULT NULL,
        p_payment_id        OUT NUMBER,
        p_principal_paid    OUT NUMBER,
        p_interest_paid     OUT NUMBER,
        p_remaining_balance OUT NUMBER
    ) IS
        v_loan           loans%ROWTYPE;
        v_next_payment   loan_payments%ROWTYPE;
        v_split          SYS.ODCIVARCHAR2LIST;
        v_txn_id         NUMBER;
        v_ref            VARCHAR2(50);
        v_late_fee       NUMBER := 0;
        v_pay_amount     NUMBER := p_payment_amount;
    BEGIN
        SELECT * INTO v_loan FROM loans WHERE loan_id = p_loan_id FOR UPDATE;

        IF v_loan.status = 'PAID_OFF' THEN
            RAISE_APPLICATION_ERROR(-20053, 'Loan is already paid off');
        END IF;

        IF v_loan.status NOT IN ('ACTIVE') THEN
            RAISE_APPLICATION_ERROR(-20050, 'Loan is not active: ' || v_loan.status);
        END IF;

        -- Get next due payment
        BEGIN
            SELECT * INTO v_next_payment
            FROM   loan_payments
            WHERE  loan_id = p_loan_id
            AND    status IN ('SCHEDULED','OVERDUE','PARTIAL')
            ORDER BY due_date ASC
            FETCH FIRST 1 ROW ONLY;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20057, 'No outstanding payments found for this loan');
        END;

        -- Check late fee
        IF SYSDATE > v_next_payment.due_date + c_grace_period_days THEN
            v_late_fee := ROUND(v_loan.monthly_payment * c_late_fee_pct, 2);
        END IF;

        -- Payment split
        v_split := calc_payment_split(
            v_loan.outstanding_balance,
            v_loan.interest_rate,
            p_payment_amount
        );
        p_principal_paid := TO_NUMBER(v_split(1));
        p_interest_paid  := TO_NUMBER(v_split(2));

        -- Debit payment account
        pkg_transactions.withdraw(
            p_payment_account, p_payment_amount,
            'Loan payment ' || v_loan.loan_number,
            'BRANCH', p_employee_id,
            v_txn_id, v_ref
        );

        -- Update loan balance
        UPDATE loans
        SET    outstanding_balance = outstanding_balance - p_principal_paid,
               days_past_due       = 0,
               updated_at          = SYSTIMESTAMP
        WHERE  loan_id = p_loan_id;

        p_remaining_balance := v_loan.outstanding_balance - p_principal_paid;

        -- Update payment record
        UPDATE loan_payments
        SET    paid_amount       = NVL(paid_amount, 0) + p_payment_amount,
               principal_portion = p_principal_paid,
               interest_portion  = p_interest_paid,
               payment_date      = SYSDATE,
               late_fee          = v_late_fee,
               status            = CASE
                   WHEN (NVL(paid_amount,0) + p_payment_amount) >= scheduled_amount
                   THEN 'PAID'
                   ELSE 'PARTIAL'
               END,
               transaction_id    = v_txn_id
        WHERE  payment_id = v_next_payment.payment_id
        RETURNING payment_id INTO p_payment_id;

        -- Apply late fee if applicable
        IF v_late_fee > 0 THEN
            DECLARE v_fee_txn NUMBER; BEGIN
                pkg_transactions.post_fee(
                    p_payment_account, 'LATE_FEE', v_late_fee,
                    'Late fee on loan ' || v_loan.loan_number,
                    p_employee_id, v_fee_txn
                );
            END;
        END IF;

        -- Check if loan is fully paid
        IF p_remaining_balance <= 0.01 THEN
            UPDATE loans
            SET    status     = 'PAID_OFF',
                   outstanding_balance = 0,
                   updated_at = SYSTIMESTAMP
            WHERE  loan_id = p_loan_id;

            p_remaining_balance := 0;
        END IF;

        p_audit('LOANS', p_loan_id, 'UPDATE',
                'balance=' || v_loan.outstanding_balance,
                'payment=' || p_payment_amount || ',new_balance=' || p_remaining_balance);
    END process_loan_payment;

    -- =========================================================================
    -- PROCEDURE: update_delinquency_status
    -- =========================================================================
    PROCEDURE update_delinquency_status(
        p_as_of_date       IN  DATE DEFAULT SYSDATE,
        p_delinquent_count OUT NUMBER,
        p_total_dpd_balance OUT NUMBER
    ) IS
        v_dpd NUMBER;
    BEGIN
        p_delinquent_count  := 0;
        p_total_dpd_balance := 0;

        FOR loan IN (SELECT l.loan_id, l.outstanding_balance
                     FROM   loans l
                     WHERE  l.status = 'ACTIVE') LOOP
            BEGIN
                v_dpd := calc_days_past_due(loan.loan_id);

                IF v_dpd > 0 THEN
                    UPDATE loans
                    SET    days_past_due = v_dpd,
                           times_30_dpd = CASE WHEN v_dpd >= 30  THEN times_30_dpd + 1 ELSE times_30_dpd END,
                           times_60_dpd = CASE WHEN v_dpd >= 60  THEN times_60_dpd + 1 ELSE times_60_dpd END,
                           times_90_dpd = CASE WHEN v_dpd >= 90  THEN times_90_dpd + 1 ELSE times_90_dpd END,
                           updated_at   = SYSTIMESTAMP
                    WHERE  loan_id = loan.loan_id;

                    -- Update payment status
                    UPDATE loan_payments
                    SET    status = 'OVERDUE'
                    WHERE  loan_id   = loan.loan_id
                    AND    status    = 'SCHEDULED'
                    AND    due_date  < p_as_of_date - c_grace_period_days;

                    p_delinquent_count  := p_delinquent_count + 1;
                    p_total_dpd_balance := p_total_dpd_balance + loan.outstanding_balance;
                END IF;
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
        END LOOP;
    END update_delinquency_status;

    -- =========================================================================
    -- PROCEDURE: apply_late_fees
    -- =========================================================================
    PROCEDURE apply_late_fees(
        p_as_of_date    IN  DATE DEFAULT SYSDATE,
        p_fees_applied  OUT NUMBER,
        p_total_fees    OUT NUMBER
    ) IS
        v_late_fee  NUMBER;
        v_txn_id    NUMBER;
        v_fee_count NUMBER;
    BEGIN
        p_fees_applied := 0;
        p_total_fees   := 0;

        FOR loan IN (
            SELECT l.loan_id, l.loan_number, l.monthly_payment, l.account_id,
                   l.days_past_due
            FROM   loans l
            WHERE  l.status      = 'ACTIVE'
            AND    l.days_past_due > c_grace_period_days
            AND    l.account_id  IS NOT NULL
        ) LOOP
            BEGIN
                -- Check not already charged this month
                SELECT COUNT(*) INTO v_fee_count
                FROM   fee_ledger fl
                JOIN   accounts a ON fl.account_id = a.account_id
                JOIN   loans lo ON a.account_id = lo.account_id
                WHERE  lo.loan_id  = loan.loan_id
                AND    fl.fee_type = 'LATE_FEE'
                AND    TRUNC(fl.fee_date,'MM') = TRUNC(p_as_of_date,'MM');

                IF v_fee_count = 0 THEN
                    v_late_fee := ROUND(loan.monthly_payment * c_late_fee_pct, 2);
                    pkg_transactions.post_fee(
                        loan.account_id, 'LATE_FEE', v_late_fee,
                        'Late fee: Loan ' || loan.loan_number ||
                        ' (' || loan.days_past_due || ' DPD)',
                        NULL, v_txn_id
                    );
                    p_fees_applied := p_fees_applied + 1;
                    p_total_fees   := p_total_fees + v_late_fee;
                END IF;
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
        END LOOP;
    END apply_late_fees;

    -- =========================================================================
    -- PROCEDURE: charge_off_loan
    -- =========================================================================
    PROCEDURE charge_off_loan(
        p_loan_id     IN NUMBER,
        p_reason      IN VARCHAR2,
        p_employee_id IN NUMBER
    ) IS
        v_loan loans%ROWTYPE;
    BEGIN
        SELECT * INTO v_loan FROM loans WHERE loan_id = p_loan_id FOR UPDATE;

        IF v_loan.status != 'ACTIVE' THEN
            RAISE_APPLICATION_ERROR(-20058, 'Only active loans can be charged off');
        END IF;

        IF v_loan.days_past_due < c_charge_off_days THEN
            RAISE_APPLICATION_ERROR(-20059,
                'Loan must be ' || c_charge_off_days ||
                ' DPD to charge off. Current: ' || v_loan.days_past_due);
        END IF;

        UPDATE loans
        SET    status     = 'WRITTEN_OFF',
               updated_at = SYSTIMESTAMP
        WHERE  loan_id = p_loan_id;

        -- Cancel remaining scheduled payments
        UPDATE loan_payments
        SET    status = 'WAIVED'
        WHERE  loan_id = p_loan_id AND status IN ('SCHEDULED','OVERDUE');

        -- Create fraud/risk alert
        INSERT INTO fraud_alerts (
            account_id, customer_id, alert_type, severity, description
        )
        SELECT account_id, customer_id,
               'LOAN_CHARGE_OFF', 'HIGH',
               'Loan ' || loan_number || ' charged off. Balance: $' ||
               outstanding_balance || '. Reason: ' || p_reason
        FROM   loans WHERE loan_id = p_loan_id;

        p_audit('LOANS', p_loan_id, 'UPDATE',
                'status=ACTIVE,balance=' || v_loan.outstanding_balance,
                'status=WRITTEN_OFF,reason=' || p_reason);
    END charge_off_loan;

    -- =========================================================================
    -- PROCEDURE: pay_off_loan
    -- =========================================================================
    PROCEDURE pay_off_loan(
        p_loan_id        IN  NUMBER,
        p_payoff_account IN  NUMBER,
        p_employee_id    IN  NUMBER,
        p_payoff_amount  OUT NUMBER
    ) IS
        v_loan      loans%ROWTYPE;
        v_txn_id    NUMBER;
        v_ref       VARCHAR2(50);
        v_pay_id    NUMBER;
        v_prin      NUMBER;
        v_int       NUMBER;
        v_remain    NUMBER;
    BEGIN
        SELECT * INTO v_loan FROM loans WHERE loan_id = p_loan_id FOR UPDATE;

        IF v_loan.status != 'ACTIVE' THEN
            RAISE_APPLICATION_ERROR(-20050, 'Loan is not active');
        END IF;

        -- Payoff includes any accrued interest for current month
        DECLARE
            v_days_this_month NUMBER;
            v_accrued         NUMBER;
        BEGIN
            v_days_this_month := SYSDATE - TRUNC(SYSDATE, 'MM');
            v_accrued := pkg_transactions.calc_simple_interest(
                v_loan.outstanding_balance,
                v_loan.interest_rate,
                v_days_this_month
            );
            p_payoff_amount := v_loan.outstanding_balance + v_accrued;
        END;

        -- Process as final payment
        process_loan_payment(
            p_loan_id, p_payoff_amount, p_payoff_account,
            p_employee_id, v_pay_id, v_prin, v_int, v_remain
        );

        -- Ensure fully marked as paid
        UPDATE loans
        SET    status           = 'PAID_OFF',
               outstanding_balance = 0,
               updated_at       = SYSTIMESTAMP
        WHERE  loan_id = p_loan_id;

        -- Cancel remaining scheduled payments
        UPDATE loan_payments
        SET    status = 'WAIVED'
        WHERE  loan_id = p_loan_id AND status = 'SCHEDULED';
    END pay_off_loan;

    -- =========================================================================
    -- PROCEDURE: restructure_loan
    -- =========================================================================
    PROCEDURE restructure_loan(
        p_loan_id         IN  NUMBER,
        p_new_rate        IN  NUMBER,
        p_new_term_months IN  NUMBER,
        p_reason          IN  VARCHAR2,
        p_employee_id     IN  NUMBER,
        p_new_payment     OUT NUMBER
    ) IS
        v_loan loans%ROWTYPE;
    BEGIN
        SELECT * INTO v_loan FROM loans WHERE loan_id = p_loan_id FOR UPDATE;

        IF v_loan.status != 'ACTIVE' THEN
            RAISE_APPLICATION_ERROR(-20050, 'Only active loans can be restructured');
        END IF;

        p_new_payment := calc_monthly_payment(
            v_loan.outstanding_balance, p_new_rate, p_new_term_months
        );

        UPDATE loans
        SET    interest_rate   = p_new_rate,
               term_months     = p_new_term_months,
               monthly_payment = p_new_payment,
               maturity_date   = ADD_MONTHS(SYSDATE, p_new_term_months),
               updated_at      = SYSTIMESTAMP
        WHERE  loan_id = p_loan_id;

        -- Regenerate amortization
        generate_amortization_schedule(p_loan_id, SYSDATE);

        p_audit('LOANS', p_loan_id, 'UPDATE',
                'rate=' || v_loan.interest_rate || ',term=' || v_loan.term_months,
                'new_rate=' || p_new_rate || ',new_term=' || p_new_term_months ||
                ',reason=' || p_reason);
    END restructure_loan;

END pkg_loan_mgmt;
/

SHOW ERRORS PACKAGE BODY pkg_loan_mgmt;
