import 'dart:async';

import 'package:flutter/foundation.dart';

import 'probes.dart' as probes;
import 'schedule.dart';
import 'settings.dart';
import 'sounds.dart';
import 'strings.dart';
import 'theme.dart';
import 'win32.dart';

export 'settings.dart' show Until, timerPresets;

/// Почему режим выключился сам (для уведомления).
enum Finish { timer, process, download, schedule }

/// Почему не удалось включиться (подсказка в статусе).
enum Notice { none, pickProcess, notRunning }

const downloadThreshold = 100 * 1024; // байт/с
const downloadQuiet = Duration(minutes: 2);

/// Единственный источник правды о состоянии приложения.
///
/// Компьютер бодрствует, если включён ручной режим ИЛИ сейчас идёт окно расписания.
/// Ручной режим выключается сам по условию «до каких пор» (таймер, процесс, загрузка).
/// Раз в секунду тикает [clock] — его слушают только статус и кольцо, без `notifyListeners`.
class VigilController extends ChangeNotifier {
  VigilController({
    required this.power,
    required this.sounds,
    required this.store,
    required this.autostartService,
    DateTime Function()? now,
    bool Function(String name)? processRunning,
    Future<int?> Function()? receivedBytes,
    this.registerHotkey,
    this.releaseMode = kReleaseMode,
  }) : _now = now ?? DateTime.now,
       _processRunning = processRunning ?? probes.isProcessRunning,
       _receivedBytes = receivedBytes ?? probes.receivedBytes;

  final PowerRequest power;
  final Sounds sounds;
  final SettingsStore store;
  final Autostart autostartService;
  final DateTime Function() _now;
  final bool Function(String) _processRunning;
  final Future<int?> Function() _receivedBytes;

  /// Регистрация глобальной клавиши; возвращает, удалось ли. null — без клавиши (тесты).
  Future<bool> Function(bool on)? registerHotkey;
  final bool releaseMode;

  /// Сообщение о самостоятельном выключении (Shell показывает уведомление).
  void Function(Finish reason, String? detail)? onFinished;

  final clock = ValueNotifier<int>(0);

  Settings _s = Settings();
  bool _manual = false, _scheduled = false, _error = false, _autostart = false, _hotkeyActive = false;
  bool _disposed = false, _probing = false;
  Notice _notice = Notice.none;
  DateTime? _windowEnd, _skipUntil, _endsAt, _lastAt, _quietSince;
  Duration _total = Duration.zero;
  int? _lastBytes;
  double? _speed;
  Timer? _ticker;

  bool get active => _manual || _scheduled;
  bool get manual => _manual;
  bool get scheduled => _scheduled && !_manual;
  DateTime? get windowEnd => _windowEnd;
  bool get error => _error;
  Notice get notice => _notice;
  bool get keepDisplay => _s.keepDisplay;
  Until get until => _s.until;
  int get timerMinutes => _s.timerMinutes;
  String? get processName => _s.processName;
  Schedule get schedule => _s.schedule;
  bool get soundsOn => _s.sounds;
  bool get autostart => _autostart;
  bool get hotkey => _s.hotkey;
  bool get hotkeyBusy => _s.hotkey && registerHotkey != null && !_hotkeyActive;
  int get accent => _s.accent;
  String? get language => _s.language;
  DateTime? get endsAt => _manual && _s.until == Until.timer ? _endsAt : null;

  /// Скорость загрузки, байт/с (null — ещё нет двух отсчётов).
  double? get speed => _manual && _s.until == Until.download ? _speed : null;

  /// Сколько осталось до выключения по тишине загрузки.
  Duration? get quietLeft {
    final q = _quietSince;
    if (!_manual || _s.until != Until.download || q == null) return null;
    final left = downloadQuiet - _now().difference(q);
    return left.isNegative ? Duration.zero : left;
  }

  Duration? get remaining {
    final e = endsAt;
    if (e == null) return null;
    final r = e.difference(_now());
    return r.isNegative ? Duration.zero : r;
  }

  /// Доля оставшегося времени 1 → 0; null без таймера.
  double? get progress {
    final r = remaining;
    if (r == null || _total == Duration.zero) return null;
    return r.inMilliseconds / _total.inMilliseconds;
  }

  void load() {
    _s = store.load();
    C.use(accentPresets[_s.accent]);
    S.current = S.of(_s.language);
    sounds.enabled = _s.sounds;
    _updateSchedule(natural: false);
    if (_s.wasActive && _s.until == Until.always) {
      _manual = true;
    }
    _apply();
    _syncTicker();
    unawaited(_loadAsync());
  }

  Future<void> _loadAsync() async {
    // путь автозапуска обновляем только у настоящей сборки, не у debug/тестов
    if (releaseMode) await autostartService.refresh();
    final auto = await autostartService.isEnabled();
    final hk = _s.hotkey && registerHotkey != null ? await registerHotkey!(true) : false;
    if (_disposed) return;
    _autostart = auto;
    _hotkeyActive = hk;
    notifyListeners();
  }

  // ---------- вкл/выкл ----------

  void toggle() {
    if (active) {
      if (_scheduled) _skipUntil = _windowEnd; // выключение вручную пропускает текущее окно
      _scheduled = false;
      _setManual(false);
    } else {
      _setManual(true);
    }
  }

  void setActive(bool on) {
    if (on != active) toggle();
  }

  void _setManual(bool on, {bool sound = true}) {
    _notice = Notice.none;
    if (on) {
      final problem = _conditionProblem();
      if (problem != Notice.none) {
        _notice = problem;
        sounds.play(Sfx.tick);
        notifyListeners();
        return;
      }
      _manual = true;
      _startCondition();
    } else {
      _manual = false;
      _stopCondition();
    }
    if (_apply() && sound) sounds.play(active ? Sfx.on : Sfx.off);
    _persistActive();
    _syncTicker();
    notifyListeners();
  }

  Notice _conditionProblem() {
    if (_s.until != Until.process) return Notice.none;
    final name = _s.processName;
    if (name == null) return Notice.pickProcess;
    return _processRunning(name) ? Notice.none : Notice.notRunning;
  }

  void _startCondition() {
    _stopCondition();
    final now = _now();
    if (_s.until == Until.timer) {
      _total = Duration(minutes: _s.timerMinutes);
      _endsAt = now.add(_total);
    }
    if (_s.until == Until.download) {
      _quietSince = now; // загрузка должна начаться в течение downloadQuiet
    }
  }

  void _stopCondition() {
    _endsAt = null;
    _total = Duration.zero;
    _lastBytes = null;
    _lastAt = null;
    _speed = null;
    _quietSince = null;
  }

  /// Приводит запрос питания к состоянию. При отказе WinAPI всё выключается.
  bool _apply() {
    final on = active;
    if (power.apply(system: on, display: on && _s.keepDisplay)) {
      if (on) _error = false; // ошибка остаётся на экране, пока не попробуют снова
      return true;
    }
    power.apply(system: false, display: false);
    _error = true;
    if (_scheduled) _skipUntil = _windowEnd;
    _manual = _scheduled = false;
    _stopCondition();
    return false;
  }

  void _persistActive() {
    _s.wasActive = _manual;
    store.save(_s);
  }

  void _finish(Finish reason, [String? detail]) {
    _manual = false;
    _stopCondition();
    _apply();
    _persistActive();
    sounds.play(active ? Sfx.tick : Sfx.done);
    _syncTicker();
    notifyListeners();
    // если окно расписания продолжается, компьютер всё ещё бодрствует — уведомлять не о чем
    if (!active) onFinished?.call(reason, detail);
  }

  // ---------- тик ----------

  void _syncTicker() {
    final needed = (_manual && _s.until != Until.always) || _s.schedule.enabled;
    if (needed && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
    } else if (!needed) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @visibleForTesting
  void tick() {
    if (_disposed) return;
    clock.value++;
    if (_updateSchedule(natural: true)) return;
    if (!_manual) return;
    switch (_s.until) {
      case Until.always:
        break;
      case Until.timer:
        if (remaining == Duration.zero) _finish(Finish.timer);
      case Until.process:
        final name = _s.processName;
        if (clock.value % 5 == 0 && name != null && !_processRunning(name)) _finish(Finish.process, name);
      case Until.download:
        if (clock.value % 3 == 0) unawaited(sampleDownload());
    }
  }

  /// Пересчитывает окно расписания. true — состояние изменилось (уже применено).
  bool _updateSchedule({required bool natural}) {
    final now = _now();
    final skip = _skipUntil;
    if (skip != null && !now.isBefore(skip)) _skipUntil = null;
    final end = _s.schedule.windowEnd(now);
    final inWindow = end != null && !(end == _skipUntil);
    _windowEnd = end;
    if (inWindow == _scheduled) return false;
    final wasActive = active;
    _scheduled = inWindow;
    if (!natural) return true; // при загрузке/смене настроек — без звуков и уведомлений
    _apply();
    if (active != wasActive) {
      sounds.play(active ? Sfx.on : Sfx.done);
      if (!active) onFinished?.call(Finish.schedule, null);
    }
    notifyListeners();
    return true;
  }

  @visibleForTesting
  Future<void> sampleDownload() async {
    if (_probing) return;
    _probing = true;
    try {
      final bytes = await _receivedBytes();
      if (_disposed || !_manual || _s.until != Until.download || bytes == null) return;
      final now = _now();
      final last = _lastBytes, lastAt = _lastAt;
      _lastBytes = bytes;
      _lastAt = now;
      if (last == null || lastAt == null) return;
      _speed = probes.bytesPerSecond(last, bytes, now.difference(lastAt));
      if (_speed! >= downloadThreshold) {
        _quietSince = null;
      } else {
        _quietSince ??= now;
        if (now.difference(_quietSince!) >= downloadQuiet) _finish(Finish.download);
      }
    } finally {
      _probing = false;
    }
  }

  // ---------- настройки ----------

  void _changed() {
    store.save(_s);
    sounds.play(Sfx.tick);
    notifyListeners();
  }

  void setKeepDisplay(bool v) {
    if (v == _s.keepDisplay) return;
    _s.keepDisplay = v;
    if (active) _apply();
    _changed();
  }

  void setUntil(Until u) {
    if (u == _s.until) return;
    _s.until = u;
    _conditionChanged();
  }

  void setTimer(int minutes) {
    if (minutes == _s.timerMinutes) return;
    _s.timerMinutes = minutes;
    _s.until == Until.timer ? _conditionChanged() : _changed();
  }

  void setProcess(String name) {
    _s.processName = name;
    if (_notice == Notice.pickProcess) _notice = Notice.none;
    _s.until == Until.process ? _conditionChanged() : _changed();
  }

  /// Условие поменялось во время работы: перезапустить отсчёт или выключиться, если условие невыполнимо.
  void _conditionChanged() {
    if (_manual) {
      final problem = _conditionProblem();
      if (problem != Notice.none) {
        _manual = false;
        _stopCondition();
        _apply();
        _persistActive();
        _notice = problem;
      } else {
        _startCondition();
      }
    }
    _syncTicker();
    _changed();
  }

  void setSchedule(Schedule s) {
    _s.schedule = s;
    _skipUntil = null;
    if (_updateSchedule(natural: false)) _apply();
    _syncTicker();
    _changed();
  }

  void setSounds(bool v) {
    _s.sounds = sounds.enabled = v;
    _changed();
  }

  void setAccent(int i) {
    if (i == _s.accent) return;
    _s.accent = i;
    C.use(accentPresets[i]);
    _changed();
  }

  void setLanguage(String code) {
    if (code == S.current.code && _s.language != null) return;
    _s.language = code;
    S.current = S.of(code);
    _changed();
  }

  Future<void> setAutostart(bool v) async {
    sounds.play(Sfx.tick);
    _autostart = v; // оптимистично, чтобы toggle анимировался сразу
    notifyListeners();
    final actual = await autostartService.set(v);
    if (_disposed) return;
    _autostart = actual;
    notifyListeners();
  }

  Future<void> setHotkey(bool v) async {
    _s.hotkey = v;
    _changed();
    final ok = registerHotkey == null ? false : await registerHotkey!(v);
    if (_disposed) return;
    _hotkeyActive = ok;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    power.dispose();
    clock.dispose();
    super.dispose();
  }
}
