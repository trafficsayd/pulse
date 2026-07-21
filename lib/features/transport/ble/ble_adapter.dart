import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

/// Connection state observed for a single BLE peer.
///
/// Mirrors the subset of `flutter_blue_plus` states the Pulse transport
/// actually consumes. Adapter implementations are responsible for
/// mapping vendor-specific intermediates onto these.
enum BleAdapterConnectionState { disconnected, connecting, connected }

/// A scan result surfaced by [BleScanner].
class BleAdvertisement {
  const BleAdvertisement({
    required this.device,
    required this.rssi,
    required this.serviceUuids,
  });

  final BleConnectableDevice device;
  final int rssi;
  final List<String> serviceUuids;
}

/// Thin façade around `flutter_blue_plus`'s static scanner API.
///
/// Defining it as an interface (rather than calling `FlutterBluePlus.X`
/// directly from `RealBleClient`) is what lets the unit tests inject a
/// `FakeFlutterBluePlus` without touching the device radio.
abstract interface class BleScanner {
  /// Snapshot of the most recent scan window. Implementations buffer
  /// results so a subscriber that joins late still sees what has been
  /// discovered so far in the current scan.
  Stream<List<BleAdvertisement>> get scanResults;

  /// Start scanning for advertisements that include any of the given
  /// service UUIDs. Returns immediately; results arrive on
  /// [scanResults]. The scan auto-stops at [timeout] — implementations
  /// MUST honour this to keep BLE radio energy bounded as required by
  /// the Pulse spec.
  Future<void> startScan({
    required List<String> withServiceUuids,
    required Duration timeout,
  });

  /// Stop any in-flight scan. Safe to call when not scanning.
  Future<void> stopScan();
}

/// A device discovered by [BleScanner] that the central can connect to.
abstract interface class BleConnectableDevice {
  /// Stable identifier surfaced by the OS (MAC address on Android,
  /// CBPeripheral UUID on iOS). Pulse never persists this — it is used
  /// only for the lifetime of a single GATT session.
  String get remoteId;

  /// Connection-state transitions for this device. Always emits the
  /// latest value on subscribe.
  Stream<BleAdapterConnectionState> get connectionState;

  /// Open a GATT connection. Implementations should let the platform
  /// pick the connection interval / latency — Pulse does not pin those
  /// because the OEM defaults are already tuned for low latency.
  Future<void> connect({Duration? timeout});

  /// Best-effort graceful disconnect. Does not throw if already
  /// disconnected.
  Future<void> disconnect();

  /// Discover all primary GATT services exposed by the peer.
  Future<List<BleGattService>> discoverServices();
}

/// A primary GATT service on a connected [BleConnectableDevice].
abstract interface class BleGattService {
  /// Normalised lowercase 128-bit UUID.
  String get uuid;

  /// Characteristics inside this service, in the order the peer
  /// announced them.
  List<BleGattCharacteristic> get characteristics;
}

/// A GATT characteristic. Pulse only uses two of these (TX and RX) —
/// see `ble_uuids.dart` for the canonical IDs.
abstract interface class BleGattCharacteristic {
  /// Normalised lowercase 128-bit UUID.
  String get uuid;

  /// Notifications / indications published by the peer after
  /// [setNotifyValue] has been enabled.
  Stream<List<int>> get onValueReceived;

  /// Subscribe to (or unsubscribe from) peer-initiated value updates.
  Future<void> setNotifyValue(bool enabled);

  /// Push a value to the peer. If [withoutResponse] is true the write
  /// is a low-latency BLE WRITE_NO_RSP; otherwise it is a confirmed
  /// WRITE that resolves only after the peer ACKs.
  Future<void> write(List<int> value, {bool withoutResponse = false});
}

/// Default adapter that maps directly onto `flutter_blue_plus`'s static
/// API. The real production code always uses this; tests substitute a
/// fake implementation of [BleScanner].
class FlutterBluePlusScanner implements BleScanner {
  FlutterBluePlusScanner();

  @override
  Stream<List<BleAdvertisement>> get scanResults =>
      fbp.FlutterBluePlus.scanResults.map(_mapResults);

  @override
  Future<void> startScan({
    required List<String> withServiceUuids,
    required Duration timeout,
  }) {
    return fbp.FlutterBluePlus.startScan(
      withServices: withServiceUuids.map(fbp.Guid.new).toList(),
      timeout: timeout,
    );
  }

  @override
  Future<void> stopScan() => fbp.FlutterBluePlus.stopScan();

  List<BleAdvertisement> _mapResults(List<fbp.ScanResult> results) {
    return [
      for (final r in results)
        BleAdvertisement(
          device: _FbpDevice(r.device),
          rssi: r.rssi,
          serviceUuids: [
            for (final g in r.advertisementData.serviceUuids)
              g.str.toLowerCase(),
          ],
        ),
    ];
  }
}

class _FbpDevice implements BleConnectableDevice {
  _FbpDevice(this._device);

  final fbp.BluetoothDevice _device;

  @override
  String get remoteId => _device.remoteId.str;

  @override
  Stream<BleAdapterConnectionState> get connectionState =>
      _device.connectionState.map(_mapState);

  @override
  Future<void> connect({Duration? timeout}) =>
      _device.connect(timeout: timeout ?? const Duration(seconds: 15));

  @override
  Future<void> disconnect() => _device.disconnect();

  @override
  Future<List<BleGattService>> discoverServices() async {
    final services = await _device.discoverServices();
    return [for (final s in services) _FbpService(s)];
  }

  BleAdapterConnectionState _mapState(fbp.BluetoothConnectionState s) {
    // `flutter_blue_plus` 1.36+ only streams `connected` and
    // `disconnected` on both Android and iOS — the historical
    // `connecting` / `disconnecting` values are deprecated. We treat
    // anything that isn't explicitly `connected` as `disconnected`
    // here; the GATT side tracks its own `connecting` interim state
    // inside [RealBleClient].
    if (s == fbp.BluetoothConnectionState.connected) {
      return BleAdapterConnectionState.connected;
    }
    return BleAdapterConnectionState.disconnected;
  }
}

class _FbpService implements BleGattService {
  _FbpService(this._service);

  final fbp.BluetoothService _service;

  @override
  String get uuid => _service.serviceUuid.str.toLowerCase();

  @override
  List<BleGattCharacteristic> get characteristics => [
        for (final c in _service.characteristics) _FbpCharacteristic(c),
      ];
}

class _FbpCharacteristic implements BleGattCharacteristic {
  _FbpCharacteristic(this._characteristic);

  final fbp.BluetoothCharacteristic _characteristic;

  @override
  String get uuid => _characteristic.characteristicUuid.str.toLowerCase();

  @override
  Stream<List<int>> get onValueReceived =>
      _characteristic.onValueReceived.cast<List<int>>();

  @override
  Future<void> setNotifyValue(bool enabled) =>
      _characteristic.setNotifyValue(enabled);

  @override
  Future<void> write(List<int> value, {bool withoutResponse = false}) =>
      _characteristic.write(value, withoutResponse: withoutResponse);
}
