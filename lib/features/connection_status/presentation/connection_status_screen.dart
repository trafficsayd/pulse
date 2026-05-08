import 'package:flutter/material.dart';
import 'package:pulse/l10n/app_localizations.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/channel_bars.dart';
import '../../../core/widgets/section_header.dart';
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
      appBar: PulseAppBar(title: t.connectionStatusTitle),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              const SizedBox(height: 8),
              const SectionHeader('TRANSPORT'),
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
              const Spacer(),
              GhostBanner(
                icon: Icons.shield_outlined,
                text: t.connectionStatusOfflineNotice,
              ),
              const SizedBox(height: 24),
            ],
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
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? color.withValues(alpha: 0.5) : AppColors.outlineSoft,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.16),
                border: Border.all(color: color),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
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
