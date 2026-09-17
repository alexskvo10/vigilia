import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vigilia/controller.dart';
import 'package:vigilia/probes.dart';
import 'package:vigilia/schedule.dart';
import 'package:vigilia/settings.dart';
import 'package:vigilia/shell.dart';
import 'package:vigilia/strings.dart';
import 'package:vigilia/win32.dart';

import 'controller_test.dart' show FakeAutostart, FakePower, FakeSounds;

void main() {
  group('расписание', () {
    const weekdays = Schedule(enabled: true); // пн–пт 9:00–18:00
    final wed = DateTime(2026, 9, 16);

    test('будни: внутри окна — конец окна, снаружи — null', () {
      expect(weekdays.windowEnd(wed.add(const Duration(hours: 9))), DateTime(2026, 9, 16, 18));
      expect(weekdays.windowEnd(wed.add(const Duration(hours: 17, minutes: 59))), DateTime(2026, 9, 16, 18));
      expect(weekdays.windowEnd(wed.add(const Duration(hours: 18))), isNull);
      expect(weekdays.windowEnd(wed.add(const Duration(hours: 8, minutes: 59))), isNull);
      expect(weekdays.windowEnd(DateTime(2026, 9, 19, 12)), isNull, reason: 'суббота');
      expect(weekdays.copyWith(enabled: false).windowEnd(wed.add(const Duration(hours: 12))), isNull);
      expect(weekdays.copyWith(days: 0).windowEnd(wed.add(const Duration(hours: 12))), isNull);
    });

    test('через полночь: окно принадлежит дню начала', () {
      final night = weekdays.copyWith(start: 22 * 60, end: 6 * 60, days: 1 << 4); // пятница
      expect(night.overnight, true);
      expect(night.windowEnd(DateTime(2026, 9, 18, 23)), DateTime(2026, 9, 19, 6));
      expect(night.windowEnd(DateTime(2026, 9, 19, 5, 59)), DateTime(2026, 9, 19, 6), reason: 'суббота утром');
      expect(night.windowEnd(DateTime(2026, 9, 17, 23)), isNull, reason: 'четверг не отмечен');
      expect(night.windowEnd(DateTime(2026, 9, 20, 2)), isNull, reason: 'ночь с субботы не отмечена');
    });

    test('начало = конец — окно на сутки', () {
      final day = weekdays.copyWith(start: 0, end: 0, days: 1 << 2); // среда
      expect(day.windowEnd(wed.add(const Duration(hours: 23))), DateTime(2026, 9, 17));
    });

    test('следующее окно и подпись «когда»', () {
      final fri = DateTime(2026, 9, 18, 10); // пятница, окно уже идёт
      expect(weekdays.nextStart(fri), DateTime(2026, 9, 21, 9), reason: 'после пятницы — понедельник');
      expect(weekdays.nextStart(DateTime(2026, 9, 16, 8)), DateTime(2026, 9, 16, 9));
      expect(weekdays.copyWith(enabled: false).nextStart(fri), isNull);
      expect(weekdays.copyWith(days: 0).nextStart(fri), isNull);
      final onlyWed = weekdays.copyWith(days: 1 << 2);
      expect(onlyWed.nextStart(DateTime(2026, 9, 16, 10)), DateTime(2026, 9, 23, 9), reason: 'через неделю');

      final now = DateTime(2026, 9, 16, 12);
      expect(whenText(DateTime(2026, 9, 16, 18), now, S.ru), 'сегодня в 18:00');
      expect(whenText(DateTime(2026, 9, 17, 9), now, S.ru), 'завтра в 09:00');
      expect(whenText(DateTime(2026, 9, 21, 9), now, S.ru), 'в понедельник в 09:00');
      expect(whenText(DateTime(2026, 9, 21, 9), now, S.en), 'on Monday at 09:00');
      // переход на зимнее время (сутки 25 часов) не ломает «завтра»
      expect(whenText(DateTime(2026, 10, 26, 9), DateTime(2026, 10, 25, 1), S.ru), 'завтра в 09:00');
    });

    test('JSON туда и обратно', () {
      const s = Schedule(enabled: true, days: 0x41, start: 30, end: 1410);
      final back = Schedule.fromJson(s.toJson());
      expect((back.enabled, back.days, back.start, back.end), (true, 0x41, 30, 1410));
    });
  });

  group('датчики', () {
    test('скорость: сумма по адаптерам, новый адаптер и сброс счётчика не дают скачков', () {
      const dt = Duration(seconds: 2);
      expect(bytesPerSecond({'a': 1000, 'b': 0}, {'a': 3000, 'b': 2000}, dt), 2000);
      expect(bytesPerSecond({'a': 1000}, {'a': 3000, 'new': 1 << 40}, dt), 1000);
      expect(bytesPerSecond({'a': 5000}, {'a': 10}, dt), 0);
      expect(bytesPerSecond({'a': 0}, {'a': 10}, Duration.zero), 0);
    });

    test('сетевые адаптеры видны на этой машине', () {
      final all = networkInterfaces();
      expect(all, isNotEmpty);
      expect(all.map((i) => i.guid).toSet(), hasLength(all.length), reason: 'GUID уникальны, фильтры отброшены');
      final total = receivedCounters(null);
      expect(total.keys, everyElement(isIn(all.where((i) => i.hardware).map((i) => i.guid))));
      final one = all.first;
      expect(receivedCounters(one.guid), {one.guid: isNonNegative});
      expect(pickableAdapters().every((a) => all.any((i) => i.guid == a.guid && i.up)), true);
    });

    test('процессы видны на этой машине', () {
      // на CI может не быть explorer.exe, а сам тестовый процесс есть всегда
      final self = Platform.resolvedExecutable.split(r'\').last.toLowerCase();
      final path = Platform.resolvedExecutable;
      expect(runningProcessNames(), contains(self));
      expect(processImagePath(pid), path.toLowerCase());
      final mine = WatchedProcess(self.toUpperCase(), path);
      final nameOnly = WatchedProcess(self, null);
      final elsewhere = WatchedProcess(self, r'C:\nowhere\' + self);
      final missing = WatchedProcess('definitely-not-running-42.exe', null);
      expect(runningWatched([mine, nameOnly, elsewhere, missing]), [mine, nameOnly]);
      final pickable = pickableProcesses();
      expect(pickable, contains(mine));
      expect(pickable.map((p) => p.name), isNot(contains('svchost.exe')));
    });

    test('настройки 1.1 (одно имя процесса) переносятся в список', () {
      final s = Settings.fromJson({'processName': 'Game.exe'});
      expect(s.processes, [WatchedProcess('game.exe', null)]);
      final back = Settings.fromJson(s.toJson());
      expect(back.processes, s.processes);
      final json = {
        'processes': [
          {'name': ''},
          5,
          {'name': 'a.exe', 'path': r'C:\A\a.exe'},
        ],
      };
      expect(Settings.fromJson(json).processes, [WatchedProcess('a.exe', r'c:\a\a.exe')]);
      expect(WatchedProcess('a.exe', r'C:\Tools\a.exe').folder, 'tools');
    });

    test('reg query → значение', () {
      const out = '\r\nHKEY_CURRENT_USER\\...\\Run\r\n    Vigilia    REG_SZ    "C:\\A B\\vigilia.exe" --hidden\r\n\r\n';
      expect(parseRegValue(out), r'"C:\A B\vigilia.exe" --hidden');
      expect(parseRegValue('nothing'), isNull);
    });
  });

  test('тексты: RU и EN полные и одинаковые по составу', () {
    for (final s in [S.ru, S.en]) {
      expect(s.all.where((x) => x.trim().isEmpty), isEmpty, reason: s.code);
      expect(s.days, hasLength(7));
    }
    expect(S.ru.all.length, S.en.all.length);
    expect(S.of('ru'), S.ru);
    expect(S.of('en'), S.en);
  });

  test('подсказка трея', () {
    final dir = Directory.systemTemp.createTempSync('vigilia_tip');
    addTearDown(() => dir.deleteSync(recursive: true));
    final c = VigilController(
      power: FakePower(),
      sounds: FakeSounds(),
      store: SettingsStore(File('${dir.path}/s.json')),
      autostartService: FakeAutostart(),
      now: () => DateTime(2026, 9, 16, 12),
    )..load();
    expect(Shell.tooltip(c, S.ru), 'Vigilia — обычный сон');
    c
      ..setUntil(Until.timer)
      ..setKeepDisplay(true)
      ..toggle();
    expect(Shell.tooltip(c, S.ru), 'Vigilia — не даю уснуть до 13:00 · экран включён');
    expect(Shell.tooltip(c, S.en), 'Vigilia — keeping awake until 13:00 · display on');
    c.dispose();
  });
}
