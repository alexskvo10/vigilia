import 'package:flutter/services.dart';

/// Сочетание глобальной клавиши в терминах RegisterHotKey:
/// модификаторы MOD_* и виртуальный код клавиши VK_*.
class Hotkey {
  const Hotkey(this.mods, this.vk);

  static const alt = 0x1, ctrl = 0x2, shift = 0x4, win = 0x8;
  static const fallback = Hotkey(ctrl | alt, 0x56); // Ctrl+Alt+V

  final int mods, vk;

  /// Без Ctrl, Alt или Win сочетание перехватывало бы обычный ввод.
  bool get valid => mods & (ctrl | alt | win) != 0 && _names.containsKey(vk);

  List<String> get parts => [
    if (mods & ctrl != 0) 'Ctrl',
    if (mods & alt != 0) 'Alt',
    if (mods & shift != 0) 'Shift',
    if (mods & win != 0) 'Win',
    _names[vk] ?? '?',
  ];

  String get label => parts.join('+');

  @override
  bool operator ==(Object other) => other is Hotkey && other.mods == mods && other.vk == vk;

  @override
  int get hashCode => Object.hash(mods, vk);

  Map<String, int> toJson() => {'mods': mods, 'vk': vk};

  static Hotkey fromJson(Object? j) {
    if (j is Map && j['mods'] is int && j['vk'] is int) {
      final k = Hotkey((j['mods'] as int) & 0xF, j['vk'] as int);
      if (k.valid) return k;
    }
    return fallback;
  }

  /// Сочетание из нажатой клавиши и зажатых модификаторов; null — клавиша не подходит
  /// (сам модификатор или клавиша без кода в таблице).
  static Hotkey? fromEvent(LogicalKeyboardKey key, Set<LogicalKeyboardKey> pressed) {
    final vk = _vk[key];
    if (vk == null) return null;
    bool any(Set<LogicalKeyboardKey> keys) => pressed.any(keys.contains);
    final mods =
        (any(_ctrlKeys) ? ctrl : 0) |
        (any(_altKeys) ? alt : 0) |
        (any(_shiftKeys) ? shift : 0) |
        (any(_winKeys) ? win : 0);
    return Hotkey(mods, vk);
  }

  static bool isModifier(LogicalKeyboardKey key) =>
      _ctrlKeys.contains(key) || _altKeys.contains(key) || _shiftKeys.contains(key) || _winKeys.contains(key);
}

final _ctrlKeys = {LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlRight, LogicalKeyboardKey.control};
final _altKeys = {LogicalKeyboardKey.altLeft, LogicalKeyboardKey.altRight, LogicalKeyboardKey.alt};
final _shiftKeys = {LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftRight, LogicalKeyboardKey.shift};
final _winKeys = {LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaRight, LogicalKeyboardKey.meta};

// Буквы и цифры берутся из логической клавиши: Flutter сводит их к латинице и на русской
// раскладке, а VK_* букв тоже не зависят от кириллицы.
final Map<LogicalKeyboardKey, int> _vk = {
  for (var i = 0; i < 26; i++) LogicalKeyboardKey(LogicalKeyboardKey.keyA.keyId + i): 0x41 + i,
  for (var i = 0; i < 10; i++) LogicalKeyboardKey(LogicalKeyboardKey.digit0.keyId + i): 0x30 + i,
  for (final (i, k) in _fKeys.indexed) k: 0x70 + i,
  LogicalKeyboardKey.space: 0x20,
  LogicalKeyboardKey.pageUp: 0x21,
  LogicalKeyboardKey.pageDown: 0x22,
  LogicalKeyboardKey.end: 0x23,
  LogicalKeyboardKey.home: 0x24,
  LogicalKeyboardKey.arrowLeft: 0x25,
  LogicalKeyboardKey.arrowUp: 0x26,
  LogicalKeyboardKey.arrowRight: 0x27,
  LogicalKeyboardKey.arrowDown: 0x28,
  LogicalKeyboardKey.insert: 0x2D,
  LogicalKeyboardKey.delete: 0x2E,
  LogicalKeyboardKey.pause: 0x13,
};

const _fKeys = [
  LogicalKeyboardKey.f1,
  LogicalKeyboardKey.f2,
  LogicalKeyboardKey.f3,
  LogicalKeyboardKey.f4,
  LogicalKeyboardKey.f5,
  LogicalKeyboardKey.f6,
  LogicalKeyboardKey.f7,
  LogicalKeyboardKey.f8,
  LogicalKeyboardKey.f9,
  LogicalKeyboardKey.f10,
  LogicalKeyboardKey.f11,
  LogicalKeyboardKey.f12,
  LogicalKeyboardKey.f13,
  LogicalKeyboardKey.f14,
  LogicalKeyboardKey.f15,
  LogicalKeyboardKey.f16,
  LogicalKeyboardKey.f17,
  LogicalKeyboardKey.f18,
  LogicalKeyboardKey.f19,
  LogicalKeyboardKey.f20,
  LogicalKeyboardKey.f21,
  LogicalKeyboardKey.f22,
  LogicalKeyboardKey.f23,
  LogicalKeyboardKey.f24,
];

final Map<int, String> _names = {
  for (var i = 0; i < 26; i++) 0x41 + i: String.fromCharCode(0x41 + i),
  for (var i = 0; i < 10; i++) 0x30 + i: '$i',
  for (var i = 0; i < 24; i++) 0x70 + i: 'F${i + 1}',
  0x20: 'Space',
  0x21: 'PgUp',
  0x22: 'PgDn',
  0x23: 'End',
  0x24: 'Home',
  0x25: '←',
  0x26: '↑',
  0x27: '→',
  0x28: '↓',
  0x2D: 'Ins',
  0x2E: 'Del',
  0x13: 'Pause',
};
