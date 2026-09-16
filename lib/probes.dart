import 'dart:io';

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

/// Процессы для выбора: без системных, по алфавиту.
List<String> pickableProcesses() => (runningProcessNames().difference(_system).toList()..sort());

bool isProcessRunning(String name) => runningProcessNames().contains(name.toLowerCase());

/// Всего принято байт по всем интерфейсам (`netstat -e`), null — не удалось.
Future<int?> receivedBytes() async {
  try {
    final r = await Process.run('netstat', ['-e']);
    return r.exitCode == 0 ? parseNetstatReceived(r.stdout as String) : null;
  } catch (_) {
    return null;
  }
}

/// Первая строка, которая заканчивается двумя числами, — «байты принято/отправлено».
/// Подпись строки зависит от языка Windows, поэтому смотрим только на числа.
int? parseNetstatReceived(String out) {
  for (final line in out.split('\n')) {
    final t = line.trim().split(RegExp(r'\s+'));
    if (t.length < 3) continue;
    final a = int.tryParse(t[t.length - 2]), b = int.tryParse(t.last);
    if (a != null && b != null) return a;
  }
  return null;
}

/// Скорость по двум отсчётам счётчика; счётчик мог переполниться (32 бита).
double bytesPerSecond(int prev, int now, Duration dt) {
  if (dt <= Duration.zero) return 0;
  var delta = now - prev;
  if (delta < 0) delta = prev < (1 << 32) ? now + (1 << 32) - prev : 0;
  return delta * 1000 / dt.inMilliseconds;
}
