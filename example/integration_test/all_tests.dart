// Every integration test file in one app launch, for the iOS and macOS
// scripts in tool/: each `flutter test` builds, launches and attaches once,
// and each launch on a GitHub runner's simulator can hang.
// voices_first_test.dart goes first, while the engine is fresh, then
// ios_callkit_test.dart, before anything asks about calls.
// ios_no_callkit_test.dart needs a process that never does and is run
// apart. Named so `*_test.dart` does not pick it up twice.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'app_test.dart' as app;
import 'background_test.dart' as background;
import 'interruption_test.dart' as interruption;
import 'ios_callkit_test.dart' as ios_callkit;
import 'platform_test.dart' as platform;
import 'speak_test.dart' as speak;
import 'voices_first_test.dart' as voices_first;

import '../../test/support/test_backend.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  useTestBackend();
  group('voices_first_test.dart', voices_first.main);
  group('ios_callkit_test.dart', ios_callkit.main);
  group('app_test.dart', app.main);
  group('background_test.dart', background.main);
  group('interruption_test.dart', interruption.main);
  group('platform_test.dart', platform.main);
  group('speak_test.dart', speak.main);
}
