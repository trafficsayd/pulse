import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/settings/application/settings_controller.dart';

void main() {
  group('SettingsState', () {
    test('initial state follows system locale and has notifications on', () {
      const s = SettingsState.initial;
      expect(s.locale, isNull);
      expect(s.notifications, isTrue);
      expect(s.crashReports, isFalse);
      expect(s.loading, isTrue);
    });

    test('copyWith leaves locale untouched without an explicit override', () {
      const base = SettingsState(
        locale: Locale('ru'),
        notifications: true,
        crashReports: false,
        loading: false,
      );
      final next = base.copyWith(notifications: false);
      expect(next.locale, const Locale('ru'));
      expect(next.notifications, isFalse);
    });

    test('copyWith with explicit null locale clears the override', () {
      const base = SettingsState(
        locale: Locale('ru'),
        notifications: true,
        crashReports: false,
        loading: false,
      );
      final next = base.copyWith(locale: null);
      expect(next.locale, isNull);
    });

    test('JSON round-trip preserves locale + toggles', () {
      const s = SettingsState(
        locale: Locale('ru'),
        notifications: false,
        crashReports: true,
        loading: false,
      );
      final restored = SettingsState.fromJson(s.toJson());
      expect(restored.locale, const Locale('ru'));
      expect(restored.notifications, isFalse);
      expect(restored.crashReports, isTrue);
      expect(restored.loading, isFalse);
    });

    test('fromJson with absent locale falls back to system', () {
      final restored = SettingsState.fromJson(const {
        'notifications': true,
        'crashReports': true,
      });
      expect(restored.locale, isNull);
      expect(restored.crashReports, isTrue);
    });
  });
}
