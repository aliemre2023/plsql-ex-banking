-- =============================================================================
-- PACKAGE 8: PKG_ADVANCED_RISK_ENGINE
-- Advanced Risk Engine Package
-- Handles: Credit risk scoring, stress testing, regulatory capital (Basel III),
--          liquidity risk, concentration risk, Value-at-Risk, risk scorecards,
--          expected loss calculation, RAROC computation
-- Depends on: PKG_ACCOUNT_MGMT, PKG_TRANSACTIONS, PKG_LOAN_MGMT, PKG_REPORTING
-- =============================================================================

CREATE OR REPLACE PACKAGE pkg_advanced_risk_engine AS

    -- -------------------------------------------------------------------------
    -- Constants
    -- -------------------------------------------------------------------------
    c_pd_floor               CONSTANT NUMBER := 0.0003;   -- Minimum PD 0.03%
    c_pd_ceiling             CONSTANT NUMBER := 0.9900;   -- Maximum PD 99%
    c_lgd_secured            CONSTANT NUMBER := 0.35;     -- LGD for secured
    c_lgd_unsecured          CONSTANT NUMBER := 0.65;     -- LGD for unsecured
    c_lgd_mortgage           CONSTANT NUMBER := 0.20;     -- LGD for mortgage
    c_capital_conservation   CONSTANT NUMBER := 0.025;    -- Basel III buffer
    c_countercyclical_buffer CONSTANT NUMBER := 0.025;
    c_tier1_min_ratio        CONSTANT NUMBER := 0.06;     -- 6% Tier 1
    c_total_capital_min      CONSTANT NUMBER := 0.08;     -- 8% Total CAR
    c_lcr_minimum            CONSTANT NUMBER := 1.00;     -- LCR >= 100%
    c_nsfr_minimum           CONSTANT NUMBER := 1.00;     -- NSFR >= 100%
    c_hhi_threshold          CONSTANT NUMBER := 0.25;     -- HHI concentration
    c_var_confidence_95      CONSTANT NUMBER := 0.95;
    c_var_confidence_99      CONSTANT NUMBER := 0.99;
    c_stress_mild            CONSTANT NUMBER := 0.10;     -- 10% shock
    c_stress_moderate        CONSTANT NUMBER := 0.25;     -- 25% shock
    c_stress_severe          CONSTANT NUMBER := 0.50;     -- 50% shock

    -- -------------------------------------------------------------------------
    -- Exceptions
    -- -------------------------------------------------------------------------
    e_invalid_loan_id        EXCEPTION;
    e_invalid_customer_id    EXCEPTION;
    e_insufficient_data      EXCEPTION;
    e_capital_breach         EXCEPTION;
    e_liquidity_breach       EXCEPTION;
    e_concentration_breach   EXCEPTION;

    PRAGMA EXCEPTION_INIT(e_invalid_loan_id,       -20200);
    PRAGMA EXCEPTION_INIT(e_invalid_customer_id,   -20201);
    PRAGMA EXCEPTION_INIT(e_insufficient_data,     -20202);
    PRAGMA EXCEPTION_INIT(e_capital_breach,        -20203);
    PRAGMA EXCEPTION_INIT(e_liquidity_breach,      -20204);
    PRAGMA EXCEPTION_INIT(e_concentration_breach,  -20205);

    -- -------------------------------------------------------------------------
    -- FUNCTIONS
    -- -------------------------------------------------------------------------

    FUNCTION calculate_probability_of_default(
        p_customer_id      IN NUMBER,
        p_loan_type        IN VARCHAR2 DEFAULT NULL,
        p_as_of_date       IN DATE DEFAULT SYSDATE
    ) RETURN NUMBER;

    FUNCTION calculate_expected_loss(
        p_loan_id          IN NUMBER,
        p_scenario         IN VARCHAR2 DEFAULT 'BASE',
        p_as_of_date       IN DATE DEFAULT SYSDATE
    ) RETURN NUMBER;

    FUNCTION calculate_var_exposure(
        p_portfolio_scope  IN VARCHAR2 DEFAULT 'ALL',
        p_branch_id        IN NUMBER DEFAULT NULL,
        p_confidence_level IN NUMBER DEFAULT 0.99,
        p_horizon_days     IN NUMBER DEFAULT 1
    ) RETURN NUMBER;

    FUNCTION calculate_raroc(
        p_loan_id          IN NUMBER,
        p_as_of_date       IN DATE DEFAULT SYSDATE
    ) RETURN NUMBER;

    FUNCTION get_risk_band(
        p_score            IN NUMBER
    ) RETURN VARCHAR2;

    FUNCTION calculate_herfindahl_index(
        p_dimension        IN VARCHAR2,
        p_branch_id        IN NUMBER DEFAULT NULL
    ) RETURN NUMBER;

    -- -------------------------------------------------------------------------
    -- PROCEDURES
    -- -------------------------------------------------------------------------

    PROCEDURE perform_credit_risk_assessment(
        p_customer_id      IN  NUMBER,
        p_loan_id          IN  NUMBER DEFAULT NULL,
        p_as_of_date       IN  DATE DEFAULT SYSDATE,
        p_risk_score       OUT NUMBER,
        p_risk_band        OUT VARCHAR2,
        p_pd               OUT NUMBER,
        p_lgd              OUT NUMBER,
        p_ead              OUT NUMBER,
        p_expected_loss    OUT NUMBER,
        p_recommendation   OUT VARCHAR2,
        p_detail_cursor    OUT SYS_REFCURSOR
    );

    PROCEDURE run_portfolio_stress_test(
        p_scenario         IN  VARCHAR2,
        p_branch_id        IN  NUMBER DEFAULT NULL,
        p_as_of_date       IN  DATE DEFAULT SYSDATE,
        p_loans_affected   OUT NUMBER,
        p_pre_stress_el    OUT NUMBER,
        p_post_stress_el   OUT NUMBER,
        p_capital_impact   OUT NUMBER,
        p_breach_count     OUT NUMBER,
        p_results_cursor   OUT SYS_REFCURSOR
    );

    PROCEDURE compute_regulatory_capital(
        p_branch_id        IN  NUMBER DEFAULT NULL,
        p_as_of_date       IN  DATE DEFAULT SYSDATE,
        p_tier1_capital    OUT NUMBER,
        p_tier2_capital    OUT NUMBER,
        p_total_rwa        OUT NUMBER,
        p_car_ratio        OUT NUMBER,
        p_tier1_ratio      OUT NUMBER,
        p_is_compliant     OUT VARCHAR2,
        p_shortfall        OUT NUMBER,
        p_detail_cursor    OUT SYS_REFCURSOR
    );

    PROCEDURE assess_liquidity_risk(
        p_branch_id        IN  NUMBER DEFAULT NULL,
        p_as_of_date       IN  DATE DEFAULT SYSDATE,
        p_lcr_ratio        OUT NUMBER,
        p_nsfr_ratio       OUT NUMBER,
        p_net_cash_gap_30d OUT NUMBER,
        p_net_cash_gap_90d OUT NUMBER,
        p_hqla_total       OUT NUMBER,
        p_is_lcr_compliant OUT VARCHAR2,
        p_detail_cursor    OUT SYS_REFCURSOR
    );

    PROCEDURE detect_concentration_risk(
        p_as_of_date       IN  DATE DEFAULT SYSDATE,
        p_branch_id        IN  NUMBER DEFAULT NULL,
        p_hhi_loan_type    OUT NUMBER,
        p_hhi_geography    OUT NUMBER,
        p_hhi_customer     OUT NUMBER,
        p_top_exposure_pct OUT NUMBER,
        p_alert_level      OUT VARCHAR2,
        p_detail_cursor    OUT SYS_REFCURSOR
    );

    PROCEDURE generate_risk_scorecard(
        p_branch_id        IN  NUMBER DEFAULT NULL,
        p_as_of_date       IN  DATE DEFAULT SYSDATE,
        p_overall_score    OUT NUMBER,
        p_credit_score     OUT NUMBER,
        p_liquidity_score  OUT NUMBER,
        p_market_score     OUT NUMBER,
        p_operational_score OUT NUMBER,
        p_composite_band   OUT VARCHAR2,
        p_scorecard_cursor OUT SYS_REFCURSOR
    );

    PROCEDURE run_delinquency_migration_analysis(
        p_from_date        IN  DATE,
        p_to_date          IN  DATE,
        p_branch_id        IN  NUMBER DEFAULT NULL,
        p_migration_cursor OUT SYS_REFCURSOR,
        p_summary_cursor   OUT SYS_REFCURSOR
    );

END pkg_advanced_risk_engine;
/

-- =============================================================================
-- PACKAGE BODY
-- =============================================================================

CREATE OR REPLACE PACKAGE BODY pkg_advanced_risk_engine AS

    -- -------------------------------------------------------------------------
    -- Private: Autonomous transaction audit logger
    -- -------------------------------------------------------------------------
    PROCEDURE p_log_risk_event(
        p_event_type  IN VARCHAR2,
        p_entity_id   IN NUMBER,
        p_entity_type IN VARCHAR2,
        p_details     IN VARCHAR2
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO audit_log(
            table_name, record_id, action, new_values, changed_by, changed_at, session_id
        ) VALUES (
            p_entity_type,
            p_entity_id,
            'UPDATE',
            SUBSTR('RISK_ENGINE|EVENT='||p_event_type||'|'||p_details, 1, 3900),
            SYS_CONTEXT('USERENV','SESSION_USER'),
            SYSTIMESTAMP,
            SYS_CONTEXT('USERENV','SESSIONID')
        );
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN NULL;
    END p_log_risk_event;

    -- -------------------------------------------------------------------------
    -- Private: Resolve LGD based on loan type and collateral
    -- -------------------------------------------------------------------------
    FUNCTION f_resolve_lgd(
        p_loan_type       IN VARCHAR2,
        p_collateral_type IN VARCHAR2,
        p_collateral_value IN NUMBER,
        p_outstanding     IN NUMBER
    ) RETURN NUMBER IS
        v_lgd              NUMBER;
        v_collateral_cover NUMBER := 0;
    BEGIN
        IF p_outstanding > 0 AND NVL(p_collateral_value, 0) > 0 THEN
            v_collateral_cover := LEAST(p_collateral_value / p_outstanding, 1);
        END IF;

        v_lgd := CASE p_loan_type
                     WHEN 'MORTGAGE' THEN c_lgd_mortgage
                     WHEN 'HELOC'    THEN c_lgd_secured + 0.05
                     WHEN 'AUTO'     THEN c_lgd_secured
                     WHEN 'BUSINESS' THEN
                         CASE WHEN NVL(p_collateral_type, 'NONE') = 'NONE' THEN c_lgd_unsecured
                              ELSE c_lgd_secured
                         END
                     ELSE c_lgd_unsecured
                 END;

        IF v_collateral_cover > 0 THEN
            v_lgd := v_lgd * (1 - v_collateral_cover * 0.40);
        END IF;

        RETURN GREATEST(LEAST(v_lgd, 0.99), 0.01);
    END f_resolve_lgd;

    -- =========================================================================
    -- FUNCTION: calculate_probability_of_default
    -- Logistic regression-style PD model based on payment history,
    -- credit score, utilization, dpd buckets, and loan vintage.
    -- =========================================================================
    FUNCTION calculate_probability_of_default(
        p_customer_id  IN NUMBER,
        p_loan_type    IN VARCHAR2 DEFAULT NULL,
        p_as_of_date   IN DATE DEFAULT SYSDATE
    ) RETURN NUMBER IS
        v_credit_score     NUMBER;
        v_risk_level       VARCHAR2(10);
        v_active_loans     NUMBER := 0;
        v_delinq_loans     NUMBER := 0;
        v_total_dpd        NUMBER := 0;
        v_max_dpd          NUMBER := 0;
        v_times_30dpd      NUMBER := 0;
        v_times_60dpd      NUMBER := 0;
        v_times_90dpd      NUMBER := 0;
        v_total_outstanding NUMBER := 0;
        v_total_balance    NUMBER := 0;
        v_utilization      NUMBER := 0;
        v_account_age_months NUMBER := 0;
        v_logit_score      NUMBER;
        v_pd               NUMBER;
        v_weight_cs        NUMBER := -0.0045;
        v_weight_dpd       NUMBER :=  0.0312;
        v_weight_delinq    NUMBER :=  0.8700;
        v_weight_30dpd     NUMBER :=  0.4200;
        v_weight_60dpd     NUMBER :=  0.9100;
        v_weight_90dpd     NUMBER :=  1.5500;
        v_weight_util      NUMBER :=  0.0180;
        v_weight_vintage   NUMBER := -0.0083;
        v_intercept        NUMBER := -1.2000;
        v_exists           NUMBER;
    BEGIN
        SELECT COUNT(1) INTO v_exists FROM customers WHERE customer_id = p_customer_id;
        IF v_exists = 0 THEN
            RAISE e_invalid_customer_id;
        END IF;

        SELECT c.credit_score,
               c.risk_level,
               MONTHS_BETWEEN(p_as_of_date, c.created_at)
        INTO   v_credit_score, v_risk_level, v_account_age_months
        FROM   customers c
        WHERE  c.customer_id = p_customer_id;

        SELECT COUNT(1),
               SUM(CASE WHEN l.days_past_due > 0 THEN 1 ELSE 0 END),
               SUM(l.days_past_due),
               MAX(l.days_past_due),
               SUM(l.times_30_dpd),
               SUM(l.times_60_dpd),
               SUM(l.times_90_dpd),
               SUM(l.outstanding_balance)
        INTO   v_active_loans,
               v_delinq_loans,
               v_total_dpd,
               v_max_dpd,
               v_times_30dpd,
               v_times_60dpd,
               v_times_90dpd,
               v_total_outstanding
        FROM   loans l
        WHERE  l.customer_id      = p_customer_id
          AND  l.status           IN ('ACTIVE','DEFAULTED')
          AND  (p_loan_type IS NULL OR l.loan_type = p_loan_type);

        BEGIN
            SELECT SUM(a.balance),
                   SUM(a.available_balance)
            INTO   v_total_balance,
                   v_utilization
            FROM   accounts a
            WHERE  a.customer_id = p_customer_id
              AND  a.status      = 'ACTIVE'
              AND  a.account_type IN ('CHECKING','SAVINGS','MONEY_MKT');
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_total_balance := 0;
                v_utilization   := 0;
        END;

        IF NVL(v_total_balance + v_total_outstanding, 0) > 0 THEN
            v_utilization := v_total_outstanding /
                             NULLIF(v_total_balance + v_total_outstanding, 0) * 100;
        END IF;

        v_logit_score :=  v_intercept
                        + v_weight_cs      * NVL(v_credit_score,    500)
                        + v_weight_dpd     * NVL(v_total_dpd,       0)
                        + v_weight_delinq  * NVL(v_delinq_loans,    0)
                        + v_weight_30dpd   * NVL(v_times_30dpd,     0)
                        + v_weight_60dpd   * NVL(v_times_60dpd,     0)
                        + v_weight_90dpd   * NVL(v_times_90dpd,     0)
                        + v_weight_util    * NVL(v_utilization,     0)
                        + v_weight_vintage * LEAST(NVL(v_account_age_months, 0), 120);

        v_pd := 1 / (1 + EXP(-v_logit_score));

        v_pd := GREATEST(c_pd_floor, LEAST(c_pd_ceiling, v_pd));

        CASE v_risk_level
            WHEN 'HIGH'   THEN v_pd := LEAST(v_pd * 1.25, c_pd_ceiling);
            WHEN 'MEDIUM' THEN v_pd := v_pd * 1.05;
            ELSE NULL;
        END CASE;

        RETURN ROUND(v_pd, 6);

    EXCEPTION
        WHEN e_invalid_customer_id THEN
            RAISE_APPLICATION_ERROR(-20201, 'Customer ID '||p_customer_id||' not found in risk PD calculation.');
        WHEN OTHERS THEN
            p_log_risk_event('PD_CALC_ERROR', p_customer_id, 'CUSTOMERS', SQLERRM);
            RAISE;
    END calculate_probability_of_default;

    -- =========================================================================
    -- FUNCTION: calculate_expected_loss
    -- EL = PD x LGD x EAD, supporting BASE / MILD / MODERATE / SEVERE scenarios.
    -- Applies vintage haircut and portfolio-level correlation adjustment.
    -- =========================================================================
    FUNCTION calculate_expected_loss(
        p_loan_id     IN NUMBER,
        p_scenario    IN VARCHAR2 DEFAULT 'BASE',
        p_as_of_date  IN DATE DEFAULT SYSDATE
    ) RETURN NUMBER IS
        v_customer_id      NUMBER;
        v_loan_type        VARCHAR2(30);
        v_outstanding      NUMBER;
        v_collateral_type  VARCHAR2(50);
        v_collateral_value NUMBER;
        v_disbursement_date DATE;
        v_loan_status      VARCHAR2(20);
        v_months_on_book   NUMBER;
        v_pd               NUMBER;
        v_lgd              NUMBER;
        v_ead              NUMBER;
        v_el               NUMBER;
        v_ccf              NUMBER := 1.00;
        v_scenario_pd_mult NUMBER := 1.00;
        v_scenario_lgd_mult NUMBER := 1.00;
        v_exists           NUMBER;
        v_undrawn_amount   NUMBER := 0;
        v_credit_limit     NUMBER := 0;
    BEGIN
        SELECT COUNT(1) INTO v_exists FROM loans WHERE loan_id = p_loan_id;
        IF v_exists = 0 THEN
            RAISE e_invalid_loan_id;
        END IF;

        SELECT l.customer_id,
               l.loan_type,
               l.outstanding_balance,
               l.collateral_type,
               l.collateral_value,
               l.disbursement_date,
               l.status,
               MONTHS_BETWEEN(p_as_of_date, NVL(l.disbursement_date, l.created_at))
        INTO   v_customer_id,
               v_loan_type,
               v_outstanding,
               v_collateral_type,
               v_collateral_value,
               v_disbursement_date,
               v_loan_status,
               v_months_on_book
        FROM   loans l
        WHERE  l.loan_id = p_loan_id;

        CASE UPPER(p_scenario)
            WHEN 'MILD'     THEN v_scenario_pd_mult := 1 + c_stress_mild;
                                 v_scenario_lgd_mult := 1 + c_stress_mild * 0.5;
            WHEN 'MODERATE' THEN v_scenario_pd_mult := 1 + c_stress_moderate;
                                 v_scenario_lgd_mult := 1 + c_stress_moderate * 0.6;
            WHEN 'SEVERE'   THEN v_scenario_pd_mult := 1 + c_stress_severe;
                                 v_scenario_lgd_mult := 1 + c_stress_severe * 0.7;
            ELSE
                v_scenario_pd_mult := 1.00;
                v_scenario_lgd_mult := 1.00;
        END CASE;

        IF v_loan_status = 'DEFAULTED' THEN
            v_pd := 1.00;
        ELSE
            v_pd := calculate_probability_of_default(v_customer_id, v_loan_type, p_as_of_date);
            v_pd := LEAST(v_pd * v_scenario_pd_mult, c_pd_ceiling);
        END IF;

        v_lgd := f_resolve_lgd(v_loan_type, v_collateral_type, v_collateral_value, v_outstanding);
        v_lgd := LEAST(v_lgd * v_scenario_lgd_mult, 0.99);

        IF v_loan_type = 'HELOC' THEN
            BEGIN
                SELECT NVL(c.credit_limit, 0), NVL(c.available_credit, 0)
                INTO   v_credit_limit, v_undrawn_amount
                FROM   cards c
                       JOIN loans l ON l.account_id = c.account_id
                WHERE  l.loan_id = p_loan_id
                  AND  ROWNUM = 1;
                v_ccf := 0.75;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    v_ccf := 1.00;
            END;
        END IF;

        v_ead := v_outstanding + (v_undrawn_amount * v_ccf);

        IF v_months_on_book BETWEEN 0 AND 6 THEN
            v_ead := v_ead * 1.10;
        ELSIF v_months_on_book > 60 THEN
            v_ead := v_ead * 0.95;
        END IF;

        v_el := v_pd * v_lgd * v_ead;

        RETURN ROUND(GREATEST(v_el, 0), 2);

    EXCEPTION
        WHEN e_invalid_loan_id THEN
            RAISE_APPLICATION_ERROR(-20200, 'Loan ID '||p_loan_id||' not found in EL calculation.');
        WHEN OTHERS THEN
            p_log_risk_event('EL_CALC_ERROR', p_loan_id, 'LOANS', SQLERRM);
            RAISE;
    END calculate_expected_loss;

    -- =========================================================================
    -- FUNCTION: get_risk_band
    -- Maps a numeric risk score (0-100) to a categorical band.
    -- =========================================================================
    FUNCTION get_risk_band(p_score IN NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN CASE
                   WHEN p_score IS NULL       THEN 'UNRATED'
                   WHEN p_score < 10          THEN 'AAA'
                   WHEN p_score < 20          THEN 'AA'
                   WHEN p_score < 30          THEN 'A'
                   WHEN p_score < 40          THEN 'BBB'
                   WHEN p_score < 55          THEN 'BB'
                   WHEN p_score < 70          THEN 'B'
                   WHEN p_score < 85          THEN 'CCC'
                   ELSE                            'D'
               END;
    END get_risk_band;

    -- =========================================================================
    -- FUNCTION: calculate_herfindahl_index
    -- Herfindahl-Hirschman Index for concentration measurement.
    -- p_dimension: LOAN_TYPE | GEOGRAPHY | CUSTOMER | INDUSTRY
    -- =========================================================================
    FUNCTION calculate_herfindahl_index(
        p_dimension IN VARCHAR2,
        p_branch_id IN NUMBER DEFAULT NULL
    ) RETURN NUMBER IS
        TYPE t_share_table IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
        v_shares    t_share_table;
        v_total     NUMBER := 0;
        v_hhi       NUMBER := 0;
        v_idx       PLS_INTEGER := 0;

        CURSOR c_loan_type IS
            SELECT l.loan_type, SUM(l.outstanding_balance) AS segment_total
            FROM   loans l
            WHERE  l.status       IN ('ACTIVE','DEFAULTED')
              AND  (p_branch_id IS NULL OR l.branch_id = p_branch_id)
            GROUP BY l.loan_type;

        CURSOR c_geography IS
            SELECT NVL(c.state, 'UNKNOWN') AS state,
                   SUM(l.outstanding_balance) AS segment_total
            FROM   loans l
                   JOIN customers c ON c.customer_id = l.customer_id
            WHERE  l.status IN ('ACTIVE','DEFAULTED')
              AND  (p_branch_id IS NULL OR l.branch_id = p_branch_id)
            GROUP BY NVL(c.state, 'UNKNOWN');

        CURSOR c_customer IS
            SELECT l.customer_id,
                   SUM(l.outstanding_balance) AS segment_total
            FROM   loans l
            WHERE  l.status IN ('ACTIVE','DEFAULTED')
              AND  (p_branch_id IS NULL OR l.branch_id = p_branch_id)
            GROUP BY l.customer_id;
    BEGIN
        IF UPPER(p_dimension) NOT IN ('LOAN_TYPE','GEOGRAPHY','CUSTOMER') THEN
            RETURN -1;
        END IF;

        SELECT NVL(SUM(outstanding_balance), 0)
        INTO   v_total
        FROM   loans
        WHERE  status IN ('ACTIVE','DEFAULTED')
          AND  (p_branch_id IS NULL OR branch_id = p_branch_id);

        IF v_total = 0 THEN
            RETURN 0;
        END IF;

        IF UPPER(p_dimension) = 'LOAN_TYPE' THEN
            FOR rec IN c_loan_type LOOP
                v_idx := v_idx + 1;
                v_shares(v_idx) := rec.segment_total / v_total;
            END LOOP;
        ELSIF UPPER(p_dimension) = 'GEOGRAPHY' THEN
            FOR rec IN c_geography LOOP
                v_idx := v_idx + 1;
                v_shares(v_idx) := rec.segment_total / v_total;
            END LOOP;
        ELSIF UPPER(p_dimension) = 'CUSTOMER' THEN
            FOR rec IN c_customer LOOP
                v_idx := v_idx + 1;
                v_shares(v_idx) := rec.segment_total / v_total;
            END LOOP;
        ELSE
            RETURN -1;
        END IF;

        v_idx := v_shares.FIRST;
        WHILE v_idx IS NOT NULL LOOP
            v_hhi := v_hhi + POWER(v_shares(v_idx), 2);
            v_idx := v_shares.NEXT(v_idx);
        END LOOP;

        RETURN ROUND(v_hhi, 6);
    END calculate_herfindahl_index;

    -- =========================================================================
    -- FUNCTION: calculate_var_exposure
    -- Historical Simulation VaR for the loan portfolio.
    -- Approximates VaR using distribution of daily P&L proxied by
    -- expected loss volatility across the portfolio.
    -- =========================================================================
    FUNCTION calculate_var_exposure(
        p_portfolio_scope  IN VARCHAR2 DEFAULT 'ALL',
        p_branch_id        IN NUMBER DEFAULT NULL,
        p_confidence_level IN NUMBER DEFAULT 0.99,
        p_horizon_days     IN NUMBER DEFAULT 1
    ) RETURN NUMBER IS
        TYPE t_el_table IS TABLE OF NUMBER;
        v_el_values         t_el_table := t_el_table();
        v_sorted_el         t_el_table := t_el_table();
        v_total_el          NUMBER := 0;
        v_mean_el           NUMBER := 0;
        v_variance          NUMBER := 0;
        v_std_dev           NUMBER := 0;
        v_z_score           NUMBER;
        v_var               NUMBER;
        v_count             NUMBER := 0;
        v_cutoff_idx        NUMBER;
        v_tmp               NUMBER;
        i                   PLS_INTEGER;
        j                   PLS_INTEGER;

        CURSOR c_portfolio IS
            SELECT l.loan_id,
                   l.outstanding_balance,
                   l.loan_type,
                   l.days_past_due,
                   l.times_90_dpd,
                   c.credit_score
            FROM   loans l
                   JOIN customers c ON c.customer_id = l.customer_id
            WHERE  l.status IN ('ACTIVE','DEFAULTED')
              AND  (p_branch_id IS NULL OR l.branch_id = p_branch_id)
              AND  (p_portfolio_scope = 'ALL'
                    OR (p_portfolio_scope = 'RETAIL' AND l.loan_type IN ('PERSONAL','AUTO','STUDENT','HELOC'))
                    OR (p_portfolio_scope = 'COMMERCIAL' AND l.loan_type IN ('BUSINESS','MORTGAGE')));
    BEGIN
        v_z_score := CASE
                         WHEN p_confidence_level >= 0.99 THEN 2.3263
                         WHEN p_confidence_level >= 0.975 THEN 1.9600
                         WHEN p_confidence_level >= 0.95 THEN 1.6449
                         ELSE 1.2816
                     END;

        FOR rec IN c_portfolio LOOP
            v_count := v_count + 1;
            v_el_values.EXTEND;
            v_el_values(v_count) := calculate_expected_loss(rec.loan_id, 'BASE', SYSDATE);
            v_total_el := v_total_el + v_el_values(v_count);
        END LOOP;

        IF v_count < 5 THEN
            RETURN 0;
        END IF;

        v_mean_el := v_total_el / v_count;

        FOR i IN 1..v_count LOOP
            v_variance := v_variance + POWER(v_el_values(i) - v_mean_el, 2);
        END LOOP;
        v_variance := v_variance / (v_count - 1);
        v_std_dev  := SQRT(v_variance);

        v_var := (v_mean_el + v_z_score * v_std_dev) * SQRT(p_horizon_days) * v_count;

        RETURN ROUND(GREATEST(v_var, 0), 2);

    EXCEPTION
        WHEN OTHERS THEN
            p_log_risk_event('VAR_CALC_ERROR', NVL(p_branch_id, -1), 'PORTFOLIO', SQLERRM);
            RETURN -1;
    END calculate_var_exposure;

    -- =========================================================================
    -- FUNCTION: calculate_raroc
    -- Risk-Adjusted Return on Capital for a single loan.
    -- RAROC = (Revenue - Expected Loss - Operating Cost) / Economic Capital
    -- =========================================================================
    FUNCTION calculate_raroc(
        p_loan_id    IN NUMBER,
        p_as_of_date IN DATE DEFAULT SYSDATE
    ) RETURN NUMBER IS
        v_outstanding      NUMBER;
        v_interest_rate    NUMBER;
        v_monthly_payment  NUMBER;
        v_annual_revenue   NUMBER;
        v_expected_loss    NUMBER;
        v_op_cost_pct      CONSTANT NUMBER := 0.015;
        v_op_cost          NUMBER;
        v_pd               NUMBER;
        v_lgd              NUMBER;
        v_ead              NUMBER;
        v_unexpected_loss  NUMBER;
        v_economic_capital NUMBER;
        v_raroc            NUMBER;
        v_customer_id      NUMBER;
        v_loan_type        VARCHAR2(30);
        v_collateral_type  VARCHAR2(50);
        v_collateral_val   NUMBER;
        v_exists           NUMBER;
    BEGIN
        SELECT COUNT(1) INTO v_exists FROM loans WHERE loan_id = p_loan_id;
        IF v_exists = 0 THEN
            RAISE e_invalid_loan_id;
        END IF;

        SELECT l.outstanding_balance,
               l.interest_rate,
               l.monthly_payment,
               l.customer_id,
               l.loan_type,
               l.collateral_type,
               l.collateral_value
        INTO   v_outstanding, v_interest_rate, v_monthly_payment,
               v_customer_id, v_loan_type, v_collateral_type, v_collateral_val
        FROM   loans l
        WHERE  l.loan_id = p_loan_id;

        v_annual_revenue := (v_outstanding * v_interest_rate / 100);
        v_expected_loss  := calculate_expected_loss(p_loan_id, 'BASE', p_as_of_date);
        v_op_cost        := v_outstanding * v_op_cost_pct;

        v_pd  := calculate_probability_of_default(v_customer_id, v_loan_type, p_as_of_date);
        v_lgd := f_resolve_lgd(v_loan_type, v_collateral_type, v_collateral_val, v_outstanding);
        v_ead := v_outstanding;

        v_unexpected_loss  := v_ead * v_lgd * SQRT(v_pd * (1 - v_pd));
        v_economic_capital := v_unexpected_loss * 8;

        IF NVL(v_economic_capital, 0) <= 0 THEN
            RETURN NULL;
        END IF;

        v_raroc := (v_annual_revenue - v_expected_loss - v_op_cost) / v_economic_capital;

        RETURN ROUND(v_raroc * 100, 4);

    EXCEPTION
        WHEN e_invalid_loan_id THEN
            RAISE_APPLICATION_ERROR(-20200, 'Loan ID '||p_loan_id||' not found in RAROC calculation.');
        WHEN OTHERS THEN
            p_log_risk_event('RAROC_CALC_ERROR', p_loan_id, 'LOANS', SQLERRM);
            RAISE;
    END calculate_raroc;

    -- =========================================================================
    -- PROCEDURE: perform_credit_risk_assessment
    -- Comprehensive credit risk assessment for a customer / specific loan.
    -- Combines PD, LGD, EAD into expected loss, assigns internal rating,
    -- and generates detailed risk factor breakdown via a ref cursor.
    -- =========================================================================
    PROCEDURE perform_credit_risk_assessment(
        p_customer_id      IN  NUMBER,
        p_loan_id          IN  NUMBER DEFAULT NULL,
        p_as_of_date       IN  DATE DEFAULT SYSDATE,
        p_risk_score       OUT NUMBER,
        p_risk_band        OUT VARCHAR2,
        p_pd               OUT NUMBER,
        p_lgd              OUT NUMBER,
        p_ead              OUT NUMBER,
        p_expected_loss    OUT NUMBER,
        p_recommendation   OUT VARCHAR2,
        p_detail_cursor    OUT SYS_REFCURSOR
    ) IS
        v_credit_score     NUMBER;
        v_kyc_status       VARCHAR2(20);
        v_risk_level       VARCHAR2(10);
        v_cust_active      CHAR(1);
        v_active_loan_cnt  NUMBER := 0;
        v_total_outstanding NUMBER := 0;
        v_max_dpd          NUMBER := 0;
        v_total_dpd_cnt    NUMBER := 0;
        v_open_fraud_cnt   NUMBER := 0;
        v_paid_on_time_pct NUMBER := 0;
        v_paid_on_time     NUMBER := 0;
        v_total_due        NUMBER := 0;
        v_score_component  NUMBER := 0;
        v_cs_component     NUMBER;
        v_payment_component NUMBER;
        v_fraud_component  NUMBER;
        v_dpd_component    NUMBER;
        v_portfolio_el     NUMBER := 0;
        v_loan_el          NUMBER;
        v_loan_lgd         NUMBER;
        v_loan_ead         NUMBER;
        v_exists           NUMBER;

        TYPE t_loan_rec IS RECORD (
            loan_id          NUMBER,
            loan_type        VARCHAR2(30),
            outstanding      NUMBER,
            interest_rate    NUMBER,
            days_past_due    NUMBER,
            collateral_type  VARCHAR2(50),
            collateral_value NUMBER,
            loan_status      VARCHAR2(20),
            months_on_book   NUMBER
        );
        TYPE t_loan_tab IS TABLE OF t_loan_rec;
        v_loans t_loan_tab;

        CURSOR c_loans IS
            SELECT l.loan_id,
                   l.loan_type,
                   l.outstanding_balance,
                   l.interest_rate,
                   l.days_past_due,
                   l.collateral_type,
                   l.collateral_value,
                   l.status,
                   MONTHS_BETWEEN(p_as_of_date, NVL(l.disbursement_date, l.created_at))
            FROM   loans l
            WHERE  l.customer_id = p_customer_id
              AND  l.status NOT IN ('REJECTED','WRITTEN_OFF')
              AND  (p_loan_id IS NULL OR l.loan_id = p_loan_id);
    BEGIN
        SELECT COUNT(1) INTO v_exists FROM customers WHERE customer_id = p_customer_id;
        IF v_exists = 0 THEN
            RAISE e_invalid_customer_id;
        END IF;

        SELECT c.credit_score,
               c.kyc_status,
               c.risk_level,
               c.is_active
        INTO   v_credit_score, v_kyc_status, v_risk_level, v_cust_active
        FROM   customers c
        WHERE  c.customer_id = p_customer_id;

        SELECT COUNT(1)
        INTO   v_open_fraud_cnt
        FROM   fraud_alerts fa
        WHERE  fa.customer_id = p_customer_id
          AND  fa.status IN ('OPEN','INVESTIGATING')
          AND  fa.severity IN ('HIGH','CRITICAL');

        SELECT COUNT(1),
               NVL(SUM(lp.scheduled_amount), 0),
               NVL(SUM(CASE WHEN lp.status = 'PAID' AND lp.paid_amount >= lp.scheduled_amount
                            THEN 1 ELSE 0 END), 0)
        INTO   v_total_due,
               v_total_due,
               v_paid_on_time
        FROM   loan_payments lp
               JOIN loans l ON l.loan_id = lp.loan_id
        WHERE  l.customer_id = p_customer_id
          AND  lp.due_date   <= p_as_of_date
          AND  lp.status     <> 'WAIVED';

        IF v_total_due > 0 THEN
            v_paid_on_time_pct := v_paid_on_time / v_total_due * 100;
        ELSE
            v_paid_on_time_pct := 100;
        END IF;

        OPEN c_loans;
        FETCH c_loans BULK COLLECT INTO v_loans;
        CLOSE c_loans;

        FOR i IN 1..v_loans.COUNT LOOP
            v_active_loan_cnt   := v_active_loan_cnt + 1;
            v_total_outstanding := v_total_outstanding + NVL(v_loans(i).outstanding, 0);
            v_max_dpd           := GREATEST(v_max_dpd, NVL(v_loans(i).days_past_due, 0));
            IF NVL(v_loans(i).days_past_due, 0) > 0 THEN
                v_total_dpd_cnt := v_total_dpd_cnt + 1;
            END IF;

            v_loan_lgd := f_resolve_lgd(
                v_loans(i).loan_type,
                v_loans(i).collateral_type,
                v_loans(i).collateral_value,
                v_loans(i).outstanding
            );
            v_loan_ead := v_loans(i).outstanding;
            v_loan_el  := calculate_expected_loss(v_loans(i).loan_id, 'BASE', p_as_of_date);
            v_portfolio_el := v_portfolio_el + v_loan_el;

            IF p_loan_id IS NOT NULL AND v_loans(i).loan_id = p_loan_id THEN
                p_lgd := v_loan_lgd;
                p_ead := v_loan_ead;
            END IF;
        END LOOP;

        IF p_loan_id IS NULL THEN
            p_lgd := c_lgd_unsecured;
            p_ead := v_total_outstanding;
        END IF;

        p_pd := calculate_probability_of_default(p_customer_id, NULL, p_as_of_date);
        p_expected_loss := v_portfolio_el;

        v_cs_component := CASE
                              WHEN v_credit_score >= 750 THEN 5
                              WHEN v_credit_score >= 700 THEN 15
                              WHEN v_credit_score >= 650 THEN 30
                              WHEN v_credit_score >= 600 THEN 50
                              WHEN v_credit_score >= 550 THEN 65
                              ELSE 80
                          END;

        v_payment_component := CASE
                                   WHEN v_paid_on_time_pct >= 95 THEN 0
                                   WHEN v_paid_on_time_pct >= 85 THEN 10
                                   WHEN v_paid_on_time_pct >= 70 THEN 25
                                   WHEN v_paid_on_time_pct >= 50 THEN 45
                                   ELSE 65
                               END;

        v_dpd_component := CASE
                               WHEN v_max_dpd = 0     THEN 0
                               WHEN v_max_dpd <= 30   THEN 15
                               WHEN v_max_dpd <= 60   THEN 35
                               WHEN v_max_dpd <= 90   THEN 55
                               ELSE 80
                           END;

        v_fraud_component := CASE
                                 WHEN v_open_fraud_cnt = 0 THEN 0
                                 WHEN v_open_fraud_cnt = 1 THEN 20
                                 ELSE 40
                             END;

        p_risk_score := ROUND(
                            v_cs_component      * 0.40 +
                            v_payment_component * 0.30 +
                            v_dpd_component     * 0.20 +
                            v_fraud_component   * 0.10,
                        2);

        IF v_kyc_status IN ('REJECTED','EXPIRED') THEN
            p_risk_score := LEAST(p_risk_score + 15, 100);
        END IF;
        IF v_cust_active = 'N' THEN
            p_risk_score := 100;
        END IF;

        p_risk_band := get_risk_band(p_risk_score);

        p_recommendation :=
            CASE
                WHEN p_risk_score < 20  THEN 'AUTO_APPROVE - Excellent profile, minimal risk.'
                WHEN p_risk_score < 35  THEN 'APPROVE - Good profile, standard monitoring.'
                WHEN p_risk_score < 50  THEN 'APPROVE_WITH_CONDITIONS - Fair profile, require additional collateral or co-signer.'
                WHEN p_risk_score < 65  THEN 'MANUAL_REVIEW - Elevated risk; senior credit officer review required.'
                WHEN p_risk_score < 80  THEN 'DECLINE_SOFT - High risk; consider secured products only.'
                ELSE                         'DECLINE_HARD - Very high risk or fraud flag; escalate to compliance.'
            END;

        p_log_risk_event(
            'CREDIT_ASSESSMENT',
            p_customer_id,
            'CUSTOMERS',
            'SCORE='||p_risk_score||'|BAND='||p_risk_band||'|PD='||p_pd||'|EL='||p_expected_loss
        );

        OPEN p_detail_cursor FOR
            SELECT l.loan_id,
                   l.loan_number,
                   l.loan_type,
                   l.outstanding_balance,
                   l.days_past_due,
                   l.status                                                          AS loan_status,
                   ROUND(calculate_expected_loss(l.loan_id, 'BASE', p_as_of_date), 2) AS expected_loss_base,
                   ROUND(calculate_expected_loss(l.loan_id, 'SEVERE', p_as_of_date), 2) AS expected_loss_severe,
                   ROUND(calculate_raroc(l.loan_id, p_as_of_date), 4)               AS raroc_pct,
                   CASE l.loan_type
                       WHEN 'MORTGAGE' THEN 0.20
                       WHEN 'HELOC'    THEN 0.40
                       WHEN 'AUTO'     THEN CASE WHEN NVL(l.collateral_type,'NONE') <> 'NONE' THEN 0.35 ELSE 0.65 END
                       WHEN 'BUSINESS' THEN CASE WHEN NVL(l.collateral_type,'NONE') <> 'NONE' THEN 0.35 ELSE 0.65 END
                       ELSE 0.65
                   END                                                               AS lgd,
                   ROUND(RANK() OVER (ORDER BY l.outstanding_balance DESC)
                         / COUNT(*) OVER (), 4)                                     AS size_percentile
            FROM   loans l
            WHERE  l.customer_id = p_customer_id
              AND  l.status NOT IN ('REJECTED','WRITTEN_OFF')
              AND  (p_loan_id IS NULL OR l.loan_id = p_loan_id)
            ORDER BY l.outstanding_balance DESC;

    EXCEPTION
        WHEN e_invalid_customer_id THEN
            RAISE_APPLICATION_ERROR(-20201, 'Customer '||p_customer_id||' not found.');
        WHEN OTHERS THEN
            p_log_risk_event('ASSESS_ERROR', p_customer_id, 'CUSTOMERS', SQLERRM);
            RAISE;
    END perform_credit_risk_assessment;

    -- =========================================================================
    -- PROCEDURE: run_portfolio_stress_test
    -- Applies macroeconomic shock scenarios (MILD/MODERATE/SEVERE) to the
    -- entire loan portfolio, recomputing EL under stress, identifying
    -- loans that breach write-off thresholds, and estimating capital impact.
    -- =========================================================================
    PROCEDURE run_portfolio_stress_test(
        p_scenario         IN  VARCHAR2,
        p_branch_id        IN  NUMBER DEFAULT NULL,
        p_as_of_date       IN  DATE DEFAULT SYSDATE,
        p_loans_affected   OUT NUMBER,
        p_pre_stress_el    OUT NUMBER,
        p_post_stress_el   OUT NUMBER,
        p_capital_impact   OUT NUMBER,
        p_breach_count     OUT NUMBER,
        p_results_cursor   OUT SYS_REFCURSOR
    ) IS
        TYPE t_stress_rec IS RECORD (
            loan_id         NUMBER,
            customer_id     NUMBER,
            loan_type       VARCHAR2(30),
            outstanding     NUMBER,
            base_el         NUMBER,
            stress_el       NUMBER,
            el_delta        NUMBER,
            base_raroc      NUMBER,
            stress_pd       NUMBER,
            is_breach       VARCHAR2(1)
        );
        TYPE t_stress_tab IS TABLE OF t_stress_rec INDEX BY PLS_INTEGER;
        v_stress_data       t_stress_tab;
        v_idx               PLS_INTEGER := 0;

        v_pd_multiplier     NUMBER;
        v_lgd_multiplier    NUMBER;
        v_rate_shock_bps    NUMBER;
        v_gdp_shock_pct     NUMBER;
        v_unemployment_add  NUMBER;
        v_breach_threshold  NUMBER := 0.80;

        CURSOR c_active_loans IS
            SELECT l.loan_id,
                   l.customer_id,
                   l.loan_type,
                   l.outstanding_balance,
                   l.interest_rate,
                   l.days_past_due,
                   l.collateral_type,
                   l.collateral_value,
                   l.status
            FROM   loans l
            WHERE  l.status IN ('ACTIVE','DEFAULTED')
              AND  (p_branch_id IS NULL OR l.branch_id = p_branch_id);

        v_base_el_loan      NUMBER;
        v_stress_el_loan    NUMBER;
        v_loan_raroc        NUMBER;
        v_stress_pd_val     NUMBER;
        v_base_pd           NUMBER;
        v_is_breach         VARCHAR2(1);
        v_total_portfolio   NUMBER := 0;
    BEGIN
        CASE UPPER(p_scenario)
            WHEN 'MILD' THEN
                v_pd_multiplier    := 1 + c_stress_mild;
                v_lgd_multiplier   := 1 + c_stress_mild * 0.5;
                v_rate_shock_bps   := 100;
                v_gdp_shock_pct    := -0.50;
                v_unemployment_add := 1.50;
            WHEN 'MODERATE' THEN
                v_pd_multiplier    := 1 + c_stress_moderate;
                v_lgd_multiplier   := 1 + c_stress_moderate * 0.6;
                v_rate_shock_bps   := 250;
                v_gdp_shock_pct    := -2.00;
                v_unemployment_add := 3.50;
            WHEN 'SEVERE' THEN
                v_pd_multiplier    := 1 + c_stress_severe;
                v_lgd_multiplier   := 1 + c_stress_severe * 0.7;
                v_rate_shock_bps   := 500;
                v_gdp_shock_pct    := -5.00;
                v_unemployment_add := 7.00;
            ELSE
                RAISE_APPLICATION_ERROR(-20202,
                    'Invalid stress scenario: '||p_scenario||'. Use MILD, MODERATE, or SEVERE.');
        END CASE;

        p_loans_affected := 0;
        p_pre_stress_el  := 0;
        p_post_stress_el := 0;
        p_breach_count   := 0;

        FOR rec IN c_active_loans LOOP
            v_base_el_loan   := calculate_expected_loss(rec.loan_id, 'BASE',    p_as_of_date);
            v_stress_el_loan := calculate_expected_loss(rec.loan_id, p_scenario, p_as_of_date);

            BEGIN
                v_loan_raroc := calculate_raroc(rec.loan_id, p_as_of_date);
            EXCEPTION
                WHEN OTHERS THEN v_loan_raroc := NULL;
            END;

            v_base_pd   := calculate_probability_of_default(rec.customer_id, rec.loan_type, p_as_of_date);
            v_stress_pd_val := LEAST(v_base_pd * v_pd_multiplier, c_pd_ceiling);

            v_is_breach := CASE
                               WHEN rec.outstanding_balance > 0 AND
                                    v_stress_el_loan / rec.outstanding_balance >= v_breach_threshold
                               THEN 'Y'
                               ELSE 'N'
                           END;

            p_loans_affected := p_loans_affected + 1;
            p_pre_stress_el  := p_pre_stress_el  + v_base_el_loan;
            p_post_stress_el := p_post_stress_el + v_stress_el_loan;
            IF v_is_breach = 'Y' THEN
                p_breach_count := p_breach_count + 1;
            END IF;

            v_idx := v_idx + 1;
            v_stress_data(v_idx).loan_id     := rec.loan_id;
            v_stress_data(v_idx).customer_id := rec.customer_id;
            v_stress_data(v_idx).loan_type   := rec.loan_type;
            v_stress_data(v_idx).outstanding := rec.outstanding_balance;
            v_stress_data(v_idx).base_el     := v_base_el_loan;
            v_stress_data(v_idx).stress_el   := v_stress_el_loan;
            v_stress_data(v_idx).el_delta    := v_stress_el_loan - v_base_el_loan;
            v_stress_data(v_idx).base_raroc  := v_loan_raroc;
            v_stress_data(v_idx).stress_pd   := v_stress_pd_val;
            v_stress_data(v_idx).is_breach   := v_is_breach;
        END LOOP;

        p_capital_impact := (p_post_stress_el - p_pre_stress_el) * c_total_capital_min * 12.5;

        p_log_risk_event(
            'STRESS_TEST_'||UPPER(p_scenario),
            NVL(p_branch_id, -1),
            'PORTFOLIO',
            'LOANS='||p_loans_affected||
            '|PRE_EL='||ROUND(p_pre_stress_el,2)||
            '|POST_EL='||ROUND(p_post_stress_el,2)||
            '|BREACH_CNT='||p_breach_count
        );

        OPEN p_results_cursor FOR
            SELECT l.loan_id,
                   l.loan_number,
                   c.customer_code,
                   c.first_name||' '||c.last_name                              AS customer_name,
                   l.loan_type,
                   l.outstanding_balance,
                   l.days_past_due,
                   ROUND(calculate_expected_loss(l.loan_id, 'BASE',    p_as_of_date), 2) AS el_base,
                   ROUND(calculate_expected_loss(l.loan_id, p_scenario, p_as_of_date), 2) AS el_stress,
                   ROUND(calculate_expected_loss(l.loan_id, p_scenario, p_as_of_date)
                         - calculate_expected_loss(l.loan_id, 'BASE',  p_as_of_date), 2) AS el_delta,
                   ROUND(calculate_probability_of_default(l.customer_id, l.loan_type, p_as_of_date)
                         * v_pd_multiplier * 100, 4)                           AS stressed_pd_pct,
                   ROUND(calculate_raroc(l.loan_id, p_as_of_date), 4)          AS raroc_pct,
                   CASE WHEN l.outstanding_balance > 0 AND
                              calculate_expected_loss(l.loan_id, p_scenario, p_as_of_date)
                              / l.outstanding_balance >= v_breach_threshold
                        THEN 'Y' ELSE 'N'
                   END                                                          AS breach_flag,
                   RANK() OVER (ORDER BY
                       calculate_expected_loss(l.loan_id, p_scenario, p_as_of_date) DESC) AS risk_rank
            FROM   loans l
                   JOIN customers c ON c.customer_id = l.customer_id
            WHERE  l.status IN ('ACTIVE','DEFAULTED')
              AND  (p_branch_id IS NULL OR l.branch_id = p_branch_id)
            ORDER BY el_delta DESC;

    EXCEPTION
        WHEN OTHERS THEN
            p_log_risk_event('STRESS_TEST_ERROR', NVL(p_branch_id,-1), 'PORTFOLIO', SQLERRM);
            RAISE;
    END run_portfolio_stress_test;

    -- =========================================================================
    -- PROCEDURE: compute_regulatory_capital
    -- Basel III-inspired Risk-Weighted Assets and Capital Adequacy Ratio.
    -- RWA weights: Mortgage=35%, Auto/Secured=75%, Personal/Unsecured=100%,
    --              Business=85%, HELOC=50%, Defaulted=150%.
    -- Tier 1 = equity proxy (avg balance × leverage factor).
    -- =========================================================================
    PROCEDURE compute_regulatory_capital(
        p_branch_id     IN  NUMBER DEFAULT NULL,
        p_as_of_date    IN  DATE DEFAULT SYSDATE,
        p_tier1_capital OUT NUMBER,
        p_tier2_capital OUT NUMBER,
        p_total_rwa     OUT NUMBER,
        p_car_ratio     OUT NUMBER,
        p_tier1_ratio   OUT NUMBER,
        p_is_compliant  OUT VARCHAR2,
        p_shortfall     OUT NUMBER,
        p_detail_cursor OUT SYS_REFCURSOR
    ) IS
        v_rwa_loan         NUMBER := 0;
        v_rwa_market       NUMBER := 0;
        v_rwa_operational  NUMBER := 0;
        v_total_deposits   NUMBER := 0;
        v_total_loans      NUMBER := 0;
        v_total_revenue    NUMBER := 0;
        v_var_99           NUMBER;
        v_rw               NUMBER;

        CURSOR c_loan_rwa IS
            SELECT l.loan_type,
                   l.status,
                   l.collateral_type,
                   SUM(l.outstanding_balance) AS segment_balance,
                   COUNT(1)                   AS loan_count,
                   AVG(l.interest_rate)       AS avg_rate,
                   SUM(l.days_past_due)       AS total_dpd
            FROM   loans l
            WHERE  (p_branch_id IS NULL OR l.branch_id = p_branch_id)
              AND  l.status NOT IN ('PENDING','REJECTED','WRITTEN_OFF')
              AND  l.outstanding_balance > 0
            GROUP BY l.loan_type, l.status, l.collateral_type;
    BEGIN
        SELECT NVL(SUM(a.balance), 0)
        INTO   v_total_deposits
        FROM   accounts a
        WHERE  a.status = 'ACTIVE'
          AND  (p_branch_id IS NULL OR a.branch_id = p_branch_id)
          AND  a.account_type IN ('CHECKING','SAVINGS','MONEY_MKT','BUSINESS');

        SELECT NVL(SUM(l.outstanding_balance), 0)
        INTO   v_total_loans
        FROM   loans l
        WHERE  (p_branch_id IS NULL OR l.branch_id = p_branch_id)
          AND  l.status IN ('ACTIVE','DEFAULTED');

        BEGIN
            SELECT NVL(SUM(t.amount), 0)
            INTO   v_total_revenue
            FROM   transactions t
                   JOIN accounts a ON a.account_id = t.account_id
            WHERE  t.transaction_type = 'INTEREST'
              AND  t.transaction_date >= ADD_MONTHS(p_as_of_date, -12)
              AND  (p_branch_id IS NULL OR a.branch_id = p_branch_id);
        EXCEPTION WHEN OTHERS THEN v_total_revenue := 0;
        END;

        FOR rec IN c_loan_rwa LOOP
            v_rw := CASE
                        WHEN rec.status = 'DEFAULTED' THEN 1.50
                        WHEN rec.loan_type = 'MORTGAGE' THEN 0.35
                        WHEN rec.loan_type = 'HELOC'    THEN 0.50
                        WHEN rec.loan_type IN ('AUTO','STUDENT') AND
                             NVL(rec.collateral_type,'NONE') <> 'NONE' THEN 0.75
                        WHEN rec.loan_type = 'BUSINESS' THEN 0.85
                        ELSE 1.00
                    END;

            IF NVL(rec.total_dpd, 0) > 90 AND rec.status <> 'DEFAULTED' THEN
                v_rw := LEAST(v_rw * 1.50, 1.50);
            ELSIF NVL(rec.total_dpd, 0) > 30 THEN
                v_rw := LEAST(v_rw * 1.20, 1.50);
            END IF;

            v_rwa_loan := v_rwa_loan + rec.segment_balance * v_rw;
        END LOOP;

        v_var_99         := calculate_var_exposure('ALL', p_branch_id, 0.99, 10);
        v_rwa_market     := v_var_99 * 12.5;
        v_rwa_operational := v_total_revenue * 0.15 * 12.5;

        p_total_rwa     := v_rwa_loan + v_rwa_market + v_rwa_operational;

        p_tier1_capital := v_total_deposits * 0.06;
        p_tier2_capital := v_total_deposits * 0.02;

        IF p_total_rwa > 0 THEN
            p_car_ratio   := (p_tier1_capital + p_tier2_capital) / p_total_rwa;
            p_tier1_ratio := p_tier1_capital / p_total_rwa;
        ELSE
            p_car_ratio   := 999;
            p_tier1_ratio := 999;
        END IF;

        IF p_car_ratio >= (c_total_capital_min + c_capital_conservation + c_countercyclical_buffer)
           AND p_tier1_ratio >= c_tier1_min_ratio THEN
            p_is_compliant := 'Y';
            p_shortfall    := 0;
        ELSE
            p_is_compliant := 'N';
            p_shortfall    := GREATEST(
                                  (c_total_capital_min + c_capital_conservation) * p_total_rwa
                                  - (p_tier1_capital + p_tier2_capital),
                                  0
                              );
        END IF;

        p_log_risk_event(
            'REGULATORY_CAPITAL',
            NVL(p_branch_id, -1),
            'PORTFOLIO',
            'CAR='||ROUND(p_car_ratio*100,4)||
            '|T1='||ROUND(p_tier1_ratio*100,4)||
            '|COMPLIANT='||p_is_compliant||
            '|SHORTFALL='||ROUND(p_shortfall,2)
        );

        OPEN p_detail_cursor FOR
            SELECT l.loan_type,
                   l.status                                                         AS loan_status,
                   NVL(l.collateral_type, 'NONE')                                  AS collateral_type,
                   COUNT(1)                                                         AS loan_count,
                   ROUND(SUM(l.outstanding_balance), 2)                            AS total_exposure,
                   ROUND(AVG(l.interest_rate), 4)                                  AS avg_interest_rate,
                   CASE l.status
                       WHEN 'DEFAULTED' THEN 1.50
                       ELSE CASE l.loan_type
                                WHEN 'MORTGAGE' THEN 0.35
                                WHEN 'HELOC'    THEN 0.50
                                WHEN 'BUSINESS' THEN 0.85
                                ELSE 1.00
                            END
                   END                                                              AS risk_weight,
                   ROUND(SUM(l.outstanding_balance) *
                       CASE l.status
                           WHEN 'DEFAULTED' THEN 1.50
                           ELSE CASE l.loan_type
                                    WHEN 'MORTGAGE' THEN 0.35
                                    WHEN 'HELOC'    THEN 0.50
                                    WHEN 'BUSINESS' THEN 0.85
                                    ELSE 1.00
                                END
                       END, 2)                                                      AS risk_weighted_assets,
                   ROUND(SUM(l.outstanding_balance) /
                         NULLIF(SUM(SUM(l.outstanding_balance)) OVER (), 0) * 100, 4) AS pct_of_total
            FROM   loans l
            WHERE  (p_branch_id IS NULL OR l.branch_id = p_branch_id)
              AND  l.status NOT IN ('PENDING','REJECTED','WRITTEN_OFF')
              AND  l.outstanding_balance > 0
            GROUP BY l.loan_type, l.status, l.collateral_type
            ORDER BY risk_weighted_assets DESC;

    EXCEPTION
        WHEN OTHERS THEN
            p_log_risk_event('REG_CAPITAL_ERROR', NVL(p_branch_id,-1), 'PORTFOLIO', SQLERRM);
            RAISE;
    END compute_regulatory_capital;

    -- =========================================================================
    -- PROCEDURE: assess_liquidity_risk
    -- Computes Liquidity Coverage Ratio (LCR) and Net Stable Funding Ratio
    -- (NSFR) proxies, plus 30-day and 90-day net cash flow gap analysis.
    -- HQLA = High-Quality Liquid Assets (cash + savings + near-cash).
    -- =========================================================================
    PROCEDURE assess_liquidity_risk(
        p_branch_id        IN  NUMBER DEFAULT NULL,
        p_as_of_date       IN  DATE DEFAULT SYSDATE,
        p_lcr_ratio        OUT NUMBER,
        p_nsfr_ratio       OUT NUMBER,
        p_net_cash_gap_30d OUT NUMBER,
        p_net_cash_gap_90d OUT NUMBER,
        p_hqla_total       OUT NUMBER,
        p_is_lcr_compliant OUT VARCHAR2,
        p_detail_cursor    OUT SYS_REFCURSOR
    ) IS
        v_cash_deposits      NUMBER := 0;
        v_savings_balances   NUMBER := 0;
        v_mm_balances        NUMBER := 0;
        v_hqla_haircut_cash  CONSTANT NUMBER := 1.00;
        v_hqla_haircut_sav   CONSTANT NUMBER := 0.85;
        v_hqla_haircut_mm    CONSTANT NUMBER := 0.70;
        v_net_outflows_30d   NUMBER := 0;
        v_net_inflows_30d    NUMBER := 0;
        v_net_outflows_90d   NUMBER := 0;
        v_net_inflows_90d    NUMBER := 0;
        v_loan_payments_30d  NUMBER := 0;
        v_loan_payments_90d  NUMBER := 0;
        v_fee_income_30d     NUMBER := 0;
        v_fee_income_90d     NUMBER := 0;
        v_interest_due_30d   NUMBER := 0;
        v_interest_due_90d   NUMBER := 0;
        v_expected_withdrawals_30d NUMBER := 0;
        v_expected_withdrawals_90d NUMBER := 0;
        v_available_sf       NUMBER := 0;
        v_required_sf        NUMBER := 0;
        v_total_loans_active NUMBER := 0;
    BEGIN
        SELECT NVL(SUM(CASE WHEN a.account_type = 'CHECKING' THEN a.balance ELSE 0 END), 0),
               NVL(SUM(CASE WHEN a.account_type = 'SAVINGS'  THEN a.balance ELSE 0 END), 0),
               NVL(SUM(CASE WHEN a.account_type = 'MONEY_MKT' THEN a.balance ELSE 0 END), 0)
        INTO   v_cash_deposits, v_savings_balances, v_mm_balances
        FROM   accounts a
        WHERE  a.status = 'ACTIVE'
          AND  (p_branch_id IS NULL OR a.branch_id = p_branch_id);

        p_hqla_total := v_cash_deposits  * v_hqla_haircut_cash
                      + v_savings_balances * v_hqla_haircut_sav
                      + v_mm_balances      * v_hqla_haircut_mm;

        SELECT NVL(SUM(CASE WHEN lp.due_date BETWEEN p_as_of_date AND p_as_of_date + 30
                            THEN lp.scheduled_amount ELSE 0 END), 0),
               NVL(SUM(CASE WHEN lp.due_date BETWEEN p_as_of_date AND p_as_of_date + 90
                            THEN lp.scheduled_amount ELSE 0 END), 0)
        INTO   v_loan_payments_30d, v_loan_payments_90d
        FROM   loan_payments lp
               JOIN loans l ON l.loan_id = lp.loan_id
        WHERE  lp.status IN ('SCHEDULED','PARTIAL','OVERDUE')
          AND  (p_branch_id IS NULL OR l.branch_id = p_branch_id);

        SELECT NVL(SUM(CASE WHEN fl.fee_date BETWEEN p_as_of_date AND p_as_of_date + 30
                            THEN fl.fee_amount ELSE 0 END), 0),
               NVL(SUM(CASE WHEN fl.fee_date BETWEEN p_as_of_date AND p_as_of_date + 90
                            THEN fl.fee_amount ELSE 0 END), 0)
        INTO   v_fee_income_30d, v_fee_income_90d
        FROM   fee_ledger fl
               JOIN accounts a ON a.account_id = fl.account_id
        WHERE  fl.waived = 'N'
          AND  (p_branch_id IS NULL OR a.branch_id = p_branch_id);

        SELECT NVL(SUM(CASE WHEN ip.posting_date BETWEEN p_as_of_date AND p_as_of_date + 30
                            THEN ip.net_interest ELSE 0 END), 0),
               NVL(SUM(CASE WHEN ip.posting_date BETWEEN p_as_of_date AND p_as_of_date + 90
                            THEN ip.net_interest ELSE 0 END), 0)
        INTO   v_interest_due_30d, v_interest_due_90d
        FROM   interest_postings ip
               JOIN accounts a ON a.account_id = ip.account_id
        WHERE  (p_branch_id IS NULL OR a.branch_id = p_branch_id);

        SELECT NVL(SUM(l.outstanding_balance), 0)
        INTO   v_total_loans_active
        FROM   loans l
        WHERE  l.status = 'ACTIVE'
          AND  (p_branch_id IS NULL OR l.branch_id = p_branch_id);

        v_expected_withdrawals_30d := (v_cash_deposits + v_savings_balances) * 0.05;
        v_expected_withdrawals_90d := (v_cash_deposits + v_savings_balances) * 0.12;

        v_net_outflows_30d := v_expected_withdrawals_30d;
        v_net_inflows_30d  := v_loan_payments_30d + v_fee_income_30d + v_interest_due_30d;

        v_net_outflows_90d := v_expected_withdrawals_90d;
        v_net_inflows_90d  := v_loan_payments_90d + v_fee_income_90d + v_interest_due_90d;

        p_net_cash_gap_30d := v_net_inflows_30d - v_net_outflows_30d;
        p_net_cash_gap_90d := v_net_inflows_90d - v_net_outflows_90d;

        IF v_net_outflows_30d > 0 THEN
            p_lcr_ratio := p_hqla_total / v_net_outflows_30d;
        ELSE
            p_lcr_ratio := 999;
        END IF;

        v_available_sf := v_cash_deposits   * 0.00
                        + v_savings_balances * 0.90
                        + v_mm_balances      * 0.50
                        + v_total_loans_active * 0.65;

        v_required_sf  := (v_cash_deposits + v_savings_balances + v_mm_balances) * 0.50
                        + v_total_loans_active * 0.85;

        IF v_required_sf > 0 THEN
            p_nsfr_ratio := v_available_sf / v_required_sf;
        ELSE
            p_nsfr_ratio := 999;
        END IF;

        p_is_lcr_compliant := CASE WHEN p_lcr_ratio >= c_lcr_minimum THEN 'Y' ELSE 'N' END;

        p_log_risk_event(
            'LIQUIDITY_ASSESSMENT',
            NVL(p_branch_id, -1),
            'PORTFOLIO',
            'LCR='||ROUND(p_lcr_ratio,4)||
            '|NSFR='||ROUND(p_nsfr_ratio,4)||
            '|GAP30='||ROUND(p_net_cash_gap_30d,2)||
            '|GAP90='||ROUND(p_net_cash_gap_90d,2)
        );

        OPEN p_detail_cursor FOR
            SELECT a.account_type,
                   a.currency,
                   COUNT(1)                                                          AS account_count,
                   ROUND(SUM(a.balance), 2)                                         AS total_balance,
                   ROUND(SUM(a.available_balance), 2)                               AS available_balance,
                   ROUND(SUM(a.hold_amount), 2)                                     AS held_amount,
                   ROUND(SUM(a.balance) /
                         NULLIF(SUM(SUM(a.balance)) OVER (), 0) * 100, 4)           AS pct_of_total,
                   ROUND(SUM(a.balance) *
                       CASE a.account_type
                           WHEN 'CHECKING'  THEN v_hqla_haircut_cash
                           WHEN 'SAVINGS'   THEN v_hqla_haircut_sav
                           WHEN 'MONEY_MKT' THEN v_hqla_haircut_mm
                           ELSE 0
                       END, 2)                                                      AS hqla_contribution,
                   ROUND(AVG(MONTHS_BETWEEN(SYSDATE, a.opened_date)), 2)            AS avg_account_age_months
            FROM   accounts a
            WHERE  a.status = 'ACTIVE'
              AND  (p_branch_id IS NULL OR a.branch_id = p_branch_id)
            GROUP BY a.account_type, a.currency
            ORDER BY total_balance DESC;

    EXCEPTION
        WHEN OTHERS THEN
            p_log_risk_event('LIQUIDITY_ERROR', NVL(p_branch_id,-1), 'PORTFOLIO', SQLERRM);
            RAISE;
    END assess_liquidity_risk;

    -- =========================================================================
    -- PROCEDURE: detect_concentration_risk
    -- Computes HHI indices for loan type, geographic, and single-name
    -- concentration. Flags alert levels based on thresholds.
    -- =========================================================================
    PROCEDURE detect_concentration_risk(
        p_as_of_date       IN  DATE DEFAULT SYSDATE,
        p_branch_id        IN  NUMBER DEFAULT NULL,
        p_hhi_loan_type    OUT NUMBER,
        p_hhi_geography    OUT NUMBER,
        p_hhi_customer     OUT NUMBER,
        p_top_exposure_pct OUT NUMBER,
        p_alert_level      OUT VARCHAR2,
        p_detail_cursor    OUT SYS_REFCURSOR
    ) IS
        v_total_portfolio  NUMBER := 0;
        v_top5_exposure    NUMBER := 0;
        v_max_single_cust  NUMBER := 0;
        v_max_single_type  NUMBER := 0;
        v_max_single_state NUMBER := 0;
        v_alert_score      NUMBER := 0;
    BEGIN
        SELECT NVL(SUM(l.outstanding_balance), 0)
        INTO   v_total_portfolio
        FROM   loans l
        WHERE  l.status IN ('ACTIVE','DEFAULTED')
          AND  (p_branch_id IS NULL OR l.branch_id = p_branch_id);

        IF v_total_portfolio = 0 THEN
            p_hhi_loan_type   := 0;
            p_hhi_geography   := 0;
            p_hhi_customer    := 0;
            p_top_exposure_pct := 0;
            p_alert_level     := 'NO_DATA';
            OPEN p_detail_cursor FOR SELECT NULL AS no_data FROM DUAL WHERE 1=0;
            RETURN;
        END IF;

        p_hhi_loan_type := calculate_herfindahl_index('LOAN_TYPE',  p_branch_id);
        p_hhi_geography := calculate_herfindahl_index('GEOGRAPHY',  p_branch_id);
        p_hhi_customer  := calculate_herfindahl_index('CUSTOMER',   p_branch_id);

        SELECT NVL(SUM(top5.bal), 0)
        INTO   v_top5_exposure
        FROM   (
                   SELECT l.outstanding_balance AS bal
                   FROM   loans l
                   WHERE  l.status IN ('ACTIVE','DEFAULTED')
                     AND  (p_branch_id IS NULL OR l.branch_id = p_branch_id)
                   ORDER BY l.outstanding_balance DESC
                   FETCH FIRST 5 ROWS ONLY
               ) top5;

        p_top_exposure_pct := v_top5_exposure / v_total_portfolio * 100;

        IF p_hhi_loan_type > c_hhi_threshold THEN
            v_alert_score := v_alert_score + 30;
        ELSIF p_hhi_loan_type > c_hhi_threshold * 0.70 THEN
            v_alert_score := v_alert_score + 15;
        END IF;

        IF p_hhi_geography > c_hhi_threshold THEN
            v_alert_score := v_alert_score + 25;
        ELSIF p_hhi_geography > c_hhi_threshold * 0.70 THEN
            v_alert_score := v_alert_score + 10;
        END IF;

        IF p_hhi_customer > c_hhi_threshold * 0.50 THEN
            v_alert_score := v_alert_score + 35;
        ELSIF p_hhi_customer > c_hhi_threshold * 0.25 THEN
            v_alert_score := v_alert_score + 15;
        END IF;

        IF p_top_exposure_pct > 50 THEN
            v_alert_score := v_alert_score + 20;
        ELSIF p_top_exposure_pct > 30 THEN
            v_alert_score := v_alert_score + 10;
        END IF;

        p_alert_level := CASE
                             WHEN v_alert_score >= 70 THEN 'CRITICAL'
                             WHEN v_alert_score >= 45 THEN 'HIGH'
                             WHEN v_alert_score >= 20 THEN 'MEDIUM'
                             ELSE                          'LOW'
                         END;

        p_log_risk_event(
            'CONCENTRATION_RISK',
            NVL(p_branch_id,-1),
            'PORTFOLIO',
            'HHI_TYPE='||ROUND(p_hhi_loan_type,6)||
            '|HHI_GEO='||ROUND(p_hhi_geography,6)||
            '|HHI_CUST='||ROUND(p_hhi_customer,6)||
            '|TOP5_PCT='||ROUND(p_top_exposure_pct,4)||
            '|ALERT='||p_alert_level
        );

        OPEN p_detail_cursor FOR
            WITH loan_segments AS (
                SELECT l.loan_type,
                       NVL(c.state, 'UNKNOWN')               AS state,
                       l.customer_id,
                       c.customer_code,
                       c.first_name||' '||c.last_name         AS customer_name,
                       l.outstanding_balance
                FROM   loans l
                       JOIN customers c ON c.customer_id = l.customer_id
                WHERE  l.status IN ('ACTIVE','DEFAULTED')
                  AND  (p_branch_id IS NULL OR l.branch_id = p_branch_id)
            ),
            customer_totals AS (
                SELECT customer_id,
                       customer_code,
                       customer_name,
                       SUM(outstanding_balance)  AS cust_total,
                       COUNT(1)                  AS loan_count,
                       RANK() OVER (ORDER BY SUM(outstanding_balance) DESC) AS exposure_rank
                FROM   loan_segments
                GROUP BY customer_id, customer_code, customer_name
            )
            SELECT ct.customer_code,
                   ct.customer_name,
                   ct.loan_count,
                   ROUND(ct.cust_total, 2)                                  AS total_exposure,
                   ROUND(ct.cust_total / v_total_portfolio * 100, 4)        AS pct_of_portfolio,
                   ct.exposure_rank,
                   ROUND(POWER(ct.cust_total / v_total_portfolio, 2), 8)    AS hhi_contribution,
                   CASE
                       WHEN ct.cust_total / v_total_portfolio > 0.10 THEN 'CRITICAL'
                       WHEN ct.cust_total / v_total_portfolio > 0.05 THEN 'HIGH'
                       WHEN ct.cust_total / v_total_portfolio > 0.02 THEN 'MEDIUM'
                       ELSE 'LOW'
                   END                                                       AS concentration_flag
            FROM   customer_totals ct
            ORDER BY ct.exposure_rank;

    EXCEPTION
        WHEN OTHERS THEN
            p_log_risk_event('CONCENTRATION_ERROR', NVL(p_branch_id,-1), 'PORTFOLIO', SQLERRM);
            RAISE;
    END detect_concentration_risk;

    -- =========================================================================
    -- PROCEDURE: generate_risk_scorecard
    -- Aggregates all risk dimensions into a weighted composite scorecard.
    -- Credit: 40%, Liquidity: 25%, Market (VaR): 20%, Operational: 15%.
    -- Each dimension scored 0-100 (higher = riskier).
    -- =========================================================================
    PROCEDURE generate_risk_scorecard(
        p_branch_id         IN  NUMBER DEFAULT NULL,
        p_as_of_date        IN  DATE DEFAULT SYSDATE,
        p_overall_score     OUT NUMBER,
        p_credit_score      OUT NUMBER,
        p_liquidity_score   OUT NUMBER,
        p_market_score      OUT NUMBER,
        p_operational_score OUT NUMBER,
        p_composite_band    OUT VARCHAR2,
        p_scorecard_cursor  OUT SYS_REFCURSOR
    ) IS
        v_npl_ratio         NUMBER := 0;
        v_avg_pd            NUMBER := 0;
        v_total_el          NUMBER := 0;
        v_total_loans       NUMBER := 0;
        v_delinq_rate       NUMBER := 0;
        v_lcr               NUMBER;
        v_nsfr              NUMBER;
        v_gap30             NUMBER;
        v_gap90             NUMBER;
        v_hqla              NUMBER;
        v_lcr_compliant     VARCHAR2(1);
        v_var_99            NUMBER;
        v_var_95            NUMBER;
        v_portfolio_size    NUMBER := 0;
        v_loan_count        NUMBER := 0;
        v_open_fraud_alerts NUMBER := 0;
        v_critical_alerts   NUMBER := 0;
        v_kyc_expired_cnt   NUMBER := 0;
        v_writeoff_count    NUMBER := 0;
        v_hhi_type          NUMBER;
        v_hhi_geo           NUMBER;
        v_hhi_cust          NUMBER;
        v_top5_pct          NUMBER;
        v_alert_lvl         VARCHAR2(20);
        v_dummy_cursor      SYS_REFCURSOR;
        v_el_ratio          NUMBER;
        v_t1_cap            NUMBER;
        v_t2_cap            NUMBER;
        v_rwa               NUMBER;
        v_car               NUMBER;
        v_t1_ratio          NUMBER;
        v_car_compliant     VARCHAR2(1);
        v_car_shortfall     NUMBER;
    BEGIN
        SELECT COUNT(1),
               NVL(SUM(l.outstanding_balance), 0),
               NVL(SUM(CASE WHEN l.status = 'DEFAULTED' THEN l.outstanding_balance ELSE 0 END), 0),
               NVL(SUM(CASE WHEN l.days_past_due > 0    THEN 1 ELSE 0 END), 0),
               NVL(SUM(CASE WHEN l.status = 'WRITTEN_OFF' THEN 1 ELSE 0 END), 0)
        INTO   v_loan_count,
               v_portfolio_size,
               v_total_loans,
               v_delinq_rate,
               v_writeoff_count
        FROM   loans l
        WHERE  l.status NOT IN ('PENDING','REJECTED')
          AND  (p_branch_id IS NULL OR l.branch_id = p_branch_id);

        IF v_portfolio_size > 0 THEN
            v_npl_ratio   := v_total_loans / v_portfolio_size;
            v_delinq_rate := v_delinq_rate / NULLIF(v_loan_count, 0);
        END IF;

        BEGIN
            SELECT NVL(AVG(calculate_probability_of_default(l.customer_id, l.loan_type, p_as_of_date)), 0)
            INTO   v_avg_pd
            FROM   loans l
            WHERE  l.status = 'ACTIVE'
              AND  (p_branch_id IS NULL OR l.branch_id = p_branch_id)
              AND  ROWNUM <= 200;
        EXCEPTION WHEN OTHERS THEN v_avg_pd := 0;
        END;

        FOR rec IN (SELECT l.loan_id
                    FROM   loans l
                    WHERE  l.status IN ('ACTIVE','DEFAULTED')
                      AND  (p_branch_id IS NULL OR l.branch_id = p_branch_id)) LOOP
            BEGIN
                v_total_el := v_total_el + calculate_expected_loss(rec.loan_id, 'BASE', p_as_of_date);
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
        END LOOP;

        v_el_ratio := CASE WHEN v_portfolio_size > 0 THEN v_total_el / v_portfolio_size ELSE 0 END;

        p_credit_score :=
            ROUND(
                  (LEAST(v_npl_ratio   / 0.10, 1) * 35)
                + (LEAST(v_avg_pd      / 0.20, 1) * 30)
                + (LEAST(v_delinq_rate / 0.30, 1) * 20)
                + (LEAST(v_el_ratio    / 0.05, 1) * 15),
            2);

        assess_liquidity_risk(
            p_branch_id        => p_branch_id,
            p_as_of_date       => p_as_of_date,
            p_lcr_ratio        => v_lcr,
            p_nsfr_ratio       => v_nsfr,
            p_net_cash_gap_30d => v_gap30,
            p_net_cash_gap_90d => v_gap90,
            p_hqla_total       => v_hqla,
            p_is_lcr_compliant => v_lcr_compliant,
            p_detail_cursor    => v_dummy_cursor
        );
        IF v_dummy_cursor%ISOPEN THEN CLOSE v_dummy_cursor; END IF;

        p_liquidity_score :=
            ROUND(
                  (CASE WHEN v_lcr  >= 1.50 THEN 0
                        WHEN v_lcr  >= 1.25 THEN 15
                        WHEN v_lcr  >= 1.00 THEN 30
                        WHEN v_lcr  >= 0.75 THEN 60
                        ELSE 90
                   END) * 0.40
                + (CASE WHEN v_nsfr >= 1.50 THEN 0
                        WHEN v_nsfr >= 1.25 THEN 15
                        WHEN v_nsfr >= 1.00 THEN 30
                        WHEN v_nsfr >= 0.75 THEN 55
                        ELSE 85
                   END) * 0.35
                + (CASE WHEN v_gap30 >= 0 THEN 0 ELSE LEAST(ABS(v_gap30)/NULLIF(v_hqla,0)*100, 50) END) * 0.25,
            2);

        v_var_99 := calculate_var_exposure('ALL', p_branch_id, 0.99, 1);
        v_var_95 := calculate_var_exposure('ALL', p_branch_id, 0.95, 1);

        compute_regulatory_capital(
            p_branch_id     => p_branch_id,
            p_as_of_date    => p_as_of_date,
            p_tier1_capital => v_t1_cap,
            p_tier2_capital => v_t2_cap,
            p_total_rwa     => v_rwa,
            p_car_ratio     => v_car,
            p_tier1_ratio   => v_t1_ratio,
            p_is_compliant  => v_car_compliant,
            p_shortfall     => v_car_shortfall,
            p_detail_cursor => v_dummy_cursor
        );
        IF v_dummy_cursor%ISOPEN THEN CLOSE v_dummy_cursor; END IF;

        p_market_score :=
            ROUND(
                  (CASE WHEN v_car_compliant = 'Y' THEN 10 ELSE 70 END) * 0.50
                + (CASE WHEN v_var_99 <= v_portfolio_size * 0.01 THEN 5
                        WHEN v_var_99 <= v_portfolio_size * 0.03 THEN 20
                        WHEN v_var_99 <= v_portfolio_size * 0.07 THEN 45
                        ELSE 80
                   END) * 0.30
                + (LEAST(NVL(v_car_shortfall,0) / NULLIF(v_rwa*0.01,0), 1) * 40) * 0.20,
            2);

        SELECT COUNT(1),
               NVL(SUM(CASE WHEN fa.severity = 'CRITICAL' THEN 1 ELSE 0 END), 0)
        INTO   v_open_fraud_alerts, v_critical_alerts
        FROM   fraud_alerts fa
               JOIN accounts a ON a.account_id = fa.account_id
        WHERE  fa.status IN ('OPEN','INVESTIGATING')
          AND  (p_branch_id IS NULL OR a.branch_id = p_branch_id);

        SELECT COUNT(1)
        INTO   v_kyc_expired_cnt
        FROM   customers c
               JOIN accounts a ON a.customer_id = c.customer_id
        WHERE  c.kyc_status IN ('EXPIRED','REJECTED')
          AND  a.status = 'ACTIVE'
          AND  (p_branch_id IS NULL OR a.branch_id = p_branch_id);

        p_operational_score :=
            ROUND(
                  (LEAST(v_open_fraud_alerts / GREATEST(v_loan_count * 0.01, 1), 1) * 100) * 0.40
                + (LEAST(v_critical_alerts   / GREATEST(v_loan_count * 0.005, 1), 1) * 100) * 0.35
                + (LEAST(v_kyc_expired_cnt   / GREATEST(v_loan_count * 0.05, 1), 1) * 100) * 0.25,
            2);

        p_overall_score :=
            ROUND(
                  p_credit_score      * 0.40
                + p_liquidity_score   * 0.25
                + p_market_score      * 0.20
                + p_operational_score * 0.15,
            2);

        p_composite_band := get_risk_band(p_overall_score);

        p_log_risk_event(
            'RISK_SCORECARD',
            NVL(p_branch_id, -1),
            'PORTFOLIO',
            'OVERALL='||p_overall_score||
            '|CREDIT='||p_credit_score||
            '|LIQUIDITY='||p_liquidity_score||
            '|MARKET='||p_market_score||
            '|OPERATIONAL='||p_operational_score||
            '|BAND='||p_composite_band
        );

        OPEN p_scorecard_cursor FOR
            SELECT 'CREDIT_RISK'     AS risk_dimension,
                   p_credit_score    AS dimension_score,
                   0.40              AS weight,
                   ROUND(p_credit_score * 0.40, 4) AS weighted_score,
                   get_risk_band(p_credit_score)    AS band,
                   'NPL='||ROUND(v_npl_ratio*100,4)||'% | Avg_PD='||ROUND(v_avg_pd*100,4)||'% | Delinq='||ROUND(v_delinq_rate*100,2)||'%' AS key_metrics
            FROM   DUAL
            UNION ALL
            SELECT 'LIQUIDITY_RISK',
                   p_liquidity_score,
                   0.25,
                   ROUND(p_liquidity_score * 0.25, 4),
                   get_risk_band(p_liquidity_score),
                   'LCR='||ROUND(NVL(v_lcr,0),4)||' | NSFR='||ROUND(NVL(v_nsfr,0),4)||' | Gap30d='||ROUND(NVL(v_gap30,0),2)
            FROM   DUAL
            UNION ALL
            SELECT 'MARKET_RISK',
                   p_market_score,
                   0.20,
                   ROUND(p_market_score * 0.20, 4),
                   get_risk_band(p_market_score),
                   'CAR='||ROUND(NVL(v_car,0)*100,4)||'% | VaR99='||ROUND(NVL(v_var_99,0),2)||' | RWA='||ROUND(NVL(v_rwa,0),2)
            FROM   DUAL
            UNION ALL
            SELECT 'OPERATIONAL_RISK',
                   p_operational_score,
                   0.15,
                   ROUND(p_operational_score * 0.15, 4),
                   get_risk_band(p_operational_score),
                   'FraudAlerts='||v_open_fraud_alerts||' | Critical='||v_critical_alerts||' | KYC_Expired='||v_kyc_expired_cnt
            FROM   DUAL
            UNION ALL
            SELECT 'COMPOSITE_SCORE',
                   p_overall_score,
                   1.00,
                   p_overall_score,
                   p_composite_band,
                   'Portfolio='||ROUND(v_portfolio_size,2)||' | Loans='||v_loan_count||' | EL='||ROUND(v_total_el,2)
            FROM   DUAL
            ORDER BY 3 DESC;

    EXCEPTION
        WHEN OTHERS THEN
            p_log_risk_event('SCORECARD_ERROR', NVL(p_branch_id,-1), 'PORTFOLIO', SQLERRM);
            RAISE;
    END generate_risk_scorecard;

    -- =========================================================================
    -- PROCEDURE: run_delinquency_migration_analysis
    -- Tracks how loans migrate between delinquency buckets over a period.
    -- DPD Buckets: CURRENT (0), 1-30, 31-60, 61-90, 91-180, 180+, DEFAULT.
    -- Produces a migration matrix and summary statistics.
    -- =========================================================================
    PROCEDURE run_delinquency_migration_analysis(
        p_from_date      IN  DATE,
        p_to_date        IN  DATE,
        p_branch_id      IN  NUMBER DEFAULT NULL,
        p_migration_cursor OUT SYS_REFCURSOR,
        p_summary_cursor   OUT SYS_REFCURSOR
    ) IS
        v_period_months NUMBER;
        v_from_trunc    DATE := TRUNC(p_from_date);
        v_to_trunc      DATE := TRUNC(p_to_date);

        FUNCTION f_dpd_bucket(p_dpd IN NUMBER, p_status IN VARCHAR2)
        RETURN VARCHAR2 IS
        BEGIN
            IF p_status = 'DEFAULTED' OR p_status = 'WRITTEN_OFF' THEN
                RETURN 'D - DEFAULT';
            ELSIF p_status IN ('PAID_OFF','CLOSED') THEN
                RETURN 'PAID_OFF';
            ELSIF NVL(p_dpd, 0) = 0 THEN
                RETURN 'A - CURRENT';
            ELSIF p_dpd <= 30 THEN
                RETURN 'B - 1-30DPD';
            ELSIF p_dpd <= 60 THEN
                RETURN 'C - 31-60DPD';
            ELSIF p_dpd <= 90 THEN
                RETURN 'D - 61-90DPD';
            ELSIF p_dpd <= 180 THEN
                RETURN 'E - 91-180DPD';
            ELSE
                RETURN 'F - 180+DPD';
            END IF;
        END f_dpd_bucket;

    BEGIN
        IF p_from_date IS NULL OR p_to_date IS NULL THEN
            RAISE_APPLICATION_ERROR(-20202, 'From/To dates are required for migration analysis.');
        END IF;
        IF p_to_date <= p_from_date THEN
            RAISE_APPLICATION_ERROR(-20202, 'To-date must be after from-date.');
        END IF;

        v_period_months := ROUND(MONTHS_BETWEEN(v_to_trunc, v_from_trunc), 1);

        OPEN p_migration_cursor FOR
            WITH snapshot_start AS (
                SELECT l.loan_id,
                       l.loan_number,
                       l.loan_type,
                       l.customer_id,
                       l.branch_id,
                       l.outstanding_balance                                        AS balance_start,
                       l.days_past_due                                              AS dpd_start,
                       l.status                                                     AS status_start,
                       CASE
                           WHEN l.status IN ('DEFAULTED','WRITTEN_OFF') THEN 'D - DEFAULT'
                           WHEN l.status IN ('PAID_OFF','CLOSED')        THEN 'PAID_OFF'
                           WHEN NVL(l.days_past_due,0) = 0               THEN 'A - CURRENT'
                           WHEN l.days_past_due <= 30                    THEN 'B - 1-30DPD'
                           WHEN l.days_past_due <= 60                    THEN 'C - 31-60DPD'
                           WHEN l.days_past_due <= 90                    THEN 'D - 61-90DPD'
                           WHEN l.days_past_due <= 180                   THEN 'E - 91-180DPD'
                           ELSE                                               'F - 180+DPD'
                       END                                                           AS bucket_start
                FROM   loans l
                WHERE  l.created_at    <= v_from_trunc + 1
                  AND  l.status NOT IN ('PENDING','REJECTED')
                  AND  (p_branch_id IS NULL OR l.branch_id = p_branch_id)
            ),
            payment_changes AS (
                SELECT lp.loan_id,
                       SUM(lp.paid_amount)                                          AS total_paid,
                       SUM(CASE WHEN lp.status = 'OVERDUE' THEN 1 ELSE 0 END)      AS overdue_count,
                       MAX(lp.due_date)                                             AS last_due_date
                FROM   loan_payments lp
                WHERE  lp.due_date BETWEEN v_from_trunc AND v_to_trunc
                GROUP BY lp.loan_id
            ),
            snapshot_end AS (
                SELECT l.loan_id,
                       l.outstanding_balance                                        AS balance_end,
                       l.days_past_due                                              AS dpd_end,
                       l.status                                                     AS status_end,
                       CASE
                           WHEN l.status IN ('DEFAULTED','WRITTEN_OFF') THEN 'D - DEFAULT'
                           WHEN l.status IN ('PAID_OFF','CLOSED')        THEN 'PAID_OFF'
                           WHEN NVL(l.days_past_due,0) = 0               THEN 'A - CURRENT'
                           WHEN l.days_past_due <= 30                    THEN 'B - 1-30DPD'
                           WHEN l.days_past_due <= 60                    THEN 'C - 31-60DPD'
                           WHEN l.days_past_due <= 90                    THEN 'D - 61-90DPD'
                           WHEN l.days_past_due <= 180                   THEN 'E - 91-180DPD'
                           ELSE                                               'F - 180+DPD'
                       END                                                           AS bucket_end
                FROM   loans l
                WHERE  (p_branch_id IS NULL OR l.branch_id = p_branch_id)
            )
            SELECT ss.loan_id,
                   ss.loan_number,
                   ss.loan_type,
                   ss.bucket_start,
                   se.bucket_end,
                   ROUND(ss.balance_start, 2)                                       AS balance_start,
                   ROUND(se.balance_end, 2)                                         AS balance_end,
                   ROUND(se.balance_end - ss.balance_start, 2)                      AS balance_delta,
                   ss.dpd_start,
                   se.dpd_end,
                   se.dpd_end - ss.dpd_start                                        AS dpd_change,
                   NVL(pc.total_paid, 0)                                            AS total_paid_period,
                   NVL(pc.overdue_count, 0)                                         AS overdue_payments,
                   CASE WHEN ss.bucket_start = se.bucket_end THEN 'STABLE'
                        WHEN se.bucket_end > ss.bucket_start THEN 'DOWNGRADE'
                        ELSE 'UPGRADE'
                   END                                                               AS migration_direction,
                   RANK() OVER (
                       PARTITION BY ss.bucket_start
                       ORDER BY ABS(se.dpd_end - ss.dpd_start) DESC
                   )                                                                 AS rank_within_bucket
            FROM   snapshot_start ss
                   JOIN snapshot_end se     ON se.loan_id = ss.loan_id
                   LEFT JOIN payment_changes pc ON pc.loan_id = ss.loan_id
            ORDER BY ss.bucket_start, migration_direction, balance_delta;

        OPEN p_summary_cursor FOR
            WITH migration_base AS (
                SELECT CASE
                           WHEN l.status IN ('DEFAULTED','WRITTEN_OFF') THEN 'D - DEFAULT'
                           WHEN l.status IN ('PAID_OFF','CLOSED')        THEN 'PAID_OFF'
                           WHEN NVL(l.days_past_due,0) = 0               THEN 'A - CURRENT'
                           WHEN l.days_past_due <= 30                    THEN 'B - 1-30DPD'
                           WHEN l.days_past_due <= 60                    THEN 'C - 31-60DPD'
                           WHEN l.days_past_due <= 90                    THEN 'D - 61-90DPD'
                           WHEN l.days_past_due <= 180                   THEN 'E - 91-180DPD'
                           ELSE                                               'F - 180+DPD'
                       END                                                           AS current_bucket,
                       l.loan_type,
                       l.status,
                       l.outstanding_balance,
                       l.days_past_due,
                       l.times_30_dpd,
                       l.times_60_dpd,
                       l.times_90_dpd
                FROM   loans l
                WHERE  l.status NOT IN ('PENDING','REJECTED')
                  AND  (p_branch_id IS NULL OR l.branch_id = p_branch_id)
            )
            SELECT current_bucket,
                   COUNT(1)                                                          AS loan_count,
                   ROUND(SUM(outstanding_balance), 2)                               AS total_balance,
                   ROUND(AVG(outstanding_balance), 2)                               AS avg_balance,
                   ROUND(SUM(outstanding_balance) /
                         SUM(SUM(outstanding_balance)) OVER () * 100, 4)           AS pct_of_portfolio,
                   ROUND(AVG(days_past_due), 2)                                     AS avg_dpd,
                   MAX(days_past_due)                                               AS max_dpd,
                   SUM(times_30_dpd)                                                AS total_30dpd_events,
                   SUM(times_60_dpd)                                                AS total_60dpd_events,
                   SUM(times_90_dpd)                                                AS total_90dpd_events,
                   ROUND(v_period_months, 1)                                        AS analysis_period_months,
                   v_from_trunc                                                     AS period_from,
                   v_to_trunc                                                       AS period_to
            FROM   migration_base
            GROUP BY current_bucket
            ORDER BY current_bucket;

    EXCEPTION
        WHEN OTHERS THEN
            p_log_risk_event('MIGRATION_ANALYSIS_ERROR', NVL(p_branch_id,-1), 'PORTFOLIO', SQLERRM);
            RAISE;
    END run_delinquency_migration_analysis;

END pkg_advanced_risk_engine;
/
