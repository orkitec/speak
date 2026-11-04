import 'package:flutter_test/flutter_test.dart';
import 'package:speak/speak.dart';
import 'package:speak/src/backend/backend.dart';
import 'package:speak/src/backend/unsupported_backend.dart';

void main() {
  const backend = UnsupportedBackend();

  test('what needs an engine throws UnsupportedError', () {
    expect(backend.voices, throwsUnsupportedError);
    expect(() => backend.languageAvailability('en'), throwsUnsupportedError);
    expect(
      () => backend.speak(const BackendUtterance(id: '1', text: 'Hi.')),
      throwsUnsupportedError,
    );
  });

  test('what can safely do nothing does nothing', () async {
    expect(backend.canPause, isFalse);
    expect(await backend.events.isEmpty, isTrue);
    expect(await backend.interruptions.isEmpty, isTrue);
    expect(await backend.activateAudio(SpeakAudio.prompt), AudioClaim.granted);
    expect(await backend.isInCall(), isFalse);
    expect(await backend.isBluetoothRoute(SpeakAudio.prompt), isFalse);
    await backend.deactivateAudio();
    await backend.stop();
    await backend.pause();
    await backend.resume();
    await backend.dispose();
  });

  test('Android engines are an empty list off Android', () async {
    // The test host is a desktop or the browser, never Android.
    expect(await Speak.androidEngines(), isEmpty);
  });
}
