// The web: the Web Speech API's speechSynthesis, through package:web.
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../audio.dart';
import '../backend/backend.dart';
import '../outcome.dart';
import '../voice.dart';

/// Whether the browser has speechSynthesis.
bool get hasSpeechSynthesis => web.window.has('speechSynthesis');

/// Speaks with the browser's speechSynthesis.
///
/// A web page cannot touch other audio, so the audio calls do nothing.
class WebBackend implements SpeechBackend {
  /// Creates the backend.
  WebBackend();

  web.SpeechSynthesis get _synth => web.window.speechSynthesis;

  final _events = StreamController<BackendEvent>.broadcast();

  /// The utterances handed to the browser. Chrome lets an utterance nothing
  /// in the page refers to be collected before its `end` fires.
  final _onEngine = <String, web.SpeechSynthesisUtterance>{};

  @override
  Stream<BackendEvent> get events => _events.stream;

  @override
  bool get canPause => true;

  @override
  Future<List<Voice>> voices() async => [
    for (final voice in (await _browserVoices()))
      Voice(
        id: voice.voiceURI,
        name: voice.name,
        language: voice.lang,
        requiresNetwork: !voice.localService,
      ),
  ];

  /// The browser's voices. Chrome loads them after the page, empty until
  /// `voiceschanged`; this waits a moment for that.
  Future<List<web.SpeechSynthesisVoice>> _browserVoices() async {
    var voices = _synth.getVoices().toDart;
    if (voices.isNotEmpty) return voices;
    final changed = Completer<void>();
    _synth.addEventListener(
      'voiceschanged',
      ((web.Event _) {
        if (!changed.isCompleted) changed.complete();
      }).toJS,
    );
    await changed.future.timeout(const Duration(seconds: 2), onTimeout: () {});
    voices = _synth.getVoices().toDart;
    return voices;
  }

  @override
  Future<VoiceAvailability?> languageAvailability(String languageTag) async =>
      null;

  @override
  Future<AudioClaim> activateAudio(SpeakAudio audio) async =>
      AudioClaim.granted;

  @override
  Stream<BackendInterruption> get interruptions => const Stream.empty();

  @override
  Future<bool> isInCall() async => false;

  @override
  Future<void> deactivateAudio() async {}

  /// The web plays no lead-in, so there is nothing to decide.
  @override
  Future<bool> isBluetoothRoute(SpeakAudio audio) async => false;

  @override
  void speak(BackendUtterance utterance) {
    unawaited(_speak(utterance));
  }

  Future<void> _speak(BackendUtterance utterance) async {
    final id = utterance.id;
    final spoken = web.SpeechSynthesisUtterance(utterance.text)
      ..rate = utterance.rate.clamp(0.1, 10)
      ..pitch = utterance.pitch
      ..volume = utterance.volume;
    if (utterance.voiceId case final voiceId?) {
      final voices = await _browserVoices();
      final voice = voices.where((v) => v.voiceURI == voiceId).firstOrNull;
      if (voice == null) {
        _events.add(
          BackendFailed(
            id,
            SpeakError.voiceUnavailable,
            '$voiceId is not here',
          ),
        );
        return;
      }
      spoken
        ..voice = voice
        ..lang = voice.lang;
    } else if (utterance.language case final tag?) {
      spoken.lang = tag;
    }
    spoken
      ..onstart = ((web.Event _) => _events.add(BackendStarted(id))).toJS
      ..onend = ((web.Event _) {
        _onEngine.remove(id);
        _events.add(BackendFinished(id));
      }).toJS
      ..onerror = ((web.SpeechSynthesisErrorEvent event) {
        _onEngine.remove(id);
        _events.add(_failure(id, event.error));
      }).toJS
      ..onboundary = ((web.SpeechSynthesisEvent event) {
        if (event.name != 'word') return;
        final start = event.charIndex;
        // Safari leaves charLength out; the core then finds the word's end.
        final length = (event as JSObject).getProperty<JSAny?>(
          'charLength'.toJS,
        );
        final end = length.isA<JSNumber>()
            ? start + (length as JSNumber).toDartInt
            : start;
        _events.add(BackendProgress(id, start, end));
      }).toJS;
    _onEngine[id] = spoken;
    _synth.speak(spoken);
  }

  static BackendEvent _failure(String id, String error) => switch (error) {
    'canceled' || 'interrupted' => BackendCancelled(id),
    'not-allowed' => BackendFailed(id, SpeakError.notAllowed, error),
    'language-unavailable' => BackendFailed(
      id,
      SpeakError.languageUnavailable,
      error,
    ),
    'voice-unavailable' => BackendFailed(
      id,
      SpeakError.voiceUnavailable,
      error,
    ),
    'synthesis-unavailable' ||
    'audio-hardware' => BackendFailed(id, SpeakError.engineUnavailable, error),
    _ => BackendFailed(id, SpeakError.synthesisFailed, error),
  };

  @override
  Future<void> stop() async => _synth.cancel();

  @override
  Future<void> pause() async => _synth.pause();

  @override
  Future<void> resume() async => _synth.resume();

  @override
  Future<void> dispose() async {
    _synth.cancel();
    _onEngine.clear();
    await _events.close();
  }
}
