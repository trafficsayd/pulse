import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../connections/application/connections_controller.dart';

/// First-launch screen: create a new pair (host) or join one (guest).
///
/// In production this orchestrates the Curve25519 ECDH exchange behind a
/// 6-digit short code. For the foundation PR we only wire up the UI flow
/// and persist a stub Connection so the rest of the app can be exercised.
class PairingScreen extends ConsumerWidget {
  const PairingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              const _PulseGlyph(),
              const SizedBox(height: 24),
              Text(
                t.appTitle,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 4,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _onCreatePair(context, ref),
                  child: Text(t.pairingCreate),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _onJoinPair(context, ref),
                  child: Text(t.pairingJoin),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onCreatePair(BuildContext context, WidgetRef ref) async {
    // TODO(pairing): generate Curve25519 keypair, derive 6-digit code, show
    // it via a sheet, await partner's acknowledgement, persist via PairKeys.
    await ref.read(connectionsControllerProvider.notifier).createStubConnection(
          nickname: 'Demo',
        );
    if (context.mounted) context.go(Routes.hub);
  }

  Future<void> _onJoinPair(BuildContext context, WidgetRef ref) async {
    // TODO(pairing): show 6-digit numeric input, complete ECDH on submit.
    await ref.read(connectionsControllerProvider.notifier).createStubConnection(
          nickname: 'Demo',
        );
    if (context.mounted) context.go(Routes.hub);
  }
}

class _PulseGlyph extends StatefulWidget {
  const _PulseGlyph();

  @override
  State<_PulseGlyph> createState() => _PulseGlyphState();
}

class _PulseGlyphState extends State<_PulseGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final phase = _c.value;
        return SizedBox(
          width: 160,
          height: 160,
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (final delay in const [0.0, 0.33, 0.66])
                Transform.scale(
                  scale: 0.4 + ((phase + delay) % 1.0) * 1.4,
                  child: Opacity(
                    opacity: (1 - ((phase + delay) % 1.0)).clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.pulse, width: 1.4),
                      ),
                    ),
                  ),
                ),
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: AppColors.pulse,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: AppColors.pulseGlow, blurRadius: 24),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
