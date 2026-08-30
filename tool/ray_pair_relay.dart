import 'dart:io';

const _port = 21988;

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
  final peers = <WebSocket>{};
  stdout.writeln('Pulse Ray QA relay listening on 0.0.0.0:$_port');
  await for (final request in server) {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.upgradeRequired
        ..close();
      continue;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    peers.add(socket);
    stdout.writeln('peer joined (${peers.length})');
    socket.listen(
      (message) {
        for (final peer in peers.toList(growable: false)) {
          if (!identical(peer, socket) && peer.readyState == WebSocket.open) {
            peer.add(message);
          }
        }
      },
      onDone: () {
        peers.remove(socket);
        stdout.writeln('peer left (${peers.length})');
      },
      onError: (_) => peers.remove(socket),
      cancelOnError: true,
    );
  }
}
