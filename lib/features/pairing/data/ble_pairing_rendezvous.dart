import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:uuid/uuid.dart';

import '../../transport/ble/ble_client.dart';
import '../../transport/ble/ble_transport_exception.dart';
import '../../transport/ble/packet_codec.dart';
import '../../transport/ble/real_ble_client.dart';
import '../../transport/ble/real_ble_peripheral.dart';

/// Offline key-exchange rendezvous over BLE — the "no internet right now"
/// pairing path (spec §4: работа без интернета).
///
/// The signaling Worker is nothing more than a public-key mailbox, so BLE
/// can replace it wholesale: the host advertises the Pulse GATT service and
/// the joiner connects as a central, exactly like the post-pairing signal
/// transport already does. Three tiny JSON frames ride the existing
/// [packetEncoder] format:
///
///  * `pair_hello` (joiner → host, RX write):
///    `{"v":1,"code":"<6 digits>","pub":"<base64url X25519>"}`
///  * `pair_reply` (host → joiner, TX notify):
///    `{"v":1,"pub":"<base64url>","cid":"<uuid>","token":"<random hex>"}`
///  * `pair_nack`  (host → joiner, TX notify): `{"v":1,"reason":"..."}`
///
/// The host checks the six-digit code before revealing its public key, so a
/// stranger scanning nearby learns nothing without the code. Man-in-the-middle
/// protection stays where it always was: the SAS comparison in
/// `PairingController.confirmAndPersist` — this layer only swaps public keys.
///
/// Roles match the radio reality: only Android can advertise
/// ([RealBlePeripheral.isSupported]), so the HOST path is Android-only, while
/// the JOINER path (central scan) works on both platforms. Two iPhones with
/// no internet remain a v-next gap (needs CBPeripheralManager).
const String kBlePairHelloKind = 'pair_hello';
const String kBlePairReplyKind = 'pair_reply';
const String kBlePairNackKind = 'pair_nack';

/// Protocol version stamped into every frame.
const int kBlePairProtocolVersion = 1;

/// How long the joiner scans for an advertising host before giving up.
const Duration kBlePairScanTimeout = Duration(seconds: 15);

/// Outcome of a successful BLE key exchange — mirrors what the signaling
/// path produces so `PairingController` can feed either into the same
/// derive → SAS → persist tail.
@immutable
class BlePairingResult {
  const BlePairingResult({
    required this.peerPublicKeyBase64,
    required this.connectionId,
    required this.signalingToken,
  });

  /// Partner's raw X25519 public key, base64url without padding.
  final String peerPublicKeyBase64;

  /// Connection id minted by the host (uuid v4) — both sides persist the
  /// same id, exactly like `SignalingSession.sessionId` online.
  final String connectionId;

  /// Shared random token for future internet reconnects. Opaque here.
  final String signalingToken;
}

/// Host rejected our hello (wrong code, malformed frame, …).
class BlePairingRejectedException implements Exception {
  const BlePairingRejectedException(this.reason);

  /// Machine-readable reason from the `pair_nack` frame.
  final String reason;

  @override
  String toString() => 'BlePairingRejectedException($reason)';
}

Uint8List _encodeBody(Map<String, Object?> body) =>
    Uint8List.fromList(utf8.encode(jsonEncode(body)));

Map<String, Object?>? _decodeBody(Uint8List payload) {
  try {
    final raw = jsonDecode(utf8.decode(payload));
    return raw is Map<String, Object?> ? raw : null;
  } on FormatException {
    return null;
  }
}

/// Best-effort "turn Bluetooth on" nudge. After airplane mode Android
/// leaves the adapter off and users rarely notice — `turnOn` pops the
/// system enable dialog. A refusal becomes a clear, mappable error;
/// anything else (missing plugin in tests, unsupported platform) is
/// swallowed so the actual radio call can report its own failure.
Future<void> _ensureAdapterOn() async {
  try {
    if (!Platform.isAndroid) return;
    if (await fbp.FlutterBluePlus.adapterState.first ==
        fbp.BluetoothAdapterState.on) {
      return;
    }
    await fbp.FlutterBluePlus.turnOn();
  } on fbp.FlutterBluePlusException {
    throw const BleTransportException(
      BleTransportFailure.writeFailed,
      'Bluetooth is turned off and the user declined to enable it.',
    );
  } catch (_) {
    // Tests / platforms without the plugin — let start()/connect() speak.
  }
}

/// Host side: advertise, wait for a `pair_hello` carrying the right code,
/// answer with `pair_reply`. One-shot — create a fresh instance per attempt.
class BleHostRendezvous {
  BleHostRendezvous({
    RealBlePeripheral Function()? peripheralFactory,
    Uuid uuid = const Uuid(),
    Random? random,
  })  : _peripheralFactory = peripheralFactory ?? RealBlePeripheral.new,
        _uuid = uuid,
        _random = random ?? Random.secure();

  final RealBlePeripheral Function() _peripheralFactory;
  final Uuid _uuid;
  final Random _random;

  /// Advertising requires the OS to expose a GATT server — Android only
  /// until a CoreBluetooth peripheral is written for iOS.
  static bool get isPlatformSupported => !kIsWeb && Platform.isAndroid;

  /// Advertise the Pulse service and resolve once a joiner presented the
  /// correct [pairingCode]. Wrong-code hellos are NACKed and advertising
  /// continues, so a typo on the joiner's side doesn't burn the session.
  ///
  /// Throws [TimeoutException] when nobody paired within [timeout] and
  /// `BleTransportException` for radio/permission failures.
  Future<BlePairingResult> waitForPartner({
    required String pairingCode,
    required String localPublicKeyBase64,
    required Duration timeout,
  }) async {
    final peripheral = _peripheralFactory();
    final completer = Completer<BlePairingResult>();
    StreamSubscription<Uint8List>? sub;
    Timer? deadline;
    try {
      sub = peripheral.rxWrites.listen((bytes) {
        unawaited(
          _handleFrame(
            peripheral: peripheral,
            bytes: bytes,
            pairingCode: pairingCode,
            localPublicKeyBase64: localPublicKeyBase64,
            completer: completer,
          ),
        );
      });
      await _ensureAdapterOn();
      await peripheral.start();
      deadline = Timer(timeout, () {
        if (!completer.isCompleted) {
          completer.completeError(
            TimeoutException('BLE pairing timed out', timeout),
          );
        }
      });
      final result = await completer.future;
      // Give the just-sent notify a moment to flush before the GATT server
      // is torn down with the advertiser.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await peripheral.markPaired();
      return result;
    } finally {
      deadline?.cancel();
      await sub?.cancel();
      await peripheral.dispose();
    }
  }

  Future<void> _handleFrame({
    required RealBlePeripheral peripheral,
    required Uint8List bytes,
    required String pairingCode,
    required String localPublicKeyBase64,
    required Completer<BlePairingResult> completer,
  }) async {
    if (completer.isCompleted) return;
    final Packet packet;
    try {
      packet = packetDecoder(bytes);
    } on FormatException {
      return; // Foreign/corrupt frame — ignore, keep advertising.
    }
    if (packet.kind != kBlePairHelloKind) return;

    final body = _decodeBody(packet.payload);
    final code = body?['code'];
    final pub = body?['pub'];
    if (body == null ||
        body['v'] != kBlePairProtocolVersion ||
        code is! String ||
        pub is! String ||
        pub.isEmpty) {
      await _sendNack(peripheral, 'bad_hello');
      return;
    }
    if (code != pairingCode) {
      await _sendNack(peripheral, 'code_mismatch');
      return;
    }
    if (completer.isCompleted) return;

    final connectionId = _uuid.v4();
    final token = _randomToken();
    try {
      await peripheral.sendTx(
        packetEncoder(
          Packet(
            kind: kBlePairReplyKind,
            payload: _encodeBody(<String, Object?>{
              'v': kBlePairProtocolVersion,
              'pub': localPublicKeyBase64,
              'cid': connectionId,
              'token': token,
            }),
          ),
        ),
      );
    } catch (e) {
      // Central may have dropped between hello and reply — keep waiting for
      // a reconnect until the outer deadline fires.
      if (kDebugMode) debugPrint('BleHostRendezvous: reply failed: $e');
      return;
    }
    if (!completer.isCompleted) {
      completer.complete(
        BlePairingResult(
          peerPublicKeyBase64: pub,
          connectionId: connectionId,
          signalingToken: token,
        ),
      );
    }
  }

  Future<void> _sendNack(RealBlePeripheral peripheral, String reason) async {
    try {
      await peripheral.sendTx(
        packetEncoder(
          Packet(
            kind: kBlePairNackKind,
            payload: _encodeBody(<String, Object?>{
              'v': kBlePairProtocolVersion,
              'reason': reason,
            }),
          ),
        ),
      );
    } catch (_) {
      // Best effort — the joiner also has its own timeout.
    }
  }

  String _randomToken() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// Joiner side: scan for the advertising host, write `pair_hello`, wait for
/// `pair_reply`. One-shot — create a fresh instance per attempt.
class BleJoinerRendezvous {
  BleJoinerRendezvous({
    BleClient Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? RealBleClient.new;

  final BleClient Function() _clientFactory;

  /// The central role only needs scan+connect, which `flutter_blue_plus`
  /// provides on both mobile platforms.
  static bool get isPlatformSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  /// Connect to the nearby host and exchange public keys.
  ///
  /// Throws [BlePairingRejectedException] when the host NACKs (wrong code),
  /// [TimeoutException] when no reply arrives within [timeout], and
  /// `BleTransportException` for scan/permission failures.
  Future<BlePairingResult> exchange({
    required String pairingCode,
    required String localPublicKeyBase64,
    required Duration timeout,
    Duration scanTimeout = kBlePairScanTimeout,
  }) async {
    final client = _clientFactory();
    final completer = Completer<BlePairingResult>();
    StreamSubscription<Packet>? sub;
    try {
      sub = client.incoming.listen((packet) {
        if (completer.isCompleted) return;
        if (packet.kind == kBlePairReplyKind) {
          final body = _decodeBody(packet.payload);
          final pub = body?['pub'];
          final cid = body?['cid'];
          final token = body?['token'];
          if (body == null ||
              body['v'] != kBlePairProtocolVersion ||
              pub is! String ||
              pub.isEmpty ||
              cid is! String ||
              token is! String) {
            completer.completeError(
              const BlePairingRejectedException('bad_reply'),
            );
            return;
          }
          completer.complete(
            BlePairingResult(
              peerPublicKeyBase64: pub,
              connectionId: cid,
              signalingToken: token,
            ),
          );
        } else if (packet.kind == kBlePairNackKind) {
          final body = _decodeBody(packet.payload);
          final reason = body?['reason'];
          completer.completeError(
            BlePairingRejectedException(
              reason is String ? reason : 'rejected',
            ),
          );
        }
      });
      await _ensureAdapterOn();
      await client.connect(scanTimeout: scanTimeout);
      await client.send(
        Packet(
          kind: kBlePairHelloKind,
          payload: _encodeBody(<String, Object?>{
            'v': kBlePairProtocolVersion,
            'code': pairingCode,
            'pub': localPublicKeyBase64,
          }),
        ),
      );
      return await completer.future.timeout(timeout);
    } finally {
      await sub?.cancel();
      await client.disconnect();
    }
  }
}
