import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/domain/mode_participant_range.dart';

void main() {
  group('ModeParticipantRange', () {
    test('solo admits exactly one participant', () {
      const range = ModeParticipantRange.solo;
      expect(range.admits(1), isTrue);
      expect(range.admits(0), isFalse);
      expect(range.admits(2), isFalse);
    });

    test('pair admits exactly two participants', () {
      const range = ModeParticipantRange.pair;
      expect(range.admits(2), isTrue);
      expect(range.admits(1), isFalse);
      expect(range.admits(3), isFalse);
    });

    test('pairOrGroup admits any count >= 2', () {
      const range = ModeParticipantRange.pairOrGroup;
      expect(range.admits(1), isFalse);
      expect(range.admits(2), isTrue);
      expect(range.admits(50), isTrue);
    });

    test('custom range respects both bounds', () {
      const range = ModeParticipantRange(min: 3, max: 5);
      expect(range.admits(2), isFalse);
      expect(range.admits(3), isTrue);
      expect(range.admits(5), isTrue);
      expect(range.admits(6), isFalse);
    });

    test('equality is structural', () {
      const a = ModeParticipantRange(min: 2, max: 4);
      const b = ModeParticipantRange(min: 2, max: 4);
      const c = ModeParticipantRange(min: 2, max: 5);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('toString renders the bounded and unbounded forms', () {
      expect(
        const ModeParticipantRange(min: 1, max: 1).toString(),
        contains('1'),
      );
      expect(
        const ModeParticipantRange(min: 2).toString(),
        contains('..∞'),
      );
      expect(
        const ModeParticipantRange(min: 2, max: 5).toString(),
        contains('..5'),
      );
    });
  });
}
