import 'package:flutter_test/flutter_test.dart';
import 'package:speak/speak.dart';

void main() {
  test('SpeakAudio presets say what they do', () {
    expect(SpeakAudio.prompt, const SpeakAudio());
    expect(SpeakAudio.navigation.usage, AudioUsage.navigation);
    expect(SpeakAudio.navigation.otherAudio, OtherAudio.duck);
    expect(SpeakAudio.plain.otherAudio, OtherAudio.mix);
    expect(SpeakAudio.exclusive.otherAudio, OtherAudio.pause);
    expect(SpeakAudio.prompt.hashCode, const SpeakAudio().hashCode);
    expect(SpeakAudio.plain.toString(), 'SpeakAudio(mix, prompt)');
  });

  test('Android options and engines are values', () {
    expect(
      const AndroidSpeakOptions(engine: 'a'),
      const AndroidSpeakOptions(engine: 'a'),
    );
    expect(
      const AndroidSpeakOptions(engine: 'a').hashCode,
      const AndroidSpeakOptions(engine: 'a').hashCode,
    );
    const engine = AndroidEngine(
      name: 'com.google.android.tts',
      label: 'Speech Services by Google',
      isDefault: true,
    );
    expect(
      engine,
      const AndroidEngine(
        name: 'com.google.android.tts',
        label: 'Speech Services by Google',
        isDefault: true,
      ),
    );
    expect(engine.hashCode, isNot(0));
    expect(engine.toString(), contains('default'));
  });

  test('SpeechProgress points into the text', () {
    const progress = SpeechProgress('Turn left now.', 5, 9);
    expect(progress.word, 'left');
    expect(progress.toString(), 'SpeechProgress(5..9 "left")');
    expect(
      progress.hashCode,
      const SpeechProgress('Turn left now.', 5, 9).hashCode,
    );
  });

  test('SpeakException says what failed', () {
    expect(
      const SpeakException(SpeakError.timeout, 'slow').toString(),
      'SpeakException(timeout: slow)',
    );
    expect(
      const SpeakException(SpeakError.notAllowed).toString(),
      'SpeakException(notAllowed)',
    );
  });

  test('Voice describes itself', () {
    final voice = Voice(
      id: 'x',
      name: 'Anna',
      language: 'de_de',
      requiresNetwork: true,
      isInstalled: false,
    );
    expect(
      voice.toString(),
      'Voice(Anna, de-DE, unknown, online, not installed)',
    );
  });

  test('isSupported is false on the test host', () {
    // Tests run on the VM of a desktop: no speech there unless it is macOS.
    expect(Speak.isSupported, isA<bool>());
  });
}
