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
import '../../connections/application/connections_controller.dart';
import '../../subscription/application/subscription_controller.dart';
import '../application/pairing_controller.dart';
import 'pairing_error_text.dart';

/// True when the saved-connections cap for the current tier has already
/// been reached (spec §9). Shared by the host and join entry points so
/// starting a brand-new pairing handshake never bypasses monetisation.
bool _connectionLimitReached(WidgetRef ref) {
  final maxConnections =
      ref.read(subscriptionControllerProvider.notifier).maxConnections;
  return !ref
      .read(connectionsControllerProvider.notifier)
      .canAddConnection(maxConnections);
}

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
    //
    // MONETIZATION (spec §9): this is the entry point for a brand-new
    // "create pair" flow, so it's where the saved-connections cap must be
    // enforced. If the cap for the current tier is already reached, the
    // handshake (which would burn a radio/signaling round-trip for a
    // connection the user isn't allowed to keep) never starts — the user
    // is redirected straight to the paywall instead.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_connectionLimitReached(ref)) {
        context.go(Routes.subscription);
        return;
      }
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
                                pairing.phase == PairingPhase.failed
                                    ? describePairingError(t, pairing.error)
                                    : pairing.hasShortCode
                                        ? t.connectingSecuredLink
                                        : pairing.hasPairingCode
                                            ? t.pairingEnterCode
                                            : t.pairingDerivingCode,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: pairing.phase == PairingPhase.failed
                                      ? AppColors.heart
                                      : AppColors.textMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (pairing.phase == PairingPhase.failed &&
                                  pairingErrorDetail(pairing.error)
                                      .isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  pairingErrorDetail(pairing.error),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 10,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (pairing.phase == PairingPhase.failed) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => ref
                                .read(pairingControllerProvider.notifier)
                                .startHostHandshake(),
                            child: Text(
                              t.pairingRetry,
                              style: const TextStyle(
                                color: AppColors.pulse,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
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
    // Re-check the cap right before committing to the pairing flow — the
    // handshake itself already refused to start in initState() if the
    // limit was hit, but this guards the (rare) case where state changed
    // while the user was staring at the QR/SAS code.
    if (_connectionLimitReached(ref)) {
      context.go(Routes.subscription);
      return;
    }
    context.go(Routes.connecting);
  }

  void _onJoinPair(BuildContext context) {
    // MONETIZATION (spec §9): "join" is the other brand-new-pairing entry
    // point, so it needs the same cap check before a single byte of the
    // join handshake goes out.
    if (_connectionLimitReached(ref)) {
      context.go(Routes.subscription);
      return;
    }
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

class _JoinByCodeSheet extends ConsumerStatefulWidget {
  const _JoinByCodeSheet();

  @override
  ConsumerState<_JoinByCodeSheet> createState() => _JoinByCodeSheetState();
}

class _JoinByCodeSheetState extends ConsumerState<_JoinByCodeSheet> {
  final _controller = TextEditingController();
  bool _joining = false;
  String _code = '';
  String? _error;
  String? _errorDetail;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final next = _controller.text.replaceAll(RegExp(r'\D'), '');
      if (next != _code) {
        // A fresh code attempt clears the stale failure banner.
        setState(() {
          _code = next;
          _error = null;
          _errorDetail = null;
        });
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
                      // MONETIZATION (spec §9): last-moment re-check right
                      // before the join handshake actually talks to the
                      // signaling server — the cap may have been hit while
                      // this sheet was open (e.g. another device on the
                      // same account finished pairing in the meantime).
                      if (_connectionLimitReached(ref)) {
                        Navigator.of(context).pop();
                        context.go(Routes.subscription);
                        return;
                      }
                      setState(() {
                        _joining = true;
                        _error = null;
                        _errorDetail = null;
                      });
                      await ref
                          .read(pairingControllerProvider.notifier)
                          .joinHandshake(_code);
                      if (!context.mounted) return;
                      final state = ref.read(pairingControllerProvider);
                      if (!state.isReadyToConfirm) {
                        setState(() {
                          _joining = false;
                          _error = describePairingError(t, state.error);
                          _errorDetail = pairingErrorDetail(state.error);
                        });
                        return;
                      }
                      Navigator.of(context).pop();
                      context.go(Routes.connecting);
                    }
                  : null,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.heart,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            if (_errorDetail != null && _errorDetail!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                _errorDetail!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  height: 1.3,
                ),
              ),
            ],
          ],
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
