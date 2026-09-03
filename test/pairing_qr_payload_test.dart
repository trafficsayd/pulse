import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/pairing/domain/pairing_qr_payload.dart';

void main() {
  final publicKey = base64Url
      .encode(List<int>.generate(32, (index) => index))
      .replaceAll('=', '');

  test('pairing QR round-trips code and 32-byte host public key', () {
    final encoded = PairingQrPayload.encode(
      code: '123456',
      hostPublicKeyBase64Url: publicKey,
    );

    final decoded = PairingQrPayload.parse(encoded);
    expect(decoded.code, '123456');
    expect(decoded.hostPublicKeyBase64Url, publicKey);
    expect(decoded.hostPublicKey, List<int>.generate(32, (index) => index));
  });

  test('rejects another scheme, version, extra field, and duplicate code', () {
    final invalid = <String>[
      'https://pair?v=1&code=123456&pk=$publicKey',
      'pulse://pair?v=2&code=123456&pk=$publicKey',
      'pulse://pair?v=1&code=123456&pk=$publicKey&admin=true',
      'pulse://pair?v=1&code=123456&code=654321&pk=$publicKey',
      'pulse://pair:42?v=1&code=123456&pk=$publicKey',
      'pulse://pair/?v=1&code=123456&pk=$publicKey',
    ];

    for (final value in invalid) {
      expect(
        () => PairingQrPayload.parse(value),
        throwsA(isA<PairingQrPayloadException>()),
        reason: value,
      );
    }
  });

  test('rejects malformed codes and public keys', () {
    final invalid = <String>[
      'pulse://pair?v=1&code=12345&pk=$publicKey',
      'pulse://pair?v=1&code=12345a&pk=$publicKey',
      'pulse://pair?v=1&code=123456&pk=short',
      'pulse://pair?v=1&code=123456&pk=${List.filled(42, 'A').join()}!',
    ];

    for (final value in invalid) {
      expect(
        () => PairingQrPayload.parse(value),
        throwsA(isA<PairingQrPayloadException>()),
        reason: value,
      );
    }
  });
}
