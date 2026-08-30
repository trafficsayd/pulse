import 'dart:math' as math;

enum CandleStyle { classic, glass, violet }

class CandleCharacter {
  const CandleCharacter({
    required this.windResponse,
    required this.stability,
    required this.extinguishResistance,
    required this.flickerAmount,
    required this.warmth,
    required this.crackle,
    required this.burnRatePerSecond,
    required this.shieldEfficiency,
    required this.requiresSharedIgnition,
  });

  final double windResponse;
  final double stability;
  final double extinguishResistance;
  final double flickerAmount;
  final double warmth;
  final double crackle;
  final double burnRatePerSecond;
  final double shieldEfficiency;
  final bool requiresSharedIgnition;
}

extension CandleStyleCharacter on CandleStyle {
  CandleCharacter get character => switch (this) {
        CandleStyle.classic => const CandleCharacter(
            windResponse: 1,
            stability: .90,
            extinguishResistance: 1,
            flickerAmount: .86,
            warmth: 1,
            crackle: .72,
            burnRatePerSecond: 1 / 7200,
            shieldEfficiency: .74,
            requiresSharedIgnition: false,
          ),
        CandleStyle.glass => const CandleCharacter(
            windResponse: .82,
            stability: 1.12,
            extinguishResistance: 1.12,
            flickerAmount: .64,
            warmth: .94,
            crackle: .42,
            burnRatePerSecond: 1 / 14400,
            shieldEfficiency: .84,
            requiresSharedIgnition: false,
          ),
        CandleStyle.violet => const CandleCharacter(
            windResponse: .68,
            stability: 1.28,
            extinguishResistance: 1.22,
            flickerAmount: .52,
            warmth: .76,
            crackle: .28,
            burnRatePerSecond: 1 / 21600,
            shieldEfficiency: .90,
            requiresSharedIgnition: true,
          ),
      };
}

class CandleBreathReading {
  const CandleBreathReading({
    required this.pressure,
    required this.confidence,
    required this.noiseFloor,
    required this.calibrationProgress,
    required this.calibrated,
  });

  final double pressure;
  final double confidence;
  final double noiseFloor;
  final double calibrationProgress;
  final bool calibrated;
}

/// Learns the current room's quiet level and favours noise-like breath over
/// periodic speech. No audio leaves the device; only the resulting pressure
/// is shared with the partner.
class CandleBreathAnalyzer {
  CandleBreathAnalyzer({
    this.calibrationDuration = const Duration(milliseconds: 1800),
  }) : _calibrated = calibrationDuration == Duration.zero;

  final Duration calibrationDuration;
  DateTime? _startedAt;
  double _ambientEma = .02;
  double _noiseFloor = .02;
  int _calibrationSamples = 0;
  bool _calibrated;

  bool get calibrated => _calibrated;
  double get noiseFloor => _noiseFloor;

  CandleBreathReading add({
    required double level,
    required double noiseLikeness,
    required DateTime at,
  }) {
    final clampedLevel = level.clamp(0.0, 1.0).toDouble();
    final clampedNoise = noiseLikeness.clamp(0.0, 1.0).toDouble();
    _startedAt ??= at;
    if (!_calibrated) {
      _calibrationSamples++;
      // Give quieter chunks more weight so a cough during calibration does
      // not permanently raise the floor.
      final bounded = math.min(clampedLevel, _ambientEma + .12);
      _ambientEma = _calibrationSamples == 1
          ? bounded
          : _ambientEma * .88 + bounded * .12;
      final elapsed = at.difference(_startedAt!);
      final progress = calibrationDuration == Duration.zero
          ? 1.0
          : (elapsed.inMicroseconds / calibrationDuration.inMicroseconds)
              .clamp(0.0, 1.0)
              .toDouble();
      if (progress >= 1 && _calibrationSamples >= 4) {
        _calibrated = true;
        _noiseFloor = (_ambientEma * 1.18 + .012).clamp(.015, .42);
      }
      return CandleBreathReading(
        pressure: 0,
        confidence: clampedNoise,
        noiseFloor: _noiseFloor,
        calibrationProgress: progress,
        calibrated: _calibrated,
      );
    }

    final usableRange = math.max(.08, 1 - _noiseFloor);
    final normalized =
        ((clampedLevel - _noiseFloor) / usableRange).clamp(0.0, 1.0).toDouble();
    final confidence = ((clampedNoise - .10) / .62).clamp(0.0, 1.0).toDouble();
    // Speech still creates a small movement, but only noise-like breath can
    // build enough sustained pressure to extinguish the flame.
    final pressure = normalized * (.16 + confidence * .84);
    return CandleBreathReading(
      pressure: pressure.clamp(0.0, 1.0),
      confidence: confidence,
      noiseFloor: _noiseFloor,
      calibrationProgress: 1,
      calibrated: true,
    );
  }
}

class CandleForces {
  const CandleForces({
    required this.lean,
    required this.pressure,
    required this.turbulence,
    required this.heightScale,
  });

  final double lean;
  final double pressure;
  final double turbulence;
  final double heightScale;

  factory CandleForces.resolve({
    required double localPressure,
    required double partnerPressure,
    required CandleStyle style,
    bool localShielded = false,
    bool partnerShielded = false,
  }) {
    final character = style.character;
    final shieldCount = (localShielded ? 1 : 0) + (partnerShielded ? 1 : 0);
    final shield = shieldCount == 0
        ? 0.0
        : (character.shieldEfficiency + (shieldCount - 1) * .07)
            .clamp(0.0, .96);
    final local = (localPressure * (1 - shield)).clamp(0.0, 1.0).toDouble();
    final partner = (partnerPressure * (1 - shield)).clamp(0.0, 1.0).toDouble();
    final directional = (local - partner) * character.windResponse;
    final combined = (local + partner).clamp(0.0, 1.45);
    final collision = math.min(local, partner);
    return CandleForces(
      lean: directional.clamp(-1.0, 1.0),
      pressure: combined,
      turbulence:
          ((directional.abs() * .42 + collision * .92) / character.stability)
              .clamp(0.0, 1.0),
      heightScale: (1 - combined * .27 / character.stability).clamp(.54, 1.0),
    );
  }
}

/// A candle is not reset when the screen closes. This compact state is the
/// physical memory of one pair: its height, wax history and sealed wish.
class CandleMemory {
  const CandleMemory({
    required this.waxRemaining,
    required this.sessions,
    required this.totalBurnSeconds,
    required this.signatureSeed,
    required this.smokeSignature,
    required this.sharedBreath,
    this.sealedWish,
    this.wishRevealed = false,
  });

  factory CandleMemory.fresh({required int seed}) => CandleMemory(
        waxRemaining: 1,
        sessions: 0,
        totalBurnSeconds: 0,
        signatureSeed: seed & 0x7fffffff,
        smokeSignature: seed.abs() % 3,
        sharedBreath: 0,
      );

  final double waxRemaining;
  final int sessions;
  final int totalBurnSeconds;
  final int signatureSeed;
  final int smokeSignature;
  final double sharedBreath;
  final String? sealedWish;
  final bool wishRevealed;

  bool get isSpent => waxRemaining <= .12;
  bool get hasWish => sealedWish?.trim().isNotEmpty ?? false;

  CandleMemory burn({
    required Duration elapsed,
    required CandleStyle style,
    double localBreath = 0,
    double partnerBreath = 0,
  }) {
    final seconds = math.max(0, elapsed.inMilliseconds / 1000);
    final nextWax = math.max(
      .08,
      waxRemaining - seconds * style.character.burnRatePerSecond,
    );
    final shared = math.min(localBreath, partnerBreath);
    return copyWith(
      waxRemaining: nextWax,
      totalBurnSeconds: totalBurnSeconds + seconds.round(),
      sharedBreath: (sharedBreath * .92 + shared * .08).clamp(0.0, 1.0),
    );
  }

  CandleMemory finishSession() {
    final nextSessions = sessions + 1;
    final mixed = signatureSeed ^
        (nextSessions * 7919) ^
        totalBurnSeconds ^
        (sharedBreath * 1000).round();
    return copyWith(
      sessions: nextSessions,
      smokeSignature: mixed.abs() % 3,
    );
  }

  CandleMemory copyWith({
    double? waxRemaining,
    int? sessions,
    int? totalBurnSeconds,
    int? signatureSeed,
    int? smokeSignature,
    double? sharedBreath,
    String? sealedWish,
    bool? wishRevealed,
  }) =>
      CandleMemory(
        waxRemaining: waxRemaining ?? this.waxRemaining,
        sessions: sessions ?? this.sessions,
        totalBurnSeconds: totalBurnSeconds ?? this.totalBurnSeconds,
        signatureSeed: signatureSeed ?? this.signatureSeed,
        smokeSignature: smokeSignature ?? this.smokeSignature,
        sharedBreath: sharedBreath ?? this.sharedBreath,
        sealedWish: sealedWish ?? this.sealedWish,
        wishRevealed: wishRevealed ?? this.wishRevealed,
      );

  Map<String, Object?> toJson() => {
        'wax': waxRemaining,
        'sessions': sessions,
        'burnSeconds': totalBurnSeconds,
        'seed': signatureSeed,
        'smoke': smokeSignature,
        'sharedBreath': sharedBreath,
        'wish': sealedWish,
        'wishRevealed': wishRevealed,
      };

  factory CandleMemory.fromJson(Map<String, Object?> json) => CandleMemory(
        waxRemaining: ((json['wax'] as num?)?.toDouble() ?? 1).clamp(.08, 1.0),
        sessions: math.max(0, (json['sessions'] as num?)?.toInt() ?? 0),
        totalBurnSeconds:
            math.max(0, (json['burnSeconds'] as num?)?.toInt() ?? 0),
        signatureSeed: (json['seed'] as num?)?.toInt() ?? 1,
        smokeSignature: ((json['smoke'] as num?)?.toInt() ?? 0).clamp(0, 2),
        sharedBreath:
            ((json['sharedBreath'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
        sealedWish: json['wish'] as String?,
        wishRevealed: json['wishRevealed'] as bool? ?? false,
      );
}
