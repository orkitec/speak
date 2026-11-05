// The quiet mode of the real-engine tests (support/test_backend.dart): what
// reaches the engine is the utterance unchanged, at volume 0.
// ignore_for_file: implementation_imports
import 'package:flutter_test/flutter_test.dart';
import 'package:speak/src/backend/backend.dart';

import 'support/fake_backend.dart';
import 'support/test_backend.dart';

void main() {
  test('the quiet backend says everything at volume 0, otherwise as asked', () {
    final engine = FakeBackend();
    QuietBackend(engine).speak(
      const BackendUtterance(
        id: 'u1',
        text: 'Turn left.',
        voiceId: 'v',
        language: 'en-GB',
        rate: 1.5,
        pitch: 0.8,
        volume: 0.7,
        leadIn: Duration(milliseconds: 350),
      ),
    );
    final told = engine.spoken.single;
    expect(told.volume, 0);
    expect(
      [told.id, told.text, told.voiceId, told.language],
      ['u1', 'Turn left.', 'v', 'en-GB'],
    );
    expect(
      [told.rate, told.pitch, told.leadIn],
      [1.5, 0.8, const Duration(milliseconds: 350)],
    );
  });

  test('passes everything else on', () async {
    final engine = FakeBackend();
    final quiet = QuietBackend(engine);
    await quiet.pause();
    await quiet.resume();
    await quiet.stop();
    await quiet.dispose();
    expect(
      engine.log,
      containsAllInOrder(['pause', 'resume', 'stop', 'dispose']),
    );
  });
}
