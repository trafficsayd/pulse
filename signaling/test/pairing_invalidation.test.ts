import { SELF } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';
import { authHeaders, callCreateSession } from './helpers';

/**
 * V6 — the pairing code must be retired once a pair has completed its SDP
 * exchange (an answer was posted), so a third party who later guesses the
 * same 6-digit code cannot be brokered into an already-established pairing.
 */
describe('V6 pairing-code invalidation', () => {
  async function post(path: string, token: string, body: unknown): Promise<number> {
    const res = await SELF.fetch(`https://signaling.test${path}`, {
      method: 'POST',
      headers: authHeaders(token),
      body: JSON.stringify(body),
    });
    return res.status;
  }

  it('mints a NEW session for the same code after an answer is posted', async () => {
    const code = '424242';
    const first = await callCreateSession(code);
    expect(first.status).toBe(201);
    const { sessionId, token } = first.body;

    expect(await post(`/session/${sessionId}/offer`, token, { sdp: 'v=0 offer' })).toBe(200);
    expect(await post(`/session/${sessionId}/answer`, token, { sdp: 'v=0 answer' })).toBe(200);

    // Code is now retired → a fresh createSession must not rejoin the old one.
    const second = await callCreateSession(code);
    expect(second.status).toBe(201);
    expect(second.body.sessionId).not.toBe(sessionId);
  });

  it('still lets both peers share the session before the answer arrives', async () => {
    const code = '515151';
    const a = await callCreateSession(code);
    expect(await post(`/session/${a.body.sessionId}/offer`, a.body.token, { sdp: 'v=0 offer' }))
      .toBe(200);
    // Guest joins with the same code before any answer — must get the SAME session.
    const b = await callCreateSession(code);
    expect(b.body.sessionId).toBe(a.body.sessionId);
  });
});
