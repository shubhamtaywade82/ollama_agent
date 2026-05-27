-- ### runtime.db
CREATE TABLE IF NOT EXISTS cost_ledger (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  manifest_id TEXT,
  model TEXT NOT NULL,
  input_tokens INTEGER NOT NULL,
  output_tokens INTEGER NOT NULL,
  cost_usd REAL NOT NULL,
  created_at_epoch INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_cost_ledger_manifest ON cost_ledger (manifest_id);
