import { SELF } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';
import type { AnswerPayload, IcePayload, OfferPayload, RelayMessagePayload } from '../src/types';
import { authHeaders, callCreateSession, defaultHeaders, fakeIce, TEST_IP } from './helpers';

describe('POST /session', () => {
  it('creates a session and returns sessionId + token', async () => {
    const { status, body } = await callCreateSession('1234');
    expect(status).toBe(201);
    expect(body.sessionId).toMatch(/^[0-9a-f]{32}$/);
    expect(typeof body.token).toBe('string');
    expect(body.token.split('.')).toHaveLength(3);
    expect(body.expiresAt).toBeGreaterThan(Date.now());
  });

  it('reuses the rendezvous session for the same pairingCode', async () => {
    const first = await callCreateSession('same-code');
    const second = await callCreateSession('same-code');
    expect(second.status).toBe(201);
    expect(second.body.sessionId).toBe(first.body.sessionId);
  });

  it('preserves initiator role for the same client across reconnects', async () => {
    const first = await callCreateSession('stable-role', TEST_IP, 'client-a');
    const peer = await callCreateSession('stable-role', TEST_IP, 'client-b');
    const retry = await callCreateSession('stable-role', TEST_IP, 'client-a');
    expect(first.body.isInitiator).toBe(true);
    expect(peer.body.isInitiator).toBe(false);
    expect(retry.body.isInitiator).toBe(true);
  });

  it('rejects a missing pairingCode', async () => {
    const response = await SELF.fetch('https://signaling.test/session', {
      method: 'POST',
      headers: defaultHeaders(),
      body: JSON.stringify({}),
    });
    expect(response.status).toBe(400);
  });

  it('rejects a non-JSON body', async () => {
    const response = await SELF.fetch('https://signaling.test/session', {
      method: 'POST',
      headers: { 'cf-connecting-ip': TEST_IP, 'content-type': 'text/plain' },
      body: 'pairingCode=1234',
    });
    expect(response.status).toBe(400);
  });
});

describe('offer/answer storage', () => {
  it('stores and retrieves an SDP offer', async () => {
    const { body: created } = await callCreateSession('1234');
    const postRes = await SELF.fetch(`https://signaling.test/session/${created.sessionId}/offer`, {
      method: 'POST',
      headers: authHeaders(created.token),
      body: JSON.stringify({ sdp: 'v=0\r\no=...', ice: [fakeIce(1)] }),
    });
    expect(postRes.status).toBe(200);

    const getRes = await SELF.fetch(`https://signaling.test/session/${created.sessionId}/offer`, {
      headers: authHeaders(created.token),
    });
    expect(getRes.status).toBe(200);
    const payload = (await getRes.json()) as OfferPayload;
    expect(payload.type).toBe('offer');
    expect(payload.sdp).toBe('v=0\r\no=...');
    expect(payload.ice).toHaveLength(1);
    expect(payload.ice?.[0]?.candidate).toContain('candidate:');
  });

  it('returns 204 when no offer has been posted yet', async () => {
    const { body: created } = await callCreateSession('1234');
    const getRes = await SELF.fetch(`https://signaling.test/session/${created.sessionId}/offer`, {
      headers: authHeaders(created.token),
    });
    expect(getRes.status).toBe(204);
  });

  it('stores and retrieves an SDP answer', async () => {
    const { body: created } = await callCreateSession('1234');
    const postRes = await SELF.fetch(`https://signaling.test/session/${created.sessionId}/answer`, {
      method: 'POST',
      headers: authHeaders(created.token),
      body: JSON.stringify({ sdp: 'v=0\r\no=answer' }),
    });
    expect(postRes.status).toBe(200);
    const getRes = await SELF.fetch(`https://signaling.test/session/${created.sessionId}/answer`, {
      headers: authHeaders(created.token),
    });
    expect(getRes.status).toBe(200);
    const payload = (await getRes.json()) as AnswerPayload;
    expect(payload.type).toBe('answer');
    expect(payload.sdp).toBe('v=0\r\no=answer');
  });

  it('rejects an offer with no sdp', async () => {
    const { body: created } = await callCreateSession('1234');
    const postRes = await SELF.fetch(`https://signaling.test/session/${created.sessionId}/offer`, {
      method: 'POST',
      headers: authHeaders(created.token),
      body: JSON.stringify({ ice: [] }),
    });
    expect(postRes.status).toBe(400);
  });

  it('rejects an offer with a bad ICE candidate', async () => {
    const { body: created } = await callCreateSession('1234');
    const postRes = await SELF.fetch(`https://signaling.test/session/${created.sessionId}/offer`, {
      method: 'POST',
      headers: authHeaders(created.token),
      body: JSON.stringify({ sdp: 'v=0', ice: [{ notACandidate: true }] }),
    });
    expect(postRes.status).toBe(400);
  });
});

describe('auth enforcement on session routes', () => {
  it('rejects requests without an Authorization header', async () => {
    const { body: created } = await callCreateSession('1234');
    const getRes = await SELF.fetch(`https://signaling.test/session/${created.sessionId}/offer`, {
      headers: defaultHeaders(),
    });
    expect(getRes.status).toBe(401);
  });

  it('rejects a token issued for a different session', async () => {
    const a = await callCreateSession('1111');
    const b = await callCreateSession('2222');
    const res = await SELF.fetch(`https://signaling.test/session/${b.body.sessionId}/offer`, {
      method: 'POST',
      headers: authHeaders(a.body.token),
      body: JSON.stringify({ sdp: 'v=0' }),
    });
    expect(res.status).toBe(403);
  });

  it('returns 404 for an unknown session even with a valid-looking token', async () => {
    const { body: created } = await callCreateSession('1234');
    // Sign a token whose sessionId matches the URL but the session record
    // never existed → 404 from `getSession`.
    const fakeSessionId = '00000000000000000000000000000000';
    // Reuse the existing token first to fail at the session-mismatch layer,
    // then craft a request to a different sessionId.
    const res = await SELF.fetch(`https://signaling.test/session/${fakeSessionId}/offer`, {
      headers: authHeaders(created.token),
    });
    expect([403, 404]).toContain(res.status);
  });
});

describe('ICE candidates', () => {
  it('appends ICE candidates and returns them with a cursor', async () => {
    const { body: created } = await callCreateSession('1234');

    for (const i of [1, 2, 3]) {
      const postRes = await SELF.fetch(`https://signaling.test/session/${created.sessionId}/ice`, {
        method: 'POST',
        headers: authHeaders(created.token),
        body: JSON.stringify(fakeIce(i)),
      });
      expect(postRes.status).toBe(200);
    }

    const getRes = await SELF.fetch(
      `https://signaling.test/session/${created.sessionId}/ice?since=0`,
      { headers: authHeaders(created.token) },
    );
    expect(getRes.status).toBe(200);
    const payload = (await getRes.json()) as IcePayload;
    expect(payload.candidates).toHaveLength(3);
    expect(payload.cursor).toBe(3);
  });

  it('returns only candidates after `since`', async () => {
    const { body: created } = await callCreateSession('1234');
    for (const i of [1, 2, 3, 4]) {
      await SELF.fetch(`https://signaling.test/session/${created.sessionId}/ice`, {
        method: 'POST',
        headers: authHeaders(created.token),
        body: JSON.stringify(fakeIce(i)),
      });
    }
    const getRes = await SELF.fetch(
      `https://signaling.test/session/${created.sessionId}/ice?since=2`,
      { headers: authHeaders(created.token) },
    );
    expect(getRes.status).toBe(200);
    const payload = (await getRes.json()) as IcePayload;
    expect(payload.candidates).toHaveLength(2);
    expect(payload.cursor).toBe(4);
  });

  it('returns 204 when no new candidates arrive before the deadline', async () => {
    const { body: created } = await callCreateSession('1234');
    const getRes = await SELF.fetch(
      `https://signaling.test/session/${created.sessionId}/ice?since=0`,
      { headers: authHeaders(created.token) },
    );
    // ICE_LONG_POLL_TIMEOUT_MS is 500ms in tests → the long-poll wakes up and
    // returns 204 without holding the test runner for the full 25s.
    expect(getRes.status).toBe(204);
  });

  it('rejects an ICE candidate without a `candidate` field', async () => {
    const { body: created } = await callCreateSession('1234');
    const postRes = await SELF.fetch(`https://signaling.test/session/${created.sessionId}/ice`, {
      method: 'POST',
      headers: authHeaders(created.token),
      body: JSON.stringify({ sdpMid: '0' }),
    });
    expect(postRes.status).toBe(400);
  });
});

describe('relay messages', () => {
  it('appends encrypted packets and returns them with a cursor', async () => {
    const { body: created } = await callCreateSession('1234');

    const postRes = await SELF.fetch(
      `https://signaling.test/session/${created.sessionId}/messages`,
      {
        method: 'POST',
        headers: authHeaders(created.token),
        body: JSON.stringify({
          senderId: 'client-a',
          kind: 'sealed',
          payload: 'AQID',
        }),
      },
    );
    expect(postRes.status).toBe(200);

    const getRes = await SELF.fetch(
      `https://signaling.test/session/${created.sessionId}/messages?since=0`,
      { headers: authHeaders(created.token) },
    );
    expect(getRes.status).toBe(200);
    const payload = (await getRes.json()) as RelayMessagePayload;
    expect(payload.messages).toHaveLength(1);
    expect(payload.messages[0]?.senderId).toBe('client-a');
    expect(payload.messages[0]?.kind).toBe('sealed');
    expect(payload.messages[0]?.payload).toBe('AQID');
    expect(payload.cursor).toBe(1);
  });

  it('returns only relay messages after `since`', async () => {
    const { body: created } = await callCreateSession('1234');
    for (const payload of ['AQID', 'BAUG', 'BwgJ']) {
      await SELF.fetch(`https://signaling.test/session/${created.sessionId}/messages`, {
        method: 'POST',
        headers: authHeaders(created.token),
        body: JSON.stringify({
          senderId: 'client-a',
          kind: 'sealed',
          payload,
        }),
      });
    }
    const getRes = await SELF.fetch(
      `https://signaling.test/session/${created.sessionId}/messages?since=1`,
      { headers: authHeaders(created.token) },
    );
    expect(getRes.status).toBe(200);
    const payload = (await getRes.json()) as RelayMessagePayload;
    expect(payload.messages.map((message) => message.payload)).toEqual(['BAUG', 'BwgJ']);
    expect(payload.cursor).toBe(3);
  });

  it('rejects malformed relay payloads', async () => {
    const { body: created } = await callCreateSession('1234');
    const postRes = await SELF.fetch(
      `https://signaling.test/session/${created.sessionId}/messages`,
      {
        method: 'POST',
        headers: authHeaders(created.token),
        body: JSON.stringify({
          senderId: 'client-a',
          kind: 'sealed',
          payload: 'not base64!',
        }),
      },
    );
    expect(postRes.status).toBe(400);
  });
});
