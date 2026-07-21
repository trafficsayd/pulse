import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../capabilities/application/capability_providers.dart';
import '../../../capabilities/domain/device_capability.dart';
import '../../primitives/accelerometer_3d_stream.dart';
import '../../primitives/primitive_providers.dart';
import '../../../session/application/mode_event.dart';
import '../../../session/application/mode_event_bus.dart';
import 'unsupported_mode_screen.dart';

/// "Balance" — tilt the phone to roll a glowing ball. Both users see
/// both balls on a shared virtual surface; the goal is to guide both
/// balls into the centre simultaneously, which triggers a satisfying
/// "click" haptic.
///
/// Requires [DeviceCapability.accelerometer].
class BalanceModeScreen extends ConsumerWidget {
  const BalanceModeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final capsAsync = ref.watch(deviceCapabilitiesProvider);
    const required = {DeviceCapability.accelerometer};
    if (capsAsync.isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.pulse)),
      );
    }
    final caps = capsAsync.asData?.value ?? const DeviceCapabilities.none();
    if (!caps.hasAll(required)) {
      return UnsupportedModeScreen(
        title: t.modeBalance,
        missing: caps.missing(required),
      );
    }
    return _BalanceModeView(
      accelerometer: ref.watch(accelerometerStreamProvider),
    );
  }
}

class _BalanceModeView extends ConsumerStatefulWidget {
  const _BalanceModeView({required this.accelerometer});
  final Accelerometer3DStream accelerometer;

  @override
  ConsumerState<_BalanceModeView> createState() => _BalanceModeViewState();
}

class _BalanceModeViewState extends ConsumerState<_BalanceModeView> {
  StreamSubscription<Accel3>? _sub;
  StreamSubscription<ModeEvent>? _partnerSub;
  Offset _localBall = Offset.zero;
  Offset _partnerBall = const Offset(999, 999); // off-screen initially
  Size _canvasSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _sub = widget.accelerometer.events.listen(_onAccel);
    _partnerSub = ref.read(modeEventBusProvider).incoming
        .where((e) => e.type == 'balance_ball')
        .listen(_onPartnerBall);
  }

  void _onAccel(Accel3 sample) {
    if (!mounted || _canvasSize == Size.zero) return;
    // Map accelerometer tilt to ball position within the canvas.
    // Clamp to ±6 m/s² for full deflection.
    final nx = (sample.x / 6).clamp(-1.0, 1.0);
    final ny = (sample.y / 6).clamp(-1.0, 1.0);
    final newX = _canvasSize.width / 2 + nx * _canvasSize.width * 0.4;
    final newY = _canvasSize.height / 2 + ny * _canvasSize.height * 0.4;
    final newOffset = Offset(newX, newY);
    if ((newOffset - _localBall).distance < 2) return; // throttle
    setState(() => _localBall = newOffset);
    // Send to partner.
    ref.read(modeEventBusProvider).send(ModeEvent(
      type: 'balance_ball',
      data: {
        'x': newX / _canvasSize.width,
        'y': newY / _canvasSize.height,
      },
    ));
  }

  void _onPartnerBall(ModeEvent event) {
    if (!mounted || _canvasSize == Size.zero) return;
    final x = (event.data['x'] as num?)?.toDouble() ?? 0.5;
    final y = (event.data['y'] as num?)?.toDouble() ?? 0.5;
    setState(() => _partnerBall = Offset(x * _canvasSize.width, y * _canvasSize.height));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _partnerSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            _canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
            final center = Offset(_canvasSize.width / 2, _canvasSize.height / 2);
            final bothInCenter =
                (_localBall - center).distance < 40 &&
                (_partnerBall - center).distance < 40;
            return Stack(
              children: [
                // Target ring in centre.
                Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.pulse.withValues(alpha: bothInCenter ? 0.8 : 0.3),
                        width: 2,
                      ),
                      boxShadow: bothInCenter
                          ? [BoxShadow(color: AppColors.pulse.withValues(alpha: 0.5), blurRadius: 30)]
                          : null,
                    ),
                  ),
                ),
                // Partner ball (faint).
                _Ball(position: _partnerBall, color: AppColors.heart, radius: 14, faint: true),
                // Local ball.
                _Ball(position: _localBall, color: AppColors.pulse, radius: 16),
                Positioned(
                  top: 14,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Text(
                      t.modeBalance,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    tooltip: t.hubExit,
                    color: AppColors.textSecondary,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Ball extends StatelessWidget {
  const _Ball({
    required this.position,
    required this.color,
    required this.radius,
    this.faint = false,
  });
  final Offset position;
  final Color color;
  final double radius;
  final bool faint;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx - radius,
      top: position.dy - radius,
      child: Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: faint ? 0.4 : 0.9),
          boxShadow: faint
              ? null
              : [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 20)],
        ),
      ),
    );
  }
}
