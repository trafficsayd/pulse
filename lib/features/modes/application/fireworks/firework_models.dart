class FireworkContribution {
  const FireworkContribution({
    required this.id,
    required this.authorId,
    required this.x,
    required this.y,
    required this.authoredAtMs,
    required this.sequence,
    required this.seed,
    required this.palette,
    this.replyToId,
  });

  final String id;
  final String authorId;
  final double x;
  final double y;
  final int authoredAtMs;
  final int sequence;
  final int seed;
  final int palette;
  final String? replyToId;

  FireworkContribution normalized() => FireworkContribution(
        id: id,
        authorId: authorId,
        x: x.clamp(0.0, 1.0).toDouble(),
        y: y.clamp(.08, .88).toDouble(),
        authoredAtMs: authoredAtMs,
        sequence: sequence < 0 ? 0 : sequence,
        seed: seed & 0x7fffffff,
        palette: palette.abs() % 6,
        replyToId: replyToId?.isEmpty ?? true ? null : replyToId,
      );

  String get canonicalSignature =>
      '$authoredAtMs|$authorId|$sequence|$id|$seed|$palette|'
      '${x.toStringAsFixed(6)}|${y.toStringAsFixed(6)}|${replyToId ?? ''}';
}

class FireworkCulmination {
  const FireworkCulmination({
    required this.id,
    required this.firstId,
    required this.secondId,
    required this.x,
    required this.y,
    required this.seed,
    required this.paletteA,
    required this.paletteB,
    required this.authoredAtMs,
  });

  final String id;
  final String firstId;
  final String secondId;
  final double x;
  final double y;
  final int seed;
  final int paletteA;
  final int paletteB;
  final int authoredAtMs;
}

class FireworkSnapshot {
  const FireworkSnapshot({
    required this.contributions,
    required this.culminations,
    required this.fingerprint,
  });

  final List<FireworkContribution> contributions;
  final List<FireworkCulmination> culminations;
  final int fingerprint;
}
