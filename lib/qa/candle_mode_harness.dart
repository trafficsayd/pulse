import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/modes/presentation/modes/candle_mode_screen.dart';
import '../l10n/app_localizations.dart';

/// Debug entrypoint used for physical/emulator Candle QA without mutating a
/// real saved pair. It is never referenced by the production entrypoint.
void main() {
  runApp(
    const ProviderScope(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: Locale('ru'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: CandleModeScreen(),
      ),
    ),
  );
}
