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

    test('JSON туда и обратно', () {
      const s = Schedule(enabled: true, days: 0x41, start: 30, end: 1410);
      final back = Schedule.fromJson(s.toJson());
      expect((back.enabled, back.days, back.start, back.end), (true, 0x41, 30, 1410));
    });
  });

  group('датчики', () {
    test('netstat -e: английский и русский вывод', () {
      const en =
          'Interface Statistics\r\n\r\n    Received   Sent\r\n\r\nBytes   2668910177  4225960665\r\n'
          'Unicast packets   6204921   4196651\r\n';
      const ru = 'Статистика интерфейса\r\n\r\n   Получено   Отправлено\r\n\r\nБайт   123456   789\r\n';
      expect(parseNetstatReceived(en), 2668910177);
      expect(parseNetstatReceived(ru), 123456);
      expect(parseNetstatReceived('garbage'), isNull);
    });

    test('скорость: обычная, переполнение 32-битного счётчика, нулевой интервал', () {
      expect(bytesPerSecond(1000, 4000, const Duration(seconds: 3)), 1000);
      expect(bytesPerSecond((1 << 32) - 1000, 1000, const Duration(seconds: 2)), 1000);
      expect(bytesPerSecond(1000, 2000, Duration.zero), 0);
    });

    test('процессы видны на этой машине', () {
      // на CI может не быть explorer.exe, а сам тестовый процесс есть всегда
      final self = Platform.resolvedExecutable.split(r'\').last.toLowerCase();
      expect(runningProcessNames(), contains(self));
      expect(isProcessRunning(self.toUpperCase()), true);
      expect(isProcessRunning('definitely-not-running-42.exe'), false);
      expect(pickableProcesses(), isNot(contains('svchost.exe')));
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
