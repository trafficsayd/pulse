import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/secure_key_store.dart';
import '../../subscription/application/subscription_controller.dart';

/// Tracks how many Sneak In signals were sent to each contact today, so the
/// per-tier daily quota can be enforced locally without any server-side
/// counter.
///
/// State is keyed by `contactId`, and reset whenever the calendar day rolls
/// over (using the device's local timezone — this matches the spec's
/// "1 per day per contact" wording).
class SneakInUsageState {
  const SneakInUsageState({
    this.usage = const {},
    this.bucketDay,
  });

  /// Map of contactId -> count consumed today.
  final Map<String, int> usage;

  /// Calendar day (local, midnight) the [usage] map applies to.
  final DateTime? bucketDay;

  SneakInUsageState rolledForward(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    if (bucketDay == null || today != bucketDay) {
      return SneakInUsageState(usage: const {}, bucketDay: today);
    }
    return this;
  }

  SneakInUsageState withIncrement(String contactId) {
    final next = Map<String, int>.from(usage);
    next[contactId] = (next[contactId] ?? 0) + 1;
    return SneakInUsageState(usage: next, bucketDay: bucketDay);
  }

  Map<String, Object?> toJson() => {
        'usage': usage,
        'bucketDay': bucketDay?.toIso8601String(),
      };

  factory SneakInUsageState.fromJson(Map<String, Object?> json) {
    final raw = json['usage'];
    final map = <String, int>{};
    if (raw is Map<String, Object?>) {
      raw.forEach((k, v) {
        if (v is int) map[k] = v;
      });
    }
    final day = json['bucketDay'] as String?;
    return SneakInUsageState(
      usage: map,
      bucketDay: day == null ? null : DateTime.parse(day),
    );
  }
}

class SneakInController extends Notifier<SneakInUsageState> {
  static const _storageKey = 'sneakIn.usage.v1';

  @override
  SneakInUsageState build() {
    _bootstrap();
    return const SneakInUsageState();
  }

  Future<void> _bootstrap() async {
    final store = ref.read(secureKeyStoreProvider);
    final json = await store.readJson(_storageKey);
    final loaded = json == null
        ? const SneakInUsageState()
        : SneakInUsageState.fromJson(json);
    state = loaded.rolledForward(DateTime.now());
  }

  /// True if the user can still send a Sneak In to [contactId] today.
  bool canSend(String contactId, {DateTime? now}) {
    final rolled = state.rolledForward(now ?? DateTime.now());
    final used = rolled.usage[contactId] ?? 0;
    final cap = ref
        .read(subscriptionControllerProvider.notifier)
        .sneakInPerDayPerContact;
    return used < cap;
  }

  int remaining(String contactId, {DateTime? now}) {
    final rolled = state.rolledForward(now ?? DateTime.now());
    final used = rolled.usage[contactId] ?? 0;
    final cap = ref
        .read(subscriptionControllerProvider.notifier)
        .sneakInPerDayPerContact;
    return (cap - used).clamp(0, cap);
  }

  /// Returns true if the signal was sent (quota not exhausted), false if
  /// the daily limit has been reached. The actual transmission lives in the
  /// transport layer; this controller only enforces the local quota.
  Future<bool> tryRecordSneakIn(String contactId, {DateTime? now}) async {
    final rolled = state.rolledForward(now ?? DateTime.now());
    if (!canSend(contactId, now: now)) {
      state = rolled;
      return false;
    }
    final next = rolled.withIncrement(contactId);
    state = next;
    await ref
        .read(secureKeyStoreProvider)
        .writeJson(_storageKey, next.toJson());
    return true;
  }
}

final sneakInControllerProvider =
    NotifierProvider<SneakInController, SneakInUsageState>(
        SneakInController.new);
