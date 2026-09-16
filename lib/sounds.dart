import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'win32.dart';

const sampleRate = 44100;

/// Нота: частота, начало и длительность в секундах.
typedef Note = ({double hz, double at, double len});

/// Мягкий «колокольчик»: синус + немного второй гармоники,
/// атака 6 мс, экспоненциальное затухание, в конце плавно до нуля (без щелчка).
Float64List synth(List<Note> notes, {double gain = 0.22}) {
  final total = notes.map((n) => n.at + n.len).reduce(math.max);
  final out = Float64List((total * sampleRate).ceil() + 1);
  for (final n in notes) {
    final start = (n.at * sampleRate).round();
    final len = (n.len * sampleRate).round();
    for (var i = 0; i < len; i++) {
      final t = i / sampleRate;
      final attack = math.min(1.0, t / 0.006);
      final release = math.min(1.0, (len - 1 - i) / (0.02 * sampleRate));
      final env = attack * release * math.exp(-t * 7 / n.len);
      final w = 2 * math.pi * n.hz * t;
      out[start + i] += gain * env * (math.sin(w) + 0.18 * math.sin(2 * w));
    }
  }
  return out;
}

/// PCM 16 бит, моно, 44.1 кГц в контейнере RIFF/WAVE.
Uint8List wav(Float64List samples) {
  final data = samples.length * 2;
  final b = ByteData(44 + data);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      b.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  b.setUint32(4, 36 + data, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, 1, Endian.little); // моно
  b.setUint32(24, sampleRate, Endian.little);
  b.setUint32(28, sampleRate * 2, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  b.setUint32(40, data, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    b.setInt16(44 + i * 2, (samples[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
  }
  return b.buffer.asUint8List();
}

enum Sfx { on, off, tick, done }

Float64List sfxSamples(Sfx s) => switch (s) {
  Sfx.on => synth([(hz: 659.3, at: 0, len: 0.22), (hz: 987.8, at: 0.09, len: 0.34)]),
  Sfx.off => synth([(hz: 987.8, at: 0, len: 0.2), (hz: 659.3, at: 0.08, len: 0.3)], gain: 0.16),
  Sfx.tick => synth([(hz: 1760, at: 0, len: 0.045)], gain: 0.08),
  Sfx.done => synth([
    (hz: 1318.5, at: 0, len: 0.25),
    (hz: 987.8, at: 0.12, len: 0.25),
    (hz: 659.3, at: 0.24, len: 0.5),
  ]),
};

/// Буферы выделяются один раз и живут до конца процесса: PlaySound(SND_ASYNC)
/// читает память уже после возврата, освобождать её нельзя.
class Sounds {
  bool enabled = true;
  final Map<Sfx, Pointer<Uint8>> _cache = {};

  void play(Sfx s) {
    if (!enabled) return;
    final p = _cache.putIfAbsent(s, () {
      final bytes = wav(sfxSamples(s));
      final mem = malloc<Uint8>(bytes.length);
      mem.asTypedList(bytes.length).setAll(0, bytes);
      return mem;
    });
    playWav(p);
  }
}
