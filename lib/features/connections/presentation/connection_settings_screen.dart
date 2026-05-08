import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pulse/l10n/app_localizations.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/connection_avatar.dart';
import '../../../core/widgets/section_header.dart';
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
        appBar: PulseAppBar(title: t.connectionSettingsTitle),
        body: Center(
          child: Text(
            t.errorGeneric,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: PulseAppBar(title: t.connectionSettingsTitle),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          Center(
            child: ConnectionAvatar(
              emoji: connection.emoji,
              colorIndex: connection.colorIndex,
              size: 96,
              fontSize: 56,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              connection.nickname,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SectionHeader(t.permissionsTitle),
          _PermissionTile(
            title: t.permissionsAllowSessions,
            value: connection.permissions.allowFullSessions,
            onChanged: (v) {
              ref
                  .read(connectionsControllerProvider.notifier)
                  .updatePermissions(
                    connection.id,
                    connection.permissions.copyWith(allowFullSessions: v),
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
          SectionHeader(t.connectionStatusSection),
          _StatusSegment(connection: connection),
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.danger),
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
          ),
          const SizedBox(height: 32),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
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
          activeColor: AppColors.pulse,
          onChanged: onChanged,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
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
                      color: selected == v
                          ? AppColors.pulse
                          : Colors.transparent,
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
