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

CREATE TABLE IF NOT EXISTS locks (
  scope TEXT PRIMARY KEY,
  lease_token INTEGER NOT NULL,
  holder TEXT NOT NULL,
  acquired_at TEXT NOT NULL,
  expires_at_epoch INTEGER NOT NULL,
  fencing_token INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_locks_expires ON locks (expires_at_epoch);

CREATE TABLE IF NOT EXISTS intent_reservations (
  intent_hash TEXT PRIMARY KEY,
  manifest_id TEXT NOT NULL,
  scopes TEXT NOT NULL,
  created_at_epoch INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS sagas (
  manifest_id TEXT PRIMARY KEY,
  state TEXT NOT NULL,
  intent_hash TEXT,
  planned_scopes TEXT NOT NULL,
  supervisor_lease TEXT,
  last_transition_at_epoch INTEGER NOT NULL,
  terminal INTEGER NOT NULL DEFAULT 0,
  metadata TEXT
);

CREATE INDEX IF NOT EXISTS idx_sagas_state ON sagas (state) WHERE terminal = 0;

CREATE TABLE IF NOT EXISTS saga_transitions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  manifest_id TEXT NOT NULL,
  from_state TEXT NOT NULL,
  to_state TEXT NOT NULL,
  reason TEXT,
  logical_stamp TEXT NOT NULL,
  created_at_epoch INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_saga_transitions_manifest ON saga_transitions (manifest_id, id);

CREATE TABLE IF NOT EXISTS compensations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  manifest_id TEXT NOT NULL,
  path TEXT NOT NULL,
  op TEXT NOT NULL,
  pre_blob_sha TEXT,
  pre_existed INTEGER NOT NULL,
  fencing_token INTEGER NOT NULL,
  logical_stamp TEXT NOT NULL,
  applied INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_compensations_manifest_unapplied ON compensations (manifest_id) WHERE applied = 0;

CREATE TABLE IF NOT EXISTS recovery_leases (
  manifest_id TEXT PRIMARY KEY,
  holder TEXT NOT NULL,
  acquired_at_epoch INTEGER NOT NULL,
  expires_at_epoch INTEGER NOT NULL
);
