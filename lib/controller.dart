import 'dart:async';

import 'package:flutter/foundation.dart';

import 'hotkey.dart';
import 'probes.dart' as probes;
import 'schedule.dart';
import 'settings.dart';
import 'sounds.dart';
import 'strings.dart';
import 'theme.dart';
import 'updater.dart';
import 'win32.dart';

export 'hotkey.dart' show Hotkey;
export 'settings.dart' show Until, WatchedProcess, downloadPresets, maxWatched, timerPresets;

/// Почему режим выключился сам (для уведомления).
enum Finish { timer, process, download, schedule }

/// Почему не удалось включиться (подсказка в статусе).
enum Notice { none, pickProcess, notRunning }

/// Подпись списка программ: «obs64.exe» или «obs64.exe +2».
String processesLabel(List<WatchedProcess> list) => switch (list.length) {
  0 => '',
  1 => list.first.name,
  _ => '${list.first.name} +${list.length - 1}',
};

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
    List<WatchedProcess> Function(List<WatchedProcess>)? runningWatched,
    Map<String, int> Function(String? adapter)? receivedCounters,
    this.registerHotkey,
    this.releaseMode = kReleaseMode,
    Updater? updater,
  }) : updater = updater ?? Updater(current: appVersion),
       _now = now ?? DateTime.now,
       _runningWatched = runningWatched ?? probes.runningWatched,
       _receivedCounters = receivedCounters ?? probes.receivedCounters;

  final PowerRequest power;
  final Sounds sounds;
  final SettingsStore store;
  final Autostart autostartService;
  final DateTime Function() _now;
  final List<WatchedProcess> Function(List<WatchedProcess>) _runningWatched;
  final Map<String, int> Function(String?) _receivedCounters;

  /// Регистрация глобальной клавиши; возвращает, удалось ли. null — без клавиши (тесты).
  Future<bool> Function(bool on, Hotkey key)? registerHotkey;
  final bool releaseMode;
  final Updater updater;

  /// Сообщение о самостоятельном выключении (Shell показывает уведомление).
  void Function(Finish reason)? onFinished;

  final clock = ValueNotifier<int>(0);

  Settings _s = Settings();
  bool _manual = false, _scheduled = false, _error = false, _autostart = false, _hotkeyActive = false;
  bool _disposed = false, _recording = false;
  Notice _notice = Notice.none;
  DateTime? _windowEnd, _skipUntil, _endsAt, _lastAt, _quietSince;
  Duration _total = Duration.zero;
  Map<String, int>? _lastBytes;
  double? _speed;
  Timer? _ticker, _updateTimer;

  bool get active => _manual || _scheduled;
  bool get manual => _manual;
  bool get scheduled => _scheduled && !_manual;
  DateTime? get windowEnd => _windowEnd;
  DateTime get now => _now();

  /// Начало следующего окна расписания (подсказка, пока режим выключен).
  DateTime? get nextWindow => _s.schedule.nextStart(_now());
  bool get error => _error;
  Notice get notice => _notice;
  bool get keepDisplay => _s.keepDisplay;
  Until get until => _s.until;
  int get timerMinutes => _s.timerMinutes;
  List<WatchedProcess> get processes => List.unmodifiable(_s.processes);
  Schedule get schedule => _s.schedule;
  bool get soundsOn => _s.sounds;
  bool get autostart => _autostart;
  bool get hotkey => _s.hotkey;
  bool get checkUpdates => _s.checkUpdates;
  Hotkey get hotkeyKey => _s.hotkeyKey;

  /// Сочетание зарегистрировано в Windows (без регистратора — как в настройках).
  /// Во время записи нового сочетания показывает прежнее состояние.
  bool get hotkeyActive => registerHotkey == null ? _s.hotkey : _hotkeyActive;
  bool get hotkeyBusy => _s.hotkey && registerHotkey != null && !_hotkeyActive && !_recording;
  int get accent => _s.accent;
  String? get language => _s.language;
  int get downloadKbps => _s.downloadKbps;
  int get downloadThreshold => _s.downloadKbps * 1024; // байт/с
  String? get adapter => _s.adapter;
  String? get adapterName => _s.adapterName;
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
    if (_disposed) return;
    _autostart = auto;
    await _registerHotkey();
    _scheduleUpdateChecks();
  }

  /// Автопроверка обновлений: вскоре после старта и дальше раз в 12 часов.
  /// Только у настоящей сборки — debug и тесты в сеть не ходят.
  void _scheduleUpdateChecks() {
    _updateTimer?.cancel();
    _updateTimer = null;
    if (!releaseMode || !_s.checkUpdates || _disposed) return;
    _updateTimer = Timer(const Duration(seconds: 10), () {
      unawaited(updater.check());
      _updateTimer = Timer.periodic(const Duration(hours: 12), (_) => unawaited(updater.check()));
    });
  }

  /// Проверка при открытии раздела «Система», если давно не проверяли.
  void checkUpdatesSoon() {
    if (releaseMode && _s.checkUpdates) unawaited(updater.check(ifOlderThan: const Duration(minutes: 10)));
  }

  void setCheckUpdates(bool v) {
    _s.checkUpdates = v;
    _changed();
    _scheduleUpdateChecks();
    if (v) unawaited(updater.check());
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
    if (_s.processes.isEmpty) return Notice.pickProcess;
    return _runningWatched(_s.processes).isEmpty ? Notice.notRunning : Notice.none;
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

  void _finish(Finish reason) {
    _manual = false;
    _stopCondition();
    _apply();
    _persistActive();
    sounds.play(active ? Sfx.tick : Sfx.done);
    _syncTicker();
    notifyListeners();
    // если окно расписания продолжается, компьютер всё ещё бодрствует — уведомлять не о чем
    if (!active) onFinished?.call(reason);
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
        // все отслеживаемые программы завершились
        if (clock.value % 5 == 0 && _runningWatched(_s.processes).isEmpty) _finish(Finish.process);
      case Until.download:
        if (clock.value % 2 == 0) sampleDownload();
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
      if (!active) onFinished?.call(Finish.schedule);
    }
    notifyListeners();
    return true;
  }

  @visibleForTesting
  void sampleDownload() {
    if (_disposed || !_manual || _s.until != Until.download) return;
    final bytes = _receivedCounters(_s.adapter);
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

  void setDownloadKbps(int kbps) {
    if (kbps == _s.downloadKbps) return;
    _s.downloadKbps = kbps;
    if (_manual && _s.until == Until.download) _quietSince = _now(); // новый порог — отсчёт тишины заново
    _changed();
  }

  /// Адаптер для режима «загрузка»; null — все физические.
  void setAdapter(String? guid, String? name) {
    if (guid == _s.adapter) return;
    _s.adapter = guid;
    _s.adapterName = guid == null ? null : name;
    _s.until == Until.download ? _conditionChanged() : _changed();
  }

  /// Добавить программу в список отслеживаемых или убрать из него.
  void toggleProcess(WatchedProcess p) {
    final list = _s.processes;
    if (!list.remove(p)) {
      if (list.length >= maxWatched) return;
      list.add(p);
    }
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
    await _registerHotkey();
  }

  /// Новое сочетание; заодно включает клавишу.
  Future<void> setHotkeyKey(Hotkey key) async {
    _s
      ..hotkeyKey = key
      ..hotkey = true;
    _recording = false;
    _changed();
    await _registerHotkey();
  }

  /// Пока пользователь нажимает новое сочетание, старое снято: иначе Windows перехватит его до окна.
  Future<void> recordHotkey(bool on) async {
    if (on == _recording) return;
    _recording = on;
    notifyListeners();
    await _registerHotkey();
  }

  /// Приводит регистрацию в Windows к настройкам.
  Future<void> _registerHotkey() async {
    final on = _s.hotkey && !_recording;
    final ok = registerHotkey == null ? false : await registerHotkey!(on, _s.hotkeyKey);
    if (_disposed) return;
    if (!_recording) _hotkeyActive = on && ok; // снятие на время записи — не «выключено»
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _updateTimer?.cancel();
    updater.dispose();
    power.dispose();
    clock.dispose();
    super.dispose();
  }
}
