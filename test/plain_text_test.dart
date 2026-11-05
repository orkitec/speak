import 'package:flutter_test/flutter_test.dart';
import 'package:speak/src/plain_text.dart';

void main() {
  group('text escaped for an engine that reads markup in plain text', () {
    test('text without markup characters is unchanged', () {
      final escaped = EscapedText('Turn left now.');
      expect(escaped.text, 'Turn left now.');
      expect(escaped.original(5), 5);
      expect(escaped.original(14), 14);
    });

    test('<, > and & become entities', () {
      expect(
        EscapedText('Turn left <now> onto A<B> & co.').text,
        'Turn left &lt;now&gt; onto A&lt;B&gt; &amp; co.',
      );
      expect(
        EscapedText('<speak>Hello</speak>').text,
        '&lt;speak&gt;Hello&lt;/speak&gt;',
      );
    });

    test('offsets in the escaped text map back onto the text', () {
      const text = 'Fish & chips < 5 km.';
      final escaped = EscapedText(text);
      int at(String word) => escaped.text.indexOf(word);
      String back(int start, int end) =>
          text.substring(escaped.original(start), escaped.original(end));
      expect(back(at('chips'), at('chips') + 5), 'chips');
      expect(back(at('&lt;'), at('&lt;') + 4), '<');
      expect(back(at('&amp;'), at('&amp;') + 5), '&');
      expect(back(at('5 km'), escaped.text.length), '5 km.');
    });

    test('an offset inside an entity maps to its character', () {
      final escaped = EscapedText('A<B');
      expect(escaped.original(1), 1);
      expect(escaped.original(3), 1);
      expect(escaped.original(5), 2);
    });

    test('offsets outside the text are clamped', () {
      final escaped = EscapedText('A<B');
      expect(escaped.original(-1), 0);
      expect(escaped.original(99), 3);
    });
  });
}
