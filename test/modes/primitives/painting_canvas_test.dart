import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/modes/primitives/painting_canvas.dart';

void main() {
  group('PaintingCanvas', () {
    testWidgets('records a stroke and reports it through onStrokeFinished',
        (tester) async {
      PaintStroke? captured;
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 200,
            height: 200,
            child: PaintingCanvas(
              color: Colors.red,
              onStrokeFinished: (s) => captured = s,
            ),
          ),
        ),
      );

      final canvas = find.byType(PaintingCanvas);
      final gesture = await tester.startGesture(tester.getCenter(canvas));
      await gesture.moveBy(const Offset(20, 0));
      await gesture.moveBy(const Offset(0, 20));
      await gesture.up();
      await tester.pump();

      expect(captured, isNotNull);
      expect(captured!.color, Colors.red);
      expect(captured!.points.length, greaterThanOrEqualTo(2));
    });

    testWidgets('pushRemoteStroke appears in strokes snapshot', (tester) async {
      final key = GlobalKey<PaintingCanvasState>();
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 200,
            height: 200,
            child: PaintingCanvas(key: key, color: Colors.blue),
          ),
        ),
      );
      key.currentState!.pushRemoteStroke(
        PaintStroke(
          color: Colors.yellow,
          strokeWidth: 3,
          points: const [
            PaintPoint(Offset(10, 10)),
            PaintPoint(Offset(20, 20))
          ],
        ),
      );
      await tester.pump();
      expect(key.currentState!.strokes.length, 1);
      expect(key.currentState!.strokes.first.color, Colors.yellow);
    });
  });
}
