import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:speak/src/darwin/silence.dart';

void main() {
  test('is a 16-bit mono PCM WAV of the asked length, all zeros', () {
    final wav = silentWav(const Duration(milliseconds: 350));
    final header = ByteData.sublistView(wav, 0, 44);
    String ascii(int at) => String.fromCharCodes(wav.sublist(at, at + 4));
    expect(ascii(0), 'RIFF');
    expect(ascii(8), 'WAVE');
    expect(ascii(12), 'fmt ');
    expect(ascii(36), 'data');
    expect(header.getUint16(20, Endian.little), 1, reason: 'PCM');
    expect(header.getUint16(22, Endian.little), 1, reason: 'mono');
    expect(header.getUint32(24, Endian.little), 22050);
    expect(header.getUint16(34, Endian.little), 16);
    // 350 ms at 22050 Hz, two bytes a sample.
    expect(header.getUint32(40, Endian.little), 7718 * 2);
    expect(header.getUint32(4, Endian.little), wav.length - 8);
    expect(wav.length, 44 + 7718 * 2);
    expect(wav.skip(44).every((b) => b == 0), isTrue);
  });
}
