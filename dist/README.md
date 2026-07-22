# Distribution artifacts

Binary artifacts are **not** stored in git (a 65 MB APK would bloat every
clone forever, and GitHub warns above 50 MB). This file records the
provenance of the current build so the bytes can always be verified or
reproduced.

## pulse-release-arm64.apk — v0.1.0 (versionCode 1)

| Field | Value |
| --- | --- |
| Package | `io.pulseapp.pulse` |
| Build type | release (signed with the debug keystore — dev distribution only) |
| ABI | arm64-v8a |
| Size | 65 277 094 bytes (≈65 MB) |
| SHA-256 | `f88a6d3d0381bacc00f0f425da7a0925b98b781e74b5a072690b2c229dd8909e` |
| Signature | APK Signature Scheme v1 + v2 — verified with apksigner |
| Toolchain | Flutter 3.27 (17025dd) · AGP 8.1.0 · Gradle 8.3 · JDK 17 · build-tools 34.0.0 |

Build command:

```bash
flutter build apk --release --target-platform android-arm64
```

Runtime notes for this build:

* Demo connections are **not** seeded (release build) — the People screen
  starts empty until a real pairing completes.
* Pairing needs a deployed signaling Worker: build with
  `--dart-define=SIGNALING_BASE_URL=https://<your-worker>.workers.dev`.
* Real BLE is compile-time gated: add `--dart-define=useRealBleTransport=true`
  on device builds.

## Publishing the APK on GitHub

The right home for binaries is a **Release asset** (not the git tree):

```bash
gh release create v0.1.0 pulse-release-arm64.apk \
  --title "Pulse 0.1.0 (arm64 dev build)" \
  --notes "See dist/README.md for provenance. SHA-256: f88a6d3d0381bacc00f0f425da7a0925b98b781e74b5a072690b2c229dd8909e"
```

Before store submission replace the debug signing config with a real
release keystore (`android/app/build.gradle` → `signingConfigs`).
