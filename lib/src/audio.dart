/// What happens to other apps' audio while something is spoken.
///
/// See the README's "What happens to music and podcasts" for every mode on
/// every platform.
enum OtherAudio {
  /// Play alongside it, untouched.
  ///
  /// iOS: `mixWithOthers`. Android: no audio focus is requested.
  mix,

  /// Lower it while speaking, music and spoken audio alike, and bring it
  /// back afterwards.
  ///
  /// iOS: `mixWithOthers` + `duckOthers`. Android: transient audio focus that
  /// may duck (`AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK`).
  duck,

  /// Lower music and pause spoken audio (podcasts, audiobooks) while
  /// speaking; both come back afterwards. What navigation apps do.
  ///
  /// iOS: `mixWithOthers` + `duckOthers` +
  /// `interruptSpokenAudioAndMixWithOthers`. Android: as [duck]. An app
  /// cannot make another pause there: a podcast player pauses only if it
  /// chose to pause rather than duck (`setWillPauseWhenDucked`), and the
  /// rest are lowered.
  duckAndPauseSpoken,

  /// Leave music playing at full volume but pause spoken audio while
  /// speaking.
  ///
  /// iOS: `mixWithOthers` + `interruptSpokenAudioAndMixWithOthers`. Android:
  /// as [duck], with the same limit as [duckAndPauseSpoken].
  pauseSpoken,

  /// Pause it while speaking, and let it resume afterwards.
  ///
  /// iOS: no mixing options, so other audio is interrupted. Android:
  /// transient audio focus (`AUDIOFOCUS_GAIN_TRANSIENT`).
  pause,
}

/// What happens to an utterance while a phone call has the audio.
enum SpeakDuringCalls {
  /// Not spoken: it ends as `SpeakOutcome.blocked`. The default.
  skip,

  /// Spoken anyway, as far as the platform lets it.
  speak,
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
/// right before an utterance and given back [linger] after the last one, so
/// ducked music comes back between prompts and nothing is held while the
/// app is quiet. On iOS and macOS speech always uses the `playback`
/// category: it is heard with the Ring/Silent switch on silent and, with the
/// `audio` background mode, with the screen locked.
///
/// The web cannot influence other audio, and has no lead-in: there, this
/// is ignored.
///
/// ```dart
/// final speak = Speak(audio: SpeakAudio.navigation);
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
    this.leadIn = defaultLeadIn,
    this.leadInOnBluetoothOnly = true,
    this.linger = defaultLinger,
    this.duringCalls = SpeakDuringCalls.skip,
  });

  /// The default [leadIn]: long enough for a Bluetooth headset to start
  /// playing, short enough not to be noticed.
  static const Duration defaultLeadIn = Duration(milliseconds: 350);

  /// The default [linger]: covers the gap between prompts said in quick
  /// succession, without keeping other audio lowered noticeably long.
  static const Duration defaultLinger = Duration(milliseconds: 1500);

  /// Spoken guidance, as navigation apps do it: music is lowered and podcasts
  /// are paused while speaking ([OtherAudio.duckAndPauseSpoken]), the usage
  /// is [AudioUsage.navigation].
  static const SpeakAudio navigation = SpeakAudio(
    otherAudio: OtherAudio.duckAndPauseSpoken,
    usage: AudioUsage.navigation,
  );

  /// A short prompt over other audio: everything is lowered
  /// ([OtherAudio.duck]). The default.
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

  /// Silence played before the first utterance after the audio is claimed,
  /// when the audio goes to Bluetooth (see [leadInOnBluetoothOnly]);
  /// [Duration.zero] for none.
  ///
  /// A Bluetooth headset or car stereo mutes its audio stream while it is
  /// silent and takes a moment to open it again, so the first syllables of
  /// speech that starts right away are lost. Utterances that follow while
  /// the audio is still claimed (queued ones, or within [linger]) get no
  /// lead-in. Not counted against an utterance's timeout. iOS and macOS
  /// (`preUtteranceDelay`) and Android (`playSilentUtterance`); the web has
  /// no such control.
  final Duration leadIn;

  /// Whether the [leadIn] is played only when the audio goes to a Bluetooth
  /// device or a car, the outputs that mute while silent. The default:
  /// through the phone's own speaker or wired headphones speech starts at
  /// once, and a lead-in there is only a delay.
  ///
  /// The route is read right after the audio is claimed. iOS: the session's
  /// current outputs (Bluetooth A2DP, HFP, LE, or CarPlay and other car
  /// audio). Android 13 and later: the device the speech's own audio
  /// attributes route to; before that, whether any Bluetooth (A2DP, SCO,
  /// LE) or hearing-aid output is connected. macOS has no such session and
  /// counts as no Bluetooth, so it gets no lead-in unless this is `false`.
  ///
  /// `false` plays the lead-in wherever the audio goes.
  final bool leadInOnBluetoothOnly;

  /// How long the audio stays claimed after the last utterance, in case
  /// another follows; [Duration.zero] to give it back at once.
  ///
  /// An utterance within it reuses the claim: no second [leadIn], and other
  /// audio is not raised and lowered again in between. `Speak.stop`,
  /// `Speak.pause` and `Speak.dispose` give the audio back at once.
  final Duration linger;

  /// What happens to an utterance while a phone call has the audio.
  final SpeakDuringCalls duringCalls;

  /// A copy with the given fields replaced.
  SpeakAudio copyWith({
    OtherAudio? otherAudio,
    AudioUsage? usage,
    Duration? leadIn,
    bool? leadInOnBluetoothOnly,
    Duration? linger,
    SpeakDuringCalls? duringCalls,
  }) => SpeakAudio(
    otherAudio: otherAudio ?? this.otherAudio,
    usage: usage ?? this.usage,
    leadIn: leadIn ?? this.leadIn,
    leadInOnBluetoothOnly: leadInOnBluetoothOnly ?? this.leadInOnBluetoothOnly,
    linger: linger ?? this.linger,
    duringCalls: duringCalls ?? this.duringCalls,
  );

  @override
  bool operator ==(Object other) =>
      other is SpeakAudio &&
      other.otherAudio == otherAudio &&
      other.usage == usage &&
      other.leadIn == leadIn &&
      other.leadInOnBluetoothOnly == leadInOnBluetoothOnly &&
      other.linger == linger &&
      other.duringCalls == duringCalls;

  @override
  int get hashCode => Object.hash(
    otherAudio,
    usage,
    leadIn,
    leadInOnBluetoothOnly,
    linger,
    duringCalls,
  );

  @override
  String toString() =>
      'SpeakAudio(${otherAudio.name}, ${usage.name}, '
      'lead-in ${leadIn.inMilliseconds} ms'
      '${leadInOnBluetoothOnly ? ' on Bluetooth' : ''}, '
      'linger ${linger.inMilliseconds} ms, '
      '${duringCalls == SpeakDuringCalls.skip ? 'skipped' : 'spoken'} '
      'during calls)';
}
