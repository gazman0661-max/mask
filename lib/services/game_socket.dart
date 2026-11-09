import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../diagnostics/app_log.dart';

/// Tek WebSocket bağlantısı (tüm ekranlar paylaşır). Cloudflare kotası için kurallar:
///  * Her (yeniden) bağlanma 1 istek sayılır; sunucu aynı kullanıcıya 60 sn'de 5 bağlantı hakkı verir.
///    Burada da aynı sınır var ([_throttle]); yeniden bağlanma 2-4-8-16 sn (sonra 30-60 sn) bekler.
///  * Uygulama içi (JSON) ping YOK: gelen uygulama mesajı kotadan sayılır. Bunun yerine PROTOKOL pingi var
///    ([pingEvery]): WebSocket kontrol çerçevesidir, Cloudflare'de istek/mesaj olarak faturalanmaz. Cevap gelmezse
///    dart:io soketi kapatır, [_lost] yeniden bağlanır; ölü (yarı açık) bağlantı kalmaz.
///  * Arka plandan dönüşte ([resume]) bağlantı [staleAfter]'dan uzun süre arkada kaldıysa yeniden bağlanılır
///    (NAT/Android soketi öldürmüş olabilir; 1 bağlantı = 1 istek). Kısa sürede ping zaten yakalar.
///  * `lobby` isteği en fazla 30 sn'de bir ([requestLobby]); sunucu lobiyi zaten kendisi yollar.
///  * Hamleler tur sonunda tek `batch` olarak gider ([sendBatch], en fazla 8 hamle).
///  * Sunucu 4000 (başka cihaz), 4001 (çok istek) ya da 4003 (hesap kapatıldı, [ban]) ile kapatırsa kendiliğinden yeniden bağlanılmaz.

enum SocketStatus { closed, connecting, open }

/// Sunucunun kabul ettiği oyun hamleleri (`shard.ts` MOVE_TYPES ile aynı).
const Set<String> kMoveTypes = {
  'draw', 'take', 'back', 'openSeries', 'openPairs', 'collect', 'lay', 'autolay', 'discard',
};

/// Tek `batch` mesajındaki en fazla hamle (`shard.ts` MAX_BATCH).
const int kMaxBatchOps = 8;

/// Hatalı/sırası gelmemiş hamle sunucuya yollanmaz: hatalı mesaj da kotadan sayılır.
class BatchException implements Exception {
  final String message;
  const BatchException(this.message);
  @override
  String toString() => message;
}

/// Hamle listesini ağa çıkmadan kontrol eder. Geçerliyse null, değilse sebebi döner.
///  * `draw` tek başına gider: çekilen taş gizli, sonraki hamleler taş görüldükten sonra yeni mesajla gelir.
///  * `take` (soldan al) ilk hamle olur; `take + discard` tek başına geçersiz (alınan taş kullanılmalı).
///  * `discard` her zaman son hamledir.
String? validateOps(List<Map<String, dynamic>> ops) {
  if (ops.isEmpty) return 'Boş hamle listesi.';
  if (ops.length > kMaxBatchOps) return 'Bir mesajda en fazla $kMaxBatchOps hamle olur.';
  for (var i = 0; i < ops.length; i++) {
    final t = ops[i]['t'];
    if (t is! String || !kMoveTypes.contains(t)) return 'Bilinmeyen hamle: $t';
    if (t == 'draw' && ops.length > 1) return '"draw" ayrı mesaj olarak gider (çekilen taş gizli).';
    if (t == 'take' && i != 0) return '"take" ilk hamle olmalı.';
    if (t == 'discard' && i != ops.length - 1) return '"discard" son hamle olmalı.';
  }
  if (ops.length == 2 && ops[0]['t'] == 'take' && ops[1]['t'] == 'discard') {
    return 'Soldan alınan taş kullanılmadan atılamaz (take + discard geçersiz).';
  }
  return null;
}

/// Bir turun hamlelerini sırayla biriktirir: `TurnBatch().take().openSeries(g).discard(id).build()`.
class TurnBatch {
  final List<Map<String, dynamic>> _ops = [];

  TurnBatch take() => _add({'t': 'take'});
  TurnBatch back() => _add({'t': 'back'});
  TurnBatch openSeries(List<List<int>> groups) => _add({'t': 'openSeries', 'groups': groups});
  TurnBatch openPairs(List<List<int>> groups) => _add({'t': 'openPairs', 'groups': groups});
  TurnBatch collect() => _add({'t': 'collect'});
  TurnBatch lay(int id, {int? meld, bool? front}) => _add({
        't': 'lay',
        'id': id,
        if (meld != null) 'meld': meld,
        if (front != null) 'front': front,
      });
  TurnBatch autolay() => _add({'t': 'autolay'});
  TurnBatch discard(int id) => _add({'t': 'discard', 'id': id});

  TurnBatch _add(Map<String, dynamic> op) {
    _ops.add(op);
    return this;
  }

  /// Geçerliyse hamle listesini, değilse [BatchException] döner.
  List<Map<String, dynamic>> build() {
    final err = validateOps(_ops);
    if (err != null) throw BatchException(err);
    return List.unmodifiable(_ops);
  }
}

typedef TokenProvider = Future<String> Function();

class GameSocket {
  /// `wss://okey101-server.<hesap>.workers.dev/ws` (token sorgusu eklenir).
  final String url;

  /// Her bağlanmada çağrılır: süresi dolan Supabase access_token yenilenebilsin.
  final TokenProvider token;

  /// Cihaz kimliği (isteğe bağlı): sunucu özetleyip hile/ban denetiminde kullanır (ham değer saklanmaz).
  final Future<String> Function()? device;
  final WebSocketChannel Function(Uri) _connector;

  GameSocket({
    required this.url,
    required this.token,
    this.device,
    WebSocketChannel Function(Uri)? connector,
  }) : _connector = connector ??
            ((u) => IOWebSocketChannel.connect(u, pingInterval: pingEvery, connectTimeout: const Duration(seconds: 12)));

  /// Protokol ping aralığı (ücretsiz kontrol çerçevesi). Cevapsızsa soket kapanır.
  static const Duration pingEvery = Duration(seconds: 20);

  /// Bu kadar süre arka planda kalan uygulama dönünce açık görünen bağlantıyı yeniler.
  static const Duration staleAfter = Duration(seconds: 45);

  /// Hesap/cihaz kapatılınca sunucunun yolladığı bilgi (`{perm, until, reason, device}`); yoksa null.
  /// Arayüz bunu dinleyip "hesabın kapatıldı" ekranını gösterir. Kapatma sürerken yeniden bağlanılmaz (4003).
  final ValueNotifier<Map<String, dynamic>?> ban = ValueNotifier<Map<String, dynamic>?>(null);

  static const List<int> _backoffSec = [2, 4, 8, 16, 30, 60, 60, 60, 60, 60];
  static const int _burst = 5; // sunucu: 60 sn'de 5 bağlantı
  static const Duration _window = Duration(seconds: 60);
  static const Duration _lobbyGap = Duration(seconds: 30);

  final _messages = StreamController<Map<String, dynamic>>.broadcast();
  final _statusCtl = StreamController<SocketStatus>.broadcast();
  final List<DateTime> _attempts = [];
  final math.Random _rnd = math.Random();

  WebSocketChannel? _ch;
  StreamSubscription<dynamic>? _sub;
  Timer? _retryTimer;
  SocketStatus _status = SocketStatus.closed;
  bool _wanted = false;
  bool _gaveUp = false;
  int _fails = 0;
  int _gen = 0; // eski bağlantının geç gelen olayları yok sayılsın
  DateTime? _lobbyAskedAt;

  /// Son gelen `lobby` mesajı ve zamanı (lobiye girince önce bu gösterilir).
  Map<String, dynamic>? lastLobby;
  DateTime? lastLobbyAt;

  /// Sunucudan gelen mesajlar. Ayrıca yapay olaylar: `{t:'_open'}`, `{t:'_closed', code:int?}`, `{t:'_gaveup'}`.
  Stream<Map<String, dynamic>> get messages => _messages.stream;
  Stream<SocketStatus> get status => _statusCtl.stream;
  SocketStatus get currentStatus => _status;
  bool get isOpen => _status == SocketStatus.open;

  /// Bağlanmak ister (zaten açık/bağlanıyorsa bir şey yapmaz).
  Future<void> connect() async {
    _wanted = true;
    _gaveUp = false;
    if (_status != SocketStatus.closed) return;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _open();
  }

  /// Açılana kadar bekler; [timeout] dolarsa [TimeoutException].
  Future<void> whenOpen([Duration timeout = const Duration(seconds: 12)]) async {
    if (isOpen) return;
    await connect();
    if (isOpen) return;
    await status.firstWhere((s) => s == SocketStatus.open).timeout(timeout);
  }

  DateTime? _pausedAt;

  /// Uygulama arka plana gidince çağır (dönüşte bağlantının bayatlığı buradan anlaşılır).
  void pause() => _pausedAt ??= DateTime.now();

  /// Uygulama arka plandan dönünce çağır.
  ///  * Kapalıysa hemen yeniden bağlanır.
  ///  * Açık görünüyor ama [staleAfter]'dan uzun süre arkadaydıysa bağlantıyı yenileyip yeniden bağlanır.
  /// (4000/4001/4003 ile kapatılmışsa ya da disconnect() çağrılmışsa bağlanmaz.)
  void resume() {
    final since = _pausedAt;
    _pausedAt = null;
    if (!_wanted) return;
    if (_status == SocketStatus.open) {
      if (since != null && DateTime.now().difference(since) > staleAfter) {
        Log.i('ws', 'uzun arka plan: bağlantı yenileniyor');
        _drop();
        _fails = 0;
        unawaited(_open());
      }
      return;
    }
    if (_status != SocketStatus.closed) return;
    _fails = 0;
    _gaveUp = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    unawaited(_open());
  }

  /// Açık bağlantıyı sessizce bırakır (yeniden bağlanma planlamaz); eski olaylar [_gen] ile yok sayılır.
  void _drop() {
    _gen++;
    _sub?.cancel();
    _sub = null;
    try {
      _ch?.sink.close(1000);
    } catch (_) {}
    _ch = null;
    _status = SocketStatus.closed;
    if (!_statusCtl.isClosed) _statusCtl.add(SocketStatus.closed);
  }

  /// Bilerek kapatır; yeniden bağlanma yok.
  void disconnect() {
    _wanted = false;
    _gen++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _sub?.cancel();
    _sub = null;
    try {
      _ch?.sink.close(1000);
    } catch (_) {}
    _ch = null;
    _setStatus(SocketStatus.closed);
  }

  /// Ham mesaj yollar. Bağlı değilse false.
  bool send(Map<String, dynamic> m) {
    final ch = _ch;
    if (_status != SocketStatus.open || ch == null) return false;
    try {
      ch.sink.add(jsonEncode(m));
      return true;
    } catch (e) {
      Log.w('ws', 'gönderilemedi: $e');
      return false;
    }
  }

  /// Turun hamlelerini TEK mesaj olarak yollar (1 hamle ise düz hamle mesajı).
  /// Hatalı liste için [BatchException] fırlatır ve hiçbir şey yollamaz.
  bool sendBatch(List<Map<String, dynamic>> ops) {
    final err = validateOps(ops);
    if (err != null) throw BatchException(err);
    return send(ops.length == 1 ? ops.first : {'t': 'batch', 'ops': ops});
  }

  /// `lobby` isteği: en fazla 30 sn'de bir. Sunucu değişiklikte lobiyi zaten yollar,
  /// bu yalnız lobiye geri dönüşte (masadayken değişiklik gelmedi) bir kez çağrılmalı.
  bool requestLobby() {
    final now = DateTime.now();
    final asked = _lobbyAskedAt;
    if (asked != null && now.difference(asked) < _lobbyGap) return false;
    if (!send({'t': 'lobby'})) return false;
    _lobbyAskedAt = now;
    return true;
  }

  Future<void> dispose() async {
    disconnect();
    await _messages.close();
    await _statusCtl.close();
  }

  // ------------------------------------------------------------------ iç işler

  void _setStatus(SocketStatus s) {
    if (_status == s) return;
    _status = s;
    if (!_statusCtl.isClosed) _statusCtl.add(s);
  }

  void _emit(Map<String, dynamic> m) {
    if (!_messages.isClosed) _messages.add(m);
  }

  /// 60 sn'de en fazla 5 bağlantı denemesi (sunucu 6.'yı 429 ile reddeder, o da istek sayılır).
  Future<void> _throttle() async {
    final now = DateTime.now();
    _attempts.removeWhere((t) => now.difference(t) >= _window);
    if (_attempts.length >= _burst) {
      final wait = _attempts.first.add(_window + const Duration(seconds: 1)).difference(now);
      if (!wait.isNegative) await Future<void>.delayed(wait);
    }
    _attempts.add(DateTime.now());
  }

  Future<void> _open() async {
    if (_status != SocketStatus.closed) return;
    _setStatus(SocketStatus.connecting);
    final gen = ++_gen;
    WebSocketChannel? pending; // el sıkışma tamamlanmadan hata olursa kapatılır
    try {
      await _throttle();
      if (gen != _gen || !_wanted) {
        if (gen == _gen) _setStatus(SocketStatus.closed);
        return;
      }
      final tok = await token();
      final base = Uri.parse(url);
      String? dev;
      try {
        dev = await device?.call();
      } catch (_) {
        dev = null; // cihaz kimliği alınamazsa yine bağlan
      }
      final uri = base.replace(queryParameters: {
        ...base.queryParameters,
        'token': tok,
        if (dev != null && dev.isNotEmpty) 'd': dev,
      });
      Log.i('ws', 'bağlanılıyor: ${base.host} (deneme ${_fails + 1})'); // token günlüğe YAZILMAZ
      final ch = _connector(uri);
      pending = ch;
      await ch.ready.timeout(const Duration(seconds: 12));
      if (gen != _gen || !_wanted) {
        try {
          ch.sink.close(1000);
        } catch (_) {}
        if (gen == _gen) _setStatus(SocketStatus.closed);
        return;
      }
      _ch = ch;
      _sub = ch.stream.listen(
        _onData,
        onError: (Object e) => _lost(gen, ch),
        onDone: () => _lost(gen, ch),
        cancelOnError: true,
      );
      _setStatus(SocketStatus.open);
      Log.i('ws', 'bağlantı açık');
      _emit({'t': '_open'});
    } catch (e) {
      try {
        pending?.sink.close(1000);
      } catch (_) {}
      if (gen != _gen) return;
      Log.w('ws', 'bağlanılamadı: $e');
      _setStatus(SocketStatus.closed);
      _emit({'t': '_closed', 'code': null});
      _scheduleRetry();
    }
  }

  void _onData(dynamic data) {
    _fails = 0; // sunucu konuştu: bağlantı sağlıklı
    Object? j;
    try {
      j = jsonDecode(data as String);
    } catch (_) {
      return;
    }
    if (j is! Map) return;
    final m = j.cast<String, dynamic>();
    if (m['t'] == 'lobby') {
      lastLobby = m;
      lastLobbyAt = DateTime.now();
    } else if (m['t'] == 'banned') {
      ban.value = m;
    }
    _emit(m);
  }

  void _lost(int gen, WebSocketChannel ch) {
    if (gen != _gen) return;
    final code = ch.closeCode;
    _sub?.cancel();
    _sub = null;
    _ch = null;
    _setStatus(SocketStatus.closed);
    Log.w('ws', 'bağlantı koptu (kod=$code)');
    _emit({'t': '_closed', 'code': code});
    if (code == 4000 || code == 4001 || code == 4003) {
      _wanted = false; // başka cihaz girdi / çok istek / hesap kapatıldı: kendiliğinden yeniden bağlanma
      return;
    }
    if (_wanted) _scheduleRetry();
  }

  void _scheduleRetry() {
    if (!_wanted) return;
    _fails++;
    if (_fails > _backoffSec.length) {
      _gaveUp = true; // çok denendi: uygulama öne gelince resume() yeniden dener
      Log.w('ws', 'yeniden bağlanma bırakıldı (resume bekleniyor)');
      _emit({'t': '_gaveup'});
      return;
    }
    final base = _backoffSec[_fails - 1] * 1000;
    final ms = (base * (0.8 + 0.4 * _rnd.nextDouble())).round(); // ±%20: sunucu açılınca herkes aynı anda gelmesin
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(milliseconds: ms), () {
      _retryTimer = null;
      if (_wanted && _status == SocketStatus.closed) unawaited(_open());
    });
  }

  /// Test/tanı için.
  bool get gaveUp => _gaveUp;
}
