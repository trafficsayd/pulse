import 'dart:convert';
import 'dart:typed_data';

/// Strict, versioned payload carried by a Pulse pairing QR code.
///
/// The public key binds the visual QR exchange to the key fetched from the
/// signaling rendezvous. The joiner must compare both before deriving a
/// shared secret.
final class PairingQrPayload {
  PairingQrPayload._({
    required this.code,
    required this.hostPublicKeyBase64Url,
    required this.hostPublicKey,
  });

  static const int protocolVersion = 1;
  static final RegExp _codePattern = RegExp(r'^\d{6}$');
  static final RegExp _publicKeyPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

  final String code;
  final String hostPublicKeyBase64Url;
  final Uint8List hostPublicKey;

  static String encode({
    required String code,
    required String hostPublicKeyBase64Url,
  }) {
    _validateCode(code);
    _decodePublicKey(hostPublicKeyBase64Url);
    return Uri(
      scheme: 'pulse',
      host: 'pair',
      queryParameters: <String, String>{
        'v': protocolVersion.toString(),
        'code': code,
        'pk': hostPublicKeyBase64Url,
      },
    ).toString();
  }

  factory PairingQrPayload.parse(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.scheme != 'pulse' ||
        uri.host != 'pair' ||
        uri.path.isNotEmpty ||
        uri.hasPort ||
        uri.fragment.isNotEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const PairingQrPayloadException('Not a Pulse pairing QR code');
    }

    const requiredKeys = <String>{'v', 'code', 'pk'};
    final parameters = uri.queryParametersAll;
    if (parameters.keys.toSet().difference(requiredKeys).isNotEmpty ||
        requiredKeys.difference(parameters.keys.toSet()).isNotEmpty ||
        parameters.values.any((values) => values.length != 1)) {
      throw const PairingQrPayloadException(
        'Pairing QR fields are missing, duplicated, or unsupported',
      );
    }
    if (parameters['v']!.single != protocolVersion.toString()) {
      throw const PairingQrPayloadException(
        'Unsupported pairing QR protocol version',
      );
    }

    final code = parameters['code']!.single;
    final encodedPublicKey = parameters['pk']!.single;
    _validateCode(code);
    final publicKey = _decodePublicKey(encodedPublicKey);
    return PairingQrPayload._(
      code: code,
      hostPublicKeyBase64Url: encodedPublicKey,
      hostPublicKey: publicKey,
    );
  }

  static void _validateCode(String code) {
    if (!_codePattern.hasMatch(code)) {
      throw const PairingQrPayloadException(
        'Pairing code must contain exactly six digits',
      );
    }
  }

  static Uint8List _decodePublicKey(String encoded) {
    if (!_publicKeyPattern.hasMatch(encoded)) {
      throw const PairingQrPayloadException(
        'Pairing QR public key has an invalid encoding',
      );
    }
    try {
      final decoded = base64Url.decode('$encoded=');
      if (decoded.length != 32) {
        throw const PairingQrPayloadException(
          'Pairing QR public key must be 32 bytes',
        );
      }
      return Uint8List.fromList(decoded);
    } on FormatException {
      throw const PairingQrPayloadException(
        'Pairing QR public key has an invalid encoding',
      );
    }
  }
}

final class PairingQrPayloadException implements FormatException {
  const PairingQrPayloadException(this.message);

  @override
  final String message;

  @override
  int? get offset => null;

  @override
  Object? get source => null;

  @override
  String toString() => 'PairingQrPayloadException: $message';
}

/// The QR and signaling rendezvous disagree about the host identity.
/// Continuing would allow a substituted public key to bypass QR binding.
final class PairingQrKeyMismatchException implements Exception {
  const PairingQrKeyMismatchException();

  @override
  String toString() =>
      'PairingQrKeyMismatchException: QR and signaling keys differ';
}
