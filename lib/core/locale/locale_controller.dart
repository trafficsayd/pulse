import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// User-selected locale override.
///
/// `null` means "follow the system locale" (the Material default). The
/// settings screen exposes a Russian / English picker that flips this
/// notifier; everything else just reads it via [localeControllerProvider].
class LocaleController extends Notifier<Locale?> {
  @override
  Locale? build() => null;

  void setLocale(Locale? locale) {
    state = locale;
  }
}

final localeControllerProvider =
    NotifierProvider<LocaleController, Locale?>(LocaleController.new);
