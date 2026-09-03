import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/locale/locale_controller.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/pulse_mockup.dart';
import '../../../l10n/app_localizations.dart';
import '../application/pairing_controller.dart';
import '../domain/pairing_qr_payload.dart';

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
      // Idempotent entry: only kick off the handshake if we're truly idle.
      // We deliberately do NOT auto-restart from `failed` — that state must
      // be reached only by an explicit user tap on the Retry button, otherwise
      // each frame rebuild rotates the pairing code and the partner's already-
      // submitted answer (posted against the previous session) never reaches
      // the new poller.
      final current = ref.read(pairingControllerProvider).phase;
      if (current == PairingPhase.idle) {
        ref.read(pairingControllerProvider.notifier).startHostHandshake();
      }
    });
  }

  String _formatCode(String code) {
    if (code.length != 6) return code;
    return '${code.substring(0, 3)} ${code.substring(3)}';
  }

  String _qrPayload(PairingState pairing) {
    final pub = pairing.localPublicKeyBase64;
    final code = pairing.pairingCode;
    if (pub == null || code == null) {
      // Generation in flight — fall back to a placeholder URI so the QR
      // widget doesn't crash on an empty string.
      return 'pulse://pair?pending=1';
    }
    return PairingQrPayload.encode(
      code: code,
      hostPublicKeyBase64Url: pub,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final pairing = ref.watch(pairingControllerProvider);
    final displayCode = pairing.sasCode ?? pairing.pairingCode ?? '······';

    // Host-side auto-route: once the handshake reaches `awaitingConfirmation`
    // (we have partner's public key + derived shared secret + SAS), push the
    // connecting screen which will persist the keys and forward to the hub.
    // Without this the host is stuck on a "Create pair" button that is only
    // enabled after `isReadyToConfirm` — the joiner side already auto-routes
    // via `joinHandshake`, host was asymmetric.
    ref.listen<PairingState>(pairingControllerProvider, (prev, next) {
      if (prev?.phase != PairingPhase.awaitingConfirmation &&
          next.phase == PairingPhase.awaitingConfirmation &&
          next.sasCode != null &&
          next.connectionId != null) {
        // Capture router before the gap so the linter is happy and we don't
        // re-lookup `BuildContext` after an async boundary.
        final router = GoRouter.of(context);
        Future.microtask(() {
          if (mounted) router.go(Routes.connecting);
        });
      }
    });

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          ref.read(pairingControllerProvider.notifier).reset();
        }
      },
      child: Scaffold(
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
                      onTap: () {
                        ref.read(pairingControllerProvider.notifier).reset();
                        context.go(Routes.people);
                      },
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
                                    color:
                                        AppColors.pulse.withValues(alpha: 0.2),
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
                                        .read(
                                            pairingControllerProvider.notifier)
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
        return const _JoinPairSheet();
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
    final code =
        current?.languageCode ?? Localizations.localeOf(context).languageCode;
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
                alignment:
                    isLeft ? Alignment.centerLeft : Alignment.centerRight,
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
                        onEnter: (_) => setState(() => _hoveringLeft = true),
                        onExit: (_) => setState(() => _hoveringLeft = false),
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
                        onEnter: (_) => setState(() => _hoveringRight = true),
                        onExit: (_) => setState(() => _hoveringRight = false),
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

class _JoinPairSheet extends ConsumerStatefulWidget {
  const _JoinPairSheet();

  @override
  ConsumerState<_JoinPairSheet> createState() => _JoinPairSheetState();
}

class _JoinPairSheetState extends ConsumerState<_JoinPairSheet> {
  final _controller = TextEditingController();
  late final MobileScannerController _scanner = MobileScannerController(
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
    returnImage: false,
    autoZoom: true,
  );
  bool _joining = false;
  bool _manualEntry = false;
  String _code = '';
  String? _scanError;

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
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _join({
    required String code,
    List<int>? expectedHostPublicKey,
  }) async {
    if (_joining) return;
    setState(() {
      _joining = true;
      _scanError = null;
    });
    await _scanner.stop();
    await ref.read(pairingControllerProvider.notifier).joinHandshake(
          code,
          expectedHostPublicKey: expectedHostPublicKey,
        );
    if (!mounted) return;
    final state = ref.read(pairingControllerProvider);
    if (!state.isReadyToConfirm) {
      final t = AppLocalizations.of(context)!;
      setState(() {
        _joining = false;
        _scanError = expectedHostPublicKey == null
            ? t.pairingError
            : t.pairingQrConnectionFailed;
      });
      if (!_manualEntry) await _scanner.start();
      return;
    }
    Navigator.of(context).pop();
    context.go(Routes.connecting);
  }

  void _onDetect(BarcodeCapture capture) {
    if (_joining) return;
    PairingQrPayload? payload;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      try {
        payload = PairingQrPayload.parse(raw);
        break;
      } on PairingQrPayloadException {
        // Keep looking in case the frame contains more than one QR code.
      }
    }
    if (payload == null) {
      setState(() {
        _scanError = AppLocalizations.of(context)!.pairingQrInvalid;
      });
      return;
    }
    _join(
      code: payload.code,
      expectedHostPublicKey: payload.hostPublicKey,
    );
  }

  void _showManualEntry() {
    _scanner.stop();
    setState(() {
      _manualEntry = true;
      _scanError = null;
    });
  }

  void _showScanner() {
    setState(() {
      _manualEntry = false;
      _scanError = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scanner.start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final height = (screenHeight * 0.82).clamp(
      0.0,
      (screenHeight - inset - 12).clamp(0.0, screenHeight),
    );
    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.only(bottom: inset),
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
            child: Column(
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
                  _manualEntry ? t.pairingEnterCode : t.pairingScanQr,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _manualEntry ? t.pairingManualHint : t.pairingScanQrHint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _manualEntry
                        ? _ManualCodeEntry(
                            key: const ValueKey<String>('manual'),
                            controller: _controller,
                            joining: _joining,
                            code: _code,
                            onJoin: () => _join(code: _code),
                          )
                        : _QrScannerView(
                            key: const ValueKey<String>('scanner'),
                            controller: _scanner,
                            joining: _joining,
                            onDetect: _onDetect,
                            onUseCode: _showManualEntry,
                          ),
                  ),
                ),
                if (_scanError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _scanError!,
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(color: AppColors.danger, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 6),
                TextButton(
                  onPressed: _joining
                      ? null
                      : _manualEntry
                          ? _showScanner
                          : () => Navigator.of(context).pop(),
                  child: Text(
                    _manualEntry ? t.pairingScanQrInstead : t.pairingCancel,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QrScannerView extends StatelessWidget {
  const _QrScannerView({
    super.key,
    required this.controller,
    required this.joining,
    required this.onDetect,
    required this.onUseCode,
  });

  final MobileScannerController controller;
  final bool joining;
  final ValueChanged<BarcodeCapture> onDetect;
  final VoidCallback onUseCode;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Column(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: controller,
                  onDetect: onDetect,
                  errorBuilder: (context, error) => ColoredBox(
                    color: AppColors.surface,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          error.errorCode ==
                                  MobileScannerErrorCode.permissionDenied
                              ? t.pairingCameraDenied
                              : t.pairingCameraUnavailable,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                IgnorePointer(
                  child: Center(
                    child: Container(
                      width: 226,
                      height: 226,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(
                          color: AppColors.pulse,
                          width: 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.pulse.withValues(alpha: 0.28),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: ValueListenableBuilder<MobileScannerState>(
                    valueListenable: controller,
                    builder: (context, state, _) {
                      if (state.torchState == TorchState.unavailable) {
                        return const SizedBox.shrink();
                      }
                      return Material(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: t.pairingTorch,
                          onPressed: controller.toggleTorch,
                          color: state.torchState == TorchState.on
                              ? AppColors.transportRelay
                              : Colors.white,
                          icon: Icon(
                            state.torchState == TorchState.on
                                ? Icons.flashlight_on_rounded
                                : Icons.flashlight_off_rounded,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (joining)
                  ColoredBox(
                    color: Colors.black.withValues(alpha: 0.58),
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.pulse,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: joining ? null : onUseCode,
            icon: const Icon(Icons.dialpad_rounded),
            label: Text(t.pairingUseCode),
          ),
        ),
      ],
    );
  }
}

class _ManualCodeEntry extends StatelessWidget {
  const _ManualCodeEntry({
    super.key,
    required this.controller,
    required this.joining,
    required this.code,
    required this.onJoin,
  });

  final TextEditingController controller;
  final bool joining;
  final String code;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextField(
          controller: controller,
          autofocus: true,
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
            label: joining ? t.connectingTitle : t.pairingJoin,
            onPressed: code.length == 6 && !joining ? onJoin : null,
          ),
        ),
      ],
    );
  }
}
