import 'package:flutter/material.dart';
import '../logic/okey_rules.dart';
import '../models/tile.dart';
import '../theme/app_theme.dart';
import 'tile_widget.dart';

/// Bir oyuncunun attığı taşların yığını (en üstteki taş görünür).
/// Sığacağı alanı kendisi doldurur (Expanded içinde taşma yapmaz).
class DiscardSlot extends StatelessWidget {
  final Tile? tile;
  final Okey okey;
  final bool glow;
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
      this.onTap,
      this.onDragStart,
      this.onDragUpdate,
      this.onDragEnd,
      this.onDragCancel});

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
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(.22),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: glow ? AppColors.gold : Colors.white24,
                width: glow ? 2 : 1),
            boxShadow: glow
                ? [BoxShadow(color: AppColors.gold.withOpacity(.45), blurRadius: 8)]
                : null,
          ),
          child: tile == null
              ? null
              : Center(
                  child: FittedBox(
                      child: TileWidget(
                          tile: tile!, width: 34))),
        ),
      );
}
