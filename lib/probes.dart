import 'settings.dart' show WatchedProcess;
import 'win32.dart';

/// Системные процессы, которые нет смысла предлагать в списке «пока работает».
const _system = {
  'system',
  '[system process]',
  'registry',
  'smss.exe',
  'csrss.exe',
  'wininit.exe',
  'winlogon.exe',
  'services.exe',
  'lsass.exe',
  'svchost.exe',
  'fontdrvhost.exe',
  'dwm.exe',
  'memory compression',
  'conhost.exe',
  'sihost.exe',
  'taskhostw.exe',
  'runtimebroker.exe',
  'dllhost.exe',
  'ctfmon.exe',
  'searchindexer.exe',
  'spoolsv.exe',
  'wudfhost.exe',
  'audiodg.exe',
  'vigilia.exe',
};

/// Процессы для выбора: без системных, по имени; одинаковые exe из одной папки — одной строкой.
List<WatchedProcess> pickableProcesses() {
  final seen = <String, WatchedProcess>{};
  for (final p in runningProcesses()) {
    if (_system.contains(p.name)) continue;
    final w = WatchedProcess(p.name, processImagePath(p.pid));
    seen.putIfAbsent(w.key, () => w);
  }
  return seen.values.toList()..sort((a, b) {
    final byName = a.name.compareTo(b.name);
    return byName != 0 ? byName : (a.path ?? '').compareTo(b.path ?? '');
  });
}

/// Какие из отслеживаемых программ сейчас запущены.
/// Сначала сравниваются имена (дёшево), пути запрашиваются только у совпавших по имени.
List<WatchedProcess> runningWatched(List<WatchedProcess> watched) {
  if (watched.isEmpty) return const [];
  final byName = <String, List<int>>{};
  for (final p in runningProcesses()) {
    (byName[p.name] ??= []).add(p.pid);
  }
  final paths = <int, String?>{};
  return [
    for (final w in watched)
      if (byName[w.name] case final pids?)
        if (w.path == null || pids.any((pid) => paths.putIfAbsent(pid, () => processImagePath(pid)) == w.path)) w,
  ];
}

/// Сетевой адаптер для выбора в режиме «загрузка».
typedef NetAdapter = ({String guid, String name, bool vpn, bool wireless});

/// Адаптеры для выбора: подключённые, без служебных. Виртуальные — только если через них
/// уже шёл трафик (VPN), иначе список забивают пустые «Подключения по локальной сети*».
List<NetAdapter> pickableAdapters() => [
  for (final i in networkInterfaces())
    if (i.up && (i.hardware || i.received > 0)) (guid: i.guid, name: i.alias, vpn: !i.hardware, wireless: i.wireless),
];

/// Счётчики принятых байт: выбранного адаптера или всех физических (null).
/// Трафик VPN проходит и через физический адаптер, поэтому в «все» VPN не входит — иначе посчитается дважды.
Map<String, int> receivedCounters(String? adapter) => {
  for (final i in networkInterfaces())
    if (adapter == null ? i.hardware : i.guid == adapter) i.guid: i.received,
};

/// Скорость по двум замерам. Считаются только адаптеры, которые есть в обоих:
/// подключившийся адаптер не даёт скачка, а сбросивший счётчик — отрицательной скорости.
double bytesPerSecond(Map<String, int> prev, Map<String, int> now, Duration dt) {
  if (dt <= Duration.zero) return 0;
  var delta = 0;
  now.forEach((k, v) {
    final p = prev[k];
    if (p != null && v > p) delta += v - p;
  });
  return delta * 1000 / dt.inMilliseconds;
}
