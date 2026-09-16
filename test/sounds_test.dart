import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vigilia/sounds.dart';

void main() {
  for (final s in Sfx.values) {
    test('WAV $s: корректный заголовок, без щелчков, без клиппинга', () {
      final samples = sfxSamples(s);
      final bytes = wav(samples);
      final b = ByteData.sublistView(bytes);
      String tag(int at) => String.fromCharCodes(bytes.sublist(at, at + 4));

      expect(tag(0), 'RIFF');
      expect(tag(8), 'WAVE');
      expect(tag(36), 'data');
      expect(b.getUint32(4, Endian.little), bytes.length - 8);
      expect(b.getUint32(40, Endian.little), bytes.length - 44);
      expect(b.getUint16(22, Endian.little), 1);
      expect(b.getUint32(24, Endian.little), 44100);
      expect(b.getUint16(34, Endian.little), 16);

      expect(samples.first.abs(), lessThan(0.01));
      expect(samples.last.abs(), lessThan(0.01));
      expect(samples.map((x) => x.abs()).reduce((a, b) => a > b ? a : b), lessThan(0.95));
    });
  }
}
