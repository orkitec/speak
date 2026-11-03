/// How an utterance ended, when it did not fail.
///
/// Failures are a [SpeakException] instead.
enum SpeakOutcome {
  /// Spoken to the end.
  completed,

  /// Cut off or dropped by `Speak.stop`, or by a later utterance spoken with
  /// [SpeakQueue.interrupt]. Decided by this package from those calls, never
  /// from which callback the platform happens to send.
  interrupted,

  /// Never started: it was still waiting when its `expireAfter` ran out.
  expired,
}

/// What a new utterance does to the ones before it.
enum SpeakQueue {
  /// Waits until everything before it has been spoken.
  append,

  /// Cuts off what is being said and drops what is waiting, all of which
  /// end as [SpeakOutcome.interrupted], and is spoken right away. Also
  /// resumes a paused speaker.
  interrupt,
}

/// Why speaking failed; see [SpeakException].
enum SpeakError {
  /// No voice speaks the asked language (see `Speak.availability`).
  languageUnavailable,

  /// The asked voice is not installed, or not on this device at all.
  voiceUnavailable,

  /// The platform has no usable speech engine: none installed on Android,
  /// none in the browser.
  engineUnavailable,

  /// The browser refused to speak before the user interacted with the page.
  notAllowed,

  /// The engine never said it had finished, within a time scaled to the
  /// length of the text.
  timeout,

  /// The engine gave up on the utterance.
  synthesisFailed,
}

/// Speaking an utterance failed.
///
/// The future returned by calling a `Speak` completes with this error; a
/// failed utterance does not stop the ones queued after it.
class SpeakException implements Exception {
  /// Creates the exception.
  const SpeakException(this.error, [this.message]);

  /// What went wrong.
  final SpeakError error;

  /// The platform's own description, when it gave one.
  final String? message;

  @override
  String toString() =>
      'SpeakException(${error.name}${message == null ? '' : ': $message'})';
}

/// The part of an utterance being spoken right now, usually a word.
///
/// Delivered to the `onProgress` callback of a call. Offsets are UTF-16
/// code unit indices into [text], like [String.substring] takes.
class SpeechProgress {
  /// Creates a progress report.
  const SpeechProgress(this.text, this.start, this.end);

  /// The whole utterance.
  final String text;

  /// Where the range starts in [text].
  final int start;

  /// Where the range ends in [text], exclusive.
  final int end;

  /// The text being spoken now: `text.substring(start, end)`.
  String get word => text.substring(start, end);

  @override
  bool operator ==(Object other) =>
      other is SpeechProgress &&
      other.text == text &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(text, start, end);

  @override
  String toString() => 'SpeechProgress($start..$end "$word")';
}
