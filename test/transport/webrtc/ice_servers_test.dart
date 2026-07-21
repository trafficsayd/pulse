import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/transport/webrtc/ice_servers.dart';

void main() {
  group('kIceServers', () {
    test('lists the two public STUN servers first', () {
      expect(kIceServers.length, 3);
      expect(kIceServers[0].urls.single, 'stun:stun.l.google.com:19302');
      expect(kIceServers[1].urls.single, 'stun:stun.cloudflare.com:3478');
    });

    test('includes the Pulse TURN placeholder', () {
      expect(kIceServers[2].urls.single, startsWith('turn:'));
    });

    test('STUN entries do not advertise auth fields in the wire map', () {
      final Map<String, Object> map = kIceServers[0].toMap();
      expect(map.containsKey('username'), isFalse);
      expect(map.containsKey('credential'), isFalse);
    });

    test('TURN entry without --dart-define has no credentials', () {
      // The default build (no TURN_USER / TURN_CRED set) must NOT leak
      // empty-string credentials into the WebRTC map. We assert the
      // public flag the rest of the app uses to gate TURN behaviour.
      expect(hasTurnCredentials, isFalse);
      final Map<String, Object> map = kIceServers[2].toMap();
      expect(map.containsKey('username'), isFalse);
      expect(map.containsKey('credential'), isFalse);
    });
  });

  group('IceServer.toMap', () {
    test('emits credentials only when both username and credential are set',
        () {
      const IceServer entry = IceServer(
        urls: <String>['turn:turn.example.test:3478'],
        username: 'alice',
        credential: 's3cr3t',
      );
      expect(
        entry.toMap(),
        equals(<String, Object>{
          'urls': <String>['turn:turn.example.test:3478'],
          'username': 'alice',
          'credential': 's3cr3t',
        }),
      );
    });

    test('omits empty credential strings', () {
      const IceServer entry = IceServer(
        urls: <String>['turn:turn.example.test:3478'],
        username: '',
        credential: '',
      );
      final Map<String, Object> map = entry.toMap();
      expect(map.containsKey('username'), isFalse);
      expect(map.containsKey('credential'), isFalse);
    });
  });
}
