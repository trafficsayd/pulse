CREATE TABLE IF NOT EXISTS signaling_store (
  key TEXT PRIMARY KEY NOT NULL,
  value TEXT NOT NULL,
  expires_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_signaling_store_expires_at
  ON signaling_store (expires_at);
