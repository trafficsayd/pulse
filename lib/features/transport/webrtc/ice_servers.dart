/// ICE server configuration used by the WebRTC relay transport.
///
/// We deliberately keep this list short and inspectable:
///
/// * Two **public STUN** servers (Google + Cloudflare) so the WebRTC stack
///   can discover the device's public reflexive address without a relay.
/// * A **TURN placeholder** at `turn:turn.pulse.app:3478`. Real credentials
///   must be provided at build time via
///   `--dart-define=TURN_USER=... --dart-define=TURN_CRED=...`; without
///   them the TURN entry is still appended but its `username` / `credential`
///   fields are empty strings, which means TURN will simply fail open and
///   the connection will fall back to direct/STUN paths.
///
/// See `webrtc/README.md` for the full rationale and production checklist.
library;

const String _kTurnUsername = String.fromEnvironment(
  'TURN_USER',
  defaultValue: '',
);

const String _kTurnCredential = String.fromEnvironment(
  'TURN_CRED',
  defaultValue: '',
);

const String _kTurnUrl = String.fromEnvironment(
  'TURN_URL',
  defaultValue: 'turn:turn.pulse.app:3478',
);

/// One ICE server entry, shaped to match WebRTC's `RTCIceServer` dictionary.
///
/// Each entry has a list of URLs (so a single record can advertise the
/// same server over UDP and TCP, for instance) and optional auth fields.
class IceServer {
  const IceServer({
    required this.urls,
    this.username,
    this.credential,
  });

  factory IceServer.fromJson(Map<String, Object?> json) {
    final Object? rawUrls = json['urls'];
    final List<String> urls = switch (rawUrls) {
      String value => <String>[value],
      List<Object?> values =>
        values.whereType<String>().toList(growable: false),
      _ => const <String>[],
    };
    if (urls.isEmpty) {
      throw const FormatException('ICE server must contain at least one URL');
    }
    return IceServer(
      urls: urls,
      username: json['username'] is String ? json['username']! as String : null,
      credential:
          json['credential'] is String ? json['credential']! as String : null,
    );
  }

  /// One or more URLs (`stun:` / `turn:` / `turns:`).
  final List<String> urls;

  /// Long-term TURN username. `null` for STUN-only entries.
  final String? username;

  /// Long-term TURN credential. `null` for STUN-only entries.
  final String? credential;

  /// Render this entry into the plain `Map<String, dynamic>` shape that
  /// `flutter_webrtc` (and any future native bridge) expects.
  Map<String, Object> toMap() {
    final Map<String, Object> out = <String, Object>{'urls': urls};
    final String? user = username;
    final String? cred = credential;
    if (user != null && user.isNotEmpty) {
      out['username'] = user;
    }
    if (cred != null && cred.isNotEmpty) {
      out['credential'] = cred;
    }
    return out;
  }
}

/// Canonical ICE server list for Pulse.
///
/// Order matters: WebRTC tries entries top-to-bottom, so we list the cheap
/// public STUN servers first and only fall back to our TURN relay if both
/// peers are stuck behind symmetric NATs.
const List<IceServer> kIceServers = <IceServer>[
  IceServer(urls: <String>['stun:stun.l.google.com:19302']),
  IceServer(urls: <String>['stun:stun.cloudflare.com:3478']),
  IceServer(
    urls: <String>[_kTurnUrl],
    username: _kTurnUsername,
    credential: _kTurnCredential,
  ),
];

/// True when the TURN entry has both a username and a credential, i.e. when
/// the binary was compiled with `--dart-define=TURN_USER=... TURN_CRED=...`.
///
/// Used by diagnostics screens (and by tests) to decide whether the app is
/// currently capable of falling back through TURN.
bool get hasTurnCredentials =>
    _kTurnUsername.isNotEmpty && _kTurnCredential.isNotEmpty;

/// Builds the per-session ICE configuration. Cloudflare credentials are
/// minted by the signaling Worker and take precedence over the optional
/// compile-time development relay.
List<IceServer> iceServersForSession(List<IceServer> shortLivedServers) {
  final List<IceServer> result = <IceServer>[
    kIceServers[0],
    kIceServers[1],
  ];
  result.addAll(shortLivedServers.where((server) => server.urls
      .any((url) => url.startsWith('turn:') || url.startsWith('turns:'))));
  if (shortLivedServers.isEmpty && hasTurnCredentials) {
    result.add(kIceServers[2]);
  }
  return List<IceServer>.unmodifiable(result);
}
