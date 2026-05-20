import type { Env } from './types';

/**
 * Sliding-window rate limiter backed by KV.
 *
 * For each (ip, minuteBucket) we store an integer counter under
 * `ratelimit:<ip>:<minuteBucket>`. On every request we increment the current
 * bucket and inspect the previous bucket, then compute a weighted sum that
 * smooths the boundary between minutes:
 *
 *     count = current + previous * (1 - elapsed_in_current_minute / 60)
 *
 * When that weighted count exceeds the configured per-minute limit we reject
 * the request with 429.
 *
 * KV is eventually consistent, so the counter is a soft bound: a determined
 * attacker can squeeze a handful of extra requests through during a write
 * propagation window. That is acceptable for an anti-abuse signal that pairs
 * with the per-session TTL.
 */

const PREFIX = 'ratelimit:';
const BUCKET_MS = 60_000;
/** TTL on the counter keys — two minutes is enough for the sliding window. */
const BUCKET_TTL_SECONDS = 120;

export interface RateLimitDecision {
  allowed: boolean;
  /** Approximate requests in the trailing 60s window. */
  count: number;
  /** Configured limit for this Worker. */
  limit: number;
  /** Seconds until the trailing window decays below the limit. */
  retryAfterSeconds: number;
}

function ipFromRequest(req: Request): string {
  return (
    req.headers.get('cf-connecting-ip') ??
    req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ??
    'unknown'
  );
}

function parseLimit(env: Env): number {
  const raw = env.RATE_LIMIT_PER_MINUTE;
  if (!raw) {
    return 30;
  }
  const n = Number.parseInt(raw, 10);
  return Number.isFinite(n) && n > 0 ? n : 30;
}

async function readCounter(env: Env, key: string): Promise<number> {
  const v = await env.SIGNALING_SESSIONS.get(key);
  if (!v) {
    return 0;
  }
  const n = Number.parseInt(v, 10);
  return Number.isFinite(n) && n >= 0 ? n : 0;
}

/**
 * Check the limit and (when allowed) increment the current bucket.
 *
 * `nowMs` is taken as an argument so tests can pin the clock.
 */
export async function checkAndIncrementRateLimit(
  env: Env,
  req: Request,
  nowMs: number = Date.now(),
): Promise<RateLimitDecision> {
  const ip = ipFromRequest(req);
  const limit = parseLimit(env);

  const currentBucket = Math.floor(nowMs / BUCKET_MS);
  const previousBucket = currentBucket - 1;
  const currentKey = `${PREFIX}${ip}:${currentBucket}`;
  const previousKey = `${PREFIX}${ip}:${previousBucket}`;

  const [current, previous] = await Promise.all([
    readCounter(env, currentKey),
    readCounter(env, previousKey),
  ]);

  const elapsedInBucket = nowMs - currentBucket * BUCKET_MS;
  const previousWeight = 1 - elapsedInBucket / BUCKET_MS;
  const weighted = current + previous * previousWeight;

  if (weighted >= limit) {
    const overshoot = weighted - limit + 1;
    const retryAfterSeconds = Math.max(1, Math.ceil((overshoot / Math.max(1, previous)) * 60));
    return { allowed: false, count: Math.round(weighted), limit, retryAfterSeconds };
  }

  await env.SIGNALING_SESSIONS.put(currentKey, String(current + 1), {
    expirationTtl: BUCKET_TTL_SECONDS,
  });

  return {
    allowed: true,
    count: Math.round(weighted) + 1,
    limit,
    retryAfterSeconds: 0,
  };
}
