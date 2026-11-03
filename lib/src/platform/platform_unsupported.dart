import '../android_options.dart';
import '../backend/backend.dart';
import '../backend/unsupported_backend.dart';

/// No speech here.
bool get isSupported => false;

/// No backend here: every call throws [UnsupportedError].
SpeechBackend createBackend(AndroidSpeakOptions android) =>
    const UnsupportedBackend();

/// No Android here.
Future<List<AndroidEngine>> androidEngines() async => const [];
