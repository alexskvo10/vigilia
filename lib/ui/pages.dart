import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../controller.dart';
import '../probes.dart';
import '../schedule.dart';
import '../strings.dart';
import '../theme.dart';
import '../updater.dart';
import 'hold_button.dart';
import 'hotkey_field.dart';
import 'pressable.dart';
import 'segmented.dart';
import 'toggle.dart';

enum SettingsPage {
  mode,
  schedule,
  general,
  system,
  picker,
  adapter;

  /// Вложенная страница раздела «Режим».
  bool get isSub => this == picker || this == adapter;
}

/// Содержимое панели настроек: переключатель разделов + текущий раздел.
/// Раздел сменяется кроссфейдом со сдвигом, высота панели меняется плавно.
class SettingsPages extends StatelessWidget {
  const SettingsPages({super.key, required this.c, required this.page, required this.onPage});

  final VigilController c;
  final SettingsPage page;
  final ValueChanged<SettingsPage> onPage;

  @override
  Widget build(BuildContext context) {
    final s = S.current;
    final tab = page.isSub ? SettingsPage.mode : page;
    final body = switch (page) {
      SettingsPage.mode => _ModePage(
        c: c,
        onPick: () => onPage(SettingsPage.picker),
        onAdapter: () => onPage(SettingsPage.adapter),
      ),
      SettingsPage.schedule => _SchedulePage(c: c),
      SettingsPage.general => _GeneralPage(c: c),
      SettingsPage.system => _SystemPage(c: c),
      SettingsPage.picker => _ProcessPicker(c: c, onDone: () => onPage(SettingsPage.mode)),
      SettingsPage.adapter => _AdapterPicker(c: c, onDone: () => onPage(SettingsPage.mode)),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Segmented<SettingsPage>(
          label: s.settings,
          items: [
            (SettingsPage.mode, s.pageMode),
            (SettingsPage.schedule, s.pageSchedule),
            (SettingsPage.general, s.pageGeneral),
            (SettingsPage.system, s.pageSystem),
          ],
          value: tab,
          onChanged: onPage,
          focusTag: 'page',
        ),
        const SizedBox(height: 12),
        AnimatedSize(
          duration: D.panel,
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: AnimatedSwitcher(
            duration: D.panel,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topCenter,
              children: [
                for (final p in previous) Positioned(left: 0, right: 0, top: 0, child: p),
                ?current,
              ],
            ),
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(a),
                child: child,
              ),
            ),
            child: KeyedSubtree(key: ValueKey(page), child: body),
          ),
        ),
      ],
    );
  }
}

/// Подпись раздела: иконка + капс.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.icon, this.text, {super.key, this.trailing});
  final IconData icon;
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 2, bottom: 8),
    child: Row(
      children: [
        Icon(icon, size: 13, color: C.overlay0),
        const SizedBox(width: 6),
        Text(text, style: mono(10, color: C.subtext0, spacing: 1.2)),
        const Spacer(),
        ?trailing,
      ],
    ),
  );
}

// ---------------- Режим ----------------

class _ModePage extends StatelessWidget {
  const _ModePage({required this.c, required this.onPick, required this.onAdapter});
  final VigilController c;
  final VoidCallback onPick, onAdapter;

  @override
  Widget build(BuildContext context) {
    final s = S.current;
    final sub = switch (c.until) {
      Until.always => const SizedBox(key: ValueKey('always'), width: double.infinity),
      Until.timer => Padding(
        key: const ValueKey('timer'),
        padding: const EdgeInsets.only(top: 8),
        child: Segmented<int>(
          label: s.untilTimer,
          items: [for (final m in timerPresets) (m, presetLabel(m, s))],
          value: c.timerMinutes,
          onChanged: c.setTimer,
        ),
      ),
      Until.process => Padding(
        key: const ValueKey('process'),
        padding: const EdgeInsets.only(top: 8),
        child: _RowButton(
          icon: Icons.apps_rounded,
          label: c.processes.isEmpty ? s.chooseProcess : processesLabel(c.processes),
          highlight: c.processes.isEmpty,
          trailing: Icons.chevron_right_rounded,
          onTap: onPick,
        ),
      ),
      Until.download => Padding(
        key: const ValueKey('download'),
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Segmented<int>(
              label: s.threshold,
              items: [for (final k in downloadPresets) (k, kbpsLabel(k, s))],
              value: c.downloadKbps,
              onChanged: c.setDownloadKbps,
            ),
            const SizedBox(height: 8),
            _RowButton(
              icon: Icons.lan_rounded,
              label: s.adapterLabel(c.adapter == null ? s.allAdapters : c.adapterName ?? ''),
              trailing: Icons.chevron_right_rounded,
              onTap: onAdapter,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Row(
                children: [
                  Icon(Icons.download_rounded, size: 14, color: C.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.downloadHint(kbpsLabel(c.downloadKbps, s)),
                      style: mono(10, weight: FontWeight.w500, color: C.subtext0),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(Icons.desktop_windows_rounded, s.display),
        Segmented<bool>(
          label: s.display,
          items: [(false, s.displayCanSleep), (true, s.displayStaysOn)],
          value: c.keepDisplay,
          onChanged: c.setKeepDisplay,
        ),
        const SizedBox(height: 12),
        SectionLabel(Icons.flag_outlined, s.untilLabel),
        Segmented<Until>(
          label: s.untilLabel,
          items: [
            (Until.always, s.untilAlways),
            (Until.timer, s.untilTimer),
            (Until.process, s.untilProcess),
            (Until.download, s.untilDownload),
          ],
          value: c.until,
          onChanged: c.setUntil,
        ),
        AnimatedSize(
          duration: D.panel,
          curve: Curves.easeOutCubic,
          child: AnimatedSwitcher(duration: D.color, child: sub),
        ),
      ],
    );
  }
}

String kbpsLabel(int k, S s) => k < 1000 ? '$k ${s.kbs}' : '${k ~/ 1000} ${s.mbs}';

String presetLabel(int m, S s) => m < 60 ? '$m${s.minutes}' : '${m ~/ 60}${s.hours}';

/// Строка-кнопка на всю ширину (выбор процесса, «назад»).
class _RowButton extends StatelessWidget {
  const _RowButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.highlight = false,
    this.iconOnly = false,
  });

  final IconData icon;
  final IconData? trailing;
  final String label;
  final bool highlight, iconOnly;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    radius: BorderRadius.circular(8),
    pop: 1.015,
    flash: 0.12,
    pressScale: 0.98,
    semanticLabel: label,
    onTap: onTap,
    builder: (context, hovered, _) => AnimatedContainer(
      duration: D.color,
      height: 34,
      padding: EdgeInsets.symmetric(horizontal: iconOnly ? 0 : 10),
      decoration: BoxDecoration(
        color: hovered ? C.hairline : C.text.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: highlight ? C.accent.withValues(alpha: 0.6) : C.hairline),
      ),
      child: iconOnly
          ? Icon(icon, size: 16, color: hovered ? C.accent : C.subtext0)
          : Row(
              children: [
                Icon(icon, size: 15, color: highlight || hovered ? C.accent : C.subtext0),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono(12, weight: FontWeight.w600, color: highlight ? C.accent : C.text),
                  ),
                ),
                if (trailing != null)
                  AnimatedSlide(
                    offset: Offset(hovered ? 0.15 : 0, 0),
                    duration: D.base,
                    curve: Curves.easeOutQuint,
                    child: Icon(trailing, size: 16, color: C.overlay0),
                  ),
              ],
            ),
    ),
  );
}

// ---------------- Выбор процесса ----------------

class _ProcessPicker extends StatefulWidget {
  const _ProcessPicker({required this.c, required this.onDone});
  final VigilController c;
  final VoidCallback onDone;

  @override
  State<_ProcessPicker> createState() => _ProcessPickerState();
}

class _ProcessPickerState extends State<_ProcessPicker> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  late List<WatchedProcess> _all = _load();

  List<WatchedProcess> _load() {
    final list = pickableProcesses();
    // выбранные ранее программы могли уже завершиться — всё равно показываем их первыми
    return [
      for (final p in widget.c.processes)
        if (!list.contains(p)) p,
      ...list,
    ];
  }

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.current;
    final q = _query.text.trim().toLowerCase();
    final items = q.isEmpty ? _all : _all.where((p) => p.name.contains(q) || (p.path?.contains(q) ?? false)).toList();
    final chosen = widget.c.processes;
    // одинаковые имена из разных папок подписываем папкой
    final names = <String, int>{};
    for (final p in _all) {
      names[p.name] = (names[p.name] ?? 0) + 1;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 34,
              child: _RowButton(icon: Icons.arrow_back_rounded, label: s.back, iconOnly: true, onTap: widget.onDone),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SearchField(controller: _query, focus: _focus, hint: s.searchProcess),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 34,
              child: _RowButton(
                icon: Icons.refresh_rounded,
                label: s.refresh,
                iconOnly: true,
                onTap: () => setState(() => _all = _load()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 160,
          child: items.isEmpty
              ? Center(
                  child: Text(
                    s.nothingFound,
                    style: mono(11, weight: FontWeight.w500, color: C.overlay0),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: items.length,
                  itemExtent: 30,
                  itemBuilder: (context, i) => _PickRow(
                    name: items[i].name,
                    hint: names[items[i].name]! > 1 && items[i].folder != null ? '${items[i].folder}\\' : null,
                    selected: chosen.contains(items[i]),
                    // каскад только для первых строк, как у списков в остальном UI
                    index: math.min(i, 8),
                    onTap: () => widget.c.toggleProcess(items[i]),
                  ),
                ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 14,
          child: AnimatedSwitcher(
            duration: D.color,
            child: Text(
              chosen.isEmpty ? s.pickHint : s.picked(chosen.length, maxWatched),
              key: ValueKey(chosen.length),
              style: mono(10, weight: FontWeight.w500, color: chosen.isEmpty ? C.overlay0 : C.subtext0),
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.focus, required this.hint});
  final TextEditingController controller;
  final FocusNode focus;
  final String hint;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, focus]),
    builder: (context, _) => AnimatedContainer(
      duration: D.color,
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: focus.hasFocus ? darker(C.surface0, 1.14) : C.text.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: focus.hasFocus ? C.accent : C.hairline),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 15, color: focus.hasFocus ? C.accent : C.overlay0),
          const SizedBox(width: 8),
          Expanded(
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                if (controller.text.isEmpty)
                  Text(
                    hint,
                    style: mono(12, weight: FontWeight.w500, color: C.overlay0),
                  ),
                EditableText(
                  controller: controller,
                  focusNode: focus,
                  autofocus: true,
                  style: mono(12, weight: FontWeight.w600),
                  cursorColor: C.accent,
                  backgroundCursorColor: C.overlay0,
                  cursorWidth: 2,
                  selectionColor: C.accent.withValues(alpha: 0.35),
                  maxLines: 1,
                  inputFormatters: [FilteringTextInputFormatter.deny('\n')],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _PickRow extends StatefulWidget {
  const _PickRow({
    required this.name,
    required this.selected,
    required this.index,
    required this.onTap,
    this.hint,
    this.icon,
  });
  final String name;
  final String? hint; // приглушённая подпись после имени
  final IconData? icon;
  final bool selected;
  final int index;
  final VoidCallback onTap;

  @override
  State<_PickRow> createState() => _PickRowState();
}

class _PickRowState extends State<_PickRow> with SingleTickerProviderStateMixin {
  // строка въезжает слева: задержка index·40ms, 300ms OutBack(0.85)
  late final AnimationController _in;

  @override
  void initState() {
    super.initState();
    _in = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300 + widget.index * 40),
    )..forward();
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    final row = Pressable(
      radius: BorderRadius.circular(6),
      pop: 1.01,
      flash: 0.1,
      semanticLabel: widget.name,
      toggled: widget.selected,
      onTap: widget.onTap,
      builder: (context, hovered, _) => AnimatedContainer(
        duration: D.color,
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: widget.selected ? C.accent : (hovered ? C.hairline : C.hairline.withValues(alpha: 0)),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, size: 14, color: widget.selected ? C.onAccent : (hovered ? C.accent : C.overlay0)),
              const SizedBox(width: 8),
            ],
            // имя и подпись занимают всё место до галочки — галочка всегда у правого края
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      widget.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(
                        11.5,
                        weight: widget.selected ? FontWeight.w700 : FontWeight.w500,
                        color: widget.selected ? C.onAccent : (hovered ? C.text : C.subtext0),
                      ),
                    ),
                  ),
                  if (widget.hint != null) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        widget.hint!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: mono(
                          10,
                          weight: FontWeight.w500,
                          color: widget.selected ? C.onAccent.withValues(alpha: 0.6) : C.overlay0,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // галочка «выскакивает» с пружинкой
            AnimatedScale(
              scale: widget.selected ? 1 : 0,
              duration: still ? Duration.zero : const Duration(milliseconds: 320),
              curve: widget.selected ? const OutBack(1.8) : Curves.easeInCubic,
              child: Icon(Icons.check_rounded, size: 15, color: C.onAccent),
            ),
          ],
        ),
      ),
    );
    if (still) return row;
    return AnimatedBuilder(
      animation: _in,
      child: row,
      builder: (context, child) {
        final total = _in.duration!.inMilliseconds;
        final t = ((_in.value * total - widget.index * 40) / 300).clamp(0.0, 1.0);
        return Opacity(
          opacity: Curves.easeOutCubic.transform(t),
          child: Transform.translate(offset: Offset(-14 * (1 - const OutBack(0.85).transform(t)), 0), child: child),
        );
      },
    );
  }
}

// ---------------- Выбор адаптера ----------------

class _AdapterPicker extends StatefulWidget {
  const _AdapterPicker({required this.c, required this.onDone});
  final VigilController c;
  final VoidCallback onDone;

  @override
  State<_AdapterPicker> createState() => _AdapterPickerState();
}

class _AdapterPickerState extends State<_AdapterPicker> {
  late List<NetAdapter> _all = pickableAdapters();

  void _pick(String? guid, String? name) {
    widget.c.setAdapter(guid, name);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.current, c = widget.c;
    // выбранный адаптер сейчас может быть отключён — всё равно показываем его
    final missing = c.adapter != null && !_all.any((a) => a.guid == c.adapter);
    final rows = <Widget>[
      _PickRow(
        name: s.allAdapters,
        hint: s.allAdaptersHint,
        icon: Icons.hub_rounded,
        selected: c.adapter == null,
        index: 0,
        onTap: () => _pick(null, null),
      ),
      if (missing)
        _PickRow(
          name: c.adapterName ?? '',
          hint: s.disconnected,
          icon: Icons.link_off_rounded,
          selected: true,
          index: 1,
          onTap: widget.onDone,
        ),
      for (final (i, a) in _all.indexed)
        _PickRow(
          name: a.name,
          hint: a.vpn ? 'VPN' : null,
          icon: a.vpn
              ? Icons.vpn_lock_rounded
              : a.wireless
              ? Icons.wifi_rounded
              : Icons.settings_ethernet_rounded,
          selected: a.guid == c.adapter,
          index: math.min(i + (missing ? 2 : 1), 8),
          onTap: () => _pick(a.guid, a.name),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 34,
              child: _RowButton(icon: Icons.arrow_back_rounded, label: s.back, iconOnly: true, onTap: widget.onDone),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(s.adapterTitle, style: mono(12, color: C.text)),
            ),
            SizedBox(
              width: 34,
              child: _RowButton(
                icon: Icons.refresh_rounded,
                label: s.refresh,
                iconOnly: true,
                onTap: () => setState(() => _all = pickableAdapters()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 180),
          child: ListView(padding: EdgeInsets.zero, shrinkWrap: true, itemExtent: 30, children: rows),
        ),
      ],
    );
  }
}

// ---------------- Расписание ----------------

class _SchedulePage extends StatelessWidget {
  const _SchedulePage({required this.c});
  final VigilController c;

  @override
  Widget build(BuildContext context) {
    final s = S.current, sch = c.schedule;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Toggle(
          icon: Icons.event_rounded,
          label: s.scheduleToggle,
          hint: switch ((c.windowEnd, c.nextWindow)) {
            (final end?, _) when c.scheduled => s.onSchedule(hhmm(end)),
            (_, final next?) => s.nextWindow(whenText(next, c.now, s)),
            _ => null,
          },
          value: sch.enabled,
          onChanged: (v) => c.setSchedule(sch.copyWith(enabled: v)),
        ),
        const SizedBox(height: 8),
        // пока расписание выключено, настройки видны, но приглушены
        AnimatedOpacity(
          opacity: sch.enabled ? 1 : 0.45,
          duration: D.color,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var d = 0; d < 7; d++)
                    _DayChip(
                      label: s.days[d],
                      on: sch.days & (1 << d) != 0,
                      weekend: d >= 5,
                      onTap: () => c.setSchedule(sch.copyWith(days: sch.days ^ (1 << d))),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _TimeStepper(
                      label: s.from,
                      minutes: sch.start,
                      onChanged: (m) => c.setSchedule(sch.copyWith(start: m)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _TimeStepper(
                      label: s.to,
                      minutes: sch.end,
                      onChanged: (m) => c.setSchedule(sch.copyWith(end: m)),
                    ),
                  ),
                ],
              ),
              AnimatedSize(
                duration: D.base,
                curve: Curves.easeOutCubic,
                child: sch.overnight
                    ? Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            Icon(Icons.nightlight_round, size: 12, color: C.overlay0),
                            const SizedBox(width: 6),
                            Text(
                              s.overnight,
                              style: mono(10, weight: FontWeight.w500, color: C.overlay0),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Круглая кнопка дня недели: включённый день залит акцентом, заливка «вырастает» из центра (OutBack).
class _DayChip extends StatelessWidget {
  const _DayChip({required this.label, required this.on, required this.weekend, required this.onTap});
  final String label;
  final bool on, weekend;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    radius: BorderRadius.circular(16),
    pop: 1.10,
    popUp: 110,
    popDown: 420,
    flash: 0.3,
    hoverScale: 1.06,
    pressScale: 0.94,
    toggled: on,
    semanticLabel: label,
    onTap: onTap,
    builder: (context, hovered, _) => SizedBox.square(
      dimension: 32,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: D.color,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hovered ? C.surface1 : C.text.withValues(alpha: 0.05),
              border: Border.all(color: C.hairline),
            ),
          ),
          AnimatedScale(
            scale: on ? 1 : 0,
            duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 320),
            curve: on ? const OutBack(1.6) : Curves.easeInCubic,
            child: DecoratedBox(
              decoration: BoxDecoration(shape: BoxShape.circle, color: C.accent),
              child: const SizedBox.expand(),
            ),
          ),
          Text(label, style: mono(10.5, color: on ? C.onAccent : (weekend ? C.overlay0 : C.subtext0))),
        ],
      ),
    ),
  );
}

/// «С 09:00 [−][+]»: шаг 30 минут, по кругу через полночь. Цифры меняются вертикальным «перелистыванием».
class _TimeStepper extends StatelessWidget {
  const _TimeStepper({required this.label, required this.minutes, required this.onChanged});
  final String label;
  final int minutes;
  final ValueChanged<int> onChanged;

  void _step(int d) => onChanged((minutes + d * 30) % (24 * 60));

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.only(left: 10, right: 3),
      decoration: BoxDecoration(
        color: C.hairline,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: C.hairline),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: mono(10, weight: FontWeight.w600, color: C.overlay0),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: ClipRect(
              child: AnimatedSwitcher(
                duration: D.base,
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(a),
                    child: child,
                  ),
                ),
                child: Text(
                  minutesToHhmm(minutes),
                  key: ValueKey(minutes),
                  style: mono(14, weight: FontWeight.w800),
                ),
              ),
            ),
          ),
          _StepButton(icon: Icons.remove_rounded, label: '−30', onTap: () => _step(-1)),
          _StepButton(icon: Icons.add_rounded, label: '+30', onTap: () => _step(1)),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    radius: BorderRadius.circular(6),
    pop: 1.10,
    popUp: 110,
    popDown: 420,
    flash: 0.4,
    flashMs: 400,
    hoverScale: 1.04,
    pressScale: 1.08,
    semanticLabel: label,
    onTap: onTap,
    builder: (context, hovered, _) => AnimatedContainer(
      duration: D.color,
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: hovered ? C.surface1 : C.surface1.withValues(alpha: 0),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, size: 15, color: hovered ? C.text : C.subtext0),
    ),
  );
}

// ---------------- Общие ----------------

class _GeneralPage extends StatelessWidget {
  const _GeneralPage({required this.c});
  final VigilController c;

  @override
  Widget build(BuildContext context) {
    final s = S.current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(Icons.palette_outlined, s.color),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < accentPresets.length; i++)
              _Swatch(
                color: accentPresets[i],
                label: s.accentNames[i],
                tag: 'accent$i',
                selected: c.accent == i,
                onTap: () => c.setAccent(i),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SectionLabel(Icons.translate_rounded, s.language),
        Segmented<String>(
          label: s.language,
          items: const [('ru', 'Русский'), ('en', 'English')],
          value: s.code,
          onChanged: c.setLanguage,
          focusTag: 'lang',
        ),
        Container(height: 1, margin: const EdgeInsets.fromLTRB(2, 12, 2, 4), color: C.hairline),
        Toggle(
          icon: c.soundsOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          label: s.sounds,
          value: c.soundsOn,
          onChanged: c.setSounds,
        ),
      ],
    );
  }
}

// ---------------- Система ----------------

class _SystemPage extends StatelessWidget {
  const _SystemPage({required this.c});
  final VigilController c;

  @override
  Widget build(BuildContext context) {
    final s = S.current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Toggle(
          icon: Icons.keyboard_rounded,
          label: s.hotkey,
          hintWidget: Row(
            children: [
              Flexible(
                child: HotkeyField(
                  value: c.hotkeyKey,
                  busy: c.hotkeyBusy,
                  busyText: s.hotkeyBusy,
                  onChanged: c.setHotkeyKey,
                  onRecording: c.recordHotkey,
                ),
              ),
            ],
          ),
          value: c.hotkey && c.hotkeyActive,
          onChanged: c.setHotkey,
        ),
        Toggle(icon: Icons.rocket_launch_rounded, label: s.autostart, value: c.autostart, onChanged: c.setAutostart),
        Container(height: 1, margin: const EdgeInsets.fromLTRB(2, 4, 2, 10), color: C.hairline),
        _UpdatesSection(c: c),
      ],
    );
  }
}

/// Обновления: автопроверка, статус и кнопка «удерживайте, чтобы обновить».
class _UpdatesSection extends StatefulWidget {
  const _UpdatesSection({required this.c});
  final VigilController c;

  @override
  State<_UpdatesSection> createState() => _UpdatesSectionState();
}

class _UpdatesSectionState extends State<_UpdatesSection> {
  @override
  void initState() {
    super.initState();
    // не во время построения: проверка сразу меняет статус
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.c.checkUpdatesSoon();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.current, c = widget.c, u = c.updater;
    return ListenableBuilder(
      listenable: u,
      builder: (context, _) {
        final latest = u.latest?.version ?? '';
        final percent = (u.progress * 100).round();
        final status = switch (u.status) {
          UpdateStatus.idle => s.updCurrent(appVersion),
          UpdateStatus.checking => s.updChecking,
          UpdateStatus.upToDate => s.updLatest(appVersion),
          UpdateStatus.available => s.updAvailable(latest),
          UpdateStatus.downloading => s.updDownloading(percent).toLowerCase(),
          UpdateStatus.installing => s.updInstalling.toLowerCase(),
          UpdateStatus.failed => s.updFailed,
        };
        final (label, progress) = switch (u.status) {
          UpdateStatus.downloading => (s.updDownloading(percent), u.progress),
          UpdateStatus.installing => (s.updInstalling, 1.0),
          _ => (u.installed ? s.holdToUpdate(latest) : s.holdToDownload(latest), null),
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionLabel(
              Icons.system_update_alt_rounded,
              s.updates,
              trailing: _SpinButton(
                label: s.checkNow,
                spinning: u.status == UpdateStatus.checking,
                onTap: u.busy ? null : () => u.check(),
              ),
            ),
            Toggle(
              icon: Icons.autorenew_rounded,
              label: s.checkUpdates,
              hint: status,
              warn: u.status == UpdateStatus.failed,
              value: c.checkUpdates,
              onChanged: c.setCheckUpdates,
            ),
            AnimatedSize(
              duration: D.panel,
              curve: Curves.easeOutCubic,
              child: u.hasUpdate
                  ? Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: HoldButton(
                        label: label,
                        icon: Icons.download_rounded,
                        progress: progress,
                        sounds: c.sounds,
                        onConfirmed: u.update,
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        );
      },
    );
  }
}

/// Маленькая круглая кнопка с иконкой обновления; крутится, пока идёт проверка.
class _SpinButton extends StatefulWidget {
  const _SpinButton({required this.label, required this.spinning, required this.onTap});
  final String label;
  final bool spinning;
  final VoidCallback? onTap;

  @override
  State<_SpinButton> createState() => _SpinButtonState();
}

class _SpinButtonState extends State<_SpinButton> with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didUpdateWidget(_SpinButton old) {
    super.didUpdateWidget(old);
    if (widget.spinning && !reduceMotion(context)) {
      if (!_spin.isAnimating) _spin.repeat();
    } else if (_spin.isAnimating) {
      // докручиваем до целого оборота, чтобы иконка не замирала боком
      _spin.animateTo(1, duration: Duration(milliseconds: ((1 - _spin.value) * 900).round() + 1)).then((_) {
        if (mounted) _spin.value = 0;
      }, onError: (_) {});
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Pressable(
    radius: BorderRadius.circular(11),
    pop: 1.12,
    popUp: 110,
    popDown: 420,
    flash: 0.3,
    hoverScale: 1.08,
    pressScale: 0.92,
    semanticLabel: widget.label,
    onTap: widget.onTap ?? () {},
    builder: (context, hovered, _) => SizedBox.square(
      dimension: 22,
      child: RotationTransition(
        turns: _spin,
        child: Icon(Icons.refresh_rounded, size: 15, color: widget.spinning || hovered ? C.accent : C.overlay0),
      ),
    ),
  );
}

/// Цветной кружок акцента: выбранный обведён кольцом, которое «пружинит» при выборе.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.label,
    required this.tag,
    required this.selected,
    required this.onTap,
  });
  final Color color;
  final String label, tag;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    radius: BorderRadius.circular(17),
    pop: 1.10,
    popUp: 110,
    popDown: 420,
    flash: 0.4,
    flashMs: 400,
    hoverScale: 1.08,
    pressScale: 0.92,
    selected: selected,
    semanticLabel: label,
    focusTag: tag,
    onTap: onTap,
    builder: (context, hovered, _) => SizedBox.square(
      dimension: 34,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedScale(
            scale: selected ? 1 : 0.6,
            duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 360),
            curve: selected ? const OutBack(1.8) : Curves.easeInCubic,
            child: AnimatedOpacity(
              opacity: selected ? 1 : 0,
              duration: D.color,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [lighter(color, 1.04), darker(color, 1.15)],
              ),
              boxShadow: [BoxShadow(color: color.withValues(alpha: hovered ? 0.45 : 0.2), blurRadius: 8)],
            ),
          ),
        ],
      ),
    ),
  );
}
