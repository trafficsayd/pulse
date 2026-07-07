# Pulse

Non-verbal sensory communication for two (or more) trusted people.
No text. No accounts. No data collection. No internet required.

The full product specification lives in [`docs/spec_ru.md`](docs/spec_ru.md)
(Russian, source of truth). An English version will be added later.

## Status

Early scaffolding. This repository currently ships:

- Flutter application skeleton (iOS + Android, dark theme).
- Dual-language localization (RU / EN) wired through ARB files —
  adding a new language is "translate one file".
- Domain models for connections, permissions, sneak-in quotas, and
  subscription entitlements (with unit tests).
- Transport interface (`Transport`) with BLE, local-network, and encrypted
  internet relay fallback over the signaling Worker.
- Secure storage abstraction over iOS Keychain / Android
  EncryptedSharedPreferences.
- Riverpod-based state for connections, subscription tier, and the
  per-day Sneak In quota.
- Screens: pairing, hub (mode carousel), my people, permissions sheet,
  Sneak In wheel, subscription, mode runner.
- Real pairing by 6-digit code: both phones exchange public keys through the
  signaling Worker, verify the same SAS, persist shared keys, and reuse the
  shared signaling token for reconnects.
- End-to-end packet sealing with Curve25519-derived AES-GCM keys.

Still pending before store release:

- Production Play Store / App Store signing and IAP product setup.
- Native WebRTC data-channel optimization. The current over-internet fallback
  is a signaling relay for encrypted packets, so it is functional for testing
  but not the final low-latency transport.

## Tech stack

- Flutter `>=3.27`, Dart `^3.6`.
- `flutter_riverpod` for state.
- `go_router` for navigation.
- `flutter_secure_storage` as the cross-platform key store.
- `intl` + Flutter's gen-l10n for localisation.

## Run locally

```bash
flutter pub get
flutter run
```

## Run on Android

Deploy the signaling Worker first, then pass its URL into the app:

```bash
cd signaling
npm ci
wrangler secret put WORKER_SECRET
wrangler deploy

cd ..
flutter run -d <android-device-id> --dart-define=SIGNALING_BASE_URL=https://<your-worker>.workers.dev
```

Two phones must use the same deployed `SIGNALING_BASE_URL`. The host opens
pairing, the second phone enters the 6-digit code, both confirm the same SAS,
then mode events travel as encrypted packets through the best available
transport.

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
│   ├── subscription/     # entitlements + paywall screen
│   └── transport/        # transport interface + BLE/LAN/signaling relay
└── l10n/                 # ARB files (en, ru)
```
