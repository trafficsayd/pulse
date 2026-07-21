import 'dart:convert';
import 'dart:typed_data';

import '../transport.dart';

/// Wire-level alias for a packet that travels across the BLE GATT
/// characteristics. The BLE layer never inspects the encrypted payload —
/// see Track B's `PairChannel` for the sealed envelope inside it.
typedef Packet = TransportPacket;

/// JSON-encode a [Packet] into a single GATT write frame.
///
/// The on-the-wire shape is intentionally tiny so it fits inside the
/// default 23-byte BLE ATT MTU after the kind/header overhead. Mode
/// payloads that exceed this are the responsibility of higher layers
/// (chunking lives in Track B, not here).
///
/// Format:
/// ```json
/// {"k":"mode_event","p":"<base64-encoded encrypted bytes>"}
/// ```
Uint8List packetEncoder(Packet packet) {
  final json = jsonEncode({
    'k': packet.kind,
    'p': base64.encode(packet.payload),
  });
  return Uint8List.fromList(utf8.encode(json));
}

/// Inverse of [packetEncoder]. Throws [FormatException] if the frame is
/// malformed; callers should catch this and treat it as a tamper /
/// truncation event rather than crashing.
Packet packetDecoder(List<int> bytes) {
  final raw = jsonDecode(utf8.decode(bytes));
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('packet is not a JSON object');
  }
  final kind = raw['k'];
  final payloadB64 = raw['p'];
  if (kind is! String || payloadB64 is! String) {
    throw const FormatException('packet is missing "k" or "p"');
  }
  return TransportPacket(
    kind: kind,
    payload: Uint8List.fromList(base64.decode(payloadB64)),
  );
}
