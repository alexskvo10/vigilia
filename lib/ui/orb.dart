import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../strings.dart';
import '../theme.dart';
import 'pressable.dart';

const _sclera = Color(0xFFFBF6FF);

/// Главная кнопка. Выкл: глаз закрыт, над орбом всплывают «z».
/// Вкл: глаз открывается с перелётом, моргает, следит за курсором;
/// вокруг «дышит» аура (1800ms InOutSine) и вращается пунктирная орбита со спутником.
/// При переключении от края расходится волна.
class Orb extends StatefulWidget {
  const Orb({
    super.key,
    required this.active,
    required this.error,
    required this.progress,
    required this.pointer,
    required this.onTap,
    this.size = 188,
  });

  final bool active, error;
  final double? progress; // 1 → 0, null без таймера
  final ValueListenable<Offset?> pointer; // глобальная позиция курсора
  final VoidCallback onTap;
  final double size;

  @override
  State<Orb> createState() => _OrbState();
}

class _OrbState extends State<Orb> with TickerProviderStateMixin {
  late final _on = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
    reverseDuration: D.panel,
    value: widget.active ? 1 : 0,
  );
  late final _onCurve = CurvedAnimation(parent: _on, curve: Curves.easeOutQuint, reverseCurve: Curves.easeInCubic);
  late final _lid = AnimationController(
    vsync: this,
    duration: D.slow,
    reverseDuration: D.base,
    value: widget.active ? 1 : 0,
  );
  late final _lidCurve = CurvedAnimation(parent: _lid, curve: const OutBack(1.6), reverseCurve: Curves.easeInCubic);
  late final _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 190));
  late final _breath = AnimationController(vsync: this, duration: D.breathe);
  late final _spin = AnimationController(vsync: this, duration: const Duration(seconds: 24));
  late final _zz = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800));
  late final _wave = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late final _look = AnimationController(vsync: this, duration: D.settle);
  Offset _lookFrom = Offset.zero, _lookTo = Offset.zero;
  Timer? _blinkTimer;
  final _rnd = math.Random();
  bool _still = false;
  double _lastProgress = 1; // при сбросе таймера кольцо гаснет на месте, а не докручивается

  Offset get _lookAt => Offset.lerp(_lookFrom, _lookTo, Curves.easeOutCubic.transform(_look.value))!;

  @override
  void initState() {
    super.initState();
    widget.pointer.addListener(_onPointer);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = reduceMotion(context);
    _syncLoops();
  }

  @override
  void didUpdateWidget(Orb old) {
    super.didUpdateWidget(old);
    if (old.pointer != widget.pointer) {
      old.pointer.removeListener(_onPointer);
      widget.pointer.addListener(_onPointer);
    }
    if (old.active != widget.active) {
      if (widget.active) {
        _on.forward();
        if (_still) {
          _lid.value = 1;
        } else {
          _lid.forward();
        }
      } else {
        _on.reverse();
        _lid.reverse();
      }
      if (!_still) _wave.forward(from: 0);
      _syncLoops();
      // открывшийся глаз сразу смотрит на курсор, закрывшийся — прямо (после раскладки кадра)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onPointer();
      });
    }
  }

  void _syncLoops() {
    final on = widget.active && !_still;
    final off = !widget.active && !_still;
    on ? _breath.repeat(reverse: true) : _breath.stop();
    on ? _spin.repeat() : _spin.stop();
    off ? _zz.repeat() : _zz.stop();
    _blinkTimer?.cancel();
    if (on) _scheduleBlink();
  }

  void _scheduleBlink() {
    _blinkTimer = Timer(Duration(milliseconds: 2400 + _rnd.nextInt(4200)), () async {
      if (!mounted) return;
      await _blink.forward(from: 0).orCancel.catchError((_) {});
      if (mounted && _rnd.nextDouble() < 0.25) {
        await _blink.forward(from: 0).orCancel.catchError((_) {}); // иногда двойное моргание
      }
      if (mounted && widget.active && !_still) _scheduleBlink();
    });
  }

  void _onPointer() {
    final box = context.findRenderObject() as RenderBox?;
    final p = widget.pointer.value;
    var target = Offset.zero;
    if (p != null && box != null && box.hasSize && widget.active && !_still) {
      final v = p - box.localToGlobal(box.size.center(Offset.zero));
      final d = v.distance;
      if (d > 1) target = v / d * math.min(1.0, d / 220);
    }
    if ((target - _lookTo).distance < 0.01) return;
    _lookFrom = _lookAt;
    _lookTo = target;
    _look.forward(from: 0);
  }

  @override
  void dispose() {
    widget.pointer.removeListener(_onPointer);
    _blinkTimer?.cancel();
    _onCurve.dispose();
    _lidCurve.dispose();
    for (final c in [_on, _lid, _blink, _breath, _spin, _zz, _wave, _look]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.size;
    _lastProgress = widget.progress ?? _lastProgress;
    final halo = d * 1.75;
    return SizedBox.square(
      dimension: halo,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _HaloPainter(
                  on: _onCurve,
                  breath: _breath,
                  spin: _spin,
                  zz: _zz,
                  wave: _wave,
                  radius: d / 2,
                  active: widget.active,
                  still: _still,
                ),
              ),
            ),
          ),
          // кольцо таймера: плавный ход раз в секунду, появление/исчезание
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: widget.progress == null ? 0 : 1,
              duration: D.settle,
              curve: Curves.easeOutCubic,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: _lastProgress),
                duration: const Duration(seconds: 1),
                builder: (context, p, _) => CustomPaint(size: Size.square(d * 1.22), painter: _RingPainter(p)),
              ),
            ),
          ),
          Pressable(
            radius: BorderRadius.circular(d / 2),
            pop: 0.94,
            popUp: 110,
            popDown: 420,
            flash: 0.45,
            flashMs: 400,
            hoverScale: 1.03,
            pressScale: 0.96,
            autofocus: true,
            focusTag: 'orb',
            toggled: widget.active,
            semanticLabel: widget.active ? S.current.orbOff : S.current.orbOn,
            onTap: widget.onTap,
            builder: (context, hovered, _) => TweenAnimationBuilder<double>(
              tween: Tween(end: hovered ? 1 : 0),
              duration: const Duration(milliseconds: 200),
              builder: (context, hover, _) => CustomPaint(
                size: Size.square(d),
                painter: _OrbPainter(
                  on: _onCurve,
                  lid: _lidCurve,
                  blink: _blink,
                  look: _look,
                  lookAt: () => _lookAt,
                  hover: hover,
                  error: widget.error,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.on,
    required this.lid,
    required this.blink,
    required this.look,
    required this.lookAt,
    required this.hover,
    required this.error,
  }) : super(repaint: Listenable.merge([on, lid, blink, look]));

  final Animation<double> on, lid, blink, look;
  final Offset Function() lookAt;
  final double hover;
  final bool error;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = size.center(Offset.zero);
    final t = on.value.clamp(0.0, 1.0);

    // «печатная» тень + цветное свечение на hover
    canvas.drawCircle(c + const Offset(0, 3), r, Paint()..color = Color.fromRGBO(0, 0, 0, 0.14 + 0.10 * hover));
    if (hover > 0) {
      canvas.drawCircle(c + const Offset(0, 2), r + 2, Paint()..color = C.accent.withValues(alpha: 0.18 * hover));
    }

    // диск: surface → акцентный градиент (darker(accent,1.15) → accent)
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(lighter(C.surface1, 1.1), lighter(C.accent, 1.04), t)!,
            Color.lerp(C.surface0, darker(C.accent, 1.15), t)!,
          ],
        ).createShader(rect),
    );
    // блик сверху и тонкий ободок
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.6),
          radius: 0.9,
          colors: [
            C.flash.withValues(alpha: 0.10 + 0.08 * t),
            C.flash.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
    canvas.drawCircle(
      c,
      r - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = error ? C.danger.withValues(alpha: 0.9) : C.hairline
        ..strokeWidth = error ? 2 : 1,
    );

    _eye(canvas, c, size.width, t);
  }

  void _eye(Canvas canvas, Offset c, double d, double t) {
    final w = d * 0.5, h = d * 0.19;
    final closure = math.sin(math.pi * blink.value); // 0 → 1 → 0
    final open = lid.value * (1 - closure);
    final up = _lerp(0.6 * h, -2.0 * h, open);
    final low = _lerp(0.6 * h, 1.7 * h, open);
    final ink = Color.lerp(C.subtext0, C.onAccent, t)!;

    canvas.save();
    canvas.translate(c.dx, c.dy + h * 0.1);
    final eye = Path()
      ..moveTo(-w / 2, 0)
      ..quadraticBezierTo(0, up, w / 2, 0)
      ..quadraticBezierTo(0, low, -w / 2, 0)
      ..close();

    if (open > 0.02) {
      canvas.drawPath(eye, Paint()..color = Color.lerp(C.surface0, _sclera, t)!);
      canvas.save();
      canvas.clipPath(eye);
      final ir = h * 0.92;
      final ic = Offset(lookAt().dx * w * 0.2, lookAt().dy * h * 0.35);
      canvas.drawCircle(
        ic,
        ir,
        Paint()
          ..shader = RadialGradient(
            colors: [darker(C.accent, 2.4), C.crust],
          ).createShader(Rect.fromCircle(center: ic, radius: ir)),
      );
      canvas.drawCircle(
        ic,
        ir,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ir * 0.16
          ..color = C.accent.withValues(alpha: 0.55 * t),
      );
      canvas.drawCircle(ic + Offset(-ir * 0.32, -ir * 0.36), ir * 0.24, Paint()..color = _sclera);
      canvas.drawCircle(ic + Offset(ir * 0.3, ir * 0.3), ir * 0.09, Paint()..color = _sclera.withValues(alpha: 0.7));
      canvas.restore();
    }

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = d * 0.024
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = ink;
    canvas.drawPath(eye, stroke);

    // ресницы спящего глаза: торчат вниз от закрытого века
    final lash = (1 - open * 4).clamp(0.0, 1.0);
    if (lash > 0) {
      stroke
        ..color = ink.withValues(alpha: ink.a * lash)
        ..strokeWidth = d * 0.018;
      for (final s in [0.22, 0.5, 0.78]) {
        final x = -w / 2 + w * s;
        final y = 2 * s * (1 - s) * low;
        final dir = Offset((s - 0.5) * 0.9, 1);
        canvas.drawLine(Offset(x, y + d * 0.012), Offset(x, y + d * 0.012) + dir * (h * 0.42), stroke);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.hover != hover || old.error != error;
}

class _HaloPainter extends CustomPainter {
  _HaloPainter({
    required this.on,
    required this.breath,
    required this.spin,
    required this.zz,
    required this.wave,
    required this.radius,
    required this.active,
    required this.still,
  }) : super(repaint: Listenable.merge([on, breath, spin, zz, wave]));

  final Animation<double> on, breath, spin, zz, wave;
  final double radius;
  final bool active, still;

  late final _z = TextPainter(
    text: TextSpan(
      text: 'z',
      style: mono(16, weight: FontWeight.w800, color: C.subtext0),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = radius;
    final t = on.value.clamp(0.0, 1.0);

    // аура
    if (t > 0) {
      final b = still ? 0.8 : _lerp(0.4, 1.0, Curves.easeInOutSine.transform(breath.value));
      final R = r * 1.75;
      canvas.drawCircle(
        c,
        R,
        Paint()
          ..shader = RadialGradient(
            colors: [
              C.accent.withValues(alpha: 0.55 * t * b),
              C.accent.withValues(alpha: 0.2 * t * b),
              C.accent.withValues(alpha: 0),
            ],
            stops: const [0.52, 0.7, 1],
          ).createShader(Rect.fromCircle(center: c, radius: R)),
      );
    }

    // пунктирная орбита
    final orbit = r * 1.34;
    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..color = Color.lerp(C.surface2.withValues(alpha: 0.55), C.accent.withValues(alpha: 0.6), t)!;
    const n = 56;
    final rot = spin.value * 2 * math.pi;
    final rect = Rect.fromCircle(center: c, radius: orbit);
    for (var i = 0; i < n; i++) {
      canvas.drawArc(rect, rot + i * 2 * math.pi / n, 2 * math.pi / n * 0.42, false, dash);
    }
    // спутник
    if (t > 0) {
      final a = -math.pi / 2 - rot * 3;
      final p = c + Offset(math.cos(a), math.sin(a)) * orbit;
      canvas.drawCircle(
        p,
        7,
        Paint()
          ..color = C.accent.withValues(alpha: 0.5 * t)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawCircle(p, 3.5 * t, Paint()..color = lighter(C.accent, 1.1));
    }

    // волна при переключении
    if (wave.isAnimating) {
      final w = Curves.easeOutCubic.transform(wave.value);
      canvas.drawCircle(
        c,
        r * (1 + 0.55 * w),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8 + 2.4 * (1 - w)
          ..color = (active ? C.accent : C.overlay0).withValues(alpha: 0.7 * (1 - w)),
      );
    }

    // «z z z» спящего орба
    final sleep = 1 - t;
    if (sleep > 0) {
      final phases = still ? const [0.35, 0.62] : [for (var k = 0; k < 3; k++) (zz.value + k / 3) % 1];
      for (final p in phases) {
        final pos = c + Offset(r * (0.62 + 0.42 * p), -r * (0.62 + 0.6 * p));
        final s = 0.6 + 0.7 * p;
        final alpha = math.sin(math.pi * p) * sleep * 0.85;
        canvas.save();
        canvas.translate(pos.dx, pos.dy);
        canvas.rotate(-0.25 + 0.3 * p);
        canvas.scale(s);
        canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
        _z.paint(canvas, Offset(-_z.width / 2, -_z.height / 2));
        canvas.restore();
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_HaloPainter old) => old.active != active || old.still != still || old.radius != radius;
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(2);
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = C.surface0,
    );
    if (progress <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = C.accent,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

double _lerp(double a, double b, double t) => a + (b - a) * t;
