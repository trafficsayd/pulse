import 'dart:async';

import '../../../l10n/app_localizations.dart';
import '../../transport/ble/ble_transport_exception.dart';
import '../data/ble_pairing_rendezvous.dart';

/// Human-readable, localized reason for a failed pairing handshake.
///
/// Turns the raw [Object] stored in `PairingState.error` into something a
/// user standing in a field with two phones can actually act on —
/// «включите Bluetooth» beats «Что-то пошло не так» every time.
String describePairingError(AppLocalizations t, Object? error) {
  if (error == null) return t.errorGeneric;
  if (error is BlePairingRejectedException) {
    return error.reason == 'code_mismatch'
        ? t.pairingErrorCodeMismatch
        : t.pairingErrorRejected;
  }
  if (error is BleTransportException) {
    return switch (error.reason) {
      BleTransportFailure.permissionDenied => t.pairingErrorPermission,
      BleTransportFailure.scanTimeout => t.pairingErrorPartnerNotFound,
      BleTransportFailure.disconnected => t.pairingErrorLinkDropped,
      BleTransportFailure.writeFailed => t.pairingErrorBluetooth,
    };
  }
  if (error is TimeoutException) return t.pairingErrorTimeout;
  return t.errorGeneric;
}

/// Compact single-line technical detail for field debugging — shown in
/// small muted type under the human message so a tester can report the
/// exact failure without adb access. Empty when there is nothing useful
/// beyond the human message.
String pairingErrorDetail(Object? error) {
  if (error == null) return '';
  final raw = error.toString().replaceAll('\n', ' ').trim();
  return raw.length <= 140 ? raw : '${raw.substring(0, 137)}…';
}
