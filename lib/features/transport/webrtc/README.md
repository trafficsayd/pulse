# `lib/features/transport/webrtc/`

WebRTC-related primitives that the relay transport (`WebRtcTransport`) will
build on. Nothing here imports `flutter_webrtc` directly — that arrives in
Track F3. The files in this directory are designed to be plain Dart so they
can be unit-tested without any native plugin.

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
