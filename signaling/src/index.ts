import { extractBearerToken, signToken, verifyToken } from './auth';
import { checkAndIncrementRateLimit } from './rate_limit';
import {
  appendIce,
  createSession,
  getAnswer,
  getOffer,
  getSession,
  readIceSince,
  storeAnswer,
  storeOffer,
} from './session';
import type {
  AnswerPayload,
  CreateSessionRequest,
  CreateSessionResponse,
  Env,
  IceCandidate,
  IcePayload,
  OfferPayload,
} from './types';

/**
 * Pulse signaling Worker.
 *
 * This Worker is a thin rendezvous broker. It never sees decrypted payload
 * bytes — it only relays SDP and ICE candidates between two opaque sessions
 * so that two devices behind separate NATs can establish a direct WebRTC
 * connection. Sessions auto-expire after 10 minutes and every endpoint is
 * gated by a short-lived HMAC bearer token.
 */

const JSON_HEADERS = { 'content-type': 'application/json; charset=utf-8' } as const;

function json(body: unknown, init: ResponseInit = {}): Response {
  return new Response(JSON.stringify(body), {
    ...init,
    headers: { ...JSON_HEADERS, ...(init.headers ?? {}) },
  });
}

function errorJson(status: number, code: string, message: string): Response {
  return json({ error: code, message }, { status });
}

function poll(intervalMs: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, intervalMs));
}

function parseLongPollTimeoutMs(env: Env): number {
  const raw = env.ICE_LONG_POLL_TIMEOUT_MS;
  if (!raw) {
    return 25_000;
  }
  const n = Number.parseInt(raw, 10);
  return Number.isFinite(n) && n > 0 ? n : 25_000;
}

function parseLongPollIntervalMs(env: Env): number {
  const raw = env.ICE_LONG_POLL_INTERVAL_MS;
  if (!raw) {
    return 500;
  }
  const n = Number.parseInt(raw, 10);
  return Number.isFinite(n) && n > 0 ? n : 500;
}

/**
 * Validate that the request body is a JSON object and return it as `unknown`
 * so callers can narrow it themselves.
 */
async function readJsonBody(req: Request): Promise<unknown> {
  if (req.headers.get('content-type')?.includes('application/json') !== true) {
    throw new SyntaxError('content-type must be application/json');
  }
  return req.json();
}

function isString(value: unknown): value is string {
  return typeof value === 'string';
}

function asIceCandidate(value: unknown): IceCandidate | null {
  if (typeof value !== 'object' || value === null) {
    return null;
  }
  const v = value as Record<string, unknown>;
  if (typeof v['candidate'] !== 'string') {
    return null;
  }
  const out: IceCandidate = { candidate: v['candidate'] };
  if (v['sdpMid'] === null || typeof v['sdpMid'] === 'string') {
    out.sdpMid = v['sdpMid'] as string | null;
  }
  if (v['sdpMLineIndex'] === null || typeof v['sdpMLineIndex'] === 'number') {
    out.sdpMLineIndex = v['sdpMLineIndex'] as number | null;
  }
  if (v['usernameFragment'] === null || typeof v['usernameFragment'] === 'string') {
    out.usernameFragment = v['usernameFragment'] as string | null;
  }
  return out;
}

function asIceCandidateList(value: unknown): IceCandidate[] | null {
  if (!Array.isArray(value)) {
    return null;
  }
  const out: IceCandidate[] = [];
  for (const item of value) {
    const candidate = asIceCandidate(item);
    if (!candidate) {
      return null;
    }
    out.push(candidate);
  }
  return out;
}

async function requireAuth(
  env: Env,
  req: Request,
  sessionId: string,
  nowMs: number,
): Promise<Response | null> {
  const token = extractBearerToken(req);
  if (!token) {
    return errorJson(401, 'missing_token', 'Authorization: Bearer <token> required');
  }
  const verification = await verifyToken(env.WORKER_SECRET, token, nowMs, sessionId);
  if (!verification.ok) {
    const code = verification.reason;
    const status = code === 'expired' ? 401 : 403;
    return errorJson(status, code, `token rejected: ${code}`);
  }
  // Token is valid and belongs to this session.
  return null;
}

/**
 * Extract a positive integer query parameter, returning a fallback when the
 * parameter is missing or malformed.
 */
function intQuery(url: URL, name: string, fallback: number): number {
  const raw = url.searchParams.get(name);
  if (raw === null) {
    return fallback;
  }
  const n = Number.parseInt(raw, 10);
  return Number.isFinite(n) && n >= 0 ? n : fallback;
}

interface RouteContext {
  env: Env;
  request: Request;
  url: URL;
  nowMs: number;
}

async function handleCreateSession(ctx: RouteContext): Promise<Response> {
  let body: unknown;
  try {
    body = await readJsonBody(ctx.request);
  } catch {
    return errorJson(400, 'bad_body', 'expected JSON body with `pairingCode`');
  }
  if (typeof body !== 'object' || body === null) {
    return errorJson(400, 'bad_body', 'expected JSON object');
  }
  const { pairingCode } = body as Partial<CreateSessionRequest>;
  if (!isString(pairingCode) || pairingCode.length === 0 || pairingCode.length > 64) {
    return errorJson(400, 'bad_pairing_code', '`pairingCode` must be a 1..64 char string');
  }

  const session = await createSession(ctx.env, pairingCode, ctx.nowMs);
  const token = await signToken(ctx.env.WORKER_SECRET, session.sessionId, session.expiresAt);
  const response: CreateSessionResponse = {
    sessionId: session.sessionId,
    token,
    expiresAt: session.expiresAt,
  };
  return json(response, { status: 201 });
}

async function handlePostOffer(ctx: RouteContext, sessionId: string): Promise<Response> {
  const authFailure = await requireAuth(ctx.env, ctx.request, sessionId, ctx.nowMs);
  if (authFailure) {
    return authFailure;
  }
  const session = await getSession(ctx.env, sessionId);
  if (!session) {
    return errorJson(404, 'session_not_found', 'session does not exist or has expired');
  }

  let body: unknown;
  try {
    body = await readJsonBody(ctx.request);
  } catch {
    return errorJson(400, 'bad_body', 'expected JSON body with `sdp`');
  }
  if (typeof body !== 'object' || body === null) {
    return errorJson(400, 'bad_body', 'expected JSON object');
  }
  const { sdp, ice } = body as { sdp?: unknown; ice?: unknown };
  if (!isString(sdp) || sdp.length === 0) {
    return errorJson(400, 'bad_sdp', '`sdp` must be a non-empty string');
  }
  let parsedIce: IceCandidate[] | undefined;
  if (ice !== undefined) {
    const list = asIceCandidateList(ice);
    if (!list) {
      return errorJson(400, 'bad_ice', '`ice` must be an array of ICE candidates');
    }
    parsedIce = list;
  }
  const payload: OfferPayload = {
    type: 'offer',
    sdp,
    storedAt: ctx.nowMs,
    ...(parsedIce ? { ice: parsedIce } : {}),
  };
  await storeOffer(ctx.env, sessionId, payload);
  return json({ ok: true }, { status: 200 });
}

async function handleGetOffer(ctx: RouteContext, sessionId: string): Promise<Response> {
  const authFailure = await requireAuth(ctx.env, ctx.request, sessionId, ctx.nowMs);
  if (authFailure) {
    return authFailure;
  }
  const session = await getSession(ctx.env, sessionId);
  if (!session) {
    return errorJson(404, 'session_not_found', 'session does not exist or has expired');
  }
  const offer = await getOffer(ctx.env, sessionId);
  if (!offer) {
    return new Response(null, { status: 204 });
  }
  return json(offer, { status: 200 });
}

async function handlePostAnswer(ctx: RouteContext, sessionId: string): Promise<Response> {
  const authFailure = await requireAuth(ctx.env, ctx.request, sessionId, ctx.nowMs);
  if (authFailure) {
    return authFailure;
  }
  const session = await getSession(ctx.env, sessionId);
  if (!session) {
    return errorJson(404, 'session_not_found', 'session does not exist or has expired');
  }

  let body: unknown;
  try {
    body = await readJsonBody(ctx.request);
  } catch {
    return errorJson(400, 'bad_body', 'expected JSON body with `sdp`');
  }
  if (typeof body !== 'object' || body === null) {
    return errorJson(400, 'bad_body', 'expected JSON object');
  }
  const { sdp, ice } = body as { sdp?: unknown; ice?: unknown };
  if (!isString(sdp) || sdp.length === 0) {
    return errorJson(400, 'bad_sdp', '`sdp` must be a non-empty string');
  }
  let parsedIce: IceCandidate[] | undefined;
  if (ice !== undefined) {
    const list = asIceCandidateList(ice);
    if (!list) {
      return errorJson(400, 'bad_ice', '`ice` must be an array of ICE candidates');
    }
    parsedIce = list;
  }
  const payload: AnswerPayload = {
    type: 'answer',
    sdp,
    storedAt: ctx.nowMs,
    ...(parsedIce ? { ice: parsedIce } : {}),
  };
  await storeAnswer(ctx.env, sessionId, payload);
  return json({ ok: true }, { status: 200 });
}

async function handleGetAnswer(ctx: RouteContext, sessionId: string): Promise<Response> {
  const authFailure = await requireAuth(ctx.env, ctx.request, sessionId, ctx.nowMs);
  if (authFailure) {
    return authFailure;
  }
  const session = await getSession(ctx.env, sessionId);
  if (!session) {
    return errorJson(404, 'session_not_found', 'session does not exist or has expired');
  }
  const answer = await getAnswer(ctx.env, sessionId);
  if (!answer) {
    return new Response(null, { status: 204 });
  }
  return json(answer, { status: 200 });
}

async function handlePostIce(ctx: RouteContext, sessionId: string): Promise<Response> {
  const authFailure = await requireAuth(ctx.env, ctx.request, sessionId, ctx.nowMs);
  if (authFailure) {
    return authFailure;
  }
  const session = await getSession(ctx.env, sessionId);
  if (!session) {
    return errorJson(404, 'session_not_found', 'session does not exist or has expired');
  }

  let body: unknown;
  try {
    body = await readJsonBody(ctx.request);
  } catch {
    return errorJson(400, 'bad_body', 'expected JSON body with `candidate`');
  }
  const candidate = asIceCandidate(body);
  if (!candidate) {
    return errorJson(400, 'bad_candidate', 'expected an ICE candidate object');
  }
  const cursor = await appendIce(ctx.env, sessionId, candidate);
  return json({ ok: true, cursor }, { status: 200 });
}

async function handleGetIce(ctx: RouteContext, sessionId: string): Promise<Response> {
  const authFailure = await requireAuth(ctx.env, ctx.request, sessionId, ctx.nowMs);
  if (authFailure) {
    return authFailure;
  }
  const session = await getSession(ctx.env, sessionId);
  if (!session) {
    return errorJson(404, 'session_not_found', 'session does not exist or has expired');
  }

  const since = intQuery(ctx.url, 'since', 0);
  const timeoutMs = parseLongPollTimeoutMs(ctx.env);
  const intervalMs = parseLongPollIntervalMs(ctx.env);
  const deadline = ctx.nowMs + timeoutMs;

  let payload: IcePayload = await readIceSince(ctx.env, sessionId, since);
  while (payload.candidates.length === 0 && Date.now() < deadline) {
    await poll(intervalMs);
    payload = await readIceSince(ctx.env, sessionId, since);
  }
  if (payload.candidates.length === 0) {
    return new Response(null, { status: 204 });
  }
  return json(payload, { status: 200 });
}

interface RouteMatch {
  handler: (ctx: RouteContext, sessionId: string) => Promise<Response>;
  sessionId: string;
}

function matchSessionRoute(method: string, pathname: string): RouteMatch | null {
  // /session/:id/(offer|answer|ice)
  const match = /^\/session\/([0-9a-fA-F]{6,64})\/(offer|answer|ice)$/.exec(pathname);
  if (!match) {
    return null;
  }
  const sessionId = match[1]!;
  const sub = match[2]!;
  if (sub === 'offer' && method === 'POST') {
    return { handler: handlePostOffer, sessionId };
  }
  if (sub === 'offer' && method === 'GET') {
    return { handler: handleGetOffer, sessionId };
  }
  if (sub === 'answer' && method === 'POST') {
    return { handler: handlePostAnswer, sessionId };
  }
  if (sub === 'answer' && method === 'GET') {
    return { handler: handleGetAnswer, sessionId };
  }
  if (sub === 'ice' && method === 'POST') {
    return { handler: handlePostIce, sessionId };
  }
  if (sub === 'ice' && method === 'GET') {
    return { handler: handleGetIce, sessionId };
  }
  return null;
}

async function handle(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const nowMs = Date.now();
  const ctx: RouteContext = { env, request, url, nowMs };

  if (url.pathname === '/health' && request.method === 'GET') {
    return json({ ok: true, service: 'pulse-signaling' });
  }

  // Rate limit ALL routes — including unmatched ones — so probing 404s cannot
  // bypass the per-IP cap.
  const decision = await checkAndIncrementRateLimit(env, request, nowMs);
  if (!decision.allowed) {
    return errorJson(429, 'rate_limited', `over ${decision.limit} req/min for this IP`);
  }

  if (url.pathname === '/session' && request.method === 'POST') {
    return handleCreateSession(ctx);
  }

  const match = matchSessionRoute(request.method, url.pathname);
  if (match) {
    return match.handler(ctx, match.sessionId);
  }

  return errorJson(404, 'not_found', `${request.method} ${url.pathname} is not a signaling route`);
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      return await handle(request, env);
    } catch (err) {
      console.error('signaling worker uncaught error', err);
      return errorJson(500, 'internal_error', 'unexpected signaling worker failure');
    }
  },
} satisfies ExportedHandler<Env>;
