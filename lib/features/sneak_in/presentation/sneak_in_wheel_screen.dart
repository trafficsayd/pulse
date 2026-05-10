import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/pulse_bottom_nav.dart';
import '../../connections/application/connections_controller.dart';
import '../../connections/domain/connection.dart';
import '../application/sneak_in_controller.dart';
import 'sneak_signal_catalogue.dart';

/// Sneak In wheel — pick one of N short sounds, swipe up to send to a paused
/// partner.
///
/// The actual transmission lives in the transport layer; this screen is
/// only responsible for picking a signal and respecting the per-day quota
/// enforced by [SneakInController].
class SneakInWheelScreen extends ConsumerStatefulWidget {
  const SneakInWheelScreen({super.key});

  @override
  ConsumerState<SneakInWheelScreen> createState() => _SneakInWheelScreenState();
}

class _SneakInWheelScreenState extends ConsumerState<SneakInWheelScreen> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final state = ref.watch(connectionsControllerProvider);
    final pausedTargets = state.connections
        .where((c) => c.permissions.allowSneakIn)
        .toList(growable: false);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(t.sneakInPickSound)),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: _SignalWheel(
                    selectedIndex: _selected,
                    onSelect: (i) => setState(() => _selected = i),
                  ),
                ),
              ),
              const _SwipeUpAffordance(),
              const SizedBox(height: 8),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: _Targets(
                  targets: pausedTargets,
                  selectedSignalIndex: _selected,
                ),
              ),
              const PulseBottomNav(active: PulseNavTab.sneakIn),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignalWheel extends StatelessWidget {
  const _SignalWheel({required this.selectedIndex, required this.onSelect});

  final int selectedIndex;
  final void Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    const radius = 120.0;
    const signals = kSneakSignals;
    return SizedBox(
      width: radius * 2 + 80,
      height: radius * 2 + 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: radius * 2,
            height: radius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.outline),
            ),
          ),
          for (var i = 0; i < signals.length; i++)
            _wheelTile(
              index: i,
              total: signals.length,
              radius: radius,
              selected: i == selectedIndex,
              icon: signals[i].icon,
              onTap: () => onSelect(i),
            ),
        ],
      ),
    );
  }

  Widget _wheelTile({
    required int index,
    required int total,
    required double radius,
    required bool selected,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final angle = (index / total) * 2 * math.pi - math.pi / 2;
    final x = math.cos(angle) * radius;
    final y = math.sin(angle) * radius;
    return Transform.translate(
      offset: Offset(x, y),
      child: GestureDetector(
        onTap: onTap,
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
          child: Icon(
            icon,
            color: selected ? AppColors.pulse : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _SwipeUpAffordance extends StatelessWidget {
  const _SwipeUpAffordance();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Column(
      children: [
        const Icon(Icons.keyboard_arrow_up_rounded, color: AppColors.textMuted),
        const SizedBox(height: 4),
        Text(
          t.sneakInSwipeUp,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ],
    );
  }
}

class _Targets extends ConsumerWidget {
  const _Targets({required this.targets, required this.selectedSignalIndex});

  final List<Connection> targets;
  final int selectedSignalIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (targets.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final c in targets)
          GestureDetector(
            onVerticalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) < -200) {
                _send(context, ref, c);
              }
            },
            onTap: () => _send(context, ref, c),
            child: _TargetChip(connection: c),
          ),
      ],
    );
  }

  Future<void> _send(
    BuildContext context,
    WidgetRef ref,
    Connection target,
  ) async {
    final ok = await ref
        .read(sneakInControllerProvider.notifier)
        .tryRecordSneakIn(target.id);
    if (!ok) {
      if (!context.mounted) return;
      final t = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.sneakInLimitReached)),
      );
      return;
    }
    HapticFeedback.mediumImpact();
    // TODO(transport): publish a sneak_signal packet via TransportManager.
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
    final color = AppColors.avatarPalette[
        connection.colorIndex % AppColors.avatarPalette.length];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(connection.emoji),
          const SizedBox(width: 6),
          Text(
            connection.nickname,
            style: const TextStyle(color: AppColors.textPrimary),
          ),
          const SizedBox(width: 6),
          Text(
            t.sneakInRemaining(remaining),
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
