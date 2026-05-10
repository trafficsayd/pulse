import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
          final connectionId = state.uri.queryParameters['connectionId'] ?? '';
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
    errorBuilder: (context, state) {
      return const Scaffold(
        body: Center(child: Icon(Icons.error_outline_rounded)),
      );
    },
  );
}
