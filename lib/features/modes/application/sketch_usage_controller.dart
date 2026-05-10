import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../connections/application/connections_controller.dart'
    show secureKeyStoreProvider;
import '../../subscription/application/subscription_controller.dart';

/// Tracks how many sketch strokes the user has spent today.
///
/// The Pulse spec models the LoveSketch-style daily-stroke budget as a
/// per-day counter (50 / day for trial + expired tiers; effectively
/// unlimited for subscribed). Reset is keyed off the device's local
/// midnight, matching how [SneakInController] models its quota.
class SketchUsageState {
  const SketchUsageState({
    this.strokesUsed = 0,
    this.bucketDay,
  });

  final int strokesUsed;
  final DateTime? bucketDay;

  SketchUsageState rolledForward(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    if (bucketDay == null || today != bucketDay) {
      return SketchUsageState(strokesUsed: 0, bucketDay: today);
    }
    return this;
  }

  SketchUsageState withIncrement() => SketchUsageState(
        strokesUsed: strokesUsed + 1,
        bucketDay: bucketDay,
      );

  Map<String, Object?> toJson() => {
        'strokesUsed': strokesUsed,
        'bucketDay': bucketDay?.toIso8601String(),
      };

  factory SketchUsageState.fromJson(Map<String, Object?> json) =>
      SketchUsageState(
        strokesUsed: (json['strokesUsed'] as int?) ?? 0,
        bucketDay: json['bucketDay'] == null
            ? null
            : DateTime.parse(json['bucketDay']! as String),
      );
}

class SketchUsageController extends Notifier<SketchUsageState> {
  static const _storageKey = 'sketch.usage.v1';

  @override
  SketchUsageState build() {
    _bootstrap();
    return const SketchUsageState();
  }

  Future<void> _bootstrap() async {
    final store = ref.read(secureKeyStoreProvider);
    final json = await store.readJson(_storageKey);
    final loaded = json == null
        ? const SketchUsageState()
        : SketchUsageState.fromJson(json);
    state = loaded.rolledForward(DateTime.now());
  }

  bool canDrawStroke({DateTime? now}) {
    final rolled = state.rolledForward(now ?? DateTime.now());
    final cap = ref.read(subscriptionControllerProvider.notifier)
        .dailyStrokesPerDay;
    return rolled.strokesUsed < cap;
  }

  int remaining({DateTime? now}) {
    final rolled = state.rolledForward(now ?? DateTime.now());
    final cap = ref.read(subscriptionControllerProvider.notifier)
        .dailyStrokesPerDay;
    return (cap - rolled.strokesUsed).clamp(0, cap);
  }

  Future<bool> tryRecordStroke({DateTime? now}) async {
    final rolled = state.rolledForward(now ?? DateTime.now());
    if (!canDrawStroke(now: now)) {
      state = rolled;
      return false;
    }
    final next = rolled.withIncrement();
    state = next;
    await ref
        .read(secureKeyStoreProvider)
        .writeJson(_storageKey, next.toJson());
    return true;
  }
}

final sketchUsageControllerProvider =
    NotifierProvider<SketchUsageController, SketchUsageState>(
        SketchUsageController.new);
