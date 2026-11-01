import 'dart:async';
import 'package:flutter/material.dart';
import '../diagnostics/app_log.dart';
import '../models/player.dart';
import '../models/rewards.dart';
import '../services/ad_service.dart';
import '../widgets/level_up_dialog.dart';
import '../widgets/ticket_daily_dialog.dart';
import '../models/profile.dart';
import '../services/profile_service.dart';
import 'profile_screen.dart';
import '../models/table_models.dart';
import '../services/account_service.dart';
import '../services/game_service.dart';
import '../services/inbox_service.dart';
import '../services/push_service.dart';
import '../theme/app_theme.dart';
import '../widgets/lobby_widgets.dart';
import '../widgets/reward_popup.dart';
import '../models/app_settings.dart';
import 'game_screen.dart';
import 'inbox_screen.dart';
import 'settings_screen.dart';
import 'store_screen.dart';
import 'rooms_screen.dart';

/// Ana ekran: üst çubuk, yatay kaydırmalı oda kartları, alt çubuk.
class LobbyScreen extends StatefulWidget {
  final GameService service;
  final InboxService inbox;
  final PushService push;

  /// Verilirse avatara dokununca profil düzenlenir; kaydedilince [onProfileChanged] çağrılır.
  final ProfileService? profiles;
  final void Function(Profile)? onProfileChanged;

  /// Misafir/Google hesap değiştirme (Ayarlar > HESABIM). Hesap değişince [onAccountSwitched] çağrılır.
  final AccountService? account;
  final VoidCallback? onAccountSwitched;

  /// Ödüllü reklam (günlük ödül 2x ve "Reklam izle" butonu). Şimdilik sahte; gerçek reklam için değiştir.
  final AdService ads;
  const LobbyScreen(
      {super.key,
      required this.service,
      required this.inbox,
      this.push = const NoopPushService(),
      this.profiles,
      this.onProfileChanged,
      this.account,
      this.onAccountSwitched,
      this.ads = const MockAdService()});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  Player? _me;
  List<TableInfo> _tables = const [];
  int _unread = 0; // mesaj kutusunda AL bekleyen / okunmamış sayısı

  // bilet bakiyesi + günlük bilet + reklam bileti
  TicketStatus? _tk;
  int _adWait = 0; // reklam biletine kalan saniye (her saniye geri sayar)
  bool _adBusy = false;
  bool _levelBusy = false; // seviye kutlaması açıkken ikinci kez açılmasın
  bool _dailyShown = false; // giriş penceresi uygulama açılışında bir kez çıkar
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load().then((_) => _autoDaily());
    widget.push
        .init(onOpenInbox: _openInbox, onInboxChanged: _load)
        .catchError((Object e, StackTrace s) {
      Log.e('push', 'push servisi başlatılamadı', e, s);
    });
  }

  Future<void> _loadUnread() async {
    try {
      final msgs = await widget.inbox.fetch();
      final n = msgs.where((m) => !m.claimed).length;
      if (!mounted) return;
      setState(() => _unread = n);
    } catch (e, s) {
      Log.e('lobi', 'mesaj kutusu sayısı alınamadı', e, s);
    }
  }

  void _openInbox() {
    if (!mounted) return;
    _push(InboxScreen(service: widget.inbox));
  }

  Future<void> _load() async {
    Log.d('lobi', 'profil ve masalar yükleniyor');
    try {
      final me = await widget.service.fetchMyProfile();
      final tables = await widget.service.fetchTables();
      if (!mounted) return;
      setState(() {
        _me = me;
        _tables = tables;
      });
      Log.i('lobi', 'yüklendi: çip=${me.chipCount} masa=${tables.length}');
    } catch (e, s) {
      Log.e('lobi', 'lobi verisi yüklenemedi', e, s);
    }
    await _loadUnread();
    await _loadRewards();
  }

  /// Günlük ödül ve reklam durumu. Hata lobiyi bozmaz (butonlar pasif kalır).
  Future<void> _loadRewards() async {
    try {
      final t = await widget.service.fetchTicketStatus();
      if (!mounted) return;
      setState(() {
        _tk = t;
        _adWait = t.adWaitSeconds;
      });
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && _adWait > 0) setState(() => _adWait--);
      });
      await _maybeLevelUp(t);
    } catch (e, s) {
      Log.e('ödül', 'ödül durumu alınamadı', e, s);
    }
  }

  /// Seviye atlandıysa kutlama + hediye bilet penceresi (AL'a basınca bilet geçer). Maçtan lobiye dönünce de çıkar.
  Future<void> _maybeLevelUp(TicketStatus t) async {
    if (_levelBusy || !mounted || t.pendingLevels <= 0) return;
    _levelBusy = true;
    try {
      final r = await showLevelUp(context, service: widget.service, level: t.level, pending: t.pendingLevels);
      if (!mounted || r == null) return;
      setState(() => _tk = TicketStatus(
            tickets: r.tickets,
            adWaitSeconds: t.adWaitSeconds,
            dailyCanClaim: t.dailyCanClaim,
            xp: t.xp,
            leaguePoints: t.leaguePoints,
            level: r.level,
            levelClaimed: r.level,
          ));
    } finally {
      _levelBusy = false;
    }
  }

  /// Giriş yapılınca günlük ödül alınabiliyorsa pencere kendiliğinden açılır (uygulama açılışında bir kez).
  Future<void> _autoDaily() async {
    if (_dailyShown || !mounted || _tk?.dailyCanClaim != true) return;
    _dailyShown = true;
    await _openDaily();
  }

  Future<void> _openDaily() async {
    final t = _tk;
    if (t == null) return;
    if (!t.dailyCanClaim) {
      showToast(context, 'Bugünün biletlerini aldın. Yarın $kDailyTickets bilet daha seni bekliyor.',
          icon: Icons.card_giftcard_rounded);
      return;
    }
    final r = await showTicketDaily(context, service: widget.service, ads: widget.ads);
    if (!mounted) return;
    _load(); // bakiye arkada hemen güncellensin
    if (r != null) {
      showToast(context, '+${r.amount} bilet! Bakiyen: ${r.tickets}',
          kind: ToastKind.success, icon: Icons.confirmation_number_rounded);
    }
  }

  Future<void> _watchAd() async {
    if (_adBusy) return;
    if (_tk == null) {
      _loadRewards();
      return;
    }
    if (_adWait > 0) {
      showToast(context, 'Yeni reklam ${_mmss(_adWait)} sonra hazır.',
          kind: ToastKind.warn, icon: Icons.timer_rounded);
      return;
    }
    _adBusy = true;
    try {
      final watched = await widget.ads.showRewarded(context);
      if (!watched || !mounted) return;
      final st = await widget.service.claimAdTicket();
      if (!mounted) return;
      setState(() => _adWait = st.waitSeconds);
      _load();
      showToast(context, '+1 bilet! Yeni reklam ${_mmss(st.waitSeconds)} sonra hazır.',
          kind: ToastKind.success, icon: Icons.confirmation_number_rounded);
    } on JoinException catch (e) {
      if (mounted) showToast(context, e.message, kind: ToastKind.error);
      _loadRewards();
    } catch (e, s) {
      Log.e('ödül', 'reklam bileti alınamadı', e, s);
      if (mounted) showToast(context, 'Bilet alınamadı, tekrar dene.', kind: ToastKind.error);
    } finally {
      _adBusy = false;
    }
  }

  static String _mmss(int sec) =>
      '${(sec ~/ 60).toString().padLeft(2, '0')}:${(sec % 60).toString().padLeft(2, '0')}';

  int get _totalOnline => _tables.fold(0, (a, t) => a + t.playerCount);

  Future<void> _push(Widget page) async {
    Log.i('lobi', 'sayfaya gidiliyor: ${page.runtimeType}');
    await Navigator.of(context).push(MaterialPageRoute(
        settings: RouteSettings(name: page.runtimeType.toString()),
        builder: (_) => page));
    Log.d('lobi', 'sayfadan dönüldü: ${page.runtimeType}');
    _load();
  }

  void _soon() => showToast(context, 'Çok yakında!');

  /// Sağ üstteki mağaza butonu: bilet paketleri sayfası.
  void _openStore() => _push(StoreScreen(tickets: _tk?.tickets));

  Future<void> _editProfile() async {
    final svc = widget.profiles;
    if (svc == null) return;
    final me = _me;
    final cur = Profile(name: me?.name ?? '', avatar: me?.avatar ?? 0, named: true);
    Log.i('lobi', 'profil düzenleme açıldı');
    final res = await Navigator.of(context).push<Profile>(MaterialPageRoute(
        settings: const RouteSettings(name: 'ProfileScreen'),
        builder: (_) => ProfileScreen(service: svc, initial: cur)));
    if (res == null || !mounted) return;
    widget.onProfileChanged?.call(res);
    _load();
  }

  void _pickRoom({bool turbo = false}) {
    Log.i('lobi', 'masa listesi açılıyor: turbo=$turbo');
    _push(RoomsScreen(service: widget.service, ads: widget.ads, turbo: turbo));
  }

  void _quick() async {
    Log.i('lobi', 'HEMEN OYNA');
    final msg = await Navigator.of(context).push<String>(MaterialPageRoute(
        settings: const RouteSettings(name: 'GameScreen(hemen oyna)'),
        builder: (_) => GameScreen(
            service: widget.service,
            ads: widget.ads,
            quick: AppSettings.I.quick())));
    Log.i('lobi', 'oyundan dönüldü: mesaj=$msg');
    if (msg != null && mounted) showToast(context, msg);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Column(children: [
              TopHud(player: _me, tickets: _tk?.tickets, level: _tk?.level, levelProgress: _tk?.levelProgress, onShop: _openStore, onProfile: widget.profiles == null ? null : _editProfile),
              const SizedBox(height: 8),
              Expanded(child: _cards()),
              const SizedBox(height: 8),
              _bottomBar(),
            ]),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ kartlar

  Widget _cards() {
    final classic = _tables.where((t) => !t.settings.turbo);
    final turbo = _tables.where((t) => t.settings.turbo);
    int sum(Iterable<TableInfo> l) => l.fold(0, (a, t) => a + t.playerCount);
    return Row(children: [
      SizedBox(
        width: 150,
        child: Column(children: [
          Expanded(child: _dailyCard()),
          const SizedBox(height: 6),
          Expanded(child: _miniCard('GÖREVLER', 'Gör', Icons.flag)),
          const SizedBox(height: 6),
          Expanded(child: _miniCard('TURNUVA', 'Sıralama', Icons.emoji_events)),
        ]),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Row(children: [
          Expanded(
            child: _roomCard(
              title: 'KLASİK',
              sub: 'ODALAR',
              players: sum(classic),
              art: const _TilesArt(a: '10', b: '1', color: Color(0xFF1E6BD0)),
              onPick: _pickRoom,
              onCreate: () => _push(RoomsScreen(
                  service: widget.service, ads: widget.ads, autoCreate: true)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _roomCard(
              title: 'TURBO',
              sub: 'MASALAR · 15 sn',
              players: sum(turbo),
              art: const _TilesArt(a: '5', b: '1', color: Color(0xFFB3221A)),
              onPick: () => _pickRoom(turbo: true),
              onCreate: () => _push(RoomsScreen(
                  service: widget.service,
                  ads: widget.ads,
                  turbo: true,
                  autoCreate: true)),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _dailyCard() {
    final d = _tk;
    final ready = d?.dailyCanClaim == true;
    return GestureDetector(
      onTap: _openDaily,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: ready
                  ? const [AppColors.orange, AppColors.orangeDark]
                  : const [Color(0xFF4A5A66), Color(0xFF29343D)]),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: ready ? AppColors.goldLight : Colors.black45, width: ready ? 1.5 : 1),
        ),
        child: Row(children: [
          Stack(clipBehavior: Clip.none, children: [
            Icon(Icons.card_giftcard, size: 30, color: ready ? Colors.white : Colors.white54),
            if (ready)
              Positioned(
                  right: -3,
                  top: -3,
                  child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: AppColors.bad,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5)))),
          ]),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('GÜNLÜK BİLET',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          color: ready ? Colors.white : Colors.white70)),
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(ready ? Icons.touch_app : Icons.check_circle,
                        size: 12, color: ready ? Colors.white : AppColors.good),
                    const SizedBox(width: 3),
                    Text(d == null ? '...' : (ready ? 'Topla' : 'Alındı'),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: ready ? Colors.white : Colors.white54)),
                  ]),
                ]),
          ),
        ]),
      ),
    );
  }

  Widget _miniCard(String title, String action, IconData icon) => GestureDetector(
        onTap: _soon,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF4A5A66), Color(0xFF29343D)]),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black45),
          ),
          child: Row(children: [
            Icon(icon, size: 30, color: Colors.white54),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                            color: Colors.white70)),
                    const SizedBox(height: 2),
                    Row(children: [
                      const Icon(Icons.lock, size: 12, color: Colors.white38),
                      const SizedBox(width: 3),
                      const Text('Yakında',
                          style: TextStyle(fontSize: 11, color: Colors.white38)),
                    ]),
                  ]),
            ),
          ]),
        ),
      );

  Widget _roomCard({
    required String title,
    required String sub,
    required int players,
    required Widget art,
    VoidCallback? onPick,
    VoidCallback? onCreate,
  }) =>
      Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        decoration: BoxDecoration(
          color: const Color(0xFFEFE6CF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black45, width: 1.5),
          boxShadow: const [
            BoxShadow(color: Colors.black38, offset: Offset(0, 3), blurRadius: 5)
          ],
        ),
        child: Column(children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 22,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy)),
          Text(sub,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF6A2A8A))),
          const SizedBox(height: 4),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(fit: StackFit.expand, children: [
                art,
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text('$players oyuncu',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.white70)),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
                child: CandyButton(
                    onTap: onPick,
                    kind: CandyKind.blue,
                    radius: 7,
                    height: 34,
                    child: const Text('ODA SEÇ',
                        style: TextStyle(fontSize: 13)))),
            const SizedBox(width: 5),
            Expanded(
                child: CandyButton(
                    onTap: onCreate,
                    kind: CandyKind.orange,
                    radius: 7,
                    height: 34,
                    child: const Text('MASA AÇ',
                        style: TextStyle(fontSize: 13)))),
          ]),
        ]),
      );

  // ---------------------------------------------------------- alt çubuk

  Widget _mailButton() => Stack(clipBehavior: Clip.none, children: [
        RoundBtn(icon: Icons.mail, onTap: _openInbox),
        if (_unread > 0)
          Positioned(
            right: -3,
            top: -5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.bad,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text('$_unread',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: Colors.white)),
            ),
          ),
      ]);

  /// HEMEN OYNA'nın yanındaki "Reklam izle bilet kazan" butonu (10 dakikada bir, +1 bilet).
  Widget _adButton() {
    final ready = _tk != null && _adWait <= 0;
    return SizedBox(
      width: 104,
      child: CandyButton(
        onTap: _watchAd,
        kind: ready ? CandyKind.orange : CandyKind.gray,
        radius: 18,
        height: 60,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.play_circle_fill, size: 18),
            const SizedBox(width: 3),
            Text(ready ? 'REKLAM İZLE' : _tk == null ? '...' : _mmss(_adWait),
                style: const TextStyle(fontSize: 11, height: 1.1)),
          ]),
          const SizedBox(height: 2),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.confirmation_number_rounded, size: 13, color: AppColors.goldLight),
            const SizedBox(width: 3),
            const Text('+1 BİLET', style: TextStyle(fontSize: 12)),
          ]),
        ]),
      ),
    );
  }

  Widget _bottomBar() => SizedBox(
        height: 66,
        child: Row(children: [
          RoundBtn(icon: Icons.groups, onTap: _soon),
          const SizedBox(width: 6),
          _mailButton(),
          const SizedBox(width: 6),
          RoundBtn(icon: Icons.leaderboard, onTap: _soon),
          const Spacer(),
          SizedBox(
            width: 230,
            child: CandyButton(
              onTap: _me == null ? null : _quick,
              kind: CandyKind.green,
              radius: 22,
              height: 60,
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('HEMEN OYNA',
                        style: TextStyle(fontSize: 22, height: 1.1)),
                    Text('$_totalOnline Oyuncu Çevrimiçi',
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700)),
                  ]),
            ),
          ),
          const SizedBox(width: 8),
          _adButton(),
          const Spacer(),
          RoundBtn(icon: Icons.info_outline, onTap: _soon),
          const SizedBox(width: 6),
          RoundBtn(
              icon: Icons.settings,
              onTap: () => _push(SettingsScreen(
                  player: _me,
                  account: widget.account,
                  onAccountSwitched: widget.onAccountSwitched))),
        ]),
      );
}

/// Kart görseli: iki eğik okey taşı. Gerçek görsel eklenince değiştirilir.
class _TilesArt extends StatelessWidget {
  final String a, b;
  final Color color;
  const _TilesArt({required this.a, required this.b, required this.color});

  Widget _tile(String n, Color c) => Container(
        width: 52,
        height: 70,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.tileCream,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: AppColors.tileEdge, width: 2),
          boxShadow: const [
            BoxShadow(color: Colors.black45, offset: Offset(0, 3), blurRadius: 4)
          ],
        ),
        child: Text(n,
            style: TextStyle(
                fontSize: 32, fontWeight: FontWeight.w900, color: c)),
      );

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
              radius: .9, colors: [color, Color.lerp(color, Colors.black, .6)!]),
        ),
        child: Center(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Transform.rotate(angle: -.2, child: _tile(a, AppColors.tileBlack)),
            const SizedBox(width: 4),
            Transform.rotate(angle: .15, child: _tile(b, AppColors.tileYellow)),
          ]),
        ),
      );
}
