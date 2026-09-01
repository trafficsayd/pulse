import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/locale/locale_controller.dart';
import 'core/routing/app_router.dart';
import 'core/routing/routes.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/session_error_banner.dart';
import 'features/subscription/application/subscription_controller.dart';
import 'features/connections/application/connections_controller.dart';
import 'features/lockscreen/application/lockscreen_ray_bridge.dart';
import 'features/lockscreen/application/lockscreen_knock_bridge.dart';
import 'features/modes/application/mode_registry.dart';
import 'features/modes/domain/pulse_mode.dart';
import 'features/session/application/mode_event.dart';
import 'features/session/application/mode_event_bus.dart';
import 'l10n/app_localizations.dart';

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
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  bool _didRestoreInitialRoute = false;
  PulseModeId? _lastIncomingMode;
  DateTime? _lastIncomingAt;
  bool? _connectionKeepAliveEnabled;

  @override
  void initState() {
    super.initState();
    // Eagerly initialise the subscription controller so the IAP service
    // is subscribed to `purchaseStream` for the whole app lifetime — a
    // redelivery that arrives before the paywall is opened must not be
    // dropped on the floor.
    ref.read(subscriptionControllerProvider.notifier);
    LockscreenKnockBridge.initialize(
      onNativeReply: (event) => ref.read(modeEventBusProvider).send(event),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeControllerProvider);
    final hasActiveConnection = ref.watch(
      connectionsControllerProvider.select((state) => state.active != null),
    );
    _syncConnectionKeepAlive(hasActiveConnection);
    ref.listen<AsyncValue<ModeEvent>>(incomingModeEventProvider, (_, next) {
      final event = next.valueOrNull;
      if (event == null) return;
      // Android renders Ray on a dedicated, keyguard-safe native canvas.
      // Forward before showing the in-app banner so the first live point is
      // not lost while the lock-screen activity is being created.
      unawaited(
        LockscreenRayBridge.handleIncoming(
          event,
          languageCode: locale?.languageCode,
        ),
      );
      unawaited(
        LockscreenKnockBridge.handleIncoming(
          event,
          languageCode: locale?.languageCode,
        ),
      );
      if (event.type == 'sneak_in') {
        _showIncomingSneakIn(event);
      } else {
        _showIncomingMode(event);
      }
    });
    _restoreInitialRoute();
    return MaterialApp.router(
      scaffoldMessengerKey: _messengerKey,
      onGenerateTitle: (context) =>
          AppLocalizations.of(context)?.appTitle ?? 'Pulse',
      theme: buildPulseTheme(),
      darkTheme: buildPulseTheme(),
      themeMode: ThemeMode.dark,
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) {
        return SessionErrorBanner(
          child: ColoredBox(
            color: AppColors.background,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        );
      },
      routerConfig: _router,
    );
  }

  void _syncConnectionKeepAlive(bool enabled) {
    if (_connectionKeepAliveEnabled == enabled) return;
    _connectionKeepAliveEnabled = enabled;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _connectionKeepAliveEnabled != enabled) return;
      unawaited(LockscreenRayBridge.setConnectionKeepAlive(enabled));
    });
  }

  void _showIncomingMode(ModeEvent event) {
    // Level-stream modes emit continuously while their screen is open. A
    // silent sample is transport housekeeping, not a human interaction, and
    // must not keep replacing notifications from newer modes.
    if ((event.type == 'whisper_level' || event.type == 'breath_level') &&
        ((event.data['level'] as num?)?.toDouble() ?? 0) <= 0.05) {
      return;
    }
    final modeId = modeForEventType(event.type);
    if (modeId == null) return;
    final path = Routes.modePath(modeId.name);
    if (_isCurrentPath(path)) return;
    final now = DateTime.now();
    if (_lastIncomingMode == modeId &&
        _lastIncomingAt != null &&
        now.difference(_lastIncomingAt!) < const Duration(seconds: 30)) {
      return;
    }
    _lastIncomingMode = modeId;
    _lastIncomingAt = now;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Navigation and an incoming event can complete in the same frame.
      // Re-check here so a banner scheduled on the hub cannot cover the
      // controls after the matching mode has already opened.
      if (!mounted || _isCurrentPath(path)) return;
      final messenger = _messengerKey.currentState;
      final messengerContext = _messengerKey.currentContext;
      if (messenger == null || messengerContext == null) return;
      final l10n = AppLocalizations.of(messengerContext);
      final descriptor = findMode(modeId);
      final title = descriptor != null && l10n != null
          ? localizedModeTitle(descriptor, l10n)
          : modeId.name;
      HapticFeedback.mediumImpact();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('${l10n?.appTitle ?? 'Pulse'} · $title'),
          action: SnackBarAction(
            label: Localizations.localeOf(messengerContext).languageCode == 'ru'
                ? 'Открыть'
                : 'Open',
            onPressed: () {
              messenger.hideCurrentSnackBar();
              _router.push(path);
            },
          ),
        ));
    });
  }

  void _showIncomingSneakIn(ModeEvent event) {
    final active = ref.read(connectionsControllerProvider).active;
    if (active == null) return;
    final signal = event.data['signal'] as String? ?? '✨';
    final location = Uri(
      path: Routes.sneakInIncoming,
      queryParameters: {
        'connectionId': active.id,
        'signal': signal,
      },
    ).toString();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _messengerKey.currentState?.hideCurrentSnackBar();
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
      _router.go(location);
    });
  }

  bool _isCurrentPath(String path) {
    final displayedPath = _router.routeInformationProvider.value.uri.path;
    final configuration = _router.routerDelegate.currentConfiguration;
    if (displayedPath == path || configuration.uri.path == path) return true;

    // GoRouter.push creates an ImperativeRouteMatch. Its visible page is in
    // `matches`, while both URI values intentionally remain at the underlying
    // route (usually /hub). Inspect the real navigation stack so incoming
    // events cannot show a redundant banner over an already-open mode.
    bool containsPath(List<RouteMatchBase> matches) {
      for (final match in matches) {
        if (match.matchedLocation == path) return true;
        if (match is ShellRouteMatch && containsPath(match.matches)) {
          return true;
        }
      }
      return false;
    }

    return containsPath(configuration.matches);
  }

  void _restoreInitialRoute() {
    if (_didRestoreInitialRoute) return;
    _didRestoreInitialRoute = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(connectionsControllerProvider.notifier).loaded;
      if (!mounted) return;
      final state = ref.read(connectionsControllerProvider);
      if (state.connections.isNotEmpty) {
        _router.go(Routes.hub);
      }
    });
  }
}
