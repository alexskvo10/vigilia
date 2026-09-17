import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vigilia/controller.dart';
import 'package:vigilia/schedule.dart';
import 'package:vigilia/settings.dart';
import 'package:vigilia/sounds.dart';
import 'package:vigilia/strings.dart';
import 'package:vigilia/theme.dart';
import 'package:vigilia/ui/home.dart';
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
  void play(Sfx s, {bool loop = false}) {
    if (enabled) played.add(s);
  }

  @override
  void stop() {}
}

class FakeAutostart implements Autostart {
  bool on = false;
  int refreshed = 0;
  @override
  Future<bool> isEnabled() async => on;
  @override
  Future<bool> set(bool v) async => on = v;
  @override
  Future<void> refresh() async => refreshed++;
}

void main() {
  late Directory dir;
  late FakePower power;
  late FakeSounds sounds;
  late DateTime now;
  late Set<String> running;
  late int bytes;
  String? askedAdapter;
  final finished = <Finish>[];

  setUp(() {
    dir = Directory.systemTemp.createTempSync('vigilia_test');
    power = FakePower();
    sounds = FakeSounds();
    now = DateTime(2026, 9, 16, 12); // среда
    running = {};
    bytes = 0;
    askedAdapter = 'не спрашивали';
    finished.clear();
  });
  tearDown(() {
    dir.deleteSync(recursive: true);
    C.use(accentPresets.first);
    S.current = S.ru;
  });

  SettingsStore store() => SettingsStore(File('${dir.path}/s.json'));
  VigilController make({Future<bool> Function(bool, Hotkey)? hotkey, bool release = false, FakeAutostart? auto}) =>
      VigilController(
          power: power,
          sounds: sounds,
          store: store(),
          autostartService: auto ?? FakeAutostart(),
          now: () => now,
          // «запущена» — если совпал ключ (путь или имя)
          runningWatched: (list) => [
            for (final p in list)
              if (running.contains(p.key)) p,
          ],
          receivedCounters: (adapter) {
            askedAdapter = adapter;
            return {adapter ?? 'wifi': bytes};
          },
          registerHotkey: hotkey,
          releaseMode: release,
        )
        ..onFinished = finished.add
        ..load();

  void tickFor(VigilController c, Duration d) {
    for (var i = 0; i < d.inSeconds; i++) {
      now = now.add(const Duration(seconds: 1));
      c.tick();
    }
  }

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

  test('таймер истекает, выключает и сообщает причину', () {
    final c = make()
      ..setUntil(Until.timer)
      ..setTimer(30)
      ..setActive(true);
    expect(c.remaining, const Duration(minutes: 30));
    tickFor(c, const Duration(minutes: 10));
    expect(c.active, true);
    expect(c.progress, closeTo(2 / 3, 1e-9));
    tickFor(c, const Duration(minutes: 20));
    expect((c.active, power.system, c.endsAt), (false, false, null));
    expect(sounds.played.last, Sfx.done);
    expect(finished, [Finish.timer]);
    c.dispose();
  });

  test('смена таймера перезапускает отсчёт; «всегда» не истекает', () {
    final c = make()
      ..setUntil(Until.timer)
      ..setActive(true);
    now = now.add(const Duration(minutes: 25));
    c.setTimer(120);
    expect(c.remaining, const Duration(minutes: 120));
    c.setUntil(Until.always);
    expect((c.endsAt, c.progress), (null, null));
    tickFor(c, const Duration(hours: 5));
    expect(c.active, true);
    expect(finished, isEmpty);
    c.dispose();
  });

  test('тик двигает clock, но не пересобирает экран', () {
    final c = make()
      ..setUntil(Until.timer)
      ..setActive(true);
    var notified = 0;
    c.addListener(() => notified++);
    tickFor(c, const Duration(seconds: 5));
    expect((c.clock.value, notified), (5, 0));
    c.dispose();
  });

  test('процесс: не выбран / не запущен — не включаемся; все завершились — выключаемся', () {
    final c = make()..setUntil(Until.process);
    c.toggle();
    expect((c.active, c.notice), (false, Notice.pickProcess));

    final game = WatchedProcess('Game.exe', r'C:\Games\Game.exe');
    final render = WatchedProcess('render.exe', null);
    c.toggleProcess(game);
    expect(c.notice, Notice.none);
    expect(c.processes, [game]);
    c.toggle();
    expect((c.active, c.notice), (false, Notice.notRunning));

    // запущен exe с тем же именем, но из другой папки — не считается
    running.add(r'c:\other\game.exe');
    c.toggle();
    expect(c.active, false);

    c.toggleProcess(render);
    running.addAll([r'c:\games\game.exe', 'render.exe']);
    c.toggle();
    expect((c.active, c.notice, power.system), (true, Notice.none, true));

    // пока работает хоть одна — не выключаемся
    running.remove('render.exe');
    tickFor(c, const Duration(seconds: 10));
    expect(c.active, true);

    running.clear();
    tickFor(c, const Duration(seconds: 5));
    expect((c.active, power.system), (false, false));
    expect(finished, [Finish.process]);

    // повторный выбор убирает из списка; настройки переживают перезапуск
    c.toggleProcess(render);
    expect(c.processes, [game]);
    c.dispose();
    expect(make().processes, [game]);
  });

  test('выключено и расписание включено — подзаголовок с ближайшим окном', () {
    final c = make();
    expect(Status.subtitle(c, S.ru).$2, S.ru.subOff);
    c.setSchedule(const Schedule(enabled: true, start: 20 * 60, end: 22 * 60));
    expect(Status.subtitle(c, S.ru).$2, 'Расписание: сегодня в 20:00');
    now = DateTime(2026, 9, 16, 21);
    c.tick(); // окно началось — режим включён, подсказки больше нет
    expect(Status.subtitle(c, S.ru).$2, 'по расписанию до 22:00');
    c.toggle(); // пропуск текущего окна
    expect(Status.subtitle(c, S.ru).$2, 'Расписание: завтра в 20:00');
    c.dispose();
  });

  test('больше $maxWatched программ не добавляется', () {
    final c = make();
    for (var i = 0; i < maxWatched + 3; i++) {
      c.toggleProcess(WatchedProcess('p$i.exe', null));
    }
    expect(c.processes.length, maxWatched);
    c.dispose();
  });

  test('смена условия на невыполнимое во время работы выключает с подсказкой', () {
    final c = make()..setActive(true);
    c.setUntil(Until.process);
    expect((c.active, c.notice, power.system), (false, Notice.pickProcess, false));
    c.dispose();
  });

  test('загрузка: пока скорость ≥ порога — работаем; 2 минуты тишины — выключаемся', () async {
    final c = make()
      ..setUntil(Until.download)
      ..setActive(true);
    void sample(int addBytes, Duration dt) {
      now = now.add(dt);
      bytes += addBytes;
      c.sampleDownload();
    }

    sample(0, Duration.zero); // первый отсчёт — только база
    expect(c.speed, isNull);
    sample(3 * 1024 * 1024, const Duration(seconds: 3)); // 1 МБ/с
    expect(c.speed, closeTo(1024 * 1024, 1));
    expect(c.quietLeft, isNull);

    sample(1000, const Duration(seconds: 90)); // затихло
    expect(c.quietLeft, downloadQuiet);
    sample(1000, const Duration(seconds: 90));
    expect(c.quietLeft, const Duration(seconds: 30));
    sample(20 * 1024 * 1024, const Duration(seconds: 3)); // всплеск сбрасывает отсчёт
    expect((c.active, c.quietLeft), (true, null));

    sample(0, const Duration(seconds: 60));
    sample(0, const Duration(seconds: 60));
    expect(c.active, true);
    sample(0, const Duration(seconds: 61));
    expect(c.active, false);
    expect(finished, [Finish.download]);
    c.dispose();
  });

  test('загрузка: порог и адаптер из настроек', () {
    final c = make()
      ..setUntil(Until.download)
      ..setDownloadKbps(500)
      ..setAdapter('guid-1', 'Wi-Fi')
      ..setActive(true);
    c.sampleDownload();
    expect(askedAdapter, 'guid-1');
    now = now.add(const Duration(seconds: 2));
    bytes += 600 * 1024; // 300 КБ/с — ниже порога 500
    c.sampleDownload();
    expect(c.quietLeft, isNotNull);
    c.setDownloadKbps(100); // порог ниже скорости, отсчёт тишины начинается заново
    now = now.add(const Duration(seconds: 2));
    bytes += 600 * 1024;
    c.sampleDownload();
    expect((c.downloadKbps, c.quietLeft), (100, null));
    c.dispose();
    final again = make();
    expect((again.downloadKbps, again.adapter, again.adapterName), (100, 'guid-1', 'Wi-Fi'));
    again.setAdapter(null, 'x');
    expect((again.adapter, again.adapterName), (null, null));
    again.dispose();
  });

  test('загрузка так и не началась — выключаемся через 2 минуты', () async {
    final c = make()
      ..setUntil(Until.download)
      ..setActive(true);
    c.sampleDownload();
    now = now.add(const Duration(minutes: 1));
    c.sampleDownload();
    expect(c.active, true);
    now = now.add(const Duration(minutes: 1, seconds: 1));
    c.sampleDownload();
    expect(c.active, false);
    c.dispose();
  });

  test('расписание: в окне — бодрствуем, по концу окна — выключаемся с уведомлением', () {
    now = DateTime(2026, 9, 16, 17, 59, 55); // среда
    store().save(Settings()..schedule = const Schedule(enabled: true, start: 9 * 60, end: 18 * 60));
    final c = make();
    expect((c.active, c.scheduled, c.manual, power.system), (true, true, false, true));
    expect(c.windowEnd, DateTime(2026, 9, 16, 18));
    expect(sounds.played, isEmpty, reason: 'при запуске без звука');
    tickFor(c, const Duration(seconds: 5));
    expect((c.active, power.system), (false, false));
    expect(finished, [Finish.schedule]);
    c.dispose();
  });

  test('расписание: ручное выключение пропускает текущее окно, следующее работает', () {
    now = DateTime(2026, 9, 16, 10);
    store().save(Settings()..schedule = const Schedule(enabled: true));
    final c = make();
    c.toggle();
    expect((c.active, power.system), (false, false));
    tickFor(c, const Duration(minutes: 1));
    expect(c.active, false, reason: 'окно пропущено');

    c.toggle(); // ручное включение внутри пропущенного окна работает
    expect((c.active, c.manual), (true, true));
    c.toggle();

    now = DateTime(2026, 9, 17, 8, 59, 59);
    c.tick();
    expect(c.active, false);
    now = DateTime(2026, 9, 17, 9);
    c.tick();
    expect((c.active, c.scheduled), (true, true));
    c.dispose();
  });

  test('ручной режим поверх расписания не выключается концом окна', () {
    now = DateTime(2026, 9, 16, 17, 59);
    store().save(Settings()..schedule = const Schedule(enabled: true));
    final c = make();
    c.setUntil(Until.timer);
    // уже активно по расписанию: включаем ручной режим через выключение+включение
    c.toggle();
    c.toggle();
    expect((c.manual, c.active), (true, true));
    tickFor(c, const Duration(minutes: 2));
    expect(c.active, true);
    expect(finished, isEmpty);
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

  test('настройки сохраняются; ручной режим восстанавливается только для «всегда»', () {
    make()
      ..setKeepDisplay(true)
      ..setSounds(false)
      ..setActive(true);
    var c = make();
    expect((c.keepDisplay, c.soundsOn, c.active, power.display), (true, false, true, true));

    c.setUntil(Until.timer);
    c.setActive(false);
    c.setActive(true);
    c = make();
    expect((c.until, c.timerMinutes, c.active), (Until.timer, 60, false));
  });

  test('цвет и язык применяются и сохраняются', () {
    make()
      ..setAccent(3)
      ..setLanguage('en');
    expect((C.accent, S.current.code), (accentPresets[3], 'en'));
    C.use(accentPresets.first);
    S.current = S.ru;
    final c = make();
    expect((c.accent, c.language, C.accent, S.current.code), (3, 'en', accentPresets[3], 'en'));
  });

  test('горячая клавиша: занята — подсказка; выключение снимает регистрацию', () async {
    final calls = <(bool, Hotkey)>[];
    var free = false;
    final c = make(
      hotkey: (on, key) async {
        calls.add((on, key));
        return on && free;
      },
    );
    await pumpEventQueue();
    expect((c.hotkey, c.hotkeyBusy, c.hotkeyKey.label), (true, true, 'Ctrl+Alt+V'));
    expect(calls, [(true, Hotkey.fallback)]);
    free = true;
    await c.setHotkey(true);
    expect(c.hotkeyBusy, false);
    await c.setHotkey(false);
    expect((c.hotkey, c.hotkeyBusy, calls.last.$1), (false, false, false));
    c.dispose();
  });

  test('новое сочетание: запись снимает старое, выбор регистрирует и включает', () async {
    final calls = <(bool, Hotkey)>[];
    final c = make(
      hotkey: (on, key) async {
        calls.add((on, key));
        return on;
      },
    );
    await c.setHotkey(false);
    await c.recordHotkey(true);
    expect((calls.last.$1, c.hotkeyBusy), (false, false));
    const ctrlShiftF9 = Hotkey(Hotkey.ctrl | Hotkey.shift, 0x78);
    await c.setHotkeyKey(ctrlShiftF9);
    expect(calls.last, (true, ctrlShiftF9));
    expect((c.hotkey, c.hotkeyBusy), (true, false));
    // отмена записи возвращает прежнее сочетание
    await c.recordHotkey(true);
    await c.recordHotkey(false);
    expect(calls.last, (true, ctrlShiftF9));
    c.dispose();
    expect(make().hotkeyKey, ctrlShiftF9);
  });

  test('путь автозапуска обновляется только в Release-сборке', () async {
    final debug = FakeAutostart(), release = FakeAutostart();
    final a = make(auto: debug), b = make(auto: release, release: true);
    await pumpEventQueue();
    expect((debug.refreshed, release.refreshed), (0, 1));
    a.dispose();
    b.dispose();
  });

  test('битый или чужой JSON → дефолты', () {
    File('${dir.path}/s.json').writeAsStringSync('{oops');
    expect(store().load().until, Until.always);
    File('${dir.path}/s.json').writeAsStringSync(
      '{"timerMinutes": 7, "sounds": "yes", "keepDisplay": true, "until": "forever", '
      '"accent": 99, "language": "de", "schedule": {"enabled": true, "start": 99999, "days": -1}}',
    );
    final s = store().load();
    expect(
      (s.timerMinutes, s.sounds, s.keepDisplay, s.until, s.accent, s.language),
      (60, true, true, Until.always, 0, null),
    );
    expect((s.schedule.enabled, s.schedule.start, s.schedule.days), (true, 9 * 60, 0x7F));
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
