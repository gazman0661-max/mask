import 'package:flutter/material.dart';
import '../models/table_models.dart';
import '../theme/app_theme.dart';
import 'avatar.dart';

/// "OYUN BAŞLIYOR" penceresi: masa dolunca geri sayım ([seconds]) gösterir. Geri sayım bitince ekran oyunu
/// başlatır (başlama zili + bilet düşer). Bilet henüz düşmedi: bu pencerede çıkan kimse bir şey kaybetmez.
/// Biri kalkıp yerine başkası oturursa sayaç [kStartCountdownSeconds]'den yeniden başlar.
class GameStartPopup extends StatelessWidget {
  final int seconds;
  final TableSnapshot table;
  const GameStartPopup({super.key, required this.seconds, required this.table});

  @override
  Widget build(BuildContext context) {
    final players = [table.me, table.left, table.top, table.right];
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
              const Text('OYUN BAŞLIYOR',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                      color: AppColors.goldLight)),
              const SizedBox(height: 8),
              Row(mainAxisSize: MainAxisSize.min, children: [
                for (final p in players)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      AvatarWidget(index: p.avatar ?? 0, size: 40),
                      const SizedBox(height: 3),
                      SizedBox(
                        width: 72,
                        child: Text(p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white70)),
                      ),
                    ]),
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
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (w, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: w)),
                  child: Text('$seconds',
                      key: ValueKey<int>(seconds),
                      style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 8),
              const Text('Bilet oyun başlayınca düşer',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white60)),
            ]),
          ),
        ),
      ),
    );
  }
}
