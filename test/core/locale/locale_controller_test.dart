import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/core/locale/locale_controller.dart';
import 'package:pulse/core/storage/secure_key_store.dart';

void main() {
  test('selected locale survives a new provider container', () async {
    final store = SecureKeyStore();
    final first = ProviderContainer(
      overrides: [secureKeyStoreProvider.overrideWithValue(store)],
    );
    first.read(localeControllerProvider.notifier).setLocale(const Locale('ru'));
    await Future<void>.delayed(Duration.zero);
    first.dispose();

    final second = ProviderContainer(
      overrides: [secureKeyStoreProvider.overrideWithValue(store)],
    );
    addTearDown(second.dispose);
    second.read(localeControllerProvider);
    await Future<void>.delayed(Duration.zero);

    expect(second.read(localeControllerProvider), const Locale('ru'));
  });
}
