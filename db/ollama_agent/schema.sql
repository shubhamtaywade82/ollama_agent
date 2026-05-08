-- ### event_store.db
-- Append-only events; PRAGMAs applied by DatabaseRegistry after open.
PRAGMA journal_mode=WAL;
PRAGMA synchronous=FULL;

CREATE TABLE IF NOT EXISTS events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  manifest_id TEXT NOT NULL,
  logical_stamp TEXT NOT NULL,
  kind TEXT NOT NULL,
  payload BLOB NOT NULL,
  intent_hash TEXT,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_events_manifest_id_id ON events (manifest_id, id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_events_intent_hash_unique ON events (intent_hash) WHERE intent_hash IS NOT NULL;

-- ### runtime.db
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;

CREATE TABLE IF NOT EXISTS workspace_fingerprints (
  manifest_id TEXT PRIMARY KEY,
  fingerprint TEXT NOT NULL,
  parent_manifest_id TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS fencing_tokens (
  scope TEXT PRIMARY KEY,
  last_token INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS integration_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  manifest_id TEXT NOT NULL,
  payload BLOB NOT NULL,
  status TEXT NOT NULL,
  created_at TEXT NOT NULL
);
