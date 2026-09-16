import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vigilia/controller.dart';
import 'package:vigilia/settings.dart';
import 'package:vigilia/sounds.dart';
import 'package:vigilia/win32.dart';

class FakePower implements PowerRequest {
  bool system = false, display = false, fail = false;
  @override
  bool apply({required bool system, required bool display}) {
    if (fail && system) return false;
    this.system = system;
    this.display = display;
    return true;
  }

  @override
  void dispose() => apply(system: false, display: false);
}

class FakeSounds implements Sounds {
  final played = <Sfx>[];
  @override
  bool enabled = true;
  @override
  void play(Sfx s) {
    if (enabled) played.add(s);
  }
}

class FakeAutostart implements Autostart {
  bool on = false;
  @override
  Future<bool> isEnabled() async => on;
  @override
  Future<bool> set(bool v) async => on = v;
}

void main() {
  late Directory dir;
  late FakePower power;
  late FakeSounds sounds;
  late DateTime now;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('vigilia_test');
    power = FakePower();
    sounds = FakeSounds();
    now = DateTime(2026, 9, 16, 12);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  SettingsStore store() => SettingsStore(File('${dir.path}/s.json'));
  VigilController make() =>
      VigilController(power: power, sounds: sounds, store: store(), autostartService: FakeAutostart(), now: () => now)
        ..load();

  test('вкл/выкл ставит и снимает запрос, играет звук', () {
    final c = make();
    c.toggle();
    expect((c.active, power.system, power.display), (true, true, false));
    c.toggle();
    expect((c.active, power.system), (false, false));
    expect(sounds.played, [Sfx.on, Sfx.off]);
    c.dispose();
  });

  test('режим экрана меняется на лету', () {
    final c = make()..setActive(true);
    c.setKeepDisplay(true);
    expect(power.display, true);
    c.setKeepDisplay(false);
    expect((power.system, power.display), (true, false));
    c.setActive(false);
    c.setKeepDisplay(true);
    expect(power.display, false, reason: 'в выключенном состоянии запрос не ставится');
    c.dispose();
  });

  test('таймер истекает и выключает', () {
    final c = make()..setTimer(30);
    c.setActive(true);
    expect(c.remaining, const Duration(minutes: 30));
    now = now.add(const Duration(minutes: 10));
    c.tick();
    expect(c.active, true);
    expect(c.progress, closeTo(2 / 3, 1e-9));
    now = now.add(const Duration(minutes: 20));
    c.tick();
    expect((c.active, power.system, c.endsAt), (false, false, null));
    expect(sounds.played.last, Sfx.done);
    c.dispose();
  });

  test('смена таймера во время работы перезапускает отсчёт; ∞ не истекает', () {
    final c = make()..setTimer(30);
    c.setActive(true);
    now = now.add(const Duration(minutes: 25));
    c.setTimer(60);
    expect(c.remaining, const Duration(minutes: 60));
    c.setTimer(0);
    expect((c.endsAt, c.progress), (null, null));
    now = now.add(const Duration(days: 3));
    c.tick();
    expect(c.active, true);
    c.dispose();
  });

  test('ошибка WinAPI: остаётся выключенным и показывает ошибку', () {
    power.fail = true;
    final c = make()..toggle();
    expect((c.active, c.error, power.system), (false, true, false));
    power.fail = false;
    c.toggle();
    expect((c.active, c.error), (true, false));
    c.dispose();
  });

  test('настройки сохраняются; состояние восстанавливается только без таймера', () {
    make()
      ..setKeepDisplay(true)
      ..setSounds(false)
      ..setActive(true);
    var c = make();
    expect((c.keepDisplay, c.soundsOn, c.active, power.display), (true, false, true, true));

    c.setTimer(60);
    c.setActive(false);
    c.setActive(true);
    c = make();
    expect((c.timerMinutes, c.active), (60, false));
  });

  test('битый или чужой JSON → дефолты', () {
    File('${dir.path}/s.json').writeAsStringSync('{oops');
    expect(store().load().timerMinutes, 0);
    File('${dir.path}/s.json').writeAsStringSync('{"timerMinutes": -5, "sounds": "yes", "keepDisplay": true}');
    final s = store().load();
    expect((s.timerMinutes, s.sounds, s.keepDisplay), (0, true, true));
    File('${dir.path}/s.json').writeAsStringSync('[1,2]');
    expect(store().load().wasActive, false);
  });

  test('звуки выключаются', () {
    final c = make()..setSounds(false);
    c.toggle();
    expect(sounds.played, isEmpty);
    c.dispose();
  });
}
