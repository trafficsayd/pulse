import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';

/// "Establishing connection…" splash. Walks through three checklist items
/// (key exchange → channel encryption → secure link) before continuing
/// onto the hub. The animation is fully local — no transport is started.
class ConnectionSetupScreen extends ConsumerStatefulWidget {
  const ConnectionSetupScreen({super.key});

  @override
  ConsumerState<ConnectionSetupScreen> createState() =>
      _ConnectionSetupScreenState();
}

class _ConnectionSetupScreenState extends ConsumerState<ConnectionSetupScreen>
    with SingleTickerProviderStateMixin {
  static const _stepCount = 3;
  int _step = 0;
  Timer? _timer;
  late final AnimationController _ring = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 900), (t) {
      if (!mounted) return;
      setState(() => _step++);
      if (_step >= _stepCount) {
        t.cancel();
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) context.go(Routes.hub);
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const Spacer(),
                AnimatedBuilder(
                  animation: _ring,
                  builder: (context, _) => Transform.rotate(
                    angle: _ring.value * 6.283,
                    child: Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: AppColors.pulse, width: 2),
                        boxShadow: const [
                          BoxShadow(
                              color: AppColors.pulseHalo, blurRadius: 48),
                        ],
                        gradient: const SweepGradient(
                          colors: [
                            Colors.transparent,
                            AppColors.pulse,
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  t.connSetupTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 28),
                _ChecklistItem(
                  label: t.connSetupKeys,
                  done: _step >= 1,
                  inProgress: _step == 0,
                ),
                _ChecklistItem(
                  label: t.connSetupEncrypt,
                  done: _step >= 2,
                  inProgress: _step == 1,
                ),
                _ChecklistItem(
                  label: t.connSetupSecure,
                  done: _step >= 3,
                  inProgress: _step == 2,
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChecklistItem extends StatelessWidget {
  const _ChecklistItem({
    required this.label,
    required this.done,
    required this.inProgress,
  });

  final String label;
  final bool done;
  final bool inProgress;

  @override
  Widget build(BuildContext context) {
    final color = done
        ? AppColors.statusActive
        : inProgress
            ? AppColors.pulse
            : AppColors.textMuted;
    final icon = done
        ? Icons.check_circle_rounded
        : inProgress
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_off_rounded;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: done || inProgress
                    ? AppColors.textPrimary
                    : AppColors.textMuted,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
