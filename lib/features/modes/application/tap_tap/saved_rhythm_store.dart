import 'dart:convert';

import '../../../../core/storage/secure_key_store.dart';

class SavedKnockRhythm {
  const SavedKnockRhythm({
    required this.id,
    required this.name,
    required this.intervalsMs,
    required this.intensities,
  });

  final String id;
  final String name;
  final List<int> intervalsMs;
  final List<double> intensities;

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'intervalsMs': intervalsMs,
        'intensities': intensities,
      };

  static SavedKnockRhythm? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    final intervals = raw['intervalsMs'];
    final intensities = raw['intensities'];
    if (id is! String ||
        id.isEmpty ||
        id.length > 96 ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 40 ||
        intervals is! List ||
        intensities is! List ||
        intervals.length != intensities.length ||
        intervals.isEmpty ||
        intervals.length > 16) {
      return null;
    }
    final parsedIntervals = <int>[];
    final parsedIntensities = <double>[];
    for (var i = 0; i < intervals.length; i++) {
      final interval = intervals[i];
      final intensity = intensities[i];
      if (interval is! num ||
          interval < 0 ||
          interval > 12000 ||
          intensity is! num ||
          intensity < 0 ||
          intensity > 1) {
        return null;
      }
      parsedIntervals.add(interval.toInt());
      parsedIntensities.add(intensity.toDouble());
    }
    return SavedKnockRhythm(
      id: id,
      name: name.trim(),
      intervalsMs: List.unmodifiable(parsedIntervals),
      intensities: List.unmodifiable(parsedIntensities),
    );
  }
}

/// Encrypted, opt-in-only storage for normalized rhythm signatures.
///
/// No pressure samples, touch coordinates, partner name, or notification
/// text is persisted. Corrupt entries are discarded during reads.
class SavedRhythmStore {
  SavedRhythmStore(this._storage, {this.capacity = 12});

  static const _storageKey = 'tap_tap.saved_rhythms.v1';
  final SecureKeyStore _storage;
  final int capacity;

  Future<List<SavedKnockRhythm>> readAll() async {
    final raw = await _storage.readString(_storageKey);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return List.unmodifiable(
        decoded.map(SavedKnockRhythm.tryParse).whereType<SavedKnockRhythm>(),
      );
    } on FormatException {
      return const [];
    }
  }

  Future<void> save(SavedKnockRhythm rhythm) async {
    final valid = SavedKnockRhythm.tryParse(rhythm.toJson());
    if (valid == null) throw ArgumentError.value(rhythm, 'rhythm');
    final current = await readAll();
    final next = <SavedKnockRhythm>[
      valid,
      ...current.where((item) => item.id != valid.id),
    ].take(capacity).toList(growable: false);
    await _storage.writeString(
      _storageKey,
      jsonEncode(next.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> delete(String id) async {
    final next = (await readAll()).where((item) => item.id != id).toList();
    if (next.isEmpty) {
      await _storage.delete(_storageKey);
    } else {
      await _storage.writeString(
        _storageKey,
        jsonEncode(next.map((item) => item.toJson()).toList()),
      );
    }
  }
}
