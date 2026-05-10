import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/pulse_bottom_nav.dart';
import '../../../shared/widgets/pulse_drawer.dart';
import '../../connections/application/connections_controller.dart';
import '../../connections/domain/connection.dart';
import '../../modes/application/mode_registry.dart';
import '../../modes/domain/pulse_mode.dart';
import '../../subscription/application/subscription_controller.dart';
import '../../transport/transport.dart';

/// Main canvas after pairing. The mockup lays modes out in a 3-column grid
/// with the active mode highlighted in the centre, a top bar with a drawer
/// trigger and a transport pill, and a bottom nav exposing My People /
/// Pulse / Sneak In.
class HubScreen extends ConsumerWidget {
  const HubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final connections = ref.watch(connectionsControllerProvider);
    final activeConnection = connections.active;

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const PulseDrawer(),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: Column(
            children: [
              const _HubHeader(),
              const SizedBox(height: 12),
              Expanded(
                child: _ModeGrid(activeConnection: activeConnection),
              ),
              if (activeConnection == null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 12),
                  child: Text(
                    t.hubChooseSomeone,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
              const _PaginationDots(active: 0, count: 3),
              const SizedBox(height: 16),
              const PulseBottomNav(active: PulseNavTab.hub),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _HubHeader extends StatelessWidget {
  const _HubHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu_rounded),
            color: AppColors.textSecondary,
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
          const Spacer(),
          const _TransportPill(kind: TransportKind.direct),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _TransportPill extends StatelessWidget {
  const _TransportPill({required this.kind});

  final TransportKind kind;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final (color, label) = switch (kind) {
      TransportKind.direct => (
          AppColors.transportDirect,
          '${t.transportDirect} (${t.connectionBle})'
        ),
      TransportKind.localNetwork => (
          AppColors.transportLocal,
          t.transportLocal,
        ),
      TransportKind.relay => (AppColors.transportRelay, t.transportRelay),
      TransportKind.searching => (
          AppColors.transportSearching,
          t.transportSearching,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeGrid extends ConsumerWidget {
  const _ModeGrid({required this.activeConnection});

  final Connection? activeConnection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GridView.builder(
        physics: const BouncingScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.85,
        ),
        itemCount: kAllModes.length + 1,
        itemBuilder: (context, i) {
          if (i == kAllModes.length) return const _MoreTile();
          final mode = kAllModes[i];
          final isFeatured =
              mode.id == PulseModeId.halfHeart && activeConnection != null;
          return _ModeGridTile(
            mode: mode,
            featured: isFeatured,
            connection: activeConnection,
          );
        },
      ),
    );
  }
}

class _ModeGridTile extends ConsumerWidget {
  const _ModeGridTile({
    required this.mode,
    required this.featured,
    required this.connection,
  });

  final PulseModeDescriptor mode;
  final bool featured;
  final Connection? connection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final unlocked = ref
        .read(subscriptionControllerProvider.notifier)
        .isModeUnlocked(mode.id);
    final color = unlocked ? AppColors.pulse : AppColors.textMuted;
    return GestureDetector(
      onTap: () => _enter(context, ref),
      onLongPress: () => _enter(context, ref),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: featured ? 86 : 68,
            height: featured ? 86 : 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: featured ? AppColors.heroGradient : null,
              color: featured ? null : AppColors.surface,
              border: Border.all(
                color: featured ? Colors.transparent : AppColors.outline,
                width: 1.2,
              ),
              boxShadow: featured
                  ? const [
                      BoxShadow(color: AppColors.pulseHalo, blurRadius: 24),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: featured && connection != null
                ? Text(
                    connection!.emoji,
                    style: const TextStyle(fontSize: 28),
                  )
                : Icon(mode.icon, size: 30, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            _modeLabel(t, mode.id),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: featured ? AppColors.textPrimary : AppColors.textSecondary,
              fontSize: 11,
              fontWeight: featured ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          if (!unlocked)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                Icons.lock_outline_rounded,
                size: 12,
                color: AppColors.textMuted,
              ),
            ),
        ],
      ),
    );
  }

  void _enter(BuildContext context, WidgetRef ref) {
    final unlocked = ref
        .read(subscriptionControllerProvider.notifier)
        .isModeUnlocked(mode.id);
    if (!unlocked) {
      context.push(Routes.subscription);
      return;
    }
    // push() — not go() — so the mode screen's close X pops cleanly.
    context.push(Routes.modePath(mode.id.name));
  }
}

String _modeLabel(AppLocalizations t, PulseModeId id) => switch (id) {
      PulseModeId.tapTap => t.modeTapTap,
      PulseModeId.halfHeart => t.modeHalfHeart,
      PulseModeId.candle => t.modeCandle,
      PulseModeId.whisper => t.modeWhisper,
      PulseModeId.bell => t.modeBell,
      PulseModeId.ray => t.modeRay,
      PulseModeId.constellation => t.modeConstellation,
      PulseModeId.sketch => t.modeSketch,
      PulseModeId.goosebumps ||
      PulseModeId.thread ||
      PulseModeId.thunder ||
      PulseModeId.fireworks ||
      PulseModeId.balance ||
      PulseModeId.sandbox ||
      PulseModeId.breath ||
      PulseModeId.sync =>
        t.modesPaidLocked,
    };

class _MoreTile extends StatelessWidget {
  const _MoreTile();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: () => context.push(Routes.modesBrowser),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surface,
              border: Border.all(color: AppColors.outline, width: 1.2),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.add_rounded,
              size: 30,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t.modeMore,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaginationDots extends StatelessWidget {
  const _PaginationDots({required this.active, required this.count});
  final int active;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == active;
        return Container(
          width: isActive ? 18 : 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: isActive ? AppColors.pulse : AppColors.outline,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}
