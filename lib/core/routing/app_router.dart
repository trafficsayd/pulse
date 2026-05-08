import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pulse/l10n/app_localizations.dart';

import '../../features/connecting/presentation/connecting_screen.dart';
import '../../features/connection_status/presentation/connection_status_screen.dart';
import '../../features/connections/presentation/connection_settings_screen.dart';
import '../../features/hub/presentation/hub_screen.dart';
import '../../features/modes/presentation/mode_runner_screen.dart';
import '../../features/modes/presentation/modes_catalog_screen.dart';
import '../../features/pairing/presentation/pairing_screen.dart';
import '../../features/people/presentation/people_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/sneak_in/presentation/sneak_in_incoming_screen.dart';
import '../../features/sneak_in/presentation/sneak_in_wheel_screen.dart';
import '../../features/subscription/presentation/subscription_screen.dart';
import '../theme/app_colors.dart';
import '../widgets/gradient_button.dart';
import 'routes.dart';

/// Builds the application's [GoRouter].
///
/// The first launch always lands on [Routes.pairing]; subsequent launches
/// (after at least one connection has been saved) jump straight into the
/// hub. Persisting the "has-paired-once" flag is owned by the connections
/// controller, so the router itself is kept stateless and trivially
/// testable.
GoRouter buildRouter() {
  return GoRouter(
    initialLocation: Routes.pairing,
    routes: [
      GoRoute(
        path: Routes.pairing,
        builder: (context, state) => const PairingScreen(),
      ),
      GoRoute(
        path: Routes.connecting,
        builder: (context, state) => const ConnectingScreen(),
      ),
      GoRoute(
        path: Routes.hub,
        builder: (context, state) => const HubScreen(),
      ),
      GoRoute(
        path: Routes.people,
        builder: (context, state) => const PeopleScreen(),
      ),
      GoRoute(
        path: Routes.sneakIn,
        builder: (context, state) => const SneakInWheelScreen(),
      ),
      GoRoute(
        path: Routes.sneakInIncoming,
        builder: (context, state) {
          final connectionId =
              state.uri.queryParameters['connectionId'] ?? '';
          return SneakInIncomingScreen(connectionId: connectionId);
        },
      ),
      GoRoute(
        path: Routes.subscription,
        builder: (context, state) => const SubscriptionScreen(),
      ),
      GoRoute(
        path: Routes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: Routes.connectionStatus,
        builder: (context, state) => const ConnectionStatusScreen(),
      ),
      GoRoute(
        path: Routes.modesCatalog,
        builder: (context, state) => const ModesCatalogScreen(),
      ),
      GoRoute(
        path: Routes.connectionSettings,
        builder: (context, state) {
          final connectionId = state.pathParameters['connectionId']!;
          return ConnectionSettingsScreen(connectionId: connectionId);
        },
      ),
      GoRoute(
        path: Routes.mode,
        builder: (context, state) {
          final modeId = state.pathParameters['modeId']!;
          return ModeRunnerScreen(modeIdRaw: modeId);
        },
      ),
    ],
    errorBuilder: (context, state) => _NotFoundScreen(uri: state.uri),
  );
}

/// Friendly fallback when a deep link doesn't match a registered route or
/// when an `:id` path parameter doesn't resolve to a real entity. Replaces
/// the previous bare error icon so deep-link typos surface a clear
/// "back to start" affordance.
class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen({required this.uri});

  final Uri uri;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.outline),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.travel_explore_rounded,
                  size: 40,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                t.routeNotFoundTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                uri.path,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 24),
              GradientButton(
                label: t.routeNotFoundBackToHub,
                onPressed: () => context.go(Routes.hub),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
