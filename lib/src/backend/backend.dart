// The seam between the platform-independent core (`Speak`) and the
// platforms. A backend is deliberately thin: it speaks one utterance when
// told to and reports what the engine says, and the core decides everything
// else — queueing, interruption, timeouts, the audio session's lifetime and,
// where the engine cannot pause, pausing.
import 'dart:async';

import '../android_options.dart';
import '../audio.dart';
import '../outcome.dart';
import '../voice.dart';

/// One utterance as the core hands it to a backend.
class BackendUtterance {
  /// Creates an utterance.
  const BackendUtterance({
    required this.id,
    required this.text,
    this.voiceId,
    this.language,
    this.rate = 1,
    this.pitch = 1,
    this.volume = 1,
    this.leadIn = Duration.zero,
  });

  /// Unique for the life of the backend; every event about it carries it.
  final String id;

  /// What to say.
  final String text;

  /// The [Voice.id] to say it in, if one was chosen.
  final String? voiceId;

  /// The BCP-47 tag to say it in when no voice was chosen.
  final String? language;

  /// Speed relative to the platform's normal speed (1).
  final double rate;

  /// Pitch relative to the voice's normal pitch (1).
  final double pitch;

  /// Volume from 0 to 1.
  final double volume;

  /// Silence to play before the text, so a Bluetooth link that went quiet is
  /// open again when speech starts; [Duration.zero] for none.
  final Duration leadIn;
}

/// Something the engine reported about an utterance.
sealed class BackendEvent {
  const BackendEvent(this.id);

  /// The [BackendUtterance.id] it is about.
  final String id;
}

/// The engine started speaking the utterance.
final class BackendStarted extends BackendEvent {
  /// Creates the event.
  const BackendStarted(super.id);
}

/// The engine is about to speak `text.substring(start, end)`. [end] may equal
/// [start] when the engine only reports where a word starts.
final class BackendProgress extends BackendEvent {
  /// Creates the event.
  const BackendProgress(super.id, this.start, this.end);

  /// Start offset, UTF-16 code units.
  final int start;

  /// End offset, exclusive; may be [start] when unknown.
  final int end;
}

/// The engine says it finished the utterance. After a stop, some engines
/// (macOS) report this rather than [BackendCancelled].
final class BackendFinished extends BackendEvent {
  /// Creates the event.
  const BackendFinished(super.id);
}

/// The engine says the utterance was cancelled.
final class BackendCancelled extends BackendEvent {
  /// Creates the event.
  const BackendCancelled(super.id);
}

/// The engine failed to speak the utterance.
final class BackendFailed extends BackendEvent {
  /// Creates the event.
  const BackendFailed(super.id, this.error, [this.message]);

  /// What kind of failure.
  final SpeakError error;

  /// The platform's description.
  final String? message;
}

/// A platform's speech engine.
abstract interface class SpeechBackend {
  /// What the engine reports, for every utterance.
  Stream<BackendEvent> get events;

  /// Whether [pause] and [resume] work. When `false` the core pauses by
  /// stopping and resumes from the last reported word.
  bool get canPause;

  /// The installed voices. May be empty when the engine cannot list them.
  Future<List<Voice>> voices();

  /// What the engine says about [languageTag] itself, for engines that can
  /// tell more than their voice list (Android's `isLanguageAvailable`);
  /// `null` to go by [voices] alone.
  Future<VoiceAvailability?> languageAvailability(String languageTag);

  /// Claims the device's audio as [audio] says, before speaking.
  Future<void> activateAudio(SpeakAudio audio);

  /// Gives the device's audio back, so other apps return to normal.
  Future<void> deactivateAudio();

  /// Starts speaking [utterance]. The engine reports through [events]; a
  /// synchronous throw is a failure of this utterance only.
  void speak(BackendUtterance utterance);

  /// Stops speaking now. Completes once the engine has been told; the
  /// terminal event for the utterance may come later, or not at all.
  Future<void> stop();

  /// Pauses the utterance being spoken, at the end of a word where possible.
  Future<void> pause();

  /// Continues a paused utterance.
  Future<void> resume();

  /// Releases the engine.
  Future<void> dispose();
}

/// Creates the backend for the current platform. Replaced by tests.
typedef BackendFactory = SpeechBackend Function(AndroidSpeakOptions android);
