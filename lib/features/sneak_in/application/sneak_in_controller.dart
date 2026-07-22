import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/secure_key_store.dart';
import '../../session/application/mode_event_bus.dart';
import '../../subscription/application/subscription_controller.dart';

/// Outcome of an attempt to fling a Sneak In signal at a partner.
enum SneakSendResult {
  /// The signal was handed to the encrypted channel and the daily quota was
  /// consumed.
  sent,

  /// The per-day-per-contact quota is exhausted; nothing was sent.
  limitReached,

  /// No live session/channel was available (no active connection, pairing
  /// incomplete, or the transport is searching), so the signal could not be
  /// delivered. Quota is deliberately left untouched.
  noChannel,
}

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

  /// Consume one unit of today's quota for [contactId] and persist it.
  ///
  /// Callers must have already verified [canSend]; this only mutates state
  /// and writes it back. Kept private so the quota bookkeeping lives in one
  /// place, shared by [tryRecordSneakIn] and [sendSneak].
  Future<void> _consume(String contactId, {DateTime? now}) async {
    final rolled = state.rolledForward(now ?? DateTime.now());
    final next = rolled.withIncrement(contactId);
    state = next;
    await ref
        .read(secureKeyStoreProvider)
        .writeJson(_storageKey, next.toJson());
  }

  /// Returns true if the signal was sent (quota not exhausted), false if
  /// the daily limit has been reached. This records the local quota only —
  /// callers wanting real delivery should use [sendSneak].
  ///
  /// Retained for backward compatibility with existing call sites and tests.
  Future<bool> tryRecordSneakIn(String contactId, {DateTime? now}) async {
    if (!canSend(contactId, now: now)) {
      state = state.rolledForward(now ?? DateTime.now());
      return false;
    }
    await _consume(contactId, now: now);
    return true;
  }

  /// Enforce the daily quota AND actually deliver [signalId] to [contactId]
  /// over the live session.
  ///
  /// Order of operations matters:
  ///   1. Quota check — if exhausted, return [SneakSendResult.limitReached]
  ///      without touching the channel.
  ///   2. Attempt delivery through [modeEventBusProvider]. If there is no
  ///      live channel (inert bus) or the transport throws, return
  ///      [SneakSendResult.noChannel] and leave the quota untouched — we do
  ///      not burn a scarce daily send on a signal that never left the
  ///      device.
  ///   3. On success, consume one unit of quota and return
  ///      [SneakSendResult.sent].
  ///
  /// Never throws: transport failures are folded into [SneakSendResult].
  Future<SneakSendResult> sendSneak(
    String contactId,
    String signalId, {
    DateTime? now,
  }) async {
    if (!canSend(contactId, now: now)) {
      state = state.rolledForward(now ?? DateTime.now());
      return SneakSendResult.limitReached;
    }

    bool delivered;
    try {
      // Attribution (`from`) is filled by the session with its own shared
      // connectionId — the key the receiver matches against its connection
      // list. We deliberately do not stamp the recipient's id here.
      delivered = await ref.read(modeEventBusProvider).sendSneak(signalId);
    } catch (_) {
      // A desynced channel / transport hiccup must not crash the UI or
      // silently consume the user's quota.
      delivered = false;
    }
    if (!delivered) return SneakSendResult.noChannel;

    await _consume(contactId, now: now);
    return SneakSendResult.sent;
  }
}

final sneakInControllerProvider =
    NotifierProvider<SneakInController, SneakInUsageState>(
        SneakInController.new);
