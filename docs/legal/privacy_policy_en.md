# Pulse — Privacy Policy

_Effective date: July 22, 2026_

Pulse is built on a simple principle: **we collect no data about you.**
No accounts, no analytics, no telemetry, no advertising identifiers.

## What stays on your devices

- **Pairing keys and connections.** When you pair with a trusted person,
  cryptographic keys are generated and stored only in your device's secure
  storage (iOS Keychain / Android encrypted storage). We have no copy and
  no way to obtain one.
- **Signals.** Touches, vibrations, sounds and light patterns travel
  directly between the paired devices, end-to-end encrypted
  (Curve25519 key agreement, AES-256-GCM). Nobody in between — including
  us — can read them.
- **Permissions** (Bluetooth, local network, microphone, camera, motion
  sensors) are used solely to power the modes on your device. Audio and
  camera frames are processed locally and never leave your phone.
  Bluetooth permissions on Android are declared with the
  `neverForLocation` flag: Pulse does not derive or read your location.

## The connection relay

When your devices are far apart, Pulse uses a relay service to help the
two phones find each other and, if a direct channel cannot open, to pass
**end-to-end encrypted packets** between them. The relay:

- sees only random session tokens — nothing tied to your identity, phone
  number or account (there are none);
- cannot decrypt any content;
- stores session data ephemerally (deleted automatically within minutes);
- processes IP addresses transiently in memory for abuse rate-limiting
  only; they are not logged or stored with any content.

## Purchases

The Pulse Premium subscription is processed entirely by Apple App Store or
Google Play. We do not receive your name, payment details or address. The
subscription status your device derives from the store receipt is stored
locally on your device.

## Crash reports

The app currently sends no crash reports. If optional crash reporting is
ever added, it will be off by default and require your explicit consent.

## Children

Pulse is intended for users aged 13 and older.

## Data requests

Since we hold no personal data, there is nothing for us to hand over,
correct or delete. Deleting the app (or a connection inside it) destroys
the local keys irrevocably.

## Changes

We will update this page and the effective date if the policy ever
changes. Material changes will be announced in the app's release notes.

## Contact

Questions: **support@pulse.app** <!-- TODO: replace with the real support address before publishing -->
