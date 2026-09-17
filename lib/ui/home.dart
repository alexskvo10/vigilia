import 'dart:io' show pid;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../controller.dart';
import '../schedule.dart';
import '../sounds.dart';
import '../strings.dart';
import '../theme.dart';
import '../updater.dart';
import '../win32.dart';
import 'motion.dart';
import 'orb.dart';
import 'pages.dart';
import 'pressable.dart';
import 'settings_drawer.dart';
import 'title_bar.dart';

/// Состояние интерфейса, которое переживает пересоздание экрана (смена цвета/языка).
class UiState {
  final settings = ValueNotifier(false); // панель настроек по умолчанию скрыта
  final page = ValueNotifier(SettingsPage.mode);
  String? screenKey; // цвет/язык последнего построенного экрана
}

/// Экран целиком. Смена цвета или языка пересоздаёт его с кроссфейдом:
/// вся палитра и все тексты меняются разом, а открытая панель и раздел сохраняются.
class VigiliaScreen extends StatelessWidget {
  const VigiliaScreen({super.key, required this.c, required this.ui, required this.onHide});

  final VigilController c;
  final UiState ui;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final key = '${c.accent}/${S.current.code}';
      // экран пересоздаётся — фокус переходит к той же кнопке нового экрана
      if (ui.screenKey != null && ui.screenKey != key) restoreFocusOnRebuild();
      ui.screenKey = key;
      return AnimatedSwitcher(
        duration: D.settle,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: DefaultTextStyle(
          key: ValueKey(key),
          style: mono(12),
          child: Home(c: c, ui: ui, onHide: onHide),
        ),
      );
    },
  );
}

class Home extends StatefulWidget {
  const Home({super.key, required this.c, required this.ui, required this.onHide});

  final VigilController c;
  final UiState ui;
  final VoidCallback onHide;

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  static const _orbArea = 292.0, _statusArea = 60.0;
  final _pointer = ValueNotifier<Offset?>(null);

  UiState get ui => widget.ui;

  void _toggleSettings() {
    widget.c.sounds.play(Sfx.tick);
    ui.settings.value = !ui.settings.value;
    if (!ui.settings.value && ui.page.value.isSub) ui.page.value = SettingsPage.mode;
  }

  void _setPage(SettingsPage p) {
    if (p == ui.page.value) return;
    widget.c.sounds.play(Sfx.tick);
    ui.page.value = p;
  }

  // Esc: выбор процесса/адаптера → раздел «Режим» → закрыть настройки → спрятать окно
  void _escape() {
    if (ui.settings.value && ui.page.value.isSub) {
      _setPage(SettingsPage.mode);
    } else if (ui.settings.value) {
      _toggleSettings();
    } else {
      widget.onHide();
    }
  }

  @override
  void dispose() {
    _pointer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _escape},
      child: MouseRegion(
        onHover: (e) => _pointer.value = e.position,
        // ложный «уход» при клике (курсор на месте) глаз не сбрасывает
        onExit: (_) {
          if (!cursorOverOwnWindow(pid)) _pointer.value = null;
        },
        child: ColoredBox(
          color: C.base,
          child: ListenableBuilder(
            listenable: Listenable.merge([c, ui.settings, ui.page]),
            builder: (context, _) => Stack(
              children: [
                // мягкое акцентное свечение окна во включённом режиме
                Positioned(
                  left: -60,
                  right: -60,
                  top: -120,
                  height: 520,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: c.active ? 1 : 0.35,
                      duration: c.active ? D.slow : D.panel,
                      curve: c.active ? Curves.easeOutCubic : Curves.easeInCubic,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            colors: [
                              C.accent.withValues(alpha: c.active ? 0.13 : 0.05),
                              C.accent.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Column(
                  children: [
                    TitleBar(onHide: widget.onHide),
                    // орб плавно уменьшается, когда снизу раскрываются настройки
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) {
                          final scale = ((box.maxHeight - _statusArea) / _orbArea).clamp(0.4, 1.0);
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Cascade(
                                index: 0,
                                child: SizedBox(
                                  height: _orbArea * scale,
                                  child: OverflowBox(
                                    maxHeight: 340,
                                    child: Transform.scale(
                                      scale: scale,
                                      // кольцо таймера двигается раз в секунду — пересобираем только орб
                                      child: ValueListenableBuilder(
                                        valueListenable: c.clock,
                                        builder: (context, _, _) => Orb(
                                          active: c.active,
                                          error: c.error,
                                          progress: c.progress,
                                          pointer: _pointer,
                                          onTap: c.toggle,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Cascade(
                                index: 1,
                                child: ValueListenableBuilder(
                                  valueListenable: c.clock,
                                  builder: (context, _, _) => Status(c),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    Cascade(
                      index: 2,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SettingsDrawer(
                          open: ui.settings.value,
                          onToggle: _toggleSettings,
                          children: [SettingsPages(c: c, page: ui.page.value, onPage: _setPage)],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Cascade(
                      index: 3,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          S.current.footer(appVersion),
                          style: mono(10, weight: FontWeight.w500, color: C.overlay0),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String clockText(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

String speedText(double bps, S s) =>
    bps < 1024 * 1024 ? '${(bps / 1024).round()} ${s.kbs}' : '${(bps / 1024 / 1024).toStringAsFixed(1)} ${s.mbs}';

/// Заголовок и подзаголовок под орбом.
class Status extends StatelessWidget {
  const Status(this.c, {super.key});
  final VigilController c;

  /// (ключ для анимации смены, текст, предупреждение ли)
  static (String, String, bool) subtitle(VigilController c, S s) {
    final procs = c.processes;
    final one = procs.length == 1 ? procs.first.name : null;
    final quiet = c.quietLeft, speed = c.speed, left = c.remaining, end = c.endsAt, win = c.windowEnd;
    if (c.error) return ('err', s.subError, false);
    if (!c.active) {
      return switch (c.notice) {
        Notice.pickProcess => ('notice', s.pickProcessFirst, true),
        Notice.notRunning => ('notice', one != null ? s.notRunning(one) : s.notRunningAny, true),
        Notice.none => switch (c.nextWindow) {
          final next? => ('next', s.nextWindow(whenText(next, c.now, s)), false),
          null => ('off', s.subOff, false),
        },
      };
    }
    if (c.scheduled && win != null) return ('schedule', s.onSchedule(hhmm(win)), false);
    if (left != null && end != null) return ('timer', s.left(clockText(left), hhmm(end)), false);
    if (c.manual && c.until == Until.process) {
      return ('process', one != null ? s.whileRunning(one) : s.whileRunningMany(procs.length), false);
    }
    if (c.manual && c.until == Until.download) {
      final idle = quiet != null && (speed == null || speed < c.downloadThreshold);
      return idle
          ? ('idle', s.downloadIdle(clockText(quiet)), false)
          : ('download', s.download(speedText(speed ?? 0, s)), false);
    }
    return c.keepDisplay ? ('disp', s.subDisplay, false) : ('sys', s.subSystem, false);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.current;
    final (title, color) = c.error
        ? (s.titleError, C.danger)
        : c.active
        ? (s.titleOn, C.text)
        : (s.titleOff, C.subtext0);
    final (kind, sub, warn) = subtitle(c, s);

    return SizedBox(
      height: 52,
      child: Column(
        children: [
          Letters(
            title,
            style: mono(20, weight: FontWeight.w800, color: color),
          ),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: D.color,
            child: Text(
              sub,
              key: ValueKey(kind),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono(11, weight: FontWeight.w500, color: warn ? C.warning : C.subtext0),
            ),
          ),
        ],
      ),
    );
  }
}
