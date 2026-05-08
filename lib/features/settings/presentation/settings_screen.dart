import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pulse/l10n/app_localizations.dart';

import '../../../core/locale/locale_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/section_header.dart';

/// App-wide settings — language, notifications, permissions, about,
/// support, crash reports.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _notifications = true;
  bool _crashReports = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final locale = ref.watch(localeControllerProvider);
    final code = locale?.languageCode ?? 'ru';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: PulseAppBar(title: t.settingsTitle),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SectionHeader(t.settingsLanguageSection),
          _LanguagePicker(currentCode: code),
          SectionHeader(t.settingsNotifications),
          _SwitchTile(
            icon: Icons.notifications_active_rounded,
            label: t.settingsNotifications,
            value: _notifications,
            onChanged: (v) => setState(() => _notifications = v),
          ),
          SectionHeader(t.settingsPermissions),
          _NavTile(
            icon: Icons.bluetooth_rounded,
            label: 'Bluetooth',
            trailing: 'OK',
            trailingColor: AppColors.transportDirect,
          ),
          _NavTile(
            icon: Icons.wifi_rounded,
            label: 'Wi-Fi',
            trailing: 'OK',
            trailingColor: AppColors.transportDirect,
          ),
          _NavTile(
            icon: Icons.mic_rounded,
            label: t.settingsPermissions,
            trailing: 'OK',
            trailingColor: AppColors.transportDirect,
          ),
          SectionHeader(t.settingsAbout),
          _NavTile(
            icon: Icons.info_outline_rounded,
            label: t.settingsAbout,
          ),
          _NavTile(
            icon: Icons.help_outline_rounded,
            label: t.settingsSupport,
            subtitle: 'support@pulse.app',
          ),
          _NavTile(
            icon: Icons.tag_rounded,
            label: t.settingsVersion('0.1.0'),
          ),
          SectionHeader('Crash reports'),
          _SwitchTile(
            icon: Icons.bug_report_outlined,
            label: t.settingsCrashReports,
            subtitle: t.settingsCrashReportsHint,
            value: _crashReports,
            onChanged: (v) => setState(() => _crashReports = v),
          ),
        ],
      ),
    );
  }
}

class _LanguagePicker extends ConsumerWidget {
  const _LanguagePicker({required this.currentCode});

  final String currentCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
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
            _LangCell(
              label: t.languageRu,
              code: 'ru',
              currentCode: currentCode,
              onTap: () => ref
                  .read(localeControllerProvider.notifier)
                  .setLocale(const Locale('ru')),
            ),
            _LangCell(
              label: t.languageEn,
              code: 'en',
              currentCode: currentCode,
              onTap: () => ref
                  .read(localeControllerProvider.notifier)
                  .setLocale(const Locale('en')),
            ),
          ],
        ),
      ),
    );
  }
}

class _LangCell extends StatelessWidget {
  const _LangCell({
    required this.label,
    required this.code,
    required this.currentCode,
    required this.onTap,
  });

  final String label;
  final String code;
  final String currentCode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selected = code == currentCode;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.pulse : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.outlineSoft),
        ),
        child: SwitchListTile.adaptive(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.pulse,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          secondary: Icon(icon, color: AppColors.textSecondary),
          title: Text(label,
              style: const TextStyle(color: AppColors.textPrimary)),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle!,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.label,
    this.subtitle,
    this.trailing,
    this.trailingColor,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final String? trailing;
  final Color? trailingColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.outlineSoft),
        ),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          leading: Icon(icon, color: AppColors.textSecondary),
          title: Text(label,
              style: const TextStyle(color: AppColors.textPrimary)),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle!,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
          trailing: trailing == null
              ? null
              : Text(
                  trailing!,
                  style: TextStyle(
                    color: trailingColor ?? AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
        ),
      ),
    );
  }
}
