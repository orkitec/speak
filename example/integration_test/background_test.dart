// Android 15 turns down audio focus for an app in the background that runs
// no foreground service (AUDIOFOCUS_REQUEST_FAILED). That is no call, so the
// speech must still go out, without focus. Android only.
// ignore_for_file: implementation_imports
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jni_flutter/jni_flutter.dart';
import 'package:speak/speak.dart';
import 'package:speak/src/android/jni_bindings.dart' as android;

import '../../test/support/test_backend.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  useTestBackend();

  testWidgets('in the background, refused focus is no call: the text is '
      'spoken without it', (_) async {
    if (kIsWeb || !Platform.isAndroid) {
      markTestSkipped('Android only');
      return;
    }
    final speak = Speak()..language = 'en';
    addTearDown(speak.dispose);

    // In front: the focus is granted.
    expect(await speak('In front.'), SpeakOutcome.completed);

    final activity = androidActivity(
      PlatformDispatcher.instance.engineId!,
    )!.as(android.Activity.type);
    // Brought back to the front however the test ends.
    addTearDown(() => _toFront(activity));
    expect(activity.moveTaskToBack(true), isTrue);
    // Android lets an app that just left the front keep asking for a few
    // seconds (on the API 35 emulator, refusals start between 3 and 6 s).
    await Future<void>.delayed(const Duration(seconds: 8));
    if (android.Build$VERSION.SDK_INT >= 35) {
      expect(
        _focusRequestResult(),
        android.AudioManager.AUDIOFOCUS_REQUEST_FAILED,
        reason: 'Android 15 refuses focus to an app in the background',
      );
    }

    // Behind: the focus is refused; the speech goes out anyway.
    final watch = Stopwatch()..start();
    expect(await speak('In the background.'), SpeakOutcome.completed);
    expect(watch.elapsed, greaterThan(const Duration(milliseconds: 300)));
  });
}

/// What a focus request from this app gets right now (given back at once).
int _focusRequestResult() {
  final manager = androidApplicationContext
      .as(android.Context.type)
      .getSystemService$1(android.Context.AUDIO_SERVICE)!
      .as(android.AudioManager.type);
  final request =
      android.AudioFocusRequest$Builder.new$1(
            android.AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK,
          )
          .setAudioAttributes(
            android.AudioAttributes$Builder()
                .setUsage(android.AudioAttributes.USAGE_ASSISTANT)!
                .build(),
          )!
          .setOnAudioFocusChangeListener(
            android.AudioManager$OnAudioFocusChangeListener.implement(
              android.$AudioManager$OnAudioFocusChangeListener(
                onAudioFocusChange: (_) {},
                onAudioFocusChange$async: true,
              ),
            ),
          )!
          .build();
  final result = manager.requestAudioFocus(request);
  manager.abandonAudioFocusRequest(request);
  return result;
}

/// Brings the test app's task back to the front.
void _toFront(android.Activity activity) {
  androidApplicationContext
      .as(android.Context.type)
      .getSystemService$1(android.Context.ACTIVITY_SERVICE)!
      .as(android.ActivityManager.type)
      .moveTaskToFront(activity.taskId, 0);
}
