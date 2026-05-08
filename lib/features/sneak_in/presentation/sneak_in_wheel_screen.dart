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
import '../../connections/application/connections_controller.dart';
import '../../connections/domain/connection.dart';
import '../../connections/domain/connection_status.dart';
import '../application/sneak_in_controller.dart';

/// 8-emoji selector wheel. Tap to highlight a sound, swipe up (or tap the
/// glowing center disc) to send it to the active partner.
class SneakInWheelScreen extends ConsumerStatefulWidget {
  const SneakInWheelScreen({super.key});

  @override
  ConsumerState<SneakInWheelScreen> createState() =>
      _SneakInWheelScreenState();
}

class _SneakInWheelScreenState extends ConsumerState<SneakInWheelScreen> {
  int _selected = 0;

  static const List<_SneakEmoji> _emojis = [
    _SneakEmoji('🤭', 'sneakSignalHiccup'),
    _SneakEmoji('💨', 'sneakSignalToot'),
    _SneakEmoji('🔔', 'sneakSignalBell'),
    _SneakEmoji('👻', 'sneakSignalKnock'),
    _SneakEmoji('🤫', 'sneakSignalWhisper'),
    _SneakEmoji('👏', 'sneakSignalClap'),
    _SneakEmoji('💥', 'sneakSignalBoom'),
    _SneakEmoji('🐭', 'sneakSignalSqueak'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final state = ref.watch(connectionsControllerProvider);
    final pausedTargets = state.connections
        .where((c) =>
            c.permissions.allowSneakIn &&
            c.status != ConnectionStatus.archived)
        .toList(growable: false);

    return BottomNavShell(
      current: BottomNavTab.sneakIn,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                t.sneakInTitle,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                t.sneakInChooseSound,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: _Wheel(
                  emojis: _emojis,
                  selectedIndex: _selected,
                  onSelect: (i) {
                    setState(() => _selected = i);
                    HapticFeedback.selectionClick();
                  },
                  onCenterTap: () => _send(pausedTargets),
                ),
              ),
            ),
            Text(
              t.sneakInSwipeUp,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _Targets(targets: pausedTargets),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _send(List<Connection> targets) async {
    if (targets.isEmpty) return;
    final t = AppLocalizations.of(context)!;
    final target = targets.first;
    final ok = await ref
        .read(sneakInControllerProvider.notifier)
        .tryRecordSneakIn(target.id);
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.sneakInLimitReached)),
      );
      return;
    }
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    context.go(
      '${Routes.sneakInIncoming}?connectionId=${target.id}',
    );
  }
}

class _SneakEmoji {
  const _SneakEmoji(this.emoji, this.titleKey);
  final String emoji;
  final String titleKey;
}

class _Wheel extends StatelessWidget {
  const _Wheel({
    required this.emojis,
    required this.selectedIndex,
    required this.onSelect,
    required this.onCenterTap,
  });

  final List<_SneakEmoji> emojis;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onCenterTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -200) onCenterTap();
      },
      child: SizedBox(
        width: 320,
        height: 320,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.outline),
              ),
            ),
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.outlineSoft),
              ),
            ),
            for (var i = 0; i < emojis.length; i++)
              _emojiTile(
                context,
                index: i,
                total: emojis.length,
                radius: 120,
              ),
            GestureDetector(
              onTap: onCenterTap,
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [AppColors.pulse, AppColors.heart],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.pulse.withValues(alpha: 0.5),
                      blurRadius: 32,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.send_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emojiTile(
    BuildContext context, {
    required int index,
    required int total,
    required double radius,
  }) {
    final angle = (index / total) * 2 * math.pi - math.pi / 2;
    final dx = math.cos(angle) * radius;
    final dy = math.sin(angle) * radius;
    final selected = index == selectedIndex;
    return Transform.translate(
      offset: Offset(dx, dy),
      child: GestureDetector(
        onTap: () => onSelect(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected
                ? AppColors.pulse.withValues(alpha: 0.18)
                : AppColors.surface,
            border: Border.all(
              color: selected ? AppColors.pulse : AppColors.outline,
              width: selected ? 2 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            emojis[index].emoji,
            style: const TextStyle(fontSize: 26),
          ),
        ),
      ),
    );
  }
}

class _Targets extends ConsumerWidget {
  const _Targets({required this.targets});

  final List<Connection> targets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (targets.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final c in targets) _TargetChip(connection: c),
      ],
    );
  }
}

class _TargetChip extends ConsumerWidget {
  const _TargetChip({required this.connection});

  final Connection connection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final remaining = ref
        .watch(sneakInControllerProvider.notifier)
        .remaining(connection.id);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConnectionAvatar(
            emoji: connection.emoji,
            colorIndex: connection.colorIndex,
            size: 22,
            showRing: false,
          ),
          const SizedBox(width: 8),
          Text(
            connection.nickname,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            t.sneakInRemaining(remaining),
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
