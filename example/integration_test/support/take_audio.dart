// What the interruption scenarios need from the platform, done by the test
// app itself so no adb, phone call or Siri is needed:
//
// - Android: a second audio focus request, `AUDIOFOCUS_GAIN_TRANSIENT`, from
//   its own listener, which takes the focus from the speaker's request the
//   way a call's ringtone does; abandoning it gives the focus back. And the
//   app's own audio mode set to `MODE_IN_COMMUNICATION`, as a VoIP app does
//   during a call (MODIFY_AUDIO_SETTINGS, in the example's manifest).
// - iOS: `AVAudioSessionInterruptionNotification` posted with type `began`
//   and `ended`. An app cannot interrupt its own audio session (there is one
//   per app), so this exercises the package's observer, not the system's
//   decision to interrupt.
//
// The package's own bindings are used for both; they are not public API.
// ignore_for_file: implementation_imports
import 'dart:io';

import 'package:jni_flutter/jni_flutter.dart';
import 'package:objective_c/objective_c.dart' as objc;
import 'package:speak/src/android/jni_bindings.dart' as android;
import 'package:speak/src/darwin/av_bindings.dart' as darwin;

android.AudioFocusRequest? _taken;

android.AudioManager get _audioManager => androidApplicationContext
    .as(android.Context.type)
    .getSystemService$1(android.Context.AUDIO_SERVICE)!
    .as(android.AudioManager.type);

/// Asks for audio focus from the test app with its own listener, as another
/// app would (Android). [onChange] hears what Android tells that listener.
android.AudioFocusRequest requestFocus(
  int gain, {
  bool pauseWhenDucked = false,
  void Function(int change)? onChange,
}) {
  final request = android.AudioFocusRequest$Builder.new$1(gain)
      .setAudioAttributes(
        android.AudioAttributes$Builder()
            .setUsage(android.AudioAttributes.USAGE_MEDIA)!
            .build(),
      )!
      .setWillPauseWhenDucked(pauseWhenDucked)!
      .setOnAudioFocusChangeListener(
        android.AudioManager$OnAudioFocusChangeListener.implement(
          android.$AudioManager$OnAudioFocusChangeListener(
            onAudioFocusChange: onChange ?? (_) {},
            onAudioFocusChange$async: true,
          ),
        ),
      )!
      .build()!;
  _audioManager.requestAudioFocus(request);
  return request;
}

/// Gives [request]'s focus up.
void abandonFocus(android.AudioFocusRequest request) =>
    _audioManager.abandonAudioFocusRequest(request);

/// Takes the audio away from the speaker as a call would.
Future<void> takeAudio() async {
  if (Platform.isAndroid) {
    final request = _taken =
        android.AudioFocusRequest$Builder.new$1(
              android.AudioManager.AUDIOFOCUS_GAIN_TRANSIENT,
            )
            .setAudioAttributes(
              android.AudioAttributes$Builder()
                  .setUsage(android.AudioAttributes.USAGE_MEDIA)!
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
    _audioManager.requestAudioFocus(request);
  } else {
    postInterruption(began: true);
  }
  // The speaker hears of it asynchronously.
  await Future<void>.delayed(const Duration(milliseconds: 500));
}

/// Gives it back, as the end of the call would.
Future<void> giveAudioBack() async {
  if (Platform.isAndroid) {
    final request = _taken;
    _taken = null;
    if (request != null) _audioManager.abandonAudioFocusRequest(request);
  } else {
    postInterruption(began: false);
  }
  await Future<void>.delayed(const Duration(milliseconds: 500));
}

/// The audio mode now (Android only).
Future<int> audioMode() async => _audioManager.mode;

/// Puts the app in a call's audio mode (Android only).
Future<void> enterCallMode() async {
  _audioManager.mode = android.AudioManager.MODE_IN_COMMUNICATION;
}

/// Leaves it.
Future<void> leaveCallMode() async {
  if (!Platform.isAndroid) return;
  _audioManager.mode = android.AudioManager.MODE_NORMAL;
}

/// Posts `AVAudioSessionInterruptionNotification` as the system would (iOS).
void postInterruption({required bool began}) {
  darwin.NSNotificationCenter.getDefaultCenter().postNotificationName(
    darwin.AVAudioSessionInterruptionNotification,
    userInfo: objc.NSDictionary.dictionaryWithObject(
      // AVAudioSessionInterruptionTypeBegan is 1, Ended 0.
      (began ? 1 : 0).toNSNumber(),
      forKey: objc.NSCopying.as(darwin.AVAudioSessionInterruptionTypeKey),
    ),
  );
}
