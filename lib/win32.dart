// Тонкий слой над WinAPI через dart:ffi. Без Flutter-зависимостей,
// чтобы его можно было гонять обычным `dart run`.
import 'dart:ffi';

import 'package:ffi/ffi.dart';

final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _user32 = DynamicLibrary.open('user32.dll');
final _winmm = DynamicLibrary.open('winmm.dll');
final _powrprof = DynamicLibrary.open('powrprof.dll');

final _powerCreateRequest = _kernel32.lookupFunction<IntPtr Function(Pointer<Void>), int Function(Pointer<Void>)>(
  'PowerCreateRequest',
);
final _powerSetRequest = _kernel32.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>(
  'PowerSetRequest',
);
final _powerClearRequest = _kernel32.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>(
  'PowerClearRequest',
);
final _closeHandle = _kernel32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
final _playSound = _winmm
    .lookupFunction<Int32 Function(Pointer<Uint8>, IntPtr, Uint32), int Function(Pointer<Uint8>, int, int)>(
      'PlaySoundW',
    );
final _systemParametersInfo = _user32
    .lookupFunction<Int32 Function(Uint32, Uint32, Pointer<Void>, Uint32), int Function(int, int, Pointer<Void>, int)>(
      'SystemParametersInfoW',
    );
final _callNtPowerInformation = _powrprof
    .lookupFunction<
      Int32 Function(Int32, Pointer<Void>, Uint32, Pointer<Void>, Uint32),
      int Function(int, Pointer<Void>, int, Pointer<Void>, int)
    >('CallNtPowerInformation');

const _invalidHandle = -1;
const _requestDisplay = 0; // PowerRequestDisplayRequired
const _requestSystem = 1; // PowerRequestSystemRequired

const esSystemRequired = 0x1;
const esDisplayRequired = 0x2;

/// Один power request на всё время жизни процесса. Когда процесс
/// завершается, Windows снимает запрос сама.
class PowerRequest {
  int _handle = _invalidHandle;
  bool _system = false, _display = false;

  bool _ensureHandle() {
    if (_handle != _invalidHandle) return true;
    // REASON_CONTEXT (x64 = 32 байта): Version=0, Flags=SIMPLE_STRING(1), LPWSTR.
    final ctx = calloc<Uint8>(32);
    final reason = 'Vigilia: режим «не спать» включён'.toNativeUtf16();
    try {
      ctx.cast<Uint32>()[1] = 1;
      (ctx + 8).cast<Pointer<Utf16>>().value = reason;
      _handle = _powerCreateRequest(ctx.cast());
    } finally {
      calloc.free(reason);
      calloc.free(ctx);
    }
    return _handle != _invalidHandle;
  }

  bool _set(int type, bool on) => (on ? _powerSetRequest(_handle, type) : _powerClearRequest(_handle, type)) != 0;

  /// Приводит запрос к нужному состоянию. false — WinAPI отказал.
  bool apply({required bool system, required bool display}) {
    if (!system && !display && _handle == _invalidHandle) return true;
    if (!_ensureHandle()) return false;
    var ok = true;
    if (system != _system) {
      if (_set(_requestSystem, system)) {
        _system = system;
      } else {
        ok = false;
      }
    }
    if (display != _display) {
      if (_set(_requestDisplay, display)) {
        _display = display;
      } else {
        ok = false;
      }
    }
    return ok;
  }

  void dispose() {
    apply(system: false, display: false);
    if (_handle != _invalidHandle) _closeHandle(_handle);
    _handle = _invalidHandle;
  }
}

/// Флаги ES_* текущего состояния системы (CallNtPowerInformation/SystemExecutionState).
int systemExecutionState() {
  final out = calloc<Uint32>();
  try {
    return _callNtPowerInformation(16, nullptr, 0, out.cast(), 4) == 0 ? out.value : -1;
  } finally {
    calloc.free(out);
  }
}

/// SND_ASYNC | SND_NODEFAULT | SND_MEMORY (+ SND_LOOP). Буфер должен жить, пока звук играет.
void playWav(Pointer<Uint8> wav, {bool loop = false}) => _playSound(wav, 0, 0x1 | 0x2 | 0x4 | (loop ? 0x8 : 0));

/// Останавливает звук, запущенный [playWav].
void stopWav() => _playSound(nullptr, 0, 0);

/// false, если в Windows выключены анимации («Параметры → Специальные возможности → Эффекты анимации»).
bool systemAnimationsEnabled() {
  final v = calloc<Int32>();
  try {
    return _systemParametersInfo(0x1042, 0, v.cast(), 0) == 0 || v.value != 0;
  } finally {
    calloc.free(v);
  }
}

final _createSnapshot = _kernel32.lookupFunction<IntPtr Function(Uint32, Uint32), int Function(int, int)>(
  'CreateToolhelp32Snapshot',
);
final _process32First = _kernel32
    .lookupFunction<Int32 Function(IntPtr, Pointer<Uint8>), int Function(int, Pointer<Uint8>)>('Process32FirstW');
final _process32Next = _kernel32
    .lookupFunction<Int32 Function(IntPtr, Pointer<Uint8>), int Function(int, Pointer<Uint8>)>('Process32NextW');

/// Все запущенные процессы: имя exe (в нижнем регистре) и PID.
/// PROCESSENTRY32W на x64: 568 байт, th32ProcessID со смещения 8, szExeFile (WCHAR[260]) со смещения 44.
List<({String name, int pid})> runningProcesses() {
  const size = 568, pidAt = 8, nameAt = 44;
  final snap = _createSnapshot(0x2 /* TH32CS_SNAPPROCESS */, 0);
  if (snap == _invalidHandle) return [];
  final entry = calloc<Uint8>(size);
  final list = <({String name, int pid})>[];
  try {
    entry.cast<Uint32>().value = size;
    for (var ok = _process32First(snap, entry); ok != 0; ok = _process32Next(snap, entry)) {
      final name = (entry + nameAt).cast<Utf16>().toDartString(length: _wcslen(entry + nameAt, 260));
      list.add((name: name.toLowerCase(), pid: (entry + pidAt).cast<Uint32>().value));
    }
  } finally {
    calloc.free(entry);
    _closeHandle(snap);
  }
  return list;
}

Set<String> runningProcessNames() => {for (final p in runningProcesses()) p.name};

final _openProcess = _kernel32.lookupFunction<IntPtr Function(Uint32, Int32, Uint32), int Function(int, int, int)>(
  'OpenProcess',
);
final _queryImageName = _kernel32
    .lookupFunction<
      Int32 Function(IntPtr, Uint32, Pointer<Utf16>, Pointer<Uint32>),
      int Function(int, int, Pointer<Utf16>, Pointer<Uint32>)
    >('QueryFullProcessImageNameW');

/// Полный путь exe процесса (в нижнем регистре); null — нет доступа (системные и защищённые процессы).
String? processImagePath(int pid) {
  final h = _openProcess(0x1000 /* PROCESS_QUERY_LIMITED_INFORMATION */, 0, pid);
  if (h == 0) return null;
  const cap = 32768;
  final buf = calloc<Uint16>(cap);
  final len = calloc<Uint32>()..value = cap;
  try {
    if (_queryImageName(h, 0, buf.cast(), len) == 0) return null;
    return buf.cast<Utf16>().toDartString(length: len.value).toLowerCase();
  } finally {
    calloc.free(buf);
    calloc.free(len);
    _closeHandle(h);
  }
}

int _wcslen(Pointer<Uint8> p, int max) {
  final w = p.cast<Uint16>();
  var n = 0;
  while (n < max && w[n] != 0) {
    n++;
  }
  return n;
}

final class _Point extends Struct {
  @Int32()
  external int x;
  @Int32()
  external int y;
}

final _getCursorPos = _user32.lookupFunction<Int32 Function(Pointer<_Point>), int Function(Pointer<_Point>)>(
  'GetCursorPos',
);
final _windowFromPoint = _user32.lookupFunction<IntPtr Function(_Point), int Function(_Point)>('WindowFromPoint');
final _getAncestor = _user32.lookupFunction<IntPtr Function(IntPtr, Uint32), int Function(int, int)>('GetAncestor');
final _getWindowThreadProcessId = _user32
    .lookupFunction<Uint32 Function(IntPtr, Pointer<Uint32>), int Function(int, Pointer<Uint32>)>(
      'GetWindowThreadProcessId',
    );

/// Находится ли курсор над окном этого процесса.
/// Нужно, чтобы отличить настоящий уход курсора от ложного: при нажатии кнопки мыши
/// Flutter захватывает указатель, и Windows присылает «курсор ушёл», хотя он на месте.
bool cursorOverOwnWindow(int ownPid) {
  final p = calloc<_Point>();
  final owner = calloc<Uint32>();
  try {
    if (_getCursorPos(p) == 0) return false;
    final root = _getAncestor(_windowFromPoint(p.ref), 2 /* GA_ROOT */);
    if (root == 0) return false;
    _getWindowThreadProcessId(root, owner);
    return owner.value == ownPid;
  } finally {
    calloc.free(p);
    calloc.free(owner);
  }
}

final _iphlpapi = DynamicLibrary.open('iphlpapi.dll');
final _getIfTable2 = _iphlpapi
    .lookupFunction<Uint32 Function(Pointer<Pointer<Uint8>>), int Function(Pointer<Pointer<Uint8>>)>('GetIfTable2');
final _freeMibTable = _iphlpapi.lookupFunction<Void Function(Pointer<Uint8>), void Function(Pointer<Uint8>)>(
  'FreeMibTable',
);

/// Сетевой интерфейс Windows (строка MIB_IF_ROW2).
typedef NetInterface = ({String guid, String alias, bool hardware, bool up, bool wireless, int received});

/// Сетевые интерфейсы без служебных: фильтров драйверов (дублируют счётчики адаптера),
/// петли и туннелей. Счётчики 64-битные, переполнения нет.
///
/// MIB_IF_TABLE2 на x64: NumEntries (4 байта) + выравнивание, строки по 1352 байта с 8-го байта.
/// В строке: InterfaceGuid @12, Alias WCHAR[257] @28, Type @1128,
/// флаги @1152 (бит 0 — аппаратный, бит 1 — фильтр), OperStatus @1156, InOctets @1208.
/// Смещения сверены с Get-NetAdapterStatistics.
List<NetInterface> networkInterfaces() {
  const row = 1352;
  final table = calloc<Pointer<Uint8>>();
  final list = <NetInterface>[];
  try {
    if (_getIfTable2(table) != 0) return list;
    final t = table.value;
    try {
      final n = t.cast<Uint32>().value;
      for (var i = 0; i < n; i++) {
        final r = t + 8 + i * row;
        final type = (r + 1128).cast<Uint32>().value;
        final flags = (r + 1152).cast<Uint8>().value;
        if (flags & 0x2 != 0 || type == 24 /* loopback */ || type == 131 /* tunnel */ ) continue;
        list.add((
          guid: _guid(r + 12),
          alias: (r + 28).cast<Utf16>().toDartString(length: _wcslen(r + 28, 257)),
          hardware: flags & 0x1 != 0,
          up: (r + 1156).cast<Uint32>().value == 1,
          wireless: type == 71,
          received: (r + 1208).cast<Uint64>().value,
        ));
      }
    } finally {
      _freeMibTable(t);
    }
  } finally {
    calloc.free(table);
  }
  return list;
}

String _guid(Pointer<Uint8> p) => [for (var i = 0; i < 16; i++) p[i].toRadixString(16).padLeft(2, '0')].join();
