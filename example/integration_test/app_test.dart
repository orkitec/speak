// Drives the demo app: the voices load, Stop interrupts, and Speak speaks and
// logs the outcome.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:speak_example/main.dart';

import '../../test/support/test_backend.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  useTestBackend();

  Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 300 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (finder.evaluate().isEmpty) {
      final texts = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data);
      fail('not found: $finder; on screen: ${texts.toList()}');
    }
  }

  // The demo is a lazily built list: on a small screen the buttons are not
  // built until scrolled to.
  Future<void> tapInList(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(finder);
  }

  testWidgets('the demo lists voices, speaks and stops', (tester) async {
    await tester.pumpWidget(const SpeakDemoApp());
    await pumpUntil(
      tester,
      find.textContaining(RegExp(r'Voice \([1-9]\d* installed\)')),
    );

    // The default text is long enough to be stopped half-way.
    await tapInList(tester, find.text('Speak'));
    await tester.pump(const Duration(seconds: 1));
    await tapInList(tester, find.text('Stop'));
    await pumpUntil(tester, find.textContaining('interrupted: '));

    final field = find.byType(TextField).first;
    await tester.ensureVisible(field);
    await tester.enterText(field, 'Turn left.');
    await tapInList(tester, find.text('Speak'));
    await pumpUntil(tester, find.text('completed: Turn left.'));
  });
}
