import { SELF } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';

const HEAVY_IP = '198.51.100.42';
const QUIET_IP = '198.51.100.43';

/**
 * Hit `POST /session` with the supplied IP. We use this everywhere because
 * the unauthenticated `/health` probe is intentionally excluded from the
 * rate-limit middleware — only routes that actually touch state are gated.
 */
async function hit(ip: string): Promise<number> {
  const r = await SELF.fetch('https://signaling.test/session', {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'cf-connecting-ip': ip },
    body: JSON.stringify({ pairingCode: 'abcd' }),
  });
  return r.status;
}

describe('rate limit', () => {
  it('allows ~30 requests per minute and then rate-limits the IP', async () => {
    // KV is eventually consistent (it is in production too), so we do not
    // demand a perfectly tight 30/31 boundary. We do require that after a
    // burst the bucket eventually trips 429 and that we stay within `2*limit`
    // requests of the configured threshold.
    const limit = 30;
    let firstRejectedAt = -1;
    let allowed = 0;
    for (let i = 0; i < 80; i++) {
      const status = await hit(HEAVY_IP);
      if (status === 201) {
        allowed++;
      } else if (status === 429) {
        firstRejectedAt = i;
        break;
      } else {
        throw new Error(`unexpected status ${status}`);
      }
    }
    expect(firstRejectedAt).toBeGreaterThanOrEqual(0);
    expect(allowed).toBeGreaterThanOrEqual(limit - 5);
    expect(allowed).toBeLessThanOrEqual(limit * 2);

    expect(await hit(HEAVY_IP)).toBe(429);
  });

  it('does not penalise a different IP', async () => {
    // Burn through the heavy IP's budget…
    for (let i = 0; i < 40; i++) {
      const status = await hit(HEAVY_IP);
      if (status === 429) {
        break;
      }
    }
    // …and confirm the quiet IP still works.
    expect(await hit(QUIET_IP)).toBe(201);
  });

  it('rate-limits POST /session, the only unauthenticated mutating route', async () => {
    const ip = '198.51.100.99';
    let lastStatus = 0;
    for (let i = 0; i < 80; i++) {
      lastStatus = await hit(ip);
      if (lastStatus === 429) {
        break;
      }
    }
    expect(lastStatus).toBe(429);
  });
});
