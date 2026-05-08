import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/hub/presentation/hub_screen.dart';
import '../../features/modes/presentation/mode_runner_screen.dart';
import '../../features/pairing/presentation/pairing_screen.dart';
import '../../features/people/presentation/people_screen.dart';
import '../../features/sneak_in/presentation/sneak_in_wheel_screen.dart';
import '../../features/subscription/presentation/subscription_screen.dart';
import 'routes.dart';

/// Builds the application's [GoRouter].
///
/// The first launch always lands on [Routes.pairing]; once at least one
/// connection exists the user is shuttled to [Routes.hub]. Persisting the
/// "has-paired-once" flag is owned by the connections controller, so the
/// router itself is kept stateless and trivially testable.
GoRouter buildRouter() {
  return GoRouter(
    initialLocation: Routes.pairing,
    routes: [
      GoRoute(
        path: Routes.pairing,
        builder: (context, state) => const PairingScreen(),
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
        path: Routes.subscription,
        builder: (context, state) => const SubscriptionScreen(),
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
