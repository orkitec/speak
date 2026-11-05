// The voices as the very first thing asked of a fresh engine. Android's
// Google engine reports itself started before it has loaded its voices; the
// list must not come back without them. Named to run first on Android, where
// each file is an app of its own and the engine's service is cold only for
// the first; first in all_tests.dart elsewhere.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:speak/speak.dart';
// ignore: implementation_imports
import 'package:speak/src/android/voice_list.dart' show voicesSettle;

import '../../test/support/test_backend.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  useTestBackend();

  testWidgets('the voices, asked for first, are there', (_) async {
    final speak = Speak();
    addTearDown(speak.dispose);
    final watch = Stopwatch()..start();
    final voices = await speak.voices();
    final installed = voices.where((v) => v.isInstalled).toList();
    final english = voices.where((v) => v.language.startsWith('en')).toList();
    // What the engine listed, for when it differs between images.
    // The time against the window the engine is given ([voicesSettle] on
    // Android), so CI shows the margin.
    debugPrint(
      'voices first: ${voices.length} after ${watch.elapsedMilliseconds} ms '
      '(Android allows ${voicesSettle.inMilliseconds} ms), '
      '${installed.length} installed, ${english.length} English '
      '(${english.where((v) => v.isInstalled).length} installed)',
    );
    expect(voices, isNotEmpty);
    expect(installed, isNotEmpty);
  });
}
