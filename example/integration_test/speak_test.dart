// Runs the real engine of the device it is on: the iOS simulator, an Android
// emulator, macOS (through tool/macos_integration_test.sh). The scenarios are
// shared with the browser tests in test/web_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../test/support/scenarios.dart';
import '../../test/support/test_backend.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  useTestBackend();
  speakScenarios(
    (description, body) => testWidgets(description, (_) => body()),
  );
}
