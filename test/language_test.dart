import 'package:flutter_test/flutter_test.dart';
import 'package:speak/speak.dart';
import 'package:speak/src/language.dart';

Voice _voice(
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

void main() {
  group('normalizeLanguageTag', () {
    test('cases each subtag the BCP-47 way', () {
      expect(normalizeLanguageTag('en-us'), 'en-US');
      expect(normalizeLanguageTag('EN_gb'), 'en-GB');
      expect(normalizeLanguageTag('zh-hant-tw'), 'zh-Hant-TW');
      expect(normalizeLanguageTag('sr_latn'), 'sr-Latn');
      expect(normalizeLanguageTag('es-419'), 'es-419');
      expect(normalizeLanguageTag(' de '), 'de');
    });

    test('maps the legacy codes Java and older engines still report', () {
      expect(normalizeLanguageTag('iw-IL'), 'he-IL');
      expect(normalizeLanguageTag('in_ID'), 'id-ID');
      expect(normalizeLanguageTag('ji'), 'yi');
    });

    test('keeps variants and extensions lower-case', () {
      expect(normalizeLanguageTag('de-DE-1996'), 'de-DE-1996');
      expect(normalizeLanguageTag('en-US-u-ca-GREGORY'), 'en-US-u-ca-gregory');
    });

    test('leaves an empty tag empty', () {
      expect(normalizeLanguageTag(''), '');
    });
  });

  group('languageMatch', () {
    test('the language has to be the same', () {
      expect(languageMatch('de-DE', 'en-US'), 0);
      expect(languageMatch('de', 'de-DE'), greaterThan(0));
    });

    test('a voice for the asked region beats one for another region', () {
      expect(
        languageMatch('en-GB', 'en-GB'),
        greaterThan(languageMatch('en-GB', 'en-US')),
      );
      expect(languageMatch('en-GB', 'en-US'), greaterThan(0));
    });

    test('different scripts never match', () {
      expect(languageMatch('zh-Hans-CN', 'zh-Hant-TW'), 0);
      expect(languageMatch('zh-Hans', 'zh-Hans-CN'), greaterThan(0));
    });

    test('compares normalised tags', () {
      expect(languageMatch('en_gb', 'EN-GB'), languageMatch('en-GB', 'en-GB'));
    });
  });

  group('bestVoiceFor', () {
    test('picks the best installed offline voice for the region', () {
      final voices = [
        _voice('us-premium', 'en-US', quality: VoiceQuality.premium),
        _voice('gb-normal', 'en-GB'),
        _voice('gb-enhanced', 'en-GB', quality: VoiceQuality.enhanced),
        _voice('de', 'de-DE', quality: VoiceQuality.premium),
      ];
      expect(bestVoiceFor(voices, 'en-GB')?.id, 'gb-enhanced');
      expect(bestVoiceFor(voices, 'en')?.id, 'us-premium');
    });

    test('falls back to another region of the language', () {
      final voices = [_voice('us', 'en-US'), _voice('de', 'de-DE')];
      expect(bestVoiceFor(voices, 'en-AU')?.id, 'us');
    });

    test('prefers an offline voice over a better online one', () {
      final voices = [
        _voice('online', 'de-DE', quality: VoiceQuality.premium, network: true),
        _voice('offline', 'de-DE', quality: VoiceQuality.low),
      ];
      expect(bestVoiceFor(voices, 'de-DE')?.id, 'offline');
    });

    test('never picks a voice that is not installed', () {
      final voices = [
        _voice(
          'missing',
          'fr-FR',
          quality: VoiceQuality.premium,
          installed: false,
        ),
      ];
      expect(bestVoiceFor(voices, 'fr-FR'), isNull);
    });

    test('settles ties by id so the choice is stable', () {
      final voices = [_voice('b', 'it-IT'), _voice('a', 'it-IT')];
      expect(bestVoiceFor(voices, 'it-IT')?.id, 'a');
    });

    test('is null when nothing speaks the language', () {
      expect(bestVoiceFor([_voice('us', 'en-US')], 'ja-JP'), isNull);
    });
  });

  group('availabilityFor', () {
    test('available when an installed offline voice exists', () {
      final voices = [
        _voice('a', 'de-AT'),
        _voice('n', 'de-DE', network: true),
      ];
      expect(availabilityFor(voices, 'de-DE'), VoiceAvailability.available);
    });

    test('needsNetwork when only online voices speak it', () {
      final voices = [_voice('n', 'pt-BR', network: true)];
      expect(availabilityFor(voices, 'pt-BR'), VoiceAvailability.needsNetwork);
    });

    test('notInstalled when the only voices still have to be downloaded', () {
      final voices = [_voice('m', 'pl-PL', installed: false)];
      expect(availabilityFor(voices, 'pl'), VoiceAvailability.notInstalled);
    });

    test('unsupported when no voice speaks the language', () {
      expect(
        availabilityFor([_voice('a', 'en-US')], 'ko-KR'),
        VoiceAvailability.unsupported,
      );
    });
  });

  group('Voice', () {
    test('normalises its language and is equal by id', () {
      final voice = _voice('x', 'en_gb');
      expect(voice.language, 'en-GB');
      expect(voice, _voice('x', 'de'));
      expect(voice.hashCode, 'x'.hashCode);
    });

    test('reports its own availability', () {
      expect(_voice('a', 'en').availability, VoiceAvailability.available);
      expect(
        _voice('a', 'en', network: true).availability,
        VoiceAvailability.needsNetwork,
      );
      expect(
        _voice('a', 'en', installed: false).availability,
        VoiceAvailability.notInstalled,
      );
    });

    test('ranks quality worst to best', () {
      expect(VoiceQuality.premium.compareTo(VoiceQuality.enhanced), 1);
      expect(VoiceQuality.unknown.compareTo(VoiceQuality.low), -1);
    });
  });
}
