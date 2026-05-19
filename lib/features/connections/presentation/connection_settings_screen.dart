import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../l10n/app_localizations.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/connection_avatar.dart';
import '../../../core/widgets/pulse_mockup.dart';
import '../application/connections_controller.dart';
import '../domain/connection.dart';
import '../domain/connection_status.dart';

/// Per-connection settings screen.
///
/// Lets the user view a connection's avatar/nickname, flip the
/// per-connection permission flags (full sessions, sneak in, confirm-first),
/// pick a status (active / paused / archived), and permanently delete the
/// connection.
class ConnectionSettingsScreen extends ConsumerWidget {
  const ConnectionSettingsScreen({required this.connectionId, super.key});

  final String connectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final state = ref.watch(connectionsControllerProvider);
    final connection = _findById(state.connections, connectionId);
    if (connection == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: PulseBackdrop(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
              child: Column(
                children: [
                  PulseHeader(
                    title: t.connectionSettingsTitle,
                    leading: PulseRoundButton(
                      icon: Icons.arrow_back_rounded,
                      onTap: () => context.go(Routes.people),
                      subtle: true,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    t.errorGeneric,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: PulseBackdrop(
        child: SafeArea(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
            children: [
              PulseHeader(
                title: t.connectionSettingsTitle,
                leading: PulseRoundButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () => context.go(Routes.people),
                  subtle: true,
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: PulseGlowCircle(
                  size: 132,
                  color: AppColors.pulse,
                  blur: 34,
                  fill: AppColors.surface.withValues(alpha: 0.74),
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
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  connection.nickname,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.25,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              PulsePanel(
                radius: 28,
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PanelTitle(t.permissionsTitle),
                    _PermissionTile(
                      title: t.permissionsAllowSessions,
                      value: connection.permissions.allowFullSessions,
                      onChanged: (v) {
                        ref
                            .read(connectionsControllerProvider.notifier)
                            .updatePermissions(
                              connection.id,
                              connection.permissions
                                  .copyWith(allowFullSessions: v),
                            );
                      },
                    ),
                    _PermissionTile(
                      title: t.permissionsAllowSneakIn,
                      value: connection.permissions.allowSneakIn,
                      onChanged: (v) {
                        ref
                            .read(connectionsControllerProvider.notifier)
                            .updatePermissions(
                              connection.id,
                              connection.permissions.copyWith(allowSneakIn: v),
                            );
                      },
                    ),
                    _PermissionTile(
                      title: t.permissionsConfirmFirst,
                      value: connection.permissions.confirmFirstSneakIn,
                      onChanged: (v) {
                        ref
                            .read(connectionsControllerProvider.notifier)
                            .updatePermissions(
                              connection.id,
                              connection.permissions
                                  .copyWith(confirmFirstSneakIn: v),
                            );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              PulsePanel(
                radius: 28,
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PanelTitle(t.connectionStatusSection),
                    _StatusSegment(connection: connection),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: BorderSide(
                      color: AppColors.danger.withValues(alpha: 0.72),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                  onPressed: () async {
                    await ref
                        .read(connectionsControllerProvider.notifier)
                        .delete(connection.id);
                    if (context.mounted) context.go(Routes.people);
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text(t.peopleDelete),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Connection? _findById(List<Connection> list, String id) {
    for (final c in list) {
      if (c.id == id) return c;
    }
    return null;
  }
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.background.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.outlineSoft),
        ),
        child: SwitchListTile.adaptive(
          value: value,
          title: Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
            ),
          ),
          activeThumbColor: AppColors.pulse,
          onChanged: onChanged,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}

class _StatusSegment extends ConsumerWidget {
  const _StatusSegment({required this.connection});

  final Connection connection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final entries = <(_SegmentValue, String)>[
      (_SegmentValue.active, t.peopleStatusActive),
      (_SegmentValue.paused, t.peopleStatusPaused),
      (_SegmentValue.archived, t.peopleStatusArchived),
    ];
    final selected = switch (connection.status) {
      ConnectionStatus.active => _SegmentValue.active,
      ConnectionStatus.paused => _SegmentValue.paused,
      ConnectionStatus.archived => _SegmentValue.archived,
    };

    return Container(
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outlineSoft),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (final (v, label) in entries)
            Expanded(
              child: GestureDetector(
                onTap: () => _select(ref, v),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected == v ? AppColors.pulse : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected == v
                          ? Colors.white
                          : AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _select(WidgetRef ref, _SegmentValue v) {
    final controller = ref.read(connectionsControllerProvider.notifier);
    switch (v) {
      case _SegmentValue.active:
        controller.makeActive(connection.id);
      case _SegmentValue.paused:
        controller.unarchive(connection.id);
      case _SegmentValue.archived:
        controller.archive(connection.id);
    }
  }
}

enum _SegmentValue { active, paused, archived }
