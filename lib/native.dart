import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart-сторона канала `vigilia/native` (windows/runner/native_shell.cpp).
class Native {
  static const _channel = MethodChannel('vigilia/native');

  /// Обработчики событий из C++: клик по иконке, пункт меню, горячая клавиша.
  static void listen({
    required void Function() onTrayClick,
    required void Function(String id) onMenu,
    required void Function() onHotkey,
  }) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'trayClick':
          onTrayClick();
        case 'menu':
          onMenu(call.arguments as String);
        case 'hotkey':
          onHotkey();
      }
    });
  }

  static Future<void> setTray({
    required bool on,
    required String tooltip,
    required String toggle,
    required String show,
    required String quit,
  }) => _call('setTray', {'on': on, 'tooltip': tooltip, 'toggle': toggle, 'show': show, 'quit': quit});

  static Future<void> notify(String title, String body) => _call('notify', {'title': title, 'body': body});

  static Future<void> removeTray() => _call('removeTray');

  static Future<bool> setHotkey(bool on) async {
    try {
      return await _channel.invokeMethod<bool>('setHotkey', on) ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> _call(String method, [Object? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on PlatformException catch (e) {
      debugPrint('native.$method: $e');
    }
  }
}
