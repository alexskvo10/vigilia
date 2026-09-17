import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../hotkey.dart';
import '../strings.dart';
import '../theme.dart';
import 'pressable.dart';

/// Сочетание клавиш «клавишами»: клик (или Enter/пробел) — запись нового сочетания.
/// Во время записи зажатые модификаторы сразу появляются клавишами, а подпись «дышит»
/// (1800ms InOutSine). Без Ctrl/Alt/Win поле трясётся: 0 → −6 → 6 → −4 → 4 → 0 по 50ms.
/// Новые клавиши входят по очереди с шагом 20ms (scale 0.55→1 OutBack 1.35, y +4→0).
/// Esc, клик мимо или уход из окна отменяют запись.
class HotkeyField extends StatefulWidget {
  const HotkeyField({
    super.key,
    required this.value,
    required this.busy,
    required this.busyText,
    required this.onChanged,
    required this.onRecording,
  });

  final Hotkey value;
  final bool busy;
  final String busyText; // «занята другой программой» после клавиш
  final ValueChanged<Hotkey> onChanged;
  final ValueChanged<bool> onRecording;

  @override
  State<HotkeyField> createState() => _HotkeyFieldState();
}

class _HotkeyFieldState extends State<HotkeyField> with TickerProviderStateMixin {
  late final _node = FocusNode(debugLabel: 'hotkey', onKeyEvent: _onKey);
  late final _breath = AnimationController(vsync: this, duration: D.breathe);
  late final _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
  late final _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 320), value: 1);
  late final AppLifecycleListener _lifecycle;
  bool _recording = false, _invalid = false;
  List<String> _held = const [];

  @override
  void initState() {
    super.initState();
    _node.addListener(() {
      if (!_node.hasFocus) _cancel();
    });
    // окно ушло на задний план — запись отменяется, иначе сочетание осталось бы снятым
    _lifecycle = AppLifecycleListener(onInactive: _cancel, onHide: _cancel);
  }

  @override
  void dispose() {
    // запись могла идти: вернуть сочетание в Windows, но не во время разборки дерева
    if (_recording) {
      final onRecording = widget.onRecording;
      Future.microtask(() => onRecording(false));
    }
    _lifecycle.dispose();
    _node.dispose();
    _breath.dispose();
    _shake.dispose();
    _enter.dispose();
    super.dispose();
  }

  void _start() {
    if (_recording) return;
    setState(() {
      _recording = true;
      _invalid = false;
      _held = const [];
    });
    _node.requestFocus();
    if (!reduceMotion(context)) _breath.repeat(reverse: true);
    widget.onRecording(true);
  }

  void _stop() {
    _breath
      ..stop()
      ..value = 0;
    setState(() {
      _recording = false;
      _held = const [];
    });
  }

  void _cancel() {
    if (!_recording) return;
    _stop();
    widget.onRecording(false);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (!_recording) return KeyEventResult.ignored;
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    if (e is KeyUpEvent || Hotkey.isModifier(e.logicalKey)) {
      // показываем зажатые модификаторы, пока основная клавиша не нажата
      final preview = Hotkey.fromEvent(LogicalKeyboardKey.keyA, pressed)!;
      setState(() {
        _held = preview.parts.sublist(0, preview.parts.length - 1);
        if (e is KeyDownEvent) _invalid = false; // новая попытка — предупреждение гаснет
      });
      return KeyEventResult.handled;
    }
    if (e is! KeyDownEvent) return KeyEventResult.handled;
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    final key = Hotkey.fromEvent(e.logicalKey, pressed);
    if (key == null || !key.valid) {
      setState(() => _invalid = true);
      if (!reduceMotion(context)) _shake.forward(from: 0);
      return KeyEventResult.handled;
    }
    _stop();
    _invalid = false;
    if (!reduceMotion(context)) _enter.forward(from: 0);
    widget.onChanged(key);
    return KeyEventResult.handled;
  }

  // 0 → −6 → 6 → −4 → 4 → 0, по 50ms на шаг
  double get _shakeX {
    const steps = [0.0, -6.0, 6.0, -4.0, 4.0, 0.0];
    if (!_shake.isAnimating) return 0;
    final t = _shake.value * 5;
    final i = math.min(t.floor(), 4);
    return steps[i] + (steps[i + 1] - steps[i]) * (t - i);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.current;
    final signal = _invalid ? C.warning : C.accent;
    // отдельный узел доступности: иначе подпись сольётся со строкой переключателя
    return Semantics(
      container: true,
      child: TapRegion(
        onTapOutside: (_) => _cancel(),
        child: AnimatedBuilder(
          animation: _shake,
          builder: (context, child) => Transform.translate(offset: Offset(_shakeX, 0), child: child),
          child: Pressable(
            focusNode: _node,
            radius: BorderRadius.circular(6),
            pop: 1.04,
            flash: 0.25,
            pressScale: 0.97,
            semanticLabel: '${s.hotkey}: ${widget.value.label}',
            onTap: _start,
            builder: (context, hovered, _) => AnimatedContainer(
              duration: D.color,
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: _recording ? signal.withValues(alpha: 0.12) : (hovered ? C.hairline : const Color(0x00FFFFFF)),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _recording ? signal.withValues(alpha: 0.7) : const Color(0x00FFFFFF)),
              ),
              child: AnimatedSize(
                duration: D.base,
                curve: Curves.easeOutCubic,
                alignment: Alignment.centerLeft,
                // подпись кнопки уже содержит сочетание — текст клавиш озвучивать не нужно
                child: ExcludeSemantics(
                  child: _recording ? _recordingRow(s, signal) : _caps(widget.value.parts, hovered),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _recordingRow(S s, Color signal) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ..._held.map((p) => _Cap(p, color: C.text)),
      if (_held.isNotEmpty) const SizedBox(width: 2),
      Flexible(
        child: AnimatedBuilder(
          animation: _breath,
          builder: (context, _) => Opacity(
            opacity: 1 - 0.6 * Curves.easeInOutSine.transform(_breath.value),
            child: Text(
              _invalid ? s.hotkeyNeedsModifier : s.hotkeyPress,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono(9.5, weight: FontWeight.w600, color: signal),
            ),
          ),
        ),
      ),
      const SizedBox(width: 3),
    ],
  );

  Widget _caps(List<String> parts, bool hovered) => AnimatedBuilder(
    animation: _enter,
    builder: (context, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, p) in parts.indexed)
          _entering(i, _Cap(p, color: widget.busy ? C.warning : (hovered ? C.accent : C.text))),
        if (widget.busy) ...[
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              widget.busyText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono(9.5, weight: FontWeight.w500, color: C.warning),
            ),
          ),
          const SizedBox(width: 2),
        ],
      ],
    ),
  );

  Widget _entering(int i, Widget cap) {
    if (_enter.isCompleted) return cap;
    final ms = _enter.value * 320 - i * 20;
    final t = (ms / 240).clamp(0.0, 1.0);
    return Opacity(
      opacity: (ms / 150).clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, 4 * (1 - const OutBack(1.25).transform((ms / 220).clamp(0.0, 1.0)))),
        child: Transform.scale(scale: 0.55 + 0.45 * const OutBack(1.35).transform(t), child: cap),
      ),
    );
  }
}

/// Одна клавиша: «клавиатурная» плашка с тёмной кромкой снизу.
class _Cap extends StatelessWidget {
  const _Cap(this.label, {required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 1.5),
    padding: const EdgeInsets.symmetric(horizontal: 5),
    height: 16,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: C.surface1,
      borderRadius: BorderRadius.circular(4),
      boxShadow: [BoxShadow(color: C.crust, offset: const Offset(0, 1.5))],
    ),
    child: Text(label, style: mono(9.5, color: color)),
  );
}
