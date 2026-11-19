-- The accounts of the service. The balance is kept in cents, so the money
-- never meets the rounding error of a floating point number.
CREATE TABLE accounts (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  balance INTEGER NOT NULL DEFAULT 0
);

-- @down
DROP TABLE accounts;
