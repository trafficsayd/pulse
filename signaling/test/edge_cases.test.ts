import { env, SELF } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';
import type { Env } from '../src/types';
import { authHeaders, callCreateSession, defaultHeaders, TEST_IP } from './helpers';

describe('routing edge cases', () => {
  it('returns 404 for an unknown path', async () => {
    const r = await SELF.fetch('https://signaling.test/totally-unknown', {
      headers: { 'cf-connecting-ip': TEST_IP },
    });
    expect(r.status).toBe(404);
  });

  it('returns 404 for a wrong method on /session', async () => {
    const r = await SELF.fetch('https://signaling.test/session', {
      method: 'GET',
      headers: { 'cf-connecting-ip': TEST_IP },
    });
    expect(r.status).toBe(404);
  });

  it('returns 401 for malformed bearer tokens', async () => {
    const { body: created } = await callCreateSession('1234');
    const r = await SELF.fetch(`https://signaling.test/session/${created.sessionId}/offer`, {
      headers: defaultHeaders({ authorization: 'Bearer not.a.real.token' }),
    });
    expect([401, 403]).toContain(r.status);
  });

  it('rejects a session id that does not match the URL pattern', async () => {
    const { body: created } = await callCreateSession('1234');
    const r = await SELF.fetch('https://signaling.test/session/zzz/offer', {
      headers: authHeaders(created.token),
    });
    // The route regex enforces hex-only ids, so a non-hex id is a 404.
    expect(r.status).toBe(404);
  });
});

describe('TTL behaviour', () => {
  it('returns 404 once the underlying session record has been removed', async () => {
    const { body: created } = await callCreateSession('1234');
    // Simulate TTL expiry by deleting the session row directly via the bound
    // KV namespace. This is exactly what happens in production once the TTL
    // we set on `put()` elapses.
    const testEnv = env as unknown as Env;
    await testEnv.SIGNALING_SESSIONS.delete(`session:${created.sessionId}`);

    const r = await SELF.fetch(`https://signaling.test/session/${created.sessionId}/offer`, {
      headers: authHeaders(created.token),
    });
    expect(r.status).toBe(404);
  });
});

describe('health probe', () => {
  it('GET /health returns 200 without auth', async () => {
    const r = await SELF.fetch('https://signaling.test/health', {
      headers: { 'cf-connecting-ip': TEST_IP },
    });
    expect(r.status).toBe(200);
    const body = (await r.json()) as { ok: boolean; service: string };
    expect(body.ok).toBe(true);
    expect(body.service).toBe('pulse-signaling');
  });
});
