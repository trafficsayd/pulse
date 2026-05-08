import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pulse/l10n/app_localizations.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/bottom_nav_shell.dart';
import '../../../core/widgets/connection_avatar.dart';
import '../../../core/widgets/section_header.dart';
import '../../connections/application/connections_controller.dart';
import '../../connections/domain/connection.dart';
import '../../connections/domain/connection_status.dart';

/// "My People" — saved connections list with status, transport hint, and
/// per-row affordances.
///
/// Layout matches the mockup: each row shows the avatar, nickname,
/// localized status line, and a trailing icon depending on the row's
/// state — a play button for the active connection, a small lock icon
/// for archived, and the row itself navigates to the connection's
/// settings on tap.
class PeopleScreen extends ConsumerWidget {
  const PeopleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final state = ref.watch(connectionsControllerProvider);

    return BottomNavShell(
      current: BottomNavTab.people,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t.peopleTitle,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => context.go(Routes.pairing),
                    icon: const Icon(
                      Icons.person_add_alt_1_rounded,
                      color: AppColors.pulse,
                    ),
                    tooltip: t.peopleAdd,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                t.peopleLongPressHint,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: state.connections.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          t.peopleEmpty,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        for (final c in state.connections)
                          _PersonRow(connection: c),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonRow extends ConsumerWidget {
  const _PersonRow({required this.connection});

  final Connection connection;

  String _statusLabel(AppLocalizations t) {
    switch (connection.status) {
      case ConnectionStatus.active:
        return t.peopleStatusActiveWithYou;
      case ConnectionStatus.paused:
        if (connection.permissions.allowSneakIn) {
          return t.peopleStatusPausedSneakIn;
        }
        return t.peopleStatusPaused;
      case ConnectionStatus.archived:
        return t.peopleStatusArchived;
    }
  }

  Color _statusColor() {
    switch (connection.status) {
      case ConnectionStatus.active:
        return AppColors.transportDirect;
      case ConnectionStatus.paused:
        return AppColors.textSecondary;
      case ConnectionStatus.archived:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final muted = connection.status == ConnectionStatus.archived;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () =>
            context.go(Routes.connectionSettingsPath(connection.id)),
        onLongPress: () => _showActions(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Opacity(
                opacity: muted ? 0.5 : 1,
                child: ConnectionAvatar(
                  emoji: connection.emoji,
                  colorIndex: connection.colorIndex,
                  size: 48,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      connection.nickname,
                      style: TextStyle(
                        color: muted
                            ? AppColors.textSecondary
                            : AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _statusLabel(t),
                      style: TextStyle(
                        color: _statusColor(),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _TrailingAction(connection: connection),
            ],
          ),
        ),
      ),
    );
  }

  void _showActions(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              SectionHeader(connection.nickname),
              const SizedBox(height: 4),
              ListTile(
                leading: const Icon(Icons.bolt_rounded, color: AppColors.pulse),
                title: Text(t.peopleMakeActive),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await ref
                      .read(connectionsControllerProvider.notifier)
                      .makeActive(connection.id);
                  if (context.mounted) context.go(Routes.hub);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.notifications_active_rounded,
                  color: AppColors.heart,
                ),
                title: Text(t.peopleSneakIn),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.go(Routes.sneakIn);
                },
              ),
              ListTile(
                leading: const Icon(Icons.tune_rounded),
                title: Text(t.peoplePermissions),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.go(Routes.connectionSettingsPath(connection.id));
                },
              ),
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: Text(t.peopleArchive),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await ref
                      .read(connectionsControllerProvider.notifier)
                      .archive(connection.id);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.danger,
                ),
                title: Text(
                  t.peopleDelete,
                  style: const TextStyle(color: AppColors.danger),
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await ref
                      .read(connectionsControllerProvider.notifier)
                      .delete(connection.id);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _TrailingAction extends ConsumerWidget {
  const _TrailingAction({required this.connection});

  final Connection connection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (connection.status) {
      case ConnectionStatus.active:
        return Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.pulse.withValues(alpha: 0.15),
            border: Border.all(color: AppColors.pulse),
          ),
          child: const Icon(
            Icons.play_arrow_rounded,
            color: AppColors.pulse,
            size: 22,
          ),
        );
      case ConnectionStatus.paused:
        return IconButton(
          onPressed: () => context.go(Routes.sneakIn),
          icon: const Icon(
            Icons.notifications_active_outlined,
            color: AppColors.textSecondary,
          ),
        );
      case ConnectionStatus.archived:
        return const Padding(
          padding: EdgeInsets.only(right: 8),
          child: Icon(
            Icons.lock_outline_rounded,
            color: AppColors.textMuted,
            size: 20,
          ),
        );
    }
  }
}
