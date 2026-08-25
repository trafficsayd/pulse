# `lib/features/transport/webrtc/`

WebRTC primitives used by `WebRtcTransport`. `native_peer.dart` is the narrow
adapter around `flutter_webrtc`; signaling and ICE models remain plain Dart so
the complete negotiation can be unit-tested with an in-memory peer.

## Contents

* `ice_servers.dart` — `kIceServers` and the `IceServer` model used to
  configure the WebRTC stack.
* `signaling_client.dart` — thin HTTP client that talks to the
  Cloudflare Worker in [`../../../../signaling/`](../../../../signaling/).
* `native_peer.dart` — native `RTCPeerConnection` / `RTCDataChannel` adapter.

## TURN credentials

Every connection starts with public STUN. The authenticated signaling Worker
then requests a short-lived Cloudflare TURN credential and adds it to the same
ICE configuration. Libwebrtc prefers host/STUN candidates and selects TURN only
when a firewall or NAT prevents direct P2P.

| URL | Purpose |
| --- | ------- |
| `stun:stun.l.google.com:19302` | Public Google STUN. |
| `stun:stun.cloudflare.com:3478` | Public Cloudflare STUN. |
| Cloudflare `turn:` / `turns:` URLs | Automatic fallback only. |

Configure production secrets on the Worker (never in the app binary):

To enable TURN in a real build, pass:

```sh
npx wrangler secret put TURN_KEY_ID
npx wrangler secret put TURN_KEY_API_TOKEN
```

The Worker calls Cloudflare's `generate-ice-servers` endpoint with a 24-hour
TTL. The long-term API token stays in Worker secrets. Builds can still use the
legacy `TURN_USER` / `TURN_CRED` dart-defines for isolated development, but
production must use short-lived credentials.

## Signaling base URL

`SignalingClient` resolves its base URL from the `SIGNALING_BASE_URL`
`--dart-define`, defaulting to the production Pulse Worker at
`https://pulse-signaling.trafficsayd-pulse.workers.dev`.
Override per environment:

```bash
flutter run --dart-define=SIGNALING_BASE_URL=https://pulse-signaling.staging.workers.dev
```

The client exposes typed `createSession`, `postOffer`, `getOffer`,
`postAnswer`, `getAnswer`, `postIce`, and an `iceCandidates(...)` long-poll
stream. All HTTP calls have client-side timeouts — 5 s for short POSTs and
GETs, 30 s for the ICE long-poll.
