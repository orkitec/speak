// Text for an engine that reads markup in what it is given as plain text,
// as AVSpeechSynthesizer does on macOS and before iOS 27: a `<` there starts a tag, and the tag
// and the words after it are lost. Escaped, the text is said as written.
// Pure, so it is tested on the VM.

/// [source] with `&`, `<` and `>` written as entities, and the way back from
/// offsets in the escaped [text] to offsets in [source].
class EscapedText {
  /// Escapes [source].
  factory EscapedText(String source) {
    final text = StringBuffer();
    final toSource = <int>[];
    for (var i = 0; i < source.length; i++) {
      final unit = source[i];
      final written = switch (unit) {
        '&' => '&amp;',
        '<' => '&lt;',
        '>' => '&gt;',
        _ => unit,
      };
      text.write(written);
      for (var j = 0; j < written.length; j++) {
        toSource.add(i);
      }
    }
    toSource.add(source.length);
    return EscapedText._(source, text.toString(), toSource);
  }

  EscapedText._(this.source, this.text, this._toSource);

  /// The text as asked for.
  final String source;

  /// The text to hand to the engine.
  final String text;

  /// For each offset in [text] (and its end), the offset in [source] of the
  /// character it was written for.
  final List<int> _toSource;

  /// The offset in [source] for [offset] in [text]; one inside an entity is
  /// its character's.
  int original(int offset) => _toSource[offset.clamp(0, text.length)];
}

/// Whether AVSpeechSynthesizer reads markup in plain text on this system:
/// on macOS ([macOS]), and on iOS before 27, where [version] is
/// `Platform.operatingSystemVersion` ("Version 26.1 (Build 23B80)"). Measured:
/// macOS 26 and the iOS 26 simulator drop a tag and the words after it; the
/// iOS 27.0 simulator reads the text as written, and would read entities
/// out. A version that cannot be read counts as before 27.
bool readsMarkup({required bool macOS, required String version}) {
  if (macOS) return true;
  final major = RegExp(r'(\d+)\.').firstMatch(version)?.group(1);
  return major == null || int.parse(major) < 27;
}
