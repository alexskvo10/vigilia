import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigilia/sounds.dart';
import 'package:vigilia/ui/hold_button.dart';
import 'package:vigilia/updater.dart';

import 'controller_test.dart' show FakeSounds;

Map<String, Object?> releaseJson({
  String tag = 'v1.3.0',
  String name = 'Vigilia-1.3.0-setup.exe',
  int size = 4,
  String? digest,
}) => {
  'tag_name': tag,
  'draft': false,
  'prerelease': false,
  'assets': [
    {'name': 'notes.txt', 'browser_download_url': 'https://example.com/notes.txt', 'size': 1},
    {'name': name, 'browser_download_url': 'https://example.com/$name', 'size': size, 'digest': digest},
  ],
};

void main() {
  group('разбор релиза', () {
    test('версия, установщик, хеш', () {
      final r = Release.parse(releaseJson(digest: 'sha256:ABCDEF'))!;
      expect((r.version, r.size, r.sha256), ('1.3.0', 4, 'abcdef'));
      expect(r.url.toString(), 'https://example.com/Vigilia-1.3.0-setup.exe');
    });

    test('черновик, пре-релиз, без установщика, кривой тег — не релиз', () {
      expect(Release.parse({...releaseJson(), 'draft': true}), isNull);
      expect(Release.parse({...releaseJson(), 'prerelease': true}), isNull);
      expect(Release.parse(releaseJson(name: 'Vigilia.zip')), isNull);
      expect(Release.parse(releaseJson(tag: 'latest')), isNull);
      expect(Release.parse(null), isNull);
      expect(Release.parse('garbage'), isNull);
    });

    test('сравнение версий', () {
      expect(compareVersions('1.2.0', '1.1.9'), 1);
      expect(compareVersions('1.2', '1.2.0'), 0);
      expect(compareVersions('1.10.0', '1.9.0'), 1);
      expect(compareVersions('1.2.0', '1.2.1'), -1);
      expect(compareVersions('x', '1.0.0'), -1);
    });

    test('хеш из вывода certutil (новый и старый формат)', () {
      const hash = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
      expect(parseCertutilHash('SHA256 hash of f.exe:\r\n$hash\r\nCertUtil: -hashfile OK\r\n'), hash);
      final spaced = [for (var i = 0; i < 64; i += 2) hash.substring(i, i + 2).toUpperCase()].join(' ');
      expect(parseCertutilHash('SHA256 hash of file f.exe:\r\n$spaced\r\n'), hash);
      expect(parseCertutilHash('error'), isNull);
    });
  });

  group('Updater', () {
    late Directory dir;
    late List<String> log;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('vigilia_upd');
      log = [];
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Updater make({
      Object? json,
      Object? error,
      List<int> bytes = const [1, 2, 3, 4],
      String? hash,
      bool installed = true,
      DateTime Function()? now,
    }) => Updater(
      current: '1.2.0',
      installed: installed,
      now: now,
      fetchJson: (url) async {
        log.add('fetch');
        if (error != null) throw error;
        return json;
      },
      download: (r, progress) async {
        progress(0.5);
        progress(1);
        return File('${dir.path}/setup.exe')..writeAsBytesSync(bytes);
      },
      sha256: (f) async => hash,
      runInstaller: (f) async => log.add('install'),
      openPage: (url) async => log.add('open $url'),
    )..onQuit = () => log.add('quit');

    test('нашли новую версию → скачали → запустили установщик → выход', () async {
      final u = make(
        json: releaseJson(digest: 'sha256:aa'),
        hash: 'aa',
      );
      final progress = <double>[];
      u.addListener(() => progress.add(u.progress));
      await u.check();
      expect((u.status, u.hasUpdate, u.latest!.version), (UpdateStatus.available, true, '1.3.0'));
      await u.update();
      expect(progress, containsAllInOrder([0.5, 1.0]));
      expect(u.status, UpdateStatus.installing);
      expect(log, ['fetch', 'install', 'quit']);
    });

    test('та же или старая версия, релизов нет, ошибка сети', () async {
      final same = make(json: releaseJson(tag: 'v1.2.0'));
      await same.check();
      expect((same.status, same.hasUpdate), (UpdateStatus.upToDate, false));

      final none = make(json: null); // 404
      await none.check();
      expect(none.status, UpdateStatus.upToDate);

      final offline = make(error: const SocketException('нет сети'));
      await offline.check();
      expect((offline.status, offline.hasUpdate), (UpdateStatus.failed, false));
    });

    test('размер или хеш не совпали — установщик не запускается', () async {
      final short = make(json: releaseJson(), bytes: [1, 2]);
      await short.check();
      await short.update();
      expect(short.status, UpdateStatus.failed);

      final bad = make(
        json: releaseJson(digest: 'sha256:aa'),
        hash: 'bb',
      );
      await bad.check();
      await bad.update();
      expect((bad.status, bad.hasUpdate), (UpdateStatus.failed, true), reason: 'кнопка остаётся для повтора');
      expect(log, isNot(contains('install')));
      expect(File('${dir.path}/setup.exe').existsSync(), false, reason: 'подозрительный файл удалён');
    });

    test('портативная копия — открывается страница релиза', () async {
      final u = make(json: releaseJson(), installed: false);
      await u.check();
      await u.update();
      expect(log, ['fetch', 'open $releasesPage']);
    });

    test('недавняя проверка не повторяется', () async {
      var now = DateTime(2026, 9, 17, 12);
      final u = make(
        json: releaseJson(tag: 'v1.2.0'),
        now: () => now,
      );
      await u.check();
      await u.check(ifOlderThan: const Duration(minutes: 10));
      expect(log, ['fetch']);
      now = now.add(const Duration(minutes: 11));
      await u.check(ifOlderThan: const Duration(minutes: 10));
      expect(log, ['fetch', 'fetch']);
    });
  });

  group('HoldButton', () {
    Future<(FakeSounds, List<int>)> pump(WidgetTester t, {double? progress}) async {
      final sounds = FakeSounds();
      final confirmed = <int>[];
      await t.pumpWidget(
        WidgetsApp(
          color: const Color(0xFF000000),
          builder: (_, _) => Center(
            child: SizedBox(
              width: 300,
              child: HoldButton(
                label: 'Удерживайте — обновить',
                icon: Icons.download_rounded,
                sounds: sounds,
                progress: progress,
                onConfirmed: () => confirmed.add(1),
              ),
            ),
          ),
        ),
      );
      return (sounds, confirmed);
    }

    testWidgets('короткое нажатие не срабатывает, удержание — срабатывает', (t) async {
      final (sounds, confirmed) = await pump(t);
      final at = t.getCenter(find.byType(HoldButton));
      final g = await t.startGesture(at, kind: PointerDeviceKind.mouse);
      await t.pump(const Duration(milliseconds: 400));
      await g.up();
      await t.pump(const Duration(seconds: 2));
      expect(confirmed, isEmpty);
      expect(sounds.played, [Sfx.charge]);

      final g2 = await t.startGesture(at, kind: PointerDeviceKind.mouse);
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(confirmed, [1]);
      expect(sounds.played.last, Sfx.impact);
      await g2.up();
      await t.pump(const Duration(seconds: 2));
      expect(confirmed, [1], reason: 'одно удержание — одно срабатывание');
      expect(t.takeException(), isNull);
    });

    testWidgets('клавиатура: удержание пробела', (t) async {
      final (_, confirmed) = await pump(t);
      Focus.of(
        t.element(find.descendant(of: find.byType(HoldButton), matching: find.byType(CustomPaint))),
      ).requestFocus();
      await t.pump();
      await t.sendKeyDownEvent(LogicalKeyboardKey.space);
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      await t.sendKeyUpEvent(LogicalKeyboardKey.space);
      await t.pump(const Duration(seconds: 2));
      expect(confirmed, [1]);
    });

    testWidgets('во время скачивания не нажимается', (t) async {
      final (sounds, confirmed) = await pump(t, progress: 0.4);
      final g = await t.startGesture(t.getCenter(find.byType(HoldButton)), kind: PointerDeviceKind.mouse);
      await t.pump(const Duration(seconds: 2));
      await g.up();
      await t.pump(const Duration(seconds: 1));
      expect(confirmed, isEmpty);
      expect(sounds.played, isEmpty);
    });
  });
}
