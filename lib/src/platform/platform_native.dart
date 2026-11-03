import 'dart:io';

import '../android/android_backend.dart';
import '../android_options.dart';
import '../backend/backend.dart';
import '../backend/unsupported_backend.dart';
import '../darwin/darwin_backend.dart';

/// iOS, macOS and Android speak.
bool get isSupported =>
    Platform.isIOS || Platform.isMacOS || Platform.isAndroid;

/// The backend for this operating system.
SpeechBackend createBackend(AndroidSpeakOptions android) {
  if (Platform.isIOS || Platform.isMacOS) return DarwinBackend();
  if (Platform.isAndroid) return AndroidBackend(android);
  return const UnsupportedBackend();
}

/// The Android engines; empty elsewhere.
Future<List<AndroidEngine>> androidEngines() async =>
    Platform.isAndroid ? AndroidBackend.engines() : const [];
