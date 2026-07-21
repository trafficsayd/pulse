import 'dart:async';
import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

import 'ble_transport_exception.dart';

/// Runtime permissions Pulse needs before it can touch the BLE radio.
///
/// On Android 12+ each of `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, and
/// `BLUETOOTH_ADVERTISE` is a separate runtime grant. On iOS Bluetooth
/// is gated by a single `NSBluetoothAlwaysUsageDescription` prompt, so
/// the gate degenerates to a no-op there.
abstract interface class BlePermissionGate {
  /// Request all BLE permissions the current role needs. Throws
  /// [BleTransportException] with [BleTransportFailure.permissionDenied]
  /// if any of them is refused.
  ///
  /// [advertise] is true for the peripheral role and false for the
  /// central role — we don't ask for `bluetoothAdvertise` on central
  /// because some OEMs surface it as a separate scary toggle.
  Future<void> ensureGranted({required bool advertise});
}

/// Default implementation using `permission_handler`.
class RealBlePermissionGate implements BlePermissionGate {
  const RealBlePermissionGate();

  @override
  Future<void> ensureGranted({required bool advertise}) async {
    if (!Platform.isAndroid) {
      // iOS uses Info.plist usage description + a single OS-managed
      // prompt that the BLE stack triggers on first scan — there is no
      // `permission_handler` analog to request up front.
      return;
    }
    final required = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      if (advertise) Permission.bluetoothAdvertise,
    ];
    final statuses = await required.request();
    for (final entry in statuses.entries) {
      if (!entry.value.isGranted) {
        throw BleTransportException.permissionDenied(_humanName(entry.key));
      }
    }
  }

  String _humanName(Permission p) {
    if (p == Permission.bluetoothScan) return 'bluetoothScan';
    if (p == Permission.bluetoothConnect) return 'bluetoothConnect';
    if (p == Permission.bluetoothAdvertise) return 'bluetoothAdvertise';
    return p.toString();
  }
}
