import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'game_popup.dart';
import 'lobby_widgets.dart' show CandyKind;

/// Oyundan çıkarken gösterilen onay penceresi (`showGamePopup<bool>` ile açılır).
/// `true` = çık, `false`/null = devam et.
class ExitConfirmDialog extends StatelessWidget {
  const ExitConfirmDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return GamePopup(
      title: 'OYUNDAN ÇIK',
      maxWidth: 420,
      onClose: () => Navigator.of(context).pop(false),
      actions: [
        PopupButton(
            label: 'ÇIK',
            kind: CandyKind.red,
            width: 150,
            height: 46,
            onTap: () => Navigator.of(context).pop(true)),
        PopupButton(
            label: 'DEVAM ET',
            kind: CandyKind.green,
            width: 170,
            height: 46,
            onTap: () => Navigator.of(context).pop(false)),
      ],
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black26,
            border: Border.all(color: AppColors.gold, width: 2),
          ),
          child: const Icon(Icons.warning_amber_rounded,
              size: 30, color: AppColors.goldLight),
        ),
        const SizedBox(height: 10),
        const Text(
          'Çıkmak istediğinden emin misin?\nGiriş çipin iade edilmez, puan yazılmaz.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14.5, height: 1.35, color: Colors.white),
        ),
      ]),
    );
  }
}
