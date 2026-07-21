import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';

import '../../../core/locale/locale_controller.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/pulse_mockup.dart';

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
  void initState() {
    super.initState();
    _checkPermissions();
  }

  // Real permission status map: true = granted.
  final Map<Permission, bool> _permStatus = {};

  Future<void> _checkPermissions() async {
    final results = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.microphone,
    ].request();
    final hasNearbyWifi = await Permission.nearbyWifiDevices.isGranted;
    if (mounted) {
      setState(() {
        _permStatus
          ..[Permission.bluetoothScan] =
              results[Permission.bluetoothScan] == PermissionStatus.granted
          ..[Permission.bluetoothConnect] =
              results[Permission.bluetoothConnect] == PermissionStatus.granted
          ..[Permission.microphone] =
              results[Permission.microphone] == PermissionStatus.granted
          ..[Permission.nearbyWifiDevices] = hasNearbyWifi;
      });
    }
  }

  bool _isGranted(Permission p) => _permStatus[p] ?? false;

  Future<void> _openSupportEmail(AppLocalizations t) async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@pulse-app.app',
      query: 'subject=Pulse support',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showAboutDialog(BuildContext context, AppLocalizations t) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text(
          t.appTitle,
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.subscriptionTagline,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            Text(
              t.settingsVersion('0.1.0'),
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.hubExit),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final locale = ref.watch(localeControllerProvider);
    final code = locale?.languageCode ?? 'ru';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: PulseBackdrop(
        child: SafeArea(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
            children: [
              PulseHeader(title: t.settingsTitle),
              const SizedBox(height: 16),
              _SectionCard(
                title: t.settingsLanguageSection,
                child: _LanguagePicker(currentCode: code),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: t.settingsNotifications,
                child: _SwitchTile(
                  icon: Icons.notifications_active_rounded,
                  label: t.settingsNotifications,
                  value: _notifications,
                  onChanged: (v) => setState(() => _notifications = v),
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: t.settingsPermissions,
                child: Column(
                  children: [
                    _NavTile(
                      icon: Icons.bluetooth_rounded,
                      label: t.settingsPermissionBluetooth,
                      trailing: _isGranted(Permission.bluetoothScan)
                          ? t.settingsPermissionGranted
                          : '—',
                      trailingColor: _isGranted(Permission.bluetoothScan)
                          ? AppColors.transportDirect
                          : AppColors.textMuted,
                      onTap: _checkPermissions,
                    ),
                    _NavTile(
                      icon: Icons.wifi_rounded,
                      label: t.settingsPermissionWifi,
                      trailing: _isGranted(Permission.nearbyWifiDevices)
                          ? t.settingsPermissionGranted
                          : '—',
                      trailingColor: _isGranted(Permission.nearbyWifiDevices)
                          ? AppColors.transportDirect
                          : AppColors.textMuted,
                      onTap: _checkPermissions,
                    ),
                    _NavTile(
                      icon: Icons.mic_rounded,
                      label: t.settingsPermissionMicrophone,
                      trailing: _isGranted(Permission.microphone)
                          ? t.settingsPermissionGranted
                          : '—',
                      trailingColor: _isGranted(Permission.microphone)
                          ? AppColors.transportDirect
                          : AppColors.textMuted,
                      onTap: _checkPermissions,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: t.settingsAbout,
                child: Column(
                  children: [
                    _NavTile(
                      icon: Icons.science_outlined,
                      label: t.settingsDiagnostics,
                      subtitle: t.settingsDiagnosticsHint,
                      onTap: () => context.go(Routes.diagnostics),
                    ),
                    _NavTile(
                      icon: Icons.info_outline_rounded,
                      label: t.settingsAbout,
                      onTap: () => _showAboutDialog(context, t),
                    ),
                    _NavTile(
                      icon: Icons.help_outline_rounded,
                      label: t.settingsSupport,
                      subtitle: t.settingsSupportEmail,
                      onTap: () => _openSupportEmail(t),
                    ),
                    _NavTile(
                      icon: Icons.tag_rounded,
                      label: t.settingsVersion('0.1.0'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: t.settingsCrashReportsSection,
                child: _SwitchTile(
                  icon: Icons.bug_report_outlined,
                  label: t.settingsCrashReports,
                  subtitle: t.settingsCrashReportsHint,
                  value: _crashReports,
                  onChanged: (v) => setState(() => _crashReports = v),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PulsePanel(
      radius: 28,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
              ),
            ),
          ),
          child,
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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.38),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.background.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.outlineSoft),
        ),
        child: SwitchListTile.adaptive(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.pulse,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          secondary: Icon(icon, color: AppColors.textSecondary),
          title:
              Text(label, style: const TextStyle(color: AppColors.textPrimary)),
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
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final String? trailing;
  final Color? trailingColor;
  final VoidCallback? onTap;

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
        child: ListTile(
          onTap: onTap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          leading: Icon(icon, color: AppColors.textSecondary),
          title:
              Text(label, style: const TextStyle(color: AppColors.textPrimary)),
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
