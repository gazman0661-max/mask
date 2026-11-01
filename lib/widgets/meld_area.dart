import 'package:flutter/material.dart';
import '../logic/meld.dart';
import '../logic/okey_rules.dart';
import '../models/tile.dart';
import '../theme/app_theme.dart';
import 'tile_widget.dart';

/// Sürüklenen taşın bırakıldığı per ve taraf (seride okey için baş/son).
class MeldHit {
  final int index;
  final bool front;
  const MeldHit(this.index, this.front);
}

/// Masaya açılan perlerin dizildiği alan (taşarsa kaydırılır).
/// [highlight] true dönen perler seçili/sürüklenen taşı kabul ettiğini gösterir.
class MeldArea extends StatefulWidget {
  final List<Meld> melds;
  final Okey okey;
  final bool Function(Meld)? highlight;
  final void Function(int index)? onTapMeld;

  /// Hatalı açılıp GERİ TOPLA bekleyen perler (kırmızı çerçeve, işlem yok).
  final List<List<Tile>> pending;
  final bool pendingPairs;
  const MeldArea(
      {super.key,
      required this.melds,
      required this.okey,
      this.highlight,
      this.onTapMeld,
      this.pending = const [],
      this.pendingPairs = false});

  @override
  State<MeldArea> createState() => MeldAreaState();
}

class MeldAreaState extends State<MeldArea> {
  final _areaKey = GlobalKey();
  final List<GlobalKey> _keys = [];

  /// Ekran koordinatı alanın içinde mi?
  bool containsGlobal(Offset g) {
    final ctx = _areaKey.currentContext;
    if (ctx == null) return false;
    final rb = ctx.findRenderObject() as RenderBox;
    return rb.size.contains(rb.globalToLocal(g));
  }

  /// Ekran koordinatının denk geldiği per (kenarlardan biraz pay bırakılır).
  /// Yoksa null. [front]: noktanın perin sol yarısında olup olmadığı.
  MeldHit? hitMeld(Offset g) {
    for (var i = 0; i < widget.melds.length && i < _keys.length; i++) {
      final ctx = _keys[i].currentContext;
      if (ctx == null) continue;
      final rb = ctx.findRenderObject() as RenderBox;
      final local = rb.globalToLocal(g);
      final rect = (Offset.zero & rb.size).inflate(8);
      if (rect.contains(local)) return MeldHit(i, local.dx < rb.size.width / 2);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    while (_keys.length < widget.melds.length) {
      _keys.add(GlobalKey());
    }
    // Seri/küt perleri solda, çift perleri sağda ayrı bölgelerde durur.
    final series = <int>[], pairs = <int>[];
    for (var i = 0; i < widget.melds.length; i++) {
      (widget.melds[i].kind == MeldKind.pair ? pairs : series).add(i);
    }
    return ClipRRect(
      key: _areaKey,
      borderRadius: BorderRadius.circular(10),
      child: CustomPaint(
        painter: _GridPainter(),
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.black.withOpacity(.2),
          child: Stack(children: [
            Center(
              child: Text('101',
                  style: TextStyle(
                      fontSize: 72,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                      color: Colors.white.withOpacity(.05))),
            ),
            Row(children: [
              Expanded(flex: 3, child: _zone('SERİ', series, !widget.pendingPairs)),
              Container(width: 1.5, color: Colors.white24),
              Expanded(flex: 2, child: _zone('ÇİFT', pairs, widget.pendingPairs)),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _zone(String label, List<int> indexes, bool withPending) =>
      Stack(children: [
        Positioned(
          right: 6,
          bottom: 3,
          child: Text(label,
              style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w800,
                  color: Colors.white.withOpacity(.22))),
        ),
        SingleChildScrollView(
          padding: const EdgeInsets.all(6),
          child: Wrap(spacing: 10, runSpacing: 6, children: [
            for (final i in indexes) _meld(i),
            if (withPending)
              for (final g in widget.pending) _pendingMeld(g),
          ]),
        ),
      ]);

  Widget _pendingMeld(List<Tile> g) => Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.bad, width: 1.5),
          color: AppColors.bad.withOpacity(.18),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final t in g) TileWidget(tile: t, width: 20),
        ]),
      );

  Widget _meld(int i) {
    final m = widget.melds[i];
    final hot = widget.highlight?.call(m) ?? false;
    return GestureDetector(
      key: _keys[i],
      onTap: widget.onTapMeld == null ? null : () => widget.onTapMeld!(i),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: hot ? AppColors.gold : Colors.transparent, width: 1.5),
          color: hot ? AppColors.gold.withOpacity(.15) : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final t in m.tiles)
            TileWidget(tile: t, width: 20),
        ]),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withOpacity(.05)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 18) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 18) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}
