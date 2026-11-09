import 'package:flutter/material.dart';
import '../models/tile.dart';
import '../theme/app_theme.dart';

/// Okey taşı. [hidden] taşı arkası dönük (boş beyaz) çizer: gerçek okey
/// ıstakada böyle durur. [wild] küçük bir yıldızla işaretler.
class TileWidget extends StatelessWidget {
  final Tile tile;
  final double width;
  final bool wild;
  final bool hidden;

  /// Yardımlı masada: bu taş masadaki bir pere işlenebilir (yeşil işaret).
  final bool layable;
  final bool selected;
  final bool glow;
  const TileWidget(
      {super.key,
      required this.tile,
      required this.width,
      this.wild = false,
      this.hidden = false,
      this.layable = false,
      this.selected = false,
      this.glow = false});

  static Color colorOf(TileColor c) => switch (c) {
        TileColor.yellow => AppColors.tileYellow,
        TileColor.blue => AppColors.tileBlue,
        TileColor.black => AppColors.tileBlack,
        TileColor.red => AppColors.tileRed,
      };

  @override
  Widget build(BuildContext context) {
    final c = colorOf(tile.color);
    final hot = selected || glow;
    return Container(
      width: width,
      height: width * 1.35,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFDF6), AppColors.tileCream, Color(0xFFEFE6CF)],
          stops: [0, .55, 1],
        ),
        borderRadius: BorderRadius.circular(width * .16),
        border: Border.all(
            color: hot ? AppColors.gold : AppColors.tileEdge,
            width: hot ? 2 : 1),
        boxShadow: [
          const BoxShadow(
              color: Colors.black45, blurRadius: 3, offset: Offset(0, 2)),
          if (hot)
            BoxShadow(
                color: AppColors.gold.withOpacity(.55), blurRadius: 8),
        ],
      ),
      child: Stack(alignment: Alignment.center, children: [
        if (!hidden)
          Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (tile.isFakeJoker)
              Icon(Icons.star_rounded,
                  color: AppColors.tileRed, size: width * .7)
            else
              Padding(
                padding: EdgeInsets.symmetric(horizontal: width * .06),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('${tile.number}',
                      style: TextStyle(
                          color: c,
                          fontWeight: FontWeight.w900,
                          height: 1,
                          fontSize: width * .56)),
                ),
              ),
            if (width >= 20) SizedBox(height: width * .05),
            if (width >= 20 && !tile.isFakeJoker)
              Container(
                width: width * .2,
                height: width * .2,
                decoration: BoxDecoration(
                    shape: BoxShape.circle, color: c.withOpacity(.4)),
              ),
          ],
        ),
        if (layable)
          Positioned(
            bottom: width * .06,
            left: width * .06,
            child: Container(
              width: width * .28,
              height: width * .28,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: Color(0xFF2ECC71)),
              child: Icon(Icons.check_rounded,
                  size: width * .22, color: Colors.white),
            ),
          ),
        if (wild && !hidden)
          Positioned(
            top: width * .06,
            right: width * .06,
            child: Icon(Icons.star_rounded,
                size: width * .3, color: AppColors.gold),
          ),
      ]),
    );
  }
}
