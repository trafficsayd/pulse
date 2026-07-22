import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/pulse_mockup.dart';
import '../../../l10n/app_localizations.dart';
import '../../connections/application/connections_controller.dart';
import '../../pairing/application/pairing_controller.dart';

/// "Establishing connection..." — animated handshake screen shown right
/// after a pair is initiated.
///
/// Two phone glyphs face each other across a dotted ring; below, three
/// progressive checklist items light up as the handshake advances:
///   1. Key exchange  (ECDH on Curve25519)
///   2. Channel encrypted  (HKDF-SHA-256 + AES-256-GCM ready)
///   3. Secure link established  (PairKeys persisted to SecureKeyStore)
///
/// After the third item lights, the screen auto-routes into the hub.
class ConnectingScreen extends ConsumerStatefulWidget {
  const ConnectingScreen({super.key});

  @override
  ConsumerState<ConnectingScreen> createState() => _ConnectingScreenState();
}

class _ConnectingScreenState extends ConsumerState<ConnectingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _orbit;
  bool _persisting = false;
  bool _routed = false;

  @override
  void initState() {
    super.initState();
    _orbit = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    // NOTE: persistence is NOT started automatically. Key material is only
    // written after the user explicitly confirms the SAS codes match — see
    // the verification gate in [build] and [_confirmMatch]. This is the
    // anti-MITM defence required by §6 of the spec.
  }

  /// User compared the SAS code shown here with their partner's screen and
  /// confirmed the two are identical. Only now do we persist key material.
  Future<void> _confirmMatch() async {
    if (_persisting || _routed) return;
    setState(() => _persisting = true);
    final controller = ref.read(pairingControllerProvider.notifier);
    final result = await controller.confirmAndPersist(sasConfirmed: true);
    if (!mounted) return;
    if (result == null) {
      // Persistence failed — bounce back to pairing so the user can
      // retry. Avoids leaving them on a stuck "establishing" spinner.
      context.go(Routes.pairing);
      return;
    }
    final pairingState = ref.read(pairingControllerProvider);
    await ref
        .read(connectionsControllerProvider.notifier)
        .createPairedConnection(
          connectionId: result.connectionId,
          nickname: AppLocalizations.of(context)?.appTitle ?? 'Pulse',
          signalingToken: pairingState.signalingToken ?? result.connectionId,
        );
    // Give the orbit animation a beat to feel intentional, then hub.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted || _routed) return;
    _routed = true;
    context.go(Routes.hub);
  }

  /// User reported the codes do NOT match — abort without persisting and
  /// return to pairing. A mismatch is a strong indicator of a MITM.
  void _abortMismatch() {
    ref.read(pairingControllerProvider.notifier).abortPairing();
    if (!mounted) return;
    context.go(Routes.pairing);
  }

  @override
  void dispose() {
    _orbit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final state = ref.watch(pairingControllerProvider);
    final step = _stepFromPhase(state.phase);
    // Anti-MITM gate: while the handshake sits at awaitingConfirmation and we
    // have not yet started persisting, show the SAS comparison screen instead
    // of the progress animation. Persistence cannot proceed until the user
    // taps "the codes match".
    final showVerifyGate =
        state.phase == PairingPhase.awaitingConfirmation && !_persisting;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: PulseBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
            child: showVerifyGate
                ? _VerifyGate(
                    code: state.sasCode ?? '······',
                    onMatch: _confirmMatch,
                    onMismatch: _abortMismatch,
                  )
                : Column(
              children: [
                PulseHeader(title: t.connectingTitle),
                const SizedBox(height: 34),
                Text(
                  t.connectingTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.35,
                  ),
                ),
                const SizedBox(height: 34),
                PulsePanel(
                  radius: 34,
                  padding: const EdgeInsets.all(18),
                  child: SizedBox(
                    width: 286,
                    height: 286,
                    child: AnimatedBuilder(
                      animation: _orbit,
                      builder: (context, _) {
                        return CustomPaint(
                          painter: _DottedRingPainter(progress: _orbit.value),
                          child: const Stack(
                            alignment: Alignment.center,
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: _PhoneGlyph(rotated: false),
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: _PhoneGlyph(rotated: true),
                              ),
                              PulseGlowCircle(
                                size: 72,
                                color: AppColors.pulse,
                                fill: AppColors.surface,
                                blur: 28,
                                borderWidth: 1,
                                child: Icon(
                                  Icons.lock_rounded,
                                  color: AppColors.pulse,
                                  size: 28,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const Spacer(),
                PulsePanel(
                  radius: 28,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _StepRow(
                        done: step >= 1,
                        inProgress: step == 0,
                        label: t.connectingKeyExchange,
                      ),
                      const SizedBox(height: 14),
                      _StepRow(
                        done: step >= 2,
                        inProgress: step == 1,
                        label: t.connectingChannelEncrypted,
                      ),
                      const SizedBox(height: 14),
                      _StepRow(
                        done: step >= 3,
                        inProgress: step == 2,
                        label: t.connectingSecuredLink,
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

  /// Map an opaque [PairingPhase] onto the 0..3 progress indicator that
  /// the three-step checklist understands.
  int _stepFromPhase(PairingPhase phase) {
    switch (phase) {
      case PairingPhase.idle:
      case PairingPhase.generatingKeys:
      case PairingPhase.awaitingPartner:
        return 0;
      case PairingPhase.derivingSecret:
      case PairingPhase.awaitingConfirmation:
        return 1;
      case PairingPhase.persisting:
        return 2;
      case PairingPhase.ready:
        return 3;
      case PairingPhase.failed:
        return 0;
    }
  }
}

/// SAS comparison gate. Presents the short authentication string large and
/// centred with two explicit choices. Confirming persistence is impossible
/// without the affirmative "codes match" tap, which is the app's only
/// defence against an active man-in-the-middle on the signaling path.
class _VerifyGate extends StatelessWidget {
  const _VerifyGate({
    required this.code,
    required this.onMatch,
    required this.onMismatch,
  });

  final String code;
  final VoidCallback onMatch;
  final VoidCallback onMismatch;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Column(
      children: [
        PulseHeader(title: t.connectingTitle),
        const Spacer(),
        const PulseGlowCircle(
          size: 78,
          color: AppColors.pulse,
          fill: AppColors.surface,
          blur: 30,
          borderWidth: 1,
          child: Icon(Icons.verified_user_rounded,
              color: AppColors.pulse, size: 34),
        ),
        const SizedBox(height: 26),
        Text(
          t.verifyCodeTitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            t.verifyCodeBody,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 28),
        PulsePanel(
          radius: 22,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
          child: Text(
            code,
            style: const TextStyle(
              color: AppColors.pulse,
              fontSize: 40,
              height: 1,
              fontWeight: FontWeight.w700,
              letterSpacing: 10,
              fontFamily: 'monospace',
            ),
          ),
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: onMatch,
            child: Text(t.verifyCodeMatch),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onMismatch,
          child: Text(
            t.verifyCodeMismatch,
            style: const TextStyle(color: AppColors.danger),
          ),
        ),
      ],
    );
  }
}

class _PhoneGlyph extends StatelessWidget {
  const _PhoneGlyph({required this.rotated});

  final bool rotated;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: rotated ? 0.18 : -0.18,
      child: Container(
        width: 56,
        height: 96,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.pulse, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: AppColors.pulse.withValues(alpha: 0.4),
              blurRadius: 24,
            ),
          ],
        ),
        child: const Center(
          child: Icon(
            Icons.smartphone_rounded,
            color: AppColors.pulse,
            size: 28,
          ),
        ),
      ),
    );
  }
}

class _DottedRingPainter extends CustomPainter {
  _DottedRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 8;
    final paint = Paint()..style = PaintingStyle.fill;

    const totalDots = 48;
    for (var i = 0; i < totalDots; i++) {
      final angle = (i / totalDots) * 2 * math.pi;
      final shifted = (i / totalDots + progress) % 1.0;
      paint.color = AppColors.pulse.withValues(
        alpha: 0.18 + 0.6 * (1 - (shifted - 0.5).abs() * 2).clamp(0.0, 1.0),
      );
      final p = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      canvas.drawCircle(p, 1.6, paint);
    }
  }

  @override
  bool shouldRepaint(_DottedRingPainter old) => old.progress != progress;
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.done,
    required this.inProgress,
    required this.label,
  });

  final bool done;
  final bool inProgress;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = done
        ? AppColors.transportDirect
        : inProgress
            ? AppColors.pulse
            : AppColors.textMuted;
    return Row(
      children: [
        SizedBox(
          width: 22,
          height: 22,
          child: done
              ? Container(
                  decoration: const BoxDecoration(
                    color: AppColors.transportDirect,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                )
              : inProgress
                  ? const CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppColors.pulse),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.outline),
                      ),
                    ),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
