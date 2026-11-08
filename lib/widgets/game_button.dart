import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Aksiyon butonu (SERİ AÇ, ÇİFT AÇ, TAŞLARI İŞLE, AT ...). [primary] açık
/// renkli ana aksiyon, değilse yarı saydam çelik mavisi ikincil aksiyon.
class GameButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final IconData? icon;
  const GameButton(
      {super.key,
      required this.label,
      required this.onTap,
      this.primary = false,
      this.icon});

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    final fg = primary ? AppColors.navy : Colors.white;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(
        opacity: on ? 1 : .45,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: primary
                  ? const [Colors.white, Color(0xFFE3D5B8)]
                  : const [Color(0xFF7A1E38), Color(0xFF4F1022)],
            ),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
                color: primary ? Colors.white : Colors.white24, width: 1),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 2))
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 5),
            ],
            Text(label,
                style: TextStyle(
                    color: fg,
                    fontSize: 12.5,
                    letterSpacing: .3,
                    fontWeight: FontWeight.w900)),
          ]),
        ),
      ),
    );
  }
}
