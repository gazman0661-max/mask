import 'dart:async';
import 'dart:math';
import '../models/goals.dart';
import '../models/player.dart';
import '../models/quick_chat.dart';
import '../models/rewards.dart';
import '../models/rooms.dart';
import '../models/table_models.dart';
import '../models/tile.dart';
import 'game_service.dart';

class MockGameService implements GameService {
  int chipCount = 50000;
  /// Oyuncunun takma adı ve avatarı (profil ekranından gelir).
  String myName = 'Oyuncu_01';
  int myAvatar = 0;
  static const _y = TileColor.yellow,
      _b = TileColor.blue,
      _k = TileColor.black,
      _r = TileColor.red;
  int _id = 0;
  int _seq = 1;

  // Hazır mesaj: sahte serviste bilgisayar oyuncular ara sıra karşılık verir (ekran canlı görünsün).
  final _chat = StreamController<ChatEvent>.broadcast();
  final _rnd = Random();
  final _limiter = ChatLimiter();

  @override
  Stream<ChatEvent> get chatEvents => _chat.stream;

  // Sahte serviste kopma/boşta yok: hep bağlı, kimse bot değil.
  @override
  Stream<Presence> get presence => Stream<Presence>.empty();

  @override
  Stream<bool> get connection => Stream<bool>.empty();

  @override
  bool get isConnected => true;

  @override
  void imHere() {}

  @override
  void sendChat(int id) {
    final now = DateTime.now();
    if (!_limiter.canSend(now)) return; // sunucudakiyle aynı bekleme + dakikalık sınır
    _limiter.record(now);
    if (_rnd.nextInt(100) >= 60) return; // %60 ihtimalle bir bilgisayar cevap verir
    const replies = [8, 9, 12, 13, 14, 15, 5, 3, 1]; // 😂 😎 👏 👍 🔥 🤔 Evet Elin nasıl? Okey attın!
    Future.delayed(Duration(milliseconds: 900 + _rnd.nextInt(1400)), () {
      if (_chat.isClosed) return;
      _chat.add(ChatEvent(1 + _rnd.nextInt(3), replies[_rnd.nextInt(replies.length)]));
    });
  }
  Tile _t(int n, TileColor c) => Tile(id: _id++, number: n, color: c);

  final List<TableInfo> _tables = [
    const TableInfo(
        id: 't1',
        name: 'Başlangıç Masası',
        hostName: 'Elif',
        seatNames: ['Elif', 'Kaan', 'Zeynep'],
        playerCount: 3,
        settings: TableSettings()),
    const TableInfo(
        id: 't2',
        name: 'Sakin Masa',
        hostName: 'Murat',
        seatNames: ['Murat', 'Ayşe'],
        playerCount: 2,
        settings:
            TableSettings(folding: false, hands: 3)),
    const TableInfo(
        id: 't3',
        name: 'Hızlı 101',
        hostName: 'Bilge',
        playerCount: 1,
        settings: TableSettings(turbo: true)),
    const TableInfo(
        id: 't4',
        name: 'Orta Masa',
        hostName: 'Kemal',
        playerCount: 2,
        settings: TableSettings(hands: 2)),
    const TableInfo(
        id: 't5',
        name: 'Yardımsız Usta',
        hostName: 'Selin',
        playerCount: 4,
        settings: TableSettings(assisted: false, folding: true, hands: 3)),
    const TableInfo(
        id: 't6',
        name: 'Usta Hızlı',
        hostName: 'Can',
        playerCount: 1,
        settings: TableSettings(
            turbo: true, assisted: false, hands: 4)),
    const TableInfo(
        id: 't8',
        name: 'VIP Salon',
        hostName: 'Burak',
        playerCount: 3,
        settings: TableSettings(
            assisted: false, folding: true, hands: 2)),
    const TableInfo(
        id: 't9',
        name: 'Şampiyonlar Ligi',
        hostName: 'Tolga',
        playerCount: 2,
        settings: TableSettings(
            assisted: false, hands: 2)),
    const TableInfo(
        id: 't10',
        name: 'Efsane Masa',
        hostName: 'Gül',
        playerCount: 1,
        settings: TableSettings(
            assisted: false, hands: 4)),
    const TableInfo(
        id: 't11',
        name: 'Acemi Hızlı',
        hostName: 'Nur',
        playerCount: 2,
        settings: TableSettings(turbo: true)),
  ];

  @override
  String? get lobbyNotice => null;

  @override
  Stream<void>? get tablesChanged => null; // sahte servis bildirim yollamaz: ekran 30 sn'de yeniler

  @override
  Future<Player> fetchMyProfile() async {
    await _latency();
    return Player(id: 'me', name: myName, chipCount: chipCount, level: _level, avatar: myAvatar);
  }

  // ---- günlük ödül / reklam çipi (bellekte; sunucudaki mantığın aynısı, Türkiye saati yerine cihaz saati)
  int _dailyStreak = 0;
  DateTime? _lastDaily;
  DateTime? _lastAd;

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// (alınabilir mi, gün numarası)
  (bool, int) _dailyNow() {
    final now = DateTime.now();
    final last = _lastDaily;
    if (last != null && _sameDay(last, now)) return (false, _dailyStreak < 1 ? 1 : _dailyStreak);
    if (last != null && _sameDay(last, now.subtract(const Duration(days: 1)))) return (true, nextDay(_dailyStreak));
    return (true, 1);
  }

  @override
  Future<DailyStatus> fetchDailyStatus() async {
    await _latency();
    final (can, day) = _dailyNow();
    return DailyStatus(canClaim: can, day: day, amount: dailyAmount(day));
  }

  @override
  Future<DailyClaim> claimDaily({bool doubled = false}) async {
    await _latency();
    final (can, day) = _dailyNow();
    if (!can) throw const JoinException('Bugünün ödülünü zaten aldın.');
    final amount = dailyAmount(day) * (doubled ? 2 : 1);
    chipCount += amount;
    _dailyStreak = day;
    _lastDaily = DateTime.now();
    return DailyClaim(day: day, amount: amount, chips: chipCount);
  }

  int get _adWait {
    final last = _lastAd;
    if (last == null) return 0;
    final left = kAdCooldown - DateTime.now().difference(last);
    return left.isNegative ? 0 : left.inSeconds + 1;
  }

  @override
  Future<AdStatus> fetchAdStatus() async {
    await _latency();
    return AdStatus(amount: kAdChips, waitSeconds: _adWait);
  }

  @override
  Future<AdStatus> claimAdChips() async {
    await _latency();
    if (_adWait > 0) throw const JoinException('Yeni reklam henüz hazır değil.');
    chipCount += kAdChips;
    _lastAd = DateTime.now();
    return AdStatus(amount: kAdChips, waitSeconds: kAdCooldown.inSeconds);
  }

  // ---- çip + seviye (bellekte; sunucudaki mantığın aynısı)
  int xp = 600; // sahte servis: XP elle artırılır (test); seviye XP'den hesaplanır (600 XP = seviye 4)
  int levelClaimed = 4; // 600 XP = seviye 4: açılışta kutlama penceresi çıkmasın (testler xp'yi artırınca çıkar)

  int get _level => levelOfXp(xp);

  @override
  Future<ChipStatus> fetchChipStatus() async {
    await _latency();
    return ChipStatus(chips: chipCount, xp: xp, level: _level, levelClaimed: levelClaimed);
  }

  // ---- günlük görevler / başarımlar / lig (yalnız geliştirme: sahte sayılar)
  final Set<String> _taskClaimed = {};
  final Map<String, int> _achClaimed = {};

  @override
  Future<TasksStatus> fetchTasks() async {
    await _latency();
    return TasksStatus(played: 3, wins: 0, pts: 160, claimed: Set.of(_taskClaimed));
  }

  @override
  Future<GoalClaim> claimTask(String taskId) async {
    await _latency();
    final def = kDailyTasks.where((t) => t.id == taskId);
    if (def.isEmpty) throw const JoinException('Geçersiz görev.');
    if (_taskClaimed.contains(taskId)) throw const JoinException('Bu görevin ödülünü zaten aldın.');
    final st = await fetchTasks();
    if (!st.done(def.first)) throw const JoinException('Bu görev henüz tamamlanmadı.');
    _taskClaimed.add(taskId);
    chipCount += def.first.reward;
    return GoalClaim(amount: def.first.reward, chips: chipCount);
  }

  @override
  Future<AchStatus> fetchAchievements() async {
    await _latency();
    return AchStatus(played: 12, wins: 2, xp: xp, claimed: Map.of(_achClaimed));
  }

  @override
  Future<GoalClaim> claimAchievement(String id, int tier) async {
    await _latency();
    final defs = kAchDefs.where((a) => a.id == id);
    if (defs.isEmpty || tier < 1 || tier > 4) throw const JoinException('Geçersiz başarım.');
    final st = await fetchAchievements();
    final a = defs.first;
    if (st.valueOf(a) < a.targets[tier - 1]) throw const JoinException('Bu başarım henüz tamamlanmadı.');
    if ((_achClaimed[id] ?? 0) >= tier) throw const JoinException('Bu başarımın ödülünü zaten aldın.');
    if ((_achClaimed[id] ?? 0) != tier - 1) throw const JoinException('Önce bir önceki kademenin ödülünü al.');
    _achClaimed[id] = tier;
    chipCount += kAchRewards[tier - 1];
    return GoalClaim(amount: kAchRewards[tier - 1], chips: chipCount);
  }

  @override
  Future<List<LeagueRow>> fetchLeague({int limit = 50}) async {
    await _latency();
    const names = ['Kartal_4821', 'Şahin_1203', 'Aslan_9087', 'Kaplan_3342', 'Tilki_7710', 'Ceylan_5521'];
    return [
      for (var i = 0; i < names.length; i++)
        LeagueRow(pos: i + 1, userId: i == 3 ? 'me' : 'u$i', name: names[i], avatar: i * 3, points: 600 - i * 70),
    ];
  }

  @override
  String? get myUserId => 'me';

  @override
  Future<LevelClaim> claimLevelRewards() async {
    await _latency();
    final lv = levelOfXp(xp);
    final n = lv - levelClaimed;
    if (n <= 0) throw const JoinException('Alınacak seviye hediyesi yok.');
    chipCount += n * kLevelUpChips;
    levelClaimed = lv;
    return LevelClaim(amount: n * kLevelUpChips, chips: chipCount, level: lv);
  }

  /// Masaya oturmak / masa kurmak çip DÜŞÜRMEZ, yalnız oda şartını ister (sunucudaki `can_sit`: min çip, min seviye, çip tavanı).
  void _requireRoom(int roomId, int bet) {
    final r = roomById(roomId);
    if (!r.hasBet(bet)) throw JoinException('Bahis ${r.name} için ${r.minBet}-${r.maxBet} arasında olmalı.');
    final why = roomBlockReason(r, chips: chipCount, level: _level, bet: bet);
    if (why != null) throw JoinException('${r.name}: $why.');
  }

  /// Giriş çipi oyun BAŞLARKEN düşer (sunucudaki `start_match`). Geri sayım bitince ekran çağırır; her yeni oyun (TEKRAR OYNA dahil)
  /// odanın giriş bahsini düşer. Kazanç sahte serviste yok (maç sonucu sunucu işi).
  int _room = kDefaultRoom;
  int _bet = roomById(kDefaultRoom).minBet;

  @override
  Future<void> beginMatch() async {
    final bet = _bet;
    if (chipCount < bet) throw const JoinException('Çipin bu oda için yetmiyor. Reklam izleyerek ya da günlük ödülünle devam edebilirsin.');
    chipCount -= bet;
  }

  @override
  Future<List<TableInfo>> fetchTables() async {
    await _latency();
    return List.of(_tables);
  }

  /// Masa adı serbest değil: en küçük boş numara (masa_1, masa_2, ...), sunucuyla aynı kural.
  String _nextTableName() {
    final used = _tables.map((t) => t.name).toSet();
    var n = 1;
    while (used.contains('masa_$n')) n++;
    return 'masa_$n';
  }

  @override
  Future<TableInfo> createTable({
    required String name,
    required TableSettings settings,
  }) async {
    await _latency();
    _requireRoom(settings.room, settings.bet); // masa kurmak çip düşürmez (oda şartı aranır); giriş çipi oyun başlarken düşer
    _room = settings.room;
    _bet = settings.bet;
    final id = 'u${_seq++}';
    final t = TableInfo(
      id: id,
      name: _nextTableName(),
      hostName: 'Oyuncu_01',
      playerCount: 1,
      settings: settings,
    );
    _tables.insert(0, t);
    return t;
  }

  @override
  Future<TableSnapshot> joinTable({
    String? tableId,
    TableSettings? quick,
  }) async {
    await _latency();
    var settings = quick ?? const TableSettings();
    if (tableId != null) {
      final i = _tables.indexWhere((t) => t.id == tableId);
      if (i < 0) throw const JoinException('Masa artık yok.');
      final t = _tables[i];
      final mine = t.hostName == 'Oyuncu_01';
      if (t.isFull && !mine) throw const JoinException('Masa dolu.');
      settings = t.settings;
    }
    _requireRoom(settings.room, settings.bet); // oturmak bedava; giriş çipi geri sayım bitince (beginMatch) düşer
    _room = settings.room;
    _bet = settings.bet;
    _id = 0;
    // Sunucudaki gibi: masaya oturunca diğer koltuklar BOŞ; ilk bot [botFirstDelay] sonra, diğerleri [botNextDelay]
    // arayla oturur, dolunca geri sayım başlar ([tableUpdates]).
    _cancelFill();
    _bots = 0;
    _curSettings = settings;
    _curTableId = tableId ?? 'quick';
    _scheduleBot(botFirstDelay);
    return _tableSnap();
  }

  // ---- masa bekleme simülasyonu (sunucudaki FIRST_BOT_MS / NEXT_BOT_MS davranışı) ----
  /// Testlerde kısaltılabilir.
  Duration botFirstDelay = kFirstBotDelay;
  Duration botNextDelay = kNextBotDelay;
  final _tableUpdates = StreamController<TableSnapshot>.broadcast();
  final List<Timer> _fillTimers = [];
  TableSettings _curSettings = const TableSettings();
  String _curTableId = 'quick';
  int _bots = 0; // oturmuş bot sayısı (0..3)

  static const _botSeats = [Seat.left, Seat.top, Seat.right];
  static const _botPlayers = <Seat, Player>{
    Seat.left: Player(id: 'p2', name: 'Elif', chipCount: 32500, avatar: 16),
    Seat.top: Player(id: 'p3', name: 'Murat', chipCount: 18200, avatar: 8),
    Seat.right: Player(id: 'p4', name: 'Bilgisayar', chipCount: 50000, avatar: 3),
  };

  TableSnapshot _tableSnap({int startsInMs = 0}) {
    final seated = _botSeats.take(_bots).toSet();
    Player at(Seat s) => seated.contains(s)
        ? _botPlayers[s]!
        : const Player(id: 'empty', name: 'Bekleniyor', chipCount: 0);
    return TableSnapshot(
      tableId: _curTableId,
      settings: _curSettings,
      me: Player(id: 'me', name: myName, chipCount: chipCount, avatar: myAvatar),
      left: at(Seat.left),
      top: at(Seat.top),
      right: at(Seat.right),
      rack: List<Tile?>.filled(32, null),
      indicator: _t(12, _b),
      deckCount: 54,
      discards: {
        Seat.left: _t(4, _r),
        Seat.me: _t(10, _y),
        Seat.right: _t(2, _k),
        Seat.top: _t(2, _y),
      },
      openedMelds: const [],
      activeSeat: Seat.me,
      emptySeats: {for (final s in _botSeats) if (!seated.contains(s)) s},
      startsInMs: startsInMs,
    );
  }

  void _scheduleBot(Duration d) {
    _fillTimers.add(Timer(d, () {
      if (_tableUpdates.isClosed) return;
      _bots++;
      final full = _bots >= _botSeats.length;
      _tableUpdates.add(_tableSnap(startsInMs: full ? kStartCountdownSeconds * 1000 : 0));
      if (full) {
        _scheduleMatchStart();
      } else {
        _scheduleBot(botNextDelay);
      }
    }));
  }

  // ---- ÖNİZLEME maçı: gerçek sunucu yok; geri sayım bitince SABİT bir el gösterilir (yerleşimi görmek için).
  // Oyun kuralı/bot burada ÇALIŞMAZ: hamleler "sunucu yok" uyarısı verir.
  final _match = StreamController<Map<String, dynamic>>.broadcast();
  Map<String, dynamic>? _matchState;

  void _scheduleMatchStart() {
    _fillTimers.add(Timer(Duration(seconds: kStartCountdownSeconds), () {
      if (_match.isClosed) return;
      _matchState = _previewState();
      _match.add(_matchState!);
    }));
  }

  Map<String, dynamic> _previewState() {
    Map<String, dynamic> tile(int id) => id >= 104
        ? {'id': id, 'n': 0, 'c': 3, 'fake': true}
        : {'id': id, 'n': (id ~/ 2) % 13 + 1, 'c': (id ~/ 2) ~/ 13, 'fake': false};
    final ids = List<int>.generate(106, (i) => i)..shuffle(Random(7));
    final ind = ids.firstWhere((i) => i < 104);
    ids.remove(ind);
    final hand = ids.sublist(0, 22);
    final indT = tile(ind);
    final ok = {'n': (indT['n'] as int) == 13 ? 1 : (indT['n'] as int) + 1, 'c': indT['c']};
    List<T> four<T>(T v) => List<T>.filled(4, v);
    return {
      't': 'state',
      'table': {
        'id': _curTableId,
        'name': 'masa_1',
        'seats': [myName, 'Bilgisayar', 'Murat', 'Elif'],
        'avatars': [myAvatar, 3, 8, 16],
        'away': four(false),
        'afk': four(false),
        'startsIn': 0,
      },
      'me': 0,
      'turn': 0,
      'phase': 'play',
      'round': 1,
      'handsTotal': _curSettings.hands,
      'indicator': indT,
      'okey': ok,
      'deck': 106 - 1 - 85,
      'hand': [for (final i in hand) tile(i)],
      'counts': [22, 21, 21, 21],
      'tops': <Object?>[null, null, null, null],
      'melds': <Object?>[],
      'layers': <String, int>{},
      'opened': <Object?>[null, null, null, null],
      'openScore': four(0),
      'required': 101,
      'requiredPairs': 5,
      'penalty': four(0),
      'totals': four(0),
      'lastDelta': four(0),
      'mustUse': null,
      'acted': false,
      'pending': null,
      'result': null,
      'settings': {
        'team': _curSettings.team,
        'folding': _curSettings.folding,
        'turbo': _curSettings.turbo,
        'hands': _curSettings.hands,
      },
      'turnToken': 1,
    };
  }

  @override
  Stream<Map<String, dynamic>> get matchEvents => _match.stream;

  @override
  Map<String, dynamic>? get latestMatchState => _matchState;

  @override
  bool sendMatch(Map<String, dynamic> msg) {
    Future.microtask(() {
      if (!_match.isClosed) {
        _match.add({'t': 'err', 'm': 'Önizleme: oyun sunucusu bağlı değil, hamle yapılamaz.'});
      }
    });
    return true;
  }

  void _cancelFill() {
    for (final t in _fillTimers) {
      t.cancel();
    }
    _fillTimers.clear();
  }

  @override
  Stream<TableSnapshot> get tableUpdates => _tableUpdates.stream;

  /// Maç bitti, aynı masada yeni oyun: sahte serviste rakipler masada kalır, geri sayım hemen başlar.
  @override
  Future<TableSnapshot> stayAtTable() async {
    await _latency();
    _requireRoom(_room, _bet);
    _cancelFill();
    _bots = _botSeats.length;
    _matchState = null;
    _scheduleMatchStart();
    return _tableSnap(startsInMs: kStartCountdownSeconds * 1000);
  }

  @override
  void leaveTable() {
    _cancelFill();
    _bots = 0;
    _matchState = null;
  }

  Future<void> _latency() => Future.delayed(const Duration(milliseconds: 350));
}
