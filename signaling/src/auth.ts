import type { TokenVerification } from './types';

/**
 * Token wire format:
 *
 *     base64url(sessionId) "." base64url(expiresAt) "." base64url(hmac)
 *
 * `hmac` is HMAC-SHA-256 over the literal bytes of
 * `base64url(sessionId) + "." + base64url(expiresAt)` keyed with
 * `WORKER_SECRET`. Constant-time comparison is used during verification.
 */

const encoder = new TextEncoder();

/** Base64url encode without padding. */
export function b64urlEncode(input: Uint8Array | string): string {
  const bytes = typeof input === 'string' ? encoder.encode(input) : input;
  let binary = '';
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]!);
  }
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
}

/** Base64url decode tolerant of missing padding. */
export function b64urlDecode(input: string): Uint8Array {
  const padded = input
    .replaceAll('-', '+')
    .replaceAll('_', '/')
    .padEnd(input.length + ((4 - (input.length % 4)) % 4), '=');
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

async function importHmacKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign', 'verify'],
  );
}

async function hmacSign(secret: string, message: string): Promise<Uint8Array> {
  const key = await importHmacKey(secret);
  const sig = await crypto.subtle.sign('HMAC', key, encoder.encode(message));
  return new Uint8Array(sig);
}

/**
 * Constant-time byte comparison. Returning early on length mismatch is safe
 * because the length of a SHA-256 HMAC is fixed and known to attackers.
 */
function timingSafeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.byteLength !== b.byteLength) {
    return false;
  }
  let diff = 0;
  for (let i = 0; i < a.byteLength; i++) {
    diff |= (a[i] ?? 0) ^ (b[i] ?? 0);
  }
  return diff === 0;
}

/**
 * Mint a bearer token for `sessionId` that expires at `expiresAtMs`
 * (millisecond epoch). The signature covers both fields so changing either
 * one in transit invalidates the token.
 */
export async function signToken(
  secret: string,
  sessionId: string,
  expiresAtMs: number,
): Promise<string> {
  const sid = b64urlEncode(sessionId);
  const exp = b64urlEncode(expiresAtMs.toString());
  const sig = await hmacSign(secret, `${sid}.${exp}`);
  return `${sid}.${exp}.${b64urlEncode(sig)}`;
}

/**
 * Verify a bearer token against `WORKER_SECRET` and the current clock.
 *
 * When `expectedSessionId` is provided the token must also belong to that
 * session — used so a token issued for session A cannot be replayed against
 * session B.
 */
export async function verifyToken(
  secret: string,
  token: string,
  nowMs: number,
  expectedSessionId?: string,
): Promise<TokenVerification> {
  const parts = token.split('.');
  if (parts.length !== 3) {
    return { ok: false, reason: 'malformed' };
  }
  const [sidPart, expPart, sigPart] = parts;
  if (!sidPart || !expPart || !sigPart) {
    return { ok: false, reason: 'malformed' };
  }

  let sessionId: string;
  let expiresAt: number;
  let providedSig: Uint8Array;
  try {
    sessionId = new TextDecoder().decode(b64urlDecode(sidPart));
    const expStr = new TextDecoder().decode(b64urlDecode(expPart));
    expiresAt = Number.parseInt(expStr, 10);
    providedSig = b64urlDecode(sigPart);
  } catch {
    return { ok: false, reason: 'malformed' };
  }

  if (!Number.isFinite(expiresAt)) {
    return { ok: false, reason: 'malformed' };
  }
  if (expectedSessionId !== undefined && sessionId !== expectedSessionId) {
    return { ok: false, reason: 'session_mismatch' };
  }

  const expectedSig = await hmacSign(secret, `${sidPart}.${expPart}`);
  if (!timingSafeEqual(providedSig, expectedSig)) {
    return { ok: false, reason: 'bad_signature' };
  }
  if (nowMs >= expiresAt) {
    return { ok: false, reason: 'expired' };
  }

  return { ok: true, sessionId, expiresAt };
}

/**
 * Pull a `Bearer <token>` value out of the `Authorization` header.
 * Returns `null` if the header is missing or malformed.
 */
export function extractBearerToken(req: Request): string | null {
  const header = req.headers.get('authorization');
  if (!header) {
    return null;
  }
  const trimmed = header.trim();
  const lower = trimmed.toLowerCase();
  if (!lower.startsWith('bearer ')) {
    return null;
  }
  const token = trimmed.slice('bearer '.length).trim();
  return token.length > 0 ? token : null;
}
