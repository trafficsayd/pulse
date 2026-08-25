import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'transport.dart';

/// Local-network transport using plain TCP sockets (`dart:io`).
///
/// Both peers open a TCP listener and advertise it with a small UDP broadcast
/// derived from the connection's opaque signaling token. A stable per-device
/// id elects one dialer, avoiding duplicate cross-connections. When both
/// instances run on one host (tests), the deterministic TCP-port collision is
/// also used as a fast loopback path. Once connected, both sides exchange
/// identity tokens to verify they are talking to the right peer.
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
  RawDatagramSocket? _discoverySocket;
  StreamSubscription<RawSocketEvent>? _discoverySub;
  Timer? _announceTimer;
  String? _identityToken;
  String? _clientId;
  int? _listenPort;
  bool _disconnectRequested = false;
  bool _dialing = false;

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
    _disconnectRequested = false;
    _identityToken = reconnectTokens['signalingToken'] ?? '';
    if (_identityToken!.isEmpty) {
      // An unpaired/legacy connection has no shared discovery namespace.
      // Binding a common empty-token port could connect unrelated app
      // instances, so stay in searching until valid reconnect data exists.
      return;
    }
    _clientId = reconnectTokens['transportClientId']?.isNotEmpty == true
        ? reconnectTokens['transportClientId']
        : '${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';

    final port = _portFromToken(_identityToken!);
    _listenPort = port;
    debugPrint('[LAN] attempting to bind port $port');

    // Try to become the listener first.
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      debugPrint('[LAN] listening on port $port');
      _serverSub = _server!.listen(_onClientConnected);
      final host = reconnectTokens['localNetworkHost'];
      if (host != null && host.isNotEmpty) {
        unawaited(_tryConnect(port, host: host));
      }
    } on SocketException {
      // Port already in use — another peer may already be listening in this
      // process (desktop integration tests). Try it once. If the port belongs
      // to an unrelated/stale socket, fall back to an ephemeral listener and
      // let UDP discovery advertise the actual port.
      debugPrint('[LAN] port $port in use — connecting as client');
      await _tryConnect(
        port,
        host: reconnectTokens['localNetworkHost'],
        maxAttempts: 1,
      );
      if (_socket == null && !_disconnectRequested) {
        _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
        _listenPort = _server!.port;
        debugPrint('[LAN] listening on fallback port $_listenPort');
        _serverSub = _server!.listen(_onClientConnected);
      }
    }

    // On separate phones both peers can bind the same TCP port, so a port
    // collision cannot elect a client. A tiny UDP broadcast advertises the
    // listener and a per-device id; exactly one peer (lexicographically the
    // greater id) dials. The opaque connection tag contains no profile data
    // and the TCP identity check still runs before encrypted packets flow.
    await _startDiscovery();
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
    _disconnectRequested = true;
    _connected = false;
    _announceTimer?.cancel();
    _announceTimer = null;
    await _discoverySub?.cancel();
    _discoverySub = null;
    _discoverySocket?.close();
    _discoverySocket = null;
    await _serverSub?.cancel();
    _serverSub = null;
    await _socketSub?.cancel();
    _socketSub = null;
    await _server?.close();
    _server = null;
    await _socket?.close();
    _socket = null;
    _reconnectAttempts = 0;
    _dialing = false;
    _state.add(TransportKind.searching);
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// Deterministic port in the dynamic/private range: 49152 + (hash % 16384).
  static int _portFromToken(String token) {
    final hash = _hashToken(token);
    return 49152 + (hash % 16384);
  }

  static int _discoveryPortFromToken(String token) {
    final hash = _hashToken('pulse-lan:$token');
    return 32768 + (hash % 12000);
  }

  static int _hashToken(String token) {
    var hash = 0x811C9DC5; // FNV-1a 32-bit offset basis.
    for (final byte in utf8.encode(token)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  /// Handle an incoming TCP client on the server socket.
  void _onClientConnected(Socket client) {
    debugPrint('[LAN] client connected from ${client.remoteAddress.address}');
    if (_connected) {
      unawaited(client.close());
      return;
    }
    _attachSocket(client);
  }

  Future<void> _startDiscovery() async {
    final token = _identityToken;
    final port = _listenPort;
    if (token == null || token.isEmpty || port == null) return;
    final discoveryPort = _discoveryPortFromToken(token);
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
        // Physical peers have separate network stacks, so they do not need
        // SO_REUSEPORT. Keeping it disabled also avoids load-balancing a
        // broadcast to only one socket in same-host desktop tests.
        reusePort: false,
      );
      if (_disconnectRequested) {
        socket.close();
        return;
      }
      _discoverySocket = socket;
      socket.broadcastEnabled = true;
      _discoverySub = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = socket.receive()) != null) {
          _onDiscovery(datagram!);
        }
      }, onError: (Object error) {
        debugPrint('[LAN] discovery socket failed: $error');
      });
      _announce();
      _announceTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _announce(),
      );
    } on SocketException catch (error) {
      // Two transports in one desktop test process may not be allowed to
      // share a UDP port. The deterministic TCP collision path above still
      // connects them over loopback; physical devices do not share sockets.
      debugPrint('[LAN] discovery unavailable: $error');
    }
  }

  void _announce() {
    final socket = _discoverySocket;
    final token = _identityToken;
    final clientId = _clientId;
    final port = _listenPort;
    if (socket == null ||
        token == null ||
        clientId == null ||
        port == null ||
        _disconnectRequested) {
      return;
    }
    final payload = utf8.encode(jsonEncode(<String, Object>{
      'v': 1,
      'tag': _hashToken(token).toRadixString(16),
      'id': clientId,
      'port': port,
    }));
    try {
      socket.send(
        payload,
        InternetAddress('255.255.255.255'),
        _discoveryPortFromToken(token),
      );
    } on SocketException catch (error) {
      debugPrint('[LAN] discovery announce failed: $error');
    }
  }

  void _onDiscovery(Datagram datagram) {
    if (_disconnectRequested || _connected || _dialing) return;
    try {
      final message = jsonDecode(utf8.decode(datagram.data));
      if (message is! Map<String, dynamic>) return;
      final token = _identityToken;
      final localId = _clientId;
      final peerId = message['id'] as String?;
      final peerPort = message['port'] as int?;
      if (token == null ||
          localId == null ||
          peerId == null ||
          peerId == localId ||
          peerPort == null ||
          message['tag'] != _hashToken(token).toRadixString(16)) {
        return;
      }
      // Stable election prevents two cross-connected sockets. The other peer
      // remains the listener and keeps announcing after any disconnection.
      if (localId.compareTo(peerId) > 0) {
        unawaited(_tryConnect(
          peerPort,
          host: datagram.address.address,
          maxAttempts: 1,
        ));
      }
    } on Object catch (error) {
      debugPrint('[LAN] malformed discovery packet: $error');
    }
  }

  /// Try to connect as a client to localhost on [port].
  Future<void> _tryConnect(
    int port, {
    String? host,
    int maxAttempts = _maxReconnectAttempts,
  }) async {
    if (_dialing || _disconnectRequested) return;
    _dialing = true;
    final targetHost = host == null || host.isEmpty
        ? InternetAddress.loopbackIPv4.address
        : host;
    try {
      var attempts = 0;
      while (attempts < maxAttempts && !_connected && !_disconnectRequested) {
        try {
          final socket = await Socket.connect(
            targetHost,
            port,
            timeout: const Duration(seconds: 5),
          );
          if (_disconnectRequested) {
            await socket.close();
            return;
          }
          debugPrint('[LAN] connected to $targetHost:$port as client');
          _attachSocket(socket);
          return;
        } on SocketException catch (e) {
          attempts++;
          _reconnectAttempts++;
          if (attempts >= maxAttempts) return;
          final delay = Duration(
            seconds: _backoffSeconds(_reconnectAttempts),
          );
          debugPrint(
            '[LAN] connect attempt $_reconnectAttempts failed: $e — '
            'retrying in ${delay.inSeconds}s',
          );
          await Future<void>.delayed(delay);
        }
      }
    } finally {
      _dialing = false;
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
        debugPrint('[LAN] socket error: $e');
        _onDisconnected();
      },
      onDone: () {
        debugPrint('[LAN] socket closed');
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
        debugPrint('[LAN] peer identity: $peerToken');
        final expected = _identityToken;
        if (expected != null && expected.isNotEmpty && peerToken != expected) {
          debugPrint('[LAN] peer identity mismatch — disconnecting');
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
      debugPrint('[LAN] malformed line: $line ($e)');
    }
  }

  void _onDisconnected() {
    final wasConnected = _connected;
    _connected = false;
    if (wasConnected) _state.add(TransportKind.searching);
    unawaited(_socketSub?.cancel());
    _socketSub = null;
    _socket = null;
    _reconnectAttempts = 0;
    // UDP discovery and the TCP listener remain armed. The elected dialer
    // reconnects on the next two-second announcement without app intervention.
    _announce();
  }

  /// Exponential backoff: 1s, 2s, 4s, 8s, 16s capped at 30s.
  static int _backoffSeconds(int attempt) {
    final seconds = 1 << (attempt - 1); // 1, 2, 4, 8, 16
    return seconds.clamp(1, 30);
  }
}
