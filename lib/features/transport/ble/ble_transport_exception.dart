/// Reason a Pulse BLE transport operation failed.
///
/// Kept narrow on purpose so the UI can map straight to a localised
/// string without inspecting [BleTransportException.cause]. New variants
/// must be appended at the bottom — they are part of the public contract
/// between transport and presentation layers.
enum BleTransportFailure {
  /// One of `bluetoothScan`, `bluetoothConnect`, or `bluetoothAdvertise`
  /// was refused by the OS at runtime. The user is offered a deeplink
  /// into system settings.
  permissionDenied,

  /// No peripheral advertising the Pulse service was found inside the
  /// scan window. The hub shows the "still searching" state and the
  /// manager moves on to the next transport tier.
  scanTimeout,

  /// The peer disappeared after a successful GATT connection — either
  /// the radio link dropped or the peripheral terminated the session.
  /// Higher layers treat this as recoverable and re-arm scanning.
  disconnected,

  /// A GATT write was rejected (busy, too long for the negotiated MTU,
  /// or the peer NACKed). The packet was NOT delivered and is not
  /// retried — Pulse never queues mode events.
  writeFailed,
}

/// Failure raised by any of the BLE transport classes
/// (`RealBleClient`, `RealBlePeripheral`).
///
/// Callers should match on [reason] rather than parsing [message]. The
/// optional [cause] preserves the underlying exception (typically from
/// `flutter_blue_plus`) so logs can surface it without breaking the
/// public contract.
class BleTransportException implements Exception {
  const BleTransportException(this.reason, this.message, {this.cause});

  /// Convenience constructor for permission refusal.
  const BleTransportException.permissionDenied([String? which])
      : reason = BleTransportFailure.permissionDenied,
        message = which == null
            ? 'Bluetooth permission was denied.'
            : 'Bluetooth permission "$which" was denied.',
        cause = null;

  /// Convenience constructor for an empty scan window.
  const BleTransportException.scanTimeout(Duration window)
      : reason = BleTransportFailure.scanTimeout,
        message = 'No Pulse peer was found within the scan window.',
        cause = window;

  /// Convenience constructor for a mid-session link drop.
  const BleTransportException.disconnected([String? detail])
      : reason = BleTransportFailure.disconnected,
        message = detail == null
            ? 'BLE peer disconnected.'
            : 'BLE peer disconnected: $detail',
        cause = null;

  /// Convenience constructor for a failed GATT write.
  const BleTransportException.writeFailed(Object underlying)
      : reason = BleTransportFailure.writeFailed,
        message = 'Failed to write packet to the BLE peer.',
        cause = underlying;

  /// Machine-readable failure variant.
  final BleTransportFailure reason;

  /// Human-readable English fallback. The UI normally resolves a
  /// localised string from [reason]; [message] is for logs and tests.
  final String message;

  /// Optional underlying error preserved for diagnostics.
  final Object? cause;

  @override
  String toString() => 'BleTransportException(${reason.name}): $message';
}
