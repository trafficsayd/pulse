import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/transport/webrtc_transport.dart';

void main() {
  group('WebRtcTransport.isOfferer', () {
    test('the lexicographically larger client id is the offerer', () {
      expect(WebRtcTransport.isOfferer('ffff', '0000'), isTrue);
      expect(WebRtcTransport.isOfferer('0000', 'ffff'), isFalse);
    });

    test('is symmetric: exactly one peer offers', () {
      const a = 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4';
      const b = '0011223344556677889900aabbccddee';
      // Whatever the ids, the two peers must disagree on who offers.
      expect(WebRtcTransport.isOfferer(a, b),
          isNot(WebRtcTransport.isOfferer(b, a)));
    });

    test('a degenerate id collision fails closed (neither offers)', () {
      // Astronomically unlikely with 128 bits, but must not deadlock into
      // two offerers.
      expect(WebRtcTransport.isOfferer('same', 'same'), isFalse);
    });
  });

  group('WebRtcTransport.parseRoleClaim', () {
    test('extracts the client id from a role-claim entry', () {
      expect(WebRtcTransport.parseRoleClaim('pulse-role:deadbeef'), 'deadbeef');
    });

    test('returns null for a real ICE candidate line', () {
      expect(
        WebRtcTransport.parseRoleClaim(
          'candidate:842163049 1 udp 1677729535 …',
        ),
        isNull,
      );
    });

    test('returns null for empty / unrelated strings', () {
      expect(WebRtcTransport.parseRoleClaim(''), isNull);
      expect(WebRtcTransport.parseRoleClaim('role:nope'), isNull);
    });
  });
}
