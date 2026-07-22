# Changelog

## 1.0.0+1 — store-readiness (unreleased)

First release candidate for App Store / Google Play.

### Added
- Android upload-keystore release signing via `android/key.properties`
  (gitignored; CI recreates it from GitHub Secrets).
- R8 keep rules for WebRTC, BLE, and Play Billing
  (`android/app/proguard-rules.pro`); minification + resource shrinking
  enabled for release builds.
- Tag-triggered GitHub Actions workflow building a signed AAB
  (`.github/workflows/release-android.yml`).
- Paywall: store-localised price from `ProductDetails` with static fallback
  (`subscriptionPricePerMonth` l10n key, `premiumProductProvider`).
- Paywall: working Terms of Use / Privacy Policy links
  (`LEGAL_TERMS_URL` / `LEGAL_PRIVACY_URL` dart-defines with sane defaults).
- Legal documents (privacy policy, terms of use; RU/EN, markdown + hostable
  HTML) under `docs/legal/`.
- Release runbooks under `docs/release/`: master checklist, Android signing,
  iOS release, export compliance, App Store Connect / Play Console setup,
  store listings, review notes, screenshots plan, signaling production
  deploy, TURN options.

### Changed
- **iOS:** `PrivacyInfo.xcprivacy` is now registered in the Runner target
  (Resources build phase) so the privacy manifest actually ships in the
  bundle — previously it existed in the tree but was not part of the build.
- **iOS:** `UIRequiresFullScreen=true` — portrait-only apps must opt out of
  iPad multitasking or App Store validation rejects the build.
- **iOS:** `ITSAppUsesNonExemptEncryption=true` — Pulse ships its own E2E
  encryption (standard algorithms); see `docs/release/export_compliance.md`.
- **Android:** app label `pulse` → `Pulse`; explicit `compileSdk`/`targetSdk`
  35 (Play target-API policy); removed unused
  `FOREGROUND_SERVICE`/`FOREGROUND_SERVICE_CONNECTED_DEVICE` permissions
  (no `<service>` exists yet; restore together with a real implementation).
- Version bumped to `1.0.0+1`.
- README refreshed to match the actual state of the code.

### Notes for testers
- First release build with R8 enabled: run the full two-device smoke pass
  (pairing, all transports, purchase, restore) on the internal track before
  promoting.
