import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/connections/domain/connection.dart';
import 'package:pulse/features/connections/domain/connection_status.dart';
import 'package:pulse/features/connections/domain/permission_flags.dart';

void main() {
  group('Connection', () {
    final fixed = DateTime.utc(2025, 1, 1, 12);

    Connection sample() => Connection(
          id: 'abc-123',
          nickname: 'Alex',
          colorIndex: 3,
          emoji: '🌙',
          status: ConnectionStatus.paused,
          permissions: const PermissionFlags(),
          createdAt: fixed,
          bleAddressToken: 'ble-token',
          signalingToken: 'sig-token',
        );

    test('round-trips through JSON', () {
      final c = sample();
      final restored = Connection.fromJson(c.toJson());
      expect(restored.id, c.id);
      expect(restored.nickname, c.nickname);
      expect(restored.colorIndex, c.colorIndex);
      expect(restored.emoji, c.emoji);
      expect(restored.status, c.status);
      expect(restored.permissions, c.permissions);
      expect(restored.createdAt, c.createdAt);
      expect(restored.bleAddressToken, c.bleAddressToken);
      expect(restored.signalingToken, c.signalingToken);
    });

    test('copyWith preserves immutable identity fields', () {
      final updated = sample().copyWith(
        nickname: 'Sam',
        status: ConnectionStatus.active,
      );
      expect(updated.id, sample().id);
      expect(updated.createdAt, sample().createdAt);
      expect(updated.nickname, 'Sam');
      expect(updated.status, ConnectionStatus.active);
    });

    test('equality is based on id only', () {
      final a = sample();
      final b = sample().copyWith(nickname: 'Sam');
      expect(a, b);
    });
  });

  group('PermissionFlags', () {
    test('blocked sentinel exposes both gates closed', () {
      expect(PermissionFlags.blocked.isBlocked, isTrue);
      expect(PermissionFlags.blocked.allowFullSessions, isFalse);
      expect(PermissionFlags.blocked.allowSneakIn, isFalse);
    });

    test('default flags are open', () {
      const f = PermissionFlags();
      expect(f.allowFullSessions, isTrue);
      expect(f.allowSneakIn, isTrue);
      expect(f.confirmFirstSneakIn, isTrue);
      expect(f.isBlocked, isFalse);
    });

    test('round-trips through JSON', () {
      const f = PermissionFlags(
        allowFullSessions: false,
        allowSneakIn: true,
        confirmFirstSneakIn: false,
      );
      final restored = PermissionFlags.fromJson(f.toJson());
      expect(restored, f);
    });
  });
}
