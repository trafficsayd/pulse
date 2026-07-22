import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulse/core/storage/secure_key_store.dart';
import 'package:pulse/features/pairing/application/pairing_controller.dart';
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
  final Map<String, String> _pairingToSession = <String, String>{};
  final Map<String, String> _offerBySession = <String, String>{};
  final Map<String, String> _answerBySession = <String, String>{};
  int _next = 0;

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

    await _waitFor(host, (s) => s.pairingCode != null);
    final code = host.read(pairingControllerProvider).pairingCode!;

    await guestController.joinHandshake(
      code,
      timeout: const Duration(seconds: 5),
    );
    await hostFuture;

    final hostState = host.read(pairingControllerProvider);
    final guestState = guest.read(pairingControllerProvider);
    expect(hostState.phase, PairingPhase.awaitingConfirmation);
    expect(guestState.phase, PairingPhase.awaitingConfirmation);
    expect(hostState.sasCode, guestState.sasCode);
    expect(hostState.connectionId, guestState.connectionId);

    // Both users compared the SAS on their screens and it matched.
    final hostKeys = await hostController.confirmAndPersist(sasConfirmed: true);
    final guestKeys =
        await guestController.confirmAndPersist(sasConfirmed: true);
    expect(hostKeys?.connectionId, guestKeys?.connectionId);
    expect(hostKeys?.symmetricKey, guestKeys?.symmetricKey);

    // SECURITY: the ephemeral private key must never be persisted.
    expect(hostKeys?.localPrivateKey, isNull);
    expect(guestKeys?.localPrivateKey, isNull);
  });

  test('confirmAndPersist refuses to persist when SAS is not confirmed',
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
    await _waitFor(host, (s) => s.pairingCode != null);
    final code = host.read(pairingControllerProvider).pairingCode!;
    await guestController.joinHandshake(code,
        timeout: const Duration(seconds: 5));
    await hostFuture;

    // User did NOT confirm the codes match — persisting must be refused and
    // no key material may be returned (anti-MITM gate).
    final refused = await hostController.confirmAndPersist(sasConfirmed: false);
    expect(refused, isNull);
    expect(host.read(pairingControllerProvider).phase, PairingPhase.failed);
    expect(
      host.read(pairingControllerProvider).error,
      isA<SasNotConfirmedException>(),
    );
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
