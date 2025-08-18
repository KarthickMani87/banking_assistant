-- Users
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    email VARCHAR(200) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT now()
);

-- Accounts
CREATE TABLE accounts (
    id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(id),
    account_number VARCHAR(20) UNIQUE NOT NULL,
    account_type VARCHAR(50) CHECK (account_type IN ('checking','savings','credit')),
    balance NUMERIC(12,2) DEFAULT 0,
    currency VARCHAR(3) DEFAULT 'USD'
);

-- Transactions
CREATE TABLE transactions (
    id SERIAL PRIMARY KEY,
    account_id INT REFERENCES accounts(id),
    amount NUMERIC(12,2) NOT NULL,
    category VARCHAR(50),
    description TEXT,
    created_at TIMESTAMP DEFAULT now()
);

-- Payees
CREATE TABLE payees (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    account_number VARCHAR(20) NOT NULL,
    category VARCHAR(50)
);

-- Alerts
CREATE TABLE alerts (
    id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(id),
    type VARCHAR(50),
    threshold NUMERIC(12,2),
    created_at TIMESTAMP DEFAULT now(),
    is_active BOOLEAN DEFAULT true
);

