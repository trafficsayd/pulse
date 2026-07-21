import { describe, expect, it } from 'vitest';
import { extractBearerToken, signToken, verifyToken } from '../src/auth';

const SECRET = 'unit-test-secret';

describe('auth.signToken / verifyToken', () => {
  it('round-trips a valid token', async () => {
    const expiresAt = Date.now() + 60_000;
    const token = await signToken(SECRET, 'sid-abc', expiresAt);
    const result = await verifyToken(SECRET, token, Date.now());
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.sessionId).toBe('sid-abc');
      expect(result.expiresAt).toBe(expiresAt);
    }
  });

  it('rejects an expired token', async () => {
    const expiresAt = Date.now() - 1_000;
    const token = await signToken(SECRET, 'sid-abc', expiresAt);
    const result = await verifyToken(SECRET, token, Date.now());
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.reason).toBe('expired');
    }
  });

  it('rejects a token signed with a different secret', async () => {
    const expiresAt = Date.now() + 60_000;
    const token = await signToken('other-secret', 'sid-abc', expiresAt);
    const result = await verifyToken(SECRET, token, Date.now());
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.reason).toBe('bad_signature');
    }
  });

  it('rejects a token whose session does not match', async () => {
    const expiresAt = Date.now() + 60_000;
    const token = await signToken(SECRET, 'sid-A', expiresAt);
    const result = await verifyToken(SECRET, token, Date.now(), 'sid-B');
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.reason).toBe('session_mismatch');
    }
  });

  it('rejects a malformed token', async () => {
    const result = await verifyToken(SECRET, 'not.a.token', Date.now());
    expect(result.ok).toBe(false);
  });

  it('rejects tokens with the wrong number of parts', async () => {
    const result = await verifyToken(SECRET, 'only-one-part', Date.now());
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.reason).toBe('malformed');
    }
  });
});

describe('auth.extractBearerToken', () => {
  it('extracts a bearer token', () => {
    const req = new Request('https://example.test', {
      headers: { authorization: 'Bearer abc.def.ghi' },
    });
    expect(extractBearerToken(req)).toBe('abc.def.ghi');
  });

  it('is case-insensitive on the `Bearer` keyword', () => {
    const req = new Request('https://example.test', {
      headers: { authorization: 'bearer abc.def.ghi' },
    });
    expect(extractBearerToken(req)).toBe('abc.def.ghi');
  });

  it('returns null when missing', () => {
    const req = new Request('https://example.test');
    expect(extractBearerToken(req)).toBeNull();
  });

  it('returns null when the scheme is wrong', () => {
    const req = new Request('https://example.test', {
      headers: { authorization: 'Basic abc' },
    });
    expect(extractBearerToken(req)).toBeNull();
  });
});
