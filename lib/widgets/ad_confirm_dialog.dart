import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'game_popup.dart';
import 'lobby_widgets.dart' show CandyKind;
import 'player_badge.dart' show formatChips;

/// Reklam izleyip çip kazanmadan önce çıkan onay penceresi:
/// "Kısa bir reklam izle, [amount] çip kazan" + İZLE / VAZGEÇ.
/// İZLE -> true. VAZGEÇ, X ya da dışarı dokunma -> false (reklam açılmaz, çip verilmez).
Future<bool> showAdConfirm(
  BuildContext context, {
  required int amount,
  String? note,
}) async {
  final r = await showGamePopup<bool>(
    context,
    builder: (_) => AdConfirmDialog(amount: amount, note: note),
  );
  return r == true;
}

class AdConfirmDialog extends StatelessWidget {
  final int amount;

  /// İsteğe bağlı küçük açıklama (ör. "Ödülün 2 katı").
  final String? note;
  const AdConfirmDialog({super.key, required this.amount, this.note});

  @override
  Widget build(BuildContext context) => GamePopup(
        title: 'REKLAM İZLE',
        icon: Icons.play_circle_fill_rounded,
        maxWidth: 440,
        onClose: () => Navigator.of(context).pop(false),
        actions: [
          PopupButton(
            label: 'İZLE',
            icon: Icons.play_arrow_rounded,
            kind: CandyKind.green,
            width: 190,
            height: 54,
            onTap: () => Navigator.of(context).pop(true),
          ),
          PopupButton(
            label: 'VAZGEÇ',
            kind: CandyKind.gray,
            width: 170,
            height: 54,
            onTap: () => Navigator.of(context).pop(false),
          ),
        ],
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Kısa bir reklam izle',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(.38),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.gold.withOpacity(.6)),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const CoinIcon(size: 36),
                const SizedBox(width: 10),
                Text('${formatChips(amount)} ÇİP KAZAN',
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .5,
                        color: AppColors.goldLight)),
              ]),
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 8),
            Text(note!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white70)),
          ],
        ]),
      );
}
