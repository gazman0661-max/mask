import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Sıra bendeyken üstte görünen süre çubuğu: kalan süre soldan dolu kalır,
/// azaldıkça yeşil -> turuncu -> kırmızıya döner.
class TurnTimerBar extends StatelessWidget {
  final Animation<double> turn; // 1 -> 0
  final Duration total;
  const TurnTimerBar({super.key, required this.turn, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: AnimatedBuilder(
        animation: turn,
        builder: (_, __) {
          final v = turn.value.clamp(0.0, 1.0).toDouble();
          final secs = (v * total.inMilliseconds / 1000).ceil();
          final color = v > .5
              ? AppColors.good
              : (v > .22 ? AppColors.orange : AppColors.bad);
          return Row(children: [
            Icon(Icons.timer_outlined, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: LayoutBuilder(builder: (_, box) {
                final w = box.maxWidth;
                final x = (w * v).clamp(0.0, w).toDouble();
                return SizedBox(
                  height: 16,
                  child: Stack(clipBehavior: Clip.none, children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 6,
                      child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                              color: Colors.white12,
                              borderRadius: BorderRadius.circular(2))),
                    ),
                    Positioned(
                      left: 0,
                      top: 6,
                      child: Container(
                          width: x,
                          height: 4,
                          decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(2))),
                    ),
                    Positioned(
                      left: (x - 6).clamp(0.0, w - 12 < 0 ? 0.0 : w - 12).toDouble(),
                      top: 2,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: color.withOpacity(.8), blurRadius: 8)
                          ],
                        ),
                      ),
                    ),
                  ]),
                );
              }),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 22,
              child: Text('$secs',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w900, color: color)),
            ),
          ]);
        },
      ),
    );
  }
}
