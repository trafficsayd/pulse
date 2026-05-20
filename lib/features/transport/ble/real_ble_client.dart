import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ble_adapter.dart';
import 'ble_client.dart';
import 'ble_permission_gate.dart';
import 'ble_transport_exception.dart';
import 'ble_uuids.dart';
import 'packet_codec.dart';

/// Real central-mode BLE client backed by `flutter_blue_plus`.
///
/// Replaces the historical `_PlaceholderBleClient` no-op used while the
/// app was still scaffolding (Tracks A–E). Flow on [connect]:
///
/// 1. Request `bluetoothScan` + `bluetoothConnect` runtime permissions
///    (Android 12+; iOS is a no-op — the OS prompts on first radio use).
/// 2. Start a bounded scan for advertisements carrying [pulseServiceUuid].
/// 3. First matching device wins: stop scanning, connect GATT.
/// 4. Discover services, locate the Pulse service, subscribe to the TX
///    characteristic, cache the RX characteristic for outbound writes.
/// 5. Subscribe to `connectionState` so we surface a clean
///    `disconnected` event the moment the radio link drops.
///
/// All BLE primitives go through [BleScanner] / [BleConnectableDevice]
/// adapters so the same code path is exercised by `FakeFlutterBluePlus`
/// in unit tests without touching real radio hardware.
class RealBleClient implements BleClient {
  RealBleClient({
    BleScanner? scanner,
    BlePermissionGate? permissions,
  })  : _scanner = scanner ?? FlutterBluePlusScanner(),
        _permissions = permissions ?? const RealBlePermissionGate();

  final BleScanner _scanner;
  final BlePermissionGate _permissions;

  final StreamController<Packet> _incoming =
      StreamController<Packet>.broadcast();
  final StreamController<BleClientState> _state =
      StreamController<BleClientState>.broadcast();
  BleClientState _currentState = BleClientState.idle;

  // Connection-time scratch state — wiped on every disconnect so a
  // reconnect cannot inherit stale notification subscriptions.
  BleConnectableDevice? _device;
  BleGattCharacteristic? _rx;
  // Subscriptions are cancelled in [disconnect]/[dispose] — the lint
  // can't see that across function boundaries.
  // ignore: cancel_subscriptions
  StreamSubscription<List<int>>? _txSub;
  // ignore: cancel_subscriptions
  StreamSubscription<BleAdapterConnectionState>? _connSub;
  // ignore: cancel_subscriptions
  StreamSubscription<List<BleAdvertisement>>? _scanSub;

  // Single-flight guard for [connect] so the transport manager can call
  // it concurrently from multiple state observers without spawning
  // overlapping scans.
  bool _connecting = false;

  @override
  Stream<Packet> get incoming => _incoming.stream;

  @override
  Stream<BleClientState> get state => _state.stream;

  @override
  BleClientState get currentState => _currentState;

  @override
  Future<void> connect({
    Duration scanTimeout = const Duration(seconds: 10),
    Map<String, String> reconnectTokens = const {},
  }) async {
    if (_connecting) return;
    _connecting = true;
    try {
      await _permissions.ensureGranted(advertise: false);
      _setState(BleClientState.scanning);

      final found = Completer<BleAdvertisement>();
      _scanSub = _scanner.scanResults.listen(
        (results) {
          if (found.isCompleted) return;
          for (final adv in results) {
            final hasService = adv.serviceUuids
                .any((u) => u.toLowerCase() == pulseServiceUuid);
            if (hasService) {
              found.complete(adv);
              return;
            }
          }
        },
        onError: (Object e, StackTrace st) {
          if (!found.isCompleted) found.completeError(e, st);
        },
      );

      await _scanner.startScan(
        withServiceUuids: const [pulseServiceUuid],
        timeout: scanTimeout,
      );

      BleAdvertisement adv;
      try {
        adv = await found.future.timeout(scanTimeout);
      } on TimeoutException {
        await _stopScanQuiet();
        _setState(BleClientState.idle);
        throw BleTransportException.scanTimeout(scanTimeout);
      }
      await _stopScanQuiet();

      _device = adv.device;
      _setState(BleClientState.connecting);
      await adv.device.connect(timeout: const Duration(seconds: 15));

      // Observe peer-initiated disconnects.
      _connSub = adv.device.connectionState.listen((s) {
        if (s == BleAdapterConnectionState.disconnected &&
            _currentState != BleClientState.idle) {
          _setState(BleClientState.disconnected);
          _incoming.addError(
            const BleTransportException.disconnected(),
          );
        }
      });

      final services = await adv.device.discoverServices();
      final pulse = services.firstWhere(
        (s) => s.uuid.toLowerCase() == pulseServiceUuid,
        orElse: () => throw const BleTransportException(
          BleTransportFailure.disconnected,
          'Pulse GATT service was not found on the peer.',
        ),
      );

      final tx = pulse.characteristics.firstWhere(
        (c) => c.uuid.toLowerCase() == pulseTxCharacteristicUuid,
        orElse: () => throw const BleTransportException(
          BleTransportFailure.disconnected,
          'Pulse TX characteristic was not found on the peer.',
        ),
      );
      final rx = pulse.characteristics.firstWhere(
        (c) => c.uuid.toLowerCase() == pulseRxCharacteristicUuid,
        orElse: () => throw const BleTransportException(
          BleTransportFailure.disconnected,
          'Pulse RX characteristic was not found on the peer.',
        ),
      );

      await tx.setNotifyValue(true);
      _txSub = tx.onValueReceived.listen(
        _onTxNotification,
        onError: _incoming.addError,
      );
      _rx = rx;

      _setState(BleClientState.connected);
    } finally {
      _connecting = false;
    }
  }

  @override
  Future<void> send(Packet packet) async {
    final rx = _rx;
    if (rx == null || _currentState != BleClientState.connected) {
      throw const BleTransportException(
        BleTransportFailure.writeFailed,
        'BLE client is not connected.',
      );
    }
    try {
      await rx.write(packetEncoder(packet), withoutResponse: false);
    } catch (e) {
      throw BleTransportException.writeFailed(e);
    }
  }

  @override
  Future<void> disconnect() async {
    await _stopScanQuiet();
    await _safeCancel(_scanSub);
    _scanSub = null;
    await _safeCancel(_txSub);
    _txSub = null;
    await _safeCancel(_connSub);
    _connSub = null;
    final dev = _device;
    _device = null;
    _rx = null;
    if (dev != null) {
      try {
        await dev
            .disconnect()
            .timeout(const Duration(seconds: 3), onTimeout: () {});
      } catch (e, st) {
        if (kDebugMode) debugPrint('RealBleClient.disconnect: $e\n$st');
      }
    }
    _setState(BleClientState.idle);
  }

  /// Cleanly drop the streams. After [dispose] the client is permanently
  /// unusable; create a fresh instance for any future session.
  Future<void> dispose() async {
    await disconnect();
    await _incoming.close().timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        );
    await _state.close().timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        );
  }

  void _onTxNotification(List<int> bytes) {
    try {
      _incoming.add(packetDecoder(bytes));
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('RealBleClient: dropped malformed TX frame: $e\n$st');
      }
      _incoming.addError(e, st);
    }
  }

  void _setState(BleClientState next) {
    if (next == _currentState) return;
    _currentState = next;
    _state.add(next);
  }

  Future<void> _stopScanQuiet() async {
    try {
      await _scanner
          .stopScan()
          .timeout(const Duration(seconds: 3), onTimeout: () {});
    } catch (e, st) {
      if (kDebugMode) debugPrint('RealBleClient.stopScan: $e\n$st');
    }
  }

  Future<void> _safeCancel(StreamSubscription<dynamic>? sub) async {
    if (sub == null) return;
    try {
      await sub.cancel().timeout(
            const Duration(seconds: 3),
            onTimeout: () {},
          );
    } catch (e, st) {
      if (kDebugMode) debugPrint('RealBleClient._safeCancel: $e\n$st');
    }
  }
}
