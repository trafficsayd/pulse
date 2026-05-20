# Pulse signaling Worker

A small Cloudflare Worker that acts as a rendezvous broker between two
Pulse peers behind separate NATs. The Worker only relays opaque SDP and
ICE messages — payload bytes are end-to-end encrypted by the app on top
of DTLS-SRTP, so this server cannot see anything sensitive.

## Routes

| Method | Path | Auth | Purpose |
| ------ | ---- | ---- | ------- |
| `POST` | `/session` | none | Create a new signaling session. Body: `{ "pairingCode": "..." }`. Returns `{ sessionId, token, expiresAt }`. |
| `POST` | `/session/:id/offer` | bearer | Store the SDP offer (and optional initial ICE candidates). |
| `GET`  | `/session/:id/offer` | bearer | Read the stored offer. `204` if not yet posted. |
| `POST` | `/session/:id/answer` | bearer | Store the SDP answer. |
| `GET`  | `/session/:id/answer` | bearer | Read the stored answer. `204` if not yet posted. |
| `POST` | `/session/:id/ice` | bearer | Append one trickle-ICE candidate. |
| `GET`  | `/session/:id/ice?since=N` | bearer | Long-poll (up to 25 s) for ICE candidates after cursor `N`. Returns `204` on timeout. |
| `GET`  | `/health` | none | Liveness probe. |

### Auth model

`POST /session` returns a short-lived HMAC-SHA-256 bearer token of the form

```
base64url(sessionId) "." base64url(expiresAt) "." base64url(hmac)
```

signed with the Worker's `WORKER_SECRET`. Every subsequent request must
include `Authorization: Bearer <token>` and the token must match the
session id in the URL. Tokens expire when the session expires (10 min
after creation).

### TTL

Every KV entry tied to a session is written with `expirationTtl: 600`
(10 minutes). Expired entries vanish from KV and any further requests
respond with `404 session_not_found`.

### Rate limit

At most **30 requests per minute per IP** (read from `cf-connecting-ip`).
Implemented as a sliding-window counter in KV across two 60-second
buckets. The `/health` probe is intentionally excluded so external
monitoring is not throttled.

## Deploy

```bash
# One-time: create the KV namespace this Worker depends on.
wrangler kv:namespace create SIGNALING_SESSIONS
wrangler kv:namespace create SIGNALING_SESSIONS --preview
# Paste the returned ids into wrangler.toml (`id` and `preview_id`).

# Set the HMAC key used to sign session tokens.
wrangler secret put WORKER_SECRET

# Deploy.
wrangler deploy
```

`wrangler.toml` also exposes a few tunable variables under `[vars]`:

| Var | Default | Description |
| --- | ------- | ----------- |
| `ICE_LONG_POLL_TIMEOUT_MS` | `25000` | Max time `GET /session/:id/ice` will hold the request open. |
| `ICE_LONG_POLL_INTERVAL_MS` | `500` | Poll interval inside the long-poll loop. |
| `RATE_LIMIT_PER_MINUTE` | `30` | Per-IP request budget. |
| `SESSION_TTL_SECONDS` | `600` | TTL applied to every KV entry. |

## Local development

```bash
npm install
echo "WORKER_SECRET=local-dev-secret" > .dev.vars
npm run dev
```

`.dev.vars` is gitignored — never commit a real `WORKER_SECRET`.

## Tests

```bash
npm test
```

Tests run against [`@cloudflare/vitest-pool-workers`](https://www.npmjs.com/package/@cloudflare/vitest-pool-workers),
which boots a Miniflare worker for each test file with an isolated KV
namespace. They cover happy-path session creation, offer/answer storage,
auth rejection, rate limiting and TTL expiry. 34 specs at the time of
writing.

## Lint / format

```bash
npm run lint           # ESLint, strict mode, max-warnings=0
npm run format:check   # Prettier
npm run typecheck      # tsc --noEmit
```
