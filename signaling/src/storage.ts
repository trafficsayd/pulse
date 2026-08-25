import type { Env } from './types';

interface PutOptions {
  expirationTtl: number;
}

export interface SignalingStore {
  get(key: string): Promise<string | null>;
  put(key: string, value: string, options: PutOptions): Promise<void>;
}

export interface StoredIceCandidate {
  cursor: number;
  value: string;
}

/** Insert one candidate without a read-modify-write race. D1 row ids are cursors. */
export async function appendD1IceCandidate(
  env: Env,
  sessionId: string,
  value: string,
  expirationTtl: number,
): Promise<number | null> {
  if (!env.SIGNALING_DB || env.USE_KV_FOR_TESTS === 'true') return null;
  const result = await env.SIGNALING_DB.prepare(
    'INSERT INTO signaling_ice (session_id, value, expires_at) VALUES (?1, ?2, ?3)',
  )
    .bind(sessionId, value, Date.now() + expirationTtl * 1000)
    .run();
  return Number(result.meta.last_row_id);
}

/** Read the append-only D1 ICE stream after an opaque monotonically growing cursor. */
export async function readD1IceCandidatesSince(
  env: Env,
  sessionId: string,
  since: number,
): Promise<StoredIceCandidate[] | null> {
  if (!env.SIGNALING_DB || env.USE_KV_FOR_TESTS === 'true') return null;
  const result = await env.SIGNALING_DB.prepare(
    `SELECT id AS cursor, value FROM signaling_ice
     WHERE session_id = ?1 AND id > ?2 AND expires_at > ?3
     ORDER BY id ASC`,
  )
    .bind(sessionId, since, Date.now())
    .all<StoredIceCandidate>();
  return result.results;
}

/**
 * D1-backed KV-shaped adapter. Production uses D1's 100k rows-written/day
 * free allowance; tests and a rollback deployment can still use Workers KV.
 */
export function signalingStore(env: Env): SignalingStore {
  const db = env.USE_KV_FOR_TESTS === 'true' ? undefined : env.SIGNALING_DB;
  if (!db) return env.SIGNALING_SESSIONS;

  return {
    async get(key: string): Promise<string | null> {
      const row = await db
        .prepare('SELECT value FROM signaling_store WHERE key = ?1 AND expires_at > ?2')
        .bind(key, Date.now())
        .first<{ value: string }>();
      return row?.value ?? null;
    },
    async put(key: string, value: string, options: PutOptions): Promise<void> {
      const expiresAt = Date.now() + options.expirationTtl * 1000;
      await db
        .prepare(
          `INSERT INTO signaling_store (key, value, expires_at)
           VALUES (?1, ?2, ?3)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value, expires_at = excluded.expires_at`,
        )
        .bind(key, value, expiresAt)
        .run();
    },
  };
}
