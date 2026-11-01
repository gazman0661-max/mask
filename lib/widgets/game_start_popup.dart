import 'package:flutter/material.dart';
import '../models/table_models.dart';
import '../theme/app_theme.dart';
import 'avatar.dart';

/// "OYUN BAŞLIYOR" penceresi: masa dolunca geri sayım ([seconds]) gösterir. Geri sayım bitince ekran oyunu
/// başlatır (başlama zili + bilet düşer). Bilet henüz düşmedi: bu pencerede çıkan kimse bir şey kaybetmez.
/// Biri kalkıp yerine başkası oturursa sayaç [kStartCountdownSeconds]'den yeniden başlar.
///
/// [waiting] true iken masa henüz dolmamıştır: "OYUNCU BEKLENİYOR" gösterir (sayaç yok), boş koltuklar "Bekleniyor"
/// yazar, masa dolunca ekran bu pencereyi geri sayımlı hâline çevirir. [onLeave] doluysa "MASADAN AYRIL" düğmesi çıkar
/// (başlamadan kalkan hiçbir şey kaybetmez).
class GameStartPopup extends StatelessWidget {
  final int seconds;
  final TableSnapshot table;
  final bool waiting;
  final VoidCallback? onLeave;
  const GameStartPopup(
      {super.key, required this.seconds, required this.table, this.waiting = false, this.onLeave});

  @override
  Widget build(BuildContext context) {
    final seats = [Seat.me, Seat.left, Seat.top, Seat.right];
    final players = [table.me, table.left, table.top, table.right];
    final seated = 4 - table.emptySeats.length;
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.surfaceLight, AppColors.surface, AppColors.bg]),
            border: Border.all(color: AppColors.gold, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 18)],
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(waiting ? 'OYUNCU BEKLENİYOR' : 'OYUN BAŞLIYOR',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                      color: AppColors.goldLight)),
              const SizedBox(height: 8),
              Row(mainAxisSize: MainAxisSize.min, children: [
                for (var k = 0; k < players.length; k++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      table.emptySeats.contains(seats[k])
                          ? Container(
                              key: ValueKey<String>('bos-${seats[k].name}'),
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white10,
                                  border: Border.all(color: Colors.white24, width: 1.5)),
                              child: const Icon(Icons.person_outline, size: 22, color: Colors.white38))
                          : AvatarWidget(index: players[k].avatar ?? 0, size: 40),
                      const SizedBox(height: 3),
                      SizedBox(
                        width: 72,
                        child: Text(table.emptySeats.contains(seats[k]) ? 'Bekleniyor' : players[k].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white70)),
                      ),
                    ]),
                  ),
              ]),
              const SizedBox(height: 8),
              Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 4, children: [
                for (final r in table.rules)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: r.on ? AppColors.good.withOpacity(.85) : Colors.black26,
                    ),
                    child: Text(r.label,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: r.on ? Colors.white : Colors.white54)),
                  ),
              ]),
              const SizedBox(height: 10),
              Container(
                width: 84,
                height: 84,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.bg,
                  border: Border.all(color: AppColors.goldLight, width: 4),
                ),
                child: waiting
                    ? Column(mainAxisSize: MainAxisSize.min, children: [
                        const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.goldLight)),
                        const SizedBox(height: 4),
                        Text('$seated/4',
                            key: const ValueKey<String>('oturan'),
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                      ])
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        transitionBuilder: (w, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: w)),
                        child: Text('$seconds',
                            key: ValueKey<int>(seconds),
                            style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: Colors.white)),
                      ),
              ),
              const SizedBox(height: 8),
              Text(waiting ? 'Masa dolunca geri sayım başlar · Bilet oyun başlayınca düşer' : 'Bilet oyun başlayınca düşer',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white60)),
              if (onLeave != null) ...[
                const SizedBox(height: 10),
                ElevatedButton(
                  key: const ValueKey<String>('masadan-ayril'),
                  onPressed: onLeave,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.bad,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                  child: const Text('MASADAN AYRIL',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: .8)),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
