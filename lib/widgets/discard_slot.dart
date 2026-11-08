import 'package:flutter/material.dart';
import '../logic/okey_rules.dart';
import '../models/tile.dart';
import '../theme/app_theme.dart';
import 'tile_widget.dart';

/// Bir oyuncunun attığı taşların yığını (en üstteki taş görünür, altında yığın kenarları belli olur).
/// Sığacağı alanı kendisi doldurur (Expanded içinde taşma yapmaz).
///
/// [label]: alt kenarda küçük hap etiketi (ör. 'ÇEK', 'AT'); [glow] iken altın dolgulu yanar.
/// [emptyIcon]: yuva boşken silik gösterilen ikon (bırakma hedefi olduğunu hissettirir).
class DiscardSlot extends StatelessWidget {
  final Tile? tile;
  final Okey okey;
  final bool glow;
  final String? label;
  final IconData? emptyIcon;
  final VoidCallback? onTap;
  final void Function(Offset global)? onDragStart;
  final void Function(Offset global)? onDragUpdate;
  final VoidCallback? onDragEnd;
  final VoidCallback? onDragCancel;
  const DiscardSlot(
      {super.key,
      this.tile,
      required this.okey,
      this.glow = false,
      this.label,
      this.emptyIcon,
      this.onTap,
      this.onDragStart,
      this.onDragUpdate,
      this.onDragEnd,
      this.onDragCancel});

  /// Yığının arkada kalan, hafif kaymış taş yüzeyi.
  Widget _ghost(double w) => Container(
        width: w,
        height: w * 1.35,
        decoration: BoxDecoration(
          color: AppColors.tileCream.withOpacity(.5),
          borderRadius: BorderRadius.circular(w * .14),
          border: Border.all(color: AppColors.tileEdge.withOpacity(.7), width: .8),
        ),
      );

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onPanStart:
            onDragStart == null ? null : (d) => onDragStart!(d.globalPosition),
        onPanUpdate:
            onDragUpdate == null ? null : (d) => onDragUpdate!(d.globalPosition),
        onPanEnd: onDragEnd == null ? null : (_) => onDragEnd!(),
        onPanCancel: onDragCancel,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(.30),
                      Colors.black.withOpacity(.14),
                    ]),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                    color: glow ? AppColors.gold : Colors.white24,
                    width: glow ? 2 : 1),
                boxShadow: glow
                    ? [BoxShadow(color: AppColors.gold.withOpacity(.45), blurRadius: 8)]
                    : null,
              ),
              child: LayoutBuilder(builder: (context, box) {
                // Taş genişliği: alanın yüksekliğine ve genişliğine sığan en büyük (yığın payı 4 px).
                final byH = (box.maxHeight - 4) / 1.35;
                final byW = box.maxWidth - 4;
                final tw = (byH < byW ? byH : byW).clamp(12.0, 34.0).toDouble();
                if (tile == null) {
                  return Center(
                    child: emptyIcon == null
                        ? const SizedBox.shrink()
                        : Icon(emptyIcon,
                            size: tw * .8,
                            color: (glow ? AppColors.goldLight : Colors.white)
                                .withOpacity(glow ? .8 : .18)),
                  );
                }
                return Center(
                  child: SizedBox(
                    width: tw + 4,
                    height: tw * 1.35 + 4,
                    child: Stack(clipBehavior: Clip.none, children: [
                      Positioned(left: 0, top: 4, child: _ghost(tw)),
                      Positioned(left: 2, top: 2, child: _ghost(tw)),
                      Positioned(
                          left: 4,
                          top: 0,
                          child: TileWidget(tile: tile!, width: tw)),
                    ]),
                  ),
                );
              }),
            ),
          ),
          // Etiket kutunun alt kenarında küçük bir hap olarak durur (taş boyunu küçültmez, dokunuşu geçirir).
          if (label != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: -5,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: glow ? AppColors.goldLight : Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.gold.withOpacity(.8), width: 1),
                    ),
                    child: Text(label!,
                        style: TextStyle(
                            fontSize: 8.5,
                            height: 1,
                            letterSpacing: .6,
                            fontWeight: FontWeight.w900,
                            color: glow ? AppColors.navy : Colors.white70)),
                  ),
                ),
              ),
            ),
        ]),
      );
}
