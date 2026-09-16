import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme.dart';
import 'pressable.dart';

/// Сегментный переключатель с «гусеницей»: передний край плашки едет 200ms,
/// задний 350ms (OutExpo), поэтому плашка сначала тянется, потом подтягивает хвост.
/// Стрелки ←/→ переключают выбор.
class Segmented<T> extends StatefulWidget {
  const Segmented({super.key, required this.items, required this.value, required this.onChanged, this.label});

  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;
  final String? label;

  @override
  State<Segmented<T>> createState() => _SegmentedState<T>();
}

/// Край плашки: едет от текущего положения к цели со своей длительностью.
class _Edge {
  _Edge(TickerProvider vsync, double at) : _from = at, _to = at, ctrl = AnimationController(vsync: vsync);
  final AnimationController ctrl;
  double _from, _to;

  double get value => _from + (_to - _from) * Curves.easeOutExpo.transform(ctrl.value);

  void moveTo(double to, int ms) {
    if (to == _to) return;
    _from = value;
    _to = to;
    ctrl
      ..duration = Duration(milliseconds: ms)
      ..forward(from: 0);
  }

  void jump(double to) {
    ctrl.value = 1;
    _from = _to = to;
  }
}

class _SegmentedState<T> extends State<Segmented<T>> with TickerProviderStateMixin {
  static const _h = 32.0, _inset = 3.0, _r = 8.0;
  late final _left = _Edge(this, _index.toDouble());
  late final _right = _Edge(this, _index + 1.0);
  late final _nodes = List.generate(widget.items.length, (i) => FocusNode(debugLabel: 'seg$i'));

  int get _index => widget.items.indexWhere((e) => e.$1 == widget.value).clamp(0, widget.items.length - 1);

  @override
  void didUpdateWidget(Segmented<T> old) {
    super.didUpdateWidget(old);
    final to = _index.toDouble();
    if (reduceMotion(context)) {
      _left.jump(to);
      _right.jump(to + 1);
    } else {
      final forward = to > _left._to;
      _left.moveTo(to, forward ? 350 : 200);
      _right.moveTo(to + 1, forward ? 200 : 350);
    }
  }

  @override
  void dispose() {
    _left.ctrl.dispose();
    _right.ctrl.dispose();
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final d = switch (e.logicalKey) {
      LogicalKeyboardKey.arrowLeft => -1,
      LogicalKeyboardKey.arrowRight => 1,
      _ => 0,
    };
    if (d == 0) return KeyEventResult.ignored;
    final i = (_index + d).clamp(0, widget.items.length - 1);
    if (i != _index) widget.onChanged(widget.items[i].$1);
    _nodes[i].requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.items.length, sel = _index;
    return Semantics(
      label: widget.label,
      container: true,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onKey,
        child: Container(
          height: _h,
          decoration: BoxDecoration(
            color: C.hairline,
            borderRadius: BorderRadius.circular(_r),
            border: Border.all(color: C.hairline),
          ),
          child: LayoutBuilder(
            builder: (context, box) {
              final w = (box.maxWidth - _inset * 2) / n;
              return Stack(
                children: [
                  AnimatedBuilder(
                    animation: Listenable.merge([_left.ctrl, _right.ctrl]),
                    builder: (context, _) => Positioned(
                      left: _inset + _left.value * w,
                      right: box.maxWidth - _inset - _right.value * w,
                      top: _inset,
                      bottom: _inset,
                      child: AnimatedContainer(
                        duration: D.color,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [darker(C.accent, 1.08), C.accent]),
                          // внешние углы — радиус контрола, внутренние — 2px
                          borderRadius: BorderRadius.horizontal(
                            left: Radius.circular(sel == 0 ? _r - _inset + 1 : 2),
                            right: Radius.circular(sel == n - 1 ? _r - _inset + 1 : 2),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      const SizedBox(width: _inset),
                      for (var i = 0; i < n; i++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: _inset),
                            child: Pressable(
                              focusNode: _nodes[i],
                              radius: BorderRadius.circular(_r - _inset),
                              pressScale: 0.96,
                              selected: i == sel,
                              semanticLabel: widget.items[i].$2,
                              onTap: () {
                                if (i != sel) widget.onChanged(widget.items[i].$1);
                              },
                              builder: (context, hovered, pressed) => AnimatedContainer(
                                duration: D.color,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: hovered && i != sel ? C.hairline : const Color(0x00FFFFFF),
                                  borderRadius: BorderRadius.circular(_r - _inset),
                                ),
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 200),
                                  style: mono(
                                    11,
                                    weight: i == sel ? FontWeight.w700 : FontWeight.w500,
                                    color: i == sel ? C.onAccent : (hovered ? C.text : C.subtext0),
                                  ),
                                  child: Text(
                                    widget.items[i].$2,
                                    maxLines: 1,
                                    overflow: TextOverflow.fade,
                                    softWrap: false,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(width: _inset),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
