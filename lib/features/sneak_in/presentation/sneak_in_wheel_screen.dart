import 'dart:async';
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
import '../../connections/domain/connection_status.dart';
import '../application/sneak_in_controller.dart';
import 'sneak_signal_catalogue.dart';
import 'sneak_sound_player.dart';

/// 8-emoji selector wheel. Tap to highlight a sound, swipe up (or tap the
/// glowing center disc) to send it to the active partner.
class SneakInWheelScreen extends ConsumerStatefulWidget {
  const SneakInWheelScreen({super.key});

  @override
  ConsumerState<SneakInWheelScreen> createState() => _SneakInWheelScreenState();
}

class _SneakInWheelScreenState extends ConsumerState<SneakInWheelScreen> {
  int _selected = 0;

  /// Single source of truth for the wheel — the shared protocol catalogue.
  /// Order determines the angular position on the dial; ids are the wire
  /// payload sent to the partner.
  static const List<SneakSignal> _signals = kSneakSignals;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final state = ref.watch(connectionsControllerProvider);
    final pausedTargets = state.connections
        .where((c) =>
            c.permissions.allowSneakIn && c.status != ConnectionStatus.archived)
        .toList(growable: false);

    return BottomNavShell(
      current: BottomNavTab.sneakIn,
      body: PulseBackdrop(
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 104),
            child: Column(
              children: [
                PulseHeader(
                  title: t.sneakInTitle,
                  leading: PulseRoundButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => context.go(Routes.hub),
                    subtle: true,
                  ),
                  trailing: PulseRoundButton(
                    icon: Icons.notifications_active_rounded,
                    onTap: () {},
                    color: AppColors.heart,
                    subtle: true,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  t.sneakInChooseSound,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Expanded(
                  child: Center(
                    child: _Wheel(
                      signals: _signals,
                      selectedIndex: _selected,
                      onSelect: (i) {
                        setState(() => _selected = i);
                        HapticFeedback.selectionClick();
                        // Preview the signal so picking one is done by ear,
                        // not by reading labels. Fails soft (see player).
                        unawaited(
                          ref
                              .read(sneakSoundPlayerProvider)
                              .playSignal(_signals[i].id),
                        );
                      },
                      onCenterTap: () => _send(pausedTargets),
                    ),
                  ),
                ),
                PulsePanel(
                  radius: 22,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.keyboard_double_arrow_up_rounded,
                        color: AppColors.heart,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        t.sneakInSwipeUp,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _Targets(targets: pausedTargets),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _send(List<Connection> targets) async {
    if (targets.isEmpty) return;
    final t = AppLocalizations.of(context)!;
    final target = targets.first;
    final signal = _signals[_selected];
    // Quota check + real delivery over the encrypted session.
    final result = await ref
        .read(sneakInControllerProvider.notifier)
        .sendSneak(target.id, signal.id);
    if (!mounted) return;
    switch (result) {
      case SneakSendResult.limitReached:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.sneakInLimitReached)),
        );
        return;
      case SneakSendResult.noChannel:
        // No live partner channel: distinct error buzz, no navigation and
        // no fabricated copy (no offline string exists to reuse honestly).
        HapticFeedback.vibrate();
        return;
      case SneakSendResult.sent:
        HapticFeedback.mediumImpact();
        // Sender-side confirmation: hear what the partner will hear.
        unawaited(
          ref.read(sneakSoundPlayerProvider).playSignal(signal.id),
        );
        context.go(
          '${Routes.sneakInIncoming}?connectionId=${target.id}',
        );
        return;
    }
  }
}

class _Wheel extends StatelessWidget {
  const _Wheel({
    required this.signals,
    required this.selectedIndex,
    required this.onSelect,
    required this.onCenterTap,
  });

  final List<SneakSignal> signals;
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
        width: 334,
        height: 334,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 312,
              height: 312,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surface.withValues(alpha: 0.44),
                border: Border.all(color: AppColors.outlineSoft),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.heart.withValues(alpha: 0.13),
                    blurRadius: 42,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            CustomPaint(
              size: const Size.square(300),
              painter: _WheelPainter(selectedIndex: selectedIndex),
            ),
            for (var i = 0; i < signals.length; i++)
              _emojiTile(
                context,
                index: i,
                total: signals.length,
                radius: 118,
              ),
            GestureDetector(
              onTap: onCenterTap,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [AppColors.heart, AppColors.pulse],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.pulse.withValues(alpha: 0.55),
                      blurRadius: 36,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.send_rounded,
                  color: Colors.white,
                  size: 31,
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
          width: selected ? 62 : 56,
          height: selected ? 62 : 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.surface.withValues(alpha: 0.9),
            border: Border.all(
              color: selected ? AppColors.heart : AppColors.outlineSoft,
              width: selected ? 2.2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.heart.withValues(alpha: 0.44),
                      blurRadius: 24,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            signals[index].emoji,
            style: TextStyle(fontSize: selected ? 29 : 25),
          ),
        ),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  const _WheelPainter({required this.selectedIndex});

  final int selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 8; i++) {
      final start = -math.pi / 2 + i * math.pi / 4;
      paint.color = (i == selectedIndex ? AppColors.heart : AppColors.pulse)
          .withValues(alpha: i == selectedIndex ? 0.20 : 0.055);
      canvas.drawArc(rect, start, math.pi / 4 - 0.018, true, paint);
    }
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.outlineSoft;
    canvas.drawCircle(center, radius, linePaint);
    canvas.drawCircle(center, 86, linePaint);
    for (var i = 0; i < 8; i++) {
      final angle = -math.pi / 2 + i * math.pi / 4;
      canvas.drawLine(
        center + Offset(math.cos(angle), math.sin(angle)) * 92,
        center + Offset(math.cos(angle), math.sin(angle)) * radius,
        linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_WheelPainter oldDelegate) =>
      oldDelegate.selectedIndex != selectedIndex;
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
    final remaining =
        ref.watch(sneakInControllerProvider.notifier).remaining(connection.id);
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
