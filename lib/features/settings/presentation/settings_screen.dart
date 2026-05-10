import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
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
            const SizedBox(height: 24),
            Center(
              child: Text(
                t.settingsVersion('0.5.0'),
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
      applicationVersion: '0.5.0',
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
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textSecondary),
      title: Text(label, style: const TextStyle(color: AppColors.textPrimary)),
      trailing:
          const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
      onTap: onTap,
    );
  }
}
