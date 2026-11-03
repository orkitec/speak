// Drives the demo app: the voices load, Stop interrupts, and Speak speaks and
// logs the outcome.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:speak_example/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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

  testWidgets('the demo lists voices, speaks and stops', (tester) async {
    await tester.pumpWidget(const SpeakDemoApp());
    await pumpUntil(
      tester,
      find.textContaining(RegExp(r'Voice \([1-9]\d* installed\)')),
    );

    // The default text is long enough to be stopped half-way.
    await tester.tap(find.text('Speak'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Stop'));
    await pumpUntil(tester, find.textContaining('interrupted: '));

    await tester.enterText(find.byType(TextField).first, 'Turn left.');
    await tester.tap(find.text('Speak'));
    await pumpUntil(tester, find.text('completed: Turn left.'));
  });
}
