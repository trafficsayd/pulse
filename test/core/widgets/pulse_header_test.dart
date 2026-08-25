import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/core/widgets/pulse_mockup.dart';

void main() {
  testWidgets('header title never overlaps the trailing control',
      (tester) async {
    const titleKey = Key('header-title');
    const trailingKey = Key('language-switcher');

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 180,
              child: PulseHeader(
                title: 'Создать пару',
                titleKey: titleKey,
                leading: SizedBox(width: 40, height: 40),
                trailing: SizedBox(
                  key: trailingKey,
                  width: 86,
                  height: 34,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final titleRect = tester.getRect(find.byKey(titleKey));
    final trailingRect = tester.getRect(find.byKey(trailingKey));

    expect(titleRect.right, lessThanOrEqualTo(trailingRect.left));
  });
}
