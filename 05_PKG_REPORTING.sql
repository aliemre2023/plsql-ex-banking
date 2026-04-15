-- =============================================================================
-- PACKAGE 4: PKG_REPORTING
-- Banking Reports & Analytics Package
-- Handles: Customer statements, risk reports, portfolio analytics,
--          regulatory reports, branch performance
-- Depends on: PKG_ACCOUNT_MGMT, PKG_TRANSACTIONS, PKG_LOAN_MGMT
-- =============================================================================

CREATE OR REPLACE PACKAGE pkg_reporting AS

    -- -------------------------------------------------------------------------
    -- FUNCTIONS
    -- -------------------------------------------------------------------------

    -- Returns customer net worth (all accounts)
    FUNCTION get_customer_net_worth(p_customer_id IN NUMBER) RETURN NUMBER;

    -- Returns average account balance over N months
    FUNCTION get_avg_balance_n_months(p_account_id IN NUMBER, p_months IN NUMBER) RETURN NUMBER;

    -- Returns branch total deposits
    FUNCTION get_branch_total_deposits(p_branch_id IN NUMBER) RETURN NUMBER;

    -- Returns branch total loan portfolio
    FUNCTION get_branch_loan_portfolio(p_branch_id IN NUMBER) RETURN NUMBER;

    -- Computes loan-to-deposit ratio for a branch
    FUNCTION calc_ldr(p_branch_id IN NUMBER) RETURN NUMBER;

    -- Returns non-performing loan ratio
    FUNCTION calc_npl_ratio(p_branch_id IN NUMBER DEFAULT NULL) RETURN NUMBER;

    -- Returns customer lifetime value score
    FUNCTION calc_customer_ltv(p_customer_id IN NUMBER) RETURN NUMBER;

    -- Returns month-over-month growth for deposits
    FUNCTION calc_deposit_growth_pct(
        p_branch_id   IN NUMBER DEFAULT NULL,
        p_month_count IN NUMBER DEFAULT 1
    ) RETURN NUMBER;

    -- -------------------------------------------------------------------------
    -- PROCEDURES
    -- -------------------------------------------------------------------------

    -- Generates account statement for a period
    PROCEDURE generate_account_statement(
        p_account_id   IN  NUMBER,
        p_from_date    IN  DATE,
        p_to_date      IN  DATE,
        p_statement    OUT SYS_REFCURSOR
    );

    -- Generates customer portfolio summary
    PROCEDURE generate_customer_portfolio(
        p_customer_id  IN  NUMBER,
        p_summary      OUT SYS_REFCURSOR
    );

    -- Generates branch performance report
    PROCEDURE generate_branch_report(
        p_branch_id    IN  NUMBER,
        p_as_of_date   IN  DATE DEFAULT SYSDATE,
        p_report       OUT SYS_REFCURSOR
    );

    -- Generates delinquency report (regulatory)
    PROCEDURE generate_delinquency_report(
        p_as_of_date   IN  DATE DEFAULT SYSDATE,
        p_report       OUT SYS_REFCURSOR
    );

    -- Generates SAR/CTR suspicious activity summary
    PROCEDURE generate_suspicious_activity_report(
        p_from_date    IN  DATE,
        p_to_date      IN  DATE,
        p_report       OUT SYS_REFCURSOR
    );

    -- Generates top customer ranking by balance
    PROCEDURE get_top_customers(
        p_top_n        IN  NUMBER DEFAULT 10,
        p_branch_id    IN  NUMBER DEFAULT NULL,
        p_result       OUT SYS_REFCURSOR
    );

    -- Generates transaction velocity report (fraud support)
    PROCEDURE transaction_velocity_report(
        p_from_date    IN  DATE,
        p_to_date      IN  DATE,
        p_threshold    IN  NUMBER DEFAULT 5,  -- Min transactions to flag
        p_report       OUT SYS_REFCURSOR
    );

    -- Generates interest income summary by account type
    PROCEDURE interest_income_summary(
        p_year        IN  NUMBER DEFAULT TO_NUMBER(TO_CHAR(SYSDATE,'YYYY')),
        p_report      OUT SYS_REFCURSOR
    );

    -- Generates fee income report
    PROCEDURE fee_income_report(
        p_from_date   IN  DATE,
        p_to_date     IN  DATE,
        p_report      OUT SYS_REFCURSOR
    );

    -- Generates loan portfolio by risk bucket
    PROCEDURE loan_portfolio_risk_report(
        p_as_of_date  IN  DATE DEFAULT SYSDATE,
        p_report      OUT SYS_REFCURSOR
    );

END pkg_reporting;
/

CREATE OR REPLACE PACKAGE BODY pkg_reporting AS

    -- =========================================================================
    -- FUNCTION: get_customer_net_worth
    -- =========================================================================
    FUNCTION get_customer_net_worth(p_customer_id IN NUMBER) RETURN NUMBER IS
        v_deposits NUMBER;
        v_loans    NUMBER;
    BEGIN
        SELECT NVL(SUM(balance), 0)
        INTO   v_deposits
        FROM   accounts
        WHERE  customer_id = p_customer_id
        AND    status != 'CLOSED';

        SELECT NVL(SUM(outstanding_balance), 0)
        INTO   v_loans
        FROM   loans
        WHERE  customer_id = p_customer_id
        AND    status = 'ACTIVE';

        RETURN v_deposits - v_loans;
    END get_customer_net_worth;

    -- =========================================================================
    -- FUNCTION: get_avg_balance_n_months
    -- =========================================================================
    FUNCTION get_avg_balance_n_months(p_account_id IN NUMBER, p_months IN NUMBER) RETURN NUMBER IS
        v_avg NUMBER;
    BEGIN
        WITH monthly_closing AS (
            SELECT TRUNC(transaction_date,'MM') AS month,
                   -- Last balance in the month
                   LAST_VALUE(balance_after) OVER (
                       PARTITION BY TRUNC(transaction_date,'MM')
                       ORDER BY transaction_date
                       ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
                   ) AS closing_balance
            FROM   transactions
            WHERE  account_id = p_account_id
            AND    transaction_date >= ADD_MONTHS(TRUNC(SYSDATE,'MM'), -p_months)
        )
        SELECT NVL(AVG(DISTINCT closing_balance), 0)
        INTO   v_avg
        FROM   monthly_closing;

        RETURN ROUND(v_avg, 2);
    END get_avg_balance_n_months;

    -- =========================================================================
    -- FUNCTION: get_branch_total_deposits
    -- =========================================================================
    FUNCTION get_branch_total_deposits(p_branch_id IN NUMBER) RETURN NUMBER IS
        v_total NUMBER;
    BEGIN
        SELECT NVL(SUM(balance), 0)
        INTO   v_total
        FROM   accounts
        WHERE  branch_id = p_branch_id
        AND    status    = 'ACTIVE';
        RETURN v_total;
    END get_branch_total_deposits;

    -- =========================================================================
    -- FUNCTION: get_branch_loan_portfolio
    -- =========================================================================
    FUNCTION get_branch_loan_portfolio(p_branch_id IN NUMBER) RETURN NUMBER IS
        v_total NUMBER;
    BEGIN
        SELECT NVL(SUM(outstanding_balance), 0)
        INTO   v_total
        FROM   loans
        WHERE  branch_id = p_branch_id
        AND    status = 'ACTIVE';
        RETURN v_total;
    END get_branch_loan_portfolio;

    -- =========================================================================
    -- FUNCTION: calc_ldr (Loan-to-Deposit Ratio)
    -- =========================================================================
    FUNCTION calc_ldr(p_branch_id IN NUMBER) RETURN NUMBER IS
        v_loans    NUMBER := get_branch_loan_portfolio(p_branch_id);
        v_deposits NUMBER := get_branch_total_deposits(p_branch_id);
    BEGIN
        IF v_deposits = 0 THEN RETURN 0; END IF;
        RETURN ROUND(v_loans / v_deposits, 4);
    END calc_ldr;

    -- =========================================================================
    -- FUNCTION: calc_npl_ratio (Non-Performing Loan Ratio)
    -- =========================================================================
    FUNCTION calc_npl_ratio(p_branch_id IN NUMBER DEFAULT NULL) RETURN NUMBER IS
        v_total_loans NUMBER;
        v_npl         NUMBER;
    BEGIN
        SELECT NVL(SUM(outstanding_balance), 0)
        INTO   v_total_loans
        FROM   loans
        WHERE  status = 'ACTIVE'
        AND    (p_branch_id IS NULL OR branch_id = p_branch_id);

        SELECT NVL(SUM(outstanding_balance), 0)
        INTO   v_npl
        FROM   loans
        WHERE  status      = 'ACTIVE'
        AND    days_past_due >= 90  -- 90+ DPD = non-performing
        AND    (p_branch_id IS NULL OR branch_id = p_branch_id);

        IF v_total_loans = 0 THEN RETURN 0; END IF;
        RETURN ROUND(v_npl / v_total_loans, 4);
    END calc_npl_ratio;

    -- =========================================================================
    -- FUNCTION: calc_customer_ltv (Lifetime Value)
    -- Scoring model based on tenure, balance, products, activity
    -- =========================================================================
    FUNCTION calc_customer_ltv(p_customer_id IN NUMBER) RETURN NUMBER IS
        v_tenure_months   NUMBER;
        v_avg_balance     NUMBER;
        v_product_count   NUMBER;
        v_txn_frequency   NUMBER;  -- Avg monthly transactions
        v_interest_paid   NUMBER;
        v_fees_paid       NUMBER;
        v_ltv_score       NUMBER;
    BEGIN
        -- Tenure
        SELECT MONTHS_BETWEEN(SYSDATE, MIN(opened_date))
        INTO   v_tenure_months
        FROM   accounts WHERE customer_id = p_customer_id;

        -- Average balance across all accounts
        SELECT NVL(AVG(balance), 0)
        INTO   v_avg_balance
        FROM   accounts
        WHERE  customer_id = p_customer_id AND status != 'CLOSED';

        -- Product count
        SELECT COUNT(DISTINCT account_type) + COUNT(DISTINCT (SELECT 1 FROM loans l
                                                               WHERE l.customer_id = p_customer_id
                                                               AND l.status = 'ACTIVE'
                                                               AND ROWNUM = 1))
        INTO   v_product_count
        FROM   accounts WHERE customer_id = p_customer_id AND status = 'ACTIVE';

        -- Transaction frequency (last 12 months)
        SELECT NVL(COUNT(*) / GREATEST(1, MONTHS_BETWEEN(SYSDATE, MIN(a.opened_date))), 0)
        INTO   v_txn_frequency
        FROM   transactions t
        JOIN   accounts a ON t.account_id = a.account_id
        WHERE  a.customer_id = p_customer_id
        AND    t.transaction_date >= ADD_MONTHS(SYSDATE, -12);

        -- LTV Formula: weighted sum
        v_ltv_score :=
            (v_tenure_months    * 10)    +    -- $10 per month tenure
            (v_avg_balance      * 0.02)  +    -- 2% of avg balance
            (v_product_count    * 500)   +    -- $500 per product
            (v_txn_frequency    * 5);         -- $5 per monthly transaction

        RETURN ROUND(NVL(v_ltv_score, 0), 2);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN 0;
        WHEN OTHERS THEN RETURN 0;
    END calc_customer_ltv;

    -- =========================================================================
    -- FUNCTION: calc_deposit_growth_pct
    -- =========================================================================
    FUNCTION calc_deposit_growth_pct(
        p_branch_id   IN NUMBER DEFAULT NULL,
        p_month_count IN NUMBER DEFAULT 1
    ) RETURN NUMBER IS
        v_current_balance NUMBER;
        v_prior_balance   NUMBER;
        v_prior_date      DATE := ADD_MONTHS(SYSDATE, -p_month_count);
    BEGIN
        -- Current balance
        SELECT NVL(SUM(balance), 0)
        INTO   v_current_balance
        FROM   accounts
        WHERE  status = 'ACTIVE'
        AND    (p_branch_id IS NULL OR branch_id = p_branch_id);

        -- Approximate prior balance using transaction history
        WITH prior_state AS (
            SELECT account_id,
                   (SELECT NVL(MAX(balance_after), 0)
                    FROM   transactions t2
                    WHERE  t2.account_id   = t.account_id
                    AND    t2.transaction_date <= v_prior_date) AS prior_bal
            FROM   (SELECT DISTINCT account_id FROM transactions) t
            JOIN   accounts a USING (account_id)
            WHERE  a.status = 'ACTIVE'
            AND    (p_branch_id IS NULL OR a.branch_id = p_branch_id)
        )
        SELECT NVL(SUM(prior_bal), 0)
        INTO   v_prior_balance
        FROM   prior_state;

        IF v_prior_balance = 0 THEN RETURN 0; END IF;
        RETURN ROUND(((v_current_balance - v_prior_balance) / v_prior_balance) * 100, 2);
    END calc_deposit_growth_pct;

    -- =========================================================================
    -- PROCEDURE: generate_account_statement
    -- =========================================================================
    PROCEDURE generate_account_statement(
        p_account_id IN  NUMBER,
        p_from_date  IN  DATE,
        p_to_date    IN  DATE,
        p_statement  OUT SYS_REFCURSOR
    ) IS
    BEGIN
        OPEN p_statement FOR
            SELECT
                t.transaction_id,
                t.transaction_date,
                t.value_date,
                t.transaction_type,
                t.description,
                t.reference_number,
                t.channel,
                CASE WHEN t.transaction_type IN ('DEPOSIT','TRANSFER_IN','INTEREST','ADJUSTMENT')
                     THEN t.amount ELSE NULL END AS credit_amount,
                CASE WHEN t.transaction_type IN ('WITHDRAWAL','TRANSFER_OUT','FEE','PAYMENT')
                     THEN t.amount ELSE NULL END AS debit_amount,
                t.balance_after                   AS running_balance,
                t.status,
                -- Related account info for transfers
                ra.account_number                 AS related_account_number,
                (SELECT c.first_name || ' ' || c.last_name
                 FROM   customers c
                 JOIN   accounts ra2 ON c.customer_id = ra2.customer_id
                 WHERE  ra2.account_id = t.related_account_id)
                                                  AS related_party_name,
                e.first_name || ' ' || e.last_name AS processed_by_name
            FROM   transactions t
            LEFT JOIN accounts ra ON t.related_account_id = ra.account_id
            LEFT JOIN employees e ON t.processed_by = e.employee_id
            WHERE  t.account_id = p_account_id
            AND    TRUNC(t.transaction_date) BETWEEN p_from_date AND p_to_date
            AND    t.status != 'FAILED'
            ORDER  BY t.transaction_date, t.transaction_id;
    END generate_account_statement;

    -- =========================================================================
    -- PROCEDURE: generate_customer_portfolio
    -- =========================================================================
    PROCEDURE generate_customer_portfolio(
        p_customer_id IN  NUMBER,
        p_summary     OUT SYS_REFCURSOR
    ) IS
    BEGIN
        OPEN p_summary FOR
            -- Accounts section
            SELECT
                'ACCOUNT'                          AS product_type,
                a.account_id                       AS product_id,
                a.account_number                   AS product_number,
                at.type_name                       AS product_name,
                a.balance                          AS balance,
                a.available_balance                AS available_balance,
                a.status,
                a.opened_date,
                NULL                               AS interest_rate,
                NULL                               AS monthly_payment,
                NULL                               AS outstanding_balance,
                a.currency,
                (SELECT COUNT(*)
                 FROM   transactions t
                 WHERE  t.account_id = a.account_id
                 AND    t.transaction_date >= ADD_MONTHS(SYSDATE,-3)) AS txn_last_90d,
                pkg_account_mgmt.get_account_age_days(a.account_id) AS age_days
            FROM   accounts a
            JOIN   account_types at ON a.account_type = at.type_code
            WHERE  a.customer_id = p_customer_id
            UNION ALL
            -- Loans section
            SELECT
                'LOAN'                             AS product_type,
                l.loan_id                          AS product_id,
                l.loan_number                      AS product_number,
                l.loan_type                        AS product_name,
                NULL                               AS balance,
                NULL                               AS available_balance,
                l.status,
                l.disbursement_date                AS opened_date,
                l.interest_rate,
                l.monthly_payment,
                l.outstanding_balance,
                'USD'                              AS currency,
                l.days_past_due                    AS txn_last_90d,
                TRUNC(SYSDATE - NVL(l.disbursement_date, l.created_at)) AS age_days
            FROM   loans l
            WHERE  l.customer_id = p_customer_id
            ORDER  BY 1, 4;
    END generate_customer_portfolio;

    -- =========================================================================
    -- PROCEDURE: generate_branch_report
    -- =========================================================================
    PROCEDURE generate_branch_report(
        p_branch_id  IN  NUMBER,
        p_as_of_date IN  DATE DEFAULT SYSDATE,
        p_report     OUT SYS_REFCURSOR
    ) IS
    BEGIN
        OPEN p_report FOR
            WITH branch_metrics AS (
                SELECT
                    b.branch_id,
                    b.branch_name,
                    b.branch_code,
                    COUNT(DISTINCT a.customer_id)                            AS total_customers,
                    COUNT(DISTINCT CASE WHEN a.status='ACTIVE' THEN a.account_id END) AS active_accounts,
                    NVL(SUM(CASE WHEN a.status='ACTIVE' THEN a.balance END),0) AS total_deposits,
                    NVL(AVG(CASE WHEN a.status='ACTIVE' THEN a.balance END),0) AS avg_account_balance,
                    COUNT(DISTINCT CASE WHEN a.account_type='CHECKING' AND a.status='ACTIVE'
                          THEN a.account_id END) AS checking_accounts,
                    COUNT(DISTINCT CASE WHEN a.account_type='SAVINGS' AND a.status='ACTIVE'
                          THEN a.account_id END) AS savings_accounts,
                    -- New accounts this month
                    COUNT(DISTINCT CASE WHEN a.opened_date >= TRUNC(p_as_of_date,'MM')
                          THEN a.account_id END) AS new_accounts_mtd,
                    -- Closed accounts this month
                    COUNT(DISTINCT CASE WHEN a.closed_date >= TRUNC(p_as_of_date,'MM')
                          THEN a.account_id END) AS closed_accounts_mtd
                FROM   branches b
                LEFT JOIN accounts a ON b.branch_id = a.branch_id
                WHERE  b.branch_id = p_branch_id
                GROUP  BY b.branch_id, b.branch_name, b.branch_code
            ),
            loan_metrics AS (
                SELECT
                    l.branch_id,
                    COUNT(*) FILTER (WHERE l.status='ACTIVE')                AS active_loans,
                    NVL(SUM(CASE WHEN l.status='ACTIVE'
                         THEN l.outstanding_balance END),0)                  AS total_loan_balance,
                    NVL(SUM(CASE WHEN l.status='ACTIVE' AND l.days_past_due > 0
                         THEN l.outstanding_balance END),0)                  AS delinquent_balance,
                    COUNT(CASE WHEN l.status='ACTIVE' AND l.days_past_due>=30
                         THEN 1 END)                                         AS loans_30dpd,
                    COUNT(CASE WHEN l.status='ACTIVE' AND l.days_past_due>=90
                         THEN 1 END)                                         AS loans_90dpd,
                    -- New loans this month
                    COUNT(CASE WHEN l.disbursement_date >= TRUNC(p_as_of_date,'MM')
                         AND l.status='ACTIVE' THEN 1 END)                   AS new_loans_mtd,
                    NVL(SUM(CASE WHEN l.disbursement_date >= TRUNC(p_as_of_date,'MM')
                         AND l.status='ACTIVE' THEN l.principal_amount END),0) AS new_loan_amt_mtd
                FROM   loans l
                WHERE  l.branch_id = p_branch_id
                GROUP  BY l.branch_id
            ),
            txn_metrics AS (
                SELECT
                    a.branch_id,
                    COUNT(t.transaction_id)                                  AS total_txns_mtd,
                    NVL(SUM(CASE WHEN t.transaction_type='DEPOSIT'
                         THEN t.amount END),0)                               AS deposits_mtd,
                    NVL(SUM(CASE WHEN t.transaction_type='WITHDRAWAL'
                         THEN t.amount END),0)                               AS withdrawals_mtd,
                    NVL(SUM(CASE WHEN t.transaction_type='FEE'
                         THEN t.amount END),0)                               AS fee_income_mtd,
                    NVL(SUM(CASE WHEN t.transaction_type='INTEREST'
                         THEN t.amount END),0)                               AS interest_posted_mtd
                FROM   transactions t
                JOIN   accounts a ON t.account_id = a.account_id
                WHERE  a.branch_id = p_branch_id
                AND    t.transaction_date >= TRUNC(p_as_of_date,'MM')
                AND    t.status = 'COMPLETED'
                GROUP  BY a.branch_id
            )
            SELECT
                bm.*,
                NVL(lm.active_loans, 0)          AS active_loans,
                NVL(lm.total_loan_balance, 0)     AS total_loan_balance,
                NVL(lm.delinquent_balance, 0)     AS delinquent_balance,
                NVL(lm.loans_30dpd, 0)            AS loans_30dpd,
                NVL(lm.loans_90dpd, 0)            AS loans_90dpd,
                NVL(lm.new_loans_mtd, 0)          AS new_loans_mtd,
                NVL(lm.new_loan_amt_mtd, 0)       AS new_loan_amt_mtd,
                NVL(tm.total_txns_mtd, 0)         AS total_txns_mtd,
                NVL(tm.deposits_mtd, 0)           AS deposits_mtd,
                NVL(tm.withdrawals_mtd, 0)        AS withdrawals_mtd,
                NVL(tm.fee_income_mtd, 0)         AS fee_income_mtd,
                NVL(tm.interest_posted_mtd, 0)    AS interest_posted_mtd,
                -- Ratios
                ROUND(NVL(lm.total_loan_balance,0) /
                      NULLIF(bm.total_deposits,0), 4)  AS loan_to_deposit_ratio,
                ROUND(NVL(lm.delinquent_balance,0) /
                      NULLIF(lm.total_loan_balance,0) * 100, 2) AS npl_ratio_pct
            FROM   branch_metrics bm
            LEFT JOIN loan_metrics lm ON bm.branch_id = lm.branch_id
            LEFT JOIN txn_metrics  tm ON bm.branch_id = tm.branch_id;
    END generate_branch_report;

    -- =========================================================================
    -- PROCEDURE: generate_delinquency_report
    -- =========================================================================
    PROCEDURE generate_delinquency_report(
        p_as_of_date IN  DATE DEFAULT SYSDATE,
        p_report     OUT SYS_REFCURSOR
    ) IS
    BEGIN
        OPEN p_report FOR
            SELECT
                l.loan_id,
                l.loan_number,
                l.loan_type,
                c.customer_id,
                c.first_name || ' ' || c.last_name       AS customer_name,
                c.email,
                c.phone,
                b.branch_name,
                l.principal_amount,
                l.outstanding_balance,
                l.monthly_payment,
                l.interest_rate,
                l.days_past_due,
                -- DPD bucket
                CASE
                    WHEN l.days_past_due = 0       THEN 'CURRENT'
                    WHEN l.days_past_due <= 29     THEN '1-29 DPD'
                    WHEN l.days_past_due <= 59     THEN '30-59 DPD'
                    WHEN l.days_past_due <= 89     THEN '60-89 DPD'
                    WHEN l.days_past_due <= 119    THEN '90-119 DPD'
                    WHEN l.days_past_due <= 179    THEN '120-179 DPD'
                    ELSE '180+ DPD (Charge-off)'
                END                                      AS dpd_bucket,
                l.times_30_dpd,
                l.times_60_dpd,
                l.times_90_dpd,
                -- Next payment
                (SELECT MIN(lp.due_date)
                 FROM   loan_payments lp
                 WHERE  lp.loan_id = l.loan_id
                 AND    lp.status IN ('OVERDUE','SCHEDULED'))  AS next_due_date,
                -- Amount past due
                (SELECT NVL(SUM(lp.scheduled_amount - NVL(lp.paid_amount,0)),0)
                 FROM   loan_payments lp
                 WHERE  lp.loan_id = l.loan_id
                 AND    lp.status = 'OVERDUE')               AS amount_past_due,
                l.collateral_type,
                l.collateral_value,
                c.credit_score,
                c.risk_level,
                -- Recommended action
                CASE
                    WHEN l.days_past_due >= 180 THEN 'INITIATE CHARGE-OFF'
                    WHEN l.days_past_due >= 90  THEN 'LEGAL/COLLECTIONS REFERRAL'
                    WHEN l.days_past_due >= 60  THEN 'WORKOUT/RESTRUCTURE'
                    WHEN l.days_past_due >= 30  THEN 'CONTACT CUSTOMER'
                    ELSE 'MONITOR'
                END                                          AS recommended_action
            FROM   loans l
            JOIN   customers c ON l.customer_id = c.customer_id
            JOIN   branches  b ON l.branch_id   = b.branch_id
            WHERE  l.status = 'ACTIVE'
            ORDER  BY l.days_past_due DESC, l.outstanding_balance DESC;
    END generate_delinquency_report;

    -- =========================================================================
    -- PROCEDURE: generate_suspicious_activity_report
    -- =========================================================================
    PROCEDURE generate_suspicious_activity_report(
        p_from_date IN  DATE,
        p_to_date   IN  DATE,
        p_report    OUT SYS_REFCURSOR
    ) IS
    BEGIN
        OPEN p_report FOR
            WITH large_cash AS (
                -- CTR: Cash transactions >= $10,000
                SELECT
                    t.transaction_id,
                    t.account_id,
                    a.customer_id,
                    'CTR_REQUIRED'             AS alert_type,
                    t.amount,
                    t.transaction_date,
                    t.channel,
                    'Cash transaction >= $10,000' AS description
                FROM   transactions t
                JOIN   accounts a ON t.account_id = a.account_id
                WHERE  t.transaction_type IN ('DEPOSIT','WITHDRAWAL')
                AND    t.amount >= 10000
                AND    TRUNC(t.transaction_date) BETWEEN p_from_date AND p_to_date
                AND    t.status = 'COMPLETED'
            ),
            structuring AS (
                -- Structuring: Multiple transactions just under $10k same day
                SELECT
                    t.transaction_id,
                    t.account_id,
                    a.customer_id,
                    'STRUCTURING_POSSIBLE'     AS alert_type,
                    t.amount,
                    t.transaction_date,
                    t.channel,
                    'Multiple transactions totaling >= $9,000' AS description
                FROM   transactions t
                JOIN   accounts a ON t.account_id = a.account_id
                WHERE  t.transaction_type = 'DEPOSIT'
                AND    TRUNC(t.transaction_date) BETWEEN p_from_date AND p_to_date
                AND    t.status = 'COMPLETED'
                AND    (SELECT SUM(t2.amount)
                        FROM   transactions t2
                        WHERE  t2.account_id = t.account_id
                        AND    t2.transaction_type = 'DEPOSIT'
                        AND    TRUNC(t2.transaction_date) = TRUNC(t.transaction_date)
                        AND    t2.status = 'COMPLETED') BETWEEN 9000 AND 9999.99
            ),
            rapid_movement AS (
                -- Large deposit followed by withdrawal within 24 hours
                SELECT
                    t1.transaction_id,
                    t1.account_id,
                    a.customer_id,
                    'RAPID_MOVEMENT'           AS alert_type,
                    t1.amount,
                    t1.transaction_date,
                    t1.channel,
                    'Large deposit followed by withdrawal within 24hrs' AS description
                FROM   transactions t1
                JOIN   accounts a ON t1.account_id = a.account_id
                WHERE  t1.transaction_type = 'DEPOSIT'
                AND    t1.amount >= 5000
                AND    TRUNC(t1.transaction_date) BETWEEN p_from_date AND p_to_date
                AND    EXISTS (
                    SELECT 1 FROM transactions t2
                    WHERE  t2.account_id     = t1.account_id
                    AND    t2.transaction_type = 'WITHDRAWAL'
                    AND    t2.amount         >= t1.amount * 0.9
                    AND    t2.transaction_date BETWEEN t1.transaction_date
                                             AND t1.transaction_date + INTERVAL '1' DAY
                )
            )
            SELECT
                ua.alert_type,
                ua.transaction_id,
                ua.account_id,
                a.account_number,
                ua.customer_id,
                c.first_name || ' ' || c.last_name AS customer_name,
                c.risk_level,
                ua.amount,
                ua.transaction_date,
                ua.channel,
                ua.description,
                -- Existing fraud alert if any
                (SELECT fa.alert_id FROM fraud_alerts fa
                 WHERE  fa.transaction_id = ua.transaction_id
                 AND    ROWNUM = 1)        AS fraud_alert_id,
                c.credit_score
            FROM (
                SELECT * FROM large_cash
                UNION ALL
                SELECT * FROM structuring
                UNION ALL
                SELECT * FROM rapid_movement
            ) ua
            JOIN accounts  a ON ua.account_id  = a.account_id
            JOIN customers c ON ua.customer_id = c.customer_id
            ORDER BY ua.amount DESC, ua.transaction_date DESC;
    END generate_suspicious_activity_report;

    -- =========================================================================
    -- PROCEDURE: get_top_customers
    -- =========================================================================
    PROCEDURE get_top_customers(
        p_top_n     IN  NUMBER DEFAULT 10,
        p_branch_id IN  NUMBER DEFAULT NULL,
        p_result    OUT SYS_REFCURSOR
    ) IS
    BEGIN
        OPEN p_result FOR
            SELECT * FROM (
                SELECT
                    c.customer_id,
                    c.customer_code,
                    c.first_name || ' ' || c.last_name              AS customer_name,
                    c.customer_type,
                    c.credit_score,
                    COUNT(DISTINCT a.account_id)                    AS account_count,
                    NVL(SUM(a.balance),0)                           AS total_balance,
                    NVL(SUM(CASE WHEN a.account_type='SAVINGS'
                         THEN a.balance END),0)                     AS savings_balance,
                    NVL(SUM(CASE WHEN a.account_type='CHECKING'
                         THEN a.balance END),0)                     AS checking_balance,
                    (SELECT NVL(SUM(l.outstanding_balance),0)
                     FROM loans l WHERE l.customer_id = c.customer_id
                     AND l.status='ACTIVE')                         AS total_loan_balance,
                    pkg_reporting.get_customer_net_worth(c.customer_id) AS net_worth,
                    pkg_reporting.calc_customer_ltv(c.customer_id)     AS ltv_score,
                    (SELECT COUNT(*) FROM transactions t JOIN accounts a2
                     ON t.account_id = a2.account_id
                     WHERE a2.customer_id = c.customer_id
                     AND t.transaction_date >= ADD_MONTHS(SYSDATE,-3))  AS txns_last_90d,
                    RANK() OVER (ORDER BY NVL(SUM(a.balance),0) DESC)  AS balance_rank
                FROM   customers c
                JOIN   accounts  a ON c.customer_id = a.customer_id
                WHERE  a.status = 'ACTIVE'
                AND    (p_branch_id IS NULL OR a.branch_id = p_branch_id)
                GROUP  BY c.customer_id, c.customer_code, c.first_name,
                          c.last_name, c.customer_type, c.credit_score
            )
            WHERE balance_rank <= p_top_n
            ORDER BY balance_rank;
    END get_top_customers;

    -- =========================================================================
    -- PROCEDURE: transaction_velocity_report
    -- =========================================================================
    PROCEDURE transaction_velocity_report(
        p_from_date IN  DATE,
        p_to_date   IN  DATE,
        p_threshold IN  NUMBER DEFAULT 5,
        p_report    OUT SYS_REFCURSOR
    ) IS
    BEGIN
        OPEN p_report FOR
            WITH daily_velocity AS (
                SELECT
                    a.account_id,
                    a.account_number,
                    a.customer_id,
                    TRUNC(t.transaction_date)                       AS txn_date,
                    COUNT(*)                                        AS daily_txn_count,
                    SUM(t.amount)                                   AS daily_volume,
                    SUM(CASE WHEN t.transaction_type='DEPOSIT'
                         THEN t.amount ELSE 0 END)                 AS daily_deposits,
                    SUM(CASE WHEN t.transaction_type='WITHDRAWAL'
                         THEN t.amount ELSE 0 END)                 AS daily_withdrawals,
                    COUNT(DISTINCT t.channel)                      AS channels_used,
                    -- Unusual hour activity (between midnight and 5am)
                    COUNT(CASE WHEN TO_NUMBER(TO_CHAR(t.transaction_date,'HH24')) < 5
                         THEN 1 END)                               AS off_hours_txns
                FROM   transactions t
                JOIN   accounts a ON t.account_id = a.account_id
                WHERE  TRUNC(t.transaction_date) BETWEEN p_from_date AND p_to_date
                AND    t.status = 'COMPLETED'
                GROUP  BY a.account_id, a.account_number, a.customer_id,
                          TRUNC(t.transaction_date)
                HAVING COUNT(*) >= p_threshold
            )
            SELECT
                dv.*,
                c.first_name || ' ' || c.last_name  AS customer_name,
                c.risk_level,
                c.customer_type,
                -- Flag if suspicious
                CASE
                    WHEN dv.daily_txn_count >= p_threshold * 3   THEN 'HIGH'
                    WHEN dv.off_hours_txns > 2                   THEN 'MEDIUM'
                    WHEN dv.channels_used >= 3                   THEN 'MEDIUM'
                    ELSE 'LOW'
                END                                 AS velocity_risk,
                -- Existing fraud alerts for this account
                (SELECT COUNT(*) FROM fraud_alerts fa
                 WHERE fa.account_id = dv.account_id
                 AND   fa.status = 'OPEN')          AS open_alerts
            FROM   daily_velocity dv
            JOIN   customers c ON dv.customer_id = c.customer_id
            ORDER  BY dv.daily_txn_count DESC, dv.daily_volume DESC;
    END transaction_velocity_report;

    -- =========================================================================
    -- PROCEDURE: interest_income_summary
    -- =========================================================================
    PROCEDURE interest_income_summary(
        p_year   IN  NUMBER DEFAULT TO_NUMBER(TO_CHAR(SYSDATE,'YYYY')),
        p_report OUT SYS_REFCURSOR
    ) IS
    BEGIN
        OPEN p_report FOR
            SELECT
                TO_CHAR(ip.posting_date,'MON-YYYY')         AS period,
                a.account_type,
                at.type_name,
                COUNT(ip.posting_id)                        AS accounts_posted,
                ROUND(AVG(ip.interest_rate),4)              AS avg_rate,
                ROUND(AVG(ip.average_balance),2)            AS avg_balance,
                ROUND(SUM(ip.gross_interest),2)             AS gross_interest,
                ROUND(SUM(ip.tax_withheld),2)               AS tax_withheld,
                ROUND(SUM(ip.net_interest),2)               AS net_interest,
                ROUND(SUM(ip.gross_interest) / NULLIF(SUM(ip.average_balance),0) * 100,4)
                                                            AS effective_yield_pct
            FROM   interest_postings ip
            JOIN   accounts a ON ip.account_id = a.account_id
            JOIN   account_types at ON a.account_type = at.type_code
            WHERE  TO_NUMBER(TO_CHAR(ip.posting_date,'YYYY')) = p_year
            GROUP  BY TO_CHAR(ip.posting_date,'MON-YYYY'),
                      TO_CHAR(ip.posting_date,'YYYYMM'),
                      a.account_type, at.type_name
            ORDER  BY TO_CHAR(ip.posting_date,'YYYYMM'), a.account_type;
    END interest_income_summary;

    -- =========================================================================
    -- PROCEDURE: fee_income_report
    -- =========================================================================
    PROCEDURE fee_income_report(
        p_from_date IN  DATE,
        p_to_date   IN  DATE,
        p_report    OUT SYS_REFCURSOR
    ) IS
    BEGIN
        OPEN p_report FOR
            SELECT
                fl.fee_type,
                COUNT(*)                                   AS fee_count,
                ROUND(SUM(fl.fee_amount),2)                AS gross_fees,
                COUNT(CASE WHEN fl.waived='Y' THEN 1 END)  AS waived_count,
                ROUND(SUM(CASE WHEN fl.waived='Y' THEN fl.fee_amount ELSE 0 END),2)
                                                           AS waived_amount,
                ROUND(SUM(CASE WHEN fl.waived='N' THEN fl.fee_amount ELSE 0 END),2)
                                                           AS net_fee_income,
                ROUND(COUNT(CASE WHEN fl.waived='Y' THEN 1 END) /
                      NULLIF(COUNT(*),0) * 100, 2)         AS waiver_rate_pct,
                -- Top branch collecting this fee
                (SELECT b.branch_name
                 FROM   accounts ac JOIN branches b ON ac.branch_id = b.branch_id
                 WHERE  ac.account_id = (
                     SELECT fl2.account_id FROM fee_ledger fl2
                     WHERE fl2.fee_type = fl.fee_type
                     AND TRUNC(fl2.fee_date) BETWEEN p_from_date AND p_to_date
                     GROUP BY fl2.account_id
                     ORDER BY SUM(fl2.fee_amount) DESC
                     FETCH FIRST 1 ROW ONLY)
                 FETCH FIRST 1 ROW ONLY)                  AS top_branch
            FROM   fee_ledger fl
            WHERE  TRUNC(fl.fee_date) BETWEEN p_from_date AND p_to_date
            GROUP  BY fl.fee_type
            ORDER  BY net_fee_income DESC;
    END fee_income_report;

    -- =========================================================================
    -- PROCEDURE: loan_portfolio_risk_report
    -- =========================================================================
    PROCEDURE loan_portfolio_risk_report(
        p_as_of_date IN  DATE DEFAULT SYSDATE,
        p_report     OUT SYS_REFCURSOR
    ) IS
    BEGIN
        OPEN p_report FOR
            SELECT
                l.loan_type,
                CASE
                    WHEN l.days_past_due = 0       THEN 'Pass (Current)'
                    WHEN l.days_past_due <= 29     THEN 'Watch (1-29 DPD)'
                    WHEN l.days_past_due <= 89     THEN 'Substandard (30-89 DPD)'
                    WHEN l.days_past_due <= 179    THEN 'Doubtful (90-179 DPD)'
                    ELSE 'Loss (180+ DPD)'
                END                                       AS risk_classification,
                COUNT(*)                                  AS loan_count,
                ROUND(SUM(l.outstanding_balance),2)       AS outstanding_balance,
                ROUND(AVG(l.outstanding_balance),2)       AS avg_loan_size,
                ROUND(AVG(l.interest_rate),4)             AS avg_rate,
                ROUND(AVG(l.credit_score_at_origination),0) AS avg_orig_credit_score,
                -- Required reserve (% of outstanding by classification)
                ROUND(SUM(l.outstanding_balance) *
                    CASE
                        WHEN l.days_past_due = 0    THEN 0.01
                        WHEN l.days_past_due <= 29  THEN 0.05
                        WHEN l.days_past_due <= 89  THEN 0.15
                        WHEN l.days_past_due <= 179 THEN 0.50
                        ELSE 1.00
                    END, 2)                               AS required_reserve,
                ROUND(SUM(l.outstanding_balance) /
                      (SELECT NVL(SUM(outstanding_balance),1)
                       FROM loans WHERE status='ACTIVE') * 100, 2) AS portfolio_pct,
                -- Collateral coverage
                ROUND(NVL(SUM(l.collateral_value),0),2)  AS total_collateral,
                ROUND(NVL(SUM(l.collateral_value),0) /
                      NULLIF(SUM(l.outstanding_balance),0),4) AS collateral_coverage
            FROM   loans l
            WHERE  l.status = 'ACTIVE'
            GROUP  BY l.loan_type,
                CASE
                    WHEN l.days_past_due = 0       THEN 'Pass (Current)'
                    WHEN l.days_past_due <= 29     THEN 'Watch (1-29 DPD)'
                    WHEN l.days_past_due <= 89     THEN 'Substandard (30-89 DPD)'
                    WHEN l.days_past_due <= 179    THEN 'Doubtful (90-179 DPD)'
                    ELSE 'Loss (180+ DPD)'
                END
            ORDER  BY l.loan_type, MIN(l.days_past_due);
    END loan_portfolio_risk_report;

END pkg_reporting;
/

SHOW ERRORS PACKAGE BODY pkg_reporting;
