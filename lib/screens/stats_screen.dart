import 'package:flutter/material.dart';
import '../models/player_stats.dart';
import '../widgets/lobby_widgets.dart';

/// "İstatistiklerim": kişisel rekorlar ve sayaçlar (yalnız bu cihazda tutulur, sunucu gerektirmez).
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  @override
  void initState() {
    super.initState();
    PlayerStats.I.load(); // yüklenince ListenableBuilder yeniler
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: AppBackground(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              child: Column(children: [
                SizedBox(
                  height: 44,
                  child: Stack(alignment: Alignment.center, children: [
                    const Text('İSTATİSTİKLERİM',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 2)),
                    Align(
                        alignment: Alignment.centerLeft,
                        child: RoundBtn(
                            icon: Icons.arrow_back,
                            kind: CandyKind.red,
                            size: 38,
                            onTap: () => Navigator.of(context).pop())),
                  ]),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListenableBuilder(
                    listenable: PlayerStats.I,
                    builder: (context, _) => _body(PlayerStats.I),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );

  Widget _body(PlayerStats s) {
    final rate = s.matchesPlayed == 0 ? '-' : '%${s.winRate.round()}';
    final best = s.bestHand == null ? '-' : '${s.bestHand}';
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _section('GENEL'),
        _grid([
          _Stat('🎴', '${s.matchesPlayed}', 'Oynanan maç'),
          _Stat('🏆', '${s.matchesWon}', 'Kazanılan maç'),
          _Stat('📈', rate, 'Kazanma oranı'),
          _Stat('🃏', '${s.handsPlayed}', 'Oynanan el'),
          _Stat('✅', '${s.handsWon}', 'Bitirdiğin el'),
        ]),
        const SizedBox(height: 10),
        _section('REKORLARIN'),
        _grid([
          _Stat('🔥', '${s.bestWinStreak}', 'En uzun galibiyet serisi'),
          _Stat('⚡', '${s.curWinStreak}', 'Şu anki seri'),
          _Stat('🎯', best, 'En iyi el puanı'),
          _Stat('⭐', '${s.okeyFinishes}', 'Okey atarak bitirme'),
          _Stat('💫', '${s.eldenFinishes}', 'Elden bitirme'),
          _Stat('👯', '${s.pairFinishes}', 'Çiftle bitirme'),
        ]),
        if (s.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 12, 8, 4),
            child: Text('Maç oynadıkça rekorların burada birikir.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 13)),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(8, 10, 8, 4),
          child: Text('Veriler bu cihazda saklanır.',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 11)),
        ),
      ]),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
        child: Text(t,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.6, color: Colors.white60)),
      );

  Widget _grid(List<_Stat> items) => LayoutBuilder(builder: (context, box) {
        const gap = 8.0;
        final cols = box.maxWidth >= 640 ? 3 : 2;
        final w = (box.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final it in items) SizedBox(width: w, child: _card(it)),
        ]);
      });

  Widget _card(_Stat it) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(children: [
          Text(it.icon, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(it.value,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
              ),
              Text(it.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: Colors.white70, height: 1.15)),
            ]),
          ),
        ]),
      );
}

class _Stat {
  final String icon;
  final String value;
  final String label;
  const _Stat(this.icon, this.value, this.label);
}
