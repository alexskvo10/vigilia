import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../sounds.dart';
import '../theme.dart';
import 'pressable.dart' show keyboardMode;

/// «Удерживай, чтобы подтвердить».
///
/// Пока кнопку держат (мышью или Enter/пробелом), заливка растёт до конца за
/// `800 · (1 − уровень)` мс (InSine), отпустили раньше — стекает за `1500 · уровень` мс (OutQuad).
/// Передний край — волна с амплитудой `min(10, залито, осталось) · sin(уровень · π)`,
/// фаза крутится с периодом 800ms. Заливка — градиент darker(акцент, 1.15) → акцент.
/// Текст под заливкой перекрашивается ровно по волне; буквы у фронта приподнимаются на
/// `3.5 · bump` px, растут на `12% · bump` и наклоняются на `±7° · bump`,
/// где `bump = exp(−((уровень − x) · 9)²)`. Иконка — так же, но слабее (1px, 3%).
/// Новый текст входит по буквам с шагом 20ms.
/// Срабатывание: вспышка 0.5, поп до 0.95, звук удара; через 1200ms кнопка сбрасывается.
///
/// Если задан [progress], кнопка не нажимается и показывает прогресс заливкой.
class HoldButton extends StatefulWidget {
  const HoldButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onConfirmed,
    required this.sounds,
    this.progress,
    this.height = 56,
  });

  final String label;
  final IconData icon;
  final VoidCallback onConfirmed;
  final Sounds sounds;
  final double? progress;
  final double height;

  @override
  State<HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<HoldButton> with TickerProviderStateMixin {
  late final _level = AnimationController(vsync: this);
  late final _phase = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
  late final _enter = AnimationController(vsync: this, duration: _enterDuration(widget.label));
  late final _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  late final _pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 490));
  late final _hover = AnimationController(vsync: this, duration: D.color);
  final _focus = FocusNode(debugLabel: 'hold');
  bool _holding = false, _done = false, _focused = false;
  _Glyphs? _glyphs;

  static String _skeleton(String label) => label.replaceAll(RegExp(r'[0-9]'), '');

  static Duration _enterDuration(String label) => Duration(milliseconds: 240 + 20 * label.length);

  bool get _still => reduceMotion(context);
  bool get _interactive => widget.progress == null && !_done;

  @override
  void initState() {
    super.initState();
    _level.addStatusListener((s) {
      if (s == AnimationStatus.completed && _holding) _confirm();
    });
    _enter.value = 1; // первый показ — без входа букв (панель и так въезжает каскадом)
  }

  @override
  void didUpdateWidget(HoldButton old) {
    super.didUpdateWidget(old);
    if (old.label != widget.label) {
      _glyphs = null;
      // смена процентов при скачивании — без повторного входа букв
      if (_skeleton(old.label) != _skeleton(widget.label) && !_still) {
        _enter.duration = _enterDuration(widget.label);
        _enter.forward(from: 0);
      }
    }
    if (widget.progress != null && _holding) _release();
    _syncPhase();
  }

  @override
  void dispose() {
    if (_holding) widget.sounds.stop();
    for (final c in [_level, _phase, _enter, _flash, _pop, _hover]) {
      c.dispose();
    }
    _focus.dispose();
    super.dispose();
  }

  void _syncPhase() {
    final moving = !_still && (_holding || (widget.progress ?? 0) > 0);
    if (moving && !_phase.isAnimating) _phase.repeat();
    if (!moving && _phase.isAnimating) _phase.stop();
  }

  void _press() {
    if (!_interactive || _holding) return;
    setState(() => _holding = true);
    widget.sounds.play(Sfx.charge, loop: true);
    final left = 1 - _level.value;
    _level.animateTo(
      1,
      duration: Duration(milliseconds: math.max(1, (800 * left).round())),
      curve: Curves.easeInSine,
    );
    _syncPhase();
  }

  void _release() {
    if (!_holding) return;
    setState(() => _holding = false);
    widget.sounds.stop();
    if (_done) return;
    final level = _level.value;
    _level.animateTo(
      0,
      duration: Duration(milliseconds: math.max(1, (1500 * level).round())),
      curve: Curves.easeOutQuad,
    );
    _syncPhase();
  }

  void _confirm() {
    setState(() {
      _holding = false;
      _done = true;
    });
    widget.sounds.play(Sfx.impact); // заменяет зацикленную «зарядку»
    _flash.forward(from: 0);
    if (!_still) _pop.forward(from: 0);
    _syncPhase();
    widget.onConfirmed();
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() => _done = false);
      _level.animateTo(0, duration: D.panel, curve: Curves.easeOutCubic);
    });
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    final key = e.logicalKey;
    if (key != LogicalKeyboardKey.space && key != LogicalKeyboardKey.enter) return KeyEventResult.ignored;
    if (e is KeyDownEvent) _press();
    if (e is KeyUpEvent) _release();
    return KeyEventResult.handled;
  }

  // поп: 1 → 0.95 за 110ms (OutQuad) → 1 за 380ms (OutQuint)
  double get _popScale {
    if (!_pop.isAnimating) return 1;
    final t = _pop.value * 490;
    if (t < 110) return 1 - 0.05 * Curves.easeOutQuad.transform(t / 110);
    return 0.95 + 0.05 * Curves.easeOutQuint.transform((t - 110) / 380);
  }

  _Glyphs _glyphsFor(TextStyle style) => _glyphs ??= _Glyphs(widget.label, widget.icon, style);

  @override
  Widget build(BuildContext context) {
    final glyphs = _glyphsFor(mono(13));
    final progress = widget.progress;
    return Semantics(
      button: true,
      enabled: _interactive,
      label: widget.label,
      child: Focus(
        focusNode: _focus,
        canRequestFocus: _interactive,
        onKeyEvent: _onKey,
        onFocusChange: (v) {
          setState(() => _focused = v);
          if (!v) _release();
        },
        child: MouseRegion(
          cursor: _interactive ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) => _hover.forward(),
          // без отпускания по уходу курсора: Windows присылает ложный уход при нажатии;
          // отпускание кнопки мыши приходит сюда и за пределами кнопки
          onExit: (_) => _hover.reverse(),
          child: Listener(
            onPointerDown: (e) {
              if (e.buttons == kPrimaryButton) _press();
            },
            onPointerUp: (_) => _release(),
            onPointerCancel: (_) => _release(),
            child: ValueListenableBuilder(
              valueListenable: keyboardMode,
              builder: (context, keyboard, child) => AnimatedContainer(
                duration: D.color,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _focused && keyboard ? C.accent : const Color(0x00000000), width: 2),
                ),
                child: child,
              ),
              child: AnimatedBuilder(
                animation: Listenable.merge([_level, _phase, _enter, _flash, _pop, _hover]),
                builder: (context, _) => Transform.scale(
                  scale: _popScale,
                  child: TweenAnimationBuilder<double>(
                    // прогресс скачивания подтягивается плавно
                    tween: Tween(end: progress ?? 0),
                    duration: D.panel,
                    curve: Curves.easeOutCubic,
                    builder: (context, shown, _) => CustomPaint(
                      size: Size(double.infinity, widget.height),
                      painter: _HoldPainter(
                        level: progress != null ? shown : _level.value,
                        phase: _phase.value,
                        hover: _interactive ? _hover.value : 0,
                        enter: _enter.value,
                        flash: _flash.isAnimating ? 0.5 * (1 - Curves.easeOutExpo.transform(_flash.value)) : 0,
                        glyphs: glyphs,
                        still: _still,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Буквы и иконка, разложенные один раз белым цветом; цвет задаёт слой при рисовании.
class _Glyphs {
  _Glyphs(String label, IconData icon, TextStyle style)
    : chars = [
        for (final ch in label.characters)
          TextPainter(
            text: TextSpan(
              text: ch,
              style: style.copyWith(color: const Color(0xFFFFFFFF)),
            ),
            textDirection: TextDirection.ltr,
          )..layout(),
      ],
      icon = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            fontSize: 17,
            color: const Color(0xFFFFFFFF),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

  final List<TextPainter> chars;
  final TextPainter icon;
  static const gap = 8.0;

  double get width => icon.width + gap + chars.fold(0.0, (w, c) => w + c.width);
}

class _HoldPainter extends CustomPainter {
  _HoldPainter({
    required this.level,
    required this.phase,
    required this.hover,
    required this.enter,
    required this.flash,
    required this.glyphs,
    required this.still,
  });

  final double level, phase, hover, enter, flash;
  final _Glyphs glyphs;
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final shape = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12));
    canvas.save();
    canvas.clipRRect(shape);
    canvas.drawRRect(shape, Paint()..color = Color.lerp(C.mantle, C.base, hover)!);

    final fill = _fillPath(w, h);
    if (fill != null) {
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            colors: [darker(C.accent, 1.15), C.accent],
          ).createShader(Rect.fromLTWH(0, 0, math.max(1, level * w), h)),
      );
    }

    // текст поверх фона, затем тёмная копия — только внутри заливки
    _content(canvas, size, Color.lerp(C.accent, C.text, hover)!);
    if (fill != null) {
      canvas.save();
      canvas.clipPath(fill);
      _content(canvas, size, C.crust);
      canvas.restore();
    }

    if (flash > 0) canvas.drawRRect(shape, Paint()..color = C.flash.withValues(alpha: flash));
    canvas.restore();
  }

  /// Заливка до level·w с волнистым правым краем.
  Path? _fillPath(double w, double h) {
    final fx = level * w;
    if (fx <= 0) return null;
    if (level >= 1) return Path()..addRect(Rect.fromLTWH(0, 0, w, h));
    final amp = still ? 0.0 : math.min(10.0, math.min(fx, w - fx)) * math.sin(level * math.pi);
    final a = phase * 2 * math.pi;
    final path = Path()..moveTo(0, 0);
    const steps = 16;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      path.lineTo(fx + amp * math.sin(2 * math.pi * t + a), t * h);
    }
    return path
      ..lineTo(0, h)
      ..close();
  }

  void _content(Canvas canvas, Size size, Color color) {
    final w = size.width, cy = size.height / 2;
    var x = (w - glyphs.width) / 2;
    canvas.saveLayer(Offset.zero & size, Paint()..colorFilter = ColorFilter.mode(color, BlendMode.srcIn));

    // иконка: те же принципы, что у букв, но слабее
    final ib = _bump((x + glyphs.icon.width / 2) / w);
    _glyph(canvas, glyphs.icon, x + glyphs.icon.width / 2, cy - ib, 1 + 0.03 * ib, 0, 1);
    x += glyphs.icon.width + _Glyphs.gap;

    for (final (i, g) in glyphs.chars.indexed) {
      final cx = x + g.width / 2;
      final bump = _bump(cx / w);
      final side = i.isEven ? -1 : 1;
      // вход буквы: шаг 20ms, scale 0.55→1 (240ms OutBack 1.35), y +4→0 (220ms OutBack 1.25),
      // поворот ±10°→0 (220ms OutCubic), прозрачность 150ms
      final total = 240 + 20 * glyphs.chars.length;
      final ms = enter * total - i * 20;
      final t = (ms / 240).clamp(0.0, 1.0);
      final enterScale = 0.55 + 0.45 * const OutBack(1.35).transform(t);
      final enterY = 4 * (1 - const OutBack(1.25).transform((ms / 220).clamp(0.0, 1.0)));
      final enterRot = side * 10 * (1 - Curves.easeOutCubic.transform((ms / 220).clamp(0.0, 1.0)));
      _glyph(
        canvas,
        g,
        cx,
        cy - 3.5 * bump + enterY,
        (1 + 0.12 * bump) * enterScale,
        (side * 7 * bump + enterRot) * math.pi / 180,
        (ms / 150).clamp(0.0, 1.0),
      );
      x += g.width;
    }
    canvas.restore();
  }

  double _bump(double x) {
    if (still || level <= 0 || level >= 1) return 0;
    final d = (level - x) * 9;
    return math.exp(-d * d);
  }

  void _glyph(Canvas canvas, TextPainter g, double cx, double cy, double scale, double angle, double opacity) {
    if (opacity <= 0) return;
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(angle);
    canvas.scale(scale);
    if (opacity < 1) {
      canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
      g.paint(canvas, Offset(-g.width / 2, -g.height / 2));
      canvas.restore();
    } else {
      g.paint(canvas, Offset(-g.width / 2, -g.height / 2));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HoldPainter old) =>
      old.level != level ||
      old.phase != phase ||
      old.hover != hover ||
      old.enter != enter ||
      old.flash != flash ||
      old.glyphs != glyphs ||
      old.still != still;
}
