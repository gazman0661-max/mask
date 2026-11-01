import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/tile.dart';
import '../services/telemetry.dart';

enum LogLevel { debug, info, warn, error }

/// Günlükte taşı kısa yazar: 7k#23 = 7 siyah, id 23. (s=sarı b=mavi k=siyah r=kırmızı)
String logTile(Tile? t) {
  if (t == null) return '-';
  if (t.isFakeJoker) return 'sahteOkey#${t.id}';
  const c = {
    TileColor.yellow: 's',
    TileColor.blue: 'b',
    TileColor.black: 'k',
    TileColor.red: 'r',
  };
  return '${t.number}${c[t.color]}#${t.id}';
}

class LogEntry {
  final DateTime time;
  final LogLevel level;
  final String tag;
  final String message;
  final String? stack;
  const LogEntry(this.time, this.level, this.tag, this.message, this.stack);

  String get levelLabel => switch (level) {
        LogLevel.debug => 'DEBUG',
        LogLevel.info => 'INFO',
        LogLevel.warn => 'WARN',
        LogLevel.error => 'ERROR',
      };

  static String _two(int n) => n.toString().padLeft(2, '0');

  String get clock =>
      '${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}.${time.millisecond.toString().padLeft(3, '0')}';

  String format() {
    final b = StringBuffer('$clock $levelLabel [$tag] $message');
    final s = stack;
    if (s != null && s.trim().isNotEmpty) {
      b.write('\n');
      b.write(s.trimRight().split('\n').map((l) => '    $l').join('\n'));
    }
    return b.toString();
  }
}

/// Uygulama geneli tanı günlüğü. Bellekte halka tampon + dosyaya yazım
/// (önceki oturum kaydı için). Kullanım: Log.i('etiket', 'mesaj');
class Log {
  Log._();

  static const int _max = 4000;
  static final List<LogEntry> _entries = [];
  static final List<LogEntry> _errors = [];

  /// Günlük değiştikçe (en fazla ~0.7 sn'de bir) artar; ekran bunu dinler.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static final DateTime startedAt = DateTime.now();

  /// Bir önceki oturumun kaydı (uygulama açılışında dosyadan okunur).
  static String previous = '';

  /// Ekran/cihaz bilgisi (ResponsiveShell günceller); dışa aktarımın başına eklenir.
  static String deviceInfo = '';

  static List<LogEntry> get entries => _entries;
  static List<LogEntry> get errors => _errors;

  static File? _file;
  static final StringBuffer _pending = StringBuffer();
  static Timer? _flushTimer, _notifyTimer;
  static Future<Object?> _io = Future<Object?>.value();

  static String? _lastKey;
  static DateTime _lastAt = DateTime(2000);
  static int _suppressed = 0;

  static Future<void> init() async {
    if (kIsWeb) return;
    try {
      final f = File('${Directory.systemTemp.path}/okey101_oturum.log');
      if (await f.exists()) previous = await f.readAsString();
      await f.writeAsString('');
      _file = f;
    } catch (e) {
      debugPrint('Log.init hata: $e');
    }
  }

  static void d(String tag, String m) => _add(LogLevel.debug, tag, m);
  static void i(String tag, String m) => _add(LogLevel.info, tag, m);
  static void w(String tag, String m) => _add(LogLevel.warn, tag, m);
  static void e(String tag, String m, [Object? error, StackTrace? stack]) {
    _add(LogLevel.error, tag, error == null ? m : '$m | $error', stack);
    // Çökme/hata raporu (Firebase açıksa). Yakalanmayan platform/zone hataları ÖLÜMCÜL sayılır. Hiçbir zaman fırlatmaz.
    Telemetry.error(error ?? '[$tag] $m', stack, fatal: tag == 'platform' || tag == 'zone');
  }

  static void _add(LogLevel lv, String tag, String m, [StackTrace? st]) {
    final now = DateTime.now();
    final key = '${lv.index}|$tag|$m';
    // Aynı mesaj art arda gelirse (ör. her karede tekrarlanan hata) bastır.
    if (key == _lastKey && now.difference(_lastAt).inMilliseconds < 1500) {
      _suppressed++;
      _lastAt = now;
      return;
    }
    if (_suppressed > 0) {
      _push(LogEntry(now, LogLevel.debug, 'log',
          '(yukarıdaki mesaj $_suppressed kez daha tekrarlandı)', null));
      _suppressed = 0;
    }
    _lastKey = key;
    _lastAt = now;
    _push(LogEntry(now, lv, tag, m, st?.toString()));
  }

  static void _push(LogEntry e) {
    _entries.add(e);
    if (_entries.length > _max + 300) _entries.removeRange(0, 300);
    if (e.level == LogLevel.error) {
      _errors.add(e);
      if (_errors.length > 500) _errors.removeAt(0);
    }
    final line = e.format();
    if (kDebugMode) debugPrint(line);
    // Dosya yoksa (web/FlutLab) tamponda biriktirme: sınırsız bellek büyürdü.
    if (_file != null) _pending.writeln(line);
    if (e.level == LogLevel.error) {
      flush(); // çökme öncesi son hatayı kaybetme
    } else {
      _flushTimer ??= Timer(const Duration(seconds: 2), flush);
    }
    _notifyTimer ??= Timer(const Duration(milliseconds: 700), () {
      _notifyTimer = null;
      revision.value++;
    });
  }

  static void flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    final f = _file;
    if (f == null || _pending.isEmpty) return;
    final text = _pending.toString();
    _pending.clear();
    _io = _io
        .then<Object?>((_) => f.writeAsString(text, mode: FileMode.append))
        .catchError((Object err) {
      debugPrint('günlük yazılamadı: $err');
      return null;
    });
  }

  /// Bu oturumun ve hata listesini siler.
  static void clearSession() {
    _entries.clear();
    _errors.clear();
    _pending.clear();
    final f = _file;
    if (f != null) {
      _io = _io.then<Object?>((_) => f.writeAsString('')).catchError((Object _) => null);
    }
    revision.value++;
  }

  static void clearPrevious() {
    previous = '';
    revision.value++;
  }

  // ---------------------------------------------------------- dışa aktarım

  static String header() {
    final mode = kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug');
    return '101 Okey tanı kaydı\n'
        'Oturum başlangıcı: ${startedAt.toIso8601String()}\n'
        'Dışa aktarma: ${DateTime.now().toIso8601String()}\n'
        'Platform: $defaultTargetPlatform | mod: $mode\n'
        '${deviceInfo.isEmpty ? '' : '$deviceInfo\n'}'
        'Kayıt: ${_entries.length} satır, ${_errors.length} hata, '
        '${_entries.where((e) => e.level == LogLevel.warn).length} uyarı\n'
        '${'=' * 44}\n';
  }

  static String sessionText() =>
      header() + _entries.map((e) => e.format()).join('\n');

  static String errorsText() =>
      header() + _errors.map((e) => e.format()).join('\n');

  static String previousText() =>
      previous.isEmpty ? 'Önceki oturum kaydı yok.' : previous;
}
