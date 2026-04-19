<h1>PLSQL Example Banking</h1>

<p>
This repository is an AI-generated sample PL/SQL banking application for demo and learning purposes.
It models core banking operations such as customer/account management, transactions, loans, reporting,
and database-level unit tests on Oracle.
</p>

<h2>What Is Included</h2>

<ul>
    <li><b>Schema and seed data</b> for a realistic banking domain</li>
    <li><b>PL/SQL packages</b> for account, transaction, loan, and reporting flows</li>
    <li><b>Unit test scripts</b> to validate core package behavior</li>
</ul>

<h2>Script Order</h2>

<ol>
    <li>01_DDL_SCHEMA.sql</li>
    <li>02_PKG_ACCOUNT_MGMT.sql</li>
    <li>03_PKG_TRANSACTIONS.sql</li>
    <li>04_PKG_LOAN_MGMT.sql</li>
    <li>05_PKG_REPORTING.sql</li>
    <li>06_UNIT_TESTS.sql</li>
</ol>

<h2>Purpose</h2>

<p>
The project is intended as a reference implementation for AI-assisted code generation and
PL/SQL-to-other-language modernization experiments, not as a production-ready banking system.
</p>

<h2>ER Diagram</h2>

```mermaid
erDiagram

    BRANCHES {
        NUMBER branch_id PK
        NUMBER manager_id FK
    }

    EMPLOYEES {
        NUMBER employee_id PK
        NUMBER branch_id FK
    }

    CUSTOMERS {
        NUMBER customer_id PK
        NUMBER created_by FK
    }

    ACCOUNTS {
        NUMBER account_id PK
        NUMBER customer_id FK
        NUMBER branch_id FK
        VARCHAR account_type FK
    }

    ACCOUNT_TYPES {
        VARCHAR type_code PK
    }

    TRANSACTIONS {
        NUMBER transaction_id PK
        NUMBER account_id FK
        NUMBER related_account_id FK
        NUMBER processed_by FK
        NUMBER reversal_of FK
    }

    LOANS {
        NUMBER loan_id PK
        NUMBER customer_id FK
        NUMBER account_id FK
        NUMBER branch_id FK
        NUMBER approved_by FK
    }

    LOAN_PAYMENTS {
        NUMBER payment_id PK
        NUMBER loan_id FK
        NUMBER transaction_id FK
    }

    CARDS {
        NUMBER card_id PK
        NUMBER account_id FK
        NUMBER customer_id FK
    }

    INTEREST_POSTINGS {
        NUMBER posting_id PK
        NUMBER account_id FK
        NUMBER transaction_id FK
    }

    FEE_LEDGER {
        NUMBER fee_id PK
        NUMBER account_id FK
        NUMBER waived_by FK
        NUMBER transaction_id FK
    }

    FRAUD_ALERTS {
        NUMBER alert_id PK
        NUMBER account_id FK
        NUMBER customer_id FK
        NUMBER transaction_id FK
        NUMBER resolved_by FK
    }

    AUDIT_LOG {
        NUMBER audit_id PK
    }

    EXCHANGE_RATES {
        VARCHAR from_currency PK
        VARCHAR to_currency PK
    }

    %% RELATIONSHIPS

    BRANCHES ||--o{ EMPLOYEES : employs
    EMPLOYEES ||--o{ BRANCHES : manages

    EMPLOYEES ||--o{ CUSTOMERS : creates

    CUSTOMERS ||--o{ ACCOUNTS : owns
    BRANCHES ||--o{ ACCOUNTS : hosts
    ACCOUNT_TYPES ||--o{ ACCOUNTS : defines

    ACCOUNTS ||--o{ TRANSACTIONS : records
    EMPLOYEES ||--o{ TRANSACTIONS : processes
    TRANSACTIONS ||--o{ TRANSACTIONS : reverses

    CUSTOMERS ||--o{ LOANS : takes
    ACCOUNTS ||--o{ LOANS : links
    BRANCHES ||--o{ LOANS : issues
    EMPLOYEES ||--o{ LOANS : approves

    LOANS ||--o{ LOAN_PAYMENTS : has
    TRANSACTIONS ||--o{ LOAN_PAYMENTS : pays

    ACCOUNTS ||--o{ CARDS : has
    CUSTOMERS ||--o{ CARDS : owns

    ACCOUNTS ||--o{ INTEREST_POSTINGS : accrues
    TRANSACTIONS ||--o{ INTEREST_POSTINGS : logs

    ACCOUNTS ||--o{ FEE_LEDGER : charges
    EMPLOYEES ||--o{ FEE_LEDGER : waives
    TRANSACTIONS ||--o{ FEE_LEDGER : records

    ACCOUNTS ||--o{ FRAUD_ALERTS : flags
    CUSTOMERS ||--o{ FRAUD_ALERTS : involves
    TRANSACTIONS ||--o{ FRAUD_ALERTS : triggers
    EMPLOYEES ||--o{ FRAUD_ALERTS : resolves
```
