import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../theme.dart';
import 'motion.dart';
import 'pressable.dart';

/// Панель настроек, которая «вырастает» из кнопки-пилюли: форма тянется вверх
/// и в ширину (450ms OutQuint, закрытие 300ms InCubic), на стыке с кнопкой
/// появляются вогнутые скругления — кнопка и панель читаются как одна форма.
/// Содержимое проявляется позже формы, строки въезжают слева каскадом.
class SettingsDrawer extends StatefulWidget {
  const SettingsDrawer({super.key, required this.open, required this.onToggle, required this.children});

  final bool open;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  State<SettingsDrawer> createState() => _SettingsDrawerState();
}

class _SettingsDrawerState extends State<SettingsDrawer> with SingleTickerProviderStateMixin {
  static const _tabW = 184.0, _tabH = 36.0;
  final _panelFocus = FocusNode(skipTraversal: true, canRequestFocus: false);
  final _tabFocus = FocusNode(debugLabel: 'settings-tab');

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
    reverseDuration: D.panel,
    value: widget.open ? 1 : 0,
  );
  late final CurvedAnimation _p = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutQuint,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void didUpdateWidget(SettingsDrawer old) {
    super.didUpdateWidget(old);
    if (old.open == widget.open) return;
    // фокус был внутри закрывающейся панели — переносим его на кнопку, а не теряем
    if (!widget.open && _panelFocus.hasFocus) _tabFocus.requestFocus();
    if (reduceMotion(context)) {
      _c.value = widget.open ? 1 : 0;
    } else {
      widget.open ? _c.forward() : _c.reverse();
    }
  }

  @override
  void dispose() {
    _p.dispose();
    _c.dispose();
    _panelFocus.dispose();
    _tabFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => AnimatedBuilder(
        animation: _p,
        builder: (context, _) {
          final p = _p.value;
          final panelW = _tabW + (box.maxWidth - _tabW) * Curves.easeOut.transform(p);
          // контент отстаёт от формы: сначала растёт панель, потом проявляется текст
          final reveal = ((p - 0.2) / 0.8).clamp(0.0, 1.0);
          return CustomPaint(
            painter: _DrawerPainter(p: p, panelW: panelW, tabW: _tabW, tabH: _tabH),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  clipper: _PanelClip(panelW),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    heightFactor: p,
                    child: Focus(
                      focusNode: _panelFocus,
                      child: ExcludeFocus(
                        excluding: !widget.open,
                        child: IgnorePointer(
                          ignoring: !widget.open,
                          child: Opacity(
                            opacity: reveal,
                            child: SizedBox(
                              width: box.maxWidth,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    for (var i = 0; i < widget.children.length; i++) _stagger(i, widget.children[i]),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                _tab(p),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Каскад строк при открытии: старт min(i,10)·0.04, выезд слева с −20px
  /// (окно 0.42, OutBack 0.85), прозрачность (окно 0.28). При закрытии — без каскада.
  Widget _stagger(int i, Widget child) {
    if (_c.status != AnimationStatus.forward || reduceMotion(context)) return child;
    final start = math.min(i, 10) * 0.04;
    final t = _c.value - start;
    final slide = const OutBack(0.85).transform((t / 0.42).clamp(0.0, 1.0));
    return Opacity(
      opacity: (t / 0.28).clamp(0.0, 1.0),
      child: Transform.translate(offset: Offset(-20 * (1 - slide), 0), child: child),
    );
  }

  Widget _tab(double p) {
    final open = widget.open;
    final still = reduceMotion(context);
    return SizedBox(
      width: _tabW,
      height: _tabH,
      child: Pressable(
        focusNode: _tabFocus,
        radius: BorderRadius.circular(_tabH / 2),
        // форму кнопки рисует панель и она не масштабируется, поэтому содержимое
        // не должно выходить наружу: без увеличения на hover, клик — сжатие внутрь
        pop: 0.96,
        popUp: 110,
        popDown: 400,
        pressScale: 0.97,
        toggled: open,
        semanticLabel: open ? 'Скрыть настройки' : 'Настройки',
        onTap: widget.onToggle,
        builder: (context, hovered, _) => AnimatedContainer(
          duration: D.color,
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: C.text.withValues(alpha: hovered ? 0.07 : 0),
            borderRadius: BorderRadius.circular(_tabH / 2),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          child: Row(
            children: [
              // шестерёнка проворачивается на пол-оборота с пружинкой
              TweenAnimationBuilder<double>(
                tween: Tween(end: open ? 0.5 : 0),
                duration: still ? Duration.zero : D.slow,
                curve: const OutBack(1.4),
                builder: (context, turns, child) => Transform.rotate(angle: turns * 2 * math.pi, child: child),
                child: AnimatedSwitcher(
                  duration: D.color,
                  child: Icon(
                    Icons.settings_rounded,
                    key: ValueKey(open || hovered),
                    size: 15,
                    color: open || hovered ? C.accent : C.subtext0,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Letters(open ? 'Скрыть' : 'Настройки', style: mono(12, color: open ? C.text : C.subtext0)),
                ),
              ),
              const SizedBox(width: 4),
              Transform.rotate(
                angle: math.pi * (1 - p),
                child: const Icon(Icons.expand_more_rounded, size: 16, color: C.overlay0),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Форма «панель + кнопка»: объединение скруглённой панели, пилюли и двух
/// вогнутых скруглений на стыке. Высота панели = всё, что выше кнопки.
Path drawerPath(Size size, {required double panelW, required double tabW, required double tabH}) {
  const radius = 14.0, fillet = 12.0;
  final cx = size.width / 2;
  final panelH = size.height - tabH;
  // 0 → кнопка отдельная пилюля, 1 → кнопка срослась с панелью
  final k = (panelH / (fillet * 2)).clamp(0.0, 1.0);
  final topR = Radius.circular(tabH / 2 * (1 - k));
  final bottomR = Radius.circular(tabH / 2);

  var path = Path()
    ..addRRect(
      RRect.fromRectAndCorners(
        // на 1px выше, чтобы на стыке с панелью не было шва сглаживания
        Rect.fromLTWH(cx - tabW / 2, panelH - (k > 0 ? 1 : 0), tabW, tabH + (k > 0 ? 1 : 0)),
        topLeft: topR,
        topRight: topR,
        bottomLeft: bottomR,
        bottomRight: bottomR,
      ),
    );
  if (panelH < 0.5) return path;

  final panel = Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - panelW / 2, 0, panelW, panelH),
        Radius.circular(math.min(radius, panelH / 2)),
      ),
    );
  path = Path.combine(PathOperation.union, path, panel);

  final r = math.min(fillet * k, (panelW - tabW) / 2);
  if (r < 0.5) return path;
  for (final side in const [-1.0, 1.0]) {
    final x = cx + side * tabW / 2;
    final square = Path()..addRect(Rect.fromLTWH(side < 0 ? x - r : x, panelH - 1, r, r + 1));
    final cut = Path()..addOval(Rect.fromCircle(center: Offset(x + side * r, panelH + r), radius: r));
    path = Path.combine(PathOperation.union, path, Path.combine(PathOperation.difference, square, cut));
  }
  return path;
}

class _DrawerPainter extends CustomPainter {
  _DrawerPainter({required this.p, required this.panelW, required this.tabW, required this.tabH});
  final double p, panelW, tabW, tabH;

  static final _fill = Color.alphaBlend(C.surface0.withValues(alpha: 0.6), C.base);

  @override
  void paint(Canvas canvas, Size size) {
    final path = drawerPath(size, panelW: panelW, tabW: tabW, tabH: tabH);
    // «печатная» тень: та же форма, сдвинутая на 2px
    canvas.drawPath(path.shift(const Offset(0, 2)), Paint()..color = const Color(0x24000000));
    canvas.drawPath(path, Paint()..color = _fill);
  }

  @override
  bool shouldRepaint(_DrawerPainter old) => old.p != p || old.panelW != panelW || old.tabW != tabW || old.tabH != tabH;
}

class _PanelClip extends CustomClipper<RRect> {
  _PanelClip(this.width);
  final double width;

  @override
  RRect getClip(Size size) => RRect.fromRectAndRadius(
    Rect.fromCenter(center: size.center(Offset.zero), width: width, height: size.height),
    Radius.circular(math.min(14, size.height / 2)),
  );

  @override
  bool shouldReclip(_PanelClip old) => old.width != width;
}
