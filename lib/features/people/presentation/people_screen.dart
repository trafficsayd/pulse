import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/pulse_bottom_nav.dart';
import '../../connections/application/connections_controller.dart';
import '../../connections/domain/connection.dart';
import '../../connections/domain/connection_status.dart';
import 'permissions_sheet.dart';

/// "My People" — saved connections rendered as cards in the new violet
/// theme: gradient avatars, status pills, a play button to enter a session
/// fast, plus the bottom nav so the user can swap tabs without backing out.
class PeopleScreen extends ConsumerWidget {
  const PeopleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final state = ref.watch(connectionsControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(t.peopleTitle),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: state.connections.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            t.peopleEmpty,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: AppColors.textSecondary),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        itemCount: state.connections.length,
                        itemBuilder: (context, i) {
                          final c = state.connections[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: _PersonCard(connection: c),
                          );
                        },
                      ),
              ),
              const PulseBottomNav(active: PulseNavTab.people),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonCard extends ConsumerWidget {
  const _PersonCard({required this.connection});

  final Connection connection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final color = AppColors.avatarPalette[
        connection.colorIndex % AppColors.avatarPalette.length];

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.outline),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showActions(context, ref),
        onLongPress: () => _showActions(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              _Avatar(color: color, emoji: connection.emoji),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      connection.nickname,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _StatusPill(status: connection.status),
                  ],
                ),
              ),
              _PlayButton(
                enabled: connection.status != ConnectionStatus.archived,
                onTap: () async {
                  await ref
                      .read(connectionsControllerProvider.notifier)
                      .makeActive(connection.id);
                  if (context.mounted) context.go(Routes.hub);
                },
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.more_horiz_rounded),
                color: AppColors.textSecondary,
                tooltip: t.peoplePermissions,
                onPressed: () => _showActions(context, ref),
              ),
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
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
                    color: AppColors.danger),
                title: Text(t.peopleDelete,
                    style: const TextStyle(color: AppColors.danger)),
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

class _Avatar extends StatelessWidget {
  const _Avatar({required this.color, required this.emoji});
  final Color color;
  final String emoji;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.55), color],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Text(emoji, style: const TextStyle(fontSize: 22)),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final (color, label) = switch (status) {
      ConnectionStatus.active => (AppColors.statusActive, t.peopleStatusActive),
      ConnectionStatus.paused => (AppColors.statusPaused, t.peopleStatusPaused),
      ConnectionStatus.archived =>
        (AppColors.statusArchived, t.peopleStatusArchived),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.heroGradient,
            boxShadow: [
              BoxShadow(color: AppColors.pulseHalo, blurRadius: 16),
            ],
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.play_arrow_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }
}
