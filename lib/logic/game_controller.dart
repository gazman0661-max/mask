import 'dart:async';
import '../diagnostics/app_log.dart';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/table_models.dart';
import '../services/sfx.dart';
import '../models/tile.dart';
import 'hand_scorer.dart';
import 'meld.dart';
import 'okey_rules.dart';
import 'rack_arranger.dart';
import 'rack_shift.dart';
import 'scoring.dart';

enum OpenMode { series, pairs }

enum TurnPhase { draw, play, bot, over }

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

/// 101 Okey oyun motoru (3 bilgisayara karşı). Koltuklar:
/// 0 = ben, 1 = sağ, 2 = üst, 3 = sol. Sıra: sol -> ben -> sağ -> üst -> sol.
class GameController extends ChangeNotifier {
  static const int me = 0;
  static const int cols = 16;
  static const int rackSize = 32;
  static const int openLimit = 101;
  static const int penaltyPoints = 101;
  static const int minPairs = 5;

  final List<String> names;
  final int turnSeconds;
  final TableSettings settings;
  final Random _rng;

  int get totalHands => settings.hands;

  GameController(
      {required this.names,
      this.turnSeconds = 30,
      this.settings = const TableSettings(),
      int? seed})
      : _rng = seed == null ? Random() : Random(seed) {
    // Sunucuyla aynı: ilk elde başlayan rastgele. Tohum verilirse (testler) hep ben başlarım.
    if (seed == null) _starter = _rng.nextInt(4) - 1;
    newRound();
  }

  late Okey okey;
  late Tile indicator;
  List<Tile> deck = [];
  List<Tile?> rack = List<Tile?>.filled(rackSize, null);
  final List<List<Tile>> _hands = List.generate(4, (_) => <Tile>[]);
  final List<List<Tile>> discards = List.generate(4, (_) => <Tile>[]);
  List<Meld> table = [];

  /// Masadaki taşı kimin koyduğu (taş id → koltuk). Per sahibi ilk açan olduğu için,
  /// başkasının perine işleyen oyuncunun animasyonu doğru koltuktan çıksın diye tutulur.
  final Map<int, int> tileLayer = {};
  final List<OpenMode?> opened = List<OpenMode?>.filled(4, null);

  /// Seri ile açanların açış puanı (katlamalı masada baraj hesabı için).
  final List<int> openScore = List<int>.filled(4, 0);

  /// Çiftle ilk açışta açılan çift sayısı (katlamalı masada baraj hesabı için).
  final List<int> openPairCount = List<int>.filled(4, 0);

  final List<int> penalty = List<int>.filled(4, 0);

  /// Oyuncunun masaya açtığı toplam: seri açanda sayı, çift açanda çift adedi
  /// (oyuncu rozetinde gösterilir).
  final List<int> openedTotal = List<int>.filled(4, 0);
  final List<int> totals = List<int>.filled(4, 0);

  /// Son bitmiş elin puan değişimi (beraberlik bozmak için).
  List<int> lastDelta = List<int>.filled(4, 0);

  /// Bitmiş eller: her elin koltuk başına puan değişimi (oyun sonucu ekranı).
  final List<List<int>> history = [];

  /// Soldan alınan taştan sonra bu turda masaya bir şey açıldı/işlendi mi?
  /// Evetse taş artık geri bırakılamaz (çekmeden önce per indirmek olmaz).
  bool _acted = false;

  /// Hatalı açış bekliyor (GERİ TOPLA gerekli).
  PendingOpen? pendingOpen;
  bool get hasPendingOpen => pendingOpen != null;

  /// Bilgisayarın soldan aldığı ve bu turda kullanması gereken taş.
  Tile? _botMustUse;

  int round = 0;
  int turn = 0;
  TurnPhase phase = TurnPhase.draw;
  bool pairMode = false;
  Tile? mustUse; // soldan alınan, hemen kullanılması gereken taş
  Tile? lastDrawn;
  RoundResult? result;

  /// Hükümsüz el/maç: tek elli oyunda kimse el açamadan deste bitti ya da herkes
  /// çift açtı. Kazanan yok, puan ve XP yok (sunucudaki `voided`).
  bool voided = false;

  String? toast;
  int toastId = 0;
  int turnToken = 0;
  Duration turnDuration = const Duration(seconds: 30);

  int _starter = -1;
  int _gen = 0;
  int? _eldenSeat;
  bool _disposed = false;
  Timer? _timer;
  Timer? _warnTimer; // süre azalırken uyarı sesleri

  // ---------------------------------------------------------------- durum

  // ------------------------------------------------------------- takım

  bool get teamMode => settings.team;

  /// Karşılıklı oturanlar eştir: 0-2 ve 1-3.
  static int partnerOf(int seat) => (seat + 2) % 4;
  static int teamOf(int seat) => seat % 2;

  int teamTotal(int team) =>
      totals[team] + totals[team + 2]; // 0: ben+üst, 1: sağ+sol

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

  /// Tekli oyunda kazanan koltuk(lar): toplamı en düşük, eşitlikte son el puanı
  /// en düşük olanlar. Birden fazlaysa tam beraberlik vardır.
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
  /// Eşlide kazanan takım 100, kaybeden 30. Beraberlikte aynı puan. Kimse puan kaybetmez.
  static const leaguePoints = [100, 60, 30, 10];

  /// Maçı kazanan koltuk(lar) (sunucudaki `winners()` ile aynı): hükümsüz maçta
  /// kimse; eşlide tam beraberlikte dört koltuk; tekli beraberlikte eşit olanlar.
  List<int> get winners {
    if (voided) return <int>[];
    if (teamMode) {
      final t = championTeam;
      return t == null ? <int>[0, 1, 2, 3] : <int>[t, t + 2];
    }
    return _soloBest();
  }

  List<int> rankPoints() {
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
    var pos = winners.length;
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

  /// Maç sonunda benim kazanacağım XP: 20 + lig puanı (asla düşmez).
  /// Hükümsüz maçta XP yoktur (sunucu yalnız puan yazılan oyuncuya XP verir).
  int get myXp => voided ? 0 : 20 + rankPoints()[me];

  /// Seri açan oyuncu, masada çift açan biri varsa kendi çiftlerini çift perlerin
  /// yanına indirebilir (çapraz işleme).
  bool get canLayPairs =>
      opened[me] == OpenMode.series &&
      [1, 2, 3].any((s) => opened[s] == OpenMode.pairs);

  /// Katlamalı masada seri ile ilk açış için gereken en az sayı. Masada daha
  /// önce biri seri açtıysa onun açış puanından en az 1 fazla gerekir (ilk
  /// açan 101 ile açar). Çift için bkz. [requiredPairs].
  int requiredOpen(int seat) {
    if (!settings.folding) return openLimit;
    var best = 0;
    for (var s = 0; s < 4; s++) {
      if (s == seat) continue;
      if (opened[s] == OpenMode.series && openScore[s] > best) {
        best = openScore[s];
      }
    }
    return best >= openLimit ? best + 1 : openLimit;
  }

  /// Çiftle ilk açış için gereken en az çift sayısı: normalde 5; katlamalı
  /// masada daha önce biri çift açtıysa onun çift sayısından en az 1 fazla.
  int requiredPairs(int seat) {
    if (!settings.folding) return minPairs;
    var best = 0;
    for (var s = 0; s < 4; s++) {
      if (s == seat) continue;
      if (opened[s] == OpenMode.pairs && openPairCount[s] > best) {
        best = openPairCount[s];
      }
    }
    return best >= minPairs ? best + 1 : minPairs;
  }

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
  List<Tile> _handOf(int s) => s == me ? myHand : _hands[s];
  /// Elimde kalan taşların sayı toplamı (okey sayılmaz; açmış oyuncunun elinde kalan okey ayrıca +101 yazılır).
  int get myHandValue => _handValue(me);

  /// Elde kalan puanın el sonunda çarpanı (gösterge için): çift açtıysan 2, değilse 1.
  /// (Eli okeyle ya da elden biri bitirirse çarpan iki katına çıkar; bu sonradan belli olur.)
  int get myHandMultiplier => opened[me] == OpenMode.pairs ? 2 : 1;

  int handCount(int s) => s == me ? myHand.length : _hands[s].length;
  Tile? topDiscard(int s) => discards[s].isEmpty ? null : discards[s].last;

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
    Log.i('oyun', 'oyun motoru kapandı (el=$round)');
    _disposed = true;
    _timer?.cancel();
    _warnTimer?.cancel();
    Sfx.I.stopCheer();
    super.dispose();
  }

  void _say(String m) {
    Log.i('oyun', 'bildirim: $m');
    toast = m;
    toastId++;
    notifyListeners();
  }

  // ----------------------------------------------------------------- el

  void newRound() {
    Log.i('oyun', '=== yeni el başlıyor (el ${round + 1}/$totalHands) eşli=${settings.team} katlamalı=${settings.folding} yardımlı=${settings.assisted} ===');
    _gen++;
    _timer?.cancel();
    _warnTimer?.cancel();
    Sfx.I.stopCheer();
    round++;
    result = null;
    voided = false;
    mustUse = null;
    lastDrawn = null;
    pairMode = false;
    table = [];
    tileLayer.clear();
    _eldenSeat = null;
    _acted = false;
    pendingOpen = null;
    for (var s = 0; s < 4; s++) {
      _hands[s].clear();
      discards[s].clear();
      opened[s] = null;
      openScore[s] = 0;
      openPairCount[s] = 0;
      openedTotal[s] = 0;
      penalty[s] = 0;
    }
    rack = List<Tile?>.filled(rackSize, null);

    final tiles = <Tile>[];
    var id = 0;
    for (final c in TileColor.values) {
      for (var n = 1; n <= 13; n++) {
        for (var k = 0; k < 2; k++) {
          tiles.add(Tile(id: id++, number: n, color: c));
        }
      }
    }
    tiles.add(Tile.fake(id++));
    tiles.add(Tile.fake(id++));
    tiles.shuffle(_rng);

    final idx = tiles.indexWhere((t) => !t.isFakeJoker);
    indicator = tiles.removeAt(idx);
    okey = Okey.fromIndicator(indicator);
    Log.i('oyun', 'gösterge=${logTile(indicator)} okey=${okey.number}${okey.color.name}');

    _starter = (_starter + 1) % 4;
    for (var s = 0; s < 4; s++) {
      final n = s == _starter ? 22 : 21;
      final hand = tiles.sublist(0, n);
      tiles.removeRange(0, n);
      if (s == me) {
        for (var i = 0; i < hand.length; i++) {
          rack[i] = hand[i];
        }
      } else {
        _hands[s].addAll(hand);
      }
    }
    deck = tiles;
    turn = _starter;
    Log.i('oyun', 'dağıtım: deste=${deck.length} eller=${[for (var s = 0; s < 4; s++) handCount(s)]} başlayan=koltuk $_starter');
    _beginTurn(skipDraw: true);
  }

  void _beginTurn({bool skipDraw = false}) {
    Log.d('oyun', 'sıra → koltuk $turn (${names[turn]}) skipDraw=$skipDraw deste=${deck.length} eldeki=${handCount(turn)}');
    _timer?.cancel();
    _warnTimer?.cancel();
    turnToken++;
    mustUse = null;
    lastDrawn = null;
    _acted = false;
    pendingOpen = null;
    if (turn == me) {
      phase = skipDraw ? TurnPhase.play : TurnPhase.draw;
      turnDuration = Duration(seconds: turnSeconds);
      _timer = Timer(turnDuration, _onTimeout);
      _startWarnings(turnDuration);
      Sfx.I.myTurn();
    } else {
      phase = TurnPhase.bot;
      turnDuration = const Duration(milliseconds: 2600);
      final seat = turn, gen = _gen;
      Future.delayed(const Duration(milliseconds: 800),
          () => _botTurn(seat, gen, skipDraw).catchError((Object e, StackTrace st) {
                Log.e('bot', 'bot hamlesi ÇÖKTÜ (koltuk $seat)', e, st);
              }));
    }
    _audit('sıra başı');
    notifyListeners();
  }

  void _advance() {
    turn = (turn + 1) % 4;
    _beginTurn();
  }

  /// Son 10 saniyede her saniye tık, son 3 saniyede acil çift bip.
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

  void _onTimeout() {
    _warnTimer?.cancel();
    if (_disposed || result != null || turn != me) return;
    Log.w('oyun', 'SÜRE DOLDU: koltuk $me faz=${phase.name}');
    _autoPlay();
  }

  // ---------------------------------------------------------- ıstaka

  bool _inRack(Tile t) => rack.any((x) => x?.id == t.id);

  void _putInRack(Tile t, [int? slot]) {
    if (slot != null && slot >= 0 && slot < rackSize && rack[slot] == null) {
      rack[slot] = t;
      return;
    }
    final i = rack.indexWhere((x) => x == null);
    if (i >= 0) {
      if (slot != null) {
        Log.d('ıstaka', 'istenen yuva $slot dolu/geçersiz; ${logTile(t)} yuva $i içine kondu');
      }
      rack[i] = t;
    } else {
      Log.e('ıstaka', 'ISTAKA DOLU: ${logTile(t)} yerleştirilemedi, taş kayboldu');
    }
  }

  void _removeFromRack(Tile t) {
    final i = rack.indexWhere((x) => x?.id == t.id);
    if (i >= 0) {
      rack[i] = null;
    } else {
      Log.w('ıstaka', '${logTile(t)} ıstakada bulunamadı (silinemedi)');
    }
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

  void drawFromDeck({int? slot}) {
    Log.i('oyun', 'desteden çek isteği (çekebilir=$canDraw deste=${deck.length} yuva=$slot)');
    if (!canDraw) {
      Log.w('oyun', 'çekme REDDEDİLDİ: sıra=$turn faz=${phase.name} sonuç=${result != null}');
      return;
    }
    if (deck.isEmpty) {
      _endDeckOut('Çekilecek taş kalmadı.');
      return;
    }
    final t = deck.removeLast();
    _putInRack(t, slot);
    lastDrawn = t;
    phase = TurnPhase.play;
    Log.i('oyun', 'desteden çekildi: ${logTile(t)} kalan deste=${deck.length} eldeki=${myHand.length}');
    _audit('desteden çek');
    Sfx.I.tile(mine: true);
    notifyListeners();
  }

  void takeDiscard({int? slot}) {
    Log.i('oyun', 'soldan taş al isteği (çekebilir=$canDraw üstteki=${logTile(topDiscard(3))})');
    if (!canDraw) {
      Log.w('oyun', 'soldan alma REDDEDİLDİ: sıra=$turn faz=${phase.name} sonuç=${result != null}');
      return;
    }
    final t = topDiscard(3);
    if (t == null) {
      _say('Soldaki oyuncu henüz taş atmadı.');
      return;
    }
    // Taş her zaman alınabilir; kullanamazsan GERİ BIRAK ile iade edersin
    // (süre dolarsa otomatik iade edilir).
    discards[3].removeLast();
    _putInRack(t, slot);
    mustUse = t;
    lastDrawn = t;
    _acted = false;
    phase = TurnPhase.play;
    Log.i('oyun', 'soldan alındı: ${logTile(t)} (kullanma zorunlu) eldeki=${myHand.length}');
    _audit('soldan al');
    Sfx.I.tile(mine: true);
    notifyListeners();
  }

  /// GERİ BIRAK: soldan alınan taşı kullanamayan oyuncu taşı iade eder; taş
  /// soldaki atık yığınına döner ve sıra yeniden çekme aşamasına geçer
  /// (ceza yok). Süre bundan etkilenmez.
  void returnDiscard() {
    Log.i('oyun', 'GERİ BIRAK isteği (olabilir=$canReturnDiscard)');
    if (!canReturnDiscard) {
      if (canPlay && mustUse != null && _inRack(mustUse!)) {
        _say('Per açtığın için taşı geri bırakamazsın.');
      }
      return;
    }
    final t = mustUse!;
    _removeFromRack(t);
    discards[3].add(t);
    mustUse = null;
    lastDrawn = null;
    phase = TurnPhase.draw;
    Log.i('oyun', 'soldan alınan ${logTile(t)} geri bırakıldı');
    _say('Taş geri bırakıldı. Desteden çek.');
    _audit('geri bırak');
    notifyListeners();
  }

  /// Hatalı açış (baraj geçilmedi / 5 çift yok): perler masaya konur ama
  /// geçersizdir; oyuncu GERİ TOPLA'ya basana kadar taş atamaz. Ceza geri
  /// toplarken yazılır.
  void _stageFailedOpen(List<List<Tile>> groups, OpenMode mode, String msg) {
    Log.w('oyun', 'açma BAŞARISIZ (perler masada bekliyor): $msg');
    final slots = <int, Tile>{};
    for (final g in groups) {
      for (final t in g) {
        final i = rack.indexWhere((x) => x?.id == t.id);
        if (i >= 0) {
          slots[i] = t;
          rack[i] = null;
        }
      }
    }
    pendingOpen = PendingOpen(
        mode, groups.map((g) => List<Tile>.of(g)).toList(), slots, msg);
    _say('$msg GERİ TOPLA ile taşları al.');
    _audit('hatalı açış');
    notifyListeners();
  }

  /// GERİ TOPLA: hatalı açılan perler ıstakaya (eski yuvalarına) döner,
  /// +101 ceza yazılır ve taş atılabilir.
  void collectPending() {
    Log.i('oyun', 'GERİ TOPLA isteği (bekleyen=${pendingOpen != null})');
    if (!canPlay) return;
    _collectPending();
    notifyListeners();
  }

  void _collectPending() {
    final p = pendingOpen;
    if (p == null) return;
    p.slots.forEach((slot, t) => _putInRack(t, slot));
    pendingOpen = null;
    penalty[me] += penaltyPoints;
    Sfx.I.penalty(mine: true);
    Log.w('oyun', 'CEZA +101 (hatalı açış): koltuk $me (toplam ceza=${penalty[me]})');
    _say('${p.reason} +101 ceza. Şimdi taş atabilirsin.');
    _audit('geri topla');
  }

  bool _blockedByPending() {
    if (pendingOpen == null) return false;
    _say('Önce GERİ TOPLA ile hatalı açtığın taşları al.');
    return true;
  }

  /// SERİ AÇ: ıstakada yan yana duran geçerli küt/serileri masaya açar.
  /// İlk açışta toplam >= baraj (elden bitirmede baraj aranmaz). Açtıktan
  /// sonra aynı düğme (SERİ AÇ) yeni perleri baraj olmadan açar.
  void openSeries() {
    Log.i('oyun', 'SERİ AÇ isteği: balon=${HandScorer.score(rack, cols, okey)} gerekli=${requiredOpen(me)} oynayabilir=$canPlay');
    if (!canPlay || _blockedByPending()) return;
    if (opened[me] == OpenMode.pairs) {
      _say('Çift açtın; yeni seri/küt açamazsın.');
      return;
    }
    final hand = myHand;
    final series = HandScorer.validSeries(rack, cols, okey);
    if (series.isEmpty) {
      _say('Istakada geçerli seri/küt yok. Taşları aralarında boşluk '
          'bırakarak diz.');
      return;
    }
    final inGroups = series.fold<int>(0, (s, g) => s + g.length);
    final sum = series.fold<int>(0, (s, g) => s + GroupRules.valueOf(g, okey));
    final first = opened[me] == null;
    // Soldan alınan taş açılan perlerde değilse ceza yazmadan uyar.
    if (first && !_usesMustTile(series)) return;
    var elden = false;
    if (first) {
      final need = requiredOpen(me);
      final goOut = hand.length - inGroups == 1; // elden bitirme
      if (sum < need && !goOut) {
        _stageFailedOpen(
            series, OpenMode.series, 'Seri açmak için $need sayı gerekir (şimdi: $sum).');
        return;
      }
      elden = goOut && [1, 2, 3].every((s) => opened[s] == null);
    }
    if (inGroups >= hand.length) {
      _say('Elinde atacak bir taş kalmalı.');
      return;
    }
    _openGroups(me, series, OpenMode.series, elden: elden);
    _afterMyOpen();
  }

  /// ÇİFT AÇ: yan yana duran geçerli çiftleri açar (ilk açışta en az 5 çift;
  /// katlamalı masada önceki çift açıştan 1 fazla, bkz. [requiredPairs]).
  /// Açtıktan sonra aynı düğme (ÇİFT AÇ) yeni çiftleri açar.
  void openPairs() {
    Log.i('oyun', 'ÇİFT AÇ isteği: çift=${HandScorer.pairCount(rack, cols, okey)} oynayabilir=$canPlay');
    if (!canPlay || _blockedByPending()) return;
    final cross = opened[me] == OpenMode.series;
    if (cross && !canLayPairs) {
      _say('Seri açtın; masada çift açan yoksa çift açamazsın.');
      return;
    }
    final hand = myHand;
    final pairs = HandScorer.validPairs(rack, cols, okey);
    final first = opened[me] == null;
    if (first && pairs.isNotEmpty && !_usesMustTile(pairs)) return;
    if (pairs.isEmpty) {
      _say('Istakada yan yana geçerli çift yok.');
      return;
    }
    if (first && pairs.length < requiredPairs(me)) {
      _stageFailedOpen(pairs, OpenMode.pairs,
          'Çift açmak için ${requiredPairs(me)} çift gerekir (şimdi: ${pairs.length}).');
      return;
    }
    if (pairs.length * 2 >= hand.length) {
      _say('Elinde atacak bir taş kalmalı.');
      return;
    }
    _openGroups(me, pairs, OpenMode.pairs, keepMode: cross);
    _afterMyOpen();
  }

  /// Soldan alınan taş ilk açışta açılan perlerde bulunmalı.
  bool _usesMustTile(List<List<Tile>> groups) {
    final mu = mustUse;
    if (mu == null || !_inRack(mu)) return true;
    if (groups.any((g) => g.any((t) => t.id == mu.id))) return true;
    _say('Soldan aldığın taş açtığın perlerde olmalı.');
    return false;
  }

  void _afterMyOpen() {
    Log.i('oyun', 'el açıldı: mod=${opened[me]?.name} masadaki per=${table.length}');
    final mu = mustUse;
    if (mu != null && !_inRack(mu)) mustUse = null;
    _audit('açtıktan sonra');
    Sfx.I.tile(mine: true);
    notifyListeners();
  }

  /// [seat] oyuncusunun işleyebileceği ilk per (yoksa -1). Seri de çift de
  /// açan, tüm normal (küt/seri) perlere işleyebilir; çift perlere işlenmez.
  int _layIndex(int seat, Tile t) {
    for (var i = 0; i < table.length; i++) {
      if (table[i].accepts(t, okey)) return i;
    }
    return -1;
  }

  /// Taşı masadaki bir pere işler. [meldIndex] verilmezse uygun ilk per seçilir.
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
    if (myHand.length <= 1) {
      // Son taş işlenemez; ama perdeki okeyin yerini dolduruyorsa okeyi çalar,
      // elde kalan okeyi atarak eli bitirebilirsin.
      if (meldIndex != null ? _stealJoker(tile, meldIndex) : _stealAny(tile)) {
        return;
      }
      _say('Son taşı işleyemezsin, atarak bitirmelisin.');
      return;
    }
    final i = meldIndex ?? _layIndex(me, tile);
    if (i < 0 && meldIndex == null && _stealAny(tile)) return;
    if (i < 0 || i >= table.length) {
      _say('Bu taş hiçbir pere işlenemiyor.');
      return;
    }
    final m2 = table[i].tryAdd(tile, okey, front: front);
    if (m2 == null) {
      // Bilinen bir pere bırakıldı ama eklenemiyor: perdeki okeyin yerine
      // geçiyorsa okey çalınır (yasal, ceza yok).
      if (meldIndex != null && _stealJoker(tile, meldIndex)) return;
      _say('Bu taş o pere işlenemiyor.');
      return;
    }
    table[i] = m2;
    tileLayer[tile.id] = me;
    _removeFromRack(tile);
    _acted = true;
    if (mustUse?.id == tile.id) mustUse = null;
    Log.i('oyun', 'işlendi: ${logTile(tile)} → per $i (${m2.kind.name}, ${m2.tiles.length} taş) eldeki=${myHand.length}');
    _audit('işle');
    Sfx.I.tile(mine: true);
    notifyListeners();
  }

  /// [tile] masadaki herhangi bir perdeki okeyin yerini dolduruyorsa okeyi çalar.
  bool _stealAny(Tile tile) {
    for (var k = 0; k < table.length; k++) {
      if (table[k].trySwap(tile, okey) != null) return _stealJoker(tile, k);
    }
    return false;
  }

  /// Okey çalma: [tile] perdeki okeyin yerine geçiyorsa okeyi alıp ıstakaya koyar.
  bool _stealJoker(Tile tile, int meldIndex) {
    final sw = table[meldIndex].trySwap(tile, okey);
    if (sw == null) return false;
    table[meldIndex] = sw.meld;
    tileLayer[tile.id] = me;
    _removeFromRack(tile);
    _putInRack(sw.joker);
    _acted = true;
    if (mustUse?.id == tile.id) mustUse = null;
    Log.i('oyun', 'OKEY ÇALINDI: ${logTile(tile)} → per $meldIndex, alınan okey ıstakada');
    _say('Okey çaldın!');
    _audit('okey çal');
    notifyListeners();
    return true;
  }

  /// OTO İŞLE: işlenebilen tüm taşları (okey hariç) masaya işler; atmak için
  /// en az bir taş elde kalır. Elindeki bir taş perdeki okeyin yerini
  /// dolduruyorsa okeyi de otomatik çalıp ıstakaya koyar (önce çalma denenir);
  /// son taş okeyin yerini dolduruyorsa o da çalar (okey atarak bitirilir).
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
    var n = 0, stolen = 0;
    var changed = true;
    while (changed) {
      changed = false;
      for (final t in List<Tile>.of(myHand)) {
        if (okey.isWild(t)) continue;
        // Okey çalma: taş perdeki okeyin yerini dolduruyorsa okeyi al.
        var swapped = false;
        for (var k = 0; k < table.length; k++) {
          final sw = table[k].trySwap(t, okey);
          if (sw == null) continue;
          table[k] = sw.meld;
          tileLayer[t.id] = me;
          _removeFromRack(t);
          _putInRack(sw.joker);
          _acted = true;
          if (mustUse?.id == t.id) mustUse = null;
          Log.d('oyun', 'oto işle: OKEY ÇALINDI ${logTile(t)} → per $k');
          stolen++;
          swapped = true;
          changed = true;
          break;
        }
        if (swapped) continue;
        if (myHand.length <= 1) continue; // son taş işlenmez, atılır
        final i = _layIndex(me, t);
        if (i < 0) continue;
        final m2 = table[i].tryAdd(t, okey);
        if (m2 == null) continue;
        table[i] = m2;
        tileLayer[t.id] = me;
        _removeFromRack(t);
        _acted = true;
        if (mustUse?.id == t.id) mustUse = null;
        Log.d('oyun', 'oto işle: ${logTile(t)} → per $i');
        n++;
        changed = true;
      }
    }
    final okeyMsg = stolen > 0 ? ' $stolen okey çalındı.' : '';
    _say(n == 0 && stolen == 0
        ? 'İşlenecek taş bulunamadı.'
        : '$n taş işlendi.$okeyMsg');
    _audit('oto işle');
    notifyListeners();
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
    _discardFor(me, tile);
  }

  // ------------------------------------------------------------- atış

  void _discardFor(int seat, Tile tile) {
    Log.i('oyun', 'koltuk $seat (${names[seat]}) taş attı: ${logTile(tile)}');
    final before = handCount(seat);
    if (seat == me) {
      _removeFromRack(tile);
    } else {
      _hands[seat].removeWhere((t) => t.id == tile.id);
    }
    if (handCount(seat) == before) {
      Log.e('oyun', 'koltuk $seat elinde ${logTile(tile)} YOK ama atıldı: taş çoğalabilir');
    }
    final remaining = handCount(seat);
    final finishing = remaining == 0;
    if (!finishing) {
      if (okey.isWild(tile)) {
        penalty[seat] += penaltyPoints;
        Sfx.I.penalty(mine: seat == me);
        Log.w('oyun', 'CEZA +101: koltuk $seat (toplam ceza=${penalty[seat]})');
        _say('${names[seat]} okey attı: +101 ceza.');
      } else if (table.any((m) => m.usable(tile, okey))) {
        penalty[seat] += penaltyPoints;
        Sfx.I.penalty(mine: seat == me);
        Log.w('oyun', 'CEZA +101: koltuk $seat (toplam ceza=${penalty[seat]})');
        _say('${names[seat]} işlenebilir taş attı: +101 ceza.');
      }
    }
    discards[seat].add(tile);
    Sfx.I.tile(mine: seat == me);
    if (finishing) {
      _finishRound(seat, tile);
    } else if (deck.isEmpty) {
      // Son taş çekildi: o oyuncu taşını atar atmaz el biter.
      _endDeckOut('Deste bitti.');
    } else {
      _advance();
    }
  }

  void _autoPlay() {
    Log.w('oyun', 'otomatik oyun (süre doldu) faz=${phase.name}');
    _collectPending(); // hatalı açış varsa otomatik geri topla (+101)
    if (phase == TurnPhase.draw) {
      if (deck.isEmpty) {
        _endDeckOut('Çekilecek taş kalmadı.');
        return;
      }
      final t = deck.removeLast();
      _putInRack(t);
      lastDrawn = t;
      phase = TurnPhase.play;
    }
    final mu = mustUse;
    var returned = false;
    if (mu != null && _inRack(mu)) {
      // Soldan alınan taş kullanılmadı: otomatik geri bırak, desteden çek.
      _removeFromRack(mu);
      discards[3].add(mu);
      returned = true;
      // Süre dolunca otomatik geri bırakma cezasızdır.
      mustUse = null;
      if (deck.isEmpty) {
        _endDeckOut('Çekilecek taş kalmadı.');
        return;
      }
      final t = deck.removeLast();
      _putInRack(t);
      lastDrawn = t;
    }
    final hand = myHand;
    if (hand.isEmpty) {
      Log.e('oyun', 'otomatik oyun: elde taş yok (faz=${phase.name})');
      return;
    }
    // Güvenli taş: okey değil, masaya işlenebilir değil, perlerimi bozmayan.
    final pick = _pickDiscard(me);
    _say(returned
        ? 'Süre doldu: alınan taş geri bırakıldı, taş otomatik atıldı.'
        : 'Süre doldu, taş otomatik atıldı.');
    _discardFor(me, pick);
  }

  // ------------------------------------------------------------- denetim

  /// Tutarlılık denetimi: 105 taşın (106 - gösterge) tamamı deste, eller, atıklar
  /// ve masada tam bir kez bulunmalı; masadaki perler geçerli olmalı. Bozukluk
  /// 'tutarlılık' etiketiyle ERROR olarak günlüğe yazılır (oyun devam eder).
  void _audit(String where) {
    try {
      final seen = <int, String>{};
      var total = 0;
      void add(Tile t, String place) {
        total++;
        final prev = seen[t.id];
        if (prev != null) {
          Log.e('tutarlılık', '[$where] ${logTile(t)} iki yerde: $prev ve $place');
        } else {
          seen[t.id] = place;
        }
        if (t.id < 0 || t.id > 105) {
          Log.e('tutarlılık', '[$where] geçersiz taş kimliği: ${logTile(t)} ($place)');
        }
      }

      for (final t in deck) {
        add(t, 'deste');
      }
      for (var s = 0; s < 4; s++) {
        for (final t in discards[s]) {
          add(t, 'atık$s');
        }
        if (s != me) {
          for (final t in _hands[s]) {
            add(t, 'el$s');
          }
        }
      }
      for (final t in rack) {
        if (t != null) add(t, 'ıstaka');
      }
      for (final g in pendingOpen?.groups ?? const <List<Tile>>[]) {
        for (final t in g) {
          add(t, 'bekleyen');
        }
      }
      for (var i = 0; i < table.length; i++) {
        final m = table[i];
        for (final t in m.tiles) {
          add(t, 'per$i');
        }
        if (m.kind != MeldKind.pair && GroupRules.valueOf(m.tiles, okey) <= 0) {
          Log.e('tutarlılık', '[$where] per$i geçersiz (${m.kind.name}): ${m.tiles.map(logTile).join(' ')}');
        }
      }
      if (total != 105) {
        Log.e('tutarlılık',
            '[$where] taş sayısı $total (105 olmalı): deste=${deck.length} eller=${[for (var s = 0; s < 4; s++) handCount(s)]} atık=${[for (var s = 0; s < 4; s++) discards[s].length]} per=${table.fold<int>(0, (a, m) => a + m.tiles.length)}');
      }
      final bot = phase == TurnPhase.bot;
      if (result == null && bot == (turn == me)) {
        Log.e('tutarlılık', '[$where] sıra/faz uyumsuz: sıra=$turn faz=${phase.name}');
      }
    } catch (e, s) {
      Log.e('tutarlılık', 'denetimin kendisi çöktü', e, s);
    }
  }

  // ----------------------------------------------------------- kurallar

  bool _canUse(int seat, Tile t) {
    final all = [..._handOf(seat), t];
    final mode = opened[seat];
    if (mode != null) {
      if (_layIndex(seat, t) >= 0) return true;
      // Çift açan yeni per indiremez; yalnızca mevcut perlere işleyebilir.
      if (mode == OpenMode.pairs) return false;
      final r = RackArranger.solveSeri(all, okey);
      return r.groups.any((g) => g.any((x) => x.id == t.id));
    }
    final r = RackArranger.solveSeri(all, okey);
    final inGroup = r.groups.any((g) => g.any((x) => x.id == t.id));
    if (inGroup &&
        (r.value >= requiredOpen(seat) || r.leftover.length <= 1)) {
      return true;
    }
    final p = RackArranger.solvePairs(all, okey);
    return p.pairs.length >= requiredPairs(seat) &&
        p.pairs.any((g) => g.any((x) => x.id == t.id));
  }

  void _checkAllPairs() {
    if (opened.every((o) => o == OpenMode.pairs)) {
      _endDeckOut('Herkes çift açtı, el bitti.');
    }
  }

  /// Elde kalan taşların sayı toplamı. Okey burada sayılmaz: açmış oyuncunun
  /// elinde kalan okey ayrıca +101 yazılır (bkz. [RoundScoring]).
  int _handValue(int seat) => _handOf(seat)
      .fold<int>(0, (s, t) => s + (okey.isWild(t) ? 0 : tileValue(t, okey)));

  bool _hasOkey(int seat) => _handOf(seat).any((t) => okey.isWild(t));

  /// El, kimse bitiremeden sona erdi (deste bitti ya da herkes çift açtı).
  /// Sunucudaki `endDeckOut` ile aynı kural:
  ///  - Kimse el açmadıysa: tek elli oyunda HÜKÜMSÜZ (puan/XP yok, bilet iadesi);
  ///    çok elli oyunda herkese +202 (+ o elde yenen cezalar) yazılır, sonraki ele geçilir.
  ///  - En az biri açtıysa: açmayanlar 202; açanlar elde kalan sayı kadar (çiftle
  ///    açanın 2 katı, elinde okey kalırsa +101) ceza yazar; o elin cezaları da eklenir.
  ///    En az ceza alan eli kazanır, maç sonunda toplamı en düşük olan kazanır.
  void _endDeckOut(String note) {
    Log.i('oyun', 'el kimse bitirmeden sona erdi: $note');
    _timer?.cancel();
    _warnTimer?.cancel();
    final anyOpen = opened.any((o) => o != null);
    final delta = List<int>.filled(4, 0);
    final String text;
    if (!anyOpen && totalHands == 1) {
      voided = true;
      text = '$note Kimse el açamadı: oyun hükümsüz, biletin iade edilir.';
    } else if (!anyOpen) {
      for (var s = 0; s < 4; s++) {
        delta[s] = 202 + penalty[s];
      }
      text = '$note Kimse el açamadı: herkese +202 yazıldı.';
    } else {
      for (var s = 0; s < 4; s++) {
        int d;
        if (opened[s] == null) {
          d = 202;
        } else {
          d = _handValue(s) * (opened[s] == OpenMode.series ? 1 : 2);
          if (_hasOkey(s)) d += penaltyPoints;
        }
        delta[s] = d + penalty[s];
      }
      final low = delta.reduce(min);
      final lows = [
        for (var s = 0; s < 4; s++)
          if (delta[s] == low) names[s]
      ];
      text =
          '$note Elde kalan sayılara göre puanlandı, en az ceza: ${lows.join(' ve ')} ($low).';
    }
    for (var s = 0; s < 4; s++) {
      totals[s] += delta[s];
    }
    lastDelta = List<int>.of(delta);
    history.add(List<int>.of(delta));
    result = RoundResult(null, delta, List<OpenMode?>.of(opened), text,
        deckOut: true, voided: voided);
    phase = TurnPhase.over;
    Log.i('oyun', 'deste sonu puanlaması: delta=$delta toplam=$totals ceza=$penalty açış=${opened.map((o) => o?.name).toList()} hükümsüz=$voided');
    _audit('el sonu (kimse bitirmedi)');
    notifyListeners();
  }

  void _finishRound(int winner, Tile last) {
    Log.i('oyun', 'EL BİTTİ: kazanan=$winner (${names[winner]}) son taş=${logTile(last)} mod=${opened[winner]?.name}');
    _timer?.cancel();
    _warnTimer?.cancel();
    // Okeyle / elden bitirme puanı her masada katlanır. ("Katlamalı" masa ayarı
    // açış barajının artması demektir, bkz. requiredOpen.)
    final joker = okey.isWild(last);
    final wMode = opened[winner] ?? OpenMode.series;
    final elden = _eldenSeat == winner &&
        [0, 1, 2, 3].every((s) => s == winner || opened[s] == null);
    final delta = RoundScoring.compute(
      winner: winner,
      joker: joker,
      elden: elden,
      teamMode: teamMode,
      opened: opened,
      handValues: [for (var s = 0; s < 4; s++) _handValue(s)],
      penalty: penalty,
      okeyLeft: [for (var s = 0; s < 4; s++) _hasOkey(s)],
    );
    lastDelta = List<int>.of(delta);
    history.add(List<int>.of(delta));
    for (var s = 0; s < 4; s++) {
      totals[s] += delta[s];
    }
    final note = elden
        ? (joker ? 'Elden okeyle bitirdi!' : 'Elden bitirdi!')
        : joker
            ? 'Okey atarak bitirdi (katlı puan).'
            : wMode == OpenMode.pairs
                ? 'Çiftle bitirdi.'
                : 'Eli bitirdi.';
    result = RoundResult(winner, delta, List<OpenMode?>.of(opened), note);
    phase = TurnPhase.over;
    Log.i('oyun', 'puanlama: delta=$delta toplam=$totals ceza=$penalty elde kalan=${[for (var s = 0; s < 4; s++) _handValue(s)]} elden=$elden okeyle=$joker açış=${opened.map((o) => o?.name).toList()}');
    _audit('el sonu');
    // Alkış yalnız SEN (eşli masada eşin de) kazanınca çalar: okeyle bitirme büyük alkış, normal bitiş normal alkış.
    if (winner == me || (teamMode && winner == partnerOf(me))) Sfx.I.cheer(okey: joker, mine: winner == me);
    _say('${names[winner]} eli bitirdi!');
  }

  // ---------------------------------------------------------- bilgisayar

  Future<void> _botTurn(int seat, int gen, bool skipDraw) async {
    Log.d('bot', 'koltuk $seat (${names[seat]}) hamleye başladı (skipDraw=$skipDraw)');
    bool alive() {
      final ok = !_disposed && gen == _gen && result == null && turn == seat;
      if (!ok) {
        Log.d('bot', 'koltuk $seat hamlesi bırakıldı (kapandı=$_disposed nesil=${gen == _gen} sonuç=${result != null} sıra=$turn)');
      }
      return ok;
    }
    if (!alive()) return;
    final hand = _hands[seat];
    if (!skipDraw) {
      final prev = (seat + 3) % 4;
      final d = topDiscard(prev);
      if (d != null && _botWants(seat, d)) {
        discards[prev].removeLast();
        hand.add(d);
        _botMustUse = d;
        Log.i('bot', 'koltuk $seat soldan aldı: ${logTile(d)}');
        _say('${names[seat]} yandaki taşı aldı.');
      } else if (deck.isEmpty) {
        _endDeckOut('Çekilecek taş kalmadı.');
        return;
      } else {
        final t = deck.removeLast();
        hand.add(t);
        Log.d('bot', 'koltuk $seat desteden çekti: ${logTile(t)} kalan deste=${deck.length}');
      }
      Sfx.I.tile();
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (!alive()) return;
    }
    final mu = _botMustUse;
    _botMustUse = null;
    final before = mu == null ? 0 : _countLike(hand, mu);
    _botMeld(seat, keep: mu);
    if (mu != null && _countLike(hand, mu) >= before) {
      if (!_acted) {
        // Hiçbir per açmadı/indirmedi (sunucudaki `acted`; işleme ve okey çalma sayılmaz): GERİ BIRAK gibi taşı iade eder (ceza yok),
        // desteden çeker.
        final prev = (seat + 3) % 4;
        hand.removeWhere((x) => x.id == mu.id);
        discards[prev].add(mu);
        Log.i('bot', 'koltuk $seat soldan aldığı ${logTile(mu)} taşını geri bıraktı (ceza yok)');
        _say('${names[seat]} aldığı taşı geri bıraktı.');
        if (deck.isEmpty) {
          _endDeckOut('Çekilecek taş kalmadı.');
          return;
        }
        hand.add(deck.removeLast());
      } else {
        // Per açtı/indirdi ama aldığı taşı kullanmadı: ceza.
        penalty[seat] += penaltyPoints;
        Sfx.I.penalty();
        Log.w('bot', 'CEZA +101: koltuk $seat soldan aldığı ${logTile(mu)} taşını kullanamadı (ceza=${penalty[seat]})');
        _say('${names[seat]} aldığı taşı kullanamadı: +101 ceza.');
      }
    }
    _audit('bot per sonrası');
    notifyListeners();
    if (!alive()) return;
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!alive()) return;
    if (hand.isEmpty) {
      Log.e('bot', 'koltuk $seat elinde atacak taş yok');
      return;
    }
    _discardFor(seat, _pickDiscard(seat));
  }

  bool _botWants(int seat, Tile t) => _canUse(seat, t);

  int _sumGroups(List<List<Tile>> groups) =>
      groups.fold<int>(0, (s, g) => s + GroupRules.valueOf(g, okey));

  static String _key(Tile t) =>
      t.isFakeJoker ? 'f' : '${t.number}-${t.color.index}';

  /// [hand] içinde [t] ile aynı sayı/renkte kaç taş var (sahte okey = 'f').
  int _countLike(List<Tile> hand, Tile t) =>
      hand.where((x) => _key(x) == _key(t)).length;

  /// Atacak taş kalsın diye en uzun gruptan bir uç taşı çıkarır. [keep]
  /// (soldan alınan taş) asla çıkarılmaz.
  bool _dropOne(List<List<Tile>> groups, {Tile? keep}) {
    final cands = groups.where((g) => g.length > 3).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final g in cands) {
      if (keep == null || g.last.id != keep.id) {
        g.removeLast();
        return true;
      }
      if (g.first.id != keep.id) {
        g.removeAt(0);
        return true;
      }
    }
    return false;
  }

  void _botMeld(int seat, {Tile? keep}) {
    Log.d('bot', 'koltuk $seat per/açma değerlendiriyor (açık=${opened[seat]?.name})');
    final hand = _hands[seat];
    final othersClosed =
        [0, 1, 2, 3].every((s) => s == seat || opened[s] == null);

    if (opened[seat] == null) {
      final r = RackArranger.solveSeri(hand, okey);
      final groups = r.groups.map((g) => List<Tile>.of(g)).toList();
      var ok = groups.isNotEmpty;
      if (ok && hand.length - groups.fold<int>(0, (s, g) => s + g.length) == 0) {
        ok = _dropOne(groups, keep: keep);
      }
      if (ok) {
        final left = hand.length - groups.fold<int>(0, (s, g) => s + g.length);
        if (_sumGroups(groups) >= requiredOpen(seat) ||
            (left <= 1 && othersClosed)) {
          _openGroups(seat, groups, OpenMode.series,
              elden: left == 1 && othersClosed);
        }
      }
      if (opened[seat] == null) {
        final p = RackArranger.solvePairs(hand, okey);
        final pairs = p.pairs.map((g) => List<Tile>.of(g)).toList();
        final needPairs = requiredPairs(seat);
        if (pairs.length >= needPairs) {
          if (pairs.length * 2 >= hand.length) {
            final i = pairs.lastIndexWhere(
                (g) => keep == null || !g.any((t) => t.id == keep.id));
            if (i >= 0) pairs.removeAt(i);
          }
          if (pairs.length >= needPairs) {
            _openGroups(seat, pairs, OpenMode.pairs);
          }
        }
      }
    } else if (opened[seat] == OpenMode.series) {
      final r = RackArranger.solveSeri(hand, okey);
      final groups = r.groups.map((g) => List<Tile>.of(g)).toList();
      if (groups.isNotEmpty &&
          hand.length - groups.fold<int>(0, (s, g) => s + g.length) == 0 &&
          !_dropOne(groups, keep: keep)) {
        groups.clear();
      }
      if (groups.isNotEmpty) _openGroups(seat, groups, OpenMode.series);
    }

    if (opened[seat] != null && result == null) _botLayOff(seat);
  }

  /// Perleri masaya açar (insan ve bilgisayar için ortak). İlk açışta açış
  /// puanı kaydedilir (katlamalı masada sonraki baraj buna göre artar).
  void _openGroups(int seat, List<List<Tile>> groups, OpenMode mode,
      {bool elden = false, bool keepMode = false}) {
    final first = opened[seat] == null;
    var sum = 0;
    var count = 0;
    for (final g in groups) {
      final m = mode == OpenMode.series
          ? Meld.fromGroup(g, okey, seat)
          : Meld.pairFrom(g, okey, seat);
      if (m == null) {
        Log.w('oyun', 'koltuk $seat: geçersiz grup atlandı (${mode.name}): ${g.map(logTile).join(' ')}');
        continue;
      }
      table.add(m);
      for (final t in g) {
        tileLayer[t.id] = seat;
      }
      sum += m.value;
      count++;
      for (final t in g) {
        if (seat == me) {
          _removeFromRack(t);
        } else {
          _hands[seat].removeWhere((x) => x.id == t.id);
        }
      }
    }
    if (count == 0) {
      Log.w('oyun', 'koltuk $seat: açılacak geçerli grup çıkmadı (${groups.length} aday, ${mode.name})');
      return;
    }
    Log.i('oyun', 'koltuk $seat ${first ? 'İLK AÇIŞ' : 'per indirdi'}: ${mode.name} $count grup toplam=$sum elden=$elden');
    if (seat == turn) _acted = true; // sunucudaki `acted`: sırası gelen (insan ya da bot) per açtı/indirdi
    openedTotal[seat] += mode == OpenMode.series ? sum : count;
    if (!keepMode) opened[seat] = mode;
    if (first && mode == OpenMode.series) openScore[seat] = sum;
    if (first && mode == OpenMode.pairs) openPairCount[seat] = count;
    if (elden) _eldenSeat = seat;
    if (first) {
      _say(mode == OpenMode.series
          ? '${names[seat]}, $sum sayılık seri açtı.'
          : '${names[seat]}, $count çift açtı.');
    } else if (seat == me) {
      _say('${names[seat]} yeni per açtı.');
    }
    if (mode == OpenMode.pairs && !keepMode) _checkAllPairs();
  }

  /// Bilgisayar, perlerdeki okeyi elindeki gerçek taşla değiştirip alır.
  void _botSteal(int seat) {
    final hand = _hands[seat];
    var changed = true;
    while (changed) {
      changed = false;
      for (final t in List<Tile>.of(hand)) {
        if (okey.isWild(t)) continue;
        for (var i = 0; i < table.length; i++) {
          final sw = table[i].trySwap(t, okey);
          if (sw == null) continue;
          table[i] = sw.meld;
          tileLayer[t.id] = seat;
          hand.removeWhere((x) => x.id == t.id);
          hand.add(sw.joker);
          Log.i('bot', 'koltuk $seat okey çaldı: ${logTile(t)} → per $i');
          _say('${names[seat]} okey çaldı!');
          changed = true;
          break;
        }
        if (changed) break;
      }
    }
  }

  void _botLayOff(int seat) {
    _botSteal(seat);
    final hand = _hands[seat];
    var changed = true;
    while (changed && hand.length > 1) {
      changed = false;
      for (final t in List<Tile>.of(hand)) {
        if (hand.length <= 1) break;
        if (okey.isWild(t)) continue;
        final i = _layIndex(seat, t);
        if (i < 0) continue;
        final m2 = table[i].tryAdd(t, okey);
        if (m2 == null) continue;
        table[i] = m2;
        tileLayer[t.id] = seat;
        hand.removeWhere((x) => x.id == t.id);
        Log.d('bot', 'koltuk $seat işledi: ${logTile(t)} → per $i');
        changed = true;
      }
    }
  }

  /// Atılacak güvenli taş: okey ve masaya işlenebilir taşlardan kaçınır,
  /// açtığı moda göre perleri (seri ya da çift) bozmamaya çalışır.
  Tile _pickDiscard(int seat) {
    final hand = _handOf(seat);
    final mode = opened[seat];
    List<Tile> leftover;
    if (mode == OpenMode.pairs) {
      leftover = RackArranger.solvePairs(hand, okey).leftover;
    } else if (mode == OpenMode.series) {
      leftover = RackArranger.solveSeri(hand, okey).leftover;
    } else {
      final s = RackArranger.solveSeri(hand, okey);
      final p = RackArranger.solvePairs(hand, okey);
      final inSeries = hand.length - s.leftover.length;
      leftover = (p.pairs.length >= 4 && p.pairs.length * 2 > inSeries)
          ? p.leftover
          : s.leftover;
    }
    var cands = leftover.where((t) => !okey.isWild(t)).toList();
    if (cands.isEmpty) cands = hand.where((t) => !okey.isWild(t)).toList();
    if (cands.isEmpty) cands = List<Tile>.of(hand);

    int use(Tile t) {
      var s = 0;
      for (final h in hand) {
        if (h.id == t.id) continue;
        final same = okey.colorOf(h) == okey.colorOf(t);
        final d = (okey.numberOf(h) - okey.numberOf(t)).abs();
        if (same && d <= 1) {
          s += 3;
        } else if (same && d == 2) {
          s += 1;
        } else if (!same && d == 0) {
          s += 2;
        }
      }
      return s;
    }

    // Deste bitmek üzereyse elde kalan sayı ceza yazılır: açtıysam büyük taşı önce at.
    final endgame = opened[seat] != null && deck.length <= 8;
    double cost(Tile t) =>
        use(t) * 10.0 +
        (table.any((m) => m.usable(t, okey)) ? 1000 : 0) +
        (okey.isWild(t) ? 5000 : 0) -
        okey.numberOf(t) * 0.01 -
        (endgame ? okey.numberOf(t) * 20 : 0);

    cands.sort((a, b) => cost(a).compareTo(cost(b)));
    return cands.first;
  }
}
