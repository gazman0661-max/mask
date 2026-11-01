import 'dart:async';
import 'dart:math';
import '../models/player.dart';
import '../models/quick_chat.dart';
import '../models/rewards.dart';
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
        name: 'Turbo 101',
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
        name: 'Usta Turbo',
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
        name: 'Acemi Turbo',
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
    return Player(id: 'me', name: myName, chipCount: chipCount, level: 4, avatar: myAvatar);
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

  // ---- bilet sistemi (bellekte; sunucudaki mantığın aynısı)
  int tickets = 3;
  int xp = 0; // sahte servis: XP elle artırılır (test); seviye XP'den hesaplanır
  int _levelClaimed = 1;
  DateTime? _lastAdTicket;
  DateTime? _lastDailyTicket;

  int get _adTicketWait {
    final last = _lastAdTicket;
    if (last == null) return 0;
    final left = kAdTicketCooldown - DateTime.now().difference(last);
    return left.isNegative ? 0 : left.inSeconds + 1;
  }

  bool get _dailyTicketReady {
    final last = _lastDailyTicket;
    return last == null || !_sameDay(last, DateTime.now());
  }

  @override
  Future<TicketStatus> fetchTicketStatus() async {
    await _latency();
    return TicketStatus(
        tickets: tickets,
        adWaitSeconds: _adTicketWait,
        dailyCanClaim: _dailyTicketReady,
        xp: xp,
        level: levelOfXp(xp),
        levelClaimed: _levelClaimed);
  }

  @override
  Future<TicketClaim> claimDailyTickets({bool doubled = false}) async {
    await _latency();
    if (!_dailyTicketReady) throw const JoinException('Bugünün ödülünü zaten aldın. Yarın tekrar gel!');
    final before = tickets;
    tickets += kDailyTickets * (doubled ? 2 : 1);
    _lastDailyTicket = DateTime.now();
    return TicketClaim(amount: tickets - before, tickets: tickets);
  }

  @override
  Future<TicketClaim> claimAdTicket() async {
    await _latency();
    if (_adTicketWait > 0) throw const JoinException('Yeni reklam henüz hazır değil.');
    tickets++;
    _lastAdTicket = DateTime.now();
    return TicketClaim(amount: 1, tickets: tickets, waitSeconds: kAdTicketCooldown.inSeconds);
  }

  DateTime? _lastTableAd;
  int _tableAdCount = 0;

  /// Masada reklam bileti: 10 dk sınırı yok; yalnız [kTableAdGap] bekleme + günlük [kTableAdDailyCap] sınır (sunucudaki mantığın aynısı).
  @override
  Future<TicketClaim> claimTableAdTicket() async {
    await _latency();
    final now = DateTime.now();
    final last = _lastTableAd;
    if (last != null && now.difference(last) < kTableAdGap) throw const JoinException('Yeni reklam henüz hazır değil.');
    if (last == null || !_sameDay(last, now)) _tableAdCount = 0;
    if (_tableAdCount >= kTableAdDailyCap) {
      throw const JoinException('Bugünlük reklam bileti sınırına ulaştın. Yarın tekrar dene ya da günlük biletini al.');
    }
    _tableAdCount++;
    _lastTableAd = now;
    tickets++;
    return TicketClaim(amount: 1, tickets: tickets, waitSeconds: kTableAdGap.inSeconds);
  }

  @override
  Future<LevelClaim> claimLevelRewards() async {
    await _latency();
    final lv = levelOfXp(xp);
    final n = lv - _levelClaimed;
    if (n <= 0) throw const JoinException('Alınacak seviye hediyesi yok.');
    tickets += n;
    _levelClaimed = lv;
    return LevelClaim(amount: n, tickets: tickets, level: lv);
  }

  static const _noTicket = 'Biletin yok. Reklam izleyerek ya da günlük biletinle devam edebilirsin.';

  /// Masaya oturmak / masa kurmak bilet DÜŞÜRMEZ, yalnız en az 1 bilet ister (sunucudaki `can_sit`).
  void _requireTicket() {
    if (tickets < 1) throw const JoinException(_noTicket);
  }

  /// Bilet oyun BAŞLARKEN düşer (sunucudaki `start_match`). Geri sayım bitince ekran çağırır; her yeni oyun (TEKRAR OYNA dahil) 1 bilet.
  @override
  Future<void> beginMatch() async {
    _requireTicket();
    tickets--;
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
    _requireTicket(); // masa kurmak bilet düşürmez (en az 1 bilet gerekir); bilet oyun başlarken düşer
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
    _requireTicket(); // oturmak bedava; bilet geri sayım bitince (beginMatch) düşer
    _id = 0;
    return TableSnapshot(
      tableId: tableId ?? 'quick',
      settings: settings,
      me: Player(id: 'me', name: myName, chipCount: chipCount, avatar: myAvatar),
      left: const Player(id: 'p2', name: 'Elif', chipCount: 32500, avatar: 16),
      top: const Player(id: 'p3', name: 'Murat', chipCount: 18200, avatar: 8),
      right: const Player(id: 'p4', name: 'Bilgisayar', chipCount: 50000, avatar: 3),
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
    );
  }

  Future<void> _latency() => Future.delayed(const Duration(milliseconds: 350));
}
