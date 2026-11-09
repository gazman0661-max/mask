import 'dart:async';
import 'package:flutter/material.dart';
import '../logic/game_controller.dart';
import '../models/rewards.dart' show kAdChips, kNoChipWaitSeconds;
import 'player_badge.dart' show formatChips;
import '../theme/app_theme.dart';

/// El sonucu (her el bitince) ve oyun sonucu (son el bitince) penceresi.
/// 10 saniye sonra sonraki el / yeni oyun kendiliğinden başlar.
/// MASAYA GÖZ AT pencereyi gizler, SONUCA DÖN geri getirir.
class ResultDialog extends StatefulWidget {
  final GameController c;

  final VoidCallback onLeave;
  final VoidCallback onNext;
  final VoidCallback onReplay;

  /// Oyun bitti ve çip bu odanın en azından düşük: otomatik yeni oyun DURUR (masadan atılmaz), yerine REKLAM İZLE düğmesi çıkar.
  final bool needAd;

  /// Reklam izleniyor: geri sayım ve düğmeler bekler.
  final bool paused;
  final VoidCallback? onWatchAd;

  /// Çip yetmezken [kNoChipWaitSeconds] sn içinde reklam izlenmezse çağrılır (ekran oyuncuyu lobiye alır).
  final VoidCallback? onNoChipTimeout;
  const ResultDialog(
      {super.key,
      required this.c,
      required this.onLeave,
      required this.onNext,
      required this.onReplay,
      this.needAd = false,
      this.paused = false,
      this.onWatchAd,
      this.onNoChipTimeout});

  @override
  State<ResultDialog> createState() => _ResultDialogState();
}

class _ResultDialogState extends State<ResultDialog> {
  static const _wait = 10;
  int _left = _wait;
  int _adLeft = kNoChipWaitSeconds; // çip yetmezken lobiye atılmadan önceki süre
  bool _hidden = false;
  Timer? _timer;

  GameController get c => widget.c;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (widget.paused) return; // reklam izleniyor: hiçbir sayaç işlemez
      if (widget.needAd) {
        // Çip yetmiyor: otomatik yeni oyun yok. 15 sn içinde reklam izlenmezse lobiye alınır (çip/puan kaybı yok).
        if (_adLeft <= 1) {
          t.cancel();
          setState(() => _adLeft = 0);
          widget.onNoChipTimeout?.call();
        } else {
          setState(() => _adLeft--);
        }
        return;
      }
      if (_left <= 1) {
        t.cancel();
        setState(() => _left = 0);
        c.gameOver ? widget.onReplay() : widget.onNext();
      } else {
        setState(() => _left--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) {
      return Align(
        alignment: const Alignment(0, .55),
        child: GestureDetector(
          onTap: () => setState(() => _hidden = false),
          child: _pill('SONUCA DÖN · ${widget.needAd ? _adLeft : _left}'),
        ),
      );
    }
    final over = c.gameOver;
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _round(
              'MASADAN\nAYRIL',
              const [Color(0xFFE5484D), Color(0xFF9E1C22)],
              widget.onLeave),
          const SizedBox(width: 14),
          Column(mainAxisSize: MainAxisSize.min, children: [
            _panel(over),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => setState(() => _hidden = true),
              child: _pill('MASAYA GÖZ AT'),
            ),
          ]),
          const SizedBox(width: 14),
          over
              ? (widget.needAd
                  ? _round(
                      'REKLAM İZLE\n+${formatChips(kAdChips)} ÇİP',
                      const [Color(0xFFF0A020), Color(0xFFB85E08)],
                      widget.paused ? () {} : (widget.onWatchAd ?? () {}),
                      icon: Icons.play_circle_fill_rounded)
                  : _round(
                      'YENİ OYUNA\nBAŞLA',
                      const [Color(0xFF3FBF3F), Color(0xFF1F7A25)],
                      widget.onReplay))
              : _round(
                  'SONRAKİ EL\n${c.round + 1}/${c.totalHands}',
                  const [Color(0xFF3FBF3F), Color(0xFF1F7A25)],
                  widget.onNext),
        ]),
      ),
    );
  }

  // ----------------------------------------------------------------- panel

  Widget _panel(bool over) {
    final r = c.result!;
    final single = c.totalHands == 1;
    final champs = over ? _champions() : const <int>[];
    final order = over ? _byTotal() : _byDelta(r);
    final sub = over
        ? (single
            ? (r.winner == null ? r.note : '${c.names[r.winner!]}: ${r.note}')
            : '${c.history.length} el oynandı')
        : (r.winner == null ? r.note : '${c.names[r.winner!]}: ${r.note}');
    final points = over && !c.voided ? c.rankPoints() : null;
    return Container(
      width: 470,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF5B1528), Color(0xFF3A0B19)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3B24E), width: 2),
        boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 24)],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(over ? 'OYUN SONUCU' : '${c.round}. EL SONUCU',
            style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                color: Colors.white)),
        const SizedBox(height: 2),
        Text(sub,
            style: const TextStyle(fontSize: 11.5, color: Colors.white70)),
        const SizedBox(height: 4),
        Text.rich(
            widget.needAd
                ? TextSpan(children: [
                    TextSpan(
                        text: '$_adLeft',
                        style: const TextStyle(color: AppColors.goldLight, fontWeight: FontWeight.w900)),
                    const TextSpan(text: ' SANİYE İÇİNDE LOBİYE DÖNECEKSİN · ÇİPİN BİTTİ, REKLAM İZLEYİP DEVAM EDEBİLİRSİN (YA DA MASADAN AYRIL)'),
                  ])
                : TextSpan(children: [
                    TextSpan(
                        text: '$_left',
                        style: const TextStyle(
                            color: AppColors.good, fontWeight: FontWeight.w900)),
                    TextSpan(
                        text: over
                            ? ' SANİYE İÇİNDE OYUN BAŞLAYACAK'
                            : ' SANİYE İÇİNDE SONRAKİ EL BAŞLAYACAK'),
                  ]),
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                letterSpacing: .6,
                color: Colors.white)),
        const SizedBox(height: 8),
        for (final s in order)
          _playerRow(
            s,
            crown: over ? champs.contains(s) : s == r.winner,
            label: over
                ? (champs.contains(s) ? 'KAZANAN' : null)
                : (s == r.winner ? 'ELİ BİTİRDİ' : null),
            score: over ? c.totals[s] : r.delta[s],
            sub: over
                ? (single ? _modeText(r.modes[s]) : _handsText(s))
                : '${_modeText(r.modes[s])} · toplam ${c.totals[s]}',
            points: points?[s],
            chipText: over ? _chipText(s) : null,
            chipColor: over ? _chipColor(s) : null,
          ),
        if (c.teamMode)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
                'Takımlar · ${c.names[0]}+${c.names[2]}: ${c.teamTotal(0)}'
                '   ${c.names[1]}+${c.names[3]}: ${c.teamTotal(1)}',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white70)),
          ),
        if (over)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                c.voided
                    ? 'Oyun hükümsüz · puan ve XP yok, giriş çipin iade edilir'
                    : (_championName == 'berabere'
                            ? 'Oyun bitti · berabere'
                            : 'Oyun bitti · kazanan: $_championName') +
                        '  ·  sen: +${c.rankPoints()[GameController.me]} puan · +${c.myXp} XP' +
                        _myChipFooter(),
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.goldLight)),
          ),
      ]),
    );
  }

  Widget _playerRow(int s,
      {required bool crown,
      String? label,
      required int score,
      required String sub,
      int? points,
      String? chipText,
      Color? chipColor}) {
    final mine = s == GameController.me;
    final scoreText = (!c.gameOver && score > 0 ? '+' : '') + '$score';
    final scoreColor = c.gameOver
        ? Colors.white
        : (score <= 0 ? AppColors.good : AppColors.bad);
    return Container(
      height: 58,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        gradient: mine
            ? const LinearGradient(
                colors: [Color(0xFF9A2A48), Color(0xFF5B1528)])
            : const LinearGradient(
                colors: [Color(0xFF4A0F21), Color(0xFF2E0914)]),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        SizedBox(
          width: 40,
          height: 40,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.feltDark,
                  border: Border.all(
                      color: crown ? AppColors.gold : Colors.white24, width: 2),
                ),
                child: c.botSeats[s]
                    ? const Text('🤖', style: TextStyle(fontSize: 20, height: 1))
                    : Text(c.names[s].characters.first.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: AppColors.goldLight)),
              ),
            ),
            if (crown)
              const Positioned(
                  left: -6,
                  top: -9,
                  child: Text('♛',
                      style: TextStyle(fontSize: 20, color: AppColors.gold))),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.names[s],
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800)),
                Row(children: [
                  if (points != null) ...[
                    const Icon(Icons.emoji_events_rounded,
                        size: 12, color: AppColors.gold),
                    const SizedBox(width: 3),
                    Text(
                        mine
                            ? '+$points puan · +${c.myXp} XP'
                            : '+$points puan',
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.gold)),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(sub,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 10.5, color: Colors.white60)),
                  ),
                ]),
              ]),
        ),
        Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (label != null)
                Text(label,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: AppColors.good)),
              Text(scoreText,
                  style: TextStyle(
                      fontSize: 20,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                      color: scoreColor)),
              if (chipText != null)
                Text(chipText,
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                        color: chipColor ?? Colors.white70)),
            ]),
      ]),
    );
  }

  // -------------------------------------------------------------- çip satırı

  /// Oyun sonunda satırın çip yazısı: kazanan "+8.000 çip", 2. "2.000 çip iade", diğerleri "−2.000 çip".
  /// Hükümsüzde herkes girişini geri alır. Sunucu çip bilgisi yollamadıysa (eski sürüm / ücretsiz masa) boş.
  String? _chipText(int s) {
    if (!c.gameOver || c.finalEntry <= 0) return null;
    if (c.voided) return '${formatChips(c.finalEntry)} çip iade';
    final got = c.chipsOf(s);
    if (got == null) return null;
    if (c.finalRefunded) return 'giriş iade kutunda';
    if (got > c.finalEntry) return '+${formatChips(got)} çip';
    if (got > 0) return '${formatChips(got)} çip iade';
    return '−${formatChips(c.finalEntry)} çip';
  }

  Color? _chipColor(int s) {
    if (_chipText(s) == null) return null;
    if (c.voided || c.finalRefunded) return AppColors.goldLight;
    final got = c.chipsOf(s) ?? 0;
    if (got > c.finalEntry) return AppColors.good;
    return got > 0 ? AppColors.goldLight : AppColors.bad;
  }

  /// Alt satırda benim net çipim: "· çip +6.000" / "· çip −2.000" / "· çip 0".
  String _myChipFooter() {
    if (c.voided || c.finalRefunded || c.finalEntry <= 0) return '';
    final net = c.chipNet(GameController.me);
    if (net == null) return '';
    return ' · çip ${net > 0 ? '+' : (net < 0 ? '−' : '')}${formatChips(net.abs())}';
  }

  // -------------------------------------------------------------- yardımcı

  Widget _round(String text, List<Color> colors, VoidCallback onTap, {IconData? icon}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 96,
          height: 96,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: colors),
            border: Border.all(color: const Color(0xFF3A0B19), width: 4),
            boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 12)],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) Icon(icon, size: 26, color: Colors.white),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: icon != null ? 12.5 : 14,
                    height: 1.15,
                    fontWeight: FontWeight.w900,
                    color: Colors.white)),
          ]),
        ),
      );

  Widget _pill(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF7A1E38), Color(0xFF4A0F21)]),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE3B24E)),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6)],
        ),
        child: Text(t,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: .5,
                color: Colors.white)),
      );

  String _modeText(OpenMode? m) => switch (m) {
        OpenMode.series => 'Seri açtı',
        OpenMode.pairs => 'Çift açtı',
        null => 'Açmadı',
      };

  /// Çok elli oyunda el el puanlar: "+18 · -101 · 0".
  String _handsText(int s) => [
        for (final h in c.history) (h[s] > 0 ? '+' : '') + '${h[s]}'
      ].join(' · ');

  /// Tüm eller bitince toplamı en düşük olan (eşlide takım) kazanır.
  String get _championName {
    if (c.teamMode) {
      final t = c.championTeam;
      if (t == null) return 'berabere';
      return '${c.names[t]} + ${c.names[t + 2]}';
    }
    final seat = c.championSeat;
    return seat == null ? 'berabere' : c.names[seat];
  }

  /// Oyunun kazananı olan koltuklar (beraberlikte boş).
  List<int> _champions() {
    if (c.voided) return const [];
    if (c.teamMode) {
      final t = c.championTeam;
      return t == null ? const [] : [t, t + 2];
    }
    final s = c.championSeat;
    return s == null ? const [] : [s];
  }

  /// El sonucunda eldeki puanı en düşükten yükseğe.
  List<int> _byDelta(RoundResult r) {
    final seats = [0, 1, 2, 3];
    seats.sort((a, b) => r.delta[a].compareTo(r.delta[b]));
    return seats;
  }

  /// Oyun sonucunda toplamı en düşükten yükseğe (eşlide önce takım toplamı).
  List<int> _byTotal() {
    final seats = [0, 1, 2, 3];
    seats.sort((a, b) {
      if (c.teamMode) {
        final d = c.teamTotal(a).compareTo(c.teamTotal(b));
        if (d != 0) return d;
      }
      return c.totals[a].compareTo(c.totals[b]);
    });
    return seats;
  }
}
