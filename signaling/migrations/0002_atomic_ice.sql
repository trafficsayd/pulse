CREATE TABLE IF NOT EXISTS signaling_ice (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT NOT NULL,
  value TEXT NOT NULL,
  expires_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_signaling_ice_session_cursor
  ON signaling_ice (session_id, id);

CREATE INDEX IF NOT EXISTS idx_signaling_ice_expires_at
  ON signaling_ice (expires_at);
