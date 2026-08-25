/**
 * Public TypeScript types for the Pulse signaling Worker.
 *
 * The shapes here are stable wire contracts. Bumping any required field is a
 * breaking change for the Dart client and the on-device pairing flow.
 */

/**
 * Cloudflare environment bindings injected into every Worker invocation.
 *
 * KV: `SIGNALING_SESSIONS` stores every piece of per-session state (the
 * session record itself, offers, answers, ICE candidate lists, rate-limit
 * counters). Keys carry their own namespace prefix so we can fit several
 * logical "tables" inside one KV.
 */
export interface Env {
  SIGNALING_SESSIONS: KVNamespace;
  /** Primary signaling store. D1 replaces the much smaller KV write quota. */
  SIGNALING_DB?: D1Database;
  /** Test-only escape hatch so isolated Vitest cases keep using ephemeral KV. */
  USE_KV_FOR_TESTS?: string;
  /** HMAC-SHA-256 key used to sign per-session bearer tokens. */
  WORKER_SECRET: string;
  /** Cloudflare Realtime TURN key id (server-side only). */
  TURN_KEY_ID?: string;
  /** Secret API token belonging to TURN_KEY_ID (server-side only). */
  TURN_KEY_API_TOKEN?: string;
  /** Maximum time `GET /session/:id/ice` will block waiting for new ICE. */
  ICE_LONG_POLL_TIMEOUT_MS?: string;
  /** Poll interval used inside the long-poll loop. */
  ICE_LONG_POLL_INTERVAL_MS?: string;
  /** Max requests/minute/IP enforced via a sliding-window counter in KV. */
  RATE_LIMIT_PER_MINUTE?: string;
  /** TTL applied to every KV entry tied to a session. */
  SESSION_TTL_SECONDS?: string;
}

/**
 * One signaling session record.
 *
 * Stored under `session:<sessionId>` in KV with `expirationTtl` matching the
 * session TTL. Once the entry expires both peers drop back to the pairing
 * screen automatically.
 */
export interface SignalingSession {
  /** Random 128-bit id (hex). */
  sessionId: string;
  /** Short pairing code the two peers visually confirm out-of-band. */
  pairingCode: string;
  /** Millisecond epoch at which the session was created. */
  createdAt: number;
  /** Millisecond epoch at which the session and its token expire. */
  expiresAt: number;
  /** Stable app-instance id that owns the offer role across reconnects. */
  initiatorClientId?: string;
}

/**
 * SDP offer sent by the initiating peer.
 *
 * `sdp` is the raw offer string returned by `RTCPeerConnection.createOffer()`;
 * the worker treats it as opaque text and never parses it.
 */
export interface OfferPayload {
  /** `offer` for now — kept explicit to make the wire schema self-describing. */
  type: 'offer';
  /** Raw SDP. */
  sdp: string;
  senderId?: string;
  negotiationId?: string;
  /** Optional trickle-ICE candidates included with the offer. */
  ice?: IceCandidate[];
  /** Millisecond epoch at which the offer was stored. */
  storedAt: number;
}

/**
 * SDP answer sent by the receiving peer.
 */
export interface AnswerPayload {
  type: 'answer';
  sdp: string;
  senderId?: string;
  negotiationId?: string;
  ice?: IceCandidate[];
  storedAt: number;
}

/**
 * Trickle-ICE candidate envelope.
 */
export interface IceCandidate {
  /** Standard ICE candidate string (`candidate:...`). */
  candidate: string;
  /** SDP media id this candidate belongs to. */
  sdpMid?: string | null;
  /** Index of the m-line this candidate belongs to. */
  sdpMLineIndex?: number | null;
  /** Optional username fragment for ICE restart. */
  usernameFragment?: string | null;
  /** Random per-app-instance id used to ignore reflected candidates. */
  senderId?: string;
  negotiationId?: string;
}

/**
 * Wire shape used by both `POST /session/:id/ice` and the long-poll
 * `GET /session/:id/ice` response. The list is monotonically growing inside
 * KV; the client tracks the index it has consumed via `?since=`.
 */
export interface IcePayload {
  candidates: IceCandidate[];
  /** Cursor the client should send back as `?since=` on the next long-poll. */
  cursor: number;
}

/**
 * End-to-end encrypted application packet relayed through the Worker.
 *
 * The Worker treats `payload` as opaque base64 text. Decryption and replay
 * protection happen on-device in PairChannel, so this relay does not need to
 * understand mode events or user data.
 */
export interface RelayMessage {
  /** Random per-client id so a peer can ignore its own reflected packets. */
  senderId: string;
  /** Opaque packet kind carried by the Dart transport layer. */
  kind: string;
  /** Base64-encoded encrypted bytes. */
  payload: string;
  /** Millisecond epoch at which the packet was stored. */
  storedAt: number;
}

/**
 * Long-poll payload for `GET /session/:id/messages`.
 */
export interface RelayMessagePayload {
  messages: RelayMessage[];
  /** Cursor the client should send back as `?since=` on the next long-poll. */
  cursor: number;
}

/**
 * Payload returned by `POST /session`.
 */
export interface CreateSessionResponse {
  sessionId: string;
  token: string;
  expiresAt: number;
  /** First peer creates the offer; the joining peer creates the answer. */
  isInitiator: boolean;
}

/**
 * Compact body for `POST /session`.
 */
export interface CreateSessionRequest {
  pairingCode: string;
  /** Stable for the lifetime of one app process; used to preserve SDP role. */
  clientId?: string;
}

/** Result of verifying a bearer token. */
export type TokenVerification =
  | { ok: true; sessionId: string; expiresAt: number }
  | { ok: false; reason: 'malformed' | 'expired' | 'bad_signature' | 'session_mismatch' };
