-- =============================================================================
-- BANKING OPERATIONS SYSTEM - DDL SCHEMA
-- =============================================================================
-- Oracle PL/SQL Compatible Schema
-- Author: Banking Operations System
-- Version: 1.0
-- =============================================================================

-- Drop objects if they exist (reverse dependency order)
BEGIN
    FOR r IN (SELECT object_name, object_type FROM user_objects
              WHERE object_type IN ('TABLE','SEQUENCE','TYPE')
              ORDER BY DECODE(object_type,'TYPE',1,'TABLE',2,'SEQUENCE',3))
    LOOP
        BEGIN
            IF r.object_type = 'TABLE' THEN
                EXECUTE IMMEDIATE 'DROP TABLE ' || r.object_name || ' CASCADE CONSTRAINTS PURGE';
            ELSIF r.object_type = 'SEQUENCE' THEN
                EXECUTE IMMEDIATE 'DROP SEQUENCE ' || r.object_name;
            ELSIF r.object_type = 'TYPE' THEN
                EXECUTE IMMEDIATE 'DROP TYPE ' || r.object_name || ' FORCE';
            END IF;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END LOOP;
END;
/

-- =============================================================================
-- CUSTOM TYPES
-- =============================================================================

CREATE OR REPLACE TYPE t_number_list AS TABLE OF NUMBER;
/

CREATE OR REPLACE TYPE t_varchar_list AS TABLE OF VARCHAR2(200);
/

CREATE OR REPLACE TYPE t_transaction_summary AS OBJECT (
    transaction_date   DATE,
    total_credits      NUMBER(20,2),
    total_debits       NUMBER(20,2),
    net_amount         NUMBER(20,2),
    transaction_count  NUMBER
);
/

CREATE OR REPLACE TYPE t_transaction_summary_list AS TABLE OF t_transaction_summary;
/

-- =============================================================================
-- SEQUENCES
-- =============================================================================

CREATE SEQUENCE seq_customer_id    START WITH 1000 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE seq_account_id     START WITH 100000 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE seq_transaction_id START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE seq_loan_id        START WITH 5000 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE seq_card_id        START WITH 9000 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE seq_branch_id      START WITH 10 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE seq_employee_id    START WITH 2000 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE seq_audit_id       START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE seq_alert_id       START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE seq_fee_id         START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE seq_interest_id    START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;

-- =============================================================================
-- CORE TABLES
-- =============================================================================

-- Branches
CREATE TABLE branches (
    branch_id        NUMBER(10)     DEFAULT seq_branch_id.NEXTVAL PRIMARY KEY,
    branch_code      VARCHAR2(10)   NOT NULL UNIQUE,
    branch_name      VARCHAR2(100)  NOT NULL,
    address          VARCHAR2(255),
    city             VARCHAR2(100),
    state            VARCHAR2(100),
    country          VARCHAR2(100)  DEFAULT 'US',
    phone            VARCHAR2(20),
    email            VARCHAR2(100),
    manager_id       NUMBER(10),
    is_active        CHAR(1)        DEFAULT 'Y' CHECK (is_active IN ('Y','N')),
    opened_date      DATE           DEFAULT SYSDATE,
    created_at       TIMESTAMP      DEFAULT SYSTIMESTAMP,
    updated_at       TIMESTAMP      DEFAULT SYSTIMESTAMP
);

-- Employees
CREATE TABLE employees (
    employee_id      NUMBER(10)     DEFAULT seq_employee_id.NEXTVAL PRIMARY KEY,
    branch_id        NUMBER(10)     REFERENCES branches(branch_id),
    employee_code    VARCHAR2(20)   NOT NULL UNIQUE,
    first_name       VARCHAR2(100)  NOT NULL,
    last_name        VARCHAR2(100)  NOT NULL,
    email            VARCHAR2(150)  NOT NULL UNIQUE,
    phone            VARCHAR2(20),
    role             VARCHAR2(50)   NOT NULL CHECK (role IN ('TELLER','MANAGER','LOAN_OFFICER','ANALYST','ADMIN','AUDITOR')),
    salary           NUMBER(15,2),
    hire_date        DATE           DEFAULT SYSDATE,
    is_active        CHAR(1)        DEFAULT 'Y' CHECK (is_active IN ('Y','N')),
    created_at       TIMESTAMP      DEFAULT SYSTIMESTAMP,
    updated_at       TIMESTAMP      DEFAULT SYSTIMESTAMP
);

-- Add FK for branch manager after employees table exists
ALTER TABLE branches ADD CONSTRAINT fk_branch_manager
    FOREIGN KEY (manager_id) REFERENCES employees(employee_id);

-- Customers
CREATE TABLE customers (
    customer_id      NUMBER(10)     DEFAULT seq_customer_id.NEXTVAL PRIMARY KEY,
    customer_code    VARCHAR2(20)   NOT NULL UNIQUE,
    first_name       VARCHAR2(100)  NOT NULL,
    last_name        VARCHAR2(100)  NOT NULL,
    date_of_birth    DATE           NOT NULL,
    ssn_hash         VARCHAR2(64),   -- Hashed SSN
    email            VARCHAR2(150)  NOT NULL UNIQUE,
    phone            VARCHAR2(20),
    address          VARCHAR2(255),
    city             VARCHAR2(100),
    state            VARCHAR2(50),
    zip_code         VARCHAR2(20),
    country          VARCHAR2(100)  DEFAULT 'US',
    credit_score     NUMBER(4)      CHECK (credit_score BETWEEN 300 AND 850),
    kyc_status       VARCHAR2(20)   DEFAULT 'PENDING' CHECK (kyc_status IN ('PENDING','VERIFIED','REJECTED','EXPIRED')),
    customer_type    VARCHAR2(20)   DEFAULT 'RETAIL' CHECK (customer_type IN ('RETAIL','BUSINESS','PREMIUM','VIP')),
    risk_level       VARCHAR2(10)   DEFAULT 'LOW' CHECK (risk_level IN ('LOW','MEDIUM','HIGH')),
    is_active        CHAR(1)        DEFAULT 'Y' CHECK (is_active IN ('Y','N')),
    created_at       TIMESTAMP      DEFAULT SYSTIMESTAMP,
    updated_at       TIMESTAMP      DEFAULT SYSTIMESTAMP,
    created_by       NUMBER(10)     REFERENCES employees(employee_id)
);

-- Account Types Lookup
CREATE TABLE account_types (
    type_code        VARCHAR2(20)   PRIMARY KEY,
    type_name        VARCHAR2(100)  NOT NULL,
    min_balance      NUMBER(15,2)   DEFAULT 0,
    monthly_fee      NUMBER(10,2)   DEFAULT 0,
    interest_rate    NUMBER(8,4)    DEFAULT 0,
    overdraft_limit  NUMBER(15,2)   DEFAULT 0,
    is_active        CHAR(1)        DEFAULT 'Y'
);

INSERT INTO account_types VALUES ('CHECKING',  'Checking Account',        0,      5.00,  0.0100, 500,   'Y');
INSERT INTO account_types VALUES ('SAVINGS',   'Savings Account',         500,    0,     2.5000, 0,     'Y');
INSERT INTO account_types VALUES ('MONEY_MKT', 'Money Market Account',    10000,  0,     3.5000, 0,     'Y');
INSERT INTO account_types VALUES ('CD',        'Certificate of Deposit',  1000,   0,     4.2000, 0,     'Y');
INSERT INTO account_types VALUES ('BUSINESS',  'Business Account',        2500,   15.00, 0.0500, 5000,  'Y');
INSERT INTO account_types VALUES ('PREMIUM',   'Premium Account',         25000,  0,     1.5000, 10000, 'Y');
COMMIT;

-- Accounts
CREATE TABLE accounts (
    account_id       NUMBER(10)     DEFAULT seq_account_id.NEXTVAL PRIMARY KEY,
    account_number   VARCHAR2(20)   NOT NULL UNIQUE,
    customer_id      NUMBER(10)     NOT NULL REFERENCES customers(customer_id),
    branch_id        NUMBER(10)     NOT NULL REFERENCES branches(branch_id),
    account_type     VARCHAR2(20)   NOT NULL REFERENCES account_types(type_code),
    balance          NUMBER(20,2)   DEFAULT 0 NOT NULL,
    available_balance NUMBER(20,2)  DEFAULT 0 NOT NULL,
    hold_amount      NUMBER(20,2)   DEFAULT 0,
    currency         VARCHAR2(3)    DEFAULT 'USD',
    status           VARCHAR2(20)   DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','INACTIVE','FROZEN','CLOSED','DORMANT')),
    opened_date      DATE           DEFAULT SYSDATE,
    closed_date      DATE,
    last_transaction_date DATE,
    interest_accrued NUMBER(15,2)   DEFAULT 0,
    overdraft_used   NUMBER(15,2)   DEFAULT 0,
    created_at       TIMESTAMP      DEFAULT SYSTIMESTAMP,
    updated_at       TIMESTAMP      DEFAULT SYSTIMESTAMP,
    CONSTRAINT chk_balance CHECK (balance >= -500)  -- allow some overdraft
);

-- Transactions
CREATE TABLE transactions (
    transaction_id       NUMBER(15)    DEFAULT seq_transaction_id.NEXTVAL PRIMARY KEY,
    account_id           NUMBER(10)    NOT NULL REFERENCES accounts(account_id),
    related_account_id   NUMBER(10)    REFERENCES accounts(account_id),
    transaction_type     VARCHAR2(30)  NOT NULL CHECK (transaction_type IN (
                           'DEPOSIT','WITHDRAWAL','TRANSFER_IN','TRANSFER_OUT',
                           'PAYMENT','FEE','INTEREST','REVERSAL','ADJUSTMENT')),
    amount               NUMBER(20,2)  NOT NULL CHECK (amount > 0),
    balance_before       NUMBER(20,2)  NOT NULL,
    balance_after        NUMBER(20,2)  NOT NULL,
    currency             VARCHAR2(3)   DEFAULT 'USD',
    description          VARCHAR2(500),
    reference_number     VARCHAR2(50)  UNIQUE,
    channel              VARCHAR2(20)  DEFAULT 'BRANCH' CHECK (channel IN ('BRANCH','ATM','ONLINE','MOBILE','API','SYSTEM')),
    status               VARCHAR2(20)  DEFAULT 'COMPLETED' CHECK (status IN ('PENDING','COMPLETED','FAILED','REVERSED')),
    transaction_date     TIMESTAMP     DEFAULT SYSTIMESTAMP,
    value_date           DATE          DEFAULT SYSDATE,
    processed_by         NUMBER(10)    REFERENCES employees(employee_id),
    reversal_of          NUMBER(15)    REFERENCES transactions(transaction_id),
    created_at           TIMESTAMP     DEFAULT SYSTIMESTAMP
);

-- Loans
CREATE TABLE loans (
    loan_id          NUMBER(10)     DEFAULT seq_loan_id.NEXTVAL PRIMARY KEY,
    loan_number      VARCHAR2(20)   NOT NULL UNIQUE,
    customer_id      NUMBER(10)     NOT NULL REFERENCES customers(customer_id),
    account_id       NUMBER(10)     REFERENCES accounts(account_id),
    branch_id        NUMBER(10)     NOT NULL REFERENCES branches(branch_id),
    loan_type        VARCHAR2(30)   NOT NULL CHECK (loan_type IN ('PERSONAL','MORTGAGE','AUTO','BUSINESS','STUDENT','HELOC')),
    principal_amount NUMBER(20,2)   NOT NULL,
    outstanding_balance NUMBER(20,2) NOT NULL,
    interest_rate    NUMBER(8,4)    NOT NULL,
    term_months      NUMBER(4)      NOT NULL,
    monthly_payment  NUMBER(15,2)   NOT NULL,
    disbursement_date DATE,
    maturity_date    DATE,
    status           VARCHAR2(20)   DEFAULT 'PENDING' CHECK (status IN ('PENDING','APPROVED','ACTIVE','PAID_OFF','DEFAULTED','REJECTED','WRITTEN_OFF')),
    collateral_type  VARCHAR2(50),
    collateral_value NUMBER(20,2),
    credit_score_at_origination NUMBER(4),
    approved_by      NUMBER(10)     REFERENCES employees(employee_id),
    days_past_due    NUMBER(4)      DEFAULT 0,
    times_30_dpd     NUMBER(3)      DEFAULT 0,
    times_60_dpd     NUMBER(3)      DEFAULT 0,
    times_90_dpd     NUMBER(3)      DEFAULT 0,
    created_at       TIMESTAMP      DEFAULT SYSTIMESTAMP,
    updated_at       TIMESTAMP      DEFAULT SYSTIMESTAMP
);

-- Loan Payments
CREATE TABLE loan_payments (
    payment_id       NUMBER(15)     PRIMARY KEY,
    loan_id          NUMBER(10)     NOT NULL REFERENCES loans(loan_id),
    payment_date     DATE           DEFAULT SYSDATE,
    due_date         DATE           NOT NULL,
    scheduled_amount NUMBER(15,2)   NOT NULL,
    paid_amount      NUMBER(15,2)   DEFAULT 0,
    principal_portion NUMBER(15,2)  DEFAULT 0,
    interest_portion NUMBER(15,2)   DEFAULT 0,
    late_fee         NUMBER(10,2)   DEFAULT 0,
    status           VARCHAR2(20)   DEFAULT 'SCHEDULED' CHECK (status IN ('SCHEDULED','PAID','PARTIAL','OVERDUE','WAIVED')),
    transaction_id   NUMBER(15)     REFERENCES transactions(transaction_id),
    created_at       TIMESTAMP      DEFAULT SYSTIMESTAMP
);

CREATE SEQUENCE seq_payment_id START WITH 1 INCREMENT BY 1 NOCACHE;

-- Cards
CREATE TABLE cards (
    card_id          NUMBER(10)     DEFAULT seq_card_id.NEXTVAL PRIMARY KEY,
    card_number_hash VARCHAR2(64)   NOT NULL UNIQUE,  -- Hashed card number
    card_last_four   VARCHAR2(4)    NOT NULL,
    account_id       NUMBER(10)     NOT NULL REFERENCES accounts(account_id),
    customer_id      NUMBER(10)     NOT NULL REFERENCES customers(customer_id),
    card_type        VARCHAR2(20)   NOT NULL CHECK (card_type IN ('DEBIT','CREDIT','PREPAID')),
    card_network     VARCHAR2(20)   DEFAULT 'VISA' CHECK (card_network IN ('VISA','MASTERCARD','AMEX','DISCOVER')),
    credit_limit     NUMBER(15,2),
    available_credit NUMBER(15,2),
    expiry_date      DATE           NOT NULL,
    status           VARCHAR2(20)   DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','BLOCKED','EXPIRED','CANCELLED')),
    daily_limit      NUMBER(15,2)   DEFAULT 5000,
    issued_date      DATE           DEFAULT SYSDATE,
    created_at       TIMESTAMP      DEFAULT SYSTIMESTAMP,
    updated_at       TIMESTAMP      DEFAULT SYSTIMESTAMP
);

-- Interest Postings
CREATE TABLE interest_postings (
    posting_id       NUMBER(15)     DEFAULT seq_interest_id.NEXTVAL PRIMARY KEY,
    account_id       NUMBER(10)     NOT NULL REFERENCES accounts(account_id),
    posting_date     DATE           NOT NULL,
    period_start     DATE           NOT NULL,
    period_end       DATE           NOT NULL,
    average_balance  NUMBER(20,2)   NOT NULL,
    interest_rate    NUMBER(8,4)    NOT NULL,
    gross_interest   NUMBER(15,2)   NOT NULL,
    tax_withheld     NUMBER(15,2)   DEFAULT 0,
    net_interest     NUMBER(15,2)   NOT NULL,
    transaction_id   NUMBER(15)     REFERENCES transactions(transaction_id),
    created_at       TIMESTAMP      DEFAULT SYSTIMESTAMP
);

-- Fee Ledger
CREATE TABLE fee_ledger (
    fee_id           NUMBER(15)     DEFAULT seq_fee_id.NEXTVAL PRIMARY KEY,
    account_id       NUMBER(10)     NOT NULL REFERENCES accounts(account_id),
    fee_type         VARCHAR2(50)   NOT NULL CHECK (fee_type IN ('MONTHLY_FEE','OVERDRAFT_FEE','WIRE_FEE','ATM_FEE','LATE_FEE','NSF_FEE','FOREIGN_TXN_FEE')),
    fee_amount       NUMBER(10,2)   NOT NULL,
    fee_date         DATE           DEFAULT SYSDATE,
    waived           CHAR(1)        DEFAULT 'N',
    waived_by        NUMBER(10)     REFERENCES employees(employee_id),
    waived_reason    VARCHAR2(255),
    transaction_id   NUMBER(15)     REFERENCES transactions(transaction_id),
    created_at       TIMESTAMP      DEFAULT SYSTIMESTAMP
);

-- Fraud Alerts
CREATE TABLE fraud_alerts (
    alert_id         NUMBER(15)     DEFAULT seq_alert_id.NEXTVAL PRIMARY KEY,
    account_id       NUMBER(10)     NOT NULL REFERENCES accounts(account_id),
    customer_id      NUMBER(10)     NOT NULL REFERENCES customers(customer_id),
    transaction_id   NUMBER(15)     REFERENCES transactions(transaction_id),
    alert_type       VARCHAR2(50)   NOT NULL,
    severity         VARCHAR2(10)   DEFAULT 'MEDIUM' CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    description      VARCHAR2(1000),
    status           VARCHAR2(20)   DEFAULT 'OPEN' CHECK (status IN ('OPEN','INVESTIGATING','RESOLVED','FALSE_POSITIVE')),
    resolved_by      NUMBER(10)     REFERENCES employees(employee_id),
    resolved_at      TIMESTAMP,
    created_at       TIMESTAMP      DEFAULT SYSTIMESTAMP
);

-- Audit Log
CREATE TABLE audit_log (
    audit_id         NUMBER(15)     DEFAULT seq_audit_id.NEXTVAL PRIMARY KEY,
    table_name       VARCHAR2(50)   NOT NULL,
    record_id        NUMBER(15)     NOT NULL,
    action           VARCHAR2(10)   NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
    old_values       CLOB,
    new_values       CLOB,
    changed_by       VARCHAR2(100),
    changed_at       TIMESTAMP      DEFAULT SYSTIMESTAMP,
    session_id       VARCHAR2(100),
    ip_address       VARCHAR2(50)
);

-- Exchange Rates
CREATE TABLE exchange_rates (
    from_currency    VARCHAR2(3)    NOT NULL,
    to_currency      VARCHAR2(3)    NOT NULL,
    rate             NUMBER(15,6)   NOT NULL,
    effective_date   DATE           DEFAULT SYSDATE,
    created_at       TIMESTAMP      DEFAULT SYSTIMESTAMP,
    PRIMARY KEY (from_currency, to_currency, effective_date)
);

INSERT INTO exchange_rates VALUES ('USD','EUR', 0.921000, SYSDATE, SYSTIMESTAMP);
INSERT INTO exchange_rates VALUES ('USD','GBP', 0.787000, SYSDATE, SYSTIMESTAMP);
INSERT INTO exchange_rates VALUES ('USD','JPY', 154.32000, SYSDATE, SYSTIMESTAMP);
INSERT INTO exchange_rates VALUES ('EUR','USD', 1.085000, SYSDATE, SYSTIMESTAMP);
INSERT INTO exchange_rates VALUES ('GBP','USD', 1.270000, SYSDATE, SYSTIMESTAMP);
INSERT INTO exchange_rates VALUES ('JPY','USD', 0.006480, SYSDATE, SYSTIMESTAMP);
COMMIT;

-- =============================================================================
-- INDEXES
-- =============================================================================

CREATE INDEX idx_accounts_customer  ON accounts(customer_id);
CREATE INDEX idx_accounts_status    ON accounts(status);
CREATE INDEX idx_txn_account        ON transactions(account_id);
CREATE INDEX idx_txn_date           ON transactions(transaction_date);
CREATE INDEX idx_txn_type           ON transactions(transaction_type);
CREATE INDEX idx_loans_customer     ON loans(customer_id);
CREATE INDEX idx_loans_status       ON loans(status);
CREATE INDEX idx_cards_account      ON cards(account_id);
CREATE INDEX idx_alerts_account     ON fraud_alerts(account_id);
CREATE INDEX idx_alerts_status      ON fraud_alerts(status);
CREATE INDEX idx_audit_table        ON audit_log(table_name, record_id);
CREATE INDEX idx_fee_account        ON fee_ledger(account_id);
CREATE INDEX idx_interest_account   ON interest_postings(account_id);

-- =============================================================================
-- SEED DATA
-- =============================================================================

-- Insert Branches
INSERT INTO branches (branch_code, branch_name, address, city, state, country)
VALUES ('HQ001', 'Main Headquarters', '100 Banking Blvd', 'New York', 'NY', 'US');

INSERT INTO branches (branch_code, branch_name, address, city, state, country)
VALUES ('BR002', 'Downtown Branch', '250 Wall Street', 'New York', 'NY', 'US');

INSERT INTO branches (branch_code, branch_name, address, city, state, country)
VALUES ('BR003', 'West Side Branch', '500 Broadway Ave', 'New York', 'NY', 'US');

-- Insert Employees
INSERT INTO employees (branch_id, employee_code, first_name, last_name, email, role, salary)
VALUES (10, 'EMP001', 'John', 'Smith', 'john.smith@bank.com', 'MANAGER', 95000);

INSERT INTO employees (branch_id, employee_code, first_name, last_name, email, role, salary)
VALUES (10, 'EMP002', 'Jane', 'Doe', 'jane.doe@bank.com', 'LOAN_OFFICER', 75000);

INSERT INTO employees (branch_id, employee_code, first_name, last_name, email, role, salary)
VALUES (11, 'EMP003', 'Bob', 'Johnson', 'bob.j@bank.com', 'TELLER', 45000);

INSERT INTO employees (branch_id, employee_code, first_name, last_name, email, role, salary)
VALUES (11, 'EMP004', 'Alice', 'Williams', 'alice.w@bank.com', 'ANALYST', 65000);

COMMIT;

-- Update branch managers
UPDATE branches SET manager_id = 2000 WHERE branch_id = 10;
UPDATE branches SET manager_id = 2001 WHERE branch_id = 11;
COMMIT;

-- Insert Customers
INSERT INTO customers (customer_code, first_name, last_name, date_of_birth, email, phone, 
                       credit_score, kyc_status, customer_type, risk_level, created_by)
VALUES ('CUST001','Alice','Johnson', DATE '1985-03-15', 'alice.johnson@email.com', '555-0101',
        720, 'VERIFIED', 'RETAIL', 'LOW', 2000);

INSERT INTO customers (customer_code, first_name, last_name, date_of_birth, email, phone,
                       credit_score, kyc_status, customer_type, risk_level, created_by)
VALUES ('CUST002','Bob','Smith', DATE '1978-07-22', 'bob.smith@email.com', '555-0102',
        680, 'VERIFIED', 'RETAIL', 'LOW', 2000);

INSERT INTO customers (customer_code, first_name, last_name, date_of_birth, email, phone,
                       credit_score, kyc_status, customer_type, risk_level, created_by)
VALUES ('CUST003','Carol','Davis', DATE '1990-11-08', 'carol.davis@email.com', '555-0103',
        760, 'VERIFIED', 'PREMIUM', 'LOW', 2001);

INSERT INTO customers (customer_code, first_name, last_name, date_of_birth, email, phone,
                       credit_score, kyc_status, customer_type, risk_level, created_by)
VALUES ('CUST004','David','Wilson', DATE '1965-05-30', 'david.wilson@email.com', '555-0104',
        590, 'VERIFIED', 'RETAIL', 'MEDIUM', 2001);

INSERT INTO customers (customer_code, first_name, last_name, date_of_birth, email, phone,
                       credit_score, kyc_status, customer_type, risk_level, created_by)
VALUES ('CUST005','Eve','Martinez', DATE '1992-09-14', 'eve.martinez@email.com', '555-0105',
        800, 'VERIFIED', 'VIP', 'LOW', 2000);

COMMIT;

-- Insert Accounts
INSERT INTO accounts (account_number, customer_id, branch_id, account_type, balance, available_balance)
VALUES ('ACC-100001', 1000, 10, 'CHECKING', 5000.00, 5000.00);

INSERT INTO accounts (account_number, customer_id, branch_id, account_type, balance, available_balance)
VALUES ('ACC-100002', 1000, 10, 'SAVINGS', 15000.00, 15000.00);

INSERT INTO accounts (account_number, customer_id, branch_id, account_type, balance, available_balance)
VALUES ('ACC-100003', 1001, 10, 'CHECKING', 2500.00, 2500.00);

INSERT INTO accounts (account_number, customer_id, branch_id, account_type, balance, available_balance)
VALUES ('ACC-100004', 1002, 11, 'SAVINGS', 50000.00, 50000.00);

INSERT INTO accounts (account_number, customer_id, branch_id, account_type, balance, available_balance)
VALUES ('ACC-100005', 1003, 11, 'CHECKING', 800.00, 800.00);

INSERT INTO accounts (account_number, customer_id, branch_id, account_type, balance, available_balance)
VALUES ('ACC-100006', 1004, 10, 'PREMIUM', 125000.00, 125000.00);

INSERT INTO accounts (account_number, customer_id, branch_id, account_type, balance, available_balance)
VALUES ('ACC-100007', 1004, 10, 'MONEY_MKT', 75000.00, 75000.00);

COMMIT;

PROMPT Schema creation complete.
