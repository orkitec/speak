import '../audio.dart';
import '../voice.dart';
import 'backend.dart';

/// The backend of a platform without speech: everything throws
/// [UnsupportedError], except what can safely do nothing.
class UnsupportedBackend implements SpeechBackend {
  /// Creates the backend.
  const UnsupportedBackend();

  static Never _unsupported() => throw UnsupportedError(
    'speak supports iOS, macOS, Android and the web; check Speak.isSupported.',
  );

  @override
  Stream<BackendEvent> get events => const Stream.empty();

  @override
  bool get canPause => false;

  @override
  Future<List<Voice>> voices() async => _unsupported();

  @override
  Future<VoiceAvailability?> languageAvailability(String languageTag) async =>
      _unsupported();

  @override
  Future<void> activateAudio(SpeakAudio audio) async {}

  @override
  Future<void> deactivateAudio() async {}

  @override
  Future<bool> isBluetoothRoute(SpeakAudio audio) async => false;

  @override
  void speak(BackendUtterance utterance) => _unsupported();

  @override
  Future<void> stop() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> dispose() async {}
}
