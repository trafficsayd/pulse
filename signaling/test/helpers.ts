import { env, SELF } from 'cloudflare:test';
import type { CreateSessionResponse, Env } from '../src/types';

export const TEST_IP = '203.0.113.7';

export function defaultHeaders(extra: Record<string, string> = {}): HeadersInit {
  return {
    'content-type': 'application/json',
    'cf-connecting-ip': TEST_IP,
    ...extra,
  };
}

export function authHeaders(token: string, extra: Record<string, string> = {}): HeadersInit {
  return defaultHeaders({ authorization: `Bearer ${token}`, ...extra });
}

export async function callCreateSession(
  pairingCode: string,
  ip: string = TEST_IP,
): Promise<{ status: number; body: CreateSessionResponse }> {
  const response = await SELF.fetch('https://signaling.test/session', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'cf-connecting-ip': ip,
    },
    body: JSON.stringify({ pairingCode }),
  });
  const body = (await response.json()) as CreateSessionResponse;
  return { status: response.status, body };
}

/**
 * Wipe every key in the test KV namespace between specs. Miniflare gives each
 * test its own isolated KV by default, but we keep this helper around to be
 * explicit when a test needs a totally clean slate mid-run.
 */
export async function resetKv(): Promise<void> {
  const testEnv = env as unknown as Env;
  const list = await testEnv.SIGNALING_SESSIONS.list();
  await Promise.all(list.keys.map((k) => testEnv.SIGNALING_SESSIONS.delete(k.name)));
}

/**
 * Spend the rate-limit budget for `ip` so the next request hits 429. Returns
 * once the budget has been exhausted.
 */
export async function exhaustRateLimit(ip: string): Promise<void> {
  // The default limit is 30 / min / IP. We hit `/health` because it does not
  // require auth but still flows through the rate-limit middleware.
  for (let i = 0; i < 30; i++) {
    await SELF.fetch('https://signaling.test/health', {
      headers: { 'cf-connecting-ip': ip },
    });
  }
}

export interface FakeIce {
  candidate: string;
  sdpMid?: string | null;
  sdpMLineIndex?: number | null;
}

export function fakeIce(n: number): FakeIce {
  return {
    candidate: `candidate:1 1 UDP 2113937151 192.0.2.${n} 5400${n % 10} typ host`,
    sdpMid: '0',
    sdpMLineIndex: 0,
  };
}
