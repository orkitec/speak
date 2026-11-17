// The audio session and the lead-in player, driven from a helper isolate.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:objective_c/objective_c.dart' as objc;

import 'av_bindings.dart';

/// The session's mode, as a value that can cross between isolates; the mode
/// strings themselves are Objective-C objects.
enum SessionMode {
  /// `AVAudioSessionModeVoicePrompt`.
  voicePrompt,

  /// `AVAudioSessionModeSpokenAudio`.
  spokenAudio,
}

/// Everything that sets the audio session up or tears it down, on a thread
/// that is not the main thread.
///
/// Setting the category and activating or deactivating the session can block
/// for a noticeable moment (a Bluetooth route has to be set up or torn
/// down), and iOS reports each such call made on the main thread as a hang
/// risk, which Xcode shows as a runtime issue (orkitec/speak#1). The app's
/// Dart code runs on the main thread. So these calls are made on a helper
/// isolate's thread, one isolate for the backend's life, in the order they
/// were asked for. The lead-in's player lives there too: starting an
/// `AVAudioPlayer` activates the session itself.
///
/// Only plain values cross: an Objective-C object belongs to the isolate that
/// made it.
class AudioThread {
  AudioThread._(this._isolate, this._commands, this._replies, this._pending);

  /// Starts the helper isolate.
  static Future<AudioThread> start() async {
    final replies = ReceivePort('speak audio replies');
    final ready = Completer<SendPort>();
    final pending = <int, Completer<Object?>>{};
    replies.listen((message) {
      if (message is SendPort) {
        ready.complete(message);
      } else if (message case (final int id, final Object? result)) {
        pending.remove(id)?.complete(result);
      }
    });
    final isolate = await Isolate.spawn(
      _serve,
      replies.sendPort,
      debugName: 'speak audio session',
    );
    return AudioThread._(isolate, await ready.future, replies, pending);
  }

  final Isolate _isolate;
  final SendPort _commands;
  final ReceivePort _replies;
  final Map<int, Completer<Object?>> _pending;
  int _next = 0;
  bool _closed = false;

  Future<Object?> _ask(Object command) {
    if (_closed) return Future.value();
    final id = _next++;
    final reply = _pending[id] = Completer<Object?>();
    _commands.send((id, command));
    return reply.future;
  }

  /// Sets the category and activates the session; false if iOS refused.
  Future<bool> claim(SessionMode mode, int options) async =>
      await _ask(('claim', mode.index, options)) == true;

  /// Deactivates the session and tells other apps' audio to carry on.
  Future<void> release() => _ask(('release',));

  /// Plays [wav] (the lead-in's silence), replacing any being played.
  Future<void> play(Uint8List wav) =>
      _ask(('play', TransferableTypedData.fromList([wav])));

  /// Stops the lead-in's silence, if any is playing.
  Future<void> stopPlaying() => _ask(('stop',));

  /// Ends the helper isolate; whatever was asked and not yet answered is
  /// answered with nothing.
  void close() {
    if (_closed) return;
    _closed = true;
    _commands.send(null);
    _isolate.kill();
    _replies.close();
    for (final reply in _pending.values) {
      reply.complete();
    }
    _pending.clear();
  }

  static void _serve(SendPort replies) {
    final commands = ReceivePort();
    replies.send(commands.sendPort);
    AVAudioPlayer? player;
    commands.listen((message) {
      if (message == null) {
        player?.stop();
        commands.close();
        return;
      }
      final (id, command) = message as (int, Object);
      Object? result;
      switch (command) {
        case ('claim', final int mode, final int options):
          result = _claim(SessionMode.values[mode], options);
        case ('release',):
          _release();
        case ('play', final TransferableTypedData wav):
          player?.stop();
          player = AVAudioPlayer.alloc().initWithData(
            wav.materialize().asUint8List().toNSData(),
          );
          player?.play();
        case ('stop',):
          player?.stop();
          player = null;
      }
      replies.send((id, result));
    });
  }

  /// The session claimed: category first, then activation, because options
  /// set on a session that is already active do not start ducking. The core
  /// only claims a session it has given back (or never had), so the session
  /// is inactive here.
  static bool _claim(SessionMode mode, int options) {
    if (!Platform.isIOS) return true;
    try {
      AVAudioSession.sharedInstance()
        ..setCategory(
          AVAudioSessionCategoryPlayback,
          mode: switch (mode) {
            SessionMode.voicePrompt => AVAudioSessionModeVoicePrompt,
            SessionMode.spokenAudio => AVAudioSessionModeSpokenAudio,
          },
          options: options,
        )
        ..setActive(true, withOptions: 0);
      return true;
    } on objc.NSErrorException {
      return false;
    }
  }

  /// Others are told, so ducked music comes back up and a paused podcast
  /// carries on.
  static void _release() {
    if (!Platform.isIOS) return;
    try {
      AVAudioSession.sharedInstance().setActive(
        false,
        withOptions: AVAudioSessionSetActiveOptions
            .AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation,
      );
    } on objc.NSErrorException {
      // Still in use by a player of the app's own, say: nothing to give back
      // that is ours to give.
    }
  }
}
