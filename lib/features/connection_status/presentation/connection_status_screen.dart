import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/connection_avatar.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/pulse_mockup.dart';
import '../../../l10n/app_localizations.dart';
import '../../connections/application/connections_controller.dart';
import '../../connections/domain/connection.dart';
import '../../connections/domain/connection_status.dart';
import '../../session/application/pulse_session.dart';
import '../../session/application/session_provider.dart';
import '../../transport/transport.dart';

/// Current link diagnostics for the active Pulse connection.
///
/// Kept intentionally lightweight: this is the screen behind the transport
/// pill in the hub, so it answers "who am I connected to?" and "which channel
/// is carrying traffic?" without exposing protocol internals.
class ConnectionStatusScreen extends ConsumerWidget {
  const ConnectionStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final connections = ref.watch(connectionsControllerProvider);
    final active = connections.active;
    final session = ref.watch(sessionProvider);
    final transportKind = ref.watch(transportStateProvider).valueOrNull ??
        session.valueOrNull?.currentTransport ??
        TransportKind.searching;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: PulseBackdrop(
        child: SafeArea(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
            children: [
              PulseHeader(
                title: t.connectionStatusTitle,
                leading: PulseRoundButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () => context.go(Routes.hub),
                  subtle: true,
                ),
              ),
              const SizedBox(height: 18),
              if (active == null)
                _EmptyConnection(t: t)
              else
                _ActiveConnectionPanel(
                  connection: active,
                  transportKind: transportKind,
                  session: session,
                  t: t,
                ),
              const SizedBox(height: 12),
              PulsePanel(
                radius: 24,
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(
                      Icons.privacy_tip_outlined,
                      color: AppColors.pulse,
                      size: 20,
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
    );
  }
}

class _EmptyConnection extends StatelessWidget {
  const _EmptyConnection({required this.t});

  final AppLocalizations t;

  @override
  Widget build(BuildContext context) {
    return PulsePanel(
      radius: 28,
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          const PulseGlowCircle(
            size: 96,
            color: AppColors.textMuted,
            blur: 18,
            fill: AppColors.surface,
            child: Icon(
              Icons.link_off_rounded,
              color: AppColors.textMuted,
              size: 36,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            t.hubNoActiveConnection,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t.hubChooseSomeone,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 48,
            child: GradientButton(
              label: t.peopleTitle,
              icon: Icons.people_alt_rounded,
              onPressed: () => context.go(Routes.people),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveConnectionPanel extends StatelessWidget {
  const _ActiveConnectionPanel({
    required this.connection,
    required this.transportKind,
    required this.session,
    required this.t,
  });

  final Connection connection;
  final TransportKind transportKind;
  final AsyncValue<PulseSession?> session;
  final AppLocalizations t;

  @override
  Widget build(BuildContext context) {
    return PulsePanel(
      radius: 30,
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          PulseGlowCircle(
            size: 132,
            color: _transportColor(transportKind),
            blur: 34,
            fill: AppColors.surface.withValues(alpha: 0.72),
            borderWidth: 1,
            child: ConnectionAvatar(
              emoji: connection.emoji,
              colorIndex: connection.colorIndex,
              size: 96,
              fontSize: 56,
              showRing: false,
              glow: true,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            connection.nickname,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 18),
          _StatusLine(
            icon: Icons.person_pin_circle_rounded,
            label: t.connectionStatusSection,
            value: _connectionStatusLabel(connection.status, t),
            color: _connectionStatusColor(connection.status),
          ),
          const SizedBox(height: 10),
          _StatusLine(
            icon: Icons.sensors_rounded,
            label: t.connectionStatusTitle,
            value: _transportLabel(transportKind, t),
            color: _transportColor(transportKind),
          ),
          if (session.hasError) ...[
            const SizedBox(height: 10),
            _StatusLine(
              icon: Icons.error_outline_rounded,
              label: t.errorGeneric,
              value: t.transportSearching,
              color: AppColors.danger,
            ),
          ],
        ],
      ),
    );
  }

  static String _connectionStatusLabel(
    ConnectionStatus status,
    AppLocalizations t,
  ) {
    return switch (status) {
      ConnectionStatus.active => t.peopleStatusActiveWithYou,
      ConnectionStatus.paused => t.peopleStatusPaused,
      ConnectionStatus.archived => t.peopleStatusArchived,
    };
  }

  static Color _connectionStatusColor(ConnectionStatus status) {
    return switch (status) {
      ConnectionStatus.active => AppColors.transportDirect,
      ConnectionStatus.paused => AppColors.textSecondary,
      ConnectionStatus.archived => AppColors.textMuted,
    };
  }

  static String _transportLabel(TransportKind kind, AppLocalizations t) {
    return switch (kind) {
      TransportKind.direct => t.transportDirectBle,
      TransportKind.localNetwork => t.transportLocalWifi,
      TransportKind.relay => t.transportRelayWebrtc,
      TransportKind.searching => t.transportSearching,
    };
  }

  static Color _transportColor(TransportKind kind) {
    return switch (kind) {
      TransportKind.direct => AppColors.transportDirect,
      TransportKind.localNetwork => AppColors.transportLocal,
      TransportKind.relay => AppColors.transportRelay,
      TransportKind.searching => AppColors.transportSearching,
    };
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.outlineSoft),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
