import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Токены дизайна: Catppuccin Mocha с фиолетовым подтоном
/// во всех слоях и одним акцентом.
abstract final class C {
  static const crust = Color(0xFF100D16);
  static const mantle = Color(0xFF16121E);
  static const base = Color(0xFF1C1726);
  static const surface0 = Color(0xFF2B2438);
  static const surface1 = Color(0xFF3A3149);
  static const surface2 = Color(0xFF4D4360);
  static const overlay0 = Color(0xFF6F6784);
  static const text = Color(0xFFE6DCF5);
  static const subtext0 = Color(0xFFAA9FC0);
  static const accent = Color(0xFFCBA6F7);
  static const onAccent = crust;
  static const danger = Color(0xFFF38BA8);
  static const flash = Color(0xFFFFFFFF);
  static const hairline = Color(0x1AFFFFFF); // белый 10%
}

abstract final class D {
  static const instant = Duration(milliseconds: 100);
  static const fast = Duration(milliseconds: 150);
  static const color = Duration(milliseconds: 180);
  static const base = Duration(milliseconds: 250);
  static const panel = Duration(milliseconds: 300);
  static const settle = Duration(milliseconds: 400);
  static const slow = Duration(milliseconds: 600);
  static const breathe = Duration(milliseconds: 1800);
}

const double kRadius = 10;
const String kFont = 'Cascadia Mono';
const List<String> kFontFallback = ['Consolas', 'monospace'];

TextStyle mono(double size, {FontWeight weight = FontWeight.w700, Color color = C.text, double spacing = 0}) =>
    TextStyle(
      fontFamily: kFont,
      fontFamilyFallback: kFontFallback,
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: spacing,
      height: 1.2,
    );

/// Qt OutBack с настраиваемым перелётом `s`.
class OutBack extends Curve {
  const OutBack([this.s = 1.70158]);
  final double s;

  @override
  double transformInternal(double t) {
    final u = t - 1;
    return 1 + (s + 1) * u * u * u + s * u * u;
  }
}

/// Qt.lighter: V·k в HSV, излишек сверх 1 вычитается из насыщенности.
Color lighter(Color c, double k) {
  final hsv = HSVColor.fromColor(c);
  var v = hsv.value * k, s = hsv.saturation;
  if (v > 1) {
    s = math.max(0, s - (v - 1));
    v = 1;
  }
  return hsv.withValue(v).withSaturation(s).toColor();
}

/// Qt.darker: V/k в HSV.
Color darker(Color c, double k) {
  final hsv = HSVColor.fromColor(c);
  return hsv.withValue((hsv.value / k).clamp(0, 1)).toColor();
}

/// Выставляется при старте из настроек Windows (win32.systemAnimationsEnabled).
bool systemReducedMotion = false;

/// Уменьшенное движение: без попов, дыханий и вращений; цвет и вспышка остаются.
bool reduceMotion(BuildContext context) => systemReducedMotion || MediaQuery.disableAnimationsOf(context);
