# Device integration tests

Emulators cannot exercise Pulse's core (BLE has no radio, mic/sensors/Keychain
are stubbed), so these run on **real devices**.

## Single-device smoke

```bash
flutter test integration_test -d <device-id>
```

Covers: the app boots and renders its first frame on a real device, and the
dark-only theme is applied. Extend with per-screen checks as needed.

## Two-phone flows (manual / device farm)

The flagship flows are inherently multi-device and are driven with two targets:

1. Deploy the signaling Worker (see `../signaling/README.md`) and note its URL.
2. On **both** phones:
   ```bash
   flutter run -d <device> \
     --dart-define=SIGNALING_BASE_URL=https://<worker>.workers.dev \
     --dart-define=useRealBleTransport=true
   ```
3. Host: open pairing → shows a 6-digit code. Guest: enter the code.
4. Both: confirm the SAS codes match (anti-MITM gate).
5. Verify each of the 7 starter modes, transport indicator (green/blue/yellow),
   and a Sneak In from a paused connection.

For automated two-device runs use a device farm (Firebase Test Lab multi-device
/ BrowserStack) with the same `integration_test` target on each device. BLE
proximity still requires the physical devices to be near each other.
