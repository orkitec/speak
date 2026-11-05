import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:meta/meta.dart';

import 'android_options.dart';
import 'audio.dart';
import 'backend/backend.dart';
import 'backend/unsupported_backend.dart';
import 'ios_options.dart';
import 'language.dart';
import 'outcome.dart';
import 'platform/platform.dart' as platform;
import 'voice.dart';

/// Replaces the platform's backend in this package's own tests.
@internal
BackendFactory? backendFactoryOverride;

/// How long an utterance of [text] at [rate] may take before the engine is
/// presumed stuck: ten seconds for the engine to start, plus 150 ms a
/// character (about twice as slow as any voice speaks at rate 1), scaled by
/// the rate.
@internal
Duration timeoutFor(String text, double rate) =>
    const Duration(seconds: 10) +
    Duration(milliseconds: (150 * text.length / math.max(rate, 0.1)).round());

/// How long [Speak.stop] waits for the engine to confirm before it ends the
/// utterance anyway.
const _stopGrace = Duration(seconds: 1);

/// Text-to-speech for short spoken prompts over other audio.
///
/// One `Speak` is one speaker: it says one utterance at a time, in the order
/// they were asked for, and claims the device's audio only while it speaks.
/// Call it like a function:
///
/// ```dart
/// final speak = Speak();
///
/// await speak('In two hundred metres, turn left.');
/// await speak('Turn left now.', queue: SpeakQueue.interrupt);
/// await speak('Rechts abbiegen.', language: 'de-DE');
/// ```
///
/// The future completes when the text has been spoken, or with how it ended
/// otherwise ([SpeakOutcome]), and with a [SpeakException] when the engine
/// fails. Create one `Speak` for the life of the feature that talks and
/// [dispose] it after.
///
/// iOS, macOS, Android and the web are supported; see [isSupported].
class Speak {
  /// Creates a speaker.
  ///
  /// [audio] says how speech shares the device's audio with other apps.
  /// [android] holds the settings only Android has, such as the engine.
  /// [ios] those only iOS has, such as whether CallKit is asked about calls.
  ///
  /// Nothing is started until the first call that needs the engine, so
  /// creating a `Speak` is cheap.
  factory Speak({
    SpeakAudio audio = SpeakAudio.prompt,
    AndroidSpeakOptions android = const AndroidSpeakOptions(),
    IosSpeakOptions ios = const IosSpeakOptions(),
  }) => Speak._(
    (backendFactoryOverride ?? platform.createBackend)(android, ios),
    audio,
  );

  Speak._(this._backend, this.audio) {
    _events = _backend.events.listen(_onEvent);
    _interruptions = _backend.interruptions.listen(_onInterruption);
  }

  /// Whether this platform can speak: iOS, macOS, Android, and browsers with
  /// the Web Speech API. Everywhere else every call throws
  /// [UnsupportedError].
  static bool get isSupported => platform.isSupported;

  /// The text-to-speech engines installed on an Android device, the one the
  /// user picked in the system settings first; empty on every other
  /// platform. Pass one's name as [AndroidSpeakOptions.engine].
  static Future<List<AndroidEngine>> androidEngines() =>
      platform.androidEngines();

  final SpeechBackend _backend;
  late final StreamSubscription<BackendEvent> _events;
  late final StreamSubscription<BackendInterruption> _interruptions;

  /// How the platform answered the last claim of the audio.
  AudioClaim _claim = AudioClaim.granted;

  /// How speech shares the device's audio with other apps.
  final SpeakAudio audio;

  /// The voice to speak in when a call names neither a voice nor a language.
  Voice? voice;

  /// The language (BCP-47, e.g. `en-GB`) to speak in when a call names
  /// neither a voice nor a language and [voice] is `null`. The best
  /// installed voice for it is used. `null` leaves it to the platform.
  String? language;

  /// Speed when a call does not say: 1 is the platform's normal speed,
  /// 0.5 half as fast, 2 twice as fast. Must be above 0.
  double get rate => _rate;
  set rate(double value) => _rate = _checkRate(value);
  double _rate = 1;

  /// Pitch when a call does not say: 1 is the voice's own, from 0.5 to 2.
  double get pitch => _pitch;
  set pitch(double value) => _pitch = _checkPitch(value);
  double _pitch = 1;

  /// Volume when a call does not say, from 0 to 1, relative to the device's
  /// volume.
  double get volume => _volume;
  set volume(double value) => _volume = _checkVolume(value);
  double _volume = 1;

  final _waiting = <_Job>[];
  _Job? _current;
  bool _paused = false;
  bool _held = false;
  bool _disposed = false;
  int _ids = 0;
  Future<List<Voice>>? _voices;

  /// Whether the device's audio is claimed (or being claimed).
  bool _audioOn = false;
  Future<void> _audioWork = Future<void>.value();

  /// Whether the next utterance on the engine is the first since the audio
  /// was claimed, and so gets the lead-in.
  bool _leadInDue = false;

  /// Gives the audio back when the linger after the last utterance is over.
  Timer? _linger;

  /// Whether an utterance is being spoken right now (not paused).
  bool get isSpeaking => _current != null && !_paused;

  /// Whether [pause] has been called and [resume] has not yet.
  bool get isPaused => _paused;

  /// Says [text], and completes when it has been said.
  ///
  /// The voice is [voice], or the best installed voice for [language], or
  /// else the speaker's own [Speak.voice] and [Speak.language]. A language no
  /// installed voice speaks fails with [SpeakError.languageUnavailable];
  /// check first with [availability].
  ///
  /// [rate], [pitch] and [volume] default to the speaker's own.
  ///
  /// [queue] decides what happens to anything already being said: by
  /// default the text waits its turn; [SpeakQueue.interrupt] cuts in.
  ///
  /// With [expireAfter], text still waiting after that long is dropped
  /// unsaid and completes as [SpeakOutcome.expired]; a distance announcement
  /// that waited too long is about a road already ridden.
  ///
  /// [onProgress] hears which part of [text] is being spoken, usually word
  /// by word; how finely depends on the platform (see the README). Nothing
  /// is reported while paused: what the engine reports meanwhile is
  /// reported on [resume].
  ///
  /// ```dart
  /// final outcome = await speak('Turn left now.', queue: SpeakQueue.interrupt);
  /// if (outcome == SpeakOutcome.interrupted) { /* something cut in */ }
  /// ```
  Future<SpeakOutcome> call(
    String text, {
    Voice? voice,
    String? language,
    double? rate,
    double? pitch,
    double? volume,
    SpeakQueue queue = SpeakQueue.append,
    Duration? expireAfter,
    void Function(SpeechProgress progress)? onProgress,
  }) {
    _checkUsable();
    final job = _Job(
      text,
      voice: voice,
      language: language,
      rate: rate == null ? _rate : _checkRate(rate),
      pitch: pitch == null ? _pitch : _checkPitch(pitch),
      volume: volume == null ? _volume : _checkVolume(volume),
      onProgress: onProgress,
    );
    if (text.isEmpty) return Future.value(SpeakOutcome.completed);
    if (queue == SpeakQueue.interrupt) {
      _dropWaiting();
      _waiting.add(job);
      _paused = false;
      final current = _current;
      if (current != null) unawaited(_interrupt(current));
    } else {
      _waiting.add(job);
    }
    if (expireAfter != null) {
      job.expiry = Timer(expireAfter, () {
        if (_waiting.remove(job)) job.end(SpeakOutcome.expired);
      });
    }
    _pump();
    return job.done.future;
  }

  /// The voices installed for this speaker's engine, best first, only those
  /// speaking [language] when given (`en` for every English voice, `en-GB`
  /// for British ones first).
  ///
  /// Asks the platform every time, so a voice downloaded while the app runs
  /// shows up; the voice a call picks for a language comes from the list
  /// fetched last.
  Future<List<Voice>> voices({String? language}) async {
    _checkUsable();
    final fetched = _backend.voices();
    _voices = fetched;
    final all = await fetched;
    final matching = [
      for (final voice in all)
        if (language == null || languageMatch(language, voice.language) > 0)
          voice,
    ];
    int score(Voice v) =>
        language == null ? 0 : languageMatch(language, v.language);
    return matching..sort((a, b) {
      for (final (x, y) in [
        (a.isInstalled ? 1 : 0, b.isInstalled ? 1 : 0),
        (score(a), score(b)),
        (a.requiresNetwork ? 0 : 1, b.requiresNetwork ? 0 : 1),
        (a.quality.index, b.quality.index),
      ]) {
        if (x != y) return y.compareTo(x);
      }
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.id.compareTo(b.id);
    });
  }

  /// Whether text in [language] (BCP-47) can be spoken right now, so an app
  /// can tell the user a voice is missing before it speaks.
  ///
  /// ```dart
  /// if (await speak.availability('de-DE') == VoiceAvailability.notInstalled) {
  ///   // Ask the user to download a German voice.
  /// }
  /// ```
  ///
  /// For one voice, see [Voice.availability].
  Future<VoiceAvailability> availability(String language) async {
    _checkUsable();
    final fromVoices = availabilityFor(await voices(), language);
    if (fromVoices == VoiceAvailability.available) return fromVoices;
    final hint = await _backend.languageAvailability(
      normalizeLanguageTag(language),
    );
    return hint ?? fromVoices;
  }

  /// Stops speaking: what is being said is cut off and what is waiting is
  /// dropped, all completing as [SpeakOutcome.interrupted]. Also ends a
  /// [pause]. Completes once the engine has gone quiet.
  Future<void> stop() async {
    if (_disposed) return;
    _dropWaiting();
    _paused = false;
    final current = _current;
    if (current != null) await _interrupt(current);
    // No linger after a stop: nothing more is coming.
    _releaseAudioIfIdle(now: true);
    await _audioWork;
  }

  /// Pauses speaking, at the end of a word where the platform can, until
  /// [resume]. Text asked for meanwhile waits. The device's audio is given
  /// back while paused, unless held ([holdAudio]).
  ///
  /// iOS, macOS and the web pause the engine itself. Android's engine cannot
  /// pause: there the utterance is stopped and [resume] speaks it again from
  /// the start of the last word the engine reported (from the beginning when
  /// it reported none).
  Future<void> pause() async {
    _checkUsable();
    if (_paused) return;
    _paused = true;
    final job = _current;
    if (job != null && job.backendId != null) {
      job.pauseTimeout();
      if (_backend.canPause) {
        await _guard(_backend.pause);
      } else {
        job.restartFrom = job.lastWordStart ?? job.offset;
        job.backendId = null;
        await _guard(_backend.stop);
      }
    }
    if (_paused) _releaseAudioIfIdle(now: true);
    await _audioWork;
  }

  /// Continues after [pause].
  Future<void> resume() async {
    _checkUsable();
    if (!_paused) return;
    _paused = false;
    final job = _current;
    if (job == null) {
      _pump();
      return;
    }
    // Paused before it reached the engine: [_start] carries on by itself
    // unless it had already got as far as the engine.
    if (job.backendId == null && job.restartFrom == null && !job.ready) return;
    await _claimAudio();
    if (_current != job || _paused) return;
    final from = job.restartFrom ?? (job.backendId == null ? 0 : null);
    if (from != null) {
      job.restartFrom = null;
      _startOnEngine(job, from);
    } else {
      _releaseHeldProgress(job);
      job.resumeTimeout(() => _timedOut(job));
      await _guard(_backend.resume);
    }
  }

  /// Claims the device's audio now, as [audio] says, and keeps it claimed
  /// between utterances until [releaseAudio], instead of giving it back after
  /// each.
  ///
  /// For a stretch of many prompts close together, such as a guided ride on
  /// Bluetooth headphones, where giving the audio back between prompts tears
  /// the Bluetooth stream down and the next prompt loses its first syllable.
  /// Sounds the app plays itself in between (a chime, a silent lead-in that
  /// wakes the headphones) play in the same audio session.
  ///
  /// Other audio stays ducked or paused for as long as it is held, so hold
  /// it with [OtherAudio.mix] or [OtherAudio.pauseSpoken] rather than
  /// [OtherAudio.duck] if music should play normally in between.
  Future<void> holdAudio() async {
    _checkUsable();
    _held = true;
    await _claimAudio();
  }

  /// Ends [holdAudio]: the audio is given back now, or after the utterance
  /// being spoken.
  Future<void> releaseAudio() async {
    if (!_held) return;
    _held = false;
    _releaseAudioIfIdle(now: true);
    await _audioWork;
  }

  /// Stops speaking, gives the device's audio back and releases the engine.
  /// The speaker cannot be used afterwards.
  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _held = false;
    _releaseAudioIfIdle(now: true);
    _disposed = true;
    await _audioWork;
    // Not awaited: a broadcast stream answers a cancel with a future from
    // the root zone, which a caller's own zone (fake time in tests) may never
    // see complete.
    unawaited(_events.cancel());
    unawaited(_interruptions.cancel());
    await _guard(_backend.dispose);
  }

  void _checkUsable() {
    if (_disposed) throw StateError('This Speak has been disposed.');
    if (_backend is UnsupportedBackend) {
      throw UnsupportedError(
        'speak supports iOS, macOS, Android and the web; '
        'check Speak.isSupported first.',
      );
    }
  }

  static double _checkRate(double value) {
    if (!(value > 0) || value > 10) {
      throw ArgumentError.value(
        value,
        'rate',
        'must be above 0 and at most 10',
      );
    }
    return value;
  }

  static double _checkPitch(double value) {
    if (!(value >= 0.5 && value <= 2)) {
      throw ArgumentError.value(value, 'pitch', 'must be from 0.5 to 2');
    }
    return value;
  }

  static double _checkVolume(double value) {
    if (!(value >= 0 && value <= 1)) {
      throw ArgumentError.value(value, 'volume', 'must be from 0 to 1');
    }
    return value;
  }

  void _dropWaiting() {
    final dropped = List.of(_waiting);
    _waiting.clear();
    for (final job in dropped) {
      job.end(SpeakOutcome.interrupted);
    }
  }

  /// Starts the next utterance when nothing is being spoken.
  void _pump() {
    if (_current != null || _paused || _waiting.isEmpty || _disposed) return;
    final job = _current = _waiting.removeAt(0);
    job.expiry?.cancel();
    unawaited(_start(job));
  }

  Future<void> _start(_Job job) async {
    try {
      // Nothing is said while a call has the audio, and nothing is kept for
      // after it: what was due then is out of date by the end of the call.
      // Only what the platform says now counts, never a remembered
      // interruption: iOS does not promise an end for every beginning, and a
      // flag left set would keep the rest of a ride silent.
      if (_skipDuringCalls && await _inCall()) {
        if (_current == job) _finish(job, outcome: SpeakOutcome.blocked);
        return;
      }
      final (voiceId, language) = await _resolveVoice(job);
      if (_current != job || job.stopRequested) return;
      job
        ..voiceId = voiceId
        ..languageTag = language
        ..ready = true;
      final claim = await _claimAudio();
      if (_current != job || job.stopRequested || _paused) return;
      if (claim == AudioClaim.refused && _skipDuringCalls) {
        _finish(job, outcome: SpeakOutcome.blocked);
        return;
      }
      _startOnEngine(job, 0);
    } on SpeakException catch (error) {
      if (_current == job) _finish(job, error: error);
    }
  }

  Future<(String?, String?)> _resolveVoice(_Job job) async {
    final chosen = job.voice ?? (job.language == null ? voice : null);
    if (chosen != null) {
      if (!chosen.isInstalled) {
        throw SpeakException(
          SpeakError.voiceUnavailable,
          '${chosen.id} is not installed',
        );
      }
      return (chosen.id, chosen.language);
    }
    final tag = job.language ?? language;
    if (tag == null) return (null, null);
    final installed = await (_voices ??= _backend.voices());
    if (installed.isEmpty) return (null, normalizeLanguageTag(tag));
    final best = bestVoiceFor(installed, tag);
    if (best == null) {
      throw SpeakException(
        SpeakError.languageUnavailable,
        'no installed voice speaks $tag',
      );
    }
    return (best.id, best.language);
  }

  void _startOnEngine(_Job job, int from) {
    final id = job.backendId = 'speak-${++_ids}';
    job.offset = from;
    final rest = job.text.substring(from);
    final leadIn = _leadInDue ? audio.leadIn : Duration.zero;
    _leadInDue = false;
    try {
      _backend.speak(
        BackendUtterance(
          id: id,
          text: rest,
          voiceId: job.voiceId,
          language: job.languageTag,
          rate: job.rate,
          pitch: job.pitch,
          volume: job.volume,
          leadIn: leadIn,
        ),
      );
    } on Object catch (error) {
      _finish(
        job,
        error: error is SpeakException
            ? error
            : SpeakException(SpeakError.synthesisFailed, '$error'),
      );
      return;
    }
    // The lead-in is the engine's silence, not the utterance's time.
    job.startTimeout(timeoutFor(rest, job.rate) + leadIn, () => _timedOut(job));
  }

  void _timedOut(_Job job) {
    if (_current != job) return;
    // Ended before the engine is stopped, so what the engine says about the
    // stop is not taken for this utterance's outcome.
    _finish(
      job,
      error: const SpeakException(
        SpeakError.timeout,
        'the engine did not finish in time',
      ),
    );
    unawaited(_guard(_backend.stop));
  }

  Future<void> _interrupt(_Job job) async {
    job.stopRequested = true;
    if (job.backendId == null) {
      // Not on the engine: waiting for its voice, its audio, or a resume.
      if (_current == job) _finish(job, outcome: SpeakOutcome.interrupted);
      return;
    }
    await _guard(_backend.stop);
    await Future.any([job.done.future, Future<void>.delayed(_stopGrace)]);
    if (_current == job) _finish(job, outcome: SpeakOutcome.interrupted);
  }

  void _onEvent(BackendEvent event) {
    final job = _current;
    if (job == null || event.id != job.backendId) return;
    switch (event) {
      case BackendStarted():
        break;
      case BackendProgress(:final start, :final end):
        // An engine can report words it has prepared but not played: none
        // is reported while paused, and the held ones on resume.
        if (_paused) {
          job.heldProgress.add((start, end));
        } else {
          _progress(job, start, end);
        }
      case BackendFinished():
        if (!job.stopRequested) _releaseHeldProgress(job);
        _finish(
          job,
          outcome: job.stopRequested
              ? SpeakOutcome.interrupted
              : SpeakOutcome.completed,
        );
      case BackendCancelled():
        job.stopRequested
            ? _finish(job, outcome: SpeakOutcome.interrupted)
            : _finish(
                job,
                error: const SpeakException(
                  SpeakError.synthesisFailed,
                  'the engine cancelled the utterance',
                ),
              );
      case BackendFailed(:final error, :final message):
        job.stopRequested
            ? _finish(job, outcome: SpeakOutcome.interrupted)
            : _finish(job, error: SpeakException(error, message));
    }
  }

  /// Reports the progress held while paused, in order.
  void _releaseHeldProgress(_Job job) {
    final held = [...job.heldProgress];
    job.heldProgress.clear();
    for (final (start, end) in held) {
      _progress(job, start, end);
    }
  }

  void _progress(_Job job, int start, int end) {
    final text = job.text;
    int within(int at) => at < 0 ? 0 : (at > text.length ? text.length : at);
    final from = within(job.offset + start);
    var to = within(job.offset + end);
    if (to <= from) {
      // Only the start was reported: the word runs to the next space.
      final space = text.indexOf(RegExp(r'\s'), from);
      to = space == -1 ? text.length : space;
    }
    job.lastWordStart = from;
    final listener = job.onProgress;
    if (listener == null) return;
    // In the caller's zone, where an error in the listener belongs too.
    job.zone.runUnaryGuarded(listener, SpeechProgress(text, from, to));
  }

  void _finish(_Job job, {SpeakOutcome? outcome, SpeakException? error}) {
    if (_current != job) return;
    _current = null;
    job.cancelTimeout();
    if (error != null) {
      job.fail(error);
    } else {
      job.end(outcome!);
    }
    _releaseAudioIfIdle();
    _pump();
  }

  /// Claims the audio unless it is claimed already, and says how the
  /// platform answered.
  Future<AudioClaim> _claimAudio() async {
    _linger?.cancel();
    _linger = null;
    if (!_audioOn) {
      _audioOn = true;
      _leadInDue = audio.leadIn > Duration.zero;
      final askRoute = _leadInDue && audio.leadInOnBluetoothOnly;
      _audioWork = _audioWork.then((_) async {
        var claim = AudioClaim.granted;
        try {
          claim = await _backend.activateAudio(audio);
        } on Object {
          // A claim that fails outright must not keep the text from being
          // spoken; only a refusal says another app has the audio.
        }
        _claim = claim;
        if (claim != AudioClaim.granted) {
          // Not ours: there is nothing to give back, and the next utterance
          // asks again. Refused means it is not said; unclaimed that it is
          // said without the audio claimed.
          _audioOn = false;
          if (claim == AudioClaim.refused) return;
        }
        // Asked once the audio is claimed: the category decides the route.
        if (askRoute && (_audioOn || claim == AudioClaim.unclaimed)) {
          _leadInDue = await _onBluetooth();
        }
      });
      await _audioWork;
      return _claim;
    }
    await _audioWork;
    return AudioClaim.granted;
  }

  bool get _skipDuringCalls => audio.duringCalls == SpeakDuringCalls.skip;

  /// Whether a call is going on; `false` when the platform cannot say.
  Future<bool> _inCall() async {
    try {
      return await _backend.isInCall();
    } on Object {
      return false;
    }
  }

  /// Another app taking the audio (a call, Siri, an alarm), or giving it
  /// back. A beginning cuts off what is being said; whether the next
  /// utterance may speak is asked afresh then ([_inCall], the claim).
  void _onInterruption(BackendInterruption interruption) {
    if (interruption == BackendInterruption.ended) return;
    // The platform took the audio: the claim is forgotten, not given back,
    // and the next utterance after the interruption claims it afresh.
    _linger?.cancel();
    _linger = null;
    _audioOn = false;
    _leadInDue = false;
    _paused = false;
    _dropWaiting();
    final job = _current;
    if (job == null) return;
    job.stopRequested = true;
    // The engine may still be speaking (or about to, after a lead-in).
    if (job.backendId != null) unawaited(_guard(_backend.stop));
    _finish(job, outcome: SpeakOutcome.interrupted);
  }

  /// Gives the audio back when nothing is being said: after the linger, or
  /// [now].
  void _releaseAudioIfIdle({bool now = false}) {
    final busy = !_paused && (_current != null || _waiting.isNotEmpty);
    if (!_audioOn || _held || busy) return;
    if (!now && audio.linger > Duration.zero) {
      _linger ??= Timer(audio.linger, () {
        _linger = null;
        _releaseAudioIfIdle(now: true);
      });
      return;
    }
    _linger?.cancel();
    _linger = null;
    _audioOn = false;
    _leadInDue = false;
    _audioWork = _audioWork.then((_) => _guard(_backend.deactivateAudio));
  }

  /// Whether the claimed audio goes to Bluetooth; `true` when the platform
  /// cannot say, because a clipped first word is worse than a short wait.
  Future<bool> _onBluetooth() async {
    try {
      return await _backend.isBluetoothRoute(audio);
    } on Object {
      return true;
    }
  }

  static Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on Object {
      // The engine's own trouble surfaces through its events; a failed
      // session or focus change is not worth failing speech for.
    }
  }
}

class _Job {
  _Job(
    this.text, {
    required this.voice,
    required this.language,
    required this.rate,
    required this.pitch,
    required this.volume,
    required this.onProgress,
  });

  final String text;
  final Voice? voice;
  final String? language;
  final double rate;
  final double pitch;
  final double volume;
  final void Function(SpeechProgress)? onProgress;

  final done = Completer<SpeakOutcome>();
  final zone = Zone.current;
  Timer? expiry;

  String? voiceId;
  String? languageTag;

  /// Whether the voice is resolved and only the engine is still to come.
  bool ready = false;

  /// The engine's id for the part being spoken; `null` while not on the
  /// engine.
  String? backendId;

  /// Where in [text] the part on the engine starts.
  int offset = 0;

  /// Where the last reported word starts, in [text].
  int? lastWordStart;

  /// Word progress the engine reported while paused, reported on resume.
  final heldProgress = <(int, int)>[];

  /// Where to start again on resume, after a pause the engine could not do.
  int? restartFrom;

  bool stopRequested = false;

  Timer? _timeout;

  /// When the running stretch of the timeout started; `null` while paused.
  DateTime? _since;

  /// What is left of the allowance at [_since].
  Duration _allowed = Duration.zero;

  void startTimeout(Duration allowed, void Function() onTimeout) {
    cancelTimeout();
    _allowed = allowed;
    _since = clock.now();
    _timeout = Timer(allowed, onTimeout);
  }

  /// Stops the timeout's clock: time spent paused does not count.
  void pauseTimeout() {
    _timeout?.cancel();
    _timeout = null;
    final since = _since;
    if (since != null) _allowed -= clock.now().difference(since);
    _since = null;
  }

  void resumeTimeout(void Function() onTimeout) {
    final left = _allowed.isNegative ? Duration.zero : _allowed;
    startTimeout(left, onTimeout);
  }

  void cancelTimeout() {
    _timeout?.cancel();
    _timeout = null;
  }

  void end(SpeakOutcome outcome) {
    expiry?.cancel();
    if (!done.isCompleted) done.complete(outcome);
  }

  void fail(SpeakException error) {
    expiry?.cancel();
    if (!done.isCompleted) done.completeError(error);
  }
}
