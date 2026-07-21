import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/locale/locale_controller.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/pulse_mockup.dart';
import '../../../l10n/app_localizations.dart';
import '../application/pairing_controller.dart';

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
  @override
  void initState() {
    super.initState();
    // Kick the handshake off the moment we land on this screen so that
    // by the time the user finishes reading "share this code" the SAS
    // has already been derived from the real ECDH secret.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pairingControllerProvider.notifier).startHostHandshake();
    });
  }

  String _formatCode(String code) {
    if (code.length != 6) return code;
    return '${code.substring(0, 3)} ${code.substring(3)}';
  }

  String _qrPayload(PairingState pairing) {
    final pub = pairing.localPublicKeyBase64;
    final code = pairing.pairingCode;
    if (pub == null) {
      // Generation in flight — fall back to a placeholder URI so the QR
      // widget doesn't crash on an empty string.
      return 'pulse://pair?pending=1';
    }
    return 'pulse://pair?v=1&code=${code ?? ''}&pk=$pub';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final pairing = ref.watch(pairingControllerProvider);
    final displayCode = pairing.sasCode ?? pairing.pairingCode ?? '······';

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
                    onTap: () => context.go(Routes.people),
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
                              data: _qrPayload(pairing),
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
                                _formatCode(displayCode),
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
                                pairing.hasFailed
                                    ? t.pairingError
                                    : pairing.hasShortCode
                                        ? t.connectingSecuredLink
                                        : pairing.hasPairingCode
                                            ? t.pairingEnterCode
                                            : t.pairingDerivingCode,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: pairing.hasFailed
                                      ? AppColors.danger
                                      : AppColors.textMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (pairing.hasFailed) ...[
                                const SizedBox(height: 12),
                                GradientButton(
                                  label: t.pairingRetry,
                                  onPressed: () => ref
                                      .read(pairingControllerProvider.notifier)
                                      .startHostHandshake(),
                                ),
                              ],
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
                          onPressed: pairing.isReadyToConfirm
                              ? () => _onCreatePair(context)
                              : null,
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

class _LanguageSwitcher extends ConsumerStatefulWidget {
  const _LanguageSwitcher();

  @override
  ConsumerState<_LanguageSwitcher> createState() => _LanguageSwitcherState();
}

class _LanguageSwitcherState extends ConsumerState<_LanguageSwitcher> {
  @override
  Widget build(BuildContext context) {
    final current = ref.watch(localeControllerProvider);
    final code = current?.languageCode ?? 'ru';
    final isRu = code == 'ru';
    return AnimatedToggle(
      leftLabel: 'RU',
      rightLabel: 'EN',
      isLeftSelected: isRu,
      onLeft: () => ref
          .read(localeControllerProvider.notifier)
          .setLocale(const Locale('ru')),
      onRight: () => ref
          .read(localeControllerProvider.notifier)
          .setLocale(const Locale('en')),
    );
  }
}

/// Animated two-segment sliding toggle with a pill that glides between the
/// options. Used for the RU/EN language switcher — smoother and more
/// polished than two independently-fading containers.
class AnimatedToggle extends StatefulWidget {
  const AnimatedToggle({
    super.key,
    required this.leftLabel,
    required this.rightLabel,
    required this.isLeftSelected,
    required this.onLeft,
    required this.onRight,
  });

  final String leftLabel;
  final String rightLabel;
  final bool isLeftSelected;
  final VoidCallback onLeft;
  final VoidCallback onRight;

  @override
  State<AnimatedToggle> createState() => _AnimatedToggleState();
}

class _AnimatedToggleState extends State<AnimatedToggle> {
  // Track hover/press for subtle feedback.
  bool _hoveringLeft = false;
  bool _hoveringRight = false;

  @override
  Widget build(BuildContext context) {
    const double width = 86;
    const double height = 34;
    const double pillWidth = 40;
    final bool isLeft = widget.isLeftSelected;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AppColors.outline),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The sliding pill sits behind the labels and animates its
          // horizontal position between the two halves.
          final double maxX = constraints.maxWidth - pillWidth;
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Sliding pill
              AnimatedAlign(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: isLeft
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: Container(
                  width: pillWidth,
                  height: constraints.maxHeight - 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.pulse, AppColors.pulseDeep],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.pulse.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              // Labels row — sits on top of the pill
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.isLeftSelected ? null : widget.onLeft,
                      onHorizontalDragUpdate: (_) {},
                      child: MouseRegion(
                        onEnter: (_) =>
                            setState(() => _hoveringLeft = true),
                        onExit: (_) =>
                            setState(() => _hoveringLeft = false),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 180),
                            style: TextStyle(
                              color: isLeft
                                  ? Colors.white
                                  : (_hoveringLeft
                                      ? AppColors.textPrimary
                                      : AppColors.textSecondary),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                            ),
                            child: Text(widget.leftLabel),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: !widget.isLeftSelected ? null : widget.onRight,
                      onHorizontalDragUpdate: (_) {},
                      child: MouseRegion(
                        onEnter: (_) =>
                            setState(() => _hoveringRight = true),
                        onExit: (_) =>
                            setState(() => _hoveringRight = false),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 180),
                            style: TextStyle(
                              color: !isLeft
                                  ? Colors.white
                                  : (_hoveringRight
                                      ? AppColors.textPrimary
                                      : AppColors.textSecondary),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                            ),
                            child: Text(widget.rightLabel),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              // Silence unused maxX warning when LayoutBuilder sizes change.
              if (maxX < 0) const SizedBox.shrink(),
            ],
          );
        },
      ),
    );
  }
}

class _JoinByCodeSheet extends ConsumerStatefulWidget {
  const _JoinByCodeSheet();

  @override
  ConsumerState<_JoinByCodeSheet> createState() => _JoinByCodeSheetState();
}

class _JoinByCodeSheetState extends ConsumerState<_JoinByCodeSheet> {
  final _controller = TextEditingController();
  bool _joining = false;
  String _code = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final next = _controller.text.replaceAll(RegExp(r'\D'), '');
      if (next != _code) {
        setState(() => _code = next);
      }
    });
  }

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
              label: _joining ? t.connectingTitle : t.pairingJoin,
              onPressed: _code.length == 6 && !_joining
                  ? () async {
                      setState(() => _joining = true);
                      await ref
                          .read(pairingControllerProvider.notifier)
                          .joinHandshake(_code);
                      if (!context.mounted) return;
                      final state = ref.read(pairingControllerProvider);
                      if (!state.isReadyToConfirm) {
                        setState(() => _joining = false);
                        return;
                      }
                      Navigator.of(context).pop();
                      context.go(Routes.connecting);
                    }
                  : null,
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
