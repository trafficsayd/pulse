import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pulse/l10n/app_localizations.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/bottom_nav_shell.dart';
import '../../../core/widgets/connection_avatar.dart';
import '../../../core/widgets/transport_pill.dart';
import '../../connections/application/connections_controller.dart';
import '../../connections/domain/connection.dart';
import '../../modes/application/mode_registry.dart';
import '../../modes/domain/pulse_mode.dart';
import '../../subscription/application/subscription_controller.dart';
import '../../transport/transport.dart';

const double _modeTileWidth = 84;
const double _modeTileHeight = 104;
const double _modeDiscSize = 64;

/// Main canvas after pairing.
///
/// Layout matches the design: a transport pill in the top-left, the active
/// partner avatar in the top-right; a circular constellation of mode
/// glyphs around a central "PULSE" disc; the long-press hint and bottom
/// tab bar below.
class HubScreen extends ConsumerWidget {
  const HubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final connections = ref.watch(connectionsControllerProvider);
    final activeConnection = connections.active;

    // Demo: while we have no real transport, show a "Direct (BLE)" pill if
    // we have an active connection, otherwise "Searching".
    final transportKind = activeConnection != null
        ? TransportKind.direct
        : TransportKind.searching;
    final transportLabel = activeConnection != null
        ? t.transportDirectBle
        : t.transportSearching;

    return BottomNavShell(
      current: BottomNavTab.pulse,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () => context.go(Routes.settings),
                    icon: const Icon(
                      Icons.menu_rounded,
                      color: AppColors.textSecondary,
                    ),
                    tooltip: t.settingsTitle,
                  ),
                  const Spacer(),
                  if (activeConnection != null)
                    _ActiveAvatar(connection: activeConnection),
                  if (activeConnection != null) const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => context.go(Routes.connectionStatus),
                    child: TransportPill(
                      kind: transportKind,
                      label: transportLabel,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _CircularModeLayout(activeConnection: activeConnection),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                t.hubLongPressToStart,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveAvatar extends StatelessWidget {
  const _ActiveAvatar({required this.connection});

  final Connection connection;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () =>
          context.go(Routes.connectionSettingsPath(connection.id)),
      child: ConnectionAvatar(
        emoji: connection.emoji,
        colorIndex: connection.colorIndex,
        size: 40,
      ),
    );
  }
}

class _CircularModeLayout extends ConsumerWidget {
  const _CircularModeLayout({required this.activeConnection});

  final Connection? activeConnection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Square layout sized to the smaller dimension so the constellation
        // never clips on narrow phones.
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        final modes = kStarterModes;
        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                _CenterDisc(
                  onTap: () {
                    if (activeConnection == null) {
                      context.go(Routes.people);
                    }
                  },
                ),
                for (var i = 0; i < modes.length; i++)
                  _PositionedModeTile(
                    index: i,
                    total: modes.length + 1,
                    radius: size * 0.36,
                    descriptor: modes[i],
                    activeConnection: activeConnection,
                  ),
                _PositionedExtra(
                  index: modes.length,
                  total: modes.length + 1,
                  radius: size * 0.36,
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
    final dx = math.cos(angle) * radius;
    final dy = math.sin(angle) * radius;
    final unlocked = ref
        .read(subscriptionControllerProvider.notifier)
        .isModeUnlocked(descriptor.id);
    return Transform.translate(
      offset: Offset(dx, dy),
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
    final dx = math.cos(angle) * radius;
    final dy = math.sin(angle) * radius;
    return Transform.translate(
      offset: Offset(dx, dy),
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: _modeTileWidth,
          height: _modeTileHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(
                width: _modeDiscSize,
                height: _modeDiscSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.outline),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.more_horiz_rounded,
                  color: AppColors.textSecondary,
                  size: 22,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                t.hubMore,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
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
      child: SizedBox(
        width: _modeTileWidth,
        height: _modeTileHeight,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: _modeDiscSize,
                  height: _modeDiscSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.16),
                    border: Border.all(color: color, width: 1.4),
                    boxShadow: locked
                        ? null
                        : [
                            BoxShadow(
                              color: color.withValues(alpha: 0.35),
                              blurRadius: 18,
                            ),
                          ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    descriptor.glyph,
                    style: TextStyle(
                      fontSize: 28,
                      color: locked ? AppColors.textMuted : null,
                    ),
                  ),
                ),
                if (locked)
                  Positioned(
                    bottom: 0,
                    right: 6,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.background,
                        border: Border.all(color: AppColors.outline),
                      ),
                      child: const Icon(
                        Icons.lock_rounded,
                        size: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              localizedModeTitle(descriptor, t),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: locked ? AppColors.textMuted : AppColors.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenterDisc extends StatelessWidget {
  const _CenterDisc({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            colors: [AppColors.pulse, AppColors.pulseDeep],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.pulseGlow,
              blurRadius: 40,
              spreadRadius: 6,
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          t.appTitle.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 3,
          ),
        ),
      ),
    );
  }
}
