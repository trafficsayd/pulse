import 'package:flutter/material.dart';
import 'package:pulse/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/locale/locale_controller.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';

/// Root [MaterialApp.router] for Pulse.
///
/// Stays intentionally minimal: theme, localization, and the router. All
/// dependency wiring lives inside the providers (see e.g.
/// [secureKeyStoreProvider]) so that swapping a real implementation in
/// place of a stub never requires touching this file.
class PulseApp extends ConsumerStatefulWidget {
  const PulseApp({super.key});

  @override
  ConsumerState<PulseApp> createState() => _PulseAppState();
}

class _PulseAppState extends ConsumerState<PulseApp> {
  late final _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeControllerProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) =>
          AppLocalizations.of(context)?.appTitle ?? 'Pulse',
      theme: buildPulseTheme(),
      darkTheme: buildPulseTheme(),
      themeMode: ThemeMode.dark,
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: _router,
    );
  }
}
