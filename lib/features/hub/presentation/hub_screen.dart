import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../l10n/app_localizations.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/bottom_nav_shell.dart';
import '../../../core/widgets/connection_avatar.dart';
import '../../../core/widgets/pulse_mockup.dart';
import '../../connections/application/connections_controller.dart';
import '../../connections/domain/connection.dart';
import '../../modes/application/mode_registry.dart';
import '../../modes/domain/pulse_mode.dart';
import '../../subscription/application/subscription_controller.dart';
import '../../transport/transport.dart';

class HubScreen extends ConsumerWidget {
  const HubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final connections = ref.watch(connectionsControllerProvider);
    final activeConnection = connections.active;
    final transportKind = activeConnection != null
        ? TransportKind.direct
        : TransportKind.searching;
    final transportLabel =
        activeConnection != null ? t.transportDirectBle : t.transportSearching;

    return BottomNavShell(
      current: BottomNavTab.pulse,
      body: PulseBackdrop(
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 104),
            child: Column(
              children: [
                _HubHeader(
                  activeConnection: activeConnection,
                  transportKind: transportKind,
                  transportLabel: transportLabel,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child:
                      _CircularModeLayout(activeConnection: activeConnection),
                ),
                const SizedBox(height: 12),
                PulsePanel(
                  radius: 22,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 11,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.touch_app_rounded,
                        color: AppColors.pulse,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        t.hubLongPressToStart,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HubHeader extends StatelessWidget {
  const _HubHeader({
    required this.activeConnection,
    required this.transportKind,
    required this.transportLabel,
  });

  final Connection? activeConnection;
  final TransportKind transportKind;
  final String transportLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        PulseRoundButton(
          icon: Icons.tune_rounded,
          onTap: () => context.go(Routes.settings),
          subtle: true,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Center(
            child: GestureDetector(
              onTap: () => context.go(Routes.connectionStatus),
              child:
                  _TransportBadge(kind: transportKind, label: transportLabel),
            ),
          ),
        ),
        const SizedBox(width: 10),
        if (activeConnection != null)
          _ActiveAvatar(connection: activeConnection!)
        else
          PulseRoundButton(
            icon: Icons.person_add_alt_1_rounded,
            onTap: () => context.go(Routes.people),
            subtle: true,
          ),
      ],
    );
  }
}

class _ActiveAvatar extends StatelessWidget {
  const _ActiveAvatar({required this.connection});

  final Connection connection;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go(Routes.connectionSettingsPath(connection.id)),
      child: ConnectionAvatar(
        emoji: connection.emoji,
        colorIndex: connection.colorIndex,
        size: 40,
        glow: true,
      ),
    );
  }
}

class _TransportBadge extends StatelessWidget {
  const _TransportBadge({required this.kind, required this.label});

  final TransportKind kind;
  final String label;

  Color get _color => switch (kind) {
        TransportKind.direct => AppColors.transportDirect,
        TransportKind.localNetwork => AppColors.transportLocal,
        TransportKind.relay => AppColors.transportRelay,
        TransportKind.searching => AppColors.transportSearching,
      };

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Container(
      height: 36,
      constraints: const BoxConstraints(maxWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: 0.46)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [BoxShadow(color: color, blurRadius: 10)],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircularModeLayout extends StatelessWidget {
  const _CircularModeLayout({required this.activeConnection});

  final Connection? activeConnection;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        final layoutSize = math.min(size, 354.0);
        final radius = layoutSize * 0.36;
        final modes = kStarterModes;
        return Center(
          child: SizedBox(
            width: layoutSize,
            height: layoutSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: layoutSize * 0.73,
                  height: layoutSize * 0.73,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.pulse.withValues(alpha: 0.18),
                    ),
                  ),
                ),
                Container(
                  width: layoutSize * 0.52,
                  height: layoutSize * 0.52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.heart.withValues(alpha: 0.10),
                    ),
                  ),
                ),
                _CenterDisc(
                  onTap: () {
                    if (activeConnection == null) context.go(Routes.people);
                  },
                ),
                for (var i = 0; i < modes.length; i++)
                  _PositionedModeTile(
                    index: i,
                    total: modes.length + 1,
                    radius: radius,
                    descriptor: modes[i],
                    activeConnection: activeConnection,
                  ),
                _PositionedExtra(
                  index: modes.length,
                  total: modes.length + 1,
                  radius: radius,
                  onTap: () => context.go(Routes.modesCatalog),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PositionedModeTile extends ConsumerWidget {
  const _PositionedModeTile({
    required this.index,
    required this.total,
    required this.radius,
    required this.descriptor,
    required this.activeConnection,
  });

  final int index;
  final int total;
  final double radius;
  final PulseModeDescriptor descriptor;
  final Connection? activeConnection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final angle = (index / total) * 2 * math.pi - math.pi / 2;
    final unlocked = ref
        .read(subscriptionControllerProvider.notifier)
        .isModeUnlocked(descriptor.id);
    return Transform.translate(
      offset: Offset(math.cos(angle) * radius, math.sin(angle) * radius),
      child: _ModeDisc(
        descriptor: descriptor,
        locked: !unlocked,
        onTap: () {
          if (activeConnection == null) {
            context.go(Routes.people);
            return;
          }
          if (!unlocked) {
            context.go(Routes.subscription);
            return;
          }
          HapticFeedback.selectionClick();
        },
        onLongPress: () {
          if (activeConnection == null) {
            context.go(Routes.people);
            return;
          }
          if (!unlocked) {
            context.go(Routes.subscription);
            return;
          }
          context.go(Routes.modePath(descriptor.id.name));
        },
      ),
    );
  }
}

class _PositionedExtra extends StatelessWidget {
  const _PositionedExtra({
    required this.index,
    required this.total,
    required this.radius,
    required this.onTap,
  });

  final int index;
  final int total;
  final double radius;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final angle = (index / total) * 2 * math.pi - math.pi / 2;
    return Transform.translate(
      offset: Offset(math.cos(angle) * radius, math.sin(angle) * radius),
      child: GestureDetector(
        onTap: onTap,
        child: _ModeBubble(
          color: AppColors.textSecondary,
          glyph: '•••',
          label: t.hubMore,
          locked: false,
        ),
      ),
    );
  }
}

class _ModeDisc extends StatelessWidget {
  const _ModeDisc({
    required this.descriptor,
    required this.locked,
    required this.onTap,
    required this.onLongPress,
  });

  final PulseModeDescriptor descriptor;
  final bool locked;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final color = locked ? AppColors.textMuted : descriptor.tint;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: _ModeBubble(
        color: color,
        glyph: descriptor.glyph,
        label: localizedModeTitle(descriptor, t),
        locked: locked,
      ),
    );
  }
}

class _ModeBubble extends StatelessWidget {
  const _ModeBubble({
    required this.color,
    required this.glyph,
    required this.label,
    required this.locked,
  });

  final Color color;
  final String glyph;
  final String label;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      height: 88,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              PulseGlowCircle(
                size: 60,
                color: color,
                blur: locked ? 0 : 18,
                fill: AppColors.surface.withValues(alpha: 0.78),
                child: Text(
                  glyph,
                  style: TextStyle(
                    fontSize: glyph == '•••' ? 20 : 27,
                    color: locked ? AppColors.textMuted : null,
                    fontWeight: glyph == '•••' ? FontWeight.w900 : null,
                  ),
                ),
              ),
              if (locked)
                const Positioned(
                  right: -2,
                  bottom: -2,
                  child: PulseGlowCircle(
                    size: 18,
                    color: AppColors.outline,
                    blur: 0,
                    fill: AppColors.background,
                    borderWidth: 1,
                    child: Icon(
                      Icons.lock_rounded,
                      color: AppColors.textMuted,
                      size: 10,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: locked ? AppColors.textMuted : AppColors.textSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              height: 1,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _CenterDisc extends StatelessWidget {
  const _CenterDisc({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 104,
        height: 104,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            colors: [AppColors.heart, AppColors.pulse],
            stops: [0.08, 1],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.pulse.withValues(alpha: 0.60),
              blurRadius: 44,
              spreadRadius: 7,
            ),
            BoxShadow(
              color: AppColors.heart.withValues(alpha: 0.26),
              blurRadius: 32,
            ),
          ],
        ),
        alignment: Alignment.center,
        child: const Text('💜', style: TextStyle(fontSize: 42)),
      ),
    );
  }
}
