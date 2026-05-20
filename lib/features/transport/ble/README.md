# Pulse BLE transport

Real Bluetooth Low Energy transport for Pulse — replaces the historical
`_PlaceholderBleClient` no-op once `useRealBleTransport` is enabled. Lives
under `lib/features/transport/ble/` and is consumed by `BleTransport`
(`lib/features/transport/ble_transport.dart`), which in turn is one of
the three tiers the `TransportManager` (direct → local network → relay)
picks between.

## GATT identifiers

All three UUIDs are part of the public over-the-air contract between two
paired Pulse devices and must remain stable across releases — they are
baked into peripheral advertising filters and central scan filters on
every shipped client. Bumping any of them is a breaking change that
requires a coordinated rollout across the App Store and Play Store.

| Name | UUID | Direction | Properties |
|---|---|---|---|
| Pulse service | `0000feed-0000-1000-8000-00805f9b34fb` | n/a | primary service |
| TX characteristic | `a1c1feed-0001-4001-8000-00805f9b34fb` | peripheral → central | `NOTIFY` + `WRITE_WITHOUT_RESPONSE` |
| RX characteristic | `a1c1feed-0002-4001-8000-00805f9b34fb` | central → peripheral | `WRITE` + `INDICATE` |

The service UUID lives inside the Bluetooth SIG 16-bit `0xFEED`
namespace expanded into the standard 128-bit form. The TX/RX
characteristics use random RFC 4122 v4 UUIDs so they never collide with
any SIG-assigned characteristic and stay unique to Pulse traffic.

These constants are defined in [`ble_uuids.dart`](./ble_uuids.dart).

## Role selection — central vs peripheral

Both ends of a Pulse pair are functionally equivalent over the air. The
*central* end is whichever device initiated pairing (it does the
scanning + GATT connection), and the *peripheral* end is the device
that "was waiting" (it advertises the Pulse service and accepts the
incoming connection). On reconnect, either side may end up as central —
the choice is local to that session, not persisted.

- The **central** role is implemented by [`RealBleClient`](./real_ble_client.dart).
  It owns the scan, the GATT connect, the TX notify subscription, and
  the RX write path.
- The **peripheral** role is implemented by
  [`RealBlePeripheral`](./real_ble_peripheral.dart). It owns the
  advertiser and the `BluetoothLeAdvertiser` MethodChannel hand-off to
  the native side.

Both classes share:

- [`BleClient`](./ble_client.dart) — the public interface
  `BleTransport` talks to,
- [`BlePermissionGate`](./ble_permission_gate.dart) — the Android
  runtime permission gate (`BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`,
  `BLUETOOTH_ADVERTISE`),
- [`BleScanner` / `BleConnectableDevice`](./ble_adapter.dart) — the
  thin testable adapter over `flutter_blue_plus` (`FakeFlutterBluePlus`
  drives the unit tests via these interfaces),
- [`packet_codec.dart`](./packet_codec.dart) — the tiny JSON-on-BLE
  encoder for `TransportPacket` (≤ default ATT MTU after the kind
  header).

## iOS peripheral limitation

`flutter_blue_plus` does **not** expose `CBPeripheralManager` and so
this PR does not implement BLE peripheral mode on iOS. The iOS side
always acts as a central:

- If the user opens Pulse and chooses "I am waiting", the iPhone
  starts a central scan and waits to discover an Android peripheral
  advertising `pulseServiceUuid`.
- If both devices are iPhones, advertising will only succeed if one of
  them happens to be in iOS's foreground state where CoreBluetooth
  allows implicit advertising of the bundle ID's `bluetooth-peripheral`
  background mode (declared in `Info.plist`). Reliable
  iPhone-to-iPhone peripheral advertising will land in a follow-up PR
  that adds a native `CBPeripheralManager` MethodChannel — see
  [`real_ble_peripheral.dart`](./real_ble_peripheral.dart) for the
  scaffolding.

In practice the Android-as-peripheral / iOS-as-central path covers the
vast majority of mixed-OS Pulse pairs without any additional native
work.

## Energy budget

Per the Pulse product spec the BLE radio must be a good citizen:

- `RealBleClient.connect` accepts a `scanTimeout` (default 10 s) and
  stops `FlutterBluePlus.startScan` no later than that, regardless of
  whether a peer was found.
- `RealBlePeripheral.markPaired` immediately stops advertising once a
  GATT session is established. Higher layers call this from the
  pairing controller.
- Both clients subscribe to the platform `connectionState` stream so
  the moment a peer disappears they surface a
  `BleTransportException.disconnected` to higher layers, which lets
  `TransportManager` fall through to the local network tier without
  the user noticing.

## Enabling the real transport

`BleTransport` defaults to the inert
[`PlaceholderBleClient`](./placeholder_ble_client.dart) so widget tests
and the CI smoke test do not link against a real radio. To opt into the
real client at build time, pass:

```bash
flutter run --dart-define=useRealBleTransport=true
flutter build apk --dart-define=useRealBleTransport=true
flutter build ipa --dart-define=useRealBleTransport=true
```

See [`ble_transport_config.dart`](./ble_transport_config.dart).
