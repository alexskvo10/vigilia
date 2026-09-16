import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme.dart';

/// Текст, буквы которого входят по очереди (шаг 20ms): scale 0.55→1 (OutBack 1.35),
/// y +4→0 (OutBack 1.25), поворот ±10°→0 (OutCubic), opacity 150ms.
/// Старый текст гаснет за 150ms.
class Letters extends StatelessWidget {
  const Letters(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    return AnimatedSwitcher(
      duration: D.fast,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: still ? Text(text, key: ValueKey(text), style: style) : _LetterRow(text, style, key: ValueKey(text)),
    );
  }
}

class _LetterRow extends StatefulWidget {
  const _LetterRow(this.text, this.style, {super.key});
  final String text;
  final TextStyle style;

  @override
  State<_LetterRow> createState() => _LetterRowState();
}

class _LetterRowState extends State<_LetterRow> with SingleTickerProviderStateMixin {
  static const _step = 20, _len = 240;
  late final _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _len + _step * math.max(0, widget.text.length - 1)),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chars = widget.text.characters.toList();
    final total = _c.duration!.inMilliseconds;
    return Semantics(
      label: widget.text,
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < chars.length; i++) _letter(chars[i], i, (_c.value * total - i * _step) / _len),
          ],
        ),
      ),
    );
  }

  Widget _letter(String ch, int i, double raw) {
    final t = raw.clamp(0.0, 1.0);
    final scale = 0.55 + 0.45 * const OutBack(1.35).transform(t);
    final dy = 4 * (1 - const OutBack(1.25).transform((raw * 240 / 220).clamp(0.0, 1.0)));
    final rot = (i.isEven ? -1 : 1) * 10 * math.pi / 180 * (1 - Curves.easeOutCubic.transform(t));
    final opacity = (raw * 240 / 150).clamp(0.0, 1.0);
    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(0, dy),
        child: Transform.rotate(
          angle: rot,
          child: Transform.scale(
            scale: scale,
            child: Text(ch, style: widget.style),
          ),
        ),
      ),
    );
  }
}

/// Стартовый каскад: блок поднимается на 15px (650ms OutQuint) и проявляется (450ms OutCubic)
/// с задержкой index·50 + 100 мс.
class Cascade extends StatefulWidget {
  const Cascade({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<Cascade> createState() => _CascadeState();
}

class _CascadeState extends State<Cascade> with SingleTickerProviderStateMixin {
  late final int _delay = widget.index * 50 + 100;
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    // не лениво: при reduce motion build не трогает контроллер, и он создавался бы уже в dispose
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _delay + 650),
    )..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return widget.child;
    final total = _c.duration!.inMilliseconds;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final ms = _c.value * total - _delay;
        final y = 15 * (1 - Curves.easeOutQuint.transform((ms / 650).clamp(0.0, 1.0)));
        final o = Curves.easeOutCubic.transform((ms / 450).clamp(0.0, 1.0));
        return Opacity(
          opacity: o,
          child: Transform.translate(offset: Offset(0, y), child: child),
        );
      },
    );
  }
}
