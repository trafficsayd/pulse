import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/secure_key_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../connections/application/connections_controller.dart';
import '../application/settings_controller.dart';

/// Settings is intentionally a single column of toggles + chevrons that
/// mirrors the mockup. Language, notifications and crash-reports rows are
/// wired through [SettingsController]; the rest funnel into placeholder
/// dialogs.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    // Treat "follow system" as English in the UI for now — the segmented
    // toggle intentionally collapses null → en so the user always sees a
    // selection, matching the design mockup.
    final activeCode = settings.locale?.languageCode ?? 'en';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(t.settingsTitle),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            _SectionLabel(label: t.settingsLanguage),
            _SettingsCard(
              children: [
                _LanguageRow(
                  label: t.settingsLanguageRussian,
                  active: activeCode == 'ru',
                  onTap: () => controller.setLocale(const Locale('ru')),
                ),
                const _CardDivider(),
                _LanguageRow(
                  label: t.settingsLanguageEnglish,
                  active: activeCode == 'en',
                  onTap: () => controller.setLocale(const Locale('en')),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SettingsCard(
              children: [
                _ToggleRow(
                  icon: Icons.notifications_rounded,
                  label: t.settingsNotifications,
                  value: settings.notifications,
                  onChanged: controller.setNotifications,
                ),
                const _CardDivider(),
                _ChevronRow(
                  icon: Icons.security_rounded,
                  label: t.settingsPermissions,
                  onTap: () => _showPlaceholder(context, t.settingsPermissions),
                ),
                const _CardDivider(),
                _ChevronRow(
                  icon: Icons.info_outline_rounded,
                  label: t.settingsAbout,
                  onTap: () => _showAbout(context, t),
                ),
                const _CardDivider(),
                _ChevronRow(
                  icon: Icons.support_agent_rounded,
                  label: t.settingsSupport,
                  onTap: () => _showPlaceholder(context, t.settingsSupport),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SettingsCard(
              children: [
                _ToggleRow(
                  icon: Icons.bug_report_outlined,
                  label: t.settingsCrashReports,
                  hint: t.settingsCrashReportsHint,
                  value: settings.crashReports,
                  onChanged: controller.setCrashReports,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SettingsCard(
              children: [
                _ChevronRow(
                  icon: Icons.delete_forever_rounded,
                  label: t.settingsWipeData,
                  destructive: true,
                  onTap: () => _confirmWipe(context, ref, t),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                t.settingsVersion('0.7.0'),
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showPlaceholder(BuildContext context, String title) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text(title),
        content: const Text(
          '...',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context, AppLocalizations t) {
    showAboutDialog(
      context: context,
      applicationName: 'Pulse',
      applicationVersion: '0.7.0',
      applicationLegalese: '© 2025',
      children: [
        const SizedBox(height: 12),
        Text(
          t.settingsAboutBlurb,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ],
    );
  }

  /// Drops every persisted byte: secure-storage entries, connections, key
  /// material, settings. The router stays mounted, so once the wipe finishes
  /// the user just sees an empty pristine state.
  Future<void> _confirmWipe(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations t,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text(t.settingsWipeData),
        content: Text(
          t.settingsWipeDataConfirm,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.pairingCancel),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.settingsWipeDataConfirmCta),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Wipe order: connections + key manager first (per-connection entries),
    // then nuke the secure store wholesale to also blow away the
    // settings.v1 / subscription / sketch-quota / sneak-in usage rows.
    await ref.read(connectionsControllerProvider.notifier).wipeAll();
    await _wipeSecureStore(ref.read(secureKeyStoreProvider));

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.settingsWipeDataDone)),
    );
  }

  Future<void> _wipeSecureStore(SecureKeyStore store) => store.deleteAll();
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 12,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(children: children),
    );
  }
}

class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 1,
      color: AppColors.outline,
      indent: 16,
      endIndent: 16,
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading:
          const Icon(Icons.language_rounded, color: AppColors.textSecondary),
      title: Text(label, style: const TextStyle(color: AppColors.textPrimary)),
      trailing: active
          ? const Icon(Icons.check_rounded, color: AppColors.pulse)
          : null,
      onTap: onTap,
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
  });

  final IconData icon;
  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: Icon(icon, color: AppColors.textSecondary),
      activeColor: AppColors.pulse,
      title: Text(label, style: const TextStyle(color: AppColors.textPrimary)),
      subtitle: hint == null
          ? null
          : Text(
              hint!,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
              ),
            ),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _ChevronRow extends StatelessWidget {
  const _ChevronRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final fg = destructive ? Colors.redAccent : AppColors.textPrimary;
    return ListTile(
      leading: Icon(icon, color: destructive ? Colors.redAccent : AppColors.textSecondary),
      title: Text(label, style: TextStyle(color: fg)),
      trailing:
          const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
      onTap: onTap,
    );
  }
}
