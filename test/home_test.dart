import 'dart:io';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigilia/controller.dart';
import 'package:vigilia/settings.dart';
import 'package:vigilia/strings.dart';
import 'package:vigilia/theme.dart';
import 'package:vigilia/ui/home.dart';
import 'package:vigilia/ui/settings_drawer.dart';

import 'controller_test.dart' show FakeAutostart, FakePower, FakeSounds;

/// Кадр, на котором анимация стартует, и прыжок по времени до её конца.
Future<void> settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(seconds: 2));
}

SettingsStore store(Directory dir) => SettingsStore(File('${dir.path}/s.json'));

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vigilia_ui'));
  tearDown(() {
    dir.deleteSync(recursive: true);
    C.use(accentPresets.first);
    S.current = S.ru;
  });

  var hidden = 0;
  late SemanticsHandle semantics;
  Future<(VigilController, FakePower)> pump(WidgetTester t) async {
    semantics = t.ensureSemantics(); // для поиска по подписям (bySemanticsLabel)
    final power = FakePower();
    store(dir).save(Settings()..language = 'ru');
    final c = VigilController(
      power: power,
      sounds: FakeSounds(),
      store: store(dir),
      autostartService: FakeAutostart(),
      processRunning: (_) => false,
      receivedBytes: () async => null,
    )..load();
    t.view.physicalSize = const Size(364, 691);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      WidgetsApp(
        color: C.accent,
        builder: (_, _) => VigiliaScreen(c: c, ui: UiState(), onHide: () => hidden++),
      ),
    );
    await settle(t);
    return (c, power);
  }

  Finder visible(String text) => find.text(text).hitTestable();

  testWidgets('настройки скрыты, открываются; разделы, клавиатура, Esc', (t) async {
    final (c, power) = await pump(t);
    expect(t.takeException(), isNull);
    expect(visible('Может гаснуть'), findsNothing, reason: 'настройки по умолчанию скрыты');

    // пробел по орбу (autofocus) включает режим
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await settle(t);
    expect((c.active, power.system), (true, true));

    await t.tap(find.byIcon(Icons.settings_rounded));
    await settle(t);
    expect(visible('Может гаснуть'), findsOneWidget);

    await t.tap(find.text('Не гаснет'));
    await settle(t);
    expect(power.display, true);

    await t.tap(find.text('Таймер'));
    await settle(t);
    await t.tap(find.text('2ч'));
    await settle(t);
    expect((c.until, c.timerMinutes), (Until.timer, 120));
    expect(find.textContaining('ещё 1:59:5'), findsOneWidget);

    // одна остановка Tab на переключатель: орб → разделы → экран → «до каких пор» → таймер
    for (var i = 0; i < 4; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
    }
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await settle(t);
    expect(c.timerMinutes, 60);
    await t.sendKeyEvent(LogicalKeyboardKey.home);
    await settle(t);
    expect(c.timerMinutes, 30);

    // Esc: закрыть настройки, потом спрятать окно
    hidden = 0;
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(t);
    expect((visible('Может гаснуть').evaluate().length, hidden), (0, 0));
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(hidden, 1);

    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
    semantics.dispose();
  });

  testWidgets('выбор процесса из списка и подсказка «не запущен»', (t) async {
    final (c, _) = await pump(t);
    hidden = 0;
    await t.tap(find.byIcon(Icons.settings_rounded));
    await settle(t);
    await t.tap(find.text('Процесс'));
    await settle(t);
    await t.tap(find.text('Выбрать процесс'));
    await settle(t);
    expect(find.text('Поиск процесса'), findsOneWidget);

    // Esc из поля поиска возвращает в «Режим», панель остаётся открытой
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(t);
    expect((visible('Выбрать процесс').evaluate().length, hidden), (1, 0));
    await t.tap(find.text('Выбрать процесс'));
    await settle(t);

    // список настоящий (Toolhelp32); фильтруем и берём первый
    await t.enterText(find.byType(EditableText), 'e');
    await settle(t);
    final first = find.descendant(of: find.byType(ListView), matching: find.byType(Text)).first;
    final name = t.widget<Text>(first).data!;
    expect(name, contains('e'));
    await t.tap(first);
    await settle(t);
    expect(c.processName, name);
    expect(visible(name), findsOneWidget, reason: 'вернулись в «Режим», имя на кнопке');

    // фейк говорит, что ничего не запущено
    await t.tap(find.bySemanticsLabel(S.ru.orbOn));
    await settle(t);
    expect((c.active, c.notice), (false, Notice.notRunning));
    expect(find.text('$name не запущен'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
    semantics.dispose();
  });

  testWidgets('расписание и «Общие»: цвет, язык, без переполнений', (t) async {
    final (c, _) = await pump(t);
    await t.tap(find.byIcon(Icons.settings_rounded));
    await settle(t);

    await t.tap(find.text('Расписание'));
    await settle(t);
    await t.tap(find.text('Не спать по расписанию'));
    await settle(t);
    expect(c.schedule.enabled, true);
    await t.tap(find.text('Сб'));
    await settle(t);
    expect(c.schedule.hasDay(DateTime.saturday), true);
    await t.tap(find.bySemanticsLabel('+30').last);
    await settle(t);
    expect(c.schedule.end, 18 * 60 + 30);
    expect(find.text('18:30'), findsOneWidget);

    await t.tap(find.text('Общие'));
    await settle(t);
    await t.tap(find.bySemanticsLabel('Зелёный'));
    await settle(t);
    expect(C.accent, accentPresets[3]);

    await t.tap(find.text('English'));
    await settle(t);
    expect(S.current.code, 'en');
    expect(visible('Start with Windows'), findsOneWidget, reason: 'экран пересоздан, панель осталась открытой');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
    semantics.dispose();
  });

  testWidgets('reduce motion: без бесконечных анимаций', (t) async {
    systemReducedMotion = true;
    addTearDown(() => systemReducedMotion = false);
    final (c, _) = await pump(t);
    c.toggle();
    await t.pump();
    // pumpAndSettle упал бы по таймауту, если бы дыхание/орбита/«z» крутились вечно
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
    semantics.dispose();
  });

  test('форма панели: закрыта — пилюля, открыта — панель + вогнутые стыки', () {
    const tab = (w: 184.0, h: 36.0);
    final closed = drawerPath(const Size(332, 36), panelW: 184, tabW: tab.w, tabH: tab.h);
    expect(closed.getBounds().width, closeTo(184, 0.5));
    expect(closed.contains(const Offset(10, 18)), false);

    final open = drawerPath(const Size(332, 236), panelW: 332, tabW: tab.w, tabH: tab.h);
    const tabLeft = (332 - 184) / 2;
    expect(open.contains(const Offset(166, 100)), true, reason: 'панель');
    expect(open.contains(const Offset(166, 220)), true, reason: 'кнопка');
    expect(open.contains(const Offset(tabLeft - 1, 201)), true, reason: 'вогнутый стык у кнопки');
    expect(open.contains(const Offset(tabLeft - 11, 211)), false, reason: 'за скруглением стыка пусто');
    expect(open.contains(const Offset(20, 220)), false, reason: 'под панелью сбоку пусто');
  });
}
