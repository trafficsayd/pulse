import 'package:meta/meta.dart';

/// Per-connection permissions controlled by the local user.
///
/// Stored locally next to the connection. Never transmitted — these are the
/// owner's filters on what the partner is allowed to do.
@immutable
class PermissionFlags {
  const PermissionFlags({
    this.allowFullSessions = true,
    this.allowSneakIn = true,
    this.confirmFirstSneakIn = true,
  });

  /// Allow opening a full duplex session with this person.
  final bool allowFullSessions;

  /// Allow Sneak In signals from this person while we're in another session.
  final bool allowSneakIn;

  /// On the very first Sneak In received from this person, prompt the user
  /// to confirm before delivering the signal.
  final bool confirmFirstSneakIn;

  /// All permissions revoked. Equivalent to "blocked".
  static const blocked = PermissionFlags(
    allowFullSessions: false,
    allowSneakIn: false,
    confirmFirstSneakIn: false,
  );

  bool get isBlocked => !allowFullSessions && !allowSneakIn;

  PermissionFlags copyWith({
    bool? allowFullSessions,
    bool? allowSneakIn,
    bool? confirmFirstSneakIn,
  }) {
    return PermissionFlags(
      allowFullSessions: allowFullSessions ?? this.allowFullSessions,
      allowSneakIn: allowSneakIn ?? this.allowSneakIn,
      confirmFirstSneakIn: confirmFirstSneakIn ?? this.confirmFirstSneakIn,
    );
  }

  Map<String, Object?> toJson() => {
        'allowFullSessions': allowFullSessions,
        'allowSneakIn': allowSneakIn,
        'confirmFirstSneakIn': confirmFirstSneakIn,
      };

  factory PermissionFlags.fromJson(Map<String, Object?> json) => PermissionFlags(
        allowFullSessions: json['allowFullSessions'] as bool? ?? true,
        allowSneakIn: json['allowSneakIn'] as bool? ?? true,
        confirmFirstSneakIn: json['confirmFirstSneakIn'] as bool? ?? true,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PermissionFlags &&
          allowFullSessions == other.allowFullSessions &&
          allowSneakIn == other.allowSneakIn &&
          confirmFirstSneakIn == other.confirmFirstSneakIn;

  @override
  int get hashCode => Object.hash(allowFullSessions, allowSneakIn, confirmFirstSneakIn);
}
