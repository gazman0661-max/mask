import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import '../diagnostics/app_log.dart';
import '../models/goals.dart';
import '../models/player.dart';
import '../models/quick_chat.dart';
import '../models/rewards.dart';
import '../models/table_models.dart';
import '../models/tile.dart';
import 'game_service.dart';
import 'game_socket.dart';

/// Sunucu hata kodları -> kullanıcıya gösterilen Türkçe metin.
/// Kodda olmayan metin (ör. 'Sıra sende değil.') olduğu gibi gösterilir.
const Map<String, String> kServerErrors = {
  'yetersiz_bilet': 'Biletin yok. Reklam izleyerek ya da günlük biletinle devam edebilirsin.',
  'seviye_odul_yok': 'Alınacak seviye hediyesi yok.',
  'yetersiz_cip': 'Çipin bu masa için yetmiyor.',
  'masa_dolu': 'Masa dolu.',
  'masalar_dolu': 'Şu an yeni masa kurulamıyor, biraz sonra dene.',
  'masa_yok': 'Masa artık yok.',
  'zaten_masada': 'Zaten bir masadasın.',
  'zaten_oynadi': 'Bu maça zaten girdin, başka koltuğa dönemezsin.',
  'katilim_hatasi': 'Masaya katılınamadı.',
  'sunucu_hatasi': 'Sunucu hatası oluştu. Biletin düştüyse mesaj kutunda iade bekler.',
  'gecersiz_el_sayisi': 'Geçersiz el sayısı.',
  'bakim': 'Bakım var, yeni masa kurulamıyor. Biraz sonra tekrar dene.',
  'bugun_alindi': 'Bugünün ödülünü zaten aldın. Yarın tekrar gel!',
  'reklam_bekle': 'Yeni reklam henüz hazır değil.',
  'gunluk_reklam_siniri': 'Bugünlük reklam bileti sınırına ulaştın. Yarın tekrar dene ya da günlük biletini al.',
  'giris_gerekli': 'Oturum süresi doldu, uygulamayı yeniden aç.',
  'gorev_bitmedi': 'Bu görev henüz tamamlanmadı.',
  'gorev_alindi': 'Bu görevin ödülünü zaten aldın.',
  'gecersiz_gorev': 'Geçersiz görev.',
  'basarim_bitmedi': 'Bu başarım henüz tamamlanmadı.',
  'basarim_alindi': 'Bu başarımın ödülünü zaten aldın.',
  'once_onceki_kademe': 'Önce bir önceki kademenin ödülünü al.',
  'gecersiz_basarim': 'Geçersiz başarım.',
  'kota_dolu': "Sunucu bugün çok yoğun, yeni masalar 03:00'te yeniden açılır.",
};

/// Gerçek backend: Cloudflare WebSocket (oyun/lobi) + Supabase REST (profil/çip).
///
/// KAPSAM: lobi listesi, masa kurma, masaya oturma/kalkma, profil ve çip, maç. Maç sunucuda oynanır:
/// `state` mesajları [matchEvents] ile ekrana akar, hamleler [sendMatch] ile gider (cihazda oyun motoru/bot yok).
class CloudflareGameService implements GameService {
  final GameSocket socket;

  /// https://xxxx.supabase.co
  final String supabaseUrl;

  /// Herkese açık anon anahtarı (service_role ASLA).
  final String anonKey;

  /// Giriş yapmış oyuncunun Supabase access_token'ı (RLS: yalnız kendi profilini okur).
  final Future<String> Function() accessToken;

  final http.Client _http;
  late final StreamSubscription<Map<String, dynamic>> _sub;
  _Lifecycle? _lifecycle;

  CloudflareGameService({
    required this.socket,
    required this.supabaseUrl,
    required this.anonKey,
    required this.accessToken,
    http.Client? client,
  }) : _http = client ?? http.Client() {
    _sub = socket.messages.listen(_onMessage);
  }

  // Masada mıyız? (lobi mesajları masadayken gelmez: dönüşte lobiyi bir kez tazeleriz)
  bool _inTable = false;
  String? _seatedId;
  Map<String, dynamic>? _latest; // masanın son 'table'/'state' mesajı
  final Map<String, TableSettings> _known = {}; // lobiden/kurulumdan bilinen masa ayarları
  String? _uid;
  int _chips = 0;

  static const _lobbyStale = Duration(seconds: 30);

  /// Uygulama arka plandan dönünce bağlantıyı canlandırır. main()'de bir kez çağır.
  void attachLifecycle() {
    _lifecycle ??= _Lifecycle(socket.resume, socket.pause);
    WidgetsBinding.instance.addObserver(_lifecycle!);
  }

  Future<void> dispose() async {
    final l = _lifecycle;
    if (l != null) WidgetsBinding.instance.removeObserver(l);
    await _sub.cancel();
    await socket.dispose();
    _http.close();
  }

  void _onMessage(Map<String, dynamic> m) {
    switch (m['t']) {
      case 'table':
      case 'state':
        _latest = m;
        break;
      case 'final':
        // Maç bitti ama masa AÇIK kalır (rövanş): koltuğum durur, "masada kal" ya da "kalk" derim.
        _latest = null;
        break;
      case 'left': // süre doldu / bilet yok: koltuk bırakıldı
        _inTable = false;
        _seatedId = null;
        _latest = null;
        break;
    }
  }

  // ------------------------------------------------------------------ GameService

  /// Sunucudan gelen `{t:'emo', s, k}`: s = gönderenin bana göre koltuğu (1 sağ, 2 karşı, 3 sol), k = mesaj numarası.
  @override
  Stream<ChatEvent> get chatEvents => socket.messages
      .where((m) => m['t'] == 'emo' && m['s'] is int && m['k'] is int && (m['s'] as int) >= 1 && (m['s'] as int) <= 3)
      .map((m) => ChatEvent(m['s'] as int, m['k'] as int));

  /// Yalnız numara gider (küçük, serbest yazı yok). Bağlantı yoksa sessizce düşer.
  @override
  void sendChat(int id) {
    if (!_inTable) return;
    socket.send({'t': 'emo', 'k': id});
  }

  /// `table`/`state` mesajındaki `table.away` / `table.afk` (sunucu koltuk sırası) bana göre [Seat] sırasına çevrilir.
  @override
  Stream<Presence> get presence => socket.messages
      .where((m) => (m['t'] == 'table' || m['t'] == 'state') && m['table'] is Map)
      .map(_presenceOf);

  Presence _presenceOf(Map<String, dynamic> m) {
    final t = (m['table'] as Map).cast<String, dynamic>();
    final me = m['me'] is num ? (m['me'] as num).toInt() : 0;
    List<bool> rel(Object? raw) {
      final l = raw is List ? raw : const <Object?>[];
      return [
        for (var r = 0; r < 4; r++) ((me + r) % 4) < l.length && l[(me + r) % 4] == true,
      ];
    }

    return Presence(away: rel(t['away']), afk: rel(t['afk']));
  }

  @override
  Stream<bool> get connection => socket.status.map((s) => s == SocketStatus.open);

  @override
  bool get isConnected => socket.isOpen;

  /// "OYUNA DÖN": yalnız `{t:'here'}` gider. Masada değilsek ya da bağlantı yoksa sessizce düşer.
  @override
  void imHere() {
    if (!_inTable) return;
    socket.send({'t': 'here'});
  }

  /// Lobi sunucu tarafından değişince tetiklenir (giden mesaj ücretsiz): ekran kendi
  /// zamanlayıcısıyla yenilemek zorunda değil, 'lobby' isteği atmak da gerekmez.
  @override
  Stream<void>? get tablesChanged =>
      socket.messages.where((m) => m['t'] == 'lobby').map<void>((_) {});

  /// Kota %75'e ulaşınca sunucu yeni masa kurmayı/katılmayı kapatır (lobi mesajında closed:true).
  bool get quotaClosed => socket.lastLobby?['closed'] == true;

  /// Bu saatin masa tavanı doldu: yeni masa kurulamaz, var olan masalara katılınabilir (lobi mesajında full:true).
  bool get tablesFull => socket.lastLobby?['full'] == true;

  @override
  String? get lobbyNotice {
    final n = socket.lastLobby?['notice'];
    if (n is String && n.trim().isNotEmpty) return n.trim(); // yöneticinin duyurusu en önde
    if (socket.lastLobby?['open'] == false) return 'Bakım var, yeni masa kurulamıyor. Biraz sonra tekrar dene.';
    if (quotaClosed) return "Sunucu bugün çok yoğun. Yeni masalar 03:00'te yeniden açılır.";
    if (tablesFull) return 'Şu an masa kapasitesi dolu. Yeni masa kurulamıyor, birazdan tekrar dene ya da var olan bir masaya otur.';
    return null;
  }

  @override
  Future<Player> fetchMyProfile() async {
    final tok = await accessToken();
    _uid = _uidFromJwt(tok);
    final r = await _http.get(
      Uri.parse('$supabaseUrl/rest/v1/profiles?select=id,name,chips,avatar&limit=1'),
      headers: {'apikey': anonKey, 'Authorization': 'Bearer $tok'},
    );
    if (r.statusCode != 200) {
      throw const JoinException('Profil alınamadı. Bağlantını kontrol et.');
    }
    final list = jsonDecode(r.body) as List<dynamic>;
    if (list.isEmpty) throw const JoinException('Profil bulunamadı.');
    final j = list.first as Map<String, dynamic>;
    _chips = (j['chips'] as num).toInt();
    return Player(
        id: j['id'] as String,
        name: (j['name'] ?? 'Oyuncu') as String,
        chipCount: _chips,
        avatar: (j['avatar'] as num?)?.toInt());
  }

  // ---- günlük ödül / reklam çipi: Supabase RPC (migration-006.sql). Çip eklemesi sunucuda atomik yapılır.
  Future<dynamic> _rpcAny(String fn, [Map<String, dynamic>? body]) async {
    final tok = await accessToken();
    final r = await _http.post(Uri.parse('$supabaseUrl/rest/v1/rpc/$fn'),
        headers: {'apikey': anonKey, 'Authorization': 'Bearer $tok', 'Content-Type': 'application/json'},
        body: jsonEncode(body ?? <String, dynamic>{}));
    if (r.statusCode != 200) {
      var code = '';
      try {
        code = ((jsonDecode(r.body) as Map)['message'] ?? '').toString();
      } catch (_) {}
      throw JoinException(kServerErrors[code] ?? 'İşlem yapılamadı (${r.statusCode}). Tekrar dene.');
    }
    return jsonDecode(r.body);
  }

  Future<Map<String, dynamic>> _rpc(String fn, [Map<String, dynamic>? body]) async =>
      (await _rpcAny(fn, body) as Map).cast<String, dynamic>();

  @override
  Future<DailyStatus> fetchDailyStatus() async => DailyStatus.fromJson(await _rpc('daily_status'));

  @override
  Future<DailyClaim> claimDaily({bool doubled = false}) async {
    final c = DailyClaim.fromJson(await _rpc('claim_daily', {'p_double': doubled}));
    _chips = c.chips;
    return c;
  }

  @override
  Future<AdStatus> fetchAdStatus() async => AdStatus.fromJson(await _rpc('ad_status'));

  @override
  Future<AdStatus> claimAdChips() async {
    final j = await _rpc('claim_ad_chips');
    if (j['chips'] is num) _chips = (j['chips'] as num).toInt();
    return AdStatus.fromJson(j);
  }

  // ---- bilet sistemi (migration-008.sql): bakiye, günlük bilet, reklam bileti
  @override
  Future<TicketStatus> fetchTicketStatus() async => TicketStatus.fromJson(await _rpc('ticket_status'));

  @override
  Future<TicketClaim> claimDailyTickets({bool doubled = false}) async =>
      TicketClaim.fromJson(await _rpc('claim_daily_tickets', {'p_double': doubled}));

  @override
  Future<TicketClaim> claimAdTicket() async => TicketClaim.fromJson(await _rpc('claim_ad_ticket'));

  @override
  Future<TicketClaim> claimTableAdTicket() async => TicketClaim.fromJson(await _rpc('claim_table_ad_ticket'));

  // ---- günlük görevler / başarımlar / haftalık lig (migration-015.sql, 008'deki league_top)
  @override
  Future<TasksStatus> fetchTasks() async => TasksStatus.fromJson(await _rpc('tasks_status'));

  @override
  Future<GoalClaim> claimTask(String taskId) async =>
      GoalClaim.fromJson(await _rpc('claim_task', {'p_task': taskId}));

  @override
  Future<AchStatus> fetchAchievements() async => AchStatus.fromJson(await _rpc('ach_status'));

  @override
  Future<GoalClaim> claimAchievement(String id, int tier) async =>
      GoalClaim.fromJson(await _rpc('claim_ach', {'p_id': id, 'p_tier': tier}));

  @override
  Future<List<LeagueRow>> fetchLeague({int limit = 50}) async {
    final raw = await _rpcAny('league_top', {'p_limit': limit});
    return [
      for (final e in (raw as List)) LeagueRow.fromJson((e as Map).cast<String, dynamic>()),
    ];
  }

  @override
  String? get myUserId => _uid;

  @override
  Future<LevelClaim> claimLevelRewards() async => LevelClaim.fromJson(await _rpc('claim_level_rewards'));

  @override
  Future<List<TableInfo>> fetchTables() async {
    await _ensureOpen();
    final last = socket.lastLobbyAt;
    if (socket.lastLobby == null) {
      // İlk bağlantı: sunucu bağlanır bağlanmaz lobiyi kendisi yollar, istek atma.
      await _lobbyAfter(() => true);
    } else if (_inTable || last == null || DateTime.now().difference(last) > _lobbyStale) {
      // Masadan dönüş / uzun süre sessizlik: bir kez iste (soket 30 sn'de birden fazlasına izin vermez).
      await _lobbyAfter(socket.requestLobby);
    }
    return _mapLobby(socket.lastLobby);
  }

  @override
  Future<TableInfo> createTable({
    required String name,
    required TableSettings settings,
  }) async {
    final m = await _create(name, settings);
    return _tableInfo(m, settings);
  }

  @override
  Future<TableSnapshot> joinTable({
    String? tableId,
    TableSettings? quick,
  }) async {
    Map<String, dynamic> m;
    if (tableId != null && tableId == _seatedId && _latest != null) {
      m = _latest!; // masayı kurunca sunucu kurucuyu zaten oturttu: ikinci 'join' atma
    } else if (tableId != null) {
      m = await _join(tableId);
    } else {
      final q = quick ?? const TableSettings();
      final pick = _pickQuick(q);
      if (pick != null) {
        try {
          m = await _join(pick.id);
        } on JoinException catch (e) {
          Log.w('servis', 'hızlı katılım olmadı (${e.message}), masa kuruluyor');
          m = await _create('Hızlı Masa', q);
        }
      } else {
        m = await _create('Hızlı Masa', q);
      }
    }
    final tok = await accessToken();
    _uid = _uidFromJwt(tok);
    return _snapshot(m);
  }

  /// Bilet sunucuda oyun başlarken düşer (`start_match`); istemcinin yapacağı bir şey yok.
  @override
  Future<void> beginMatch() async {}

  /// `table` mesajları (oturdu/kalktı/geri sayım): yalnız oturduğum masanınkiler, bana göre çevrilmiş [TableSnapshot].
  @override
  Stream<TableSnapshot> get tableUpdates => socket.messages
      .where((m) => m['t'] == 'table' && m['table'] is Map && (m['table'] as Map)['id'] == _seatedId)
      .map((m) {
        _latest = m;
        return _snapshot(m);
      });

  /// Maç mesajları: `state` / `say` / `err` / `final`. (`err` masa kurma/katılma cevaplarında da gelir; ekran yalnız maç
  /// başladıktan sonra dinler.)
  @override
  Stream<Map<String, dynamic>> get matchEvents => socket.messages.where((m) {
        final t = m['t'];
        return t == 'state' || t == 'say' || t == 'err' || t == 'final';
      });

  @override
  Map<String, dynamic>? get latestMatchState {
    final m = _latest;
    return m != null && m['t'] == 'state' ? m : null;
  }

  /// Hamle: yalnız masadaysak ve bağlantı açıksa gider (kota: her mesaj 1/20 istek; hamleleri tek tek yolla, bekleme [GameController] yönetir).
  @override
  bool sendMatch(Map<String, dynamic> msg) {
    if (!_inTable) return false;
    return socket.send(msg);
  }

  /// MASADA KAL: `{t:'stay'}`; sunucu bileti kontrol eder (yoksa `yetersiz_bilet`), herkes hazırsa geri sayım başlar.
  @override
  Future<TableSnapshot> stayAtTable() async {
    if (!_inTable) throw const JoinException('Masa artık yok.');
    final m = await _request({'t': 'stay'});
    _latest = m;
    return _snapshot(m);
  }

  /// Masadan kalkar (maç sürüyorsa bilet yanar!). Ekran "MASADAN ÇIK" onayından sonra çağırır.
  @override
  void leaveTable() {
    socket.send({'t': 'leave'});
    _inTable = false;
    _seatedId = null;
    _latest = null;
  }

  // ------------------------------------------------------------------ ağ yardımcıları

  Future<void> _ensureOpen() async {
    try {
      await socket.whenOpen();
    } on TimeoutException {
      throw const JoinException('Sunucuya bağlanılamadı. İnternetini kontrol et.');
    }
  }

  /// [send] true dönerse bir sonraki `lobby` mesajını (en çok 6 sn) bekler. Dinleyici ÖNCE kurulur.
  Future<void> _lobbyAfter(bool Function() send) async {
    final c = Completer<void>();
    final sub = socket.messages.listen((m) {
      if (m['t'] == 'lobby' && !c.isCompleted) c.complete();
    });
    final timer = Timer(const Duration(seconds: 6), () {
      if (!c.isCompleted) c.complete();
    });
    try {
      if (send()) await c.future;
    } finally {
      timer.cancel();
      await sub.cancel();
    }
  }

  /// Mesajı yollar; ilk `table`/`state` (başarı) ya da `err` (hata) cevabını bekler.
  Future<Map<String, dynamic>> _request(Map<String, dynamic> msg) async {
    await _ensureOpen();
    final c = Completer<Map<String, dynamic>>();
    final sub = socket.messages.listen((m) {
      if (c.isCompleted) return;
      switch (m['t']) {
        case 'table':
        case 'state':
          c.complete(m);
          break;
        case 'err':
          c.completeError(JoinException(_errText(m['m'])));
          break;
        case '_closed':
          c.completeError(const JoinException('Bağlantı koptu. Tekrar dene.'));
          break;
      }
    });
    final timer = Timer(const Duration(seconds: 15), () {
      if (!c.isCompleted) c.completeError(const JoinException('Sunucu cevap vermedi.'));
    });
    try {
      if (!socket.send(msg)) throw const JoinException('Sunucuya bağlı değilsin.');
      return await c.future;
    } finally {
      timer.cancel();
      await sub.cancel();
    }
  }

  Future<Map<String, dynamic>> _create(String name, TableSettings s) async {
    const n = 'Masa'; // ad serbest değil: sunucu masa_1, masa_2... verir (gönderilen yok sayılır)
    final m = await _request({
      't': 'create',
      'name': n,
      'hands': s.hands,
      'team': s.team,
      'folding': s.folding,
      'turbo': s.turbo,
      'bots': true,
    });
    _seated(m, s);
    return m;
  }

  Future<Map<String, dynamic>> _join(String id) async {
    final m = await _request({'t': 'join', 'id': id});
    _seated(m, null);
    return m;
  }

  void _seated(Map<String, dynamic> m, TableSettings? s) {
    final id = (m['table'] as Map)['id'] as String;
    _inTable = true;
    _seatedId = id;
    _latest = m;
    if (s != null) _known[id] = s;
  }

  static String _errText(Object? code) {
    final c = code is String ? code : '';
    return kServerErrors[c] ?? (c.isEmpty ? 'Bir hata oluştu.' : c);
  }

  // ------------------------------------------------------------------ eşlemeler

  List<TableInfo> _mapLobby(Map<String, dynamic>? lobby) {
    final raw = (lobby?['tables'] as List<dynamic>?) ?? const [];
    final out = <TableInfo>[];
    for (final e in raw) {
      final j = e as Map<String, dynamic>;
      final id = j['id'] as String;
      final s = TableSettings(
        team: (j['team'] ?? false) as bool,
        folding: (j['folding'] ?? true) as bool,
        turbo: (j['turbo'] ?? false) as bool,
        hands: (j['hands'] ?? 1) as int,
      );
      _known[id] = s;
      out.add(TableInfo(
        id: id,
        name: (j['name'] ?? 'Masa') as String,
        hostName: '', // sunucu kurucu adını göndermiyor
        settings: s,
        playerCount: (j['players'] as num).toInt(),
      ));
    }
    return out;
  }

  /// "Hemen Oyna": aynı kurallardaki, en çok insan oturan masa.
  TableInfo? _pickQuick(TableSettings q) {
    final list = _mapLobby(socket.lastLobby).where((t) {
      final s = t.settings;
      return !t.isFull &&
          s.team == q.team &&
          s.folding == q.folding &&
          s.turbo == q.turbo &&
          s.hands == q.hands;
    }).toList();
    if (list.isEmpty) return null;
    list.sort((a, b) => b.playerCount.compareTo(a.playerCount));
    return list.first;
  }

  TableInfo _tableInfo(Map<String, dynamic> m, TableSettings s) {
    final t = (m['table'] as Map).cast<String, dynamic>();
    final seats = ((t['seats'] ?? const []) as List<dynamic>).whereType<String>().toList();
    return TableInfo(
      id: t['id'] as String,
      name: (t['name'] ?? 'Masa') as String,
      hostName: seats.isEmpty ? '' : seats.first,
      settings: s,
      playerCount: seats.length,
      seatNames: seats,
    );
  }

  Tile _tile(Map<String, dynamic> j) => Tile(
        id: (j['id'] as num).toInt(),
        number: (j['n'] as num).toInt(),
        color: TileColor.values[(j['c'] as num).toInt()],
        isFakeJoker: (j['fake'] ?? false) as bool,
      );

  /// Sunucu mesajından arayüzün beklediği [TableSnapshot]. Maç başlamadan önce (`table`) taşlar yoktur:
  /// ıstaka boş, gösterge yer tutucudur. Maç başlayınca (`state`) eli/göstergeyi/sırayı doldurur.
  /// Açılmış perler (`melds`) eşlenir; rakip çipleri henüz eşlenmiyor (0).
  TableSnapshot _snapshot(Map<String, dynamic> m) {
    final t = (m['table'] as Map).cast<String, dynamic>();
    final id = t['id'] as String;
    final seats = ((t['seats'] ?? const []) as List<dynamic>).cast<String?>();
    final srv = m['settings'];
    final base = _known[id] ?? const TableSettings();
    final settings = srv is Map
        ? base.copyWith(
            team: (srv['team'] ?? base.team) as bool,
            folding: (srv['folding'] ?? base.folding) as bool,
            turbo: (srv['turbo'] ?? base.turbo) as bool,
            hands: (srv['hands'] ?? base.hands) as int,
          )
        : base;

    var mySeat = m['me'] is num ? (m['me'] as num).toInt() : -1;
    if (mySeat < 0) {
      final uid = _uid;
      final mine = uid == null || uid.length < 4 ? null : 'Oyuncu-${uid.substring(uid.length - 4)}';
      mySeat = mine == null ? 0 : seats.indexOf(mine);
      if (mySeat < 0) mySeat = 0;
    }
    String nameAt(int rel) {
      final i = (mySeat + rel) % 4;
      return i < seats.length ? (seats[i] ?? 'Bekleniyor') : 'Bekleniyor';
    }

    final avs = t['avatars'];
    int? avatarAt(int rel) {
      final i = (mySeat + rel) % 4;
      final v = avs is List && i < avs.length ? avs[i] : null;
      return v is num ? v.toInt() : null;
    }

    Player p(int rel, int chips) => Player(
        id: 'seat${(mySeat + rel) % 4}', name: nameAt(rel), chipCount: chips, avatar: avatarAt(rel));

    final rack = List<Tile?>.filled(32, null);
    final hand = m['hand'];
    if (hand is List) {
      for (var i = 0; i < hand.length && i < rack.length; i++) {
        rack[i] = _tile((hand[i] as Map).cast<String, dynamic>());
      }
    }
    final ind = m['indicator'];
    final discards = <Seat, Tile?>{for (final s in Seat.values) s: null};
    final tops = m['tops'];
    if (tops is List) {
      for (var rel = 0; rel < 4; rel++) {
        final i = (mySeat + rel) % 4;
        final x = i < tops.length ? tops[i] : null;
        if (x is Map) discards[Seat.values[rel]] = _tile(x.cast<String, dynamic>());
      }
    }
    // Masaya açılmış perler: sunucu her per için {kind, tiles, number, color, owner} yollar.
    final melds = <List<Tile>>[];
    final rawMelds = m['melds'];
    if (rawMelds is List) {
      for (final x in rawMelds) {
        final ts = x is Map ? x['tiles'] : null;
        if (ts is List) {
          melds.add([for (final t in ts) if (t is Map) _tile(t.cast<String, dynamic>())]);
        }
      }
    }
    // Taşı kimin koyduğu: sunucu mutlak koltukla yollar, bana göre çevrilir.
    final layers = <int, int>{};
    final rawLayers = m['layers'];
    if (rawLayers is Map) {
      rawLayers.forEach((k, v) {
        final id = int.tryParse('$k');
        if (id != null && v is num) layers[id] = (v.toInt() - mySeat + 4) % 4;
      });
    }
    final turn = m['turn'] is num ? (m['turn'] as num).toInt() : mySeat;

    return TableSnapshot(
      tableId: id,
      settings: settings,
      me: Player(id: _uid ?? 'me', name: nameAt(0), chipCount: _chips, avatar: avatarAt(0)),
      left: p(3, 0),
      top: p(2, 0),
      right: p(1, 0),
      rack: rack,
      indicator: ind is Map
          ? _tile(ind.cast<String, dynamic>())
          : const Tile(id: -1, number: 1, color: TileColor.yellow),
      deckCount: m['deck'] is num ? (m['deck'] as num).toInt() : 0,
      discards: discards,
      openedMelds: melds,
      meldLayers: layers,
      emptySeats: {
        for (var rel = 0; rel < 4; rel++)
          if (((mySeat + rel) % 4) >= seats.length || seats[(mySeat + rel) % 4] == null) Seat.values[rel],
      },
      activeSeat: Seat.values[(turn - mySeat) % 4],
      startsInMs: (m['table'] is Map && (m['table'] as Map)['startsIn'] is num)
          ? ((m['table'] as Map)['startsIn'] as num).toInt()
          : 0,
    );
  }

  /// JWT'nin `sub` alanı (kullanıcı kimliği); okunamazsa null.
  static String? _uidFromJwt(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length < 2) return null;
      final json = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      return (jsonDecode(json) as Map<String, dynamic>)['sub'] as String?;
    } catch (_) {
      return null;
    }
  }
}

class _Lifecycle with WidgetsBindingObserver {
  final void Function() onResume;
  final void Function() onPause;
  _Lifecycle(this.onResume, this.onPause);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResume();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      onPause();
    }
  }
}
