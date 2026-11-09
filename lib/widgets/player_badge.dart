import 'package:flutter/material.dart';
import '../models/player.dart';
import '../theme/app_theme.dart';
import 'avatar.dart';
import 'status_badges.dart';
import 'chip_icon.dart';

/// Üst ve alt (ben) oyuncu rozeti. [turn] verilirse altında süre çubuğu çıkar.
class PlayerBadge extends StatelessWidget {
  final Player player;
  final bool compact;
  final Animation<double>? turn; // 1 -> 0
  final int? count; // eldeki taş sayısı
  final String? tag; // SERİ / ÇİFT
  final String? openText; // açılan sayı / çift adedi
  final int penalty; // ceza puanı

  const PlayerBadge(
      {super.key,
      required this.player,
      this.compact = false,
      this.turn,
      this.count,
      this.tag,
      this.openText,
      this.penalty = 0});

  /// Çip bakiyesi bilinen insan oyuncuda görünür (-1 = bilinmiyor, bot = yok).
  bool get showChips => player.chipCount >= 0 && player.avatar != kBotAvatar;

  @override
  Widget build(BuildContext context) {
    final r = compact ? 11.0 : 20.0;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [AppColors.surfaceLight, AppColors.surface]),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: turn != null ? AppColors.gold : Colors.white12,
            width: turn != null ? 1.5 : 1),
      ),
      // IntrinsicWidth: süre çubuğu, sınırsız genişlikli bir Row içinde de
      // (altta "ben" rozeti) satırın genişliğini alır; sonsuz genişlik hatası olmaz.
      child: IntrinsicWidth(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
        Padding(
          padding: EdgeInsets.symmetric(
              horizontal: compact ? 5 : 8, vertical: compact ? 3 : 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (player.avatar != null)
              AvatarWidget(index: player.avatar!, size: r * 2)
            else
              CircleAvatar(
              radius: r,
              backgroundColor: AppColors.feltDark,
              backgroundImage: player.avatarUrl != null
                  ? NetworkImage(player.avatarUrl!)
                  : null,
              child: player.avatarUrl == null
                  ? Text(player.name.characters.first.toUpperCase(),
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.goldLight,
                          fontSize: compact ? 11 : 14))
                  : null,
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(player.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 12, height: 1.1)),
                // Oyuncunun çip bakiyesi (bot ve bilinmeyende gösterilmez).
                if (showChips)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    ChipIcon(size: compact ? 9 : 11),
                    const SizedBox(width: 2),
                    Text(formatChips(player.chipCount),
                        style: TextStyle(
                            fontSize: compact ? 9 : 10.5,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                            color: AppColors.goldLight)),
                  ]),
              ],
            ),
            if (count != null) ...[
              const SizedBox(width: 8),
              _pill('$count', Colors.white24),
            ],
            if (tag != null) ...[
              const SizedBox(width: 4),
              _pill(tag!, AppColors.good.withOpacity(.55)),
            ],
            if (openText != null) ...[
              const SizedBox(width: 5),
              OpenScoreBadge(text: openText!),
            ],
            if (penalty > 0) ...[
              const SizedBox(width: 4),
              PenaltyBadge(points: penalty),
            ],
          ]),
        ),
        if (turn != null)
          AnimatedBuilder(
            animation: turn!,
            // heightFactor: 1 şart. Yoksa çocuk (çocuksuz ColoredBox) yüksekliği 0'a küçülür ve çubuk görünmez olur.
            builder: (_, __) => SizedBox(
              height: 4,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: turn!.value.clamp(0.0, 1.0).toDouble(),
                  heightFactor: 1.0,
                  child: const ColoredBox(color: AppColors.good),
                ),
              ),
            ),
          ),
      ]),
      ),
    );
  }

  Widget _pill(String t, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Text(t,
            style: const TextStyle(
                fontSize: 9.5, fontWeight: FontWeight.w800, height: 1.2)),
      );
}

String formatChips(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}
