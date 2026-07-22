import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'ble_transport_exception.dart';

/// Runtime permissions Pulse needs before it can touch the BLE radio.
///
/// On Android 12+ each of `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, and
/// `BLUETOOTH_ADVERTISE` is a separate runtime grant. On Android 11 and
/// below the radio permissions are install-time, but BLE *scanning*
/// additionally requires `ACCESS_FINE_LOCATION` granted at runtime AND
/// system Location Services switched on — without both the scanner
/// silently returns zero results. On iOS Bluetooth is gated by a single
/// `NSBluetoothAlwaysUsageDescription` prompt, so the gate degenerates
/// to a no-op there.
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

  /// Reuses the peripheral MethodChannel that MainActivity always
  /// registers — its `sdkInt` method reports `Build.VERSION.SDK_INT` so
  /// the gate can tell legacy-location Androids (≤11 / API ≤30) apart
  /// from the modern neverForLocation world without another plugin.
  static const MethodChannel _channel =
      MethodChannel('app.pulse.ble/peripheral');

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
    if (await _sdkInt() < 31) {
      // Android ≤11: BLE scan results are gated behind fine location.
      required.add(Permission.locationWhenInUse);
    }
    final statuses = await required.request();
    for (final entry in statuses.entries) {
      if (!entry.value.isGranted) {
        throw BleTransportException.permissionDenied(_humanName(entry.key));
      }
    }
    if (required.contains(Permission.locationWhenInUse)) {
      // Permission granted is not enough on ≤11 — the system Location
      // toggle must also be on, otherwise scans return nothing.
      final service = await Permission.location.serviceStatus;
      if (!service.isEnabled) {
        throw const BleTransportException(
          BleTransportFailure.permissionDenied,
          'Location Services are off — Android 11 and below cannot '
          'scan for BLE devices without them.',
        );
      }
    }
  }

  Future<int> _sdkInt() async {
    try {
      return await _channel.invokeMethod<int>('sdkInt') ?? 31;
    } catch (_) {
      // Channel unavailable (tests, exotic embedding) — assume modern
      // Android and skip the legacy location dance.
      return 31;
    }
  }

  String _humanName(Permission p) {
    if (p == Permission.bluetoothScan) return 'bluetoothScan';
    if (p == Permission.bluetoothConnect) return 'bluetoothConnect';
    if (p == Permission.bluetoothAdvertise) return 'bluetoothAdvertise';
    if (p == Permission.locationWhenInUse) return 'location';
    return p.toString();
  }
}
