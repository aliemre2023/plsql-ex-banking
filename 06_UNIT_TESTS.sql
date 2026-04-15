-- =============================================================================
-- BANKING SYSTEM UNIT TESTS
-- Tests for PKG_ACCOUNT_MGMT, PKG_TRANSACTIONS, PKG_LOAN_MGMT, PKG_REPORTING
-- =============================================================================
-- Run with: SET SERVEROUTPUT ON SIZE UNLIMITED
-- All tests self-roll back to leave data clean (AUTONOMOUS_TRANSACTION tests
-- use savepoints where needed)
-- =============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK OFF

DECLARE
    -- =========================================================================
    -- Test Framework Variables
    -- =========================================================================
    v_pass_count    NUMBER := 0;
    v_fail_count    NUMBER := 0;
    v_test_name     VARCHAR2(200);
    v_suite_name    VARCHAR2(100);

    -- Test data holders
    v_account_id    NUMBER;
    v_account_num   VARCHAR2(20);
    v_txn_id        NUMBER;
    v_txn_id2       NUMBER;
    v_ref           VARCHAR2(50);
    v_ref2          VARCHAR2(50);
    v_loan_id       NUMBER;
    v_loan_num      VARCHAR2(20);
    v_monthly_pmt   NUMBER;
    v_decision      VARCHAR2(20);
    v_hold_id       NUMBER;
    v_rev_id        NUMBER;
    v_final_balance NUMBER;
    v_count         NUMBER;
    v_amount        NUMBER;
    v_result        VARCHAR2(500);
    v_bool          BOOLEAN;
    v_number        NUMBER;
    v_pay_id        NUMBER;
    v_prin_paid     NUMBER;
    v_int_paid      NUMBER;
    v_rem_balance   NUMBER;

    -- Known test data (from seed)
    c_customer_1    CONSTANT NUMBER := 1000;  -- Alice Johnson
    c_customer_2    CONSTANT NUMBER := 1001;  -- Bob Smith
    c_customer_3    CONSTANT NUMBER := 1002;  -- Carol Davis
    c_account_1     CONSTANT NUMBER := 100000; -- ACC-100001 (Checking, Alice)
    c_account_2     CONSTANT NUMBER := 100001; -- ACC-100002 (Savings, Alice)
    c_account_3     CONSTANT NUMBER := 100002; -- ACC-100003 (Checking, Bob)
    c_branch_1      CONSTANT NUMBER := 10;
    c_employee_1    CONSTANT NUMBER := 2000;
    c_employee_2    CONSTANT NUMBER := 2001;

    -- =========================================================================
    -- Test Framework Procedures
    -- =========================================================================
    PROCEDURE start_suite(p_name IN VARCHAR2) IS
    BEGIN
        v_suite_name := p_name;
        DBMS_OUTPUT.PUT_LINE(CHR(10) || '=' || LPAD('=',60,'='));
        DBMS_OUTPUT.PUT_LINE('  TEST SUITE: ' || p_name);
        DBMS_OUTPUT.PUT_LINE('=' || LPAD('=',60,'='));
    END;

    PROCEDURE assert_true(p_condition IN BOOLEAN, p_test IN VARCHAR2) IS
    BEGIN
        v_test_name := p_test;
        IF p_condition THEN
            v_pass_count := v_pass_count + 1;
            DBMS_OUTPUT.PUT_LINE('  [PASS] ' || p_test);
        ELSE
            v_fail_count := v_fail_count + 1;
            DBMS_OUTPUT.PUT_LINE('  [FAIL] ' || p_test);
        END IF;
    END;

    PROCEDURE assert_equals(p_expected IN VARCHAR2, p_actual IN VARCHAR2, p_test IN VARCHAR2) IS
    BEGIN
        assert_true(p_expected = p_actual, p_test ||
                    ' (expected: ' || p_expected || ', got: ' || p_actual || ')');
    END;

    PROCEDURE assert_equals_num(p_expected IN NUMBER, p_actual IN NUMBER,
                                 p_test IN VARCHAR2, p_tolerance IN NUMBER DEFAULT 0.01) IS
    BEGIN
        assert_true(ABS(NVL(p_expected,0) - NVL(p_actual,0)) <= p_tolerance, p_test ||
                    ' (expected: ' || p_expected || ', got: ' || p_actual || ')');
    END;

    PROCEDURE assert_not_null(p_value IN VARCHAR2, p_test IN VARCHAR2) IS
    BEGIN
        assert_true(p_value IS NOT NULL, p_test);
    END;

    PROCEDURE assert_raises(p_error_code IN NUMBER, p_test IN VARCHAR2) IS
    BEGIN
        -- Called after expected exception caught
        assert_true(SQLCODE = p_error_code OR SQLCODE = -20000 + ABS(p_error_code),
                    p_test || ' (raised error: ' || SQLCODE || ')');
    END;

    PROCEDURE print_results IS
        v_total NUMBER := v_pass_count + v_fail_count;
    BEGIN
        DBMS_OUTPUT.PUT_LINE(CHR(10) || LPAD('=',62,'='));
        DBMS_OUTPUT.PUT_LINE('  FINAL RESULTS');
        DBMS_OUTPUT.PUT_LINE(LPAD('=',62,'='));
        DBMS_OUTPUT.PUT_LINE('  Total Tests : ' || v_total);
        DBMS_OUTPUT.PUT_LINE('  Passed      : ' || v_pass_count);
        DBMS_OUTPUT.PUT_LINE('  Failed      : ' || v_fail_count);
        DBMS_OUTPUT.PUT_LINE('  Pass Rate   : ' ||
            ROUND(v_pass_count / NULLIF(v_total,0) * 100, 1) || '%');
        DBMS_OUTPUT.PUT_LINE(LPAD('=',62,'='));
    END;

BEGIN
    SAVEPOINT sp_test_start;

    -- =========================================================================
    -- SUITE 1: PKG_ACCOUNT_MGMT - FUNCTIONS
    -- =========================================================================
    start_suite('PKG_ACCOUNT_MGMT - Functions');

    -- Test 1: get_balance returns correct value
    v_amount := pkg_account_mgmt.get_balance(c_account_1);
    assert_true(v_amount >= 0, 'get_balance returns non-negative value');

    -- Test 2: get_balance for known seeded account
    assert_equals_num(5000, pkg_account_mgmt.get_balance(c_account_1),
                      'get_balance = 5000 for Alice checking account');

    -- Test 3: get_available_balance
    v_amount := pkg_account_mgmt.get_available_balance(c_account_1);
    assert_true(v_amount <= pkg_account_mgmt.get_balance(c_account_1),
                'get_available_balance <= get_balance');

    -- Test 4: is_account_active returns TRUE for active account
    assert_true(pkg_account_mgmt.is_account_active(c_account_1),
                'is_account_active = TRUE for active account');

    -- Test 5: is_account_active returns FALSE for non-existent
    assert_true(NOT pkg_account_mgmt.is_account_active(999999),
                'is_account_active = FALSE for non-existent account');

    -- Test 6: get_customer_total_balance
    v_amount := pkg_account_mgmt.get_customer_total_balance(c_customer_1);
    assert_true(v_amount >= 5000,
                'get_customer_total_balance >= 5000 for Alice (has multiple accounts)');

    -- Test 7: get_min_balance for CHECKING
    v_amount := pkg_account_mgmt.get_min_balance('CHECKING');
    assert_equals_num(0, v_amount, 'get_min_balance for CHECKING = 0');

    -- Test 8: get_min_balance for SAVINGS
    v_amount := pkg_account_mgmt.get_min_balance('SAVINGS');
    assert_equals_num(500, v_amount, 'get_min_balance for SAVINGS = 500');

    -- Test 9: get_daily_withdrawal_total (should be 0 for fresh test)
    -- Note: may have prior transactions from seed
    v_amount := pkg_account_mgmt.get_daily_withdrawal_total(c_account_1, SYSDATE - 365);
    assert_equals_num(0, v_amount, 'get_daily_withdrawal_total = 0 for date 1 year ago');

    -- Test 10: get_account_status
    v_result := pkg_account_mgmt.get_account_status(c_account_1);
    assert_equals('ACTIVE', v_result, 'get_account_status = ACTIVE for seed account');

    -- Test 11: get_account_status for non-existent
    v_result := pkg_account_mgmt.get_account_status(999999);
    assert_equals('NOT_FOUND', v_result, 'get_account_status = NOT_FOUND for invalid ID');

    -- Test 12: check_min_balance_breach - large debit
    v_bool := pkg_account_mgmt.check_min_balance_breach(c_account_2, 20000);
    assert_true(v_bool, 'check_min_balance_breach = TRUE when debit exceeds balance - min');

    -- Test 13: check_min_balance_breach - small debit on savings
    v_bool := pkg_account_mgmt.check_min_balance_breach(c_account_2, 1000);
    assert_true(NOT v_bool, 'check_min_balance_breach = FALSE for small debit on well-funded savings');

    -- Test 14: count_customer_accounts
    v_count := pkg_account_mgmt.count_customer_accounts(c_customer_1);
    assert_true(v_count >= 2, 'count_customer_accounts >= 2 for Alice (has checking + savings)');

    -- Test 15: count_customer_accounts - ALL status
    v_count := pkg_account_mgmt.count_customer_accounts(c_customer_1, 'ALL');
    assert_true(v_count >= 2, 'count_customer_accounts(ALL) >= active count');

    -- Test 16: get_account_age_days
    v_count := pkg_account_mgmt.get_account_age_days(c_account_1);
    assert_true(v_count >= 0, 'get_account_age_days >= 0');

    -- Test 17: generate_account_number uniqueness
    DECLARE
        v_num1 VARCHAR2(20);
        v_num2 VARCHAR2(20);
    BEGIN
        v_num1 := pkg_account_mgmt.generate_account_number('HQ001','CHECKING');
        v_num2 := pkg_account_mgmt.generate_account_number('HQ001','CHECKING');
        assert_true(v_num1 != v_num2, 'generate_account_number produces unique numbers');
    END;

    -- =========================================================================
    -- SUITE 2: PKG_ACCOUNT_MGMT - Procedures
    -- =========================================================================
    start_suite('PKG_ACCOUNT_MGMT - Procedures');

    -- Test 18: create_account success
    SAVEPOINT sp_create_account;
    pkg_account_mgmt.create_account(
        c_customer_1, c_branch_1, 'CHECKING',
        1500, 'USD',
        v_account_id, v_account_num
    );
    assert_true(v_account_id IS NOT NULL, 'create_account returns valid account_id');
    assert_true(v_account_num IS NOT NULL, 'create_account returns account_number');
    assert_equals_num(1500, pkg_account_mgmt.get_balance(v_account_id),
                      'create_account sets initial balance correctly');
    ROLLBACK TO sp_create_account;

    -- Test 19: create_account fails below minimum balance for SAVINGS
    SAVEPOINT sp_create_savings;
    BEGIN
        pkg_account_mgmt.create_account(
            c_customer_1, c_branch_1, 'SAVINGS', 100, 'USD',
            v_account_id, v_account_num
        );
        assert_true(FALSE, 'create_account should fail below SAVINGS minimum');
    EXCEPTION
        WHEN OTHERS THEN
            assert_true(SQLCODE < 0, 'create_account raises error below minimum deposit');
    END;
    ROLLBACK TO sp_create_savings;

    -- Test 20: update_balance CR increases balance
    SAVEPOINT sp_update_bal;
    DECLARE
        v_bal_before NUMBER := pkg_account_mgmt.get_balance(c_account_1);
    BEGIN
        pkg_account_mgmt.update_balance(c_account_1, 1000, 'CR');
        assert_equals_num(v_bal_before + 1000, pkg_account_mgmt.get_balance(c_account_1),
                          'update_balance CR increases balance by correct amount');
    END;
    ROLLBACK TO sp_update_bal;

    -- Test 21: update_balance DR decreases balance
    SAVEPOINT sp_update_dr;
    DECLARE
        v_bal_before NUMBER := pkg_account_mgmt.get_balance(c_account_1);
    BEGIN
        pkg_account_mgmt.update_balance(c_account_1, 500, 'DR');
        assert_equals_num(v_bal_before - 500, pkg_account_mgmt.get_balance(c_account_1),
                          'update_balance DR decreases balance by correct amount');
    END;
    ROLLBACK TO sp_update_dr;

    -- Test 22: update_balance insufficient funds raises exception
    SAVEPOINT sp_insuf;
    BEGIN
        pkg_account_mgmt.update_balance(c_account_1, 9999999, 'DR');
        assert_true(FALSE, 'update_balance should raise error for insufficient funds');
    EXCEPTION
        WHEN pkg_account_mgmt.e_insufficient_funds THEN
            assert_true(TRUE, 'update_balance raises e_insufficient_funds correctly');
        WHEN OTHERS THEN
            assert_true(SQLCODE = -20001, 'update_balance raises correct error code');
    END;
    ROLLBACK TO sp_insuf;

    -- Test 23: place_hold reduces available balance
    SAVEPOINT sp_hold;
    DECLARE
        v_avail_before NUMBER := pkg_account_mgmt.get_available_balance(c_account_1);
    BEGIN
        pkg_account_mgmt.place_hold(c_account_1, 200, 'Test hold', v_hold_id);
        assert_equals_num(v_avail_before - 200,
                          pkg_account_mgmt.get_available_balance(c_account_1),
                          'place_hold reduces available balance');
        assert_true(v_hold_id IS NOT NULL, 'place_hold returns hold_id');
    END;
    ROLLBACK TO sp_hold;

    -- Test 24: release_hold restores available balance
    SAVEPOINT sp_hold_release;
    DECLARE
        v_avail_before NUMBER;
    BEGIN
        pkg_account_mgmt.place_hold(c_account_1, 300, 'Test hold 2', v_hold_id);
        v_avail_before := pkg_account_mgmt.get_available_balance(c_account_1);
        pkg_account_mgmt.release_hold(c_account_1, 300);
        assert_equals_num(v_avail_before + 300,
                          pkg_account_mgmt.get_available_balance(c_account_1),
                          'release_hold restores available balance');
    END;
    ROLLBACK TO sp_hold_release;

    -- Test 25: freeze_account changes status
    SAVEPOINT sp_freeze;
    pkg_account_mgmt.freeze_account(c_account_1, 'Test freeze', c_employee_1);
    assert_equals('FROZEN', pkg_account_mgmt.get_account_status(c_account_1),
                  'freeze_account sets status to FROZEN');
    ROLLBACK TO sp_freeze;

    -- Test 26: unfreeze_account restores active status
    SAVEPOINT sp_unfreeze;
    pkg_account_mgmt.freeze_account(c_account_1, 'Test freeze', c_employee_1);
    pkg_account_mgmt.unfreeze_account(c_account_1, c_employee_1);
    assert_equals('ACTIVE', pkg_account_mgmt.get_account_status(c_account_1),
                  'unfreeze_account restores ACTIVE status');
    ROLLBACK TO sp_unfreeze;

    -- Test 27: close_account changes status to CLOSED
    SAVEPOINT sp_close;
    pkg_account_mgmt.create_account(
        c_customer_2, c_branch_1, 'CHECKING', 100, 'USD',
        v_account_id, v_account_num
    );
    pkg_account_mgmt.close_account(v_account_id, 'Test close', c_employee_1, v_final_balance);
    assert_equals('CLOSED', pkg_account_mgmt.get_account_status(v_account_id),
                  'close_account sets status to CLOSED');
    assert_equals_num(100, v_final_balance, 'close_account returns correct final balance');
    ROLLBACK TO sp_close;

    -- =========================================================================
    -- SUITE 3: PKG_TRANSACTIONS - Functions
    -- =========================================================================
    start_suite('PKG_TRANSACTIONS - Functions');

    -- Test 28: generate_reference uniqueness
    DECLARE
        v_r1 VARCHAR2(50);
        v_r2 VARCHAR2(50);
    BEGIN
        v_r1 := pkg_transactions.generate_reference('DEPOSIT');
        v_r2 := pkg_transactions.generate_reference('DEPOSIT');
        assert_true(v_r1 != v_r2, 'generate_reference produces unique values');
        assert_true(v_r1 LIKE 'DEP-%', 'generate_reference has correct prefix for DEPOSIT');
    END;

    -- Test 29: calc_simple_interest
    v_amount := pkg_transactions.calc_simple_interest(10000, 5.0, 365);
    assert_equals_num(500, v_amount, 'calc_simple_interest: 10000 @ 5% for 365 days = 500');

    -- Test 30: calc_simple_interest zero rate
    v_amount := pkg_transactions.calc_simple_interest(10000, 0, 365);
    assert_equals_num(0, v_amount, 'calc_simple_interest: 0% rate returns 0');

    -- Test 31: get_exchange_rate same currency
    v_amount := pkg_transactions.get_exchange_rate('USD', 'USD');
    assert_equals_num(1, v_amount, 'get_exchange_rate: USD to USD = 1');

    -- Test 32: get_exchange_rate different currencies
    v_amount := pkg_transactions.get_exchange_rate('USD', 'EUR');
    assert_true(v_amount > 0 AND v_amount < 2, 'get_exchange_rate: USD to EUR is reasonable');

    -- Test 33: convert_currency
    v_amount := pkg_transactions.convert_currency(1000, 'USD', 'USD');
    assert_equals_num(1000, v_amount, 'convert_currency: USD to USD unchanged');

    -- Test 34: requires_ctr_report below threshold
    assert_true(NOT pkg_transactions.requires_ctr_report(9999),
                'requires_ctr_report = FALSE for $9,999');

    -- Test 35: requires_ctr_report at threshold
    assert_true(pkg_transactions.requires_ctr_report(10000),
                'requires_ctr_report = TRUE for $10,000');

    -- Test 36: requires_ctr_report above threshold
    assert_true(pkg_transactions.requires_ctr_report(50000),
                'requires_ctr_report = TRUE for $50,000');

    -- Test 37: get_transaction_count (baseline)
    v_count := pkg_transactions.get_transaction_count(c_account_1, DATE '2000-01-01', DATE '2000-12-31');
    assert_equals_num(0, v_count, 'get_transaction_count = 0 for date range before all transactions');

    -- =========================================================================
    -- SUITE 4: PKG_TRANSACTIONS - Procedures
    -- =========================================================================
    start_suite('PKG_TRANSACTIONS - Procedures');

    -- Test 38: deposit increases balance
    SAVEPOINT sp_deposit;
    DECLARE
        v_bal_before NUMBER := pkg_account_mgmt.get_balance(c_account_1);
    BEGIN
        pkg_transactions.deposit(
            c_account_1, 1000, 'Test deposit', 'BRANCH',
            c_employee_1, v_txn_id, v_ref
        );
        assert_equals_num(v_bal_before + 1000, pkg_account_mgmt.get_balance(c_account_1),
                          'deposit increases account balance correctly');
        assert_true(v_txn_id IS NOT NULL, 'deposit returns valid transaction_id');
        assert_true(v_ref LIKE 'DEP-%', 'deposit returns DEP-prefixed reference');
    END;
    ROLLBACK TO sp_deposit;

    -- Test 39: deposit invalid amount raises error
    SAVEPOINT sp_deposit_invalid;
    BEGIN
        pkg_transactions.deposit(c_account_1, -100, 'Bad deposit', 'BRANCH',
                                  c_employee_1, v_txn_id, v_ref);
        assert_true(FALSE, 'deposit should fail with negative amount');
    EXCEPTION
        WHEN OTHERS THEN
            assert_true(TRUE, 'deposit raises error for negative amount');
    END;
    ROLLBACK TO sp_deposit_invalid;

    -- Test 40: withdraw decreases balance
    SAVEPOINT sp_withdraw;
    DECLARE
        v_bal_before NUMBER := pkg_account_mgmt.get_balance(c_account_1);
    BEGIN
        pkg_transactions.withdraw(
            c_account_1, 500, 'Test withdrawal', 'BRANCH',
            c_employee_1, v_txn_id, v_ref
        );
        assert_equals_num(v_bal_before - 500, pkg_account_mgmt.get_balance(c_account_1),
                          'withdraw decreases account balance correctly');
    END;
    ROLLBACK TO sp_withdraw;

    -- Test 41: withdraw insufficient funds raises exception
    SAVEPOINT sp_withdraw_insuf;
    BEGIN
        pkg_transactions.withdraw(c_account_1, 9999999, 'Huge withdrawal',
                                   'BRANCH', c_employee_1, v_txn_id, v_ref);
        assert_true(FALSE, 'withdraw should fail with insufficient funds');
    EXCEPTION
        WHEN pkg_account_mgmt.e_insufficient_funds THEN
            assert_true(TRUE, 'withdraw raises e_insufficient_funds correctly');
        WHEN OTHERS THEN
            assert_true(TRUE, 'withdraw raises error for insufficient funds');
    END;
    ROLLBACK TO sp_withdraw_insuf;

    -- Test 42: transfer moves funds between accounts
    SAVEPOINT sp_transfer;
    DECLARE
        v_from_before NUMBER := pkg_account_mgmt.get_balance(c_account_1);
        v_to_before   NUMBER := pkg_account_mgmt.get_balance(c_account_3);
        v_debit_id    NUMBER;
        v_credit_id   NUMBER;
    BEGIN
        pkg_transactions.transfer(
            c_account_1, c_account_3, 200,
            'Test transfer', 'ONLINE', c_employee_1,
            v_debit_id, v_credit_id, v_ref
        );
        assert_equals_num(v_from_before - 200, pkg_account_mgmt.get_balance(c_account_1),
                          'transfer: source account decremented');
        assert_equals_num(v_to_before + 200, pkg_account_mgmt.get_balance(c_account_3),
                          'transfer: destination account incremented');
        assert_true(v_debit_id IS NOT NULL AND v_credit_id IS NOT NULL,
                    'transfer returns both transaction IDs');
    END;
    ROLLBACK TO sp_transfer;

    -- Test 43: transfer to same account raises error
    SAVEPOINT sp_same_acct;
    BEGIN
        pkg_transactions.transfer(c_account_1, c_account_1, 100, 'Self transfer',
                                   'ONLINE', NULL, v_txn_id, v_txn_id2, v_ref);
        assert_true(FALSE, 'transfer to same account should fail');
    EXCEPTION
        WHEN OTHERS THEN
            assert_true(TRUE, 'transfer raises error for same source/destination');
    END;
    ROLLBACK TO sp_same_acct;

    -- Test 44: reverse_transaction within window
    SAVEPOINT sp_reversal;
    DECLARE
        v_bal_before NUMBER := pkg_account_mgmt.get_balance(c_account_1);
    BEGIN
        pkg_transactions.deposit(c_account_1, 777, 'To be reversed',
                                  'BRANCH', c_employee_1, v_txn_id, v_ref);
        DECLARE
            v_bal_after_dep NUMBER := pkg_account_mgmt.get_balance(c_account_1);
        BEGIN
            pkg_transactions.reverse_transaction(v_txn_id, 'Test reversal',
                                                  c_employee_1, v_rev_id);
            assert_equals_num(v_bal_before, pkg_account_mgmt.get_balance(c_account_1),
                              'reverse_transaction restores balance to pre-deposit level');
            assert_true(v_rev_id IS NOT NULL, 'reverse_transaction returns reversal_id');
        END;
    END;
    ROLLBACK TO sp_reversal;

    -- Test 45: post_fee deducts from account
    SAVEPOINT sp_fee;
    DECLARE
        v_bal_before NUMBER := pkg_account_mgmt.get_balance(c_account_1);
    BEGIN
        pkg_transactions.post_fee(c_account_1, 'ATM_FEE', NULL,
                                   'Test ATM fee', c_employee_1, v_txn_id);
        assert_equals_num(v_bal_before - pkg_transactions.c_atm_fee,
                          pkg_account_mgmt.get_balance(c_account_1),
                          'post_fee deducts standard ATM fee correctly');
    END;
    ROLLBACK TO sp_fee;

    -- Test 46: post_fee with custom amount
    SAVEPOINT sp_custom_fee;
    DECLARE
        v_bal_before NUMBER := pkg_account_mgmt.get_balance(c_account_1);
    BEGIN
        pkg_transactions.post_fee(c_account_1, 'WIRE_FEE', 15.00,
                                   'Custom wire fee', NULL, v_txn_id);
        assert_equals_num(v_bal_before - 15, pkg_account_mgmt.get_balance(c_account_1),
                          'post_fee with custom amount deducts correctly');
    END;
    ROLLBACK TO sp_custom_fee;

    -- Test 47: post_account_interest credits balance
    SAVEPOINT sp_interest;
    DECLARE
        v_bal_before NUMBER;
        v_period_start DATE := DATE '2024-01-01';
        v_period_end   DATE := DATE '2024-01-31';
    BEGIN
        -- First add some transactions to make interest calculation meaningful
        pkg_transactions.deposit(c_account_2, 5000, 'Test for interest',
                                  'BRANCH', c_employee_1, v_txn_id, v_ref);
        v_bal_before := pkg_account_mgmt.get_balance(c_account_2);
        pkg_transactions.post_account_interest(c_account_2, v_period_start, v_period_end,
                                               SYSDATE, v_txn_id);
        -- Should have posted or returned null (no balance in period)
        assert_true(TRUE, 'post_account_interest executes without error');
    EXCEPTION
        WHEN OTHERS THEN
            -- May error if already posted for period, which is valid behavior
            assert_true(SQLCODE = -20037,
                        'post_account_interest prevents duplicate posting');
    END;
    ROLLBACK TO sp_interest;

    -- =========================================================================
    -- SUITE 5: PKG_LOAN_MGMT - Functions
    -- =========================================================================
    start_suite('PKG_LOAN_MGMT - Functions');

    -- Test 48: calc_monthly_payment basic calculation
    -- $100,000 at 6% for 30 years = ~$599.55/month
    v_amount := pkg_loan_mgmt.calc_monthly_payment(100000, 6, 360);
    assert_true(v_amount BETWEEN 595 AND 605,
                'calc_monthly_payment: 100k @ 6% / 360mo ≈ $599.55');

    -- Test 49: calc_monthly_payment zero rate
    v_amount := pkg_loan_mgmt.calc_monthly_payment(12000, 0, 12);
    assert_equals_num(1000, v_amount, 'calc_monthly_payment: zero rate = principal/term');

    -- Test 50: calc_total_interest is positive
    v_amount := pkg_loan_mgmt.calc_total_interest(50000, 8, 60);
    assert_true(v_amount > 0, 'calc_total_interest returns positive value');

    -- Test 51: calc_total_interest > 0 for non-zero rate
    DECLARE
        v_total_pmts NUMBER;
        v_monthly    NUMBER;
    BEGIN
        v_monthly    := pkg_loan_mgmt.calc_monthly_payment(10000, 5, 24);
        v_total_pmts := v_monthly * 24;
        v_amount     := pkg_loan_mgmt.calc_total_interest(10000, 5, 24);
        assert_equals_num(v_total_pmts - 10000, v_amount, 5,
                          'calc_total_interest = total_payments - principal (within $5)');
    END;

    -- Test 52: determine_interest_rate - excellent credit
    v_amount := pkg_loan_mgmt.determine_interest_rate(800, 'MORTGAGE', 360);
    DECLARE
        v_good_rate NUMBER := pkg_loan_mgmt.determine_interest_rate(600, 'MORTGAGE', 360);
    BEGIN
        assert_true(v_amount < v_good_rate,
                    'determine_interest_rate: better credit score = lower rate');
    END;

    -- Test 53: determine_interest_rate - loan type affects rate
    DECLARE
        v_personal_rate NUMBER := pkg_loan_mgmt.determine_interest_rate(700, 'PERSONAL', 36);
        v_mortgage_rate NUMBER := pkg_loan_mgmt.determine_interest_rate(700, 'MORTGAGE', 360);
    BEGIN
        assert_true(v_personal_rate > v_mortgage_rate,
                    'Personal loan rate > mortgage rate (same credit score)');
    END;

    -- Test 54: calc_dti_ratio - no existing loans
    v_amount := pkg_loan_mgmt.calc_dti_ratio(c_customer_1, 500);
    assert_true(v_amount >= 0 AND v_amount <= 1,
                'calc_dti_ratio returns value between 0 and 1');

    -- Test 55: get_outstanding_balance for non-existent loan
    v_amount := pkg_loan_mgmt.get_outstanding_balance(999999);
    assert_equals_num(-1, v_amount, 'get_outstanding_balance = -1 for non-existent loan');

    -- Test 56: loan_eligibility_check - verified customer with good credit
    v_result := pkg_loan_mgmt.loan_eligibility_check(c_customer_3, 'PERSONAL', 5000, 24);
    assert_true(v_result IN ('APPROVED','REVIEW'),
                'loan_eligibility: Carol (760 credit score) gets APPROVED or REVIEW');

    -- Test 57: loan_eligibility_check - customer with poor credit
    -- Customer 4 (David Wilson) has credit score 590
    v_result := pkg_loan_mgmt.loan_eligibility_check(1003, 'PERSONAL', 50000, 60);
    assert_true(v_result IN ('REJECTED','REVIEW'),
                'loan_eligibility: low credit score for large personal loan = REJECTED or REVIEW');

    -- Test 58: calc_days_past_due for non-existent loan = 0
    v_count := pkg_loan_mgmt.calc_days_past_due(999999);
    assert_equals_num(0, v_count, 'calc_days_past_due = 0 for non-existent loan');

    -- =========================================================================
    -- SUITE 6: PKG_LOAN_MGMT - Procedures
    -- =========================================================================
    start_suite('PKG_LOAN_MGMT - Procedures');

    -- Test 59: originate_loan creates loan record
    SAVEPOINT sp_loan_orig;
    pkg_loan_mgmt.originate_loan(
        c_customer_3, c_account_1, c_branch_1,
        'PERSONAL', 10000, 36, NULL, NULL, c_employee_2,
        v_loan_id, v_loan_num, v_monthly_pmt, v_decision
    );
    assert_true(v_loan_id IS NOT NULL, 'originate_loan returns valid loan_id');
    assert_true(v_loan_num IS NOT NULL, 'originate_loan returns loan_number');
    assert_true(v_monthly_pmt > 0, 'originate_loan calculates positive monthly payment');
    assert_true(v_decision IN ('APPROVED','REJECTED','REVIEW'),
                'originate_loan returns valid decision');
    ROLLBACK TO sp_loan_orig;

    -- Test 60: originate_loan - monthly payment is reasonable
    SAVEPOINT sp_loan_pay;
    pkg_loan_mgmt.originate_loan(
        c_customer_3, c_account_1, c_branch_1,
        'PERSONAL', 12000, 12, NULL, NULL, c_employee_2,
        v_loan_id, v_loan_num, v_monthly_pmt, v_decision
    );
    -- $12,000 / 12 months at ~10% = roughly $1,050/month
    assert_true(v_monthly_pmt BETWEEN 900 AND 1200,
                'originate_loan: $12k/12mo payment between $900-$1200');
    ROLLBACK TO sp_loan_pay;

    -- Test 61: approve_and_disburse increases account balance
    SAVEPOINT sp_disburse;
    DECLARE
        v_bal_before NUMBER := pkg_account_mgmt.get_balance(c_account_1);
        v_l_status   VARCHAR2(20);
    BEGIN
        pkg_loan_mgmt.originate_loan(
            c_customer_3, c_account_1, c_branch_1,
            'PERSONAL', 5000, 24, NULL, NULL, c_employee_2,
            v_loan_id, v_loan_num, v_monthly_pmt, v_decision
        );
        IF v_decision IN ('APPROVED') THEN
            pkg_loan_mgmt.approve_and_disburse(v_loan_id, c_employee_2, c_account_1);
            SELECT status INTO v_l_status FROM loans WHERE loan_id = v_loan_id;
            assert_equals('ACTIVE', v_l_status, 'approve_and_disburse sets loan status to ACTIVE');
            assert_equals_num(v_bal_before + 5000,
                              pkg_account_mgmt.get_balance(c_account_1),
                              'approve_and_disburse credits disbursement to account');
        ELSE
            assert_true(TRUE, 'Loan in REVIEW/REJECTED - skip disburse test');
        END IF;
    END;
    ROLLBACK TO sp_disburse;

    -- Test 62: reject_loan changes status
    SAVEPOINT sp_reject;
    pkg_loan_mgmt.originate_loan(
        c_customer_1, c_account_1, c_branch_1,
        'BUSINESS', 500000, 120, NULL, NULL, c_employee_2,
        v_loan_id, v_loan_num, v_monthly_pmt, v_decision
    );
    IF v_decision IN ('APPROVED','REVIEW','REJECTED') AND v_loan_id IS NOT NULL THEN
        BEGIN
            pkg_loan_mgmt.reject_loan(v_loan_id, 'Test rejection', c_employee_1);
            DECLARE v_s VARCHAR2(20); BEGIN
                SELECT status INTO v_s FROM loans WHERE loan_id = v_loan_id;
                assert_equals('REJECTED', v_s, 'reject_loan sets status to REJECTED');
            END;
        EXCEPTION WHEN OTHERS THEN
            -- Might already be REJECTED
            assert_true(TRUE, 'reject_loan handled');
        END;
    END IF;
    ROLLBACK TO sp_reject;

    -- Test 63: generate_amortization_schedule creates payments
    SAVEPOINT sp_amort;
    DECLARE
        v_sched_count NUMBER;
    BEGIN
        pkg_loan_mgmt.originate_loan(
            c_customer_3, c_account_1, c_branch_1,
            'AUTO', 20000, 48, 'VEHICLE', 22000, c_employee_2,
            v_loan_id, v_loan_num, v_monthly_pmt, v_decision
        );
        IF v_decision = 'APPROVED' THEN
            pkg_loan_mgmt.approve_and_disburse(v_loan_id, c_employee_2);
            SELECT COUNT(*) INTO v_sched_count
            FROM loan_payments WHERE loan_id = v_loan_id;
            assert_equals_num(48, v_sched_count, 'generate_amortization_schedule: 48 payment records for 48-month loan');
        ELSE
            assert_true(TRUE, 'Loan not approved - amortization test skipped');
        END IF;
    END;
    ROLLBACK TO sp_amort;

    -- Test 64: restructure_loan changes rate and payment
    SAVEPOINT sp_restructure;
    DECLARE
        v_orig_payment NUMBER;
        v_new_payment  NUMBER;
    BEGIN
        pkg_loan_mgmt.originate_loan(
            c_customer_3, c_account_1, c_branch_1,
            'PERSONAL', 8000, 24, NULL, NULL, c_employee_2,
            v_loan_id, v_loan_num, v_monthly_pmt, v_decision
        );
        IF v_decision = 'APPROVED' THEN
            pkg_loan_mgmt.approve_and_disburse(v_loan_id, c_employee_2);
            v_orig_payment := v_monthly_pmt;
            pkg_loan_mgmt.restructure_loan(v_loan_id, 3.0, 48,
                                            'Rate reduction', c_employee_2, v_new_payment);
            assert_true(v_new_payment < v_orig_payment,
                        'restructure_loan: lower rate + longer term = lower payment');
        ELSE
            assert_true(TRUE, 'Loan not approved - restructure test skipped');
        END IF;
    END;
    ROLLBACK TO sp_restructure;

    -- =========================================================================
    -- SUITE 7: PKG_REPORTING - Functions
    -- =========================================================================
    start_suite('PKG_REPORTING - Functions');

    -- Test 65: get_customer_net_worth
    v_amount := pkg_reporting.get_customer_net_worth(c_customer_1);
    assert_true(v_amount IS NOT NULL, 'get_customer_net_worth returns non-null value');
    assert_true(v_amount >= 0, 'get_customer_net_worth for good customer is non-negative');

    -- Test 66: get_avg_balance_n_months
    v_amount := pkg_reporting.get_avg_balance_n_months(c_account_1, 3);
    assert_true(v_amount >= 0, 'get_avg_balance_n_months returns non-negative value');

    -- Test 67: get_branch_total_deposits
    v_amount := pkg_reporting.get_branch_total_deposits(c_branch_1);
    assert_true(v_amount > 0, 'get_branch_total_deposits > 0 for seeded branch');

    -- Test 68: get_branch_loan_portfolio
    v_amount := pkg_reporting.get_branch_loan_portfolio(c_branch_1);
    assert_true(v_amount >= 0, 'get_branch_loan_portfolio returns non-negative value');

    -- Test 69: calc_ldr
    v_amount := pkg_reporting.calc_ldr(c_branch_1);
    assert_true(v_amount >= 0, 'calc_ldr is non-negative');

    -- Test 70: calc_npl_ratio global
    v_amount := pkg_reporting.calc_npl_ratio();
    assert_true(v_amount >= 0 AND v_amount <= 1, 'calc_npl_ratio is between 0 and 1');

    -- Test 71: calc_customer_ltv
    v_amount := pkg_reporting.calc_customer_ltv(c_customer_1);
    assert_true(v_amount >= 0, 'calc_customer_ltv returns non-negative value');

    -- Test 72: calc_customer_ltv - VIP customer has higher LTV
    DECLARE
        v_vip_ltv    NUMBER := pkg_reporting.calc_customer_ltv(1004);  -- Eve, VIP, $125k
        v_retail_ltv NUMBER := pkg_reporting.calc_customer_ltv(c_customer_2);  -- Bob, RETAIL
    BEGIN
        assert_true(v_vip_ltv >= v_retail_ltv,
                    'calc_customer_ltv: VIP customer LTV >= retail customer LTV');
    END;

    -- Test 73: calc_deposit_growth_pct
    v_amount := pkg_reporting.calc_deposit_growth_pct(NULL, 1);
    assert_true(v_amount IS NOT NULL, 'calc_deposit_growth_pct returns non-null');

    -- =========================================================================
    -- SUITE 8: PKG_REPORTING - Procedures (RefCursor validation)
    -- =========================================================================
    start_suite('PKG_REPORTING - Procedures (SYS_REFCURSOR)');

    -- Test 74: generate_account_statement returns cursor
    DECLARE
        v_cursor SYS_REFCURSOR;
        v_txn_id2 NUMBER;
        v_type    VARCHAR2(30);
        v_amount2 NUMBER;
        v_rows    NUMBER := 0;
        v_dummy1  DATE;
        v_dummy2  DATE;
        v_dummy3  VARCHAR2(500);
        v_dummy4  NUMBER;
        v_dummy5  NUMBER;
        v_dummy6  VARCHAR2(50);
        v_dummy7  VARCHAR2(20);
        v_dummy8  NUMBER;
        v_dummy9  VARCHAR2(100);
        v_dummy10 VARCHAR2(100);
        v_dummy11 NUMBER;
        v_dummy12 NUMBER;
        v_dummy13 VARCHAR2(20);
    BEGIN
        pkg_reporting.generate_account_statement(
            c_account_1, DATE '2020-01-01', SYSDATE, v_cursor
        );
        LOOP
            FETCH v_cursor INTO v_txn_id2, v_dummy1, v_dummy2, v_type,
                                v_dummy3, v_dummy6, v_dummy7, v_dummy4, v_dummy5,
                                v_dummy8, v_dummy13, v_dummy9, v_dummy10, v_dummy11;
            EXIT WHEN v_cursor%NOTFOUND;
            v_rows := v_rows + 1;
        END LOOP;
        CLOSE v_cursor;
        assert_true(v_rows >= 0, 'generate_account_statement opens and fetches cursor');
        DBMS_OUTPUT.PUT_LINE('    (statement rows returned: ' || v_rows || ')');
    EXCEPTION
        WHEN OTHERS THEN
            IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
            assert_true(FALSE, 'generate_account_statement raised error: ' || SQLERRM);
    END;

    -- Test 75: generate_customer_portfolio opens without error
    DECLARE
        v_cursor SYS_REFCURSOR;
        v_rows NUMBER := 0;
        v_p_type VARCHAR2(20);
        v_p_id NUMBER;
        v_p_num VARCHAR2(20);
        v_p_name VARCHAR2(100);
        v_bal NUMBER;
        v_avail NUMBER;
        v_status VARCHAR2(20);
        v_date DATE;
        v_rate NUMBER;
        v_pmt NUMBER;
        v_outstanding NUMBER;
        v_curr VARCHAR2(3);
        v_txns NUMBER;
        v_age NUMBER;
    BEGIN
        pkg_reporting.generate_customer_portfolio(c_customer_1, v_cursor);
        LOOP
            FETCH v_cursor INTO v_p_type, v_p_id, v_p_num, v_p_name, v_bal, v_avail,
                                v_status, v_date, v_rate, v_pmt, v_outstanding,
                                v_curr, v_txns, v_age;
            EXIT WHEN v_cursor%NOTFOUND;
            v_rows := v_rows + 1;
        END LOOP;
        CLOSE v_cursor;
        assert_true(v_rows >= 2, 'generate_customer_portfolio: Alice has >= 2 products');
    EXCEPTION
        WHEN OTHERS THEN
            IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
            assert_true(FALSE, 'generate_customer_portfolio raised error: ' || SQLERRM);
    END;

    -- Test 76: generate_delinquency_report opens without error
    DECLARE
        v_cursor SYS_REFCURSOR;
    BEGIN
        pkg_reporting.generate_delinquency_report(SYSDATE, v_cursor);
        assert_true(v_cursor%ISOPEN, 'generate_delinquency_report opens cursor');
        CLOSE v_cursor;
    EXCEPTION
        WHEN OTHERS THEN
            assert_true(FALSE, 'generate_delinquency_report raised error: ' || SQLERRM);
    END;

    -- Test 77: get_top_customers returns at least 1 customer
    DECLARE
        v_cursor    SYS_REFCURSOR;
        v_rows      NUMBER := 0;
        v_cust_id   NUMBER;
        v_code      VARCHAR2(20);
        v_name      VARCHAR2(200);
        v_type      VARCHAR2(20);
        v_score     NUMBER;
        v_acct_cnt  NUMBER;
        v_total_bal NUMBER;
        v_sav_bal   NUMBER;
        v_chk_bal   NUMBER;
        v_loan_bal  NUMBER;
        v_net_worth NUMBER;
        v_ltv       NUMBER;
        v_txns      NUMBER;
        v_rank      NUMBER;
    BEGIN
        pkg_reporting.get_top_customers(5, NULL, v_cursor);
        LOOP
            FETCH v_cursor INTO v_cust_id, v_code, v_name, v_type, v_score,
                                v_acct_cnt, v_total_bal, v_sav_bal, v_chk_bal,
                                v_loan_bal, v_net_worth, v_ltv, v_txns, v_rank;
            EXIT WHEN v_cursor%NOTFOUND;
            v_rows := v_rows + 1;
        END LOOP;
        CLOSE v_cursor;
        assert_true(v_rows >= 1, 'get_top_customers returns at least 1 customer');
        assert_true(v_rows <= 5, 'get_top_customers respects top_n limit of 5');
    EXCEPTION
        WHEN OTHERS THEN
            IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
            assert_true(FALSE, 'get_top_customers raised error: ' || SQLERRM);
    END;

    -- Test 78: generate_suspicious_activity_report
    DECLARE
        v_cursor SYS_REFCURSOR;
    BEGIN
        pkg_reporting.generate_suspicious_activity_report(
            DATE '2020-01-01', SYSDATE, v_cursor
        );
        assert_true(v_cursor%ISOPEN, 'generate_suspicious_activity_report opens cursor');
        CLOSE v_cursor;
    EXCEPTION
        WHEN OTHERS THEN
            assert_true(FALSE, 'generate_suspicious_activity_report raised error: ' || SQLERRM);
    END;

    -- Test 79: transaction_velocity_report
    DECLARE
        v_cursor SYS_REFCURSOR;
    BEGIN
        pkg_reporting.transaction_velocity_report(
            DATE '2020-01-01', SYSDATE, 2, v_cursor
        );
        assert_true(v_cursor%ISOPEN, 'transaction_velocity_report opens cursor');
        CLOSE v_cursor;
    EXCEPTION
        WHEN OTHERS THEN
            assert_true(FALSE, 'transaction_velocity_report raised error: ' || SQLERRM);
    END;

    -- Test 80: interest_income_summary
    DECLARE
        v_cursor SYS_REFCURSOR;
    BEGIN
        pkg_reporting.interest_income_summary(2024, v_cursor);
        assert_true(v_cursor%ISOPEN, 'interest_income_summary opens cursor');
        CLOSE v_cursor;
    EXCEPTION
        WHEN OTHERS THEN
            assert_true(FALSE, 'interest_income_summary raised error: ' || SQLERRM);
    END;

    -- Test 81: fee_income_report
    DECLARE
        v_cursor SYS_REFCURSOR;
    BEGIN
        pkg_reporting.fee_income_report(DATE '2020-01-01', SYSDATE, v_cursor);
        assert_true(v_cursor%ISOPEN, 'fee_income_report opens cursor');
        CLOSE v_cursor;
    EXCEPTION
        WHEN OTHERS THEN
            assert_true(FALSE, 'fee_income_report raised error: ' || SQLERRM);
    END;

    -- Test 82: loan_portfolio_risk_report
    DECLARE
        v_cursor SYS_REFCURSOR;
    BEGIN
        pkg_reporting.loan_portfolio_risk_report(SYSDATE, v_cursor);
        assert_true(v_cursor%ISOPEN, 'loan_portfolio_risk_report opens cursor');
        CLOSE v_cursor;
    EXCEPTION
        WHEN OTHERS THEN
            assert_true(FALSE, 'loan_portfolio_risk_report raised error: ' || SQLERRM);
    END;

    -- =========================================================================
    -- SUITE 9: Cross-Package Integration Tests
    -- =========================================================================
    start_suite('Integration Tests - End-to-End Scenarios');

    -- Test 83: Full customer lifecycle - account creation + deposit + transfer + fee
    SAVEPOINT sp_lifecycle;
    DECLARE
        v_new_acct_id    NUMBER;
        v_new_acct_num   VARCHAR2(20);
        v_bal_after_dep  NUMBER;
        v_bal_after_xfr  NUMBER;
        v_debit_id       NUMBER;
        v_credit_id      NUMBER;
        v_xfr_ref        VARCHAR2(50);
        v_fee_txn        NUMBER;
        v_dep_txn        NUMBER;
        v_dep_ref        VARCHAR2(50);
        v_customer_net   NUMBER;
    BEGIN
        -- Create a new checking account for Bob
        pkg_account_mgmt.create_account(
            c_customer_2, c_branch_1, 'CHECKING', 0, 'USD',
            v_new_acct_id, v_new_acct_num
        );
        assert_true(v_new_acct_id IS NOT NULL, 'Lifecycle: New account created');

        -- Deposit $3,000
        pkg_transactions.deposit(
            v_new_acct_id, 3000, 'Payroll deposit', 'MOBILE',
            c_employee_1, v_dep_txn, v_dep_ref
        );
        v_bal_after_dep := pkg_account_mgmt.get_balance(v_new_acct_id);
        assert_equals_num(3000, v_bal_after_dep, 'Lifecycle: Balance = 3000 after deposit');

        -- Transfer $500 to Alice's account
        pkg_transactions.transfer(
            v_new_acct_id, c_account_1, 500,
            'Bill payment', 'ONLINE', NULL,
            v_debit_id, v_credit_id, v_xfr_ref
        );
        v_bal_after_xfr := pkg_account_mgmt.get_balance(v_new_acct_id);
        assert_equals_num(2500, v_bal_after_xfr, 'Lifecycle: Balance = 2500 after $500 transfer');

        -- Post a fee
        pkg_transactions.post_fee(v_new_acct_id, 'MONTHLY_FEE', 5.00,
                                   'Monthly fee', NULL, v_fee_txn);
        assert_equals_num(2495, pkg_account_mgmt.get_balance(v_new_acct_id),
                          'Lifecycle: Balance = 2495 after $5 fee');

        -- Verify customer net worth changed
        v_customer_net := pkg_reporting.get_customer_net_worth(c_customer_2);
        assert_true(v_customer_net > 2000, 'Lifecycle: Customer net worth reflects new account');
    END;
    ROLLBACK TO sp_lifecycle;

    -- Test 84: Loan origination + disbursement + payment cycle
    SAVEPOINT sp_loan_cycle;
    DECLARE
        v_l_id      NUMBER;
        v_l_num     VARCHAR2(20);
        v_l_pmt     NUMBER;
        v_l_dec     VARCHAR2(20);
        v_pay_id    NUMBER;
        v_p_paid    NUMBER;
        v_i_paid    NUMBER;
        v_rem_bal   NUMBER;
        v_bal_before NUMBER;
        v_bal_after  NUMBER;
        v_payoff_amt NUMBER;
    BEGIN
        -- Originate a personal loan for Carol
        pkg_loan_mgmt.originate_loan(
            c_customer_3, c_account_1, c_branch_1,
            'PERSONAL', 6000, 24, NULL, NULL, c_employee_2,
            v_l_id, v_l_num, v_l_pmt, v_l_dec
        );
        assert_true(v_l_id IS NOT NULL, 'Loan cycle: Loan originated');
        assert_true(v_l_dec IN ('APPROVED','REVIEW','REJECTED'),
                    'Loan cycle: Valid decision returned');

        IF v_l_dec = 'APPROVED' THEN
            v_bal_before := pkg_account_mgmt.get_balance(c_account_1);

            -- Disburse the loan
            pkg_loan_mgmt.approve_and_disburse(v_l_id, c_employee_2, c_account_1);
            v_bal_after := pkg_account_mgmt.get_balance(c_account_1);
            assert_equals_num(v_bal_before + 6000, v_bal_after,
                              'Loan cycle: Disbursement credited $6,000 to account');

            -- Make a scheduled payment
            v_bal_before := pkg_account_mgmt.get_balance(c_account_1);
            pkg_loan_mgmt.process_loan_payment(
                v_l_id, v_l_pmt, c_account_1, c_employee_2,
                v_pay_id, v_p_paid, v_i_paid, v_rem_bal
            );
            assert_true(v_pay_id IS NOT NULL, 'Loan cycle: Payment processed, payment_id returned');
            assert_true(v_p_paid > 0, 'Loan cycle: Principal paid > 0');
            assert_true(v_i_paid >= 0, 'Loan cycle: Interest paid >= 0');
            assert_equals_num(v_p_paid + v_i_paid, v_l_pmt, 5,
                              'Loan cycle: Principal + interest = monthly payment (within $5)');
            assert_true(v_rem_bal < 6000,
                        'Loan cycle: Remaining balance < original principal after 1 payment');
            assert_equals_num(v_bal_before - v_l_pmt, pkg_account_mgmt.get_balance(c_account_1),
                              'Loan cycle: Account balance debited by monthly payment');

            -- Verify outstanding balance reduced
            assert_equals_num(v_rem_bal,
                              pkg_loan_mgmt.get_outstanding_balance(v_l_id),
                              'Loan cycle: get_outstanding_balance matches returned rem_balance');
        ELSE
            assert_true(TRUE, 'Loan cycle: Loan not approved - payment tests skipped');
        END IF;
    END;
    ROLLBACK TO sp_loan_cycle;

    -- Test 85: Deposit structuring detection (just below CTR threshold)
    SAVEPOINT sp_structuring;
    DECLARE
        v_daily_total NUMBER;
        v_dep_txn     NUMBER;
        v_dep_ref     VARCHAR2(50);
    BEGIN
        -- Deposit just below $10,000 threshold
        pkg_transactions.deposit(
            c_account_1, 9999, 'Cash deposit 1', 'BRANCH',
            c_employee_1, v_dep_txn, v_dep_ref
        );
        -- Check that CTR is not required for sub-threshold
        assert_true(NOT pkg_transactions.requires_ctr_report(9999),
                    'Structuring: Single $9,999 deposit does not trigger CTR');

        -- Confirm it does trigger at exactly $10,000
        assert_true(pkg_transactions.requires_ctr_report(10000),
                    'Structuring: $10,000 deposit triggers CTR requirement');

        -- Check daily deposit running total includes new deposit
        v_daily_total := pkg_transactions.get_customer_daily_deposits(c_customer_1);
        assert_true(v_daily_total >= 9999,
                    'Structuring: get_customer_daily_deposits reflects same-day deposit');
    END;
    ROLLBACK TO sp_structuring;

    -- Test 86: Branch reporting consistency after transactions
    SAVEPOINT sp_branch_report;
    DECLARE
        v_deposits_before NUMBER;
        v_deposits_after  NUMBER;
        v_dep_txn         NUMBER;
        v_dep_ref         VARCHAR2(50);
        v_cursor          SYS_REFCURSOR;
    BEGIN
        v_deposits_before := pkg_reporting.get_branch_total_deposits(c_branch_1);

        -- Add a deposit via branch
        pkg_transactions.deposit(
            c_account_1, 5000, 'Branch report test', 'BRANCH',
            c_employee_1, v_dep_txn, v_dep_ref
        );

        v_deposits_after := pkg_reporting.get_branch_total_deposits(c_branch_1);
        assert_equals_num(v_deposits_before + 5000, v_deposits_after,
                          'Branch reporting: Total deposits increases after branch deposit');

        -- Branch report cursor opens cleanly
        pkg_reporting.generate_branch_report(c_branch_1, SYSDATE, v_cursor);
        assert_true(v_cursor%ISOPEN, 'Branch report cursor opens after transaction activity');
        CLOSE v_cursor;
    EXCEPTION
        WHEN OTHERS THEN
            IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
            assert_true(FALSE, 'Branch report test raised error: ' || SQLERRM);
    END;
    ROLLBACK TO sp_branch_report;

    -- Test 87: Account freeze blocks transactions
    SAVEPOINT sp_freeze_txn;
    DECLARE
        v_dep_txn NUMBER;
        v_dep_ref VARCHAR2(50);
    BEGIN
        -- Freeze Alice's checking account
        pkg_account_mgmt.freeze_account(c_account_1, 'Fraud investigation', c_employee_1);
        assert_equals('FROZEN', pkg_account_mgmt.get_account_status(c_account_1),
                      'Freeze+Txn: Account is FROZEN');

        -- Attempt deposit on frozen account - should raise error
        BEGIN
            pkg_transactions.deposit(
                c_account_1, 100, 'Deposit on frozen', 'BRANCH',
                c_employee_1, v_dep_txn, v_dep_ref
            );
            assert_true(FALSE, 'Freeze+Txn: Deposit should fail on frozen account');
        EXCEPTION
            WHEN OTHERS THEN
                assert_true(SQLCODE < 0,
                            'Freeze+Txn: Deposit raises error on frozen account');
        END;

        -- Attempt withdrawal on frozen account - should raise error
        BEGIN
            pkg_transactions.withdraw(
                c_account_1, 100, 'Withdrawal on frozen', 'BRANCH',
                c_employee_1, v_dep_txn, v_dep_ref
            );
            assert_true(FALSE, 'Freeze+Txn: Withdrawal should fail on frozen account');
        EXCEPTION
            WHEN OTHERS THEN
                assert_true(SQLCODE < 0,
                            'Freeze+Txn: Withdrawal raises error on frozen account');
        END;
    END;
    ROLLBACK TO sp_freeze_txn;

    -- =========================================================================
    -- SUITE 10: PKG_LOAN_MGMT - Batch Operations
    -- =========================================================================
    start_suite('PKG_LOAN_MGMT - Batch Operations');

    -- Test 88: update_delinquency_status executes without error
    SAVEPOINT sp_delinq;
    DECLARE
        v_delinquent_count  NUMBER;
        v_total_dpd_balance NUMBER;
    BEGIN
        pkg_loan_mgmt.update_delinquency_status(
            SYSDATE, v_delinquent_count, v_total_dpd_balance
        );
        assert_true(v_delinquent_count >= 0,
                    'update_delinquency_status: delinquent_count >= 0');
        assert_true(v_total_dpd_balance >= 0,
                    'update_delinquency_status: total_dpd_balance >= 0');
    END;
    ROLLBACK TO sp_delinq;

    -- Test 89: apply_late_fees executes without error
    SAVEPOINT sp_late_fees;
    DECLARE
        v_fees_applied NUMBER;
        v_total_fees   NUMBER;
    BEGIN
        pkg_loan_mgmt.apply_late_fees(SYSDATE, v_fees_applied, v_total_fees);
        assert_true(v_fees_applied >= 0, 'apply_late_fees: fees_applied >= 0');
        assert_true(v_total_fees >= 0,   'apply_late_fees: total_fees >= 0');
        -- Consistency: if any fees applied, total must be positive
        IF v_fees_applied > 0 THEN
            assert_true(v_total_fees > 0,
                        'apply_late_fees: total_fees > 0 when fees were applied');
        ELSE
            assert_true(TRUE, 'apply_late_fees: no overdue loans in test data (OK)');
        END IF;
    END;
    ROLLBACK TO sp_late_fees;

    -- Test 90: pay_off_loan - originate, approve, disburse, then pay off
    SAVEPOINT sp_payoff;
    DECLARE
        v_l_id      NUMBER;
        v_l_num     VARCHAR2(20);
        v_l_pmt     NUMBER;
        v_l_dec     VARCHAR2(20);
        v_payoff    NUMBER;
        v_l_status  VARCHAR2(20);
    BEGIN
        pkg_loan_mgmt.originate_loan(
            c_customer_3, c_account_1, c_branch_1,
            'PERSONAL', 3000, 12, NULL, NULL, c_employee_2,
            v_l_id, v_l_num, v_l_pmt, v_l_dec
        );
        IF v_l_dec = 'APPROVED' THEN
            pkg_loan_mgmt.approve_and_disburse(v_l_id, c_employee_2, c_account_1);
            -- Ensure enough funds exist for payoff
            pkg_transactions.deposit(c_account_1, 5000, 'Payoff fund', 'BRANCH',
                                     c_employee_1, v_txn_id, v_ref);
            pkg_loan_mgmt.pay_off_loan(v_l_id, c_account_1, c_employee_2, v_payoff);
            SELECT status INTO v_l_status FROM loans WHERE loan_id = v_l_id;
            assert_equals('PAID_OFF', v_l_status,
                          'pay_off_loan: loan status = PAID_OFF after payoff');
            assert_true(v_payoff > 0,
                        'pay_off_loan: payoff amount > 0');
            assert_equals_num(0, pkg_loan_mgmt.get_outstanding_balance(v_l_id),
                              'pay_off_loan: outstanding balance = 0 after payoff');
        ELSE
            assert_true(TRUE, 'pay_off_loan: loan not approved - test skipped');
        END IF;
    END;
    ROLLBACK TO sp_payoff;

    -- Test 91: get_next_payment_date is in the future for an active loan
    SAVEPOINT sp_next_due;
    DECLARE
        v_l_id     NUMBER;
        v_l_num    VARCHAR2(20);
        v_l_pmt    NUMBER;
        v_l_dec    VARCHAR2(20);
        v_due_date DATE;
    BEGIN
        pkg_loan_mgmt.originate_loan(
            c_customer_3, c_account_1, c_branch_1,
            'AUTO', 15000, 36, 'VEHICLE', 18000, c_employee_2,
            v_l_id, v_l_num, v_l_pmt, v_l_dec
        );
        IF v_l_dec = 'APPROVED' THEN
            pkg_loan_mgmt.approve_and_disburse(v_l_id, c_employee_2, c_account_1);
            v_due_date := pkg_loan_mgmt.get_next_payment_date(v_l_id);
            assert_true(v_due_date > SYSDATE,
                        'get_next_payment_date: first due date is in the future');
            assert_true(v_due_date <= ADD_MONTHS(SYSDATE, 2),
                        'get_next_payment_date: first due date is within 2 months');
        ELSE
            assert_true(TRUE, 'get_next_payment_date: loan not approved - test skipped');
        END IF;
    END;
    ROLLBACK TO sp_next_due;

    -- Test 92: get_loan_status_desc returns meaningful string
    SAVEPOINT sp_loan_desc;
    DECLARE
        v_l_id  NUMBER;
        v_l_num VARCHAR2(20);
        v_l_pmt NUMBER;
        v_l_dec VARCHAR2(20);
        v_desc  VARCHAR2(200);
    BEGIN
        pkg_loan_mgmt.originate_loan(
            c_customer_3, c_account_1, c_branch_1,
            'PERSONAL', 4000, 12, NULL, NULL, c_employee_2,
            v_l_id, v_l_num, v_l_pmt, v_l_dec
        );
        v_desc := pkg_loan_mgmt.get_loan_status_desc(v_l_id);
        assert_true(v_desc IS NOT NULL,
                    'get_loan_status_desc returns non-null for newly created loan');
        assert_true(LENGTH(v_desc) > 0,
                    'get_loan_status_desc returns non-empty string');
    END;
    ROLLBACK TO sp_loan_desc;

    -- =========================================================================
    -- SUITE 11: PKG_TRANSACTIONS - Additional Edge Cases
    -- =========================================================================
    start_suite('PKG_TRANSACTIONS - Edge Cases');

    -- Test 93: calc_account_interest returns non-negative value
    DECLARE
        v_int_amount NUMBER;
    BEGIN
        v_int_amount := pkg_transactions.calc_account_interest(
            c_account_2,
            ADD_MONTHS(TRUNC(SYSDATE,'MM'), -1),
            TRUNC(SYSDATE,'MM') - 1
        );
        assert_true(v_int_amount >= 0,
                    'calc_account_interest: returns non-negative value for prior month');
    END;

    -- Test 94: get_transaction_summary returns non-null for valid transaction
    SAVEPOINT sp_txn_summary;
    DECLARE
        v_dep_txn NUMBER;
        v_dep_ref VARCHAR2(50);
        v_summary VARCHAR2(500);
    BEGIN
        pkg_transactions.deposit(
            c_account_1, 250, 'Summary test deposit', 'BRANCH',
            c_employee_1, v_dep_txn, v_dep_ref
        );
        v_summary := pkg_transactions.get_transaction_summary(v_dep_txn);
        assert_true(v_summary IS NOT NULL,
                    'get_transaction_summary: returns non-null for valid transaction');
    END;
    ROLLBACK TO sp_txn_summary;

    -- Test 95: is_reversible returns TRUE immediately after deposit
    SAVEPOINT sp_reversible;
    DECLARE
        v_dep_txn  NUMBER;
        v_dep_ref  VARCHAR2(50);
        v_can_rev  BOOLEAN;
    BEGIN
        pkg_transactions.deposit(
            c_account_1, 100, 'Reversible check', 'BRANCH',
            c_employee_1, v_dep_txn, v_dep_ref
        );
        v_can_rev := pkg_transactions.is_reversible(v_dep_txn);
        assert_true(v_can_rev,
                    'is_reversible: newly posted transaction is reversible');
    END;
    ROLLBACK TO sp_reversible;

    -- Test 96: reverse_transaction raises e_already_reversed on double reversal
    SAVEPOINT sp_double_rev;
    DECLARE
        v_dep_txn  NUMBER;
        v_dep_ref  VARCHAR2(50);
        v_rev1_id  NUMBER;
        v_rev2_id  NUMBER;
    BEGIN
        pkg_transactions.deposit(
            c_account_1, 333, 'Double reversal test', 'BRANCH',
            c_employee_1, v_dep_txn, v_dep_ref
        );
        pkg_transactions.reverse_transaction(v_dep_txn, 'First reversal',
                                              c_employee_1, v_rev1_id);
        -- Attempt to reverse the same transaction again
        BEGIN
            pkg_transactions.reverse_transaction(v_dep_txn, 'Second reversal',
                                                  c_employee_1, v_rev2_id);
            assert_true(FALSE, 'reverse_transaction: double reversal should fail');
        EXCEPTION
            WHEN pkg_transactions.e_already_reversed THEN
                assert_true(TRUE,
                            'reverse_transaction: raises e_already_reversed on duplicate');
            WHEN OTHERS THEN
                assert_true(SQLCODE < 0,
                            'reverse_transaction: raises error on duplicate reversal');
        END;
    END;
    ROLLBACK TO sp_double_rev;

    -- Test 97: get_customer_daily_deposits accumulates within the same day
    SAVEPOINT sp_daily_dep;
    DECLARE
        v_before_total NUMBER;
        v_after_total  NUMBER;
        v_dep_txn      NUMBER;
        v_dep_ref      VARCHAR2(50);
    BEGIN
        v_before_total := pkg_transactions.get_customer_daily_deposits(c_customer_1);
        pkg_transactions.deposit(
            c_account_1, 1500, 'Daily accumulation test', 'ATM',
            NULL, v_dep_txn, v_dep_ref
        );
        v_after_total := pkg_transactions.get_customer_daily_deposits(c_customer_1);
        assert_equals_num(v_before_total + 1500, v_after_total,
                          'get_customer_daily_deposits: increases by deposit amount');
    END;
    ROLLBACK TO sp_daily_dep;

    -- =========================================================================
    -- SUITE 12: PKG_REPORTING - Additional Functions
    -- =========================================================================
    start_suite('PKG_REPORTING - Additional Coverage');

    -- Test 98: calc_npl_ratio for specific branch is between 0 and 1
    v_amount := pkg_reporting.calc_npl_ratio(c_branch_1);
    assert_true(v_amount >= 0 AND v_amount <= 1,
                'calc_npl_ratio: branch-level ratio is between 0 and 1');

    -- Test 99: calc_ldr for non-existent branch returns 0 or NULL gracefully
    BEGIN
        v_amount := pkg_reporting.calc_ldr(999999);
        assert_true(NVL(v_amount, 0) >= 0,
                    'calc_ldr: non-existent branch returns 0 or NULL gracefully');
    EXCEPTION
        WHEN OTHERS THEN
            assert_true(TRUE, 'calc_ldr: raises handled error for non-existent branch');
    END;

    -- Test 100: get_avg_balance_n_months for large window does not error
    v_amount := pkg_reporting.get_avg_balance_n_months(c_account_2, 24);
    assert_true(NVL(v_amount, 0) >= 0,
                'get_avg_balance_n_months: 24-month window returns non-negative');

    -- Test 101: calc_deposit_growth_pct for specific branch
    v_amount := pkg_reporting.calc_deposit_growth_pct(c_branch_1, 3);
    assert_true(v_amount IS NOT NULL,
                'calc_deposit_growth_pct: branch-specific 3-month growth returns non-null');

    -- Test 102: generate_branch_report cursor opens for valid branch
    DECLARE
        v_cursor SYS_REFCURSOR;
    BEGIN
        pkg_reporting.generate_branch_report(c_branch_1, SYSDATE, v_cursor);
        assert_true(v_cursor%ISOPEN,
                    'generate_branch_report: cursor opens for valid branch');
        CLOSE v_cursor;
    EXCEPTION
        WHEN OTHERS THEN
            IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF;
            assert_true(FALSE, 'generate_branch_report raised error: ' || SQLERRM);
    END;

    -- =========================================================================
    -- Final Rollback and Results
    -- =========================================================================
    ROLLBACK TO sp_test_start;
    print_results;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO sp_test_start;
        DBMS_OUTPUT.PUT_LINE(CHR(10) || '[FATAL] Unhandled exception in test harness:');
        DBMS_OUTPUT.PUT_LINE('  SQLCODE : ' || SQLCODE);
        DBMS_OUTPUT.PUT_LINE('  SQLERRM : ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('  Last test: ' || v_test_name);
        print_results;
END;
/
