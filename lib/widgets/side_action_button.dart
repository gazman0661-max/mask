import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Istakanın iki yanındaki "Çift diz" / "Seri diz" butonları.
class SideActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  const SideActionButton(
      {super.key,
      required this.label,
      required this.icon,
      required this.onTap,
      this.active = false});

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 54,
          height: 72,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.surfaceLight, AppColors.surface]),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: active ? AppColors.goldLight : AppColors.gold.withOpacity(.55),
                width: active ? 2 : 1),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: AppColors.gold, size: 24),
            const SizedBox(height: 4),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 10.5, fontWeight: FontWeight.w800, height: 1.1)),
          ]),
        ),
      );
}
