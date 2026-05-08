import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../connections/application/connections_controller.dart';
import '../../connections/domain/connection.dart';
import '../../connections/domain/permission_flags.dart';

/// Bottom sheet that lets the user toggle the per-connection permission flags.
class PermissionsSheet extends ConsumerStatefulWidget {
  const PermissionsSheet({required this.connection, super.key});

  final Connection connection;

  @override
  ConsumerState<PermissionsSheet> createState() => _PermissionsSheetState();
}

class _PermissionsSheetState extends ConsumerState<PermissionsSheet> {
  late PermissionFlags _draft = widget.connection.permissions;

  Future<void> _commit() async {
    await ref
        .read(connectionsControllerProvider.notifier)
        .updatePermissions(widget.connection.id, _draft);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 16, left: 8),
              child: Text(
                t.permissionsTitle(widget.connection.nickname),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SwitchListTile.adaptive(
              value: _draft.allowFullSessions,
              title: Text(t.permissionsAllowSessions),
              onChanged: (v) => setState(() {
                _draft = _draft.copyWith(allowFullSessions: v);
              }),
            ),
            SwitchListTile.adaptive(
              value: _draft.allowSneakIn,
              title: Text(t.permissionsAllowSneakIn),
              onChanged: (v) => setState(() {
                _draft = _draft.copyWith(allowSneakIn: v);
              }),
            ),
            SwitchListTile.adaptive(
              value: _draft.confirmFirstSneakIn,
              title: Text(t.permissionsConfirmFirst),
              onChanged: (v) => setState(() {
                _draft = _draft.copyWith(confirmFirstSneakIn: v);
              }),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _commit,
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }
}
