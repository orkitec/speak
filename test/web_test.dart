// The real-engine scenarios against the browser's speechSynthesis. Run with
// tool/web_test.sh: Chrome only speaks without a user gesture when started
// with --autoplay-policy=no-user-gesture-required.
@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';

import 'support/scenarios.dart';
import 'support/test_backend.dart';

void main() {
  useTestBackend();
  speakScenarios(
    (description, body) =>
        test(description, body, timeout: const Timeout(Duration(minutes: 1))),
  );
}
