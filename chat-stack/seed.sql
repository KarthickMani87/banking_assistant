-- Users
INSERT INTO users (name, email) VALUES
('Alice', 'alice@example.com'),
('Bob', 'bob@example.com'),
('Charlie', 'charlie@example.com');

-- Accounts
INSERT INTO accounts (user_id, account_number, account_type, balance, currency) VALUES
(1, '11111111', 'checking', 1200.50, 'USD'),
(1, '11111112', 'savings', 5300.75, 'USD'),
(2, '22222222', 'checking', 800.00, 'USD'),
(3, '33333333', 'checking', 1500.00, 'USD');

-- Transactions
INSERT INTO transactions (account_id, amount, category, description, created_at) VALUES
(1, -50.00, 'groceries', 'Walmart purchase', now() - interval '1 day'),
(1, -200.00, 'utilities', 'Electricity bill', now() - interval '2 days'),
(1, -20.00, 'food', 'Starbucks coffee', now() - interval '3 days'),
(2, -100.00, 'shopping', 'Amazon order', now() - interval '1 day'),
(3, 500.00, 'salary', 'Monthly salary deposit', now() - interval '5 days'),
(1, -300.00, 'travel', 'Flight booking', now() - interval '10 days');

-- Payees
INSERT INTO payees (name, account_number, category) VALUES
('Electricity Company', '99900001', 'utilities'),
('Water Supply Co.', '99900002', 'utilities'),
('Internet Provider', '99900003', 'internet'),
('Credit Card Payment', '99900004', 'credit');

-- Alerts
INSERT INTO alerts (user_id, type, threshold) VALUES
(1, 'low_balance', 1000.00),
(2, 'large_txn', 500.00);

