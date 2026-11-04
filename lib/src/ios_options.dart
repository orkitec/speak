/// Settings that only exist on iOS; ignored everywhere else.
///
/// ```dart
/// // An app sold on the China storefront, where App Review rejects apps
/// // that use CallKit:
/// final speak = Speak(ios: const IosSpeakOptions(callKit: false));
/// ```
class IosSpeakOptions {
  /// Creates the options.
  const IosSpeakOptions({this.callKit = true});

  /// Whether CallKit is asked if a call is going on, before each utterance.
  ///
  /// The package never links CallKit: with this `true` (the default) it
  /// loads the system framework at run time, on the first utterance, and a
  /// prompt due during a phone call or a CallKit VoIP call is not spoken
  /// (`SpeakOutcome.blocked`).
  ///
  /// `false` never loads CallKit, for apps sold on the China storefront,
  /// where App Review rejects apps that contain it. A call is then only
  /// noticed while `speak` holds the audio session (the interruption
  /// notification): a prompt due during a call that started between two
  /// prompts may be spoken over it.
  final bool callKit;

  @override
  bool operator ==(Object other) =>
      other is IosSpeakOptions && other.callKit == callKit;

  @override
  int get hashCode => callKit.hashCode;

  @override
  String toString() => 'IosSpeakOptions(callKit: $callKit)';
}
