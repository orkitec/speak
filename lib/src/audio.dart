/// What happens to other apps' audio while something is spoken.
enum OtherAudio {
  /// Play alongside it, untouched.
  ///
  /// iOS: `mixWithOthers`. Android: no audio focus is requested.
  mix,

  /// Lower it while speaking, and bring it back afterwards.
  ///
  /// iOS: `mixWithOthers` + `duckOthers`. Android: transient audio focus that
  /// may duck (`AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK`).
  duck,

  /// Leave music playing at full volume but pause spoken audio — podcasts,
  /// audiobooks — for as long as the prompt lasts.
  ///
  /// iOS: `mixWithOthers` + `interruptSpokenAudioAndMixWithOthers`. Android
  /// has no such distinction and ducks instead (most podcast players pause
  /// when ducked).
  pauseSpoken,

  /// Pause it while speaking, and let it resume afterwards.
  ///
  /// iOS: no mixing options, so other audio is interrupted. Android:
  /// transient audio focus (`AUDIOFOCUS_GAIN_TRANSIENT`).
  pause,
}

/// What the speech is for, so the system can route and treat it right.
enum AudioUsage {
  /// Turn-by-turn and other spoken guidance.
  ///
  /// iOS: mode `voicePrompt`. Android: `USAGE_ASSISTANCE_NAVIGATION_GUIDANCE`.
  navigation,

  /// Short prompts and notifications from an assistant, a workout or a timer.
  ///
  /// iOS: mode `voicePrompt`. Android: `USAGE_ASSISTANT`.
  prompt,

  /// Longer spoken content the user listens to, like reading an article.
  ///
  /// iOS: mode `spokenAudio`. Android: `USAGE_MEDIA`.
  spokenContent,
}

/// How speech shares the device's audio with other apps.
///
/// The platform's audio session (iOS) or audio focus (Android) is claimed
/// right before the first utterance and given back after the last one, so
/// ducked music comes back between prompts. On iOS and macOS speech always
/// uses the `playback` category: it is heard with the Ring/Silent switch on
/// silent and, with the `audio` background mode, with the screen locked.
///
/// The web cannot influence other audio: there, this is ignored.
///
/// ```dart
/// final speak = Speak(audio: SpeakAudio.prompt);
/// final reader = Speak(
///   audio: const SpeakAudio(
///     otherAudio: OtherAudio.pause,
///     usage: AudioUsage.spokenContent,
///   ),
/// );
/// ```
class SpeakAudio {
  /// Creates an audio configuration.
  const SpeakAudio({
    this.otherAudio = OtherAudio.duck,
    this.usage = AudioUsage.prompt,
  });

  /// Spoken guidance over other audio: music is ducked, the usage is
  /// [AudioUsage.navigation].
  static const SpeakAudio navigation = SpeakAudio(usage: AudioUsage.navigation);

  /// A short prompt over other audio: music is ducked. The default.
  static const SpeakAudio prompt = SpeakAudio();

  /// Speech that leaves other audio alone, mixed in at full volume.
  static const SpeakAudio plain = SpeakAudio(otherAudio: OtherAudio.mix);

  /// Speech that pauses other audio while it lasts.
  static const SpeakAudio exclusive = SpeakAudio(
    otherAudio: OtherAudio.pause,
    usage: AudioUsage.spokenContent,
  );

  /// What happens to other apps' audio.
  final OtherAudio otherAudio;

  /// What the speech is for.
  final AudioUsage usage;

  @override
  bool operator ==(Object other) =>
      other is SpeakAudio &&
      other.otherAudio == otherAudio &&
      other.usage == usage;

  @override
  int get hashCode => Object.hash(otherAudio, usage);

  @override
  String toString() => 'SpeakAudio(${otherAudio.name}, ${usage.name})';
}
