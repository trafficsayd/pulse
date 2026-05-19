import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/channel_bars.dart';
import '../../../core/widgets/pulse_mockup.dart';
import '../../transport/transport.dart';

/// Connection status — shows BLE / Wi-Fi Direct / WebRTC channel state
/// with bar indicators, plus a footer banner reminding the user that the
/// app works offline and never sends payloads to a server.
class ConnectionStatusScreen extends StatelessWidget {
  const ConnectionStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: PulseBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            child: Column(
              children: [
                PulseHeader(title: t.connectionStatusTitle),
                const SizedBox(height: 18),
                PulsePanel(
                  radius: 30,
                  padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(left: 4, bottom: 10),
                        child: Text(
                          'TRANSPORT',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      _ChannelTile(
                        icon: Icons.bluetooth_rounded,
                        title: t.transportDirectBle,
                        bars: 4,
                        kind: TransportKind.direct,
                        active: true,
                      ),
                      _ChannelTile(
                        icon: Icons.wifi_rounded,
                        title: t.transportLocalWifi,
                        bars: 2,
                        kind: TransportKind.localNetwork,
                        active: false,
                      ),
                      _ChannelTile(
                        icon: Icons.cloud_outlined,
                        title: t.transportRelayWebrtc,
                        bars: 1,
                        kind: TransportKind.relay,
                        active: false,
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                PulsePanel(
                  radius: 24,
                  padding: const EdgeInsets.all(16),
                  borderColor: AppColors.pulse.withValues(alpha: 0.34),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.shield_outlined,
                        color: AppColors.pulse,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          t.connectionStatusOfflineNotice,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                          ),
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

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.icon,
    required this.title,
    required this.bars,
    required this.kind,
    required this.active,
  });

  final IconData icon;
  final String title;
  final int bars;
  final TransportKind kind;
  final bool active;

  Color _color() => switch (kind) {
        TransportKind.direct => AppColors.transportDirect,
        TransportKind.localNetwork => AppColors.transportLocal,
        TransportKind.relay => AppColors.transportRelay,
        TransportKind.searching => AppColors.transportSearching,
      };

  @override
  Widget build(BuildContext context) {
    final color = _color();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.background.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                active ? color.withValues(alpha: 0.55) : AppColors.outlineSoft,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.18),
                    blurRadius: 20,
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            PulseGlowCircle(
              size: 40,
              color: color,
              fill: color.withValues(alpha: 0.14),
              blur: active ? 16 : 0,
              borderWidth: 1,
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ChannelBars(activeBars: bars, color: color),
          ],
        ),
      ),
    );
  }
}
