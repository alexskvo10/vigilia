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

/// SND_ASYNC | SND_NODEFAULT | SND_MEMORY. Буфер должен жить, пока звук играет.
void playWav(Pointer<Uint8> wav) => _playSound(wav, 0, 0x1 | 0x2 | 0x4);

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

/// Имена исполняемых файлов всех запущенных процессов (в нижнем регистре).
/// PROCESSENTRY32W на x64: 568 байт, szExeFile (WCHAR[260]) со смещения 44.
Set<String> runningProcessNames() {
  const size = 568, nameAt = 44;
  final snap = _createSnapshot(0x2 /* TH32CS_SNAPPROCESS */, 0);
  if (snap == _invalidHandle) return {};
  final entry = calloc<Uint8>(size);
  final names = <String>{};
  try {
    entry.cast<Uint32>().value = size;
    for (var ok = _process32First(snap, entry); ok != 0; ok = _process32Next(snap, entry)) {
      names.add((entry + nameAt).cast<Utf16>().toDartString(length: _wcslen(entry + nameAt, 260)).toLowerCase());
    }
  } finally {
    calloc.free(entry);
    _closeHandle(snap);
  }
  return names;
}

int _wcslen(Pointer<Uint8> p, int max) {
  final w = p.cast<Uint16>();
  var n = 0;
  while (n < max && w[n] != 0) {
    n++;
  }
  return n;
}
