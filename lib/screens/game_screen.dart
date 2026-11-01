import 'dart:async';
import '../diagnostics/app_log.dart';
import 'package:flutter/material.dart';
import '../logic/game_controller.dart';
import '../logic/hand_scorer.dart';
import '../logic/meld.dart';
import '../models/app_settings.dart';
import '../models/quick_chat.dart';
import '../models/rewards.dart' show kNoTicketWaitSeconds;
import '../models/table_models.dart';
import '../models/tile.dart';
import '../services/ad_service.dart';
import '../services/game_service.dart';
import '../services/sfx.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_widgets.dart';
import '../widgets/discard_slot.dart';
import '../widgets/exit_dialog.dart';
import '../widgets/game_button.dart';
import '../widgets/game_popup.dart';
import '../widgets/game_start_popup.dart';
import '../widgets/lobby_widgets.dart' show CandyKind, ToastKind, showToast;
import '../widgets/meld_area.dart';
import '../widgets/player_badge.dart';
import '../widgets/player_strip.dart';
import '../widgets/presence_widgets.dart';
import '../widgets/rack_widget.dart';
import '../widgets/result_dialog.dart';
import '../widgets/side_action_button.dart';
import '../widgets/status_badges.dart';
import '../widgets/tile_flight.dart';
import '../widgets/tile_widget.dart';
import '../widgets/turn_timer_bar.dart';

class GameScreen extends StatefulWidget {
  final GameService service;
  final String? tableId;

  /// Hemen Oyna: masa seçilmediyse bu ayarlarla girilir.
  final TableSettings? quick;

  /// Oyun sonu "REKLAM İZLE +1 BİLET" için ödüllü reklam (şimdilik sahte; LevelPlay bağlanınca gerçeği verilir).
  final AdService ads;
  const GameScreen(
      {super.key,
      required this.service,
      this.tableId,
      this.quick,
      this.ads = const MockAdService()});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
      vsync: this, duration: const Duration(seconds: 30), value: 1);
  TableSnapshot? _snap;
  GameController? _c;

  // "OYUN BAŞLIYOR": masa dolunca geri sayım; oyun motoru bitince kurulur. Bilet geri sayım BİTİNCE düşer (beginMatch).
  bool _starting = false;
  int _startLeft = kStartCountdownSeconds;
  Timer? _startTimer;
  int? _tickets; // oyun bitince bilet bakiyesi (0 ise otomatik yeni oyun durur, REKLAM İZLE çıkar)
  bool _adBusy = false;
  int _loggedRound = -1;
  Tile? _sel;
  int _seenToken = -1, _seenToast = 0;
  bool _toastVisible = false;
  Timer? _toastTimer;

  // Hazır mesaj / emoji: koltuk başına balon (0 ben, 1 sağ, 2 karşı, 3 sol), 2-3 sn görünür.
  final List<QuickChat?> _bubble = List<QuickChat?>.filled(4, null);
  final List<int> _bubbleGen = List<int>.filled(4, 0);
  final List<Timer?> _bubbleTimer = List<Timer?>.filled(4, null);
  StreamSubscription<ChatEvent>? _chatSub;
  bool _chatOpen = false;

  // Bağlantı / boşta: kopunca üstte şerit, boştayken "OYUNA DÖN", rakip koltuğunda BOŞTA / BAĞLANTI YOK etiketi.
  Presence _presence = Presence.none;
  bool _online = true;
  StreamSubscription<Presence>? _presSub;
  StreamSubscription<bool>? _connSub;
  final _chatLimit = ChatLimiter();

  // Sürükleyerek taş çekme (deste / soldaki atık) ve atma
  final _stackKey = GlobalKey();
  final _rackKey = GlobalKey<RackWidgetState>();
  final _discardKey = GlobalKey();
  final _meldKey = GlobalKey<MeldAreaState>();
  Tile? _dragTile; // ıstakadan sürüklenen taş (per vurgusu için)
  bool _srcDrag = false;
  bool _srcFromDeck = false;
  Tile? _ghost;
  Offset _ghostPos = Offset.zero;
  Offset _srcGlobal = Offset.zero;

  // El açma / taş işleme animasyonu: yeni per ya da işlenen taş, sahibinin koltuğundan perine uçar.
  final List<_FlightSpec> _flights = [];
  final Set<int> _hiddenIds = {}; // uçuş bitene kadar masada görünmez tutulan taşlar
  List<List<int>> _prevTable = const [];
  int _prevRound = -1;
  int _flightSeq = 0;
  final List<GlobalKey> _seatKeys = List<GlobalKey>.generate(4, (_) => GlobalKey());
  Offset? _dropPoint; // ıstakadan per üzerine bırakılan taşın son konumu (işleme uçuşu buradan başlar)
  DateTime _dropAt = DateTime(2000);

  bool _hit(GlobalKey k, Offset g) {
    final ctx = k.currentContext;
    if (ctx == null) return false;
    final rb = ctx.findRenderObject() as RenderBox;
    return rb.size.contains(rb.globalToLocal(g));
  }

  Offset _toLocal(Offset g) =>
      (_stackKey.currentContext!.findRenderObject() as RenderBox).globalToLocal(g);

  void _srcStart(Offset g, {Tile? tile}) {
    final c = _c;
    if (c == null || !c.canDraw) {
      Log.d('dokunma', 'sürükleyerek çekme yok sayıldı: ${c == null ? 'oyun yok' : 'sıra=${c.turn} faz=${c.phase.name} sonuç=${c.result != null}'}');
      return;
    }
    Log.d('dokunma', 'çekme sürüklemesi başladı: ${tile == null ? 'desteden' : 'soldan ${logTile(tile)}'}');
    _srcGlobal = g;
    setState(() {
      _srcDrag = true;
      _srcFromDeck = tile == null;
      _ghost = tile;
      _ghostPos = _toLocal(g);
    });
  }

  void _srcUpdate(Offset g) {
    if (!_srcDrag) return;
    _srcGlobal = g;
    final r = _rackKey.currentState;
    if (r != null) r.setExternalHover(_hit(_rackKey, g) ? r.slotAt(g) : null);
    setState(() => _ghostPos = _toLocal(g));
  }

  void _srcEnd() {
    if (!_srcDrag) return;
    final c = _c;
    final g = _srcGlobal;
    final r = _rackKey.currentState;
    final drop = _hit(_rackKey, g);
    final slot = drop ? r?.slotAt(g) : null;
    r?.setExternalHover(null);
    final fromDeck = _srcFromDeck;
    setState(() {
      _srcDrag = false;
      _ghost = null;
    });
    if (c == null) return;
    if (!drop) {
      Log.d('dokunma', 'çekme sürüklemesi ıstaka dışına bırakıldı: taş çekilmedi (${fromDeck ? 'deste' : 'soldaki atık'}, konum=(${g.dx.round()}, ${g.dy.round()}))');
      return;
    }
    Log.d('dokunma', 'çekme sürüklemesi ıstakaya bırakıldı: ${fromDeck ? 'deste' : 'soldaki atık'} yuva=$slot');
    if (fromDeck) {
      c.drawFromDeck(slot: slot);
    } else {
      c.takeDiscard(slot: slot);
    }
  }

  /// Hareket sistem tarafından iptal edildi: taş ÇEKİLMEZ.
  void _srcCancel() {
    if (!_srcDrag) return;
    Log.w('dokunma', 'çekme sürüklemesi İPTAL edildi (taş çekilmedi)');
    _rackKey.currentState?.setExternalHover(null);
    setState(() {
      _srcDrag = false;
      _ghost = null;
    });
  }

  /// Istakadan sürüklenen taş ıstaka dışına bırakılınca: atık yuvasına = at,
  /// masadaki bir pere = işle (okey için perin sol/sağ yarısı baş/son seçer),
  /// masanın boş yerine = uygun ilk pere işle.
  void _onRackDrop(GameController c, Tile tile, Offset g) {
    Log.d('dokunma', 'taş bırakıldı: ${logTile(tile)} konum=(${g.dx.round()}, ${g.dy.round()})');
    if (_hit(_discardKey, g)) {
      if (!c.canPlay) return;
      setState(() => _sel = null);
      c.discard(tile);
      return;
    }
    final area = _meldKey.currentState;
    if (area != null && area.containsGlobal(g)) {
      if (!c.canPlay) return;
      _dropPoint = g;
      _dropAt = DateTime.now();
      final h = area.hitMeld(g);
      setState(() => _sel = null);
      if (h != null) {
        c.layOff(tile, meldIndex: h.index, front: h.front);
      } else {
        c.layOff(tile);
      }
      return;
    }
    Log.d('dokunma', 'taş boş yere bırakıldı, işlem yok: ${logTile(tile)}');
  }

  void _onDragStart(Tile t) {
    Log.d('dokunma', 'taş sürükleme başladı: ${logTile(t)}');
    setState(() => _dragTile = t);
  }

  void _onDragEnd() {
    if (_dragTile != null) setState(() => _dragTile = null);
  }

  @override
  void initState() {
    super.initState();
    Log.i('ekran', 'GameScreen açıldı: masa=${widget.tableId ?? 'hemen oyna'} quick=${widget.quick != null}');
    _chatSub = widget.service.chatEvents.listen((e) => _showBubble(e.seat, e.id));
    _online = widget.service.isConnected;
    _presSub = widget.service.presence.listen((p) {
      if (mounted) setState(() => _presence = p);
    });
    _connSub = widget.service.connection.listen((v) {
      if (mounted) setState(() => _online = v);
    });
    _join();
  }

  /// Masaya girer, "OYUN BAŞLIYOR" geri sayımını başlatır; oyun motoru geri sayım bitince kurulur (TEKRAR OYNA da bunu kullanır).
  void _join({TableSettings? again}) {
    // TEKRAR OYNA ([again] dolu): eski masa numarası kullanılmaz (sunucuda maç bitince masa silinir) ve
    // kendi kurduğun masa muafiyeti de yok; aynı ayarlarla yeni bir oturuş = 1 bilet. Bilet yoksa
    // JoinException ile lobiye atılır.
    widget.service
        .joinTable(
            tableId: again == null ? widget.tableId : null,
            quick: again ?? widget.quick)
        .then((t) {
      if (!mounted) {
        Log.w('ekran', 'masa bilgisi geldi ama ekran kapanmıştı; oyun kurulmadı');
        return;
      }
      _beginCountdown(t);
    }).catchError((Object e, StackTrace st) {
      Log.e('ekran', 'masaya girilemedi', e, st);
      if (!mounted) return;
      Navigator.of(context)
          .pop(e is JoinException ? e.message : 'Masaya girilemedi.');
    });
  }

  /// Masa dolu: "OYUN BAŞLIYOR" penceresi + geri sayım ([kStartCountdownSeconds] sn). Bilet henüz düşmedi:
  /// geri sayım sırasında çıkan kimse bir şey kaybetmez. Sayaç bitince [_startMatch] (bilet düşer, zil çalar, oyun başlar).
  void _beginCountdown(TableSnapshot t) {
    _startTimer?.cancel();
    final secs = t.startsInMs > 0 ? (t.startsInMs / 1000).ceil() : kStartCountdownSeconds;
    Log.i('ekran', 'OYUN BAŞLIYOR geri sayımı: $secs sn');
    setState(() {
      _snap = t;
      _starting = true;
      _startLeft = secs;
    });
    _startTimer = Timer.periodic(const Duration(seconds: 1), (tm) {
      if (!mounted) {
        tm.cancel();
        return;
      }
      if (_startLeft > 1) {
        setState(() => _startLeft--);
        return;
      }
      tm.cancel();
      _startMatch(t);
    });
  }

  /// Geri sayım bitti: 1 bilet düşer (bileti yoksa lobiye atılır), başlama zili çalar, oyun motoru kurulur.
  void _startMatch(TableSnapshot t) {
    widget.service.beginMatch().then((_) {
      if (!mounted) return;
      Sfx.I.matchStart();
      final c = GameController(
          names: [t.me.name, t.right.name, t.top.name, t.left.name],
          turnSeconds: t.turnSeconds,
          settings: t.settings);
      Log.i('ekran', 'oyun motoru kuruldu: oyuncular=${[t.me.name, t.right.name, t.top.name, t.left.name]}');
      c.addListener(_onChange);
      _loggedRound = -1;
      _seenToken = -1;
      _sel = null;
      _prevRound = -1;
      _prevTable = const [];
      _hiddenIds.clear();
      _flights.clear();
      setState(() {
        _starting = false;
        _snap = t;
        _c = c;
      });
      _onChange();
    }).catchError((Object e, StackTrace st) {
      Log.e('ekran', 'oyun başlatılamadı (bilet?)', e, st);
      if (!mounted) return;
      Navigator.of(context).pop(e is JoinException ? e.message : 'Oyun başlatılamadı.');
    });
  }

  /// Oyun bitince bilet bakiyesini öğrenir (0 ise sonuç penceresi REKLAM İZLE gösterir, kimse masadan atılmaz).
  Future<void> _refreshTickets() async {
    try {
      final st = await widget.service.fetchTicketStatus();
      if (mounted) setState(() => _tickets = st.tickets);
    } catch (e, s) {
      Log.e('ekran', 'bilet bakiyesi okunamadı', e, s);
    }
  }

  /// Oyun sonu: reklam izle → +1 bilet → yeni oyun. Masada 10 dk sınırı YOK (yalnız 30 sn ara + günlük sınır).
  /// Reklam sürerken sonuç penceresi sayacı durur. Reklam yarıda kapatılırsa bilet verilmez, düğme yerinde kalır.
  Future<void> _watchAdForTicket() async {
    if (_adBusy) return;
    setState(() => _adBusy = true);
    try {
      final watched = await widget.ads.showRewarded(context);
      if (!watched || !mounted) return;
      final r = await widget.service.claimTableAdTicket();
      if (!mounted) return;
      Log.i('ekran', 'masada reklam bileti alındı: bilet=${r.tickets}');
      setState(() => _tickets = r.tickets);
      showToast(context, '+1 bilet! Yeni oyun başlıyor.', kind: ToastKind.success, icon: Icons.confirmation_number_rounded);
      _replay();
    } on JoinException catch (e) {
      if (mounted) showToast(context, e.message, kind: ToastKind.error);
      _refreshTickets();
    } catch (e, s) {
      Log.e('ekran', 'masada reklam bileti alınamadı', e, s);
      if (mounted) showToast(context, 'Bilet alınamadı, tekrar dene.', kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _adBusy = false);
    }
  }

  /// TEKRAR OYNA: aynı ayarlarla yeni bir masaya oturur (1 bilet), sıfırdan yeni oyun başlar.
  void _replay() {
    Log.i('ekran', 'TEKRAR OYNA düğmesi (yeni oturuş, 1 bilet)');
    final again = _snap?.settings ?? widget.quick ?? const TableSettings();
    final old = _c;
    old?.removeListener(_onChange);
    old?.dispose();
    _startTimer?.cancel();
    setState(() {
      _c = null;
      _snap = null;
      _starting = false;
      _tickets = null;
      _toastVisible = false;
    });
    _join(again: again);
  }

  /// Oyun bitmediyse çıkmadan önce onay ister. true = çıkılabilir.
  Future<bool> _confirmExit() async {
    final c = _c;
    if (c == null || c.gameOver) return true;
    Log.i('ekran', 'çıkış onayı gösteriliyor');
    final ok = await showGamePopup<bool>(context,
        barrierDismissible: false, builder: (_) => const ExitConfirmDialog());
    Log.i('ekran', ok == true ? 'çıkış ONAYLANDI' : 'oyuna devam edildi');
    return ok == true;
  }

  @override
  void dispose() {
    Log.i('ekran', 'GameScreen kapandı');
    _toastTimer?.cancel();
    _startTimer?.cancel();
    _chatSub?.cancel();
    _presSub?.cancel();
    _connSub?.cancel();
    for (final t in _bubbleTimer) {
      t?.cancel();
    }
    _c?.removeListener(_onChange);
    _c?.dispose();
    _turn.dispose();
    super.dispose();
  }

  /// Rakip koltuğunun etiketi: bota devredildiyse BOŞTA (bağlı ama süreleri kaçırdı) ya da BAĞLANTI YOK, değilse normal etiket.
  String? _tagFor(Seat s, String? base) {
    if (!_presence.isAway(s)) return base;
    return _presence.isAfk(s) ? 'BOŞTA' : 'BAĞLANTI YOK';
  }

  /// "OYUNA DÖN": sunucuya bildirir; yanıt (state.table.away) gelene kadar uyarıyı hemen kapatır.
  void _imHere() {
    Log.i('ekran', 'OYUNA DÖN: boşta durumundan dönülüyor');
    widget.service.imHere();
    setState(() => _presence = Presence.none);
  }

  /// Koltuğun yanında balon gösterir; aynı koltuktan yeni mesaj gelirse eskisinin yerine geçer.
  /// Ayarlardan SOHBET kapalıysa başkalarının balonu görünmez (kendi balonum hep görünür).
  void _showBubble(int seat, int id) {
    if (!mounted || seat < 0 || seat > 3) return;
    if (seat != 0 && !AppSettings.I.chat) return;
    final chat = quickChatById(id);
    if (chat == null) return; // yeni sürümden gelen bilinmeyen numara
    _bubbleTimer[seat]?.cancel();
    setState(() {
      _bubble[seat] = chat;
      _bubbleGen[seat]++;
    });
    _bubbleTimer[seat] = Timer(kChatShowTime, () {
      if (mounted) setState(() => _bubble[seat] = null);
    });
  }

  /// Panelden bir mesaj seçildi: kendi balonum hemen çıkar, sunucuya yalnız numara gider.
  void _sendChat(QuickChat chat) {
    final now = DateTime.now();
    if (!_chatLimit.canSend(now)) return;
    _chatLimit.record(now);
    Log.d('dokunma', 'hızlı mesaj: ${chat.id} ${chat.label}');
    widget.service.sendChat(chat.id);
    setState(() => _chatOpen = false);
    _showBubble(0, chat.id);
  }

  void _toggleChat() {
    Log.d('dokunma', _chatOpen ? 'hızlı mesaj paneli kapandı' : 'hızlı mesaj paneli açıldı');
    setState(() => _chatOpen = !_chatOpen);
    // Bekleme sürerken açıldıysa panel soluk durur; süre dolunca canlansın.
    final wait = _chatLimit.wait(DateTime.now());
    if (_chatOpen && wait > Duration.zero) {
      Timer(wait + const Duration(milliseconds: 30), () {
        if (mounted && _chatOpen) setState(() {});
      });
    }
  }

  void _onChange() {
    final c = _c;
    if (!mounted || c == null) return;
    if (c.result != null && _loggedRound != c.round) {
      _loggedRound = c.round;
      Log.i('ekran', 'el sonucu: kazanan=${c.result!.winner} puan değişimi=${c.result!.delta} toplam=${c.totals} not="${c.result!.note}"');
      if (c.round >= c.totalHands) {
        Log.i('ekran', 'MAÇ BİTTİ: ${c.teamMode ? 'kazanan takım=${c.championTeam}' : 'şampiyon=koltuk ${c.championSeat}'} toplamlar=${c.totals}');
        _refreshTickets(); // bilet 0 ise sonuç penceresi REKLAM İZLE gösterir
      }
    }
    if (c.turnToken != _seenToken) {
      _seenToken = c.turnToken;
      _turn.duration = c.turnDuration;
      _turn.reverse(from: 1);
    }
    if (c.toastId != _seenToast) {
      _seenToast = c.toastId;
      _toastVisible = true;
      _toastTimer?.cancel();
      _toastTimer = Timer(const Duration(milliseconds: 2600), () {
        if (mounted) setState(() => _toastVisible = false);
      });
    }
    _trackTable(c);
    setState(() {});
  }

  /// Masadaki perleri önceki hâliyle karşılaştırır: yeni per ya da işlenen taş varsa
  /// sahibinin koltuğundan hedefe uçan animasyon başlatır (video referansı: per per, sırayla).
  void _trackTable(GameController c) {
    final now = [
      for (final m in c.table) [for (final t in m.tiles) t.id]
    ];
    if (c.round != _prevRound || now.length < _prevTable.length) {
      _prevRound = c.round; // yeni el: animasyon yok, temiz başla
      _prevTable = now;
      _hiddenIds.clear();
      _flights.clear();
      return;
    }
    final prevIds = <int>{for (final g in _prevTable) ...g};
    final jobs = <_FlightJob>[];
    for (var i = 0; i < now.length; i++) {
      final fresh = [for (final id in now[i]) if (!prevIds.contains(id)) id];
      if (fresh.isEmpty) continue;
      final m = c.table[i];
      jobs.add(_FlightJob(i, m, fresh, newMeld: i >= _prevTable.length));
    }
    _prevTable = now;
    if (jobs.isEmpty) return;
    for (final j in jobs) {
      _hiddenIds.addAll(j.freshIds);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _launchFlights(jobs));
  }

  Offset? _seatSource(int owner) {
    final stack = _stackKey.currentContext?.findRenderObject();
    if (owner == 0) {
      final dp = _dropPoint;
      if (dp != null && DateTime.now().difference(_dropAt).inMilliseconds < 900) return dp;
      final rb = _rackKey.currentContext?.findRenderObject();
      if (rb is RenderBox && rb.hasSize) {
        return rb.localToGlobal(Offset(rb.size.width / 2, 0));
      }
      return null;
    }
    if (owner == 2) {
      if (stack is RenderBox && stack.hasSize) {
        return stack.localToGlobal(Offset(stack.size.width / 2, 26));
      }
      return null;
    }
    final rb = _seatKeys[owner].currentContext?.findRenderObject();
    if (rb is RenderBox && rb.hasSize) return rb.localToGlobal(rb.size.center(Offset.zero));
    return null;
  }

  void _launchFlights(List<_FlightJob> jobs) {
    if (!mounted || _c == null) return;
    final area = _meldKey.currentState;
    final stackCtx = _stackKey.currentContext;
    final created = <_FlightSpec>[];
    var k = 0;
    for (final j in jobs) {
      final rect = area?.meldRectGlobal(j.index);
      final src = _seatSource(j.meld.owner);
      if (area == null || stackCtx == null || rect == null || src == null) {
        _hiddenIds.removeAll(j.freshIds); // geometri yok: animasyonsuz göster
        continue;
      }
      final pair = j.meld.kind == MeldKind.pair;
      final tw = pair ? 22.0 : 20.0;
      final delay = Duration(milliseconds: 190 * (k < 5 ? k : 5));
      k++;
      if (j.newMeld) {
        created.add(_FlightSpec(
          id: _flightSeq++,
          tiles: j.meld.tiles,
          ids: j.freshIds,
          from: _toLocal(src),
          to: _toLocal(rect.center),
          fromWidth: tw * 1.5,
          toWidth: tw,
          vertical: pair,
          delay: delay,
          owner: j.meld.owner,
        ));
      } else {
        for (final id in j.freshIds) {
          final idx = j.meld.tiles.indexWhere((t) => t.id == id);
          if (idx < 0) {
            _hiddenIds.remove(id);
            continue;
          }
          final n = j.meld.tiles.length;
          final frac = (idx + .5) / n;
          final target = pair
              ? Offset(rect.center.dx, rect.top + rect.height * frac)
              : Offset(rect.left + rect.width * frac, rect.center.dy);
          created.add(_FlightSpec(
            id: _flightSeq++,
            tiles: [j.meld.tiles[idx]],
            ids: [id],
            from: _toLocal(src),
            to: _toLocal(target),
            fromWidth: tw * 1.7,
            toWidth: tw,
            vertical: false,
            delay: delay,
            owner: j.meld.owner,
          ));
          k++;
        }
      }
    }
    setState(() => _flights.addAll(created));
  }

  void _flightDone(_FlightSpec f) {
    if (!mounted) return;
    if (f.owner != 0) Sfx.I.tile(); // kendi taşımın sesi hamle anında çalıyor
    setState(() {
      _flights.removeWhere((x) => x.id == f.id);
      _hiddenIds.removeAll(f.ids);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _c, snap = _snap;
    // Geri tuşu / jesti: uyarısız çıkış yok.
    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: _confirmExit,
      child: Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(gradient: AppColors.bgGradient),
          child: (c == null || snap == null)
              ? (_starting && snap != null
                  ? GameStartPopup(seconds: _startLeft, table: snap)
                  : const Center(child: CircularProgressIndicator()))
              : _game(c, snap),
        ),
      ),
    );
  }

  Widget _game(GameController c, TableSnapshot t) {
    final sel = (_sel != null && c.rack.any((x) => x?.id == _sel!.id))
        ? _sel
        : null;
    Animation<double>? turnOf(int seat) =>
        c.turn == seat && c.result == null ? _turn : null;
    final leftTop = c.topDiscard(3);

    return Stack(key: _stackKey, fit: StackFit.expand, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 2, 6, 4),
        child: Column(children: [
          c.myTurn ? _topBarMine(c, t) : _topBar(c, t, turnOf(2)),
          Expanded(
            child: Row(children: [
              _sideColumn(
                top: DiscardSlot(tile: c.topDiscard(2), okey: c.okey),
                strip: KeyedSubtree(
                    key: _seatKeys[3],
                    child: PlayerStrip(
                    player: t.left,
                    turn: turnOf(3),
                    count: c.handCount(3),
                    tag: _tagFor(Seat.left, c.tagOf(3)),
                    openText: c.openLabel(3),
                    penalty: c.penalty[3])),
                bottom: DiscardSlot(
                    tile: leftTop,
                    okey: c.okey,
                    glow: c.canDraw && leftTop != null,
                    onTap: c.takeDiscard,
                    onDragStart: leftTop == null
                        ? null
                        : (g) => _srcStart(g, tile: leftTop),
                    onDragUpdate: _srcUpdate,
                    onDragEnd: _srcEnd,
                    onDragCancel: _srcCancel),
              ),
              const SizedBox(width: 4),
              Expanded(child: _table(c, sel)),
              const SizedBox(width: 4),
              _sideColumn(
                top: DiscardSlot(tile: c.topDiscard(1), okey: c.okey),
                strip: KeyedSubtree(
                    key: _seatKeys[1],
                    child: PlayerStrip(
                    player: t.right,
                    turn: turnOf(1),
                    count: c.handCount(1),
                    tag: _tagFor(Seat.right, c.tagOf(1)),
                    openText: c.openLabel(1),
                    penalty: c.penalty[1])),
                bottom: DiscardSlot(
                    key: _discardKey,
                    tile: c.topDiscard(0),
                    okey: c.okey,
                    glow: c.canPlay && sel != null,
                    onTap: () => _discardSelected(c, sel)),
              ),
            ]),
          ),
          SizedBox(height: 38, child: _infoRow(c, t, sel, turnOf(0))),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            SideActionButton(
                label: 'ÇİFT\nDİZ',
                icon: Icons.copy_all,
                active: c.pairMode,
                onTap: c.arrangePairs),
            const SizedBox(width: 4),
            Expanded(
                child: RackWidget(
                    key: _rackKey,
                    onDropOutside: (tile, g) => _onRackDrop(c, tile, g),
                    onDragStart: _onDragStart,
                    onDragEnd: _onDragEnd,
                    slots: c.rack,
                    columns: GameController.cols,
                    okey: c.okey,
                    selectedId: sel?.id,
                    markedId: c.myTurn ? c.lastDrawn?.id : null,
                    // Yalnızca yardımlı masada: işlenebilir taşlar işaretlenir.
                    isLayable: !c.settings.assisted
                        ? null
                        : (t) =>
                            c.result == null &&
                            !c.okey.isWild(t) &&
                            c.table.any((m) =>
                                m.accepts(t, c.okey) ||
                                m.trySwap(t, c.okey) != null),
                    onMove: c.moveRack,
                    onMoveGroup: c.moveRackGroup,
                    onTapTile: (tile) {
                      final off = _sel?.id == tile.id;
                      Log.d('dokunma', off ? 'seçim kaldırıldı: ${logTile(tile)}' : 'taş seçildi: ${logTile(tile)}');
                      setState(() => _sel = off ? null : tile);
                    })),
            const SizedBox(width: 4),
            SideActionButton(
                label: 'SERİ\nDİZ',
                icon: Icons.view_week,
                active: !c.pairMode,
                onTap: c.arrangeSeries),
          ]),
        ]),
      ),
      for (final f in _flights)
        TileFlight(
          key: ValueKey(f.id),
          tiles: f.tiles,
          from: f.from,
          to: f.to,
          fromWidth: f.fromWidth,
          toWidth: f.toWidth,
          vertical: f.vertical,
          delay: f.delay,
          onDone: () => _flightDone(f),
        ),
      if (_srcDrag)
        Positioned(
          left: _ghostPos.dx - 22,
          top: _ghostPos.dy - 30,
          child: IgnorePointer(
            child: _ghost != null
                ? TileWidget(
                    tile: _ghost!, width: 44, hidden: c.okey.isWild(_ghost!))
                : Container(
                    width: 44,
                    height: 59,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [AppColors.surfaceLight, AppColors.surface]),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: AppColors.goldLight, width: 2),
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 6)
                      ],
                    ),
                  ),
          ),
        ),
      Positioned(
        top: 44,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: AnimatedOpacity(
            opacity: _toastVisible ? 1 : 0,
            duration: const Duration(milliseconds: 250),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.82),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.gold.withOpacity(.7)),
                ),
                child: Text(c.toast ?? '',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ),
      ),
      // Hazır mesaj balonları (koltukların yanında; dokunuşu geçirir)
      Positioned.fill(
        child: IgnorePointer(
          child: Stack(children: [
            Align(
                alignment: const Alignment(0, -1),
                child: Padding(
                    padding: const EdgeInsets.only(top: 42),
                    child: ChatBubbleSlot(chat: _bubble[2], gen: _bubbleGen[2]))),
            Align(
                alignment: const Alignment(-1, -.15),
                child: Padding(
                    padding: const EdgeInsets.only(left: 64),
                    child: ChatBubbleSlot(chat: _bubble[3], gen: _bubbleGen[3]))),
            Align(
                alignment: const Alignment(1, -.15),
                child: Padding(
                    padding: const EdgeInsets.only(right: 64),
                    child: ChatBubbleSlot(chat: _bubble[1], gen: _bubbleGen[1]))),
            Align(
                alignment: const Alignment(-.55, .12),
                child: ChatBubbleSlot(chat: _bubble[0], gen: _bubbleGen[0])),
          ]),
        ),
      ),
      if (_chatOpen) ...[
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _chatOpen = false),
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          top: 40,
          right: 8,
          child: ChatPanel(
            ready: _chatLimit.canSend(DateTime.now()),
            onPick: _sendChat,
            onClose: () => setState(() => _chatOpen = false),
          ),
        ),
      ],
      if (c.result != null)
        Positioned.fill(
          child: ResultDialog(
            c: c,
            onLeave: () {
              Log.i('ekran', 'sonuç penceresinden masadan ayrıl');
              Navigator.of(context).maybePop();
            },
            onReplay: _replay,
            needAd: c.gameOver && _tickets != null && _tickets! < 1,
            paused: _adBusy,
            onWatchAd: _watchAdForTicket,
            onNoTicketTimeout: () {
              Log.i('ekran', 'bilet yok, reklam izlenmedi: ${kNoTicketWaitSeconds} sn doldu, lobiye dönülüyor');
              if (mounted) {
                Navigator.of(context)
                    .pop('Biletin bitti. Reklam izleyerek ya da günlük biletinle devam edebilirsin.');
              }
            },
            onNext: () {
              Log.i('ekran', 'SONRAKİ EL düğmesi');
              _sel = null;
              c.newRound();
            },
          ),
        ),
      if (_online && _presence.isAfk(Seat.me))
        Positioned.fill(child: AwayOverlay(onBack: _imHere)),
      if (!_online) const ConnectionBanner(),
    ]);
  }

  // ------------------------------------------------------------- parçalar

  /// Üst çubuğun iskeleti: geri oku SOLA, sohbet + skor butonları SAĞA sabit; ortadaki içerik kalan alana
  /// sığar (taşmaz, gerekirse küçülür). Böylece butonlar hiçbir durumda ortaya/sola kaymaz.
  Widget _topShell(GameController c, Widget middle) {
    final chat = AppSettings.I.chat;
    return SizedBox(
      width: double.infinity,
      height: 36,
      child: Stack(fit: StackFit.expand, children: [
        Padding(
          padding: EdgeInsets.only(left: 42, right: chat ? 76 : 42),
          child: middle,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: _iconBtn(Icons.arrow_back, () {
            Log.i('ekran', 'geri düğmesi: çıkış isteniyor');
            Navigator.of(context).maybePop();
          }),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (chat) _iconBtn(Icons.chat_bubble_rounded, _toggleChat),
            _iconBtn(Icons.leaderboard_rounded, () => _showScores(c)),
          ]),
        ),
      ]),
    );
  }

  Widget _topBar(GameController c, TableSnapshot t, Animation<double>? turn) =>
      _topShell(c, Row(children: [
        Expanded(
          child: Center(
              child: FittedBox(
            fit: BoxFit.scaleDown,
            child: PlayerBadge(
                player: t.top,
                compact: true,
                turn: turn,
                count: c.handCount(2),
                tag: _tagFor(Seat.top, c.tagOf(2)),
                openText: c.openLabel(2),
                penalty: c.penalty[2]),
          )),
        ),
      ]));

  /// Sıra bendeyken: süre çubuğu üstü kaplar (referans oyundaki gibi).
  Widget _topBarMine(GameController c, TableSnapshot t) => _topShell(c, Row(children: [
        Expanded(flex: 5, child: TurnTimerBar(turn: _turn, total: c.turnDuration)),
        const SizedBox(width: 8),
        Flexible(
          flex: 4,
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (c.openLabel(0) != null) ...[
                  OpenScoreBadge(text: c.openLabel(0)!),
                  const SizedBox(width: 6),
                ],
                if (c.penalty[0] > 0) ...[
                  PenaltyBadge(points: c.penalty[0]),
                  const SizedBox(width: 6),
                ],
                PlayerBadge(
                    player: t.top,
                    compact: true,
                    count: c.handCount(2),
                    tag: _tagFor(Seat.top, c.tagOf(2)),
                    openText: c.openLabel(2),
                    penalty: c.penalty[2]),
              ]),
            ),
          ),
        ),
      ]));

  Widget _iconBtn(IconData i, VoidCallback onTap) => IconButton(
        onPressed: onTap,
        icon: Icon(i, size: 20),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        visualDensity: VisualDensity.compact,
      );

  Widget _ruleChipV(RuleChip r) => Container(
        width: 62,
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(vertical: 3),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: r.on ? AppColors.good.withOpacity(.75) : Colors.black26,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(r.label,
            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700)),
      );

  Widget _sideColumn(
          {required Widget top, required Widget strip, required Widget bottom}) =>
      SizedBox(
        width: 50,
        child: Column(children: [
          Expanded(flex: 3, child: top),
          const SizedBox(height: 4),
          Expanded(flex: 5, child: strip),
          const SizedBox(height: 4),
          Expanded(flex: 3, child: bottom),
        ]),
      );

  Widget _table(GameController c, Tile? sel) => Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.felt, AppColors.feltDark]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.gold, width: 3),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
        ),
        child: Row(children: [
          Expanded(
            child: MeldArea(
              key: _meldKey,
              melds: c.table,
              hiddenIds: _hiddenIds,
              pending: c.pendingOpen?.groups ?? const [],
              pendingPairs: c.pendingOpen?.mode == OpenMode.pairs,
              // Katlamalı masada biri açtıysa sonraki açışın en azı (seri: puan, çift: adet).
              seriesMin: c.settings.folding &&
                      c.result == null &&
                      [0, 1, 2, 3].any((s) => c.opened[s] == OpenMode.series)
                  ? c.requiredOpen(-1)
                  : null,
              pairsMin: c.settings.folding &&
                      c.result == null &&
                      [0, 1, 2, 3].any((s) => c.opened[s] == OpenMode.pairs)
                  ? c.requiredPairs(-1)
                  : null,
              okey: c.okey,
              center: _center(c),
              centerWidth: 72,
              highlight: (m) {
                final hl = _dragTile ?? sel;
                return c.settings.assisted &&
                    hl != null &&
                    c.result == null &&
                    (m.accepts(hl, c.okey) ||
                        m.trySwap(hl, c.okey) != null);
              },
              onTapMeld: (i) {
                final s = sel;
                if (s == null) {
                  Log.d('dokunma', 'per $i dokunuldu ama seçili taş yok');
                  return;
                }
                c.layOff(s, meldIndex: i);
              },
            ),
          ),
        ]),
      );

  Widget _center(GameController c) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Kural etiketleri: Tek / Yardımlı / Katlamalı / 1 El (alt alta, göstergenin üstünde).
          for (final r in (_snap?.rules ?? const <RuleChip>[])) _ruleChipV(r),
          const SizedBox(height: 6),
          const Text('GÖSTERGE',
              style: TextStyle(
                  fontSize: 8.5,
                  letterSpacing: .6,
                  fontWeight: FontWeight.w700,
                  color: Colors.white60)),
          const SizedBox(height: 3),
          TileWidget(tile: c.indicator, width: 34),
          const SizedBox(height: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: c.drawFromDeck,
            onPanStart: (d) => _srcStart(d.globalPosition),
            onPanUpdate: (d) => _srcUpdate(d.globalPosition),
            onPanEnd: (_) => _srcEnd(),
            onPanCancel: _srcCancel,
            child: Container(
              width: 34,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.surfaceLight, AppColors.surface]),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: c.canDraw ? AppColors.goldLight : AppColors.gold.withOpacity(.5),
                    width: c.canDraw ? 2 : 1),
                boxShadow: c.canDraw
                    ? [BoxShadow(color: AppColors.gold.withOpacity(.5), blurRadius: 8)]
                    : null,
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('${c.deck.length}',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w900)),
                const Text('DESTE',
                    style: TextStyle(fontSize: 7, color: Colors.white60)),
              ]),
            ),
          ),
        ]),
      );

  Widget _infoRow(
      GameController c, TableSnapshot t, Tile? sel, Animation<double>? turn) {
    final opened = c.opened[0] != null;
    final canAct = c.canPlay;
    return Row(children: [
      Expanded(
        flex: 2,
        child: Align(
          alignment: Alignment.centerRight,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(c.statusText,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: c.myTurn ? AppColors.goldLight : Colors.white60)),
          ),
        ),
      ),
      const SizedBox(width: 8),
      // Sıra bendeyken rozet gizlenir (süre çubuğu üstte); değilken görünür.
      if (!c.myTurn) ...[
        PlayerBadge(
            player: t.me,
            compact: true,
            turn: turn,
            tag: c.tagOf(0),
            openText: c.openLabel(0),
            penalty: c.penalty[0]),
        const SizedBox(width: 8),
      ],
      Expanded(
        flex: 3,
        child: Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(children: [
              if (c.hasPendingOpen)
                GameButton(
                    label: 'GERİ TOPLA',
                    primary: true,
                    icon: Icons.undo_rounded,
                    onTap: c.collectPending),
              if (c.canReturnDiscard) ...[
                GameButton(
                    label: 'GERİ BIRAK',
                    icon: Icons.undo_rounded,
                    onTap: c.returnDiscard),
                const SizedBox(width: 6),
              ],
              if (canAct && !c.hasPendingOpen) ...[
                if (!opened) ...[
                  GameButton(
                      label: 'SERİ AÇ',
                      primary: true,
                      icon: Icons.view_week,
                      onTap: c.openSeries),
                  const SizedBox(width: 6),
                  GameButton(
                      label: 'ÇİFT AÇ',
                      primary: true,
                      icon: Icons.copy_all,
                      onTap: c.openPairs),
                  const SizedBox(width: 6),
                ] else ...[
                  GameButton(
                      label: c.opened[0] == OpenMode.pairs
                          ? 'ÇİFT AÇ'
                          : 'SERİ AÇ',
                      primary: true,
                      icon: Icons.table_rows_rounded,
                      onTap: c.opened[0] == OpenMode.pairs
                          ? c.openPairs
                          : c.openSeries),
                  const SizedBox(width: 6),
                  if (c.canLayPairs) ...[
                    GameButton(
                        label: 'ÇİFT AÇ',
                        primary: true,
                        icon: Icons.copy_all,
                        onTap: c.openPairs),
                    const SizedBox(width: 6),
                  ],
                  GameButton(
                      label: 'TAŞLARI İŞLE',
                      icon: Icons.auto_fix_high,
                      onTap: c.autoLayOff),
                  const SizedBox(width: 6),
                ],
              ],
              if (canAct && sel != null && !c.hasPendingOpen) ...[
                if (opened) ...[
                  GameButton(label: 'İŞLE', onTap: () => c.layOff(sel)),
                  const SizedBox(width: 6),
                ],
                GameButton(
                    label: 'AT',
                    icon: Icons.south_rounded,
                    onTap: () => _discardSelected(c, sel)),
              ],
            ]),
          ),
        ),
      ),
      // Yardımlı masada: eldeki sayı ıstakanın hemen üstünde, sıra kimdeyse de görünür.
      if (c.settings.assisted) ...[
        const SizedBox(width: 8),
        _scoreBubble(c),
      ],
    ]);
  }

  void _discardSelected(GameController c, Tile? sel) {
    Log.d('dokunma', 'AT düğmesi/yuvası: seçili=${logTile(sel)}');
    if (sel == null || !c.canPlay) return;
    setState(() => _sel = null);
    c.discard(sel);
  }

  /// Eldeki sayı (yardımlı masada, ıstakanın hemen üstünde; sıra bende de başkasında da görünür).
  /// Açılmamışken: seri modunda puan (açma sınırına ulaşınca yeşil; 101'de 101), çift modunda çift sayısı
  /// (5'te yeşil). Açıldıktan sonra: elde kalan taşların PUAN toplamı (çift açtıysan ×2). Altındaki küçük ok ıstakayı gösterir.
  Widget _scoreBubble(GameController c) {
    final bool ok;
    final String label;
    final String value;
    String? mult; // çift açınca elde kalan puan 2 ile çarpılır
    if (c.opened[0] != null) {
      ok = true;
      label = 'ELDE';
      final v = c.myHandValue * c.myHandMultiplier;
      value = '$v';
      mult = c.myHandMultiplier > 1 ? '×${c.myHandMultiplier}' : null;
    } else if (c.pairMode) {
      final n = HandScorer.pairCount(c.rack, GameController.cols, c.okey);
      ok = n >= 5;
      label = 'ÇİFT';
      value = '$n';
    } else {
      final sc = HandScorer.score(c.rack, GameController.cols, c.okey);
      final need = c.requiredOpen(0);
      ok = sc >= need;
      label = 'PUAN';
      value = need > GameController.openLimit ? '$sc/$need' : '$sc';
    }
    final color = ok ? const Color(0xFF2E8B57) : AppColors.surfaceLight;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ok ? AppColors.good : AppColors.gold, width: 1.5),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 8.5, letterSpacing: .5, fontWeight: FontWeight.w700, color: Colors.white70)),
          const SizedBox(width: 6),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          if (mult != null) ...[
            const SizedBox(width: 3),
            Text(mult,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.goldLight)),
          ],
        ]),
      ),
      CustomPaint(size: const Size(12, 5), painter: _PointerDown(ok ? AppColors.good : AppColors.gold)),
    ]);
  }

  void _showScores(GameController c) {
    Log.d('dokunma', 'puan tablosu açıldı');
    Widget row(String name, int total) => Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(.32),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(children: [
            Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
            Text('$total',
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppColors.goldLight)),
          ]),
        );
    showGamePopup<void>(
      context,
      builder: (ctx) => GamePopup(
        title: 'SKOR TABLOSU',
        subtitle: '${c.round}/${c.totalHands}. el',
        maxWidth: 420,
        onClose: () => Navigator.pop(ctx),
        actions: [
          PopupButton(
              label: 'KAPAT',
              kind: CandyKind.green,
              width: 170,
              height: 44,
              onTap: () => Navigator.pop(ctx)),
        ],
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (c.teamMode)
            for (final tm in const [
              [0, 2],
              [1, 3]
            ])
              row('${c.names[tm[0]]} + ${c.names[tm[1]]}', c.teamTotal(tm[0]))
          else
            for (var s = 0; s < 4; s++) row(c.names[s], c.totals[s]),
          const SizedBox(height: 6),
          const Text('Düşük puan iyidir.',
              style: TextStyle(fontSize: 11.5, color: Colors.white54)),
        ]),
      ),
    );
  }
}

/// Skor balonunun altındaki küçük aşağı ok (ıstakayı gösterir).
class _PointerDown extends CustomPainter {
  final Color color;
  const _PointerDown(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PointerDown old) => old.color != color;
}


/// Bir uçuşun tanımı (TileFlight'a verilir).
class _FlightSpec {
  final int id;
  final List<Tile> tiles;
  final List<int> ids; // uçuş bitince masada görünür olacak taşlar
  final Offset from, to;
  final double fromWidth, toWidth;
  final bool vertical;
  final Duration delay;
  final int owner;
  const _FlightSpec({
    required this.id,
    required this.tiles,
    required this.ids,
    required this.from,
    required this.to,
    required this.fromWidth,
    required this.toWidth,
    required this.vertical,
    required this.delay,
    required this.owner,
  });
}

/// Masada değişen bir per: yeni per mi, yoksa işlenen taşlar mı.
class _FlightJob {
  final int index;
  final Meld meld;
  final List<int> freshIds;
  final bool newMeld;
  const _FlightJob(this.index, this.meld, this.freshIds, {required this.newMeld});
}
