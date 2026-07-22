# `lib/features/transport/webrtc/`

Support code for the real WebRTC data-channel transport (`WebRtcTransport`,
in `../webrtc_transport.dart`). The files in **this** directory stay plain
Dart (no `flutter_webrtc` import) so they remain unit-testable without the
native plugin; `webrtc_transport.dart` is the one place that imports
`flutter_webrtc`.

## Establishing a connection (Track F3 — implemented)

`WebRtcTransport` opens a real peer-to-peer `RTCDataChannel`:

1. **Role** — both peers reconnect symmetrically, so each posts a random
   128-bit claim (`pulse-role:<id>`) to the ICE endpoint; the larger id is the
   offerer (deterministic, glare-free). See `WebRtcTransport.isOfferer`.
2. **Vanilla ICE** — candidates are gathered fully and embedded in the SDP,
   then exchanged once via the `offer`/`answer` slots. We avoid trickle ICE
   because the Worker's ICE list is a single shared log with no per-sender
   attribution.
3. **P2P** — once the channel opens, sealed packets travel P2P over
   DTLS-SRTP; the Worker only ever brokered the SDP.
4. **Fallback** — if the channel can't open within `p2pTimeout`, the transport
   transparently relays the sealed packets over the same session (`/messages`).

## Contents

* `ice_servers.dart` — `kIceServers` and the `IceServer` model used to
  configure the WebRTC stack.
* `signaling_client.dart` — thin HTTP client that talks to the
  Cloudflare Worker in [`../../../../signaling/`](../../../../signaling/).

## TURN credentials

The default `kIceServers` list contains:

| URL | Purpose |
| --- | ------- |
| `stun:stun.l.google.com:19302` | Public Google STUN. |
| `stun:stun.cloudflare.com:3478` | Public Cloudflare STUN. |
| `turn:turn.pulse.app:3478` | Pulse's TURN relay (placeholder). |

The TURN entry's `username` and `credential` come from compile-time
`--dart-define` values. Without them the relay is still listed but with
empty auth fields — TURN simply fails for that peer and the connection
falls back to direct/STUN paths.

To enable TURN in a real build, pass:

```bash
flutter build apk \
  --dart-define=TURN_USER=$REAL_TURN_USER \
  --dart-define=TURN_CRED=$REAL_TURN_CRED \
  --dart-define=TURN_URL=turn:turn.pulse.app:3478
```

Production credential rotation is handled outside this repo — the build
pipeline is expected to mint short-lived credentials from a TURN auth
service and inject them into `--dart-define`.

`hasTurnCredentials` exposes whether the current build was compiled with
credentials, so the diagnostics screen and tests can degrade gracefully.

## Signaling base URL

`SignalingClient` resolves its base URL from the `SIGNALING_BASE_URL`
`--dart-define`, defaulting to `https://pulse-signaling.example.workers.dev`.
Override per environment:

```bash
flutter run --dart-define=SIGNALING_BASE_URL=https://pulse-signaling.staging.workers.dev
```

The client exposes typed `createSession`, `postOffer`, `getOffer`,
`postAnswer`, `getAnswer`, `postIce`, and an `iceCandidates(...)` long-poll
stream. All HTTP calls have client-side timeouts — 5 s for short POSTs and
GETs, 30 s for the ICE long-poll.
