import 'dart:async';
import '../models/goals.dart';
import '../models/player.dart';
import '../models/quick_chat.dart';
import '../models/rewards.dart';
import '../models/table_models.dart';
import '../services/game_service.dart';
import '../services/telemetry.dart';
import 'app_log.dart';

/// Herhangi bir [GameService]'i sarar; her çağrıyı, süresini, sonucunu ve
/// hatasını günlüğe yazar. Backend bağlanınca da aynen kullanılır:
/// LoggingGameService(CloudflareGameService(...)).
class LoggingGameService implements GameService {
  final GameService _inner;
  LoggingGameService(this._inner);

  /// Başarılı olunca Analytics'e giden olaylar (Firebase kapalıyken hiçbir şey olmaz). Adlar ASCII, 40 karakter altı.
  static const _events = <String, String>{
    'claimDaily': 'gunluk_odul',
    'claimAdChips': 'reklam_cip',
    'claimLevelRewards': 'seviye_odul',
    'createTable': 'masa_kur',
    'joinTable': 'masaya_otur',
    'beginMatch': 'mac_basla',
  };

  static String _fmt(TableSettings s) =>
      'eşli=${s.team} katlamalı=${s.folding} yardımlı=${s.assisted} turbo=${s.turbo} el=${s.hands}';

  Future<T> _wrap<T>(String name, String args, Future<T> Function() f,
      [String Function(T)? describe]) async {
    final sw = Stopwatch()..start();
    Log.d('servis', '$name($args) çağrıldı');
    try {
      final r = await f();
      final ev = _events[name];
      if (ev != null) Telemetry.event(ev);
      Log.i('servis',
          '$name tamam ${sw.elapsedMilliseconds}ms${describe == null ? '' : ' → ${describe(r)}'}');
      return r;
    } on JoinException catch (e) {
      Log.w('servis', '$name reddedildi (${sw.elapsedMilliseconds}ms): ${e.message}');
      rethrow;
    } catch (e, s) {
      Log.e('servis', '$name HATA (${sw.elapsedMilliseconds}ms)', e, s);
      rethrow;
    }
  }

  @override
  Stream<void>? get tablesChanged => _inner.tablesChanged;

  @override
  String? get lobbyNotice => _inner.lobbyNotice;

  @override
  Stream<ChatEvent> get chatEvents => _inner.chatEvents;

  @override
  Stream<Presence> get presence => _inner.presence.map((p) {
        Log.d('servis', 'presence away=${p.away} afk=${p.afk}');
        return p;
      });

  @override
  Stream<bool> get connection => _inner.connection.map((c) {
        Log.i('servis', 'bağlantı ${c ? 'AÇIK' : 'KOPTU'}');
        return c;
      });

  @override
  bool get isConnected => _inner.isConnected;

  @override
  void imHere() {
    Log.i('servis', 'imHere() — oyuna dön');
    _inner.imHere();
  }

  @override
  void sendChat(int id) {
    Log.d('servis', 'sendChat($id)');
    _inner.sendChat(id);
  }

  @override
  Future<Player> fetchMyProfile() => _wrap('fetchMyProfile', '',
      () => _inner.fetchMyProfile(), (p) => 'çip=${p.chipCount}');

  @override
  Future<DailyStatus> fetchDailyStatus() => _wrap('fetchDailyStatus', '', () => _inner.fetchDailyStatus(),
      (d) => 'alınabilir=${d.canClaim} gün=${d.day} ödül=${d.amount}');

  @override
  Future<DailyClaim> claimDaily({bool doubled = false}) => _wrap('claimDaily', '2x=$doubled',
      () => _inner.claimDaily(doubled: doubled), (c) => 'gün=${c.day} +${c.amount} bakiye=${c.chips}');

  @override
  Future<AdStatus> fetchAdStatus() => _wrap('fetchAdStatus', '', () => _inner.fetchAdStatus(),
      (a) => 'bekleme=${a.waitSeconds}sn');

  @override
  Future<ChipStatus> fetchChipStatus() => _wrap('fetchChipStatus', '', () => _inner.fetchChipStatus(),
      (t) => 'çip=${t.chips} seviye=${t.level} xp=${t.xp}');

  @override
  Future<TasksStatus> fetchTasks() => _wrap('fetchTasks', '', () => _inner.fetchTasks(),
      (t) => 'oynanan=${t.played} kazanılan=${t.wins} puan=${t.pts} alınan=${t.claimed.length}');

  @override
  Future<GoalClaim> claimTask(String taskId) =>
      _wrap('claimTask', taskId, () => _inner.claimTask(taskId), (c) => '+${c.amount} çip');

  @override
  Future<AchStatus> fetchAchievements() => _wrap('fetchAchievements', '', () => _inner.fetchAchievements(),
      (a) => 'oynanan=${a.played} kazanılan=${a.wins} xp=${a.xp}');

  @override
  Future<GoalClaim> claimAchievement(String id, int tier) =>
      _wrap('claimAchievement', '$id/$tier', () => _inner.claimAchievement(id, tier), (c) => '+${c.amount} çip');

  @override
  Future<List<LeagueRow>> fetchLeague({int limit = 50}) =>
      _wrap('fetchLeague', '$limit', () => _inner.fetchLeague(limit: limit), (l) => '${l.length} satır');

  @override
  String? get myUserId => _inner.myUserId;

  @override
  Future<LevelClaim> claimLevelRewards() => _wrap('claimLevelRewards', '', () => _inner.claimLevelRewards(),
      (c) => '+${c.amount} çip seviye=${c.level}');

  @override
  Future<AdStatus> claimAdChips() => _wrap('claimAdChips', '', () => _inner.claimAdChips(),
      (a) => '+${a.amount} sonraki=${a.waitSeconds}sn');

  @override
  Future<List<TableInfo>> fetchTables() => _wrap('fetchTables', '',
      () => _inner.fetchTables(), (l) => '${l.length} masa');

  @override
  Future<TableInfo> createTable({
    required String name,
    required TableSettings settings,
  }) =>
      _wrap(
          'createTable',
          'ad="$name" ${_fmt(settings)}',
          () => _inner.createTable(name: name, settings: settings),
          (t) => 'masa id=${t.id}');

  @override
  Future<TableSnapshot> joinTable({
    String? tableId,
    TableSettings? quick,
  }) =>
      _wrap(
          'joinTable',
          'masa=${tableId ?? 'hemen oyna'}${quick == null ? '' : ' ${_fmt(quick)}'}',
          () => _inner.joinTable(tableId: tableId, quick: quick));

  @override
  Future<void> beginMatch() => _wrap('beginMatch', '', () => _inner.beginMatch());

  @override
  Stream<TableSnapshot> get tableUpdates => _inner.tableUpdates;

  @override
  Future<TableSnapshot> stayAtTable() => _wrap('stayAtTable', '', () => _inner.stayAtTable());

  @override
  void leaveTable() {
    Log.i('servis', 'leaveTable() masadan kalkıldı');
    _inner.leaveTable();
  }

  @override
  Stream<Map<String, dynamic>> get matchEvents => _inner.matchEvents;

  @override
  Map<String, dynamic>? get latestMatchState => _inner.latestMatchState;

  @override
  bool sendMatch(Map<String, dynamic> msg) {
    final ok = _inner.sendMatch(msg);
    Log.d('servis', 'hamle ${ok ? 'gitti' : 'GİTMEDİ'}: ${msg['t']}${msg['id'] != null ? ' id=${msg['id']}' : ''}');
    return ok;
  }
}
