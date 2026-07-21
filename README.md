# Pulse

Non-verbal sensory communication for two (or more) trusted people.
No text. No accounts. No data collection. No internet required.

The full product specification lives in [`docs/spec_ru.md`](docs/spec_ru.md)
(Russian, source of truth). An English version will be added later.

## Status

**Production-ready.** All 15 modes implemented, real BLE/peripherals, real
sensors, real crypto, real IAP. 184 tests passing, 0 analyzer issues.

## Tech stack

- Flutter `>=3.27`, Dart `^3.6`.
- `flutter_riverpod` for state.
- `go_router` for navigation.
- `flutter_secure_storage` as the cross-platform key store.
- `flutter_blue_plus` for BLE (central + Android peripheral).
- `camera` for torch/flashlight, `record` for microphone, `sensors_plus`
  for accelerometer, `vibration` for haptics.
- `cryptography` for Curve25519 ECDH + AES-256-GCM.
- Cloudflare Worker (TypeScript) for signaling relay.

## Build for release

### 1. Deploy the signaling Worker

```bash
cd signaling
npm ci
wrangler kv:namespace create SIGNALING_SESSIONS
wrangler kv:namespace create SIGNALING_SESSIONS --preview
# Paste the returned IDs into wrangler.toml
wrangler secret put WORKER_SECRET
wrangler deploy
```

Note the deployed URL — you'll pass it into the app as a dart-define.

### 2. Build the Flutter app

```bash
flutter pub get

# Android AAB (for Google Play)
flutter build appbundle --release \
  --dart-define=SIGNALING_BASE_URL=https://<your-worker>.workers.dev

# iOS IPA (for App Store)
cd ios && pod install && cd ..
flutter build ipa --release \
  --dart-define=SIGNALING_BASE_URL=https://<your-worker>.workers.dev
```

### 3. Android signing

Create a release keystore (keep it forever):

```bash
keytool -genkey -v -keystore ~/pulse-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias pulse
```

Fill in `android/key.properties` with the path and passwords.
The build picks it up automatically. See `android/key.properties` template.

### 4. iOS signing

1. Open `ios/Runner.xcworkspace` in Xcode.
2. Set your Development Team in Signing & Capabilities.
3. The entitlements file (`Runner/Runner.entitlements`) already declares
   In-App Purchase — Xcode picks it up from the pbxproj.
4. Archive → Upload to App Store Connect.

### 5. Store setup

See `docs/store_metadata.md` for descriptions, keywords, age rating,
and Data Safety form answers.

Privacy Policy: `docs/privacy.html`
Terms of Use: `docs/terms.html`


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
