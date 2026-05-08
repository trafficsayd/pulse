import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../connections/application/connections_controller.dart';
import '../../connections/domain/connection.dart';
import '../../modes/application/mode_registry.dart';
import '../../modes/domain/pulse_mode.dart';
import '../../subscription/application/subscription_controller.dart';
import '../../transport/transport.dart';

/// Main canvas after pairing. A horizontal carousel of mode icons; long
/// press to enter a mode. Top corner shows the active partner avatar and
/// transport indicator (the small color dot from [AppColors.transport*]).
class HubScreen extends ConsumerWidget {
  const HubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final connections = ref.watch(connectionsControllerProvider);
    final activeConnection = connections.active;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _HubHeader(active: activeConnection),
            const Spacer(),
            if (activeConnection == null)
              _NoActiveBanner(
                title: t.hubNoActiveConnection,
                subtitle: t.hubChooseSomeone,
              )
            else
              _ModeCarousel(activeConnection: activeConnection),
            const SizedBox(height: 24),
            Text(
              t.hubLongPressToStart,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _HubHeader extends StatelessWidget {
  const _HubHeader({required this.active});

  final Connection? active;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (active != null) ...[
            _AvatarDot(connection: active!),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                active!.nickname,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const _TransportDot(kind: TransportKind.searching),
          ] else ...[
            Expanded(
              child: Text(
                t.hubModesTitle,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.people_alt_rounded),
            color: AppColors.textSecondary,
            onPressed: () => context.go(Routes.people),
          ),
        ],
      ),
    );
  }
}

class _AvatarDot extends StatelessWidget {
  const _AvatarDot({required this.connection});

  final Connection connection;

  @override
  Widget build(BuildContext context) {
    final color = AppColors
        .avatarPalette[connection.colorIndex % AppColors.avatarPalette.length];
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.4),
      ),
      alignment: Alignment.center,
      child: Text(
        connection.emoji,
        style: const TextStyle(fontSize: 16),
      ),
    );
  }
}

class _TransportDot extends StatelessWidget {
  const _TransportDot({required this.kind});

  final TransportKind kind;

  @override
  Widget build(BuildContext context) {
    final color = switch (kind) {
      TransportKind.direct => AppColors.transportDirect,
      TransportKind.localNetwork => AppColors.transportLocal,
      TransportKind.relay => AppColors.transportRelay,
      TransportKind.searching => AppColors.transportSearching,
    };
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _NoActiveBanner extends StatelessWidget {
  const _NoActiveBanner({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ModeCarousel extends ConsumerStatefulWidget {
  const _ModeCarousel({required this.activeConnection});

  final Connection activeConnection;

  @override
  ConsumerState<_ModeCarousel> createState() => _ModeCarouselState();
}

class _ModeCarouselState extends ConsumerState<_ModeCarousel> {
  late final PageController _controller =
      PageController(viewportFraction: 0.45);
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSelectMode(PulseModeDescriptor descriptor) {
    final unlocked = ref
        .read(subscriptionControllerProvider.notifier)
        .isModeUnlocked(descriptor.id);
    if (!unlocked) {
      context.push(Routes.subscription);
      return;
    }
    // push() — not go() — so the mode screen's close X can pop back to /hub
    // instead of getting stuck.
    context.push(Routes.modePath(descriptor.id.name));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: PageView.builder(
        controller: _controller,
        itemCount: kAllModes.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) {
          final mode = kAllModes[i];
          final isCenter = i == _index;
          final unlocked = ref
              .read(subscriptionControllerProvider.notifier)
              .isModeUnlocked(mode.id);
          return AnimatedScale(
            scale: isCenter ? 1.0 : 0.78,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: GestureDetector(
              onLongPress: () => _onSelectMode(mode),
              onTap: () {
                _controller.animateToPage(
                  i,
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOut,
                );
              },
              child: _ModeTile(mode: mode, locked: !unlocked),
            ),
          );
        },
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({required this.mode, required this.locked});

  final PulseModeDescriptor mode;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: AppColors.outline),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            mode.icon,
            size: 56,
            color: locked ? AppColors.textMuted : AppColors.pulse,
          ),
          if (locked)
            const Positioned(
              top: 12,
              right: 12,
              child: Icon(
                Icons.lock_outline_rounded,
                size: 16,
                color: AppColors.textMuted,
              ),
            ),
        ],
      ),
    );
  }
}
