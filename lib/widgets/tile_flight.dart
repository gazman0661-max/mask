import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/tile.dart';
import 'tile_widget.dart';

/// Masaya per açılırken / taş işlenirken taşların kaynaktan hedefe uçması.
/// [from] ve [to] üstteki Stack'in yerel koordinatındaki MERKEZ noktalarıdır.
/// Taşlar uçarken biraz büyük görünür, hafif yay çizer, hedefe oturunca küçülür.
/// [delay] sırayla açılan perlerin arka arkaya uçması içindir (gecikme dolana
/// kadar hiçbir şey çizilmez). Bitince [onDone] çağrılır.
class TileFlight extends StatefulWidget {
  final List<Tile> tiles;
  final Offset from;
  final Offset to;
  final double fromWidth;
  final double toWidth;
  final bool vertical;
  final Duration delay;
  final Duration duration;
  final VoidCallback onDone;

  const TileFlight({
    super.key,
    required this.tiles,
    required this.from,
    required this.to,
    required this.fromWidth,
    required this.toWidth,
    required this.onDone,
    this.vertical = false,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 420),
  });

  @override
  State<TileFlight> createState() => _TileFlightState();
}

class _TileFlightState extends State<TileFlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _t;
  late final double _startFrac;

  @override
  void initState() {
    super.initState();
    final total = widget.delay + widget.duration;
    _startFrac = widget.delay.inMilliseconds / total.inMilliseconds;
    _c = AnimationController(vsync: this, duration: total);
    _t = CurvedAnimation(
        parent: _c, curve: Interval(_startFrac, 1.0, curve: Curves.easeOutCubic));
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        if (_c.value < _startFrac) {
          return const Positioned(left: 0, top: 0, child: SizedBox.shrink());
        }
        final t = _t.value;
        final p = Offset.lerp(widget.from, widget.to, t)!;
        final arc = math.sin(math.pi * t) * 14; // hafif yay
        final w = widget.fromWidth + (widget.toWidth - widget.fromWidth) * t;
        final tiles = [
          for (final tile in widget.tiles) TileWidget(tile: tile, width: w)
        ];
        return Positioned(
          left: p.dx,
          top: p.dy - arc,
          child: IgnorePointer(
            child: FractionalTranslation(
              translation: const Offset(-.5, -.5),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(.35 * (1 - t)),
                        blurRadius: 8,
                        offset: const Offset(0, 3)),
                  ],
                ),
                child: widget.vertical
                    ? Column(mainAxisSize: MainAxisSize.min, children: tiles)
                    : Row(mainAxisSize: MainAxisSize.min, children: tiles),
              ),
            ),
          ),
        );
      },
    );
  }
}
