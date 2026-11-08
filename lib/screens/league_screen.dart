import 'package:flutter/material.dart';
import '../diagnostics/app_log.dart';
import '../models/goals.dart';
import '../services/game_service.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar.dart';
import '../widgets/lobby_widgets.dart';

/// Haftalık lig sıralaması (ilk 50). Puanlar her Pazartesi (Türkiye saati) sıfırlanır.
class LeagueScreen extends StatefulWidget {
  final GameService service;
  const LeagueScreen({super.key, required this.service});

  @override
  State<LeagueScreen> createState() => _LeagueScreenState();
}

class _LeagueScreenState extends State<LeagueScreen> {
  List<LeagueRow>? _rows;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final r = await widget.service.fetchLeague(limit: 50);
      if (mounted) setState(() => _rows = r);
    } catch (e) {
      Log.w('lig', 'sıralama yüklenemedi: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  Widget _header() => Row(children: [
        RoundBtn(icon: Icons.arrow_back, onTap: () => Navigator.of(context).pop()),
        const SizedBox(width: 12),
        const Icon(Icons.emoji_events_rounded, color: AppColors.goldLight, size: 26),
        const SizedBox(width: 8),
        const Text('HAFTALIK LİG',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: AppColors.goldLight)),
        const Spacer(),
        const Text('Pazartesi sıfırlanır', style: TextStyle(fontSize: 12, color: Colors.white60)),
      ]);

  Widget _rank(int pos) {
    const medals = ['🥇', '🥈', '🥉'];
    if (pos >= 1 && pos <= 3) return Text(medals[pos - 1], style: const TextStyle(fontSize: 22));
    return Text('$pos', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white70));
  }

  Widget _row(LeagueRow r) {
    final me = widget.service.myUserId != null && r.userId == widget.service.myUserId;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: me ? AppColors.gold.withOpacity(.22) : Colors.black.withOpacity(.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: me ? AppColors.goldLight : Colors.white12, width: me ? 1.6 : 1),
      ),
      child: Row(children: [
        SizedBox(width: 36, child: Center(child: _rank(r.pos))),
        const SizedBox(width: 8),
        AvatarWidget(index: r.avatar, size: 34),
        const SizedBox(width: 10),
        Expanded(
          child: Text(me ? '${r.name}  (sen)' : r.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, fontWeight: me ? FontWeight.w900 : FontWeight.w700)),
        ),
        Text('${r.points}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.goldLight)),
        const SizedBox(width: 4),
        const Text('puan', style: TextStyle(fontSize: 11, color: Colors.white60)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    Widget body;
    if (_failed) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Sıralama yüklenemedi', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 10),
          CandyButton(onTap: _load, kind: CandyKind.orange, width: 140, height: 38, child: const Text('Tekrar dene')),
        ]),
      );
    } else if (rows == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (rows.isEmpty) {
      body = const Center(
        child: Text('Bu hafta henüz puan yok.\nİlk maçı oyna, listenin başına geç!',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.white70)),
      );
    } else {
      body = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(children: [for (final r in rows) _row(r)]),
        ),
      );
    }
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Column(children: [
              _header(),
              const SizedBox(height: 12),
              Expanded(child: body),
            ]),
          ),
        ),
      ),
    );
  }
}
