import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ble_permission_gate.dart';
import 'ble_transport_exception.dart';
import 'ble_uuids.dart';

/// Lifecycle states reported by [RealBlePeripheral].
enum BlePeripheralState {
  /// Initial — `start` has never been called or the last `stop` completed.
  idle,

  /// `BluetoothLeAdvertiser.startAdvertising` is in flight or active on
  /// Android. On iOS this state is unreachable from this class because
  /// `flutter_blue_plus` does not expose CBPeripheralManager — pair
  /// discovery there happens via the central's scan.
  advertising,

  /// A central confirmed the GATT session. Higher layers stop
  /// advertising at this point to save battery, per Pulse's "stop
  /// advertising when channel established" energy rule.
  paired,
}

/// Peripheral-mode BLE advertiser for Pulse.
///
/// `flutter_blue_plus` only ships *central* support, so this class
/// reaches across a MethodChannel to a future native `BluetoothLeAdvertiser`
/// (Android) wrapper. iOS peripheral mode is intentionally a no-op — on
/// iPhones we rely on the peer device's central role to scan for *us*
/// (the iOS-side acts as central). This matches the user-facing
/// pairing UX: whichever device tapped "I'm waiting" becomes peripheral
/// only on Android.
///
/// This class is scaffolding: it owns the MethodChannel contract, the
/// permission gate, and the lifecycle state machine, so wiring up the
/// actual native side is a self-contained follow-up.
class RealBlePeripheral {
  RealBlePeripheral({
    BlePermissionGate? permissions,
    MethodChannel? channel,
  })  : _permissions = permissions ?? const RealBlePermissionGate(),
        _channel = channel ?? const MethodChannel(_methodChannelName) {
    // Data-plane bridge: the native side pushes central writes and
    // connection lifecycle events back through the same channel.
    _channel.setMethodCallHandler(_onNativeCall);
  }

  static const String _methodChannelName = 'app.pulse.ble/peripheral';

  final BlePermissionGate _permissions;
  final MethodChannel _channel;

  final StreamController<BlePeripheralState> _state =
      StreamController<BlePeripheralState>.broadcast();
  BlePeripheralState _currentState = BlePeripheralState.idle;

  /// Lifecycle transitions for the UI / transport.
  Stream<BlePeripheralState> get state => _state.stream;

  /// Most recent state without subscribing.
  BlePeripheralState get currentState => _currentState;

  /// True when advertising is supported on the current OS.
  ///
  /// Returns `true` on Android (where the OS exposes
  /// `BluetoothLeAdvertiser`) and `false` on iOS (where peripheral mode
  /// requires CoreBluetooth's `CBPeripheralManager`, which is outside
  /// the scope of this PR).
  bool get isSupported => Platform.isAndroid;

  /// Begin advertising the Pulse GATT service so a central scanner can
  /// find us. No-op on iOS — see [isSupported].
  Future<void> start() async {
    if (!isSupported) {
      if (kDebugMode) {
        debugPrint(
          'RealBlePeripheral: peripheral mode is not supported on '
          '${Platform.operatingSystem}; relying on central-side scan.',
        );
      }
      return;
    }
    await _permissions.ensureGranted(advertise: true);
    try {
      await _channel.invokeMethod<void>('startAdvertising', <String, dynamic>{
        'serviceUuid': pulseServiceUuid,
        'txCharacteristicUuid': pulseTxCharacteristicUuid,
        'rxCharacteristicUuid': pulseRxCharacteristicUuid,
      });
      _setState(BlePeripheralState.advertising);
    } on PlatformException catch (e) {
      throw BleTransportException(
        BleTransportFailure.writeFailed,
        'Failed to start BLE advertising: ${e.message}',
        cause: e,
      );
    }
  }

  /// Mark the peripheral as paired so the higher layers know to stop
  /// advertising (and the native side can release the advertiser
  /// resource).
  Future<void> markPaired() async {
    if (!isSupported) return;
    if (_currentState == BlePeripheralState.paired) return;
    try {
      await _channel
          .invokeMethod<void>('stopAdvertising')
          .timeout(const Duration(seconds: 3), onTimeout: () {});
    } on PlatformException catch (e, st) {
      if (kDebugMode) {
        debugPrint('RealBlePeripheral.markPaired: $e\n$st');
      }
    }
    _setState(BlePeripheralState.paired);
  }

  /// Stop advertising and reset to idle. Always completes within a
  /// bounded window even if the native side is wedged.
  Future<void> stop() async {
    if (!isSupported) {
      _setState(BlePeripheralState.idle);
      return;
    }
    try {
      await _channel
          .invokeMethod<void>('stopAdvertising')
          .timeout(const Duration(seconds: 3), onTimeout: () {});
    } on PlatformException catch (e, st) {
      if (kDebugMode) debugPrint('RealBlePeripheral.stop: $e\n$st');
    }
    _setState(BlePeripheralState.idle);
  }

  final StreamController<Uint8List> _rxWrites =
      StreamController<Uint8List>.broadcast();
  final StreamController<bool> _centralConnected =
      StreamController<bool>.broadcast();

  /// Raw frames written by the connected central onto the RX
  /// characteristic. Framing/decryption is the caller's job — this layer
  /// shuttles opaque bytes, mirroring `RealBleClient.incoming`.
  Stream<Uint8List> get rxWrites => _rxWrites.stream;

  /// `true` when a central connects to our GATT server, `false` when it
  /// drops. Useful for pairing UX («партнёр рядом»).
  Stream<bool> get centralConnected => _centralConnected.stream;

  /// Push one frame to the connected central via a TX-characteristic
  /// notification. Throws [BleTransportException] when no central is
  /// connected or the native notify fails.
  Future<void> sendTx(Uint8List bytes) async {
    if (!isSupported) {
      throw const BleTransportException(
        BleTransportFailure.writeFailed,
        'BLE peripheral mode is not supported on this platform.',
      );
    }
    try {
      await _channel.invokeMethod<void>('txNotify', <String, dynamic>{
        'bytes': bytes,
      });
    } on PlatformException catch (e) {
      throw BleTransportException(
        BleTransportFailure.writeFailed,
        'Failed to notify central: ${e.message}',
        cause: e,
      );
    }
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onRxWrite':
        final args = call.arguments;
        if (args is Map && args['bytes'] is Uint8List) {
          _rxWrites.add(args['bytes'] as Uint8List);
        }
        break;
      case 'onCentralConnected':
        _centralConnected.add(true);
        break;
      case 'onCentralDisconnected':
        _centralConnected.add(false);
        break;
    }
    return null;
  }

  /// Permanently release this peripheral. Safe to call multiple times.
  Future<void> dispose() async {
    await stop();
    await _state.close().timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        );
    await _rxWrites.close().timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        );
    await _centralConnected.close().timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        );
  }

  void _setState(BlePeripheralState next) {
    if (next == _currentState) return;
    _currentState = next;
    _state.add(next);
  }
}
