import 'dart:async';
import '../diagnostics/app_log.dart';
import 'package:flutter/material.dart';
import '../models/player.dart';
import '../models/table_models.dart';
import '../services/ad_service.dart';
import '../services/game_service.dart';
import '../theme/app_theme.dart';
import '../widgets/create_table_dialog.dart';
import '../widgets/game_popup.dart';
import '../widgets/lobby_widgets.dart';
import '../widgets/table_card.dart';
import '../models/app_settings.dart';
import 'game_screen.dart';
import 'settings_screen.dart';

/// Masa listesi: seçilen odadaki masalar yatay kaydırılır, ortadaki büyük görünür.
class RoomsScreen extends StatefulWidget {
  final GameService service;

  final bool turbo, autoCreate;
  /// Oyun sonu reklam bileti için GameScreen'e iletilir.
  final AdService ads;
  const RoomsScreen(
      {super.key,
      required this.service,
      this.ads = const MockAdService(),
      this.turbo = false,
      this.autoCreate = false});

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  List<TableInfo>? _tables;
  Player? _me;
  String? _error;
  Timer? _timer;
  StreamSubscription<void>? _lobbySub;
  bool _autoDone = false;

  late bool _fTurbo = widget.turbo;
  bool _fFold = false, _fAssist = false, _fOpen = false;

  final _page = PageController(viewportFraction: .62);

  @override
  void initState() {
    super.initState();
    _load();
    // Gerçek sunucu lobiyi değişince kendisi yollar (giden mesaj ücretsiz): yalnız dinleriz, istek atmayız.
    // Zamanlayıcı SADECE bildirim vermeyen sahte servis için (her 'lobby' isteği Cloudflare'de kotadan sayılır).
    final changes = widget.service.tablesChanged;
    if (changes != null) {
      _lobbySub = changes.listen((_) => _reloadTables());
    } else {
      _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
    }
  }

  /// Sunucu lobi güncellemesi geldi: yalnız masa listesini tazele (önbellekten gelir, ağ isteği yok).
  Future<void> _reloadTables() async {
    try {
      final tables = await widget.service.fetchTables();
      if (!mounted) return;
      setState(() => _tables = tables);
    } catch (e, s) {
      Log.w('masalar', 'lobi güncellemesi işlenemedi: $e\n$s');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lobbySub?.cancel();
    _page.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final tables = await widget.service.fetchTables();
      final me = await widget.service.fetchMyProfile();
      if (!mounted) return;
      setState(() {
        _tables = tables;
        _me = me;
        _error = null;
      });
      if (widget.autoCreate && !_autoDone) {
        _autoDone = true;
        _create();
      }
    } catch (e, s) {
      Log.e('masalar', 'masa listesi yüklenemedi', e, s);
      if (!mounted) return;
      if (_tables == null) {
        setState(() => _error = 'Masalar yüklenemedi. Tekrar dene.');
      }
    }
  }

  List<TableInfo> get _visible {
    final l = (_tables ?? const <TableInfo>[]).where((t) {
      if (_fTurbo && !t.settings.turbo) return false;
      if (_fFold && !t.settings.folding) return false;
      if (_fAssist && !t.settings.assisted) return false;
      if (_fOpen && t.isFull) return false;
      return true;
    }).toList();
    // dolu masalar sona
    l.sort((a, b) => (a.isFull ? 1 : 0).compareTo(b.isFull ? 1 : 0));
    return l;
  }

  int get _totalOnline =>
      (_tables ?? const <TableInfo>[]).fold(0, (a, t) => a + t.playerCount);

  String get _tabLabel {
    const base = 'TÜM MASALAR';
    return _fTurbo ? '$base · TURBO' : base;
  }

  // --------------------------------------------------------- eylemler

  Future<void> _openGame(
      {String? tableId, TableSettings? quick}) async {
    Log.i('masalar', 'oyuna giriş: masa=${tableId ?? 'hemen oyna'} quick=${quick != null}');
    final msg = await Navigator.of(context).push<String>(MaterialPageRoute(
        settings: const RouteSettings(name: 'GameScreen'),
        builder: (_) => GameScreen(
            service: widget.service,
            ads: widget.ads,
            tableId: tableId,
            quick: quick)));
    if (!mounted) return;
    Log.i('masalar', 'oyundan dönüldü: mesaj=$msg');
    if (msg != null) showToast(context, msg);
    _load();
  }

  Future<void> _sit(TableInfo t) async {
    Log.i('masalar', 'masaya otur isteği: ${t.name} dolu=${t.isFull} ');
    if (t.isFull) return showToast(context, 'Masa dolu.', kind: ToastKind.warn);
    await _openGame(tableId: t.id);
  }

  /// Hemen Oyna: ayarlardaki tercihlere göre masa bulur / kurar.
  void _quick() {
    _openGame(quick: AppSettings.I.quick(turbo: _fTurbo));
  }

  Future<void> _create() async {
    final r = await showGamePopup<NewTable>(
      context,
      builder: (_) => CreateDialog(
        initial: TableSettings(turbo: _fTurbo),
      ),
    );
    if (r == null) return;
    Log.i('masalar', 'masa kuruluyor');
    try {
      final t = await widget.service
          .createTable(name: r.name, settings: r.settings);
      if (!mounted) return;
      await _openGame(tableId: t.id);
    } on JoinException catch (e) {
      Log.w('masalar', 'masa kurulamadı: ${e.message}');
      if (mounted) showToast(context, e.message, kind: ToastKind.error);
    } catch (e, s) {
      Log.e('masalar', 'masa kurma HATASI', e, s);
      if (mounted) showToast(context, 'Masa kurulamadı.', kind: ToastKind.error);
    }
  }

  Future<void> _filter() async {
    var fold = _fFold, assist = _fAssist, turbo = _fTurbo;
    var open = _fOpen;
    final ok = await showGamePopup<bool>(
      context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        Widget pill(String text, bool on, VoidCallback tap) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => set(tap),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: on ? AppColors.gold : Colors.black26,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: on ? Colors.transparent : Colors.white12),
                ),
                child: Text(text,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: on ? Colors.black : Colors.white)),
              ),
            );
        return GamePopup(
          title: 'MASA FİLTRELE',
          icon: Icons.filter_list_rounded,
          maxWidth: 520,
          onClose: () => Navigator.pop(ctx, false),
          actions: [
            PopupButton(
                label: 'İPTAL',
                kind: CandyKind.gray,
                width: 150,
                height: 46,
                onTap: () => Navigator.pop(ctx, false)),
            PopupButton(
                label: 'UYGULA',
                kind: CandyKind.green,
                width: 170,
                height: 46,
                onTap: () => Navigator.pop(ctx, true)),
          ],
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              pill('Katlamalı', fold, () => fold = !fold),
              pill('Yardımlı', assist, () => assist = !assist),
              pill('Turbo', turbo, () => turbo = !turbo),
              pill('Boş yer var', open, () => open = !open),
            ]),
          ]),
        );
      }),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _fFold = fold;
      _fAssist = assist;
      _fTurbo = turbo;
      _fOpen = open;
    });
    if (_page.hasClients) _page.jumpToPage(0);
  }

  // --------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Column(children: [
              TopHud(player: _me),
              const SizedBox(height: 6),
              _noticeBanner(),
              Expanded(child: _body()),
              _bottomBar(),
            ]),
          ),
        ),
      ),
    );
  }

  /// Sunucu uyarısı (kota doldu / masa kapasitesi dolu): lobinin üstünde turuncu şerit.
  Widget _noticeBanner() {
    final msg = widget.service.lobbyNotice;
    if (msg == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.orange.withOpacity(.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.orange.withOpacity(.7)),
      ),
      child: Row(children: [
        const Icon(Icons.info_outline, size: 18, color: AppColors.orange),
        const SizedBox(width: 8),
        Expanded(
            child: Text(msg,
                style: const TextStyle(
                    color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700))),
      ]),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
          child: Text(_error!, style: const TextStyle(color: Colors.white70)));
    }
    if (_tables == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final list = _visible;
    if (list.isEmpty) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Bu filtreye uygun masa yok.',
            style: TextStyle(color: Colors.white70, fontSize: 15)),
        const SizedBox(height: 10),
        CandyButton(
            onTap: _create,
            kind: CandyKind.orange,
            radius: 12,
            width: 150,
            height: 38,
            child: const Text('MASA AÇ')),
      ]));
    }
    return LayoutBuilder(builder: (context, box) {
      final double h = (box.maxHeight - 20).clamp(150.0, 300.0).toDouble();
      return PageView.builder(
        controller: _page,
        itemCount: list.length,
        itemBuilder: (_, i) => AnimatedBuilder(
          animation: _page,
          builder: (_, child) {
            double d = 1;
            if (_page.hasClients && _page.position.haveDimensions) {
              d = ((_page.page ?? 0) - i).abs().clamp(0.0, 1.0).toDouble();
            } else {
              d = i == 0 ? 0 : 1;
            }
            final s = 1 - .18 * d;
            return Center(
              child: Transform.scale(
                  scale: s,
                  child: Opacity(opacity: 1 - .35 * d, child: child)),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: SizedBox(
              height: h,
              child: TableCard(table: list[i], onSit: _sit),
            ),
          ),
        ),
      );
    });
  }

  Widget _bottomBar() => SizedBox(
        height: 74,
        child: Stack(clipBehavior: Clip.none, children: [
          // oda adı sekmesi
          Align(
            alignment: Alignment.topCenter,
            child: GestureDetector(
              onTap: _filter,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 2),
                decoration: const BoxDecoration(
                  color: AppColors.navy,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                ),
                child: Text(_tabLabel,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFE8D9B8))),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: 56,
              child: Row(children: [
                RoundBtn(
                    icon: Icons.arrow_back,
                    kind: CandyKind.red,
                    onTap: () => Navigator.of(context).pop()),
                const SizedBox(width: 6),
                RoundBtn(
                    icon: Icons.groups,
                    onTap: () => showToast(context, 'Çok yakında!')),
                const SizedBox(width: 6),
                RoundBtn(
                    icon: Icons.leaderboard,
                    onTap: () => showToast(context, 'Çok yakında!')),
                const Spacer(),
                CandyButton(
                    onTap: _create,
                    kind: CandyKind.orange,
                    radius: 16,
                    width: 118,
                    height: 50,
                    child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, size: 24),
                          SizedBox(width: 2),
                          Text('MASA\nAÇ',
                              style: TextStyle(fontSize: 13, height: 1)),
                        ])),
                const SizedBox(width: 6),
                CandyButton(
                    onTap: _me == null ? null : _quick,
                    kind: CandyKind.green,
                    radius: 16,
                    width: 170,
                    height: 54,
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('HEMEN OYNA',
                              style: TextStyle(fontSize: 18, height: 1.1)),
                          Text('$_totalOnline Oyuncu Çevrimiçi',
                              style: const TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.w700)),
                        ])),
                const SizedBox(width: 6),
                CandyButton(
                    onTap: _filter,
                    kind: CandyKind.blue,
                    radius: 16,
                    width: 118,
                    height: 50,
                    child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('MASA\nFİLTRELE',
                              style: TextStyle(fontSize: 12, height: 1)),
                          SizedBox(width: 3),
                          Icon(Icons.search, size: 22),
                        ])),
                const Spacer(),
                RoundBtn(
                    icon: Icons.settings,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        settings: const RouteSettings(name: 'SettingsScreen'),
                        builder: (_) => SettingsScreen(player: _me)))),
              ]),
            ),
          ),
        ]),
      );
}
