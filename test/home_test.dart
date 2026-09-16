import 'dart:io';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigilia/controller.dart';
import 'package:vigilia/settings.dart';
import 'package:vigilia/theme.dart';
import 'package:vigilia/ui/home.dart';
import 'package:vigilia/ui/settings_drawer.dart';

import 'controller_test.dart' show FakeAutostart, FakePower, FakeSounds;

/// Кадр, на котором анимация стартует, и прыжок по времени до её конца.
Future<void> settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(seconds: 2));
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vigilia_ui'));
  tearDown(() => dir.deleteSync(recursive: true));

  var hidden = 0;
  Future<(VigilController, FakePower)> pump(WidgetTester t) async {
    final power = FakePower();
    final c = VigilController(
      power: power,
      sounds: FakeSounds(),
      store: SettingsStore(File('${dir.path}/s.json')),
      autostartService: FakeAutostart(),
    )..load();
    t.view.physicalSize = const Size(366, 686);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      WidgetsApp(
        color: C.accent,
        textStyle: mono(12),
        builder: (_, _) => Home(c: c, onHide: () => hidden++),
      ),
    );
    await settle(t);
    return (c, power);
  }

  testWidgets('экран строится без переполнений, орб и настройки работают', (t) async {
    final (c, power) = await pump(t);
    expect(t.takeException(), isNull);
    expect(find.text('Обычный сон'), findsNothing, reason: 'заголовок набран посимвольно');
    // настройки по умолчанию скрыты
    expect(find.text('Может гаснуть').hitTestable(), findsNothing);

    // пробел по орбу (autofocus) включает режим
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await settle(t);
    expect((c.active, power.system), (true, true));

    await t.tap(find.byIcon(Icons.settings_rounded));
    await settle(t);
    expect(find.text('Может гаснуть').hitTestable(), findsOneWidget);

    await t.tap(find.text('Не гаснет'));
    await settle(t);
    expect(power.display, true);

    await t.tap(find.text('1ч'));
    await settle(t);
    expect(c.timerMinutes, 60);
    expect(find.textContaining('ещё 59:5'), findsOneWidget);

    // клавиатура: Tab с орба → «Экран»×2 → «Таймер» ∞, 30м, 1ч; стрелка вправо → 2ч
    for (var i = 0; i < 5; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
    }
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settle(t);
    expect(c.timerMinutes, 120);

    await t.tap(find.byIcon(Icons.rocket_launch_rounded));
    await settle(t);
    expect(c.autostart, true);

    // Esc: сначала закрывает настройки, потом прячет окно
    hidden = 0;
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(t);
    expect((find.text('Может гаснуть').hitTestable().evaluate().length, hidden), (0, 0));
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(hidden, 1);

    expect(t.takeException(), isNull);
    // размонтирование: все контроллеры и таймеры (моргание, тик) должны освободиться
    await t.pumpWidget(const SizedBox());
    c.dispose();
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
