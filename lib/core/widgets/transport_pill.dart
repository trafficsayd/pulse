import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../../features/transport/transport.dart';

/// Compact status pill displayed in the hub header — a colored dot plus a
/// short label such as "Прямое (BLE)" or "Локальная сеть".
///
/// The dot color comes from [AppColors.transport*] so the indicator always
/// matches the channel quality semantics used elsewhere.
class TransportPill extends StatelessWidget {
  const TransportPill({
    super.key,
    required this.kind,
    required this.label,
  });

  final TransportKind kind;
  final String label;

  Color get _color => switch (kind) {
        TransportKind.direct => AppColors.transportDirect,
        TransportKind.localNetwork => AppColors.transportLocal,
        TransportKind.relay => AppColors.transportRelay,
        TransportKind.searching => AppColors.transportSearching,
      };

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
