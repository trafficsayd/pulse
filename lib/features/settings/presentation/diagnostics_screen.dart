import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/pulse_mockup.dart';
import '../../../l10n/app_localizations.dart';
import '../../capabilities/application/capability_providers.dart';
import '../../capabilities/domain/device_capability.dart';
import '../../modes/application/mode_registry.dart';
import '../../modes/domain/pulse_mode.dart';

/// "What works on this phone?" — the single screen a user opens when a
/// mode tile is greyed out and they want to know *why*.
///
/// Composed of two lists:
///   1. **Hardware**: every [DeviceCapability], with a green dot if
///      detected on this device, red if not.
///   2. **Modes**: every mode, "Ready" or "Missing: X, Y" so the user
///      can map "greyed-out tile" → "your iPhone has no flashlight, so
///      Thunder won't run".
class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final caps = ref.watch(deviceCapabilitiesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: PulseBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              PulseHeader(
                title: t.diagnosticsTitle,
                onBack: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: caps.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, __) => Center(child: Text(t.errorGeneric)),
                  data: (capabilities) => ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    children: [
                      _SectionHeader(label: t.diagnosticsHardwareSection),
                      const SizedBox(height: 8),
                      ...DeviceCapability.values.map(
                        (c) => _CapabilityRow(
                          label: _labelFor(t, c),
                          available: capabilities.has(c),
                          statusOk: t.diagnosticsStatusOk,
                          statusMissing: t.diagnosticsStatusMissing,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _SectionHeader(label: t.diagnosticsModesSection),
                      const SizedBox(height: 8),
                      ...kAllModes.map(
                        (mode) => _ModeRow(
                          mode: mode,
                          missing:
                              capabilities.missing(mode.requiredCapabilities),
                          t: t,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _labelFor(AppLocalizations t, DeviceCapability cap) {
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
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({
    required this.label,
    required this.available,
    required this.statusOk,
    required this.statusMissing,
  });

  final String label;
  final bool available;
  final String statusOk;
  final String statusMissing;

  @override
  Widget build(BuildContext context) {
    final color = available ? AppColors.pulse : AppColors.textMuted;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineSoft),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
              ),
            ),
          ),
          Text(
            available ? statusOk : statusMissing,
            style: TextStyle(color: color, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.mode,
    required this.missing,
    required this.t,
  });

  final PulseModeDescriptor mode;
  final Set<DeviceCapability> missing;
  final AppLocalizations t;

  @override
  Widget build(BuildContext context) {
    final ok = missing.isEmpty;
    final statusColor = ok ? AppColors.pulse : AppColors.textMuted;
    final missingLabels = missing.map(_capLabel).join(', ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineSoft),
      ),
      child: Row(
        children: [
          Text(mode.glyph, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _modeTitle(t, mode.titleKey),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  ok
                      ? t.diagnosticsModeAvailable
                      : t.diagnosticsModeMissing(missingLabels),
                  style: TextStyle(color: statusColor, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _capLabel(DeviceCapability c) {
    switch (c) {
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

  static String _modeTitle(AppLocalizations t, String key) {
    // Hard-coded fallback: the mode-list is generated, but mode titles
    // live behind dynamic ARB keys, so we look them up by name.
    switch (key) {
      case 'modeTapTap':
        return t.modeTapTap;
      case 'modeHalfHeart':
        return t.modeHalfHeart;
      case 'modeCandle':
        return t.modeCandle;
      case 'modeWhisper':
        return t.modeWhisper;
      case 'modeBell':
        return t.modeBell;
      case 'modeRay':
        return t.modeRay;
      case 'modeConstellation':
        return t.modeConstellation;
      case 'modeGoosebumps':
        return t.modeGoosebumps;
      case 'modeThread':
        return t.modeThread;
      case 'modeThunder':
        return t.modeThunder;
      case 'modeFireworks':
        return t.modeFireworks;
      case 'modeBalance':
        return t.modeBalance;
      case 'modeSandbox':
        return t.modeSandbox;
      case 'modeBreath':
        return t.modeBreath;
      case 'modeSync':
        return t.modeSync;
      default:
        return key;
    }
  }
}
