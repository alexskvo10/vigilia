import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'controller.dart';
import 'native.dart';
import 'schedule.dart';
import 'strings.dart';

/// Трей и окно: крестик прячет окно в трей, режим продолжает работать.
/// Когда условие закончилось, а окно скрыто, — уведомление Windows.
class Shell with WindowListener {
  Shell(this.c);

  final VigilController c;

  /// Видно ли окно. Когда не видно, анимации ставятся на паузу (TickerMode).
  final visible = ValueNotifier<bool>(true);

  String? _applied;
  Future<void> _queue = Future.value();

  Future<void> init({required bool hidden}) async {
    windowManager.addListener(this);
    Native.listen(onTrayClick: _trayClick, onMenu: _menu, onHotkey: _hotkey);
    c.onFinished = _finished;
    await windowManager.setPreventClose(true);
    c.addListener(_sync);
    _sync();
    await _queue;
    if (hidden) {
      visible.value = false;
    } else {
      await WidgetsBinding.instance.endOfFrame; // без пустого кадра при старте
      await show();
    }
  }

  /// Текст подсказки трея. Тик таймера трей не трогает: применяем только реальные изменения.
  @visibleForTesting
  static String tooltip(VigilController c, S s) {
    if (c.error) return s.trayError;
    if (!c.active) return s.trayOff;
    final end = c.endsAt ?? (c.scheduled ? c.windowEnd : null);
    return '${s.trayOn}${end == null ? '' : s.until(hhmm(end))}${c.keepDisplay ? s.trayDisplay : ''}';
  }

  void _sync() {
    final s = S.current;
    final tip = tooltip(c, s);
    final key = '${c.active}|${s.code}|$tip';
    if (key == _applied) return;
    _applied = key;
    final on = c.active;
    // последовательно, чтобы быстрые переключения не перемешали вызовы
    _queue = _queue.then(
      (_) => Native.setTray(
        on: on,
        tooltip: tip,
        toggle: on ? s.trayTurnOff : s.trayTurnOn,
        show: s.trayShow,
        quit: s.trayQuit,
      ),
    );
  }

  void _finished(Finish reason, String? detail) {
    if (visible.value) return; // окно перед глазами — хватает звука и статуса
    final s = S.current;
    final body = switch (reason) {
      Finish.timer => s.doneTimer,
      Finish.process => s.doneProcess(detail ?? ''),
      Finish.download => s.doneDownload,
      Finish.schedule => s.doneSchedule,
    };
    unawaited(Native.notify('Vigilia', body));
  }

  void _hotkey() {
    c.toggle();
    // при скрытом окне без обратной связи непонятно, что произошло
    if (!visible.value) unawaited(Native.notify('Vigilia', c.active ? S.current.toggledOn : S.current.toggledOff));
  }

  Future<void> show() async {
    visible.value = true;
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> hide() async {
    visible.value = false;
    await windowManager.hide();
  }

  Future<void> quit() async {
    c.removeListener(_sync);
    c.dispose(); // снимает запрос питания
    windowManager.removeListener(this);
    try {
      await Native.removeTray();
      await Native.setHotkey(false);
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } finally {
      exit(0);
    }
  }

  Future<void> _trayClick() async {
    final shown = await windowManager.isVisible() && visible.value;
    if (shown) {
      await hide();
    } else {
      await show();
    }
  }

  void _menu(String id) {
    switch (id) {
      case 'toggle':
        c.toggle();
      case 'show':
        show();
      case 'quit':
        quit();
    }
  }

  @override
  void onWindowClose() => hide();

  @override
  void onWindowMinimize() => visible.value = false;

  @override
  void onWindowRestore() => visible.value = true;

  // Окно могли показать снаружи (второй запуск exe) — оживляем анимации.
  @override
  void onWindowEvent(String eventName) {
    if (eventName == 'show') visible.value = true;
    if (eventName == 'hide') visible.value = false;
  }
}
