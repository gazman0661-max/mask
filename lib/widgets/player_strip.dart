import 'package:flutter/material.dart';
import '../models/player.dart';
import '../theme/app_theme.dart';
import 'player_badge.dart';
import 'status_badges.dart';

/// Sol/sağ oyuncular için dikey şerit. Sırası gelen oyuncuda yeşil dolgu
/// süre azaldıkça yukarıdan aşağıya doğru küçülür.
class PlayerStrip extends StatelessWidget {
  final Player player;
  final Animation<double>? turn;
  final int? count;
  final String? tag;
  final String? openText; // açılan sayı / çift adedi
  final int penalty; // ceza puanı
  const PlayerStrip(
      {super.key,
      required this.player,
      this.turn,
      this.count,
      this.tag,
      this.openText,
      this.penalty = 0});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [AppColors.surfaceLight, AppColors.surface]),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: turn != null ? AppColors.gold : Colors.white12,
            width: turn != null ? 1.5 : 1),
      ),
      child: LayoutBuilder(builder: (context, box) {
        final badges = openText != null || penalty > 0;
        final roomy = box.maxHeight >= 70 && !badges;
        return Stack(children: [
          if (turn != null)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: turn!,
                builder: (_, __) => Align(
                  alignment: Alignment.topCenter,
                  child: FractionallySizedBox(
                    heightFactor: turn!.value,
                    widthFactor: 1,
                    child: ColoredBox(
                        color: AppColors.good.withOpacity(.3)),
                  ),
                ),
              ),
            ),
          Column(children: [
            if (roomy) ...[
              const SizedBox(height: 4),
              CircleAvatar(
                radius: 11,
                backgroundColor: AppColors.feltDark,
                child: Text(player.name.characters.first.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.goldLight)),
              ),
            ],
            Expanded(
              child: RotatedBox(
                quarterTurns: 1,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      tag == null ? player.name : '${player.name} · $tag',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 10.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
            if (badges)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (openText != null) OpenScoreBadge(text: openText!),
                    if (penalty > 0) ...[
                      const SizedBox(height: 2),
                      PenaltyBadge(points: penalty),
                    ],
                  ]),
                ),
              ),
            if (count != null && (roomy || badges) && box.maxHeight >= 56)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(8)),
                child: Text('$count',
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w800)),
              ),
          ]),
        ]);
      }),
    );
  }
}
