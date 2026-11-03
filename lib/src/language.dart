// BCP-47 handling and the choice of a voice for a language. Platform
// independent: every backend reports tags in its own spelling (`en_US` from
// some Android engines, `iw` from old Java locales), and everything here works
// on the normalised form.
import 'voice.dart';

/// Codes Java and some engines still report, and what they are now.
const _legacyLanguages = {'iw': 'he', 'in': 'id', 'ji': 'yi'};

final _alpha = RegExp(r'^[a-zA-Z]+$');
final _digits = RegExp(r'^[0-9]+$');

/// [tag] in canonical BCP-47 case: `en_us` becomes `en-US`, `zh-hant-tw`
/// becomes `zh-Hant-TW`.
///
/// Underscores become hyphens, the language is lower-case, a script is
/// title-case, a region upper-case, and anything after it lower-case. Legacy
/// codes (`iw`, `in`, `ji`) are replaced by the current ones.
String normalizeLanguageTag(String tag) {
  final parsed = _parse(tag);
  return [
    if (parsed.language.isNotEmpty) parsed.language,
    ?parsed.script,
    ?parsed.region,
    ...parsed.rest,
  ].join('-');
}

typedef _Tag = ({
  String language,
  String? script,
  String? region,
  List<String> rest,
});

_Tag _parse(String tag) {
  final parts = tag.trim().replaceAll('_', '-').split('-');
  final language = parts.first.toLowerCase();
  var i = 1;
  String? script;
  String? region;
  if (i < parts.length && parts[i].length == 4 && _alpha.hasMatch(parts[i])) {
    script = parts[i][0].toUpperCase() + parts[i].substring(1).toLowerCase();
    i++;
  }
  if (i < parts.length &&
      ((parts[i].length == 2 && _alpha.hasMatch(parts[i])) ||
          (parts[i].length == 3 && _digits.hasMatch(parts[i])))) {
    region = parts[i].toUpperCase();
    i++;
  }
  return (
    language: _legacyLanguages[language] ?? language,
    script: script,
    region: region,
    // Variants, extensions and private use.
    rest: [for (final part in parts.skip(i)) part.toLowerCase()],
  );
}

/// How well a voice speaking [voiceTag] fits a request for [wantedTag]:
/// `0` for not at all, higher for better.
///
/// The language has to be the same, and two different scripts never match
/// (`zh-Hans` is not `zh-Hant`). Past that, a voice for the asked region (or
/// any voice, when no region was asked for) scores `2`, a voice for another
/// region `1`.
int languageMatch(String wantedTag, String voiceTag) {
  final wanted = _parse(wantedTag);
  final voice = _parse(voiceTag);
  if (wanted.language.isEmpty || wanted.language != voice.language) return 0;
  if (wanted.script != null &&
      voice.script != null &&
      wanted.script != voice.script) {
    return 0;
  }
  if (wanted.region == null || wanted.region == voice.region) return 2;
  return 1;
}

/// The voice to speak [languageTag] with, or `null` when no installed voice
/// speaks the language.
///
/// In order: the closest region (see [languageMatch]), a voice that works
/// offline, the better [VoiceQuality], and the [Voice.id] to settle ties so
/// the choice is the same every time. A voice that is not installed is never
/// chosen.
Voice? bestVoiceFor(Iterable<Voice> voices, String languageTag) {
  Voice? best;
  var bestKey = const <int>[];
  for (final voice in voices) {
    if (!voice.isInstalled) continue;
    final match = languageMatch(languageTag, voice.language);
    if (match == 0) continue;
    final key = [match, voice.requiresNetwork ? 0 : 1, voice.quality.index];
    if (best == null || _compareKeys(key, bestKey, voice.id, best.id) > 0) {
      best = voice;
      bestKey = key;
    }
  }
  return best;
}

int _compareKeys(List<int> a, List<int> b, String idA, String idB) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return a[i].compareTo(b[i]);
  }
  // Lower id wins.
  return idB.compareTo(idA);
}

/// Whether any of [voices] can speak [languageTag]; see [VoiceAvailability].
VoiceAvailability availabilityFor(Iterable<Voice> voices, String languageTag) {
  var best = VoiceAvailability.unsupported;
  for (final voice in voices) {
    if (languageMatch(languageTag, voice.language) == 0) continue;
    final availability = voice.availability;
    // The enum is ordered best first.
    if (availability.index < best.index) best = availability;
  }
  return best;
}
