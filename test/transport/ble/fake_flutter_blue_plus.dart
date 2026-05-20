import 'dart:async';

import 'package:pulse/features/transport/ble/ble_adapter.dart';
import 'package:pulse/features/transport/ble/ble_permission_gate.dart';
import 'package:pulse/features/transport/ble/ble_transport_exception.dart';

/// In-memory stand-in for `flutter_blue_plus` used by the BLE transport
/// unit tests. Drives [RealBleClient] entirely from Dart so the tests
/// never touch the platform radio.
class FakeBleScanner implements BleScanner {
  final StreamController<List<BleAdvertisement>> _results =
      StreamController<List<BleAdvertisement>>.broadcast();
  bool isScanning = false;
  Duration? lastTimeout;
  List<String>? lastFilter;
  int startCount = 0;
  int stopCount = 0;
  Object? startError;
  bool emitMatchOnStart = false;

  final List<BleAdvertisement> pendingMatches = [];

  @override
  Stream<List<BleAdvertisement>> get scanResults => _results.stream;

  @override
  Future<void> startScan({
    required List<String> withServiceUuids,
    required Duration timeout,
  }) async {
    startCount += 1;
    isScanning = true;
    lastTimeout = timeout;
    lastFilter = withServiceUuids;
    if (startError != null) {
      final e = startError!;
      startError = null;
      throw e;
    }
    if (emitMatchOnStart && pendingMatches.isNotEmpty) {
      scheduleMicrotask(() => _results.add(pendingMatches));
    }
  }

  @override
  Future<void> stopScan() async {
    stopCount += 1;
    isScanning = false;
  }

  void emit(List<BleAdvertisement> ads) => _results.add(ads);

  Future<void> dispose() => _results.close();
}

/// In-memory peer that pretends to be the Pulse GATT service.
class FakeBleDevice implements BleConnectableDevice {
  FakeBleDevice({
    required this.remoteId,
    required List<FakeBleService> services,
    this.failConnect = false,
  }) : _services = services;

  @override
  final String remoteId;

  final bool failConnect;
  final List<FakeBleService> _services;
  final StreamController<BleAdapterConnectionState> _conn =
      StreamController<BleAdapterConnectionState>.broadcast();

  bool connected = false;
  int connectCount = 0;
  int disconnectCount = 0;

  @override
  Stream<BleAdapterConnectionState> get connectionState => _conn.stream;

  @override
  Future<void> connect({Duration? timeout}) async {
    connectCount += 1;
    if (failConnect) {
      throw const BleTransportException(
        BleTransportFailure.disconnected,
        'Fake device refused to connect.',
      );
    }
    connected = true;
    _conn.add(BleAdapterConnectionState.connected);
  }

  @override
  Future<void> disconnect() async {
    disconnectCount += 1;
    connected = false;
    _conn.add(BleAdapterConnectionState.disconnected);
  }

  /// Simulate the peer side dropping the link unilaterally.
  void simulatePeerDisconnect() {
    connected = false;
    _conn.add(BleAdapterConnectionState.disconnected);
  }

  @override
  Future<List<BleGattService>> discoverServices() async => _services;

  Future<void> dispose() => _conn.close();
}

class FakeBleService implements BleGattService {
  FakeBleService({required this.uuid, required this.characteristics});

  @override
  final String uuid;

  @override
  final List<BleGattCharacteristic> characteristics;
}

class FakeBleCharacteristic implements BleGattCharacteristic {
  FakeBleCharacteristic({required this.uuid, this.failWrite = false});

  @override
  final String uuid;

  bool failWrite;
  bool notifyEnabled = false;
  final List<List<int>> writes = [];

  final StreamController<List<int>> _values =
      StreamController<List<int>>.broadcast();

  @override
  Stream<List<int>> get onValueReceived => _values.stream;

  @override
  Future<void> setNotifyValue(bool enabled) async {
    notifyEnabled = enabled;
  }

  @override
  Future<void> write(List<int> value, {bool withoutResponse = false}) async {
    if (failWrite) {
      throw StateError('Fake write failed.');
    }
    writes.add(List<int>.from(value));
  }

  /// Simulate the peer publishing a notification on this characteristic.
  void emitNotification(List<int> bytes) => _values.add(bytes);

  Future<void> dispose() => _values.close();
}

/// Permission gate that can be wired to either always grant or always
/// deny, for permission-handling unit tests.
class FakeBlePermissionGate implements BlePermissionGate {
  FakeBlePermissionGate({this.granted = true});

  bool granted;
  int callCount = 0;
  bool? lastAdvertise;

  @override
  Future<void> ensureGranted({required bool advertise}) async {
    callCount += 1;
    lastAdvertise = advertise;
    if (!granted) {
      throw const BleTransportException.permissionDenied('bluetoothScan');
    }
  }
}
