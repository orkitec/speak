import 'dart:async';

import 'package:speak/speak.dart';
import 'package:speak/src/backend/backend.dart';

/// What a fake engine does when it is told to stop.
enum StopReply {
  /// Reports the utterance cancelled, like iOS.
  cancel,

  /// Reports the utterance finished, like macOS.
  finish,

  /// Says nothing at all.
  silent,
}

/// A speech engine driven by the test: nothing is reported until the test
/// says so, except the reply to [stop] chosen by [stopReply].
class FakeBackend implements SpeechBackend {
  FakeBackend({
    this.canPause = true,
    this.stopReply = StopReply.cancel,
    List<Voice>? voices,
  }) : installed = voices ?? [];

  @override
  final bool canPause;

  StopReply stopReply;

  /// What [voices] returns.
  List<Voice> installed;

  /// What [languageAvailability] returns.
  VoiceAvailability? languageHint;

  /// Thrown by [speak] when set.
  Object? speakError;

  /// Thrown by [activateAudio] when set.
  Object? activateError;

  /// What [isBluetoothRoute] answers; Bluetooth unless a test says not.
  bool bluetooth = true;

  /// Thrown by [isBluetoothRoute] when set.
  Object? routeError;

  /// How often [isBluetoothRoute] was asked.
  int routeQueries = 0;

  /// Called whenever [isBluetoothRoute] is asked.
  void Function()? onRouteQuery;

  /// Every call, in order: `activate:<otherAudio>`, `deactivate`,
  /// `speak:<text>` (`speak:<text>+<lead-in>ms` with a lead-in), `stop`,
  /// `pause`, `resume`, `dispose`.
  final log = <String>[];

  /// Every utterance handed over, in order.
  final spoken = <BackendUtterance>[];

  final _events = StreamController<BackendEvent>.broadcast(sync: true);

  /// The utterance the engine is speaking, if any.
  BackendUtterance? get current => _current;
  BackendUtterance? _current;

  int voiceCalls = 0;

  /// How long [voices] takes to answer, as a system busy setting up its
  /// voices may.
  Duration voicesDelay = Duration.zero;

  @override
  Stream<BackendEvent> get events => _events.stream;

  @override
  Future<List<Voice>> voices() async {
    voiceCalls++;
    if (voicesDelay > Duration.zero) await Future<void>.delayed(voicesDelay);
    return installed;
  }

  @override
  Future<VoiceAvailability?> languageAvailability(String languageTag) async =>
      languageHint;

  /// What [activateAudio] answers.
  AudioClaim claim = AudioClaim.granted;

  /// What [isInCall] answers.
  bool inCall = false;

  /// How often [isInCall] was asked.
  int callQueries = 0;

  final _interruptions = StreamController<BackendInterruption>.broadcast(
    sync: true,
  );

  @override
  Future<AudioClaim> activateAudio(SpeakAudio audio) async {
    log.add('activate:${audio.otherAudio.name}');
    if (activateError case final error?) throw error;
    return claim;
  }

  @override
  Stream<BackendInterruption> get interruptions => _interruptions.stream;

  /// Thrown by [isInCall] when set.
  Object? callError;

  @override
  Future<bool> isInCall() async {
    callQueries++;
    if (callError case final error?) throw error;
    return inCall;
  }

  /// Plays a call (or Siri, an alarm) taking the audio: the engine stops
  /// what it says without reporting anything, as iOS does.
  void interruptionBegins() {
    _current = null;
    _interruptions.add(BackendInterruption.began);
  }

  /// Plays the call ending.
  void interruptionEnds() => _interruptions.add(BackendInterruption.ended);

  /// Plays a call: the audio taken, and the call there to be asked about.
  void callBegins() {
    inCall = true;
    interruptionBegins();
  }

  /// Plays the call hanging up.
  void callEnds() {
    inCall = false;
    interruptionEnds();
  }

  @override
  Future<void> deactivateAudio() async => log.add('deactivate');

  @override
  Future<bool> isBluetoothRoute(SpeakAudio audio) async {
    routeQueries++;
    onRouteQuery?.call();
    if (routeError case final error?) throw error;
    return bluetooth;
  }

  @override
  void speak(BackendUtterance utterance) {
    final leadIn = utterance.leadIn;
    log.add(
      'speak:${utterance.text}'
      '${leadIn > Duration.zero ? '+${leadIn.inMilliseconds}ms' : ''}',
    );
    if (speakError case final error?) throw error;
    spoken.add(utterance);
    _current = utterance;
  }

  @override
  Future<void> stop() async {
    log.add('stop');
    final current = _current;
    if (current == null) return;
    _current = null;
    switch (stopReply) {
      case StopReply.cancel:
        _events.add(BackendCancelled(current.id));
      case StopReply.finish:
        _events.add(BackendFinished(current.id));
      case StopReply.silent:
        break;
    }
  }

  @override
  Future<void> pause() async => log.add('pause');

  @override
  Future<void> resume() async => log.add('resume');

  @override
  Future<void> dispose() async => log.add('dispose');

  String get _id => _current?.id ?? spoken.last.id;

  void start([String? id]) => _events.add(BackendStarted(id ?? _id));

  void progress(int start, int end, [String? id]) =>
      _events.add(BackendProgress(id ?? _id, start, end));

  /// Reports the current utterance finished.
  void finish([String? id]) {
    final which = id ?? _id;
    if (_current?.id == which) _current = null;
    _events.add(BackendFinished(which));
  }

  void cancel([String? id]) {
    final which = id ?? _id;
    if (_current?.id == which) _current = null;
    _events.add(BackendCancelled(which));
  }

  void fail(SpeakError error, [String? id]) {
    final which = id ?? _id;
    if (_current?.id == which) _current = null;
    _events.add(BackendFailed(which, error, 'fake'));
  }
}

Voice fakeVoice(
  String id,
  String language, {
  VoiceQuality quality = VoiceQuality.normal,
  bool network = false,
  bool installed = true,
}) => Voice(
  id: id,
  name: id,
  language: language,
  quality: quality,
  requiresNetwork: network,
  isInstalled: installed,
);
