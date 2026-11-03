// iOS and macOS: AVSpeechSynthesizer and AVAudioSession, called from Dart
// through the ffigen bindings in av_bindings.dart.
import 'dart:async';
import 'dart:io';

import 'package:objective_c/objective_c.dart' as objc;

import '../audio.dart';
import '../backend/backend.dart';
import '../outcome.dart';
import '../voice.dart';
import 'av_bindings.dart';

/// Speaks with AVSpeechSynthesizer.
///
/// The synthesizer queues utterances itself, but the core hands it one at a
/// time, so its queue never holds more than one. The delegate's callbacks
/// arrive as listener blocks: posted to this isolate from whichever thread
/// AVFoundation calls them on, never blocking it.
class DarwinBackend implements SpeechBackend {
  /// Creates the synthesizer and its delegate.
  DarwinBackend() {
    _delegate = AVSpeechSynthesizerDelegate$Builder.implementAsListener(
      speechSynthesizer_didStartSpeechUtterance_: (_, utterance) =>
          _report(utterance, BackendStarted.new),
      speechSynthesizer_didFinishSpeechUtterance_: (_, utterance) =>
          _report(utterance, BackendFinished.new, last: true),
      speechSynthesizer_didCancelSpeechUtterance_: (_, utterance) =>
          _report(utterance, BackendCancelled.new, last: true),
      speechSynthesizer_willSpeakRangeOfSpeechString_utterance_:
          (_, range, utterance) => _report(
            utterance,
            (id) => BackendProgress(
              id,
              range.location,
              range.location + range.length,
            ),
          ),
    );
    // The synthesizer holds its delegate weakly; this object keeps it alive.
    _synthesizer.delegate = _delegate;
  }

  final _synthesizer = AVSpeechSynthesizer();
  late final AVSpeechSynthesizerDelegate _delegate;
  final _events = StreamController<BackendEvent>.broadcast();

  /// The utterances on the synthesizer, by object address, with our id.
  /// Holding the utterance keeps its address from being reused.
  final _onEngine = <int, (String, AVSpeechUtterance)>{};

  @override
  Stream<BackendEvent> get events => _events.stream;

  @override
  bool get canPause => true;

  void _report(
    AVSpeechUtterance utterance,
    BackendEvent Function(String id) event, {
    bool last = false,
  }) {
    final address = utterance.ref.pointer.address;
    final entry = last ? _onEngine.remove(address) : _onEngine[address];
    if (entry != null && !_events.isClosed) _events.add(event(entry.$1));
  }

  @override
  Future<List<Voice>> voices() async => [
    for (final object in AVSpeechSynthesisVoice.speechVoices().asDart())
      _voice(AVSpeechSynthesisVoice.as(object)),
  ];

  static Voice _voice(AVSpeechSynthesisVoice voice) {
    final id = voice.identifier.toDartString();
    return Voice(
      id: id,
      name: voice.name.toDartString(),
      language: voice.language.toDartString(),
      quality: _isNovelty(id)
          ? VoiceQuality.low
          : switch (voice.quality) {
              AVSpeechSynthesisVoiceQuality
                  .AVSpeechSynthesisVoiceQualityDefault =>
                VoiceQuality.normal,
              AVSpeechSynthesisVoiceQuality
                  .AVSpeechSynthesisVoiceQualityEnhanced =>
                VoiceQuality.enhanced,
              AVSpeechSynthesisVoiceQuality
                  .AVSpeechSynthesisVoiceQualityPremium =>
                VoiceQuality.premium,
            },
      gender: switch (voice.gender) {
        AVSpeechSynthesisVoiceGender.AVSpeechSynthesisVoiceGenderFemale =>
          VoiceGender.female,
        AVSpeechSynthesisVoiceGender.AVSpeechSynthesisVoiceGenderMale =>
          VoiceGender.male,
        _ => VoiceGender.unknown,
      },
    );
  }

  /// Apple grades its novelty voices (Bells, Zarvox, ...) and the Eloquence
  /// voices (Eddy, Flo, ...) "default", like Samantha; ranked like her, they
  /// would be picked for a language just as often.
  static bool _isNovelty(String id) =>
      id.startsWith('com.apple.speech.synthesis.voice.') ||
      id.startsWith('com.apple.eloquence.');

  @override
  Future<VoiceAvailability?> languageAvailability(String languageTag) async =>
      null;

  @override
  Future<void> activateAudio(SpeakAudio audio) async {
    if (!Platform.isIOS) return;
    final session = AVAudioSession.sharedInstance()
      ..setCategory(
        AVAudioSessionCategoryPlayback,
        mode: switch (audio.usage) {
          AudioUsage.navigation ||
          AudioUsage.prompt => AVAudioSessionModeVoicePrompt,
          AudioUsage.spokenContent => AVAudioSessionModeSpokenAudio,
        },
        options: switch (audio.otherAudio) {
          OtherAudio.mix => _mix,
          OtherAudio.duck => _mix | _duck,
          OtherAudio.pauseSpoken => _mix | _pauseSpoken,
          OtherAudio.pause => 0,
        },
      );
    session.setActive(true, withOptions: 0);
  }

  static const _mix =
      AVAudioSessionCategoryOptions.AVAudioSessionCategoryOptionMixWithOthers;
  static const _duck =
      AVAudioSessionCategoryOptions.AVAudioSessionCategoryOptionDuckOthers;
  static const _pauseSpoken = AVAudioSessionCategoryOptions
      .AVAudioSessionCategoryOptionInterruptSpokenAudioAndMixWithOthers;

  @override
  Future<void> deactivateAudio() async {
    if (!Platform.isIOS) return;
    // Others are told, so ducked music comes back up and a paused podcast
    // carries on.
    AVAudioSession.sharedInstance().setActive(
      false,
      withOptions: AVAudioSessionSetActiveOptions
          .AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation,
    );
  }

  @override
  void speak(BackendUtterance utterance) {
    final spoken = AVSpeechUtterance.speechUtteranceWithString(
      utterance.text.toNSString(),
    );
    if (utterance.voiceId case final id?) {
      final voice = AVSpeechSynthesisVoice.voiceWithIdentifier(id.toNSString());
      if (voice == null) {
        throw SpeakException(
          SpeakError.voiceUnavailable,
          '$id is not installed',
        );
      }
      spoken.voice = voice;
    } else if (utterance.language case final tag?) {
      final voice = AVSpeechSynthesisVoice.voiceWithLanguage(tag.toNSString());
      if (voice == null) {
        throw SpeakException(
          SpeakError.languageUnavailable,
          'no voice for $tag',
        );
      }
      spoken.voice = voice;
    }
    // The utterance rate runs from a minimum to a maximum with the normal
    // speed in between (0, 0.5 and 1 today); rate 1 is the normal speed.
    spoken
      ..rate = (AVSpeechUtteranceDefaultSpeechRate * utterance.rate)
          .clamp(
            AVSpeechUtteranceMinimumSpeechRate,
            AVSpeechUtteranceMaximumSpeechRate,
          )
          .toDouble()
      ..pitchMultiplier = utterance.pitch
      ..volume = utterance.volume;
    _onEngine[spoken.ref.pointer.address] = (utterance.id, spoken);
    _synthesizer.speakUtterance(spoken);
  }

  @override
  Future<void> stop() async {
    _synthesizer.stopSpeakingAtBoundary(
      AVSpeechBoundary.AVSpeechBoundaryImmediate,
    );
  }

  @override
  Future<void> pause() async {
    _synthesizer.pauseSpeakingAtBoundary(AVSpeechBoundary.AVSpeechBoundaryWord);
  }

  @override
  Future<void> resume() async {
    _synthesizer.continueSpeaking();
  }

  @override
  Future<void> dispose() async {
    await stop();
    _synthesizer.delegate = null;
    _onEngine.clear();
    await _events.close();
  }
}
