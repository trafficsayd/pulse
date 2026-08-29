import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/secure_key_store.dart';

/// User-selected locale override.
///
/// `null` means "follow the system locale" (the Material default). The
/// settings screen exposes a Russian / English picker that flips this
/// notifier; everything else just reads it via [localeControllerProvider].
class LocaleController extends Notifier<Locale?> {
  static const _storageKey = 'locale.v1';
  bool _userChangedLocale = false;

  @override
  Locale? build() {
    unawaited(_restore());
    return null;
  }

  void setLocale(Locale? locale) {
    _userChangedLocale = true;
    state = locale;
    final store = ref.read(secureKeyStoreProvider);
    if (locale == null) {
      unawaited(store.delete(_storageKey));
    } else {
      unawaited(store.writeString(_storageKey, locale.languageCode));
    }
  }

  Future<void> _restore() async {
    final code = await ref.read(secureKeyStoreProvider).readString(_storageKey);
    if (_userChangedLocale || code == null) return;
    if (code == 'ru' || code == 'en') state = Locale(code);
  }
}

final localeControllerProvider =
    NotifierProvider<LocaleController, Locale?>(LocaleController.new);
