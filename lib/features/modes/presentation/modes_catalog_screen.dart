import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/pulse_mockup.dart';
import '../../../l10n/app_localizations.dart';
import '../../capabilities/application/capability_providers.dart';
import '../../capabilities/domain/device_capability.dart';
import '../../subscription/application/subscription_controller.dart';
import '../application/mode_registry.dart';
import '../domain/pulse_mode.dart';

/// "Modes" catalog — full grid of every shipped mode, split into starter
/// (trial) and paid sections. Tapping a starter mode launches it, tapping
/// a locked paid mode bounces to the subscription paywall, and tapping a
/// mode whose hardware requirements aren't satisfied shows a snackbar
/// with the specific missing capability.
class ModesCatalogScreen extends ConsumerWidget {
  const ModesCatalogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final starters = kStarterModes;
    final paid = kPaidModes;
    final unlockedCount = starters.length;
    final capsAsync = ref.watch(deviceCapabilitiesProvider);
    final caps = capsAsync.asData?.value ?? const DeviceCapabilities.none();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: PulseBackdrop(
        child: SafeArea(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
            children: [
              PulseHeader(title: t.modesCatalogTitle),
              const SizedBox(height: 16),
              _CatalogSection(
                title:
                    t.modesCatalogTrialSection(unlockedCount, starters.length),
                modes: starters,
                capabilities: caps,
                capabilitiesReady: capsAsync.hasValue || capsAsync.hasError,
              ),
              const SizedBox(height: 12),
              _CatalogSection(
                title: t.modesCatalogPaidSection,
                modes: paid,
                capabilities: caps,
                capabilitiesReady: capsAsync.hasValue || capsAsync.hasError,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogSection extends StatelessWidget {
  const _CatalogSection({
    required this.title,
    required this.modes,
    required this.capabilities,
    required this.capabilitiesReady,
  });

  final String title;
  final List<PulseModeDescriptor> modes;
  final DeviceCapabilities capabilities;
  final bool capabilitiesReady;

  @override
  Widget build(BuildContext context) {
    return PulsePanel(
      radius: 28,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ),
          _Grid(
            modes: modes,
            capabilities: capabilities,
            capabilitiesReady: capabilitiesReady,
          ),
        ],
      ),
    );
  }
}

class _Grid extends ConsumerWidget {
  const _Grid({
    required this.modes,
    required this.capabilities,
    required this.capabilitiesReady,
  });

  final List<PulseModeDescriptor> modes;
  final DeviceCapabilities capabilities;
  final bool capabilitiesReady;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      crossAxisCount: 3,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 0.88,
      children: [
        for (final m in modes)
          _ModeTile(
            mode: m,
            capabilities: capabilities,
            capabilitiesReady: capabilitiesReady,
          ),
      ],
    );
  }
}

class _ModeTile extends ConsumerWidget {
  const _ModeTile({
    required this.mode,
    required this.capabilities,
    required this.capabilitiesReady,
  });

  final PulseModeDescriptor mode;
  final DeviceCapabilities capabilities;
  final bool capabilitiesReady;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unlocked = ref
        .read(subscriptionControllerProvider.notifier)
        .isModeUnlocked(mode.id);
    final missing = capabilitiesReady
        ? capabilities.missing(mode.requiredCapabilities)
        : const <DeviceCapability>{};
    final supported = missing.isEmpty;
    final tappable = unlocked && supported;
    final color = tappable ? mode.tint : AppColors.textMuted;
    return Semantics(
      button: true,
      enabled: tappable,
      label: _label(context, mode),
      child: GestureDetector(
        onTap: () => _onTap(context, missing: missing, unlocked: unlocked),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.30),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: tappable
                  ? color.withValues(alpha: 0.44)
                  : AppColors.outlineSoft,
            ),
            boxShadow: tappable
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.16),
                      blurRadius: 18,
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.all(8),
          child: Stack(
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PulseGlowCircle(
                    size: 58,
                    color: color,
                    fill: color.withValues(alpha: tappable ? 0.15 : 0.08),
                    blur: tappable ? 18 : 0,
                    borderWidth: 1.2,
                    child: Text(
                      mode.glyph,
                      style: const TextStyle(fontSize: 25),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _label(context, mode),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tappable
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (!supported && unlocked) ...[
                    const SizedBox(height: 2),
                    Text(
                      AppLocalizations.of(context)!.modesUnavailableCaption,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
              if (!unlocked)
                const Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(
                    Icons.lock_rounded,
                    size: 14,
                    color: AppColors.textMuted,
                  ),
                )
              else if (!supported)
                const Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(
                    Icons.do_not_disturb_on_outlined,
                    size: 14,
                    color: AppColors.textMuted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _onTap(
    BuildContext context, {
    required Set<DeviceCapability> missing,
    required bool unlocked,
  }) {
    if (!unlocked) {
      context.go(Routes.subscription);
      return;
    }
    if (missing.isNotEmpty) {
      final t = AppLocalizations.of(context)!;
      final what = capabilityLabel(t, missing.first);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(t.modesUnavailableReason(what)),
          ),
        );
      return;
    }
    context.push(Routes.modePath(mode.id.name));
  }

  String _label(BuildContext context, PulseModeDescriptor mode) {
    final t = AppLocalizations.of(context)!;
    return localizedModeTitle(mode, t);
  }
}

/// Maps a [DeviceCapability] to its short localized label, reusing the
/// strings the diagnostics screen already ships so the catalog snackbar
/// stays in sync with the diagnostics list ("Microphone" / "Микрофон").
String capabilityLabel(AppLocalizations t, DeviceCapability cap) {
  switch (cap) {
    case DeviceCapability.microphone:
      return t.diagnosticsCapabilityMicrophone;
    case DeviceCapability.accelerometer:
      return t.diagnosticsCapabilityAccelerometer;
    case DeviceCapability.vibration:
      return t.diagnosticsCapabilityVibration;
    case DeviceCapability.vibrationAmplitude:
      return t.diagnosticsCapabilityVibrationAmplitude;
    case DeviceCapability.flashlight:
      return t.diagnosticsCapabilityFlashlight;
    case DeviceCapability.camera:
      return t.diagnosticsCapabilityCamera;
    case DeviceCapability.bluetoothLe:
      return t.diagnosticsCapabilityBluetoothLe;
    case DeviceCapability.localNetwork:
      return t.diagnosticsCapabilityLocalNetwork;
  }
}
