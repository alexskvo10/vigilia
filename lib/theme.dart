import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Варианты акцента (цвета Catppuccin Mocha).
const accentPresets = [
  Color(0xFFCBA6F7),
  Color(0xFF89B4FA),
  Color(0xFF94E2D5),
  Color(0xFFA6E3A1),
  Color(0xFFFAB387),
  Color(0xFFF5C2E7),
];

/// Палитра из акцента: оттенок акцента подмешан во все тёмные слои,
/// поэтому интерфейс выглядит цельным, а не «серым с цветной кнопкой».
class Palette {
  Palette(this.accent) {
    final h = (HSLColor.fromColor(accent).hue - 7) % 360;
    Color hsl(double s, double l) => HSLColor.fromAHSL(1, h, s, l).toColor();
    crust = hsl(0.257, 0.069);
    mantle = hsl(0.25, 0.094);
    base = hsl(0.246, 0.12);
    surface0 = hsl(0.217, 0.18);
    surface1 = hsl(0.197, 0.239);
    surface2 = hsl(0.178, 0.32);
    overlay0 = hsl(0.123, 0.461);
    text = hsl(0.556, 0.912);
    subtext0 = hsl(0.208, 0.688);
  }

  final Color accent;
  late final Color crust, mantle, base, surface0, surface1, surface2, overlay0, text, subtext0;
}

/// Токены цвета. Палитра меняется целиком при смене акцента
/// (экран при этом пересоздаётся с кроссфейдом, см. VigiliaApp).
abstract final class C {
  static Palette _p = Palette(accentPresets.first);
  static void use(Color accent) => _p = Palette(accent);

  static Color get crust => _p.crust;
  static Color get mantle => _p.mantle;
  static Color get base => _p.base;
  static Color get surface0 => _p.surface0;
  static Color get surface1 => _p.surface1;
  static Color get surface2 => _p.surface2;
  static Color get overlay0 => _p.overlay0;
  static Color get text => _p.text;
  static Color get subtext0 => _p.subtext0;
  static Color get accent => _p.accent;
  static Color get onAccent => _p.crust;
  static const danger = Color(0xFFF38BA8);
  static const warning = Color(0xFFFAB387);
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

TextStyle mono(double size, {FontWeight weight = FontWeight.w700, Color? color, double spacing = 0}) => TextStyle(
  fontFamily: kFont,
  fontFamilyFallback: kFontFallback,
  fontSize: size,
  fontWeight: weight,
  color: color ?? C.text,
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
