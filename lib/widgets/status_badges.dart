import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Açılan sayıyı (ör. 108) küçük taş kartlar olarak gösterir.
class OpenScoreBadge extends StatelessWidget {
  final String text;
  final double scale;
  const OpenScoreBadge({super.key, required this.text, this.scale = 1});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (final ch in text.characters)
          Container(
            width: 11 * scale,
            height: 15 * scale,
            margin: const EdgeInsets.only(right: 1),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white, Color(0xFFE3DCC6)]),
              borderRadius: BorderRadius.circular(2.5),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 2)],
            ),
            child: Text(ch,
                style: TextStyle(
                    fontSize: 9.5 * scale,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy)),
          ),
      ]);
}

/// Ceza puanı (+101 ...) kırmızı rozet.
class PenaltyBadge extends StatelessWidget {
  final int points;
  const PenaltyBadge({super.key, required this.points});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: AppColors.bad.withOpacity(.9),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text('+$points',
            style: const TextStyle(
                fontSize: 9.5,
                height: 1.2,
                fontWeight: FontWeight.w900,
                color: Colors.white)),
      );
}
