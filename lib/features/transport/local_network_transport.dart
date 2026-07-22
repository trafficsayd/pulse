import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'transport.dart';

/// Local-network transport using plain TCP sockets (`dart:io`).
///
/// Both peers attempt to bind a [ServerSocket] on a deterministic port
/// derived from the connection's signaling token. Whichever succeeds first
/// becomes the listener; the other connects as a client. Once the TCP
/// handshake completes, both sides exchange their identity tokens to verify
/// they are talking to the right peer.
///
/// Payloads are JSON-encoded (`{"k":"<kind>","p":"<base64>"}`) — the bytes
/// are already sealed by `PairChannel`, so the transport only needs framing,
/// not additional encryption.
class LocalNetworkTransport implements Transport {
  LocalNetworkTransport();

  // ignore: close_sinks
  final _incoming = StreamController<TransportPacket>.broadcast();
  // ignore: close_sinks
  final _state = StreamController<TransportKind>.broadcast();

  bool _connected = false;
  ServerSocket? _server;
  Socket? _socket;
  StreamSubscription<dynamic>? _serverSub;
  StreamSubscription<dynamic>? _socketSub;
  String? _identityToken;

  /// Exponential backoff state for reconnection.
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;

  @override
  TransportKind get kind => TransportKind.localNetwork;

  @override
  bool get isConnected => _connected;

  @override
  Stream<TransportPacket> get incoming => _incoming.stream;

  @override
  Stream<TransportKind> get state => _state.stream;

  @override
  Future<void> connect({required Map<String, String> reconnectTokens}) async {
    _state.add(TransportKind.searching);
    _identityToken = reconnectTokens['signalingToken'] ?? '';

    final port = _portFromToken(_identityToken!);
    if (kDebugMode) debugPrint('[LAN] attempting to bind port $port');

    // Try to become the listener first.
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      if (kDebugMode) debugPrint('[LAN] listening on port $port');
      _serverSub = _server!.listen(_onClientConnected);
      final host = reconnectTokens['localNetworkHost'];
      if (host != null && host.isNotEmpty) {
        unawaited(_tryConnect(port, host: host));
      }
    } on SocketException {
      // Port already in use — another peer is already listening. Connect.
      if (kDebugMode) debugPrint('[LAN] port $port in use — connecting as client');
      await _tryConnect(port, host: reconnectTokens['localNetworkHost']);
    }
  }

  @override
  Future<void> send(TransportPacket packet) async {
    final socket = _socket;
    if (socket == null || !_connected) return;

    final encoded = jsonEncode({
      'k': packet.kind,
      'p': base64Encode(packet.payload),
    });
    socket.writeln(encoded);
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    await _serverSub?.cancel();
    _serverSub = null;
    await _socketSub?.cancel();
    _socketSub = null;
    await _server?.close();
    _server = null;
    await _socket?.close();
    _socket = null;
    _reconnectAttempts = 0;
    _state.add(TransportKind.searching);
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// Deterministic port in the dynamic/private range: 49152 + (hash % 16384).
  static int _portFromToken(String token) {
    var hash = 0x811C9DC5; // FNV-1a 32-bit offset basis.
    for (final byte in utf8.encode(token)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return 49152 + (hash % 16384);
  }

  /// Handle an incoming TCP client on the server socket.
  void _onClientConnected(Socket client) {
    if (kDebugMode) {
      debugPrint('[LAN] client connected from ${client.remoteAddress.address}');
    }
    _attachSocket(client);
  }

  /// Try to connect as a client to localhost on [port].
  Future<void> _tryConnect(int port, {String? host}) async {
    final targetHost = host == null || host.isEmpty
        ? InternetAddress.loopbackIPv4.address
        : host;
    while (_reconnectAttempts < _maxReconnectAttempts && !_connected) {
      try {
        final socket = await Socket.connect(
          targetHost,
          port,
          timeout: const Duration(seconds: 5),
        );
        if (kDebugMode) {
          debugPrint('[LAN] connected to $targetHost:$port as client');
        }
        _attachSocket(socket);
        return;
      } on SocketException catch (e) {
        _reconnectAttempts++;
        final delay = Duration(
          seconds: _backoffSeconds(_reconnectAttempts),
        );
        if (kDebugMode) {
          debugPrint(
            '[LAN] connect attempt $_reconnectAttempts failed: $e — '
            'retrying in ${delay.inSeconds}s',
          );
        }
        await Future<void>.delayed(delay);
      }
    }
  }

  /// Attach to an established socket — send identity, listen for data.
  void _attachSocket(Socket socket) {
    _socket = socket;
    _reconnectAttempts = 0;

    // Send our identity token as the first line.
    socket.writeln(jsonEncode({'identity': _identityToken}));

    // Buffer for line-based reading.
    final buffer = StringBuffer();
    _socketSub = socket.cast<List<int>>().transform(utf8.decoder).listen(
      (data) {
        buffer.write(data);
        var content = buffer.toString();
        var newlineIdx = content.indexOf('\n');
        while (newlineIdx != -1) {
          final line = content.substring(0, newlineIdx).trim();
          content = content.substring(newlineIdx + 1);
          _onLine(line);
          newlineIdx = content.indexOf('\n');
        }
        buffer
          ..clear()
          ..write(content);
      },
      onError: (Object e) {
        if (kDebugMode) debugPrint('[LAN] socket error: $e');
        _onDisconnected();
      },
      onDone: () {
        if (kDebugMode) debugPrint('[LAN] socket closed');
        _onDisconnected();
      },
    );
  }

  /// Process a single received line (JSON).
  void _onLine(String line) {
    if (line.isEmpty) return;
    try {
      final json = jsonDecode(line) as Map<String, dynamic>;

      // Identity handshake line.
      if (json.containsKey('identity')) {
        final peerToken = json['identity'] as String;
        // SECURITY (§4/§14 zero-logging): never print the reconnection token
        // value — it is sensitive pairing material. Log only that an
        // identity line arrived, and only in debug builds.
        if (kDebugMode) debugPrint('[LAN] peer identity received');
        final expected = _identityToken;
        if (expected != null && expected.isNotEmpty && peerToken != expected) {
          if (kDebugMode) {
            debugPrint('[LAN] peer identity mismatch — disconnecting');
          }
          unawaited(disconnect());
          return;
        }
        // Mark as connected after identity exchange.
        if (!_connected) {
          _connected = true;
          _state.add(TransportKind.localNetwork);
        }
        return;
      }

      // Regular data packet.
      final packetKind = json['k'] as String?;
      final payloadB64 = json['p'] as String?;
      if (packetKind != null && payloadB64 != null) {
        _incoming.add(TransportPacket(
          kind: packetKind,
          payload: base64Decode(payloadB64),
        ));
      }
    } catch (e) {
      // SECURITY (§4/§14 zero-logging): the raw line may itself be a
      // malformed identity/token exchange — never print its contents,
      // only that a line failed to parse and why.
      if (kDebugMode) debugPrint('[LAN] malformed line dropped: $e');
    }
  }

  void _onDisconnected() {
    if (!_connected) return;
    _connected = false;
    _state.add(TransportKind.searching);
    _socket = null;
  }

  /// Exponential backoff: 1s, 2s, 4s, 8s, 16s capped at 30s.
  static int _backoffSeconds(int attempt) {
    final seconds = 1 << (attempt - 1); // 1, 2, 4, 8, 16
    return seconds.clamp(1, 30);
  }
}
