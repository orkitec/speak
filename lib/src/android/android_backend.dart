// Android: android.speech.tts.TextToSpeech and audio focus, called from Dart
// through the jnigen bindings in jni_bindings.dart. The one class Dart cannot
// create itself, the UtteranceProgressListener subclass, is in
// android/src/main/java.
import 'dart:async';

import 'package:jni/jni.dart';
import 'package:jni_flutter/jni_flutter.dart';

import '../android_options.dart';
import '../audio.dart';
import '../backend/backend.dart';
import '../outcome.dart';
import '../voice.dart' as api;
import 'jni_bindings.dart';

/// Speaks with Android's TextToSpeech.
///
/// The engine is bound when the backend is created and becomes usable when
/// its `onInit` arrives; everything asked for before then waits for it.
/// Utterances are handed over with QUEUE_FLUSH, one at a time (behind a
/// silent lead-in when the core asks for one): the core keeps the queue. The engine's callbacks come in on a binder thread and
/// are posted to this isolate without blocking it (`$async`).
class AndroidBackend implements SpeechBackend {
  /// Binds the engine named in [options], or the user's default.
  AndroidBackend(AndroidSpeakOptions options) {
    final listener = TextToSpeech$OnInitListener.implement(
      $TextToSpeech$OnInitListener(onInit: _onInit, onInit$async: true),
    );
    final engine = options.engine;
    _tts = engine == null
        ? TextToSpeech(_context, listener)
        : TextToSpeech.new$1(_context, listener, engine.toJString());
  }

  static Context get _context => androidApplicationContext.as(Context.type);

  late final TextToSpeech _tts;
  final _ready = Completer<bool>();
  final _events = StreamController<BackendEvent>.broadcast();

  /// The engine's voices by name, from the last time they were listed.
  Map<String, Voice>? _voices;

  AudioFocusRequest? _focusRequest;
  AudioManager$OnAudioFocusChangeListener? _focusListener;

  void _onInit(int status) {
    if (status != TextToSpeech.SUCCESS) {
      if (!_ready.isCompleted) _ready.complete(false);
      return;
    }
    _tts.setOnUtteranceProgressListener(
      SpeakPlugin$ProgressListener(
        SpeakPlugin$Callbacks.implement(
          $SpeakPlugin$Callbacks(
            onStart: (id) => _report(id, BackendStarted.new),
            onStart$async: true,
            onDone: (id) => _report(id, BackendFinished.new),
            onDone$async: true,
            onStop: (id, _) => _report(id, BackendCancelled.new),
            onStop$async: true,
            onError: (id, code) => _report(
              id,
              (id) => BackendFailed(id, _error(code), 'code $code'),
            ),
            onError$async: true,
            onRangeStart: (id, start, end) =>
                _report(id, (id) => BackendProgress(id, start, end)),
            onRangeStart$async: true,
          ),
        ),
      ).as(UtteranceProgressListener.type),
    );
    if (!_ready.isCompleted) _ready.complete(true);
  }

  void _report(JString? id, BackendEvent Function(String id) event) {
    if (id == null || _events.isClosed) return;
    _events.add(event(id.toDartString(releaseOriginal: true)));
  }

  static SpeakError _error(int code) => switch (code) {
    TextToSpeech.ERROR_NOT_INSTALLED_YET => SpeakError.voiceUnavailable,
    TextToSpeech.ERROR_SERVICE => SpeakError.engineUnavailable,
    _ => SpeakError.synthesisFailed,
  };

  Future<void> _engine() async {
    if (!await _ready.future) {
      throw const SpeakException(
        SpeakError.engineUnavailable,
        'the text-to-speech engine did not start',
      );
    }
  }

  @override
  Stream<BackendEvent> get events => _events.stream;

  @override
  bool get canPause => false;

  @override
  Future<List<api.Voice>> voices() async {
    await _engine();
    final listed = <String, Voice>{};
    final result = <api.Voice>[];
    for (final voice in _tts.voices?.asDart() ?? const <Voice?>{}) {
      if (voice == null) continue;
      final name = voice.name?.toDartString(releaseOriginal: true);
      final language = voice.locale?.toLanguageTag()?.toDartString(
        releaseOriginal: true,
      );
      if (name == null || language == null) continue;
      final features = {
        for (final feature in voice.features?.asDart() ?? const <JString?>{})
          ?feature?.toDartString(releaseOriginal: true),
      };
      listed[name] = voice;
      result.add(
        api.Voice(
          id: name,
          name: name,
          language: language,
          quality: switch (voice.quality) {
            >= 500 => api.VoiceQuality.premium,
            >= 400 => api.VoiceQuality.enhanced,
            >= 300 => api.VoiceQuality.normal,
            > 0 => api.VoiceQuality.low,
            _ => api.VoiceQuality.unknown,
          },
          requiresNetwork: voice.isNetworkConnectionRequired,
          isInstalled: !features.contains('notInstalled'),
        ),
      );
    }
    _voices = listed;
    return result;
  }

  @override
  Future<api.VoiceAvailability?> languageAvailability(String tag) async {
    await _engine();
    final result = _tts.isLanguageAvailable(
      Locale.forLanguageTag(tag.toJString()),
    );
    return switch (result) {
      TextToSpeech.LANG_MISSING_DATA => api.VoiceAvailability.notInstalled,
      TextToSpeech.LANG_NOT_SUPPORTED => api.VoiceAvailability.unsupported,
      _ => api.VoiceAvailability.available,
    };
  }

  @override
  Future<void> activateAudio(SpeakAudio audio) async {
    await _engine();
    final attributes = AudioAttributes$Builder()
        .setUsage(switch (audio.usage) {
          AudioUsage.navigation =>
            AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE,
          AudioUsage.prompt => AudioAttributes.USAGE_ASSISTANT,
          AudioUsage.spokenContent => AudioAttributes.USAGE_MEDIA,
        })!
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)!
        .build();
    _tts.setAudioAttributes(attributes);
    final gain = switch (audio.otherAudio) {
      OtherAudio.mix => null,
      // Android has no "pause spoken audio": a podcast player that would
      // rather pause than be lowered pauses itself on a may-duck request
      // (its own setWillPauseWhenDucked); nothing can make it.
      OtherAudio.duck ||
      OtherAudio.duckAndPauseSpoken ||
      OtherAudio.pauseSpoken => AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK,
      OtherAudio.pause => AudioManager.AUDIOFOCUS_GAIN_TRANSIENT,
    };
    if (gain == null) return;
    // Focus changes need no answer: speech is short, and a call taking the
    // audio stops the engine by itself.
    final listener = _focusListener ??=
        AudioManager$OnAudioFocusChangeListener.implement(
          $AudioManager$OnAudioFocusChangeListener(
            onAudioFocusChange: (_) {},
            onAudioFocusChange$async: true,
          ),
        );
    if (Build$VERSION.SDK_INT >= 26) {
      final request = _focusRequest = AudioFocusRequest$Builder.new$1(gain)
          .setAudioAttributes(attributes)!
          .setOnAudioFocusChangeListener(listener)!
          .build();
      _audioManager.requestAudioFocus(request);
    } else {
      _audioManager.requestAudioFocus$1(
        listener,
        AudioManager.STREAM_MUSIC,
        gain,
      );
    }
  }

  static AudioManager get _audioManager =>
      _context.getSystemService$1(Context.AUDIO_SERVICE)!.as(AudioManager.type);

  @override
  Future<void> deactivateAudio() async {
    final request = _focusRequest;
    final listener = _focusListener;
    _focusRequest = null;
    if (request != null) {
      _audioManager.abandonAudioFocusRequest(request);
    } else if (listener != null) {
      _audioManager.abandonAudioFocus(listener);
    }
  }

  @override
  void speak(BackendUtterance utterance) {
    unawaited(_speak(utterance));
  }

  Future<void> _speak(BackendUtterance utterance) async {
    try {
      await _engine();
      if (utterance.voiceId case final id?) {
        final voice = (_voices ?? {})[id] ?? await _findVoice(id);
        if (voice == null) {
          throw SpeakException(
            SpeakError.voiceUnavailable,
            '$id is not installed',
          );
        }
        _tts.setVoice(voice);
      } else if (utterance.language case final tag?) {
        final locale = Locale.forLanguageTag(tag.toJString());
        final result = _tts.setLanguage(locale);
        if (result == TextToSpeech.LANG_MISSING_DATA) {
          throw SpeakException(
            SpeakError.voiceUnavailable,
            'no voice data for $tag',
          );
        }
        if (result == TextToSpeech.LANG_NOT_SUPPORTED) {
          throw SpeakException(
            SpeakError.languageUnavailable,
            'no voice for $tag',
          );
        }
      }
      _tts
        ..setSpeechRate(utterance.rate)
        ..setPitch(utterance.pitch);
      final params = Bundle()
        ..putFloat(TextToSpeech$Engine.KEY_PARAM_VOLUME, utterance.volume);
      final leadIn = utterance.leadIn.inMilliseconds;
      if (leadIn > 0) {
        // Silence first, under an id of its own that the core ignores, so a
        // Bluetooth link is open by the time the first word is spoken.
        _tts.playSilentUtterance(
          leadIn,
          TextToSpeech.QUEUE_FLUSH,
          '${utterance.id}-lead-in'.toJString(),
        );
      }
      final result = _tts.speak(
        utterance.text.toJString().as(CharSequence.type),
        leadIn > 0 ? TextToSpeech.QUEUE_ADD : TextToSpeech.QUEUE_FLUSH,
        params,
        utterance.id.toJString(),
      );
      if (result != TextToSpeech.SUCCESS) {
        throw const SpeakException(
          SpeakError.synthesisFailed,
          'the engine refused the text',
        );
      }
    } on SpeakException catch (error) {
      _events.add(BackendFailed(utterance.id, error.error, error.message));
    }
  }

  Future<Voice?> _findVoice(String name) async {
    await voices();
    return _voices?[name];
  }

  @override
  Future<void> stop() async {
    if (!_ready.isCompleted || !await _ready.future) return;
    _tts.stop();
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> dispose() async {
    await deactivateAudio();
    if (_ready.isCompleted && await _ready.future) {
      _tts
        ..stop()
        ..shutdown();
    } else {
      unawaited(_ready.future.then((_) => _tts.shutdown()));
    }
    await _events.close();
  }

  /// The installed engines, the user's default first.
  static Future<List<AndroidEngine>> engines() async {
    // Listing engines asks the package manager; the engine itself need not
    // have started.
    final tts = TextToSpeech(_context, null);
    try {
      final fallback = tts.defaultEngine?.toDartString(releaseOriginal: true);
      final engines = [
        for (final info
            in tts.engines?.asDart() ?? const <TextToSpeech$EngineInfo?>[])
          if (info != null)
            AndroidEngine(
              name: info.name?.toDartString(releaseOriginal: true) ?? '',
              label: info.label?.toDartString(releaseOriginal: true) ?? '',
              isDefault: false,
            ),
      ];
      return [
        for (final engine in engines)
          if (engine.name == fallback)
            AndroidEngine(
              name: engine.name,
              label: engine.label,
              isDefault: true,
            ),
        for (final engine in engines)
          if (engine.name != fallback) engine,
      ];
    } finally {
      tts.shutdown();
    }
  }
}
