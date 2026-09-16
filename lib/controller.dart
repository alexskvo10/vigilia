import 'dart:async';

import 'package:flutter/foundation.dart';

import 'settings.dart';
import 'sounds.dart';
import 'win32.dart';

const timerPresets = [0, 30, 60, 120, 240];

/// Единственный источник правды о состоянии приложения.
class VigilController extends ChangeNotifier {
  VigilController({
    required this.power,
    required this.sounds,
    required this.store,
    required this.autostartService,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final PowerRequest power;
  final Sounds sounds;
  final SettingsStore store;
  final Autostart autostartService;
  final DateTime Function() _now;

  Settings _s = Settings();
  bool _active = false;
  bool _error = false;
  bool _autostart = false;
  DateTime? _endsAt;
  Duration _total = Duration.zero;
  Timer? _ticker;
  bool _disposed = false;

  bool get active => _active;
  bool get error => _error;
  bool get keepDisplay => _s.keepDisplay;
  int get timerMinutes => _s.timerMinutes;
  bool get soundsOn => _s.sounds;
  bool get autostart => _autostart;
  DateTime? get endsAt => _endsAt;

  Duration? get remaining {
    final e = _endsAt;
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

  /// Загрузка настроек; включённое состояние восстанавливается только без таймера.
  void load() {
    _s = store.load();
    sounds.enabled = _s.sounds;
    if (_s.wasActive && _s.timerMinutes == 0) _setActive(true, sound: false);
    unawaited(
      autostartService.isEnabled().then((v) {
        if (_disposed) return;
        _autostart = v;
        notifyListeners();
      }),
    );
  }

  void toggle() => _setActive(!_active);

  void setActive(bool on) {
    if (on != _active) _setActive(on);
  }

  void _setActive(bool on, {bool sound = true, Sfx? sfx}) {
    if (!power.apply(system: on, display: on && _s.keepDisplay)) {
      _error = true;
      // запрос мог примениться частично — откатываем всё
      power.apply(system: false, display: false);
      _active = false;
      _stopTimer();
      notifyListeners();
      return;
    }
    _error = false;
    _active = on;
    on ? _startTimer() : _stopTimer();
    _s.wasActive = on;
    store.save(_s);
    if (sound) sounds.play(sfx ?? (on ? Sfx.on : Sfx.off));
    notifyListeners();
  }

  void setKeepDisplay(bool v) {
    if (v == _s.keepDisplay) return;
    _s.keepDisplay = v;
    store.save(_s);
    sounds.play(Sfx.tick);
    if (_active && !power.apply(system: true, display: v)) _error = true;
    notifyListeners();
  }

  void setTimer(int minutes) {
    if (minutes == _s.timerMinutes) return;
    _s.timerMinutes = minutes;
    store.save(_s);
    sounds.play(Sfx.tick);
    if (_active) _startTimer(); // перезапуск отсчёта с текущего момента
    notifyListeners();
  }

  void setSounds(bool v) {
    _s.sounds = sounds.enabled = v;
    store.save(_s);
    sounds.play(Sfx.tick);
    notifyListeners();
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

  void _startTimer() {
    _stopTimer();
    if (_s.timerMinutes == 0) return;
    _total = Duration(minutes: _s.timerMinutes);
    _endsAt = _now().add(_total);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  void _stopTimer() {
    _ticker?.cancel();
    _ticker = null;
    _endsAt = null;
    _total = Duration.zero;
  }

  /// Раз в секунду: либо таймер истёк, либо просто обновить отсчёт.
  @visibleForTesting
  void tick() {
    if (!_active || _endsAt == null) return;
    if (remaining == Duration.zero) {
      _setActive(false, sfx: Sfx.done);
    } else {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTimer();
    power.dispose();
    super.dispose();
  }
}
