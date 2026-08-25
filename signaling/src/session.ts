import type {
  AnswerPayload,
  Env,
  IceCandidate,
  IcePayload,
  OfferPayload,
  RelayMessage,
  RelayMessagePayload,
  SignalingSession,
} from './types';
import { appendD1IceCandidate, readD1IceCandidatesSince, signalingStore } from './storage';

/**
 * KV key helpers. All keys are namespaced so a single `SIGNALING_SESSIONS`
 * namespace can hold every kind of per-session record without collisions.
 */
const KEY = {
  session: (id: string): string => `session:${id}`,
  pairing: (hash: string): string => `pairing:${hash}`,
  offer: (id: string): string => `offer:${id}`,
  answer: (id: string): string => `answer:${id}`,
  ice: (id: string): string => `ice:${id}`,
  messages: (id: string): string => `messages:${id}`,
};

const encoder = new TextEncoder();

function ttlSeconds(env: Env): number {
  const raw = env.SESSION_TTL_SECONDS;
  if (!raw) {
    return 600;
  }
  const n = Number.parseInt(raw, 10);
  return Number.isFinite(n) && n > 0 ? n : 600;
}

/**
 * Generate a 128-bit random id encoded as 32 lowercase hex chars.
 */
export function newSessionId(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  let out = '';
  for (const b of bytes) {
    out += b.toString(16).padStart(2, '0');
  }
  return out;
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', encoder.encode(value));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export async function createSession(
  env: Env,
  pairingCode: string,
  clientId?: string,
  nowMs: number = Date.now(),
): Promise<{ session: SignalingSession; isInitiator: boolean }> {
  const ttl = ttlSeconds(env);
  const pairingKey = KEY.pairing(await sha256Hex(pairingCode));
  const existingId = await signalingStore(env).get(pairingKey);
  if (existingId) {
    const existing = await getSession(env, existingId);
    if (existing) {
      const lastOffer = clientId ? await getOffer(env, existing.sessionId) : null;
      const offerIsStale = lastOffer
        ? nowMs - lastOffer.storedAt > 30_000
        : nowMs - existing.createdAt > 30_000;
      if (
        clientId &&
        (!existing.initiatorClientId || (existing.initiatorClientId !== clientId && offerIsStale))
      ) {
        existing.initiatorClientId = clientId;
        await signalingStore(env).put(KEY.session(existing.sessionId), JSON.stringify(existing), {
          expirationTtl: Math.max(1, Math.ceil((existing.expiresAt - nowMs) / 1000)),
        });
      }
      return {
        session: existing,
        isInitiator: clientId ? existing.initiatorClientId === clientId : false,
      };
    }
  }

  const session: SignalingSession = {
    sessionId: newSessionId(),
    pairingCode,
    createdAt: nowMs,
    expiresAt: nowMs + ttl * 1000,
    ...(clientId ? { initiatorClientId: clientId } : {}),
  };
  await signalingStore(env).put(KEY.session(session.sessionId), JSON.stringify(session), {
    expirationTtl: ttl,
  });
  await signalingStore(env).put(pairingKey, session.sessionId, {
    expirationTtl: ttl,
  });
  return { session, isInitiator: true };
}

export async function getSession(env: Env, sessionId: string): Promise<SignalingSession | null> {
  const raw = await signalingStore(env).get(KEY.session(sessionId));
  if (!raw) {
    return null;
  }
  try {
    return JSON.parse(raw) as SignalingSession;
  } catch {
    return null;
  }
}

export async function storeOffer(
  env: Env,
  sessionId: string,
  payload: OfferPayload,
): Promise<void> {
  await signalingStore(env).put(KEY.offer(sessionId), JSON.stringify(payload), {
    expirationTtl: ttlSeconds(env),
  });
}

export async function getOffer(env: Env, sessionId: string): Promise<OfferPayload | null> {
  const raw = await signalingStore(env).get(KEY.offer(sessionId));
  if (!raw) {
    return null;
  }
  try {
    return JSON.parse(raw) as OfferPayload;
  } catch {
    return null;
  }
}

export async function storeAnswer(
  env: Env,
  sessionId: string,
  payload: AnswerPayload,
): Promise<void> {
  await signalingStore(env).put(KEY.answer(sessionId), JSON.stringify(payload), {
    expirationTtl: ttlSeconds(env),
  });
}

export async function getAnswer(env: Env, sessionId: string): Promise<AnswerPayload | null> {
  const raw = await signalingStore(env).get(KEY.answer(sessionId));
  if (!raw) {
    return null;
  }
  try {
    return JSON.parse(raw) as AnswerPayload;
  } catch {
    return null;
  }
}

/**
 * Read the full ICE list. Empty list when nothing has been stored yet.
 */
export async function readIce(env: Env, sessionId: string): Promise<IceCandidate[]> {
  const raw = await signalingStore(env).get(KEY.ice(sessionId));
  if (!raw) {
    return [];
  }
  try {
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) {
      return [];
    }
    return parsed as IceCandidate[];
  } catch {
    return [];
  }
}

/**
 * Append a new ICE candidate to the per-session list and return the updated
 * cursor (= new list length).
 *
 * KV is last-write-wins; concurrent appends from two peers in the same
 * millisecond may drop one entry, which is acceptable because peers retry the
 * gathering loop. We keep the implementation deliberately simple — no
 * Durable Object is needed for this signaling volume.
 */
export async function appendIce(
  env: Env,
  sessionId: string,
  candidate: IceCandidate,
): Promise<number> {
  const d1Cursor = await appendD1IceCandidate(
    env,
    sessionId,
    JSON.stringify(candidate),
    ttlSeconds(env),
  );
  if (d1Cursor !== null) return d1Cursor;
  const current = await readIce(env, sessionId);
  current.push(candidate);
  await signalingStore(env).put(KEY.ice(sessionId), JSON.stringify(current), {
    expirationTtl: ttlSeconds(env),
  });
  return current.length;
}

/**
 * Return any ICE candidates added strictly after `since`. Used by the
 * long-poll endpoint to incrementally feed candidates to the peer.
 */
export async function readIceSince(
  env: Env,
  sessionId: string,
  since: number,
): Promise<IcePayload> {
  const safeSince = Number.isFinite(since) && since >= 0 ? Math.floor(since) : 0;
  const d1Rows = await readD1IceCandidatesSince(env, sessionId, safeSince);
  if (d1Rows !== null) {
    const candidates = d1Rows.flatMap((row) => {
      try {
        return [JSON.parse(row.value) as IceCandidate];
      } catch {
        return [];
      }
    });
    const cursor = d1Rows.length > 0 ? d1Rows.at(-1)!.cursor : safeSince;
    return { candidates, cursor };
  }
  const all = await readIce(env, sessionId);
  const cursor = all.length;
  if (safeSince >= cursor) {
    return { candidates: [], cursor };
  }
  return { candidates: all.slice(safeSince), cursor };
}

/**
 * Read the full relay message list. Empty list when nothing has been stored
 * yet. These are encrypted app packets, not SDP/ICE metadata.
 */
export async function readMessages(env: Env, sessionId: string): Promise<RelayMessage[]> {
  const raw = await signalingStore(env).get(KEY.messages(sessionId));
  if (!raw) {
    return [];
  }
  try {
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) {
      return [];
    }
    return parsed as RelayMessage[];
  } catch {
    return [];
  }
}

/**
 * Append one encrypted application packet to the session relay stream.
 *
 * KV is last-write-wins, so this remains best-effort under simultaneous
 * writes. Pulse mode events are already ephemeral; missed beats are allowed.
 */
export async function appendMessage(
  env: Env,
  sessionId: string,
  message: RelayMessage,
): Promise<number> {
  const current = await readMessages(env, sessionId);
  current.push(message);
  await signalingStore(env).put(KEY.messages(sessionId), JSON.stringify(current), {
    expirationTtl: ttlSeconds(env),
  });
  return current.length;
}

/**
 * Return relay messages added strictly after `since`.
 */
export async function readMessagesSince(
  env: Env,
  sessionId: string,
  since: number,
): Promise<RelayMessagePayload> {
  const all = await readMessages(env, sessionId);
  const safeSince = Number.isFinite(since) && since >= 0 ? Math.floor(since) : 0;
  const cursor = all.length;
  if (safeSince >= cursor) {
    return { messages: [], cursor };
  }
  return { messages: all.slice(safeSince), cursor };
}
