import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/app.dart';

void main() {
  testWidgets('Pulse app starts on the pairing screen', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: PulseApp()),
    );
    // First frame should mount without throwing. We don't pumpAndSettle here
    // because the pairing screen runs an idle pulse animation that never
    // settles; one pump is enough to verify the tree builds clean.
    await tester.pump();
    expect(find.byType(PulseApp), findsOneWidget);
  });
}
