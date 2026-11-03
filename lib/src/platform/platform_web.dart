import '../android_options.dart';
import '../backend/backend.dart';
import '../backend/unsupported_backend.dart';
import '../web/web_backend.dart';

/// Whether the browser has the Web Speech API.
bool get isSupported => hasSpeechSynthesis;

/// The Web Speech API backend, or one that throws without it.
SpeechBackend createBackend(AndroidSpeakOptions android) =>
    hasSpeechSynthesis ? WebBackend() : const UnsupportedBackend();

/// No Android here.
Future<List<AndroidEngine>> androidEngines() async => const [];
