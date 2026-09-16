import 'dart:convert';
import 'dart:io';

class Settings {
  bool keepDisplay = false;
  int timerMinutes = 0; // 0 = без ограничения
  bool sounds = true;
  bool wasActive = false;

  Map<String, Object> toJson() => {
    'keepDisplay': keepDisplay,
    'timerMinutes': timerMinutes,
    'sounds': sounds,
    'wasActive': wasActive,
  };

  static Settings fromJson(Object? j) {
    final s = Settings();
    if (j is! Map) return s;
    if (j['keepDisplay'] case bool v) s.keepDisplay = v;
    if (j['timerMinutes'] case int v when v >= 0) s.timerMinutes = v;
    if (j['sounds'] case bool v) s.sounds = v;
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

  /// Возвращает фактическое состояние после попытки.
  Future<bool> set(bool on) async {
    try {
      await Process.run(
        'reg',
        on
            ? ['add', _key, '/v', _name, '/t', 'REG_SZ', '/d', '"${Platform.resolvedExecutable}" --hidden', '/f']
            : ['delete', _key, '/v', _name, '/f'],
      );
    } catch (_) {}
    return isEnabled();
  }
}
