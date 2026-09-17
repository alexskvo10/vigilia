import 'dart:convert';
import 'dart:io';

import 'hotkey.dart';
import 'schedule.dart';
import 'theme.dart';

/// До каких пор держать компьютер бодрым после ручного включения.
enum Until { always, timer, process, download }

const timerPresets = [30, 60, 120, 240];
const maxWatched = 10;

/// Пороги скорости режима «загрузка», КБ/с.
const downloadPresets = [50, 100, 500, 1000];

/// Программа, пока работает которая компьютер не спит.
/// Имя — для показа и быстрого сравнения, путь — чтобы не спутать разные программы с одинаковым exe.
/// Путь null, если Windows не дала его прочитать: тогда сравнивается только имя.
class WatchedProcess {
  WatchedProcess(String name, String? path) : name = name.toLowerCase(), path = path?.toLowerCase();

  final String name;
  final String? path;

  String get key => path ?? name;

  /// Папка exe для подсказки, когда одинаковых имён несколько.
  String? get folder {
    final p = path;
    if (p == null) return null;
    final parts = p.split(r'\');
    return parts.length < 2 ? null : parts[parts.length - 2];
  }

  @override
  bool operator ==(Object other) => other is WatchedProcess && other.key == key && other.name == name;

  @override
  int get hashCode => Object.hash(name, key);

  Map<String, Object?> toJson() => {'name': name, 'path': path};

  static WatchedProcess? fromJson(Object? j) {
    if (j is! Map || j['name'] is! String || (j['name'] as String).isEmpty) return null;
    final path = j['path'];
    return WatchedProcess(j['name'] as String, path is String && path.isNotEmpty ? path : null);
  }

  @override
  String toString() => key;
}

class Settings {
  bool keepDisplay = false;
  Until until = Until.always;
  int timerMinutes = 60;
  List<WatchedProcess> processes = [];
  int downloadKbps = 100;
  String? adapter; // GUID адаптера; null — все физические
  String? adapterName; // имя для показа, если адаптер сейчас не подключён
  Schedule schedule = const Schedule();
  bool sounds = true;
  bool hotkey = true;
  bool checkUpdates = true;
  Hotkey hotkeyKey = Hotkey.fallback;
  int accent = 0;
  String? language; // null — язык системы
  bool wasActive = false;

  Map<String, Object?> toJson() => {
    'keepDisplay': keepDisplay,
    'until': until.name,
    'timerMinutes': timerMinutes,
    'processes': [for (final p in processes) p.toJson()],
    'downloadKbps': downloadKbps,
    'adapter': adapter,
    'adapterName': adapterName,
    'schedule': schedule.toJson(),
    'sounds': sounds,
    'hotkey': hotkey,
    'checkUpdates': checkUpdates,
    'hotkeyKey': hotkeyKey.toJson(),
    'accent': accent,
    'language': language,
    'wasActive': wasActive,
  };

  static Settings fromJson(Object? j) {
    final s = Settings();
    if (j is! Map) return s;
    if (j['keepDisplay'] case bool v) s.keepDisplay = v;
    if (j['until'] case String v) s.until = Until.values.asNameMap()[v] ?? Until.always;
    if (j['timerMinutes'] case int v when timerPresets.contains(v)) s.timerMinutes = v;
    if (j['processes'] case List v) {
      s.processes = {for (final e in v) ?WatchedProcess.fromJson(e)}.take(maxWatched).toList();
    } else if (j['processName'] case String v when v.isNotEmpty) {
      s.processes = [WatchedProcess(v, null)]; // настройки версии 1.1
    }
    if (j['downloadKbps'] case int v when downloadPresets.contains(v)) s.downloadKbps = v;
    if (j['adapter'] case String v when v.isNotEmpty) {
      s.adapter = v;
      s.adapterName = j['adapterName'] is String ? j['adapterName'] as String : v;
    }
    s.schedule = Schedule.fromJson(j['schedule']);
    if (j['sounds'] case bool v) s.sounds = v;
    if (j['hotkey'] case bool v) s.hotkey = v;
    if (j['checkUpdates'] case bool v) s.checkUpdates = v;
    s.hotkeyKey = Hotkey.fromJson(j['hotkeyKey']);
    if (j['accent'] case int v when v >= 0 && v < accentPresets.length) s.accent = v;
    if (j['language'] case String v when v == 'ru' || v == 'en') s.language = v;
    if (j['wasActive'] case bool v) s.wasActive = v;
    return s;
  }
}

/// JSON в %APPDATA%\Vigilia. Любая ошибка чтения — дефолты, ошибка записи — тихо пропускаем.
class SettingsStore {
  SettingsStore(this.file);

  factory SettingsStore.appData() =>
      SettingsStore(File('${Platform.environment['APPDATA'] ?? Directory.systemTemp.path}\\Vigilia\\settings.json'));

  final File file;

  Settings load() {
    try {
      return Settings.fromJson(jsonDecode(file.readAsStringSync()));
    } catch (_) {
      return Settings();
    }
  }

  void save(Settings s) {
    try {
      file.parent.createSync(recursive: true);
      final tmp = File('${file.path}.tmp')..writeAsStringSync(jsonEncode(s.toJson()), flush: true);
      tmp.renameSync(file.path); // атомарная замена: файл не бьётся при падении посреди записи
    } catch (_) {}
  }
}

/// Автозапуск через HKCU\...\Run (права администратора не нужны).
class Autostart {
  static const _key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _name = 'Vigilia';

  Future<bool> isEnabled() async {
    try {
      return (await Process.run('reg', ['query', _key, '/v', _name])).exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static String get _command => '"${Platform.resolvedExecutable}" --hidden';

  /// Если автозапуск включён, но exe переехал (переустановка, другая папка) — переписать путь.
  Future<void> refresh() async {
    try {
      final r = await Process.run('reg', ['query', _key, '/v', _name]);
      if (r.exitCode != 0) return;
      final current = parseRegValue(r.stdout as String);
      if (current != null && current != _command) await set(true);
    } catch (_) {}
  }

  /// Возвращает фактическое состояние после попытки.
  Future<bool> set(bool on) async {
    try {
      await Process.run(
        'reg',
        on ? ['add', _key, '/v', _name, '/t', 'REG_SZ', '/d', _command, '/f'] : ['delete', _key, '/v', _name, '/f'],
      );
    } catch (_) {}
    return isEnabled();
  }
}

/// Значение из вывода `reg query ... /v Vigilia`: всё после `REG_SZ`.
String? parseRegValue(String out) {
  for (final line in out.split('\n')) {
    final i = line.indexOf('REG_SZ');
    if (i >= 0) return line.substring(i + 'REG_SZ'.length).trim();
  }
  return null;
}
