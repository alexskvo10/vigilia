import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vigilia/theme.dart';

void expectColor(Color actual, int expected) {
  final e = Color(0xFF000000 | expected);
  for (final (a, b) in [(actual.r, e.r), (actual.g, e.g), (actual.b, e.b)]) {
    expect((a - b).abs() * 255, lessThanOrEqualTo(1.01), reason: '$actual vs $e');
  }
}

void main() {
  test('lighter/darker совпадают с Qt (HSV)', () {
    expectColor(lighter(const Color(0xFF313244), 1.18), 0x3a3b50);
    expectColor(darker(const Color(0xFF313244), 1.15), 0x2b2b3b);
    // переполнение V съедает насыщенность → белый
    expectColor(lighter(const Color(0xFFCBA6F7), 1.5), 0xffffff);
  });

  test('OutBack: концы на месте, есть перелёт', () {
    const c = OutBack(1.2);
    expect(c.transform(0), 0);
    expect(c.transform(1), 1);
    final peak = [for (var i = 1; i < 100; i++) c.transform(i / 100)].reduce((a, b) => a > b ? a : b);
    expect(peak, greaterThan(1));
    expect(const OutBack(0).transform(0.5), lessThanOrEqualTo(1));
  });
}
