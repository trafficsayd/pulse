import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../transport/transport.dart';
import '../application/connections_controller.dart';

/// Live connection diagnostics: which transport is in use, signal quality
/// across all candidates (BLE, Wi-Fi Direct, WebRTC) and the standing
/// privacy reminder.
class ConnectionDetailsScreen extends ConsumerWidget {
  const ConnectionDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final activeId = ref.watch(connectionsControllerProvider).activeId;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(t.connectionDetailsTitle)),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            _TransportCard(
              icon: Icons.bluetooth_rounded,
              label: t.connectionBle,
              kind: TransportKind.direct,
              bars: 4,
            ),
            const SizedBox(height: 12),
            _TransportCard(
              icon: Icons.wifi_rounded,
              label: t.connectionWifiDirect,
              kind: TransportKind.localNetwork,
              bars: 3,
            ),
            const SizedBox(height: 12),
            _TransportCard(
              icon: Icons.cloud_outlined,
              label: t.connectionWebrtc,
              kind: TransportKind.relay,
              bars: 2,
            ),
            if (activeId != null) ...[
              const SizedBox(height: 16),
              _FingerprintCard(connectionId: activeId),
            ],
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                t.connectionPrivacyNote,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _FingerprintCard extends ConsumerWidget {
  const _FingerprintCard({required this.connectionId});

  final String connectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final manager = ref.watch(pulseKeyManagerProvider);
    return FutureBuilder<String?>(
      future: manager.localFingerprint(connectionId),
      builder: (context, snapshot) {
        final fingerprint = snapshot.data;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.outline),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.pulse.withValues(alpha: 0.18),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.fingerprint_rounded,
                  color: AppColors.pulse,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.connectionKeyFingerprint,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      fingerprint ?? t.connectionKeyFingerprintUnavailable,
                      style: TextStyle(
                        color: fingerprint == null
                            ? AppColors.textMuted
                            : AppColors.textSecondary,
                        fontSize: 13,
                        fontFamily: 'monospace',
                        letterSpacing: 1.2,
                      ),
                    ),
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

class _TransportCard extends StatelessWidget {
  const _TransportCard({
    required this.icon,
    required this.label,
    required this.kind,
    required this.bars,
  });

  final IconData icon;
  final String label;
  final TransportKind kind;
  final int bars;

  Color _color() => switch (kind) {
        TransportKind.direct => AppColors.transportDirect,
        TransportKind.localNetwork => AppColors.transportLocal,
        TransportKind.relay => AppColors.transportRelay,
        TransportKind.searching => AppColors.transportSearching,
      };

  @override
  Widget build(BuildContext context) {
    final color = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.18),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          _SignalBars(bars: bars, color: color),
        ],
      ),
    );
  }
}

class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.bars, required this.color});
  final int bars;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (i) {
        final filled = i < bars;
        return Container(
          width: 4,
          height: 6.0 + i * 4,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(
            color: filled ? color : AppColors.outline,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}
