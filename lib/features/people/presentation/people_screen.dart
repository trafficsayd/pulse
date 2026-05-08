import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../connections/application/connections_controller.dart';
import '../../connections/domain/connection.dart';
import '../../connections/domain/connection_status.dart';
import 'permissions_sheet.dart';

/// "My People" — list of saved connections with status, transport, and per
/// connection contextual actions (make active, sneak in, permissions,
/// archive, delete).
class PeopleScreen extends ConsumerWidget {
  const PeopleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final state = ref.watch(connectionsControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(t.peopleTitle)),
      body: state.connections.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  t.peopleEmpty,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 12),
              itemCount: state.connections.length,
              separatorBuilder: (_, __) => const Divider(
                height: 1,
                color: AppColors.outline,
              ),
              itemBuilder: (context, i) {
                final c = state.connections[i];
                return _PersonRow(connection: c);
              },
            ),
    );
  }
}

class _PersonRow extends ConsumerWidget {
  const _PersonRow({required this.connection});

  final Connection connection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final color = AppColors.avatarPalette[
        connection.colorIndex % AppColors.avatarPalette.length];

    return ListTile(
      onTap: () => _showActions(context, ref),
      onLongPress: () => _showActions(context, ref),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 1.4),
        ),
        alignment: Alignment.center,
        child: Text(connection.emoji, style: const TextStyle(fontSize: 18)),
      ),
      title: Text(connection.nickname),
      subtitle: Text(_statusLabel(t, connection.status)),
      trailing: connection.status == ConnectionStatus.active
          ? const Icon(Icons.bolt_rounded, color: AppColors.pulse)
          : null,
    );
  }

  String _statusLabel(AppLocalizations t, ConnectionStatus status) =>
      switch (status) {
        ConnectionStatus.active => t.peopleStatusActive,
        ConnectionStatus.paused => t.peopleStatusPaused,
        ConnectionStatus.archived => t.peopleStatusArchived,
      };

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
              ListTile(
                leading: const Icon(Icons.bolt_rounded),
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
                leading: const Icon(Icons.notifications_active_outlined),
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
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: AppColors.surfaceElevated,
                    builder: (_) =>
                        PermissionsSheet(connection: connection),
                  );
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
                leading: const Icon(Icons.delete_outline_rounded,
                    color: Color(0xFFFF6B6B)),
                title: Text(t.peopleDelete,
                    style: const TextStyle(color: Color(0xFFFF6B6B))),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await ref
                      .read(connectionsControllerProvider.notifier)
                      .delete(connection.id);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
