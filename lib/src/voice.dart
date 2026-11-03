import 'language.dart';

/// How natural a voice sounds, as the platform grades it.
///
/// Ordered worst to best, so `a.index > b.index` means `a` is the better
/// voice; [compareTo] says the same.
enum VoiceQuality implements Comparable<VoiceQuality> {
  /// The platform did not say.
  unknown,

  /// A thin, robotic voice: Android's "low" and "very low".
  low,

  /// The voice a device ships with: iOS/macOS "default" (compact), Android
  /// "normal".
  normal,

  /// A better, usually downloaded voice: iOS/macOS "enhanced", Android
  /// "high".
  enhanced,

  /// The best voice on offer: iOS/macOS "premium", Android "very high".
  premium;

  @override
  int compareTo(VoiceQuality other) => index.compareTo(other.index);
}

/// Who a voice sounds like, as far as the platform says.
///
/// Only iOS and macOS report it; elsewhere it is [unknown].
enum VoiceGender {
  /// Not reported.
  unknown,

  /// A female voice.
  female,

  /// A male voice.
  male,
}

/// Whether text in a language, or in one voice, can be spoken right now.
///
/// Returned by `Speak.availability` and [Voice.availability], so an app can
/// tell the user that a voice has to be downloaded before it asks for one.
enum VoiceAvailability {
  /// An installed voice speaks it without a network connection.
  available,

  /// Only a voice that synthesises online speaks it: it says nothing, or
  /// says it late, without a connection. Android and web only.
  needsNetwork,

  /// The engine knows the language but its voice data is not installed.
  /// The user can download it in the system's text-to-speech settings.
  /// Android only.
  notInstalled,

  /// No voice for it at all.
  unsupported,
}

/// One voice the platform can speak with.
///
/// Get them from `Speak.voices`, and pass one as `voice:` to speak with it.
/// Two voices are equal when their [id]s are.
class Voice {
  /// Creates a voice description.
  ///
  /// Apps only need this to rebuild a voice they stored by [id]; voices for
  /// speaking come from `Speak.voices`. [language] is normalised to BCP-47
  /// (`en_us` becomes `en-US`).
  Voice({
    required this.id,
    required this.name,
    required String language,
    this.quality = VoiceQuality.unknown,
    this.gender = VoiceGender.unknown,
    this.requiresNetwork = false,
    this.isInstalled = true,
  }) : language = normalizeLanguageTag(language);

  /// What the platform identifies the voice by, stable across launches:
  /// the iOS/macOS identifier (`com.apple.voice.compact.en-US.Samantha`),
  /// the Android voice name (`en-us-x-iog-local`) or the web `voiceURI`.
  ///
  /// Store this to remember a user's choice.
  final String id;

  /// The name to show: "Samantha" on iOS; on Android the same machine name
  /// as [id], because Android has no display names.
  final String name;

  /// The BCP-47 tag of the language the voice speaks, e.g. `en-GB`.
  final String language;

  /// How natural the voice sounds.
  final VoiceQuality quality;

  /// Who the voice sounds like, where the platform says.
  final VoiceGender gender;

  /// Whether the voice synthesises online and needs a connection.
  final bool requiresNetwork;

  /// Whether the voice data is on the device. Android lists voices whose data
  /// still has to be downloaded; everywhere else this is always `true`.
  final bool isInstalled;

  /// Whether this voice can speak right now; see [VoiceAvailability].
  VoiceAvailability get availability => !isInstalled
      ? VoiceAvailability.notInstalled
      : requiresNetwork
      ? VoiceAvailability.needsNetwork
      : VoiceAvailability.available;

  @override
  bool operator ==(Object other) => other is Voice && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'Voice($name, $language, ${quality.name}'
      '${requiresNetwork ? ', online' : ''}'
      '${isInstalled ? '' : ', not installed'})';
}
