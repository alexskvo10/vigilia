import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../controller.dart';
import '../sounds.dart';
import '../theme.dart';
import 'motion.dart';
import 'orb.dart';
import 'segmented.dart';
import 'settings_drawer.dart';
import 'title_bar.dart';
import 'toggle.dart';

class Home extends StatefulWidget {
  const Home({super.key, required this.c, required this.onHide});

  final VigilController c;
  final VoidCallback onHide;

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  static const _orbArea = 292.0, _statusArea = 60.0;
  final _pointer = ValueNotifier<Offset?>(null);
  bool _settings = false; // настройки по умолчанию скрыты

  void _toggleSettings() {
    widget.c.sounds.play(Sfx.tick);
    setState(() => _settings = !_settings);
  }

  // Esc сначала закрывает настройки, потом прячет окно в трей
  void _escape() => _settings ? _toggleSettings() : widget.onHide();

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
        onExit: (_) => _pointer.value = null,
        child: ColoredBox(
          color: C.base,
          child: ListenableBuilder(
            listenable: c,
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
                          final scale = ((box.maxHeight - _statusArea) / _orbArea).clamp(0.55, 1.0);
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
                                      child: Orb(
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
                              Cascade(index: 1, child: _Status(c)),
                            ],
                          );
                        },
                      ),
                    ),
                    Cascade(
                      index: 2,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SettingsDrawer(open: _settings, onToggle: _toggleSettings, children: _settingsRows(c)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Cascade(
                      index: 3,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'v1.0.0 · пробел — вкл/выкл · esc — в трей',
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

  List<Widget> _settingsRows(VigilController c) => [
    const _Label(Icons.desktop_windows_rounded, 'ЭКРАН'),
    Segmented<bool>(
      label: 'Экран',
      items: const [(false, 'Может гаснуть'), (true, 'Не гаснет')],
      value: c.keepDisplay,
      onChanged: c.setKeepDisplay,
    ),
    const SizedBox(height: 12),
    const _Label(Icons.timer_outlined, 'ТАЙМЕР'),
    Segmented<int>(
      label: 'Таймер',
      items: [for (final m in timerPresets) (m, _preset(m))],
      value: c.timerMinutes,
      onChanged: c.setTimer,
    ),
    Container(height: 1, margin: const EdgeInsets.fromLTRB(2, 12, 2, 4), color: C.hairline),
    Toggle(icon: Icons.rocket_launch_rounded, label: 'Запуск с Windows', value: c.autostart, onChanged: c.setAutostart),
    Toggle(
      icon: c.soundsOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
      label: 'Звуки',
      value: c.soundsOn,
      onChanged: c.setSounds,
    ),
  ];
}

String _preset(int m) => m == 0 ? '∞' : (m < 60 ? '$mм' : '${m ~/ 60}ч');

String _clock(Duration d) {
  String two(int v) => v.toString().padLeft(2, '0');
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

class _Status extends StatelessWidget {
  const _Status(this.c);
  final VigilController c;

  @override
  Widget build(BuildContext context) {
    final (title, color) = c.error
        ? ('Не получилось', C.danger)
        : c.active
        ? ('Не даю уснуть', C.text)
        : ('Обычный сон', C.subtext0);

    final remaining = c.remaining, end = c.endsAt;
    final (kind, sub) = c.error
        ? ('err', 'Windows отклонила запрос питания')
        : !c.active
        ? ('off', 'Компьютер уснёт по настройкам Windows')
        : (remaining != null && end != null)
        ? (
            'timer',
            'ещё ${_clock(remaining)} · до ${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}',
          )
        : c.keepDisplay
        ? ('disp', 'Система и экран не уснут')
        : ('sys', 'Система не уснёт, экран может погаснуть');

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
              style: mono(11, weight: FontWeight.w500, color: C.subtext0),
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 2, bottom: 8),
    child: Row(
      children: [
        Icon(icon, size: 13, color: C.overlay0),
        const SizedBox(width: 6),
        Text(text, style: mono(10, color: C.subtext0, spacing: 1.2)),
      ],
    ),
  );
}
