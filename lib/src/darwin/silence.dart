import 'dart:typed_data';

/// A WAV file (16-bit mono PCM at [sampleRate] Hz) holding [length] of
/// silence: the lead-in played before speech on iOS and macOS.
Uint8List silentWav(Duration length, {int sampleRate = 22050}) {
  final samples = (sampleRate * length.inMicroseconds / 1e6).round();
  final dataBytes = samples * 2;
  final bytes = ByteData(44 + dataBytes);
  void ascii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      bytes.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes
    ..setUint32(16, 16, Endian.little) // fmt chunk size
    ..setUint16(20, 1, Endian.little) // PCM
    ..setUint16(22, 1, Endian.little) // mono
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * 2, Endian.little) // bytes per second
    ..setUint16(32, 2, Endian.little) // bytes per frame
    ..setUint16(34, 16, Endian.little); // bits per sample
  ascii(36, 'data');
  bytes.setUint32(40, dataBytes, Endian.little);
  // The samples are already zero.
  return bytes.buffer.asUint8List();
}
