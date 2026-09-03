import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulse/core/storage/secure_key_store.dart';
import 'package:pulse/features/pairing/application/pairing_controller.dart';
import 'package:pulse/features/pairing/domain/pairing_qr_payload.dart';
import 'package:pulse/features/transport/webrtc/signaling_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class _MemoryStorage implements FlutterSecureStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _values.remove(key);
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _values.clear();
  }

  @override
  Future<bool> containsKey({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _values.containsKey(key);

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      Map<String, String>.from(_values);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RendezvousServer {
  _RendezvousServer({
    this.answerReadFailuresRemaining = 0,
    this.answerReadFailureStatus = 503,
  });

  int answerReadFailuresRemaining;
  final int answerReadFailureStatus;
  final Map<String, String> _pairingToSession = <String, String>{};
  final Map<String, String> _offerBySession = <String, String>{};
  final Map<String, String> _answerBySession = <String, String>{};
  int _next = 0;
  int answerReadRequests = 0;

  late final MockClient client = MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    if (request.method == 'POST' && request.url.path == '/session') {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      final code = body['pairingCode']! as String;
      final sessionId = _pairingToSession.putIfAbsent(
        code,
        () => (++_next).toRadixString(16).padLeft(6, '0'),
      );
      return _json(<String, Object?>{
        'sessionId': sessionId,
        'token': 'token-$sessionId',
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 10))
            .millisecondsSinceEpoch,
      }, 201);
    }

    final match = RegExp(r'^/session/([0-9a-f]{6})/(offer|answer)$').firstMatch(
      request.url.path,
    );
    if (match == null) return http.Response('not found', 404);
    final sessionId = match.group(1)!;
    final kind = match.group(2)!;

    if (request.method == 'POST') {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      final sdp = body['sdp']! as String;
      if (kind == 'offer') {
        _offerBySession[sessionId] = sdp;
      } else {
        _answerBySession[sessionId] = sdp;
      }
      return _json(<String, Object?>{'ok': true}, 200);
    }

    if (request.method == 'GET') {
      if (kind == 'answer') answerReadRequests++;
      if (kind == 'answer' && answerReadFailuresRemaining > 0) {
        answerReadFailuresRemaining--;
        return http.Response(
          'temporary edge failure',
          answerReadFailureStatus,
        );
      }
      final sdp = kind == 'offer'
          ? _offerBySession[sessionId]
          : _answerBySession[sessionId];
      if (sdp == null) return http.Response('', 204);
      return _json(<String, Object?>{'type': kind, 'sdp': sdp}, 200);
    }

    return http.Response('method not allowed', 405);
  }

  http.Response _json(Map<String, Object?> body, int status) => http.Response(
        jsonEncode(body),
        status,
        headers: <String, String>{'content-type': 'application/json'},
      );
}

void main() {
  test('host and guest derive the same pair over signaling code', () async {
    final server = _RendezvousServer();
    final host = _container(server);
    final guest = _container(server);
    addTearDown(host.dispose);
    addTearDown(guest.dispose);

    final hostController = host.read(pairingControllerProvider.notifier);
    final guestController = guest.read(pairingControllerProvider.notifier);
    final hostFuture = hostController.startHostHandshake(
      timeout: const Duration(seconds: 5),
    );

    await _waitFor(
      host,
      (state) => state.pairingCode != null && state.localKeyPair != null,
    );
    final hostPairing = host.read(pairingControllerProvider);
    final code = hostPairing.pairingCode!;

    await guestController.joinHandshake(
      code,
      expectedHostPublicKey: hostPairing.localKeyPair!.publicKey.bytes,
      timeout: const Duration(seconds: 5),
    );
    await hostFuture;

    final hostState = host.read(pairingControllerProvider);
    final guestState = guest.read(pairingControllerProvider);
    expect(hostState.phase, PairingPhase.awaitingConfirmation);
    expect(guestState.phase, PairingPhase.awaitingConfirmation);
    expect(hostState.sasCode, guestState.sasCode);
    expect(hostState.connectionId, guestState.connectionId);

    final hostKeys = await hostController.confirmAndPersist();
    final guestKeys = await guestController.confirmAndPersist();
    expect(hostKeys?.connectionId, guestKeys?.connectionId);
    expect(hostKeys?.symmetricKey, guestKeys?.symmetricKey);
  });

  test('host survives a transient answer poll failure', () async {
    final server = _RendezvousServer(answerReadFailuresRemaining: 1);
    final host = _container(server);
    final guest = _container(server);
    addTearDown(host.dispose);
    addTearDown(guest.dispose);

    final hostController = host.read(pairingControllerProvider.notifier);
    final guestController = guest.read(pairingControllerProvider.notifier);
    final hostFuture = hostController.startHostHandshake(
      timeout: const Duration(seconds: 5),
    );

    await _waitFor(host, (state) => state.pairingCode != null);
    final code = host.read(pairingControllerProvider).pairingCode!;
    await guestController.joinHandshake(
      code,
      timeout: const Duration(seconds: 5),
    );
    await hostFuture;

    expect(
      host.read(pairingControllerProvider).phase,
      PairingPhase.awaitingConfirmation,
    );
    expect(
      host.read(pairingControllerProvider).sasCode,
      guest.read(pairingControllerProvider).sasCode,
    );
  });

  test('host survives a fresh-session 404 from an eventual edge', () async {
    final server = _RendezvousServer(
      answerReadFailuresRemaining: 1,
      answerReadFailureStatus: 404,
    );
    final host = _container(server);
    final guest = _container(server);
    addTearDown(host.dispose);
    addTearDown(guest.dispose);

    final hostController = host.read(pairingControllerProvider.notifier);
    final guestController = guest.read(pairingControllerProvider.notifier);
    final hostFuture = hostController.startHostHandshake(
      timeout: const Duration(seconds: 5),
    );

    await _waitFor(host, (state) => state.pairingCode != null);
    final code = host.read(pairingControllerProvider).pairingCode!;
    await guestController.joinHandshake(
      code,
      timeout: const Duration(seconds: 5),
    );
    await hostFuture;

    expect(
      host.read(pairingControllerProvider).phase,
      PairingPhase.awaitingConfirmation,
    );
    expect(
      host.read(pairingControllerProvider).sasCode,
      guest.read(pairingControllerProvider).sasCode,
    );
  });

  test('reset cancels an in-flight host poll', () async {
    final server = _RendezvousServer();
    final host = _container(server);
    addTearDown(host.dispose);

    final controller = host.read(pairingControllerProvider.notifier);
    final handshake = controller.startHostHandshake(
      timeout: const Duration(seconds: 5),
    );
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (
        server.answerReadRequests == 0 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(server.answerReadRequests, greaterThan(0));

    controller.reset();
    await handshake.timeout(const Duration(seconds: 1));
    final readsAfterReset = server.answerReadRequests;
    await Future<void>.delayed(const Duration(milliseconds: 600));

    expect(host.read(pairingControllerProvider).phase, PairingPhase.idle);
    expect(server.answerReadRequests, readsAfterReset);
  });

  test('QR join fails closed when signaling returns a different host key',
      () async {
    final server = _RendezvousServer();
    final host = _container(server);
    final guest = _container(server);
    addTearDown(host.dispose);
    addTearDown(guest.dispose);

    final hostController = host.read(pairingControllerProvider.notifier);
    final guestController = guest.read(pairingControllerProvider.notifier);
    final hostFuture = hostController.startHostHandshake(
      timeout: const Duration(seconds: 5),
    );
    await _waitFor(
      host,
      (state) => state.pairingCode != null && state.localKeyPair != null,
    );
    final hostState = host.read(pairingControllerProvider);
    final wrongKey = List<int>.from(hostState.localKeyPair!.publicKey.bytes);
    wrongKey[0] ^= 1;

    await guestController.joinHandshake(
      hostState.pairingCode!,
      expectedHostPublicKey: wrongKey,
      timeout: const Duration(seconds: 2),
    );

    final guestState = guest.read(pairingControllerProvider);
    expect(guestState.phase, PairingPhase.failed);
    expect(guestState.error, isA<PairingQrKeyMismatchException>());
    expect(guestState.sharedSecret, isNull);
    hostController.reset();
    await hostFuture;
  });
}

ProviderContainer _container(_RendezvousServer server) {
  return ProviderContainer(
    overrides: <Override>[
      secureKeyStoreProvider.overrideWithValue(
        SecureKeyStore(storage: _MemoryStorage()),
      ),
      pairingSignalingClientProvider.overrideWith(
        (ref) => SignalingClient(
          httpClient: server.client,
          baseUrl: 'https://example.test',
          shortGetTimeout: const Duration(milliseconds: 200),
        ),
      ),
    ],
  );
}

Future<void> _waitFor(
  ProviderContainer container,
  bool Function(PairingState state) test,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (DateTime.now().isBefore(deadline)) {
    if (test(container.read(pairingControllerProvider))) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw TimeoutException('Pairing state did not satisfy predicate');
}
