import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../diagnostics/app_log.dart';
import '../models/player_stats.dart';
import '../models/table_models.dart';
import '../models/tile.dart';
import '../services/sfx.dart';
import 'hand_scorer.dart';
import 'meld.dart';
import 'okey_rules.dart';
import 'rack_arranger.dart';
import 'rack_shift.dart';

enum OpenMode { series, pairs }

/// [bot]: sıra bende değil (rakip insan ya da sunucudaki bot oynuyor).
enum TurnPhase { draw, play, bot, over }

/// Sunucuya hamle yollar. Yollandıysa true, bağlantı yoksa false döner.
typedef MatchSend = bool Function(Map<String, dynamic> msg);

/// Bir elin sonucu. [winner] null ise kimse eli bitirmemiştir (deste bitti ya
/// da herkes çift açtı): [deckOut] true olur ve el, elde kalan sayıyla
/// puanlanır (sunucudaki `RoundResult.deckOut` ile aynı).
class RoundResult {
  final int? winner;
  final List<int> delta;
  final List<OpenMode?> modes;
  final String note;

  /// Deste bitti / herkes çift açtı: kimse bitiremedi, elde kalan sayıyla puanlandı.
  final bool deckOut;

  /// Hükümsüz: tek elli oyunda kimse el açamadan el sona erdi (puan ve XP yok).
  final bool voided;
  const RoundResult(this.winner, this.delta, this.modes, this.note,
      {this.deckOut = false, this.voided = false});
}

/// Hatalı açış denemesi: perler masada kırmızı çerçeveyle bekler, oyuncu
/// GERİ TOPLA'ya basana (ya da süre dolana) kadar taş atamaz.
class PendingOpen {
  final OpenMode mode;
  final List<List<Tile>> groups;

  /// Taşların açılmadan önceki ıstaka yuvaları (geri topla yerlerine döner).
  final Map<int, Tile> slots;
  final String reason;
  const PendingOpen(this.mode, this.groups, this.slots, this.reason);
}

/// 101 Okey maç görünümü. Oyun kuralları, dağıtım, sıra, süre, puanlama ve botlar SUNUCUDADIR
/// (`okey101-server`); bu sınıf yalnız sunucunun `state` mesajını gösterir ve hamleleri sunucuya yollar.
/// Cihazda oyun motoru ya da bot YOKTUR. Istaka dizilimi (boşluklu gruplar) istemcide kalır.
///
/// Koltuklar ekranda bana göredir: 0 = ben, 1 = sağ, 2 = üst, 3 = sol (sunucu koltukları mutlaktır,
/// [applyState] çevirir). Sıra: sol -> ben -> sağ -> üst -> sol.
class GameController extends ChangeNotifier {
  static const int me = 0;
  static const int cols = 16;
  static const int rackSize = 32;
  static const int openLimit = 101;
  static const int penaltyPoints = 101;
  static const int minPairs = 5;

  /// Koltuk adları (ben, sağ, üst, sol); her `state` mesajında masadakilerle tazelenir.
  List<String> names;
  final int turnSeconds;
  final TableSettings settings;
  final MatchSend _send;

  int get totalHands => settings.hands;

  GameController(
      {required this.names,
      this.turnSeconds = 30,
      this.settings = const TableSettings(),
      MatchSend? send})
      : _send = send ?? ((_) => false);

  Okey okey = const Okey(1, TileColor.yellow);
  Tile indicator = const Tile(id: -1, number: 1, color: TileColor.yellow);

  /// Destede kalan taş sayısı (sunucu bildirir).
  int deckCount = 0;
  List<Tile?> rack = List<Tile?>.filled(rackSize, null);
  final List<Tile?> _tops = List<Tile?>.filled(4, null);
  final List<int> _counts = List<int>.filled(4, 0);
  List<Meld> table = [];

  /// Masadaki taşı kimin koyduğu (taş id → bana göre koltuk). Başkasının perine işleyenin animasyonu
  /// doğru koltuktan çıksın diye sunucudan gelir.
  final Map<int, int> tileLayer = {};
  final List<OpenMode?> opened = List<OpenMode?>.filled(4, null);

  /// Seri ile açanların açış puanı.
  final List<int> openScore = List<int>.filled(4, 0);
  final List<int> penalty = List<int>.filled(4, 0);

  /// Oyuncunun masaya açtığı toplam: seri açanda sayı, çift açanda çift adedi (oyuncu rozetinde gösterilir).
  final List<int> openedTotal = List<int>.filled(4, 0);
  final List<int> totals = List<int>.filled(4, 0);

  /// Son bitmiş elin puan değişimi (beraberlik bozmak için).
  List<int> lastDelta = List<int>.filled(4, 0);

  /// Bitmiş eller: her elin koltuk başına puan değişimi (oyun sonucu ekranı).
  final List<List<int>> history = [];

  /// Hatalı açış bekliyor (GERİ TOPLA gerekli).
  PendingOpen? pendingOpen;
  bool get hasPendingOpen => pendingOpen != null;

  int round = 0;
  int turn = 0;
  TurnPhase phase = TurnPhase.bot;
  bool pairMode = false;
  Tile? mustUse; // soldan alınan, hemen kullanılması gereken taş
  Tile? lastDrawn;
  RoundResult? result;

  /// Hükümsüz maç: tek elli oyunda kimse el açamadan deste bitti ya da herkes çift açtı.
  /// Kazanan yok, puan ve XP yok.
  bool voided = false;

  String? toast;
  int toastId = 0;
  int turnToken = 0;
  Duration turnDuration = const Duration(seconds: 30);

  // ---- sunucu durumunun özeti
  int _me = 0; // benim MUTLAK koltuğum
  bool _acted = false;
  int _reqOpen = openLimit;
  int _reqPairs = minPairs;
  int? _tableReqOpen; // masadaki (herkesin açışına göre) seri barajı; sunucu bildirir
  int? _tableReqPairs; // masadaki çift barajı
  bool _disposed = false;
  Timer? _warnTimer;
  int _historyRound = -1; // aynı el iki kez geçmişe/istatistiğe yazılmasın
  List<int>? _finalWinners;
  List<int>? _finalPoints;
  List<int>? _finalChips; // maç sonu koltuk başına çip (1. = havuz, 2. = giriş iadesi, diğerleri 0); bana göre, bot dahil
  /// Maç sonu: giriş çipi, havuz (giriş x 4), sunucu hatasıyla iade kutusuna gitti mi.
  int finalEntry = 0;
  int finalPot = 0;
  bool finalRefunded = false;
  /// Koltuk bot mu (bana göre: 0 ben, 1 sağ, 2 üst, 3 sol). Sunucu masa bilgisindeki `bots` bayrağı.
  List<bool> botSeats = const [false, false, false, false];
  List<Tile> _lastHand = const <Tile>[];

  // ---- hamle gönderme: cevap (state / err) gelene kadar ikinci hamle yollanmaz
  bool _busy = false;
  Timer? _busyTimer;
  int? _wantSlot; // çekilen/alınan taşın konacağı yuva (sürükleyerek bırakılan yer)
  final Map<int, int> _lastSlot = {}; // taş id → ıstakadan çıkmadan önceki yuva (geri gelince yerine döner)

  // ------------------------------------------------------------- takım

  bool get teamMode => settings.team;

  /// Karşılıklı oturanlar eştir: 0-2 ve 1-3.
  static int partnerOf(int seat) => (seat + 2) % 4;
  static int teamOf(int seat) => seat % 2;

  int teamTotal(int team) => totals[team] + totals[team + 2]; // 0: ben+üst, 1: sağ+sol

  /// Eşli oyunda kazanan takım (toplamı düşük olan). Eşitlikte son elin
  /// puanı düşük olan kazanır; o da eşitse null (beraberlik).
  int? get championTeam {
    final a = teamTotal(0), b = teamTotal(1);
    if (a != b) return a < b ? 0 : 1;
    final la = lastDelta[0] + lastDelta[2], lb = lastDelta[1] + lastDelta[3];
    if (la != lb) return la < lb ? 0 : 1;
    return null;
  }

  /// Tekli oyunda kazanan koltuk (toplamı en düşük olan). Eşitlikte son
  /// elin puanı en düşük olan kazanır; yine eşitse null (beraberlik).
  int? get championSeat {
    final best = _soloBest();
    return best.length == 1 ? best.first : null;
  }

  List<int> _soloBest() {
    var best = [0];
    for (var s = 1; s < 4; s++) {
      if (totals[s] < totals[best.first]) {
        best = [s];
      } else if (totals[s] == totals[best.first]) {
        best.add(s);
      }
    }
    if (best.length > 1) {
      final low = best.map((s) => lastDelta[s]).reduce(min);
      best = best.where((s) => lastDelta[s] == low).toList();
    }
    return best;
  }

  /// Maç sonu lig puanı (sunucudaki `rankPoints` ile aynı): sıralamaya göre 100/60/30/10.
  static const leaguePoints = [100, 60, 30, 10];

  /// Maçı kazanan koltuk(lar). Maç bitince sunucunun `final` mesajındaki değer kullanılır; ondan önce
  /// (son elin sonucu geldiği an) aynı kuralla hesaplanır.
  List<int> get winners {
    final f = _finalWinners;
    if (f != null) return f;
    if (voided) return <int>[];
    if (teamMode) {
      final t = championTeam;
      return t == null ? <int>[0, 1, 2, 3] : <int>[t, t + 2];
    }
    return _soloBest();
  }

  /// Oyun sonunda koltuğun aldığı çip (1. = havuz, 2. = giriş iadesi, diğerleri 0). Sunucu bilgi vermediyse null.
  int? chipsOf(int seat) {
    final f = _finalChips;
    return f == null || seat < 0 || seat >= f.length ? null : f[seat];
  }

  /// Net çip: aldığı eksi yatırdığı giriş (kaybedenin -giriş'i).
  int? chipNet(int seat) {
    final v = chipsOf(seat);
    return v == null ? null : v - finalEntry;
  }

  List<int> rankPoints() {
    final f = _finalPoints;
    if (f != null) return List<int>.of(f);
    final out = [0, 0, 0, 0];
    final win = winners;
    if (win.isEmpty) return out;
    if (teamMode) {
      for (var s = 0; s < 4; s++) {
        out[s] = win.contains(s) ? leaguePoints[0] : leaguePoints[2];
      }
      return out;
    }
    for (final w in win) {
      out[w] = leaguePoints[0];
    }
    final rest = [0, 1, 2, 3].where((s) => !win.contains(s)).toList()
      ..sort((a, b) => totals[a].compareTo(totals[b]));
    var pos = win.length;
    for (var k = 0; k < rest.length; k++) {
      if (k > 0 && totals[rest[k]] == totals[rest[k - 1]]) {
        out[rest[k]] = out[rest[k - 1]];
      } else {
        out[rest[k]] = leaguePoints[min(pos, 3)];
      }
      pos++;
    }
    return out;
  }

  /// Maç sonunda benim kazanacağım XP: 20 + lig puanı (asla düşmez). Hükümsüz maçta XP yoktur.
  int get myXp => voided ? 0 : 20 + rankPoints()[me];

  /// Seri açan oyuncu, masada çift açan biri varsa kendi çiftlerini çift perlerin
  /// yanına indirebilir (çapraz işleme).
  bool get canLayPairs =>
      opened[me] == OpenMode.series &&
      [1, 2, 3].any((s) => opened[s] == OpenMode.pairs);

  /// Katlamalı masada seri ile ilk açış için gereken en az sayı (sunucu bildirir; yalnız benim değerim bilinir).
  int requiredOpen(int seat) => seat == me ? _reqOpen : openLimit;

  /// Masada yazan "MİN" değeri: HERKESİN (benim açışım dahil) en yüksek seri açışından 1 fazla (en az 101).
  int get tableMinSeries {
    final v = _tableReqOpen;
    if (v != null) return v;
    var best = 0;
    for (var s = 0; s < 4; s++) {
      if (opened[s] == OpenMode.series && openScore[s] > best) best = openScore[s];
    }
    return best >= openLimit ? best + 1 : openLimit;
  }

  /// Masada yazan çift "MİN" değeri: en yüksek çift açışından 1 fazla (en az 5).
  int get tableMinPairs => _tableReqPairs ?? _reqPairs;

  /// Çiftle ilk açış için gereken en az çift sayısı (sunucu bildirir; yalnız benim değerim bilinir).
  int requiredPairs(int seat) => seat == me ? _reqPairs : minPairs;

  /// Tüm eller bitti: oyun sonucu ekranı gösterilir.
  bool get gameOver => result != null && round >= totalHands;

  /// Soldan alınan taş hâlâ ıstakada ve hiçbir şey indirilmediyse geri bırakılabilir.
  bool get canReturnDiscard =>
      canPlay &&
      pendingOpen == null &&
      !_acted &&
      mustUse != null &&
      _inRack(mustUse!);

  bool get myTurn => turn == me && result == null;
  bool get canDraw => myTurn && phase == TurnPhase.draw;
  bool get canPlay => myTurn && phase == TurnPhase.play;
  List<Tile> get myHand => rack.whereType<Tile>().toList();

  /// Elimde kalan taşların sayı toplamı (okey sayılmaz; açmış oyuncunun elinde kalan okey ayrıca +101 yazılır).
  int get myHandValue => myHand
      .fold<int>(0, (s, t) => s + (okey.isWild(t) ? 0 : tileValue(t, okey)));

  /// Elde kalan puanın el sonunda çarpanı (gösterge için): çift açtıysan 2, değilse 1.
  int get myHandMultiplier => opened[me] == OpenMode.pairs ? 2 : 1;

  int handCount(int s) => s == me ? myHand.length : _counts[s];
  Tile? topDiscard(int s) => _tops[s];

  String get statusText {
    if (result != null) return 'El bitti';
    if (turn == me) {
      if (pendingOpen != null) return 'Hatalı açış: GERİ TOPLA';
      if (phase == TurnPhase.draw) return 'Sıra sende: taş çek';
      if (mustUse != null && _inRack(mustUse!)) {
        return _acted ? 'Aldığın taşı işle' : 'Aldığın taşı kullan ya da geri bırak';
      }
      if (opened[me] == null && settings.folding && requiredOpen(me) > openLimit) {
        return 'Baraj ${requiredOpen(me)} · per diz, taş at';
      }
      return 'Per diz, taş at';
    }
    return '${names[turn]} oynuyor…';
  }

  /// Rozette gösterilecek açış bilgisi (seri: açılan sayı, çift: çift adedi).
  String? openLabel(int seat) =>
      opened[seat] == null || openedTotal[seat] <= 0 ? null : '${openedTotal[seat]}';

  String? tagOf(int seat) {
    final mode = switch (opened[seat]) {
      OpenMode.series => 'SERİ',
      OpenMode.pairs => 'ÇİFT',
      null => null,
    };
    if (teamMode && seat == partnerOf(me)) {
      return mode == null ? 'EŞİN' : 'EŞİN · $mode';
    }
    return mode;
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    Log.i('oyun', 'maç görünümü kapandı (el=$round)');
    _disposed = true;
    _warnTimer?.cancel();
    _busyTimer?.cancel();
    Sfx.I.stopCheer();
    super.dispose();
  }

  void _say(String m) {
    Log.i('oyun', 'bildirim: $m');
    toast = m;
    toastId++;
    notifyListeners();
  }

  // ------------------------------------------------------- sunucudan gelenler

  int _rel(int abs) => (((abs - _me) % 4) + 4) % 4;

  /// Mutlak koltuk sırasındaki diziyi bana göre (ben, sağ, üst, sol) çevirir.
  List<T> _byRel<T>(Object? raw, T Function(Object?) conv, T fallback) {
    final l = raw is List ? raw : const <Object?>[];
    return [
      for (var r = 0; r < 4; r++)
        ((_me + r) % 4) < l.length ? conv(l[(_me + r) % 4]) : fallback
    ];
  }

  static int _int(Object? x) => x is num ? x.toInt() : 0;

  static OpenMode? _modeOf(Object? x) =>
      x == 'series' ? OpenMode.series : (x == 'pairs' ? OpenMode.pairs : null);

  Tile? _tileOrNull(Object? x) =>
      x is Map ? Tile.fromServer(x.cast<String, dynamic>()) : null;

  /// Sunucu metinlerindeki "Koltuk 2" / "koltuk 1" ifadelerini oyuncu adına çevirir.
  String _localize(String s) => s.replaceAllMapped(RegExp(r'[Kk]oltuk (\d)'), (m) {
        final a = int.tryParse(m[1] ?? '');
        return a == null ? (m[0] ?? '') : names[_rel(a)];
      });

  /// Sunucunun `{t:'state'}` mesajı: maçın tek doğru kaynağı. Her hamleden / sıra değişiminden sonra gelir.
  void applyState(Map<String, dynamic> m) {
    if (_disposed) return;
    _busyDone();
    _me = _int(m['me']);
    final srvRound = _int(m['round']);
    final fresh = srvRound != round;

    // --- masa / koltuk adları
    final tbl = m['table'];
    if (tbl is Map) {
      names = _byRel<String>(tbl['seats'], (x) => x is String ? x : 'Bekleniyor', 'Bekleniyor');
      botSeats = _byRel<bool>(tbl['bots'], (x) => x == true, false);
    }

    // --- el değişti: temiz başla
    if (fresh) {
      Log.i('oyun', '=== yeni el (el $srvRound/$totalHands) ===');
      round = srvRound;
      result = null;
      voided = false;
      pairMode = false;
      lastDrawn = null;
      mustUse = null;
      pendingOpen = null;
      table = [];
      tileLayer.clear();
      for (var s = 0; s < 4; s++) {
        openedTotal[s] = 0;
        _tops[s] = null;
      }
      Sfx.I.stopCheer();
    }

    // --- gösterge / okey / deste
    final ok = m['okey'];
    if (ok is Map) {
      okey = Okey(_int(ok['n']), TileColor.values[_int(ok['c']) % TileColor.values.length]);
    }
    final ind = _tileOrNull(m['indicator']);
    if (ind != null) indicator = ind;
    deckCount = _int(m['deck']);

    // --- koltuğa göre diziler
    final oldPenalty = List<int>.of(penalty);
    final newOpened = _byRel<OpenMode?>(m['opened'], _modeOf, null);
    final newScore = _byRel<int>(m['openScore'], _int, 0);
    final newPenalty = _byRel<int>(m['penalty'], _int, 0);
    final newTotals = _byRel<int>(m['totals'], _int, 0);
    for (var r = 0; r < 4; r++) {
      opened[r] = newOpened[r];
      openScore[r] = newScore[r];
      penalty[r] = newPenalty[r];
      totals[r] = newTotals[r];
    }
    lastDelta = _byRel<int>(m['lastDelta'], _int, 0);
    final newCounts = _byRel<int>(m['counts'], _int, 0);
    for (var r = 0; r < 4; r++) {
      _counts[r] = newCounts[r];
    }
    _reqOpen = m['required'] is num ? _int(m['required']) : openLimit;
    _reqPairs = m['requiredPairs'] is num ? _int(m['requiredPairs']) : minPairs;
    _tableReqOpen = m['tableRequired'] is num ? _int(m['tableRequired']) : null;
    _tableReqPairs = m['tableRequiredPairs'] is num ? _int(m['tableRequiredPairs']) : null;
    _acted = m['acted'] == true;

    // --- atılan taşların en üstü (ses için eskisiyle karşılaştır)
    final newTops = _byRel<Tile?>(m['tops'], _tileOrNull, null);
    for (var r = 0; r < 4; r++) {
      if (!fresh && newTops[r]?.id != _tops[r]?.id && newTops[r] != null) {
        Sfx.I.tile(mine: r == me);
      }
      _tops[r] = newTops[r];
    }
    if (!fresh) {
      for (var r = 0; r < 4; r++) {
        if (penalty[r] > oldPenalty[r]) Sfx.I.penalty(mine: r == me);
      }
    }

    // --- masadaki perler (yalnız eklenir; işlenince yerinde büyür)
    final oldTableLen = table.length;
    final rawMelds = m['melds'];
    table = [
      if (rawMelds is List)
        for (final x in rawMelds)
          if (x is Map)
            Meld.fromServer(x.cast<String, dynamic>(), owner: _rel(_int(x['owner'])))
    ];
    for (var i = fresh ? 0 : oldTableLen; i < table.length; i++) {
      final mm = table[i];
      openedTotal[mm.owner] += mm.kind == MeldKind.pair ? 1 : mm.value;
    }
    tileLayer.clear();
    final rawLayers = m['layers'];
    if (rawLayers is Map) {
      rawLayers.forEach((k, v) {
        final id = int.tryParse('$k');
        if (id != null && v is num) tileLayer[id] = _rel(v.toInt());
      });
    }

    // --- sıra / faz
    final newTurn = _rel(_int(m['turn']));
    final srvPhase = '${m['phase']}';
    final prevPhase = phase;
    turn = newTurn;
    final hasResult = m['result'] is Map;
    if (hasResult || srvPhase == 'over') {
      phase = TurnPhase.over;
    } else if (turn == me) {
      phase = srvPhase == 'draw' ? TurnPhase.draw : TurnPhase.play;
    } else {
      phase = TurnPhase.bot;
    }
    final tok = _int(m['turnToken']);
    if (tok != turnToken || fresh) {
      turnToken = tok;
      turnDuration = Duration(seconds: turnSeconds);
      lastDrawn = null;
      _warnTimer?.cancel();
      if (turn == me && !hasResult) {
        Sfx.I.myTurn();
        _startWarnings(turnDuration);
      }
    }

    // --- ıstaka
    final hand = <Tile>[
      for (final x in (m['hand'] is List ? m['hand'] as List : const <Object?>[]))
        if (x is Map) Tile.fromServer(x.cast<String, dynamic>())
    ];
    _lastHand = hand;
    final arrived = _syncRack(hand, fresh: fresh);
    if (arrived.isNotEmpty && !fresh) {
      Sfx.I.tile(mine: true);
      if (prevPhase == TurnPhase.draw && phase == TurnPhase.play && arrived.length == 1) {
        lastDrawn = arrived.first; // desteden çekilen / soldan alınan taş işaretlenir
      }
    }
    if (phase == TurnPhase.draw) lastDrawn = null;

    // --- soldan alınan taş
    final muId = m['mustUse'];
    mustUse = null;
    if (muId is num) {
      for (final t in hand) {
        if (t.id == muId.toInt()) mustUse = t;
      }
    }

    // --- hatalı açış (taşlar sunucuda elden çıkarılmıştır, masada kırmızı bekler)
    final pd = m['pending'];
    if (pd is Map) {
      final groups = <List<Tile>>[
        for (final g in (pd['groups'] is List ? pd['groups'] as List : const <Object?>[]))
          if (g is List) [for (final t in g) if (t is Map) Tile.fromServer(t.cast<String, dynamic>())]
      ];
      final slots = <int, Tile>{};
      for (final g in groups) {
        for (final t in g) {
          final s = _lastSlot[t.id];
          if (s != null) slots[s] = t;
        }
      }
      pendingOpen = PendingOpen(
          pd['mode'] == 'pairs' ? OpenMode.pairs : OpenMode.series,
          groups,
          slots,
          _localize('${pd['reason'] ?? ''}'));
    } else {
      pendingOpen = null;
    }

    // --- el sonucu
    final rs = m['result'];
    if (rs is Map) {
      final w = rs['winner'];
      voided = rs['voided'] == true;
      result = RoundResult(
        w is num ? _rel(w.toInt()) : null,
        _byRel<int>(rs['delta'], _int, 0),
        _byRel<OpenMode?>(rs['modes'], _modeOf, null),
        _localize('${rs['note'] ?? ''}'),
        deckOut: rs['deckOut'] == true,
        voided: voided,
      );
      if (_historyRound != round) {
        _historyRound = round;
        history.add(List<int>.of(result!.delta));
        _recordStats(
            winner: result!.winner,
            joker: rs['joker'] == true,
            elden: rs['elden'] == true,
            winnerMode: result!.winner == null ? null : result!.modes[result!.winner!]);
        final win = result!.winner;
        if (win != null && (win == me || (teamMode && win == partnerOf(me)))) {
          Sfx.I.cheer(okey: rs['joker'] == true, mine: win == me);
        }
      }
    } else {
      result = null;
      _finalChips = null; // oyun sürüyor: önceki maçın çip sonucu bayat
    }

    notifyListeners();
  }

  /// Sunucudan gelen bilgi mesajı (`{t:'say'}`): bildirim olarak gösterilir.
  void applySay(String m) {
    if (_disposed) return;
    _say(_localize(m));
  }

  /// Sunucunun `{t:'err'}` cevabı (ör. "Sıra sende değil."): hamle olmadı; ıstaka sunucudaki gibi geri kurulur.
  void applyError(String m) {
    if (_disposed) return;
    _busyDone();
    _wantSlot = null;
    _syncRack(_lastHand, fresh: false);
    _say(_localize(m));
  }

  /// Maç bitti (`{t:'final'}`): kazananlar ve lig puanları sunucudan kesin olarak gelir.
  void applyFinal(Map<String, dynamic> m) {
    if (_disposed) return;
    final win = m['winners'];
    _finalWinners = win is List ? [for (final w in win) _rel(_int(w))] : null;
    _finalPoints = m['points'] is List ? _byRel<int>(m['points'], _int, 0) : null;
    _finalChips = m['chipsSeat'] is List ? _byRel<int>(m['chipsSeat'], _int, 0) : null;
    finalEntry = _int(m['entry']);
    finalPot = _int(m['pot']);
    finalRefunded = m['refunded'] == true;
    voided = m['voided'] == true || voided;
    final hist = m['history'];
    if (hist is List) {
      history
        ..clear()
        ..addAll([for (final h in hist) _byRel<int>(h, _int, 0)]);
    }
    notifyListeners();
  }

  void _busyDone() {
    _busy = false;
    _busyTimer?.cancel();
  }

  /// Hamleyi yollar. Cevap (state/err) gelene kadar ikinci hamle yollanmaz; bağlantı yoksa uyarır.
  bool _sendMove(Map<String, dynamic> msg) {
    if (_busy) {
      Log.d('oyun', 'hamle bekletildi (önceki cevap gelmedi): ${msg['t']}');
      return false;
    }
    if (!_send(msg)) {
      _say('Sunucuya bağlı değilsin, hamle gönderilemedi.');
      return false;
    }
    _busy = true;
    _busyTimer?.cancel();
    _busyTimer = Timer(const Duration(seconds: 2), () => _busy = false);
    return true;
  }

  /// Son 10 saniyede her saniye tık, son 3 saniyede acil çift bip. (Süre dolunca oyunu SUNUCU oynatır.)
  void _startWarnings(Duration total) {
    _warnTimer?.cancel();
    final sw = Stopwatch()..start();
    _warnTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_disposed || result != null || turn != me) {
        t.cancel();
        return;
      }
      final left = ((total - sw.elapsed).inMilliseconds / 1000).round();
      if (left <= 0) {
        t.cancel();
      } else if (left <= 10) {
        Sfx.I.warn(urgent: left <= 3);
      }
    });
  }

  /// Aynı el iki kez kaydedilmesin; hata oyunu asla etkilemez. Hükümsüz eller sayılmaz.
  void _recordStats({int? winner, bool joker = false, bool elden = false, OpenMode? winnerMode}) {
    if (voided) return;
    try {
      unawaited(PlayerStats.I.recordHand(
        iWon: winner == me,
        okey: joker,
        elden: elden,
        pairs: winnerMode == OpenMode.pairs,
        myDelta: lastDelta[me],
      ));
      if (round >= totalHands) {
        unawaited(PlayerStats.I.recordMatch(won: winners.contains(me)));
      }
    } catch (e) {
      Log.w('istatistik', 'kaydedilemedi: $e');
    }
  }

  /// Sunucu eli yeni el için hazırlar; ekran "SONRAKİ EL" dese de sunucu eller arası beklemeyi kendisi yönetir
  /// (8 sn sonra yeni `state` gelir), burada yapılacak bir şey yok.
  void newRound() {}

  // ---------------------------------------------------------- ıstaka

  bool _inRack(Tile t) => rack.any((x) => x?.id == t.id);

  void _removeFromRack(Tile t) {
    final i = rack.indexWhere((x) => x?.id == t.id);
    if (i >= 0) {
      _lastSlot[t.id] = i;
      rack[i] = null;
    } else {
      Log.w('ıstaka', '${logTile(t)} ıstakada bulunamadı (silinemedi)');
    }
  }

  /// Sunucudaki el ile ıstakayı uzlaştırır: elden çıkan taşlar yuvasından kalkar (yuvası hatırlanır),
  /// gelen taşlar istenen / eski yuvaya, yoksa ilk boş yuvaya konur. Yeni elde ıstaka baştan kurulur.
  /// Yeni gelen taşları döner.
  List<Tile> _syncRack(List<Tile> hand, {required bool fresh}) {
    if (fresh) {
      rack = List<Tile?>.filled(rackSize, null);
      _lastSlot.clear();
      _wantSlot = null;
    }
    final ids = {for (final t in hand) t.id};
    for (var i = 0; i < rackSize; i++) {
      final t = rack[i];
      if (t != null && !ids.contains(t.id)) {
        _lastSlot[t.id] = i;
        rack[i] = null;
      }
    }
    final have = {for (final t in rack) if (t != null) t.id};
    final incoming = [for (final t in hand) if (!have.contains(t.id)) t];
    final want = _wantSlot;
    _wantSlot = null;
    for (final t in incoming) {
      int? slot;
      if (want != null && incoming.length == 1 && want >= 0 && want < rackSize && rack[want] == null) {
        slot = want;
      }
      final old = _lastSlot[t.id];
      if (slot == null && old != null && old >= 0 && old < rackSize && rack[old] == null) {
        slot = old;
      }
      slot ??= rack.indexWhere((x) => x == null);
      if (slot >= 0) {
        rack[slot] = t;
        _lastSlot.remove(t.id);
      } else {
        Log.e('ıstaka', 'ISTAKA DOLU: ${logTile(t)} yerleştirilemedi');
      }
    }
    return fresh ? const <Tile>[] : incoming;
  }

  void moveRack(int from, int to) {
    Log.d('ıstaka', 'taş taşındı: yuva $from → $to');
    if (from < 0 || to < 0 || from >= rackSize || to >= rackSize) {
      Log.e('ıstaka', 'geçersiz taşıma: yuva $from → $to (0..${rackSize - 1} olmalı)');
      return;
    }
    if (from == to) return;
    // Takas yok: hedefte taş varsa komşular kayıp yer açar, taş araya girer.
    rack = RackShift.move(rack, cols, from, to);
    notifyListeners();
  }

  /// Bir kalıbı (yan yana duran per/çift) bütün olarak taşır: [from] yuvalarındaki taşlar sırasıyla [to] yuvalarına gider.
  /// Hedefte başka taşlar varsa, kalıbın boşalttığı yuvalara sırayla yerleşirler (taş kaybolmaz).
  void moveRackGroup(List<int> from, List<int> to) {
    if (from.isEmpty || from.length != to.length) return;
    for (final i in [...from, ...to]) {
      if (i < 0 || i >= rackSize) {
        Log.e('ıstaka', 'geçersiz kalıp taşıma: $from → $to');
        return;
      }
    }
    if (to.toSet().length != to.length || from.toSet().length != from.length) return;
    var same = true;
    for (var k = 0; k < from.length; k++) {
      if (from[k] != to[k]) same = false;
    }
    if (same) return;
    final fs = from.toSet(), ts = to.toSet();
    final moving = [for (final i in from) rack[i]];
    final displaced = <Tile>[for (final i in to) if (!fs.contains(i) && rack[i] != null) rack[i]!];
    final vacated = [for (final i in from) if (!ts.contains(i)) i];
    for (final i in from) {
      rack[i] = null;
    }
    for (final i in to) {
      rack[i] = null;
    }
    for (var k = 0; k < to.length; k++) {
      rack[to[k]] = moving[k];
    }
    for (var k = 0; k < displaced.length && k < vacated.length; k++) {
      rack[vacated[k]] = displaced[k];
    }
    Log.d('ıstaka', 'kalıp taşındı: $from → $to (yerinden edilen=${displaced.length})');
    notifyListeners();
  }

  void arrangeSeries() {
    Log.i('ıstaka', 'SERİ DİZ');
    rack = RackArranger.seriDiz(rack, cols, okey);
    pairMode = false;
    notifyListeners();
  }

  void arrangePairs() {
    Log.i('ıstaka', 'ÇİFT DİZ');
    rack = RackArranger.ciftDiz(rack, cols, okey);
    pairMode = true;
    notifyListeners();
  }

  // ------------------------------------------------------- insan hamleleri
  // Hepsi sunucuya gider; sonuç `state` mesajıyla gelir. Kural denetimini sunucu yapar, hata metni [applyError] ile gösterilir.

  void drawFromDeck({int? slot}) {
    Log.i('oyun', 'desteden çek isteği (çekebilir=$canDraw deste=$deckCount yuva=$slot)');
    if (!canDraw) {
      Log.w('oyun', 'çekme REDDEDİLDİ: sıra=$turn faz=${phase.name} sonuç=${result != null}');
      return;
    }
    final prev = _wantSlot;
    _wantSlot = slot;
    if (!_sendMove({'t': 'draw'})) _wantSlot = prev;
  }

  void takeDiscard({int? slot}) {
    Log.i('oyun', 'soldan taş al isteği (çekebilir=$canDraw üstteki=${logTile(topDiscard(3))})');
    if (!canDraw) {
      Log.w('oyun', 'soldan alma REDDEDİLDİ: sıra=$turn faz=${phase.name} sonuç=${result != null}');
      return;
    }
    if (topDiscard(3) == null) {
      _say('Soldaki oyuncu henüz taş atmadı.');
      return;
    }
    // Taş her zaman alınabilir; kullanamazsan GERİ BIRAK ile iade edersin (süre dolarsa sunucu iade eder).
    final prev = _wantSlot;
    _wantSlot = slot;
    if (!_sendMove({'t': 'take'})) _wantSlot = prev;
  }

  /// GERİ BIRAK: soldan alınan taşı kullanamayan oyuncu taşı iade eder (ceza yok).
  void returnDiscard() {
    Log.i('oyun', 'GERİ BIRAK isteği (olabilir=$canReturnDiscard)');
    if (!canReturnDiscard) {
      if (canPlay && mustUse != null && _inRack(mustUse!)) {
        _say('Per açtığın için taşı geri bırakamazsın.');
      }
      return;
    }
    _sendMove({'t': 'back'});
  }

  /// GERİ TOPLA: hatalı açılan perler ıstakaya (eski yuvalarına) döner, +101 ceza yazılır ve taş atılabilir.
  void collectPending() {
    Log.i('oyun', 'GERİ TOPLA isteği (bekleyen=${pendingOpen != null})');
    if (!canPlay) return;
    _sendMove({'t': 'collect'});
  }

  bool _blockedByPending() {
    if (pendingOpen == null) return false;
    _say('Önce GERİ TOPLA ile hatalı açtığın taşları al.');
    return true;
  }

  List<List<int>> _ids(List<List<Tile>> groups) => [
        for (final g in groups) [for (final t in g) t.id]
      ];

  /// SERİ AÇ: ıstakada yan yana duran geçerli küt/serileri sunucuya yollar (baraj, elden bitirme, hatalı açış sunucuda).
  void openSeries() {
    Log.i('oyun', 'SERİ AÇ isteği: balon=${HandScorer.score(rack, cols, okey)} gerekli=${requiredOpen(me)} oynayabilir=$canPlay');
    if (!canPlay || _blockedByPending()) return;
    final series = HandScorer.validSeries(rack, cols, okey);
    if (series.isEmpty) {
      _say('Istakada geçerli seri/küt yok. Taşları aralarında boşluk bırakarak diz.');
      return;
    }
    _sendMove({'t': 'openSeries', 'groups': _ids(series)});
  }

  /// ÇİFT AÇ: yan yana duran geçerli çiftleri sunucuya yollar (ilk açışta en az 5 çift; katlamalı masada daha fazla).
  void openPairs() {
    Log.i('oyun', 'ÇİFT AÇ isteği: çift=${HandScorer.pairCount(rack, cols, okey)} oynayabilir=$canPlay');
    if (!canPlay || _blockedByPending()) return;
    final pairs = HandScorer.validPairs(rack, cols, okey);
    if (pairs.isEmpty) {
      _say('Istakada yan yana geçerli çift yok.');
      return;
    }
    _sendMove({'t': 'openPairs', 'groups': _ids(pairs)});
  }

  /// Taşı masadaki bir pere işler. [meldIndex] verilmezse sunucu uygun ilk peri (ya da okey çalmayı) seçer.
  /// [front] seride okey için başa (true) / sona (false) ekleme tercihidir.
  void layOff(Tile tile, {int? meldIndex, bool? front}) {
    Log.i('oyun', 'İŞLE isteği: taş=${logTile(tile)} per=$meldIndex ön=$front');
    if (!canPlay) {
      Log.w('oyun', 'işleme REDDEDİLDİ: faz=${phase.name} sıra=$turn');
      return;
    }
    if (_blockedByPending()) return;
    if (!_inRack(tile)) {
      Log.e('oyun', 'işlenmek istenen ${logTile(tile)} ıstakada yok (eski seçim?)');
      return;
    }
    if (opened[me] == null) {
      _say('Önce elini açmalısın.');
      return;
    }
    _sendMove({
      't': 'lay',
      'id': tile.id,
      if (meldIndex != null) 'meld': meldIndex,
      if (front != null) 'front': front,
    });
  }

  /// OTO İŞLE: işlenebilen tüm taşları (okey çalma dahil) sunucu işler; atmak için en az bir taş elde kalır.
  void autoLayOff() {
    Log.i('oyun', 'OTO İŞLE isteği');
    if (!canPlay) {
      Log.w('oyun', 'oto işle REDDEDİLDİ: faz=${phase.name} sıra=$turn');
      return;
    }
    if (_blockedByPending()) return;
    if (opened[me] == null) {
      _say('Önce elini açmalısın.');
      return;
    }
    _sendMove({'t': 'autolay'});
  }

  void discard(Tile tile) {
    Log.i('oyun', 'AT isteği: taş=${logTile(tile)} oynayabilir=$canPlay');
    if (!canPlay) {
      Log.w('oyun', 'atma REDDEDİLDİ: faz=${phase.name} sıra=$turn sonuç=${result != null}');
      return;
    }
    if (_blockedByPending()) return;
    if (!_inRack(tile)) {
      Log.e('oyun', 'atılmak istenen ${logTile(tile)} ıstakada yok (eski seçim?)');
      return;
    }
    final mu = mustUse;
    if (mu != null && _inRack(mu)) {
      _say(_acted
          ? 'Soldan aldığın taşı kullanmadan taş atamazsın.'
          : 'Soldan aldığın taşı kullan ya da GERİ BIRAK.');
      return;
    }
    if (!_sendMove({'t': 'discard', 'id': tile.id})) return;
    // Taş hemen ıstakadan kalkar (sunucu cevabı gelene kadar beklemek takılma gibi hissettirir).
    // Sunucu reddederse [applyError] ıstakayı eski hâline getirir.
    _removeFromRack(tile);
    notifyListeners();
  }
}
