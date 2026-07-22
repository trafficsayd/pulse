# Pulse

Non-verbal sensory communication for two (or more) trusted people.
No text. No accounts. No data collection. No internet required.

The full product specification lives in [`docs/spec_ru.md`](docs/spec_ru.md)
(Russian, source of truth). An English version will be added later.

## Status

Feature-complete for the 1.0 store release. This repository ships:

- Flutter application (iOS 15+ / Android 6+, dark theme) with RU / EN
  localization wired through ARB files.
- Domain models for connections, permissions, sneak-in quotas, and
  subscription entitlements (with unit tests).
- Real pairing by 6-digit code: both phones exchange public keys through the
  signaling Worker, verify the same SAS, persist shared keys, and reuse the
  shared signaling token for reconnects.
- End-to-end packet sealing with Curve25519-derived AES-GCM keys.
- Transport ladder: BLE → local network → WebRTC data channel (P2P over
  DTLS-SRTP) with automatic encrypted relay fallback through the signaling
  Worker when P2P cannot open.
- In-app purchases: `pulse_premium_monthly` auto-renewable subscription via
  `in_app_purchase` — buy, restore, pending states, receipt sanity checks,
  store-localised pricing on the paywall.
- Screens: pairing, hub (mode carousel), my people, permissions sheet,
  Sneak In wheel, subscription paywall, mode runner, diagnostics.
- Release scaffolding: Android upload-keystore signing, R8 keep rules,
  iOS privacy manifest bundled with the Runner target, tag-triggered
  signed AAB workflow.

**Release runbook:** everything left between this commit and the store
buttons is inventoried in
[`docs/release/store_release_checklist.md`](docs/release/store_release_checklist.md) —
start there. Owner-side actions (developer accounts, keystore generation,
store products, legal hosting) are marked explicitly.

## Tech stack

- Flutter `>=3.27`, Dart `^3.6`.
- `flutter_riverpod` for state.
- `go_router` for navigation.
- `flutter_secure_storage` as the cross-platform key store.
- `intl` + Flutter's gen-l10n for localisation.
- `flutter_webrtc` + Cloudflare Worker signaling for the internet tier.
- `in_app_purchase` for the Premium subscription.

## Run locally

```bash
flutter pub get
flutter run
```

## Run on two phones (full flow)

Deploy the signaling Worker first, then pass its URL into the app:

```bash
cd signaling
npm ci
wrangler secret put WORKER_SECRET
wrangler deploy

cd ..
flutter run -d <device-id> --dart-define=SIGNALING_BASE_URL=https://<your-worker>.workers.dev
```

Two phones must use the same deployed `SIGNALING_BASE_URL`. The host opens
pairing, the second phone enters the 6-digit code, both confirm the same SAS,
then mode events travel as encrypted packets through the best available
transport.

Optional TURN relay for hostile NATs (see
[`docs/release/turn.md`](docs/release/turn.md)):

```bash
flutter run ... \
  --dart-define=TURN_URL=turn:turn.example.com:3478 \
  --dart-define=TURN_USER=... --dart-define=TURN_CRED=...
```

## Release builds

- **Android:** `docs/release/android_signing.md` (local) or push a `v*` tag —
  `.github/workflows/release-android.yml` builds a signed AAB from GitHub
  Secrets.
- **iOS:** `docs/release/ios_release.md` (Xcode archive; macOS required).

## Lint and test

```bash
flutter analyze
flutter test
```

## Project layout

```
lib/
├── app.dart              # MaterialApp.router root
├── main.dart             # entry point
├── core/
│   ├── routing/          # go_router config + route constants
│   ├── storage/          # SecureKeyStore (Keychain / EncryptedSharedPreferences)
│   └── theme/            # dark theme + design tokens
├── features/
│   ├── connections/      # Connection model, repository, controller
│   ├── crypto/           # PairKeys, ECDH pairing, AES-GCM sealed channel
│   ├── hub/              # mode carousel hub screen
│   ├── modes/            # mode descriptors, registry, mode screens
│   ├── pairing/          # first-launch pairing screen
│   ├── people/           # My People screen + permissions sheet
│   ├── sneak_in/         # quota tracking + Sneak In wheel
│   ├── subscription/     # entitlements + IAP + paywall screen
│   └── transport/        # transport interface + BLE/LAN/WebRTC relay
└── l10n/                 # ARB files (en, ru)

docs/
├── spec_ru.md            # product specification (source of truth)
├── legal/                # privacy policy + terms of use (RU/EN, md + html)
└── release/              # store release runbooks and checklists
```
