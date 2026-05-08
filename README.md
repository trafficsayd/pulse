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
- Transport interface (`Transport`) with placeholder BLE / local
  network / WebRTC implementations and a manager that picks the best
  available channel.
- Secure storage abstraction over iOS Keychain / Android
  EncryptedSharedPreferences.
- Riverpod-based state for connections, subscription tier, and the
  per-day Sneak In quota.
- Screens: pairing, hub (mode carousel), my people, permissions sheet,
  Sneak In wheel, subscription, mode runner.
- A working starter mode: Knock-Knock (haptic + animated rings).
  The other six starter modes are scaffolded behind a placeholder.

What is **not** in this PR (deliberately):

- Real BLE / Wi-Fi Direct / Multipeer Connectivity / WebRTC bindings.
- Real Curve25519 ECDH and AES-256-GCM packet sealing.
- App Store / Play Store IAP integration.

Those land in follow-up PRs once the foundation is in place.

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
│   ├── crypto/           # PairKeys + PairingService contract
│   ├── hub/              # mode carousel hub screen
│   ├── modes/            # mode descriptors, registry, mode screens
│   ├── pairing/          # first-launch pairing screen
│   ├── people/           # My People screen + permissions sheet
│   ├── sneak_in/         # quota tracking + Sneak In wheel
│   ├── subscription/     # entitlements + paywall screen
│   └── transport/        # transport interface + BLE/LAN/WebRTC stubs
└── l10n/                 # ARB files (en, ru)
```
