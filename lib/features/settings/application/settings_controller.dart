import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../connections/application/connections_controller.dart';

/// Persisted user settings for things that aren't entitlements: app locale,
/// notification toggle, crash-reports opt-in.
///
/// State lives in [SecureKeyStore] under `settings.v1`, owned exclusively by
/// [SettingsController]. UI reads through Riverpod and never writes to the
/// store directly.
@immutable
class SettingsState {
  const SettingsState({
    required this.locale,
    required this.notifications,
    required this.crashReports,
    required this.loading,
  });

  /// Null means "follow system locale". Otherwise a concrete locale code
  /// (currently 'en' or 'ru').
  final Locale? locale;
  final bool notifications;
  final bool crashReports;
  final bool loading;

  static const initial = SettingsState(
    locale: null,
    notifications: true,
    crashReports: false,
    loading: true,
  );

  SettingsState copyWith({
    Object? locale = _sentinel,
    bool? notifications,
    bool? crashReports,
    bool? loading,
  }) {
    return SettingsState(
      locale: identical(locale, _sentinel) ? this.locale : locale as Locale?,
      notifications: notifications ?? this.notifications,
      crashReports: crashReports ?? this.crashReports,
      loading: loading ?? this.loading,
    );
  }

  Map<String, Object?> toJson() => {
        'locale': locale?.languageCode,
        'notifications': notifications,
        'crashReports': crashReports,
      };

  factory SettingsState.fromJson(Map<String, Object?> json) {
    final lc = json['locale'];
    return SettingsState(
      locale: lc is String && lc.isNotEmpty ? Locale(lc) : null,
      notifications: json['notifications'] as bool? ?? true,
      crashReports: json['crashReports'] as bool? ?? false,
      loading: false,
    );
  }

  static const _sentinel = Object();
}

class SettingsController extends Notifier<SettingsState> {
  static const _storageKey = 'settings.v1';

  @override
  SettingsState build() {
    _bootstrap();
    return SettingsState.initial;
  }

  Future<void> _bootstrap() async {
    final store = ref.read(secureKeyStoreProvider);
    final json = await store.readJson(_storageKey);
    if (json == null) {
      state = SettingsState.initial.copyWith(loading: false);
      return;
    }
    state = SettingsState.fromJson(json);
  }

  Future<void> setLocale(Locale? locale) async {
    state = state.copyWith(locale: locale);
    await _persist();
  }

  Future<void> setNotifications(bool value) async {
    state = state.copyWith(notifications: value);
    await _persist();
  }

  Future<void> setCrashReports(bool value) async {
    state = state.copyWith(crashReports: value);
    await _persist();
  }

  Future<void> _persist() async {
    await ref
        .read(secureKeyStoreProvider)
        .writeJson(_storageKey, state.toJson());
  }
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, SettingsState>(
        SettingsController.new);
