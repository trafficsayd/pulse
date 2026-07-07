import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/session/application/session_provider.dart';
import '../theme/app_colors.dart';

/// A thin banner shown at the top of the screen when the encrypted channel
/// encounters an error (MAC failure, replay attack, tamper).
///
/// The banner reads the [sessionProvider]'s error stream and shows a
/// dismissible warning. It auto-hides after 8 seconds if the user doesn't
/// dismiss it manually.
class SessionErrorBanner extends ConsumerStatefulWidget {
  const SessionErrorBanner({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SessionErrorBanner> createState() =>
      _SessionErrorBannerState();
}

class _SessionErrorBannerState extends ConsumerState<SessionErrorBanner> {
  StreamSubscription<Object>? _errorSub;
  String? _errorMessage;
  Timer? _autoHideTimer;

  @override
  void initState() {
    super.initState();
    _subscribeToErrors();
  }

  @override
  void didUpdateWidget(covariant SessionErrorBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    _subscribeToErrors();
  }

  void _subscribeToErrors() {
    _errorSub?.cancel();
    final sessionAsync = ref.read(sessionProvider);
    sessionAsync.whenData((session) {
      if (session == null) return;
      _errorSub = session.errors.listen((error) {
        if (!mounted) return;
        setState(() {
          _errorMessage = _humanizeError(error);
        });
        _resetAutoHide();
      });
    });
  }

  void _resetAutoHide() {
    _autoHideTimer?.cancel();
    _autoHideTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) {
        setState(() => _errorMessage = null);
      }
    });
  }

  void _dismiss() {
    _autoHideTimer?.cancel();
    setState(() => _errorMessage = null);
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    _autoHideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_errorMessage != null)
          Positioned(
            top: MediaQuery.of(context).padding.top + 4,
            left: 12,
            right: 12,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D1B1B),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.heart.withValues(alpha: 0.5),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.heart.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      color: AppColors.heart,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _dismiss,
                      child: const Icon(
                        Icons.close_rounded,
                        color: AppColors.textMuted,
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  static String _humanizeError(Object error) {
    final msg = error.toString();
    if (msg.contains('replay')) return 'Duplicate packet detected';
    if (msg.contains('MAC') || msg.contains('tamper')) {
      return 'Secure channel integrity check failed';
    }
    if (msg.contains('desync')) return 'Secure channel desynced';
    return 'Channel error — reconnecting…';
  }
}
