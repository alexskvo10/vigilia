import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Версия приложения (совпадает с pubspec.yaml и installer/vigilia.iss).
const appVersion = '1.2.0';

const repo = 'alexskvo10/vigilia';
const releasesPage = 'https://github.com/$repo/releases/latest';
final _latestApi = Uri.parse('https://api.github.com/repos/$repo/releases/latest');

/// Опубликованная версия с установщиком.
class Release {
  const Release({required this.version, required this.url, required this.size, this.sha256});

  final String version;
  final Uri url;
  final int size;
  final String? sha256; // GitHub отдаёт хеш файла в поле digest

  /// Ответ `releases/latest`; null — черновик, пре-релиз или нет установщика.
  static Release? parse(Object? json) {
    if (json is! Map || json['draft'] == true || json['prerelease'] == true) return null;
    final tag = json['tag_name'];
    if (tag is! String) return null;
    final version = tag.startsWith('v') ? tag.substring(1) : tag;
    if (_parts(version) == null) return null;
    for (final a in json['assets'] is List ? json['assets'] as List : const []) {
      if (a is! Map) continue;
      final name = a['name'], url = a['browser_download_url'], size = a['size'], digest = a['digest'];
      if (name is! String || url is! String || size is! int) continue;
      if (!RegExp(r'^Vigilia-.+-setup\.exe$', caseSensitive: false).hasMatch(name)) continue;
      final uri = Uri.tryParse(url);
      if (uri == null || uri.scheme != 'https') continue;
      final hash = digest is String && digest.startsWith('sha256:') ? digest.substring(7).toLowerCase() : null;
      return Release(version: version, url: uri, size: size, sha256: hash);
    }
    return null;
  }
}

List<int>? _parts(String v) {
  final p = v.split('.').map(int.tryParse).toList();
  return p.isEmpty || p.contains(null) ? null : p.cast<int>();
}

/// Сравнение версий вида 1.2.10; некорректная строка считается самой старой.
int compareVersions(String a, String b) {
  final pa = _parts(a), pb = _parts(b);
  if (pa == null || pb == null) return pa == null ? (pb == null ? 0 : -1) : 1;
  for (var i = 0; i < pa.length || i < pb.length; i++) {
    final d = (i < pa.length ? pa[i] : 0) - (i < pb.length ? pb[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

enum UpdateStatus { idle, checking, upToDate, available, downloading, installing, failed }

/// Проверка обновлений на GitHub Releases, скачивание и запуск установщика.
///
/// Установщик запускается тихо с ключом /UPDATE: он ждёт, пока Vigilia закроется,
/// ставит новую версию в ту же папку и запускает её. Портативная копия (без деинсталлятора
/// рядом с exe) не обновляется сама — открывается страница релиза.
class Updater extends ChangeNotifier {
  Updater({
    required this.current,
    Future<Object?> Function(Uri url)? fetchJson,
    Future<File> Function(Release r, void Function(double progress) onProgress)? download,
    Future<String?> Function(File f)? sha256,
    Future<void> Function(File installer)? runInstaller,
    Future<void> Function(String url)? openPage,
    bool? installed,
    DateTime Function()? now,
  }) : _fetchJson = fetchJson ?? _httpJson,
       _download = download ?? _httpDownload,
       _sha256 = sha256 ?? _certutilSha256,
       _runInstaller = runInstaller ?? _startInstaller,
       _openPage = openPage ?? _startBrowser,
       installed = installed ?? _isInstalled(),
       _now = now ?? DateTime.now;

  final String current;
  final bool installed;
  final Future<Object?> Function(Uri) _fetchJson;
  final Future<File> Function(Release, void Function(double)) _download;
  final Future<String?> Function(File) _sha256;
  final Future<void> Function(File) _runInstaller;
  final Future<void> Function(String) _openPage;
  final DateTime Function() _now;

  /// Приложение закрывается, чтобы установщик мог заменить файлы.
  VoidCallback? onQuit;

  UpdateStatus _status = UpdateStatus.idle;
  Release? _latest;
  double _progress = 0;
  DateTime? _checkedAt;
  bool _disposed = false;

  UpdateStatus get status => _status;
  Release? get latest => _latest;
  double get progress => _progress;

  /// Найдена версия новее текущей (кнопка обновления остаётся и после неудачной попытки).
  bool get hasUpdate => _latest != null && compareVersions(_latest!.version, current) > 0;

  bool get busy =>
      _status == UpdateStatus.checking || _status == UpdateStatus.downloading || _status == UpdateStatus.installing;

  void _set(UpdateStatus s) {
    _status = s;
    if (!_disposed) notifyListeners();
  }

  /// [ifOlderThan] — не ходить в сеть, если проверяли недавно.
  Future<void> check({Duration? ifOlderThan}) async {
    if (busy || hasUpdate) return;
    final last = _checkedAt;
    if (ifOlderThan != null && last != null && _now().difference(last) < ifOlderThan) return;
    _set(UpdateStatus.checking);
    try {
      final r = Release.parse(await _fetchJson(_latestApi));
      _checkedAt = _now();
      _latest = r;
      _set(r != null && compareVersions(r.version, current) > 0 ? UpdateStatus.available : UpdateStatus.upToDate);
    } catch (e) {
      debugPrint('update check: $e');
      _set(UpdateStatus.failed);
    }
  }

  /// Скачать и поставить найденную версию (вызывается после удержания кнопки).
  Future<void> update() async {
    final r = _latest;
    if (r == null || busy) return;
    if (!installed) {
      await _openPage(releasesPage);
      return;
    }
    _progress = 0;
    _set(UpdateStatus.downloading);
    try {
      final file = await _download(r, (p) {
        _progress = p.clamp(0.0, 1.0);
        if (!_disposed) notifyListeners();
      });
      if (await file.length() != r.size) throw const FormatException('размер не совпал');
      if (r.sha256 != null && await _sha256(file) != r.sha256) {
        await file.delete();
        throw const FormatException('хеш не совпал');
      }
      _set(UpdateStatus.installing);
      await _runInstaller(file);
      onQuit?.call();
    } catch (e) {
      debugPrint('update: $e');
      _set(UpdateStatus.failed);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

// ---------- настоящие реализации ----------

HttpClient _client() => HttpClient()
  ..connectionTimeout = const Duration(seconds: 15)
  ..userAgent = 'Vigilia-updater';

Future<Object?> _httpJson(Uri url) async {
  final client = _client();
  try {
    final req = await client.getUrl(url);
    req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    final res = await req.close().timeout(const Duration(seconds: 20));
    if (res.statusCode == 404) return null; // релизов ещё нет
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}', uri: url);
    return jsonDecode(await res.transform(utf8.decoder).join());
  } finally {
    client.close();
  }
}

Future<File> _httpDownload(Release r, void Function(double) onProgress) async {
  final dir = Directory('${Directory.systemTemp.path}\\Vigilia');
  await dir.create(recursive: true);
  final file = File('${dir.path}\\Vigilia-${r.version}-setup.exe');
  final part = File('${file.path}.part');
  final client = _client();
  try {
    final res = await (await client.getUrl(r.url)).close(); // редирект на хранилище GitHub — автоматически
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}', uri: r.url);
    final sink = part.openWrite();
    var got = 0;
    try {
      await for (final chunk in res.timeout(const Duration(seconds: 30))) {
        sink.add(chunk);
        got += chunk.length;
        onProgress(r.size > 0 ? got / r.size : 0);
      }
    } finally {
      await sink.close();
    }
    if (await file.exists()) await file.delete();
    return part.rename(file.path);
  } finally {
    client.close();
  }
}

/// SHA-256 средствами Windows (certutil есть в любой системе).
Future<String?> _certutilSha256(File f) async {
  final r = await Process.run('certutil', ['-hashfile', f.path, 'SHA256']);
  if (r.exitCode != 0) return null;
  return parseCertutilHash(r.stdout as String);
}

/// Вторая строка вывода certutil — хеш (в старых Windows с пробелами между байтами).
String? parseCertutilHash(String out) {
  for (final line in out.split('\n')) {
    final hex = line.trim().replaceAll(' ', '').toLowerCase();
    if (RegExp(r'^[0-9a-f]{64}$').hasMatch(hex)) return hex;
  }
  return null;
}

Future<void> _startInstaller(File installer) async {
  await Process.start(installer.path, [
    '/SILENT',
    '/SUPPRESSMSGBOXES',
    '/NORESTART',
    '/UPDATE',
  ], mode: ProcessStartMode.detached);
}

Future<void> _startBrowser(String url) async {
  await Process.start('rundll32', ['url.dll,FileProtocolHandler', url], mode: ProcessStartMode.detached);
}

/// Установлена ли Vigilia установщиком: рядом с exe лежит деинсталлятор Inno Setup.
bool _isInstalled() {
  final dir = File(Platform.resolvedExecutable).parent.path;
  return File('$dir\\unins000.exe').existsSync();
}
