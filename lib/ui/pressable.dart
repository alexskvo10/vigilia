import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme.dart';

/// Навигация с клавиатуры: true после нажатия клавиши, false после клика.
/// На десктопе Flutter показывает фокус всегда — а кольцо нужно только клавиатурным пользователям.
final keyboardMode = ValueNotifier(false);

void trackKeyboardMode() {
  HardwareKeyboard.instance.addHandler((e) {
    if (e is KeyDownEvent) keyboardMode.value = true;
    return false;
  });
  GestureBinding.instance.pointerRouter.addGlobalRoute((e) {
    if (e is PointerDownEvent) keyboardMode.value = false;
  });
}

/// Фокус переживает пересоздание экрана (смена цвета/языка): кнопки с одинаковым
/// [Pressable.focusTag] в старом и новом дереве считаются одной и той же кнопкой.
String? _focusMemory; // тег последней сфокусированной кнопки (null — кнопка без тега)
String? _focusRestore; // тег, который нужно сфокусировать в только что построенном дереве

/// Вызывается перед постройкой нового экрана: фокус перейдёт к кнопке с тем же тегом,
/// а если фокус был на кнопке без тега — к глазу.
void restoreFocusOnRebuild() {
  _focusRestore = _focusMemory ?? 'orb';
  // новые кнопки создаются в этом же кадре; после него запрос не действует
  SchedulerBinding.instance.addPostFrameCallback((_) => _focusRestore = null);
}

typedef PressBuilder = Widget Function(BuildContext context, bool hovered, bool pressed);

/// «Тройной отклик»: hover/press-масштаб (250ms OutQuint),
/// поп (вверх OutQuad → назад OutQuint) и белая вспышка (OutExpo).
/// Звук играет контроллер. Space/Enter нажимают, фокус с клавиатуры обводится акцентом.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.onTap,
    required this.builder,
    required this.radius,
    this.pop = 1.04,
    this.popUp = 100,
    this.popDown = 350,
    this.flash = 0.2,
    this.flashMs = 350,
    this.hoverScale = 1.0,
    this.pressScale = 1.0,
    this.focusNode,
    this.focusTag,
    this.autofocus = false,
    this.semanticLabel,
    this.selected,
    this.toggled,
  });

  final VoidCallback onTap;
  final PressBuilder builder;
  final BorderRadius radius;
  final double pop, flash, hoverScale, pressScale;
  final int popUp, popDown, flashMs;
  final FocusNode? focusNode;
  final String? focusTag;
  final bool autofocus;
  final String? semanticLabel;
  final bool? selected, toggled;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> with TickerProviderStateMixin {
  late final _pop = AnimationController(vsync: this);
  late final _flash = AnimationController(vsync: this);
  bool _hovered = false, _pressed = false, _focusRing = false;
  FocusNode? _ownNode;
  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _syncDurations();
    if (widget.focusTag != null && widget.focusTag == _focusRestore) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _node.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(Pressable old) {
    super.didUpdateWidget(old);
    _syncDurations();
  }

  void _syncDurations() {
    _pop.duration = Duration(milliseconds: widget.popUp + widget.popDown);
    _flash.duration = Duration(milliseconds: widget.flashMs);
  }

  @override
  void dispose() {
    _pop.dispose();
    _flash.dispose();
    _ownNode?.dispose();
    super.dispose();
  }

  void _fire() {
    if (!reduceMotion(context)) _pop.forward(from: 0);
    _flash.forward(from: 0);
    widget.onTap();
  }

  double _popValue() {
    final t = _pop.value, up = widget.popUp / (widget.popUp + widget.popDown);
    if (!_pop.isAnimating || t >= 1) return 1;
    if (t < up) return 1 + (widget.pop - 1) * Curves.easeOutQuad.transform(t / up);
    return widget.pop + (1 - widget.pop) * Curves.easeOutQuint.transform((t - up) / (1 - up));
  }

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    final scale = still ? 1.0 : (_pressed ? widget.pressScale : (_hovered ? widget.hoverScale : 1.0));
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      selected: widget.selected,
      toggled: widget.toggled,
      child: FocusableActionDetector(
        focusNode: _node,
        autofocus: widget.autofocus,
        onFocusChange: (v) {
          if (v) _focusMemory = widget.focusTag;
        },
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hovered = v),
        onShowFocusHighlight: (v) => setState(() => _focusRing = v),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        },
        actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => _fire())},
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: _fire,
          child: AnimatedBuilder(
            animation: _pop,
            builder: (context, child) => Transform.scale(scale: _popValue(), child: child),
            child: AnimatedScale(
              scale: scale,
              duration: D.base,
              curve: Curves.easeOutQuint,
              child: Stack(
                // размеры родителя проходят к содержимому как есть: иначе оно сжимается
                // до своей высоты и прилипает к верху (была кривая кнопка «Настройки»)
                fit: StackFit.passthrough,
                clipBehavior: Clip.none,
                children: [
                  widget.builder(context, _hovered, _pressed),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _flash,
                        builder: (context, _) {
                          final o = _flash.isAnimating
                              ? widget.flash * (1 - Curves.easeOutExpo.transform(_flash.value))
                              : 0.0;
                          return o <= 0
                              ? const SizedBox.shrink()
                              : DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: C.flash.withValues(alpha: o),
                                    borderRadius: widget.radius,
                                  ),
                                );
                        },
                      ),
                    ),
                  ),
                  if (_focusRing)
                    Positioned.fill(
                      left: -3,
                      top: -3,
                      right: -3,
                      bottom: -3,
                      child: IgnorePointer(
                        child: ValueListenableBuilder(
                          valueListenable: keyboardMode,
                          builder: (context, keyboard, _) => AnimatedOpacity(
                            opacity: keyboard ? 1 : 0,
                            duration: D.color,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(color: C.accent, width: 2),
                                borderRadius: widget.radius + BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
