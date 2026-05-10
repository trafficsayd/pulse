import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pulse/l10n/app_localizations.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/locale/locale_controller.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/pulse_mockup.dart';

/// First-launch screen: create a new pair (host) or join one (guest).
///
/// Visual layout matches the design mockup: a violet QR card framed by a
/// soft halo, the 6-digit short code in monospace below it, and the
/// language switcher pill (RU / EN) tucked into the top-right corner.
class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  late final String _shortCode = _generateShortCode();
  late final String _qrPayload = 'pulse://pair?code=$_shortCode';

  static String _generateShortCode() {
    final r = math.Random();
    final code = r.nextInt(1000000).toString().padLeft(6, '0');
    return code;
  }

  String get _formattedCode {
    return '${_shortCode.substring(0, 3)} ${_shortCode.substring(3)}';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: PulseBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
            child: Column(
              children: [
                PulseHeader(
                  title: t.pairingTitle,
                  leading: PulseRoundButton(
                    icon: Icons.close_rounded,
                    onTap: () {},
                    subtle: true,
                  ),
                  trailing: const _LanguageSwitcher(),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      children: [
                        const SizedBox(height: 22),
                        Text(
                          t.appTitle.toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 8,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          t.pairingShareCode,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 32),
                        PulseGlowCircle(
                          size: 264,
                          color: AppColors.pulse,
                          fill: AppColors.surface.withValues(alpha: 0.78),
                          borderWidth: 1.2,
                          blur: 54,
                          child: Container(
                            width: 202,
                            height: 202,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.pulse.withValues(alpha: 0.2),
                                  blurRadius: 26,
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(16),
                            child: QrImageView(
                              data: _qrPayload,
                              backgroundColor: Colors.white,
                              eyeStyle: const QrEyeStyle(
                                eyeShape: QrEyeShape.square,
                                color: AppColors.pulseDeep,
                              ),
                              dataModuleStyle: const QrDataModuleStyle(
                                dataModuleShape: QrDataModuleShape.square,
                                color: Color(0xFF181328),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 30),
                        PulsePanel(
                          radius: 28,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 18,
                          ),
                          child: Column(
                            children: [
                              Text(
                                _formattedCode,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 34,
                                  height: 1,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 8,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                t.pairingEnterCode,
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: GradientButton(
                          onPressed: () => _onCreatePair(context),
                          label: t.pairingCreate,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: OutlinedButton(
                          onPressed: () => _onJoinPair(context),
                          child: Text(t.pairingJoin),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onCreatePair(BuildContext context) {
    context.go(Routes.connecting);
  }

  void _onJoinPair(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      isScrollControlled: true,
      builder: (sheetContext) {
        return const _JoinByCodeSheet();
      },
    );
  }
}

class _LanguageSwitcher extends ConsumerWidget {
  const _LanguageSwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(localeControllerProvider);
    final code = current?.languageCode ?? 'ru';
    final isRu = code == 'ru';
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outline),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LangPill(
            label: 'RU',
            active: isRu,
            onTap: () => ref
                .read(localeControllerProvider.notifier)
                .setLocale(const Locale('ru')),
          ),
          _LangPill(
            label: 'EN',
            active: !isRu,
            onTap: () => ref
                .read(localeControllerProvider.notifier)
                .setLocale(const Locale('en')),
          ),
        ],
      ),
    );
  }
}

class _LangPill extends StatelessWidget {
  const _LangPill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.pulse : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

class _JoinByCodeSheet extends StatefulWidget {
  const _JoinByCodeSheet();

  @override
  State<_JoinByCodeSheet> createState() => _JoinByCodeSheetState();
}

class _JoinByCodeSheetState extends State<_JoinByCodeSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.outline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            t.pairingEnterCode,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 28,
              letterSpacing: 8,
              fontFamily: 'monospace',
            ),
            decoration: InputDecoration(
              counterText: '',
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppColors.outline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppColors.pulse),
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: GradientButton(
              label: t.pairingJoin,
              onPressed: () {
                Navigator.of(context).pop();
                context.go(Routes.connecting);
              },
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.pairingCancel),
          ),
        ],
      ),
    );
  }
}
