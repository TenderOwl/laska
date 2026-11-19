-- The ledger of the transfers. A transfer is written in the same transaction
-- as the change of the balances, so the ledger and the balances never
-- disagree.
CREATE TABLE transfers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  from_account TEXT NOT NULL,
  to_account TEXT NOT NULL,
  amount INTEGER NOT NULL,
  created_at TEXT NOT NULL
);

CREATE INDEX transfers_created_at ON transfers (created_at);

-- @down
DROP INDEX transfers_created_at;
DROP TABLE transfers;
