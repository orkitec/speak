import 'package:flutter_test/flutter_test.dart';
import 'package:speak/src/android/focus.dart';
import 'package:speak/src/backend/backend.dart';

void main() {
  group('what a focus request means for the claim', () {
    test('granted is granted', () {
      expect(
        focusClaim(granted: true, inCall: false, taken: false),
        AudioClaim.granted,
      );
    });

    test('a refusal during a call is refused', () {
      expect(
        focusClaim(granted: false, inCall: true, taken: false),
        AudioClaim.refused,
      );
    });

    test(
      'focus still taken by a transient loss is refused, without asking',
      () {
        expect(
          focusClaim(granted: true, inCall: false, taken: true),
          AudioClaim.refused,
        );
      },
    );

    test('a refusal with no call (Android 15, in the background) is '
        'unclaimed, not refused', () {
      expect(
        focusClaim(granted: false, inCall: false, taken: false),
        AudioClaim.unclaimed,
      );
    });
  });
}
