// CallKit is not linked: the package loads it at run time, on the first
// question about calls. A file of its own, because a process cannot unload
// a framework once loaded; ios_no_callkit_test.dart checks the opposite.
// ignore_for_file: implementation_imports
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:objective_c/objective_c.dart' as objc;
import 'package:speak/speak.dart';
import 'package:speak/src/darwin/darwin_backend.dart';

/// Whether the Objective-C runtime knows [name], i.e. its framework is
/// loaded.
bool _classLoaded(String name) {
  try {
    objc.getClass(name);
    return true;
  } on objc.FailedToLoadClassException {
    return false;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('CallKit is loaded on the first question, and says no call', (
    _,
  ) async {
    if (kIsWeb || !Platform.isIOS) return markTestSkipped('iOS only');
    // Not linked: not there until asked.
    expect(_classLoaded('CXCallObserver'), isFalse);
    final backend = DarwinBackend();
    addTearDown(backend.dispose);
    expect(await backend.isInCall(), isFalse);
    expect(_classLoaded('CXCallObserver'), isTrue);

    // And a speaker with the default options speaks as before.
    final speak = Speak()..language = 'en';
    addTearDown(speak.dispose);
    expect(await speak('Turn left.'), SpeakOutcome.completed);
  });
}
