import 'package:meta/meta.dart';

import 'connection_status.dart';
import 'permission_flags.dart';

/// A trusted, locally-stored relationship with another Pulse user.
///
/// All identifying material lives only on the device. The signaling layer
/// only ever sees opaque [signalingToken]s; nothing on the wire is tied to
/// a name, contact, or device fingerprint.
@immutable
class Connection {
  const Connection({
    required this.id,
    required this.nickname,
    required this.colorIndex,
    required this.emoji,
    required this.status,
    required this.permissions,
    required this.createdAt,
    this.bleAddressToken,
    this.signalingToken,
    this.transportClientId,
  });

  /// Stable local UUID. Not visible to the partner.
  final String id;

  /// Local nickname assigned by the user. Never transmitted.
  final String nickname;

  /// Index into [AppColors.avatarPalette] for the avatar tint.
  final int colorIndex;

  /// Single emoji glyph used inside the avatar disc. Never transmitted.
  final String emoji;

  final ConnectionStatus status;
  final PermissionFlags permissions;
  final DateTime createdAt;

  /// Random token used for BLE rediscovery. Rotated on each reconnection
  /// so that a passive observer cannot correlate sessions over time.
  final String? bleAddressToken;

  /// Random token used to register on the signaling server (relay path).
  /// The server only ever sees pairings of these tokens — no PII.
  final String? signalingToken;

  /// Random per-device id used only to keep WebRTC roles stable on restart.
  final String? transportClientId;

  Connection copyWith({
    String? nickname,
    int? colorIndex,
    String? emoji,
    ConnectionStatus? status,
    PermissionFlags? permissions,
    String? bleAddressToken,
    String? signalingToken,
    String? transportClientId,
  }) {
    return Connection(
      id: id,
      nickname: nickname ?? this.nickname,
      colorIndex: colorIndex ?? this.colorIndex,
      emoji: emoji ?? this.emoji,
      status: status ?? this.status,
      permissions: permissions ?? this.permissions,
      createdAt: createdAt,
      bleAddressToken: bleAddressToken ?? this.bleAddressToken,
      signalingToken: signalingToken ?? this.signalingToken,
      transportClientId: transportClientId ?? this.transportClientId,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'nickname': nickname,
        'colorIndex': colorIndex,
        'emoji': emoji,
        'status': status.name,
        'permissions': permissions.toJson(),
        'createdAt': createdAt.toIso8601String(),
        'bleAddressToken': bleAddressToken,
        'signalingToken': signalingToken,
        'transportClientId': transportClientId,
      };

  factory Connection.fromJson(Map<String, Object?> json) => Connection(
        id: json['id']! as String,
        nickname: json['nickname']! as String,
        colorIndex: (json['colorIndex'] as int?) ?? 0,
        emoji: (json['emoji'] as String?) ?? '✨',
        status: ConnectionStatus.fromName(json['status']! as String),
        permissions: PermissionFlags.fromJson(
          (json['permissions'] as Map<String, Object?>?) ?? const {},
        ),
        createdAt: DateTime.parse(json['createdAt']! as String),
        bleAddressToken: json['bleAddressToken'] as String?,
        signalingToken: json['signalingToken'] as String?,
        transportClientId: json['transportClientId'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Connection && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
