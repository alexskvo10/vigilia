import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'controller.dart';

/// Трей и окно: крестик прячет окно в трей, режим продолжает работать.
class Shell with TrayListener, WindowListener {
  Shell(this.c);

  final VigilController c;

  /// Видно ли окно. Когда не видно, анимации ставятся на паузу (TickerMode).
  final visible = ValueNotifier<bool>(true);

  String? _applied;
  Future<void> _queue = Future.value();

  Future<void> init({required bool hidden}) async {
    trayManager.addListener(this);
    windowManager.addListener(this);
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

  // Тик таймера каждую секунду трей не трогает: применяем только реальные изменения.
  void _sync() {
    final end = c.endsAt;
    final hhmm = end == null
        ? ''
        : ' до ${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
    final tip = c.error
        ? 'Vigilia — ошибка запроса питания'
        : c.active
        ? 'Vigilia — не даю уснуть$hhmm${c.keepDisplay ? ' · экран включён' : ''}'
        : 'Vigilia — обычный сон';
    final key = '${c.active}|$tip';
    if (key == _applied) return;
    _applied = key;
    final active = c.active;
    // последовательно, чтобы быстрые переключения не перемешали вызовы
    _queue = _queue.then((_) async {
      try {
        await trayManager.setIcon(active ? 'assets/tray_on.ico' : 'assets/tray_off.ico');
        await trayManager.setToolTip(tip);
        await trayManager.setContextMenu(
          Menu(
            items: [
              MenuItem(key: 'toggle', label: active ? 'Выключить' : 'Включить'),
              MenuItem(key: 'show', label: 'Показать окно'),
              MenuItem.separator(),
              MenuItem(key: 'quit', label: 'Выход'),
            ],
          ),
        );
      } catch (e) {
        debugPrint('tray: $e');
      }
    });
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
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    try {
      await trayManager.destroy();
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } finally {
      exit(0);
    }
  }

  @override
  void onTrayIconMouseDown() async {
    final shown = await windowManager.isVisible() && visible.value;
    shown ? hide() : show();
  }

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
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
