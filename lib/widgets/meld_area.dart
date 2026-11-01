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

  /// Uçuş animasyonu sürerken görünmez tutulan taşlar (yer tutarlar, hedef konumu doğru olur).
  final Set<int> hiddenIds;

  /// Hatalı açılıp GERİ TOPLA bekleyen perler (kırmızı çerçeve, işlem yok).
  final List<List<Tile>> pending;
  final bool pendingPairs;

  /// Katlamalı masada sonraki açışın en azı: seri bölgesinde puan, çift bölgesinde adet (sol üst).
  final int? seriesMin;
  final int? pairsMin;

  /// Seri ile çift bölgesinin ARASINDA duran orta sütun (kural etiketleri, gösterge, deste).
  final Widget? center;
  final double centerWidth;
  const MeldArea(
      {super.key,
      required this.melds,
      required this.okey,
      this.highlight,
      this.onTapMeld,
      this.hiddenIds = const <int>{},
      this.pending = const [],
      this.pendingPairs = false,
      this.seriesMin,
      this.pairsMin,
      this.center,
      this.centerWidth = 72});

  @override
  State<MeldArea> createState() => MeldAreaState();
}

class MeldAreaState extends State<MeldArea> {
  final _areaKey = GlobalKey();
  final _centerKey = GlobalKey();
  final List<GlobalKey> _keys = [];

  /// Çift bölgesi: 3 sıra, her sırada çiftler üst üste (referans masa düzeni).
  static const double _tileW = 22;
  static const double _laneW = 30;
  static const double _lanePad = 6;
  static const int _lanes = 3;

  /// Ekran koordinatı alanın içinde mi? (Orta sütun, yani gösterge/deste/etiketler masa sayılmaz.)
  bool containsGlobal(Offset g) {
    final cc = _centerKey.currentContext;
    if (cc != null) {
      final cb = cc.findRenderObject() as RenderBox;
      if (cb.size.contains(cb.globalToLocal(g))) return false;
    }
    final ctx = _areaKey.currentContext;
    if (ctx == null) return false;
    final rb = ctx.findRenderObject() as RenderBox;
    return rb.size.contains(rb.globalToLocal(g));
  }

  /// [i]. perin ekrandaki dikdörtgeni (henüz çizilmediyse null).
  Rect? meldRectGlobal(int i) {
    if (i < 0 || i >= _keys.length) return null;
    final ctx = _keys[i].currentContext;
    if (ctx == null) return null;
    final rb = ctx.findRenderObject();
    if (rb is! RenderBox || !rb.hasSize) return null;
    return rb.localToGlobal(Offset.zero) & rb.size;
  }

  Widget _tw(Tile t, double w) {
    final tw = TileWidget(tile: t, width: w);
    return widget.hiddenIds.contains(t.id) ? Opacity(opacity: 0, child: tw) : tw;
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
              Expanded(
                  child: _zone('SERİ', series, !widget.pendingPairs, widget.seriesMin)),
              Container(width: 1.5, color: Colors.white24),
              if (widget.center != null) ...[
                SizedBox(
                    key: _centerKey,
                    width: widget.centerWidth,
                    child: Center(child: widget.center)),
                Container(width: 1.5, color: Colors.white24),
              ],
              SizedBox(
                  width: _lanes * _laneW + 2 * _lanePad,
                  child: _pairZone(pairs, widget.pendingPairs, widget.pairsMin)),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _zone(String label, List<int> indexes, bool withPending, [int? minValue]) =>
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
          padding: EdgeInsets.fromLTRB(6, minValue == null ? 6 : 22, 6, 6),
          child: Wrap(spacing: 10, runSpacing: 6, children: [
            for (final i in indexes) _meld(i),
            if (withPending)
              for (final g in widget.pending) _pendingMeld(g),
          ]),
        ),
        if (minValue != null) _minChip(minValue),
      ]);

  /// Çift bölgesi: 3 sıra; çiftler (iki taş üst üste) sırayla sıralara dağılır, taşarsa kayar.
  Widget _pairZone(List<int> indexes, bool withPending, int? minValue) {
    final items = <Widget>[
      for (final i in indexes) _pairMeld(i),
      if (withPending)
        for (final g in widget.pending) _pendingMeld(g, vertical: true),
    ];
    return Stack(children: [
      Positioned.fill(
          child: CustomPaint(painter: _LanesPainter(_laneW, _lanePad, _lanes))),
      Positioned(
        right: 4,
        bottom: 3,
        child: Text('ÇİFT',
            style: TextStyle(
                fontSize: 9,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w800,
                color: Colors.white.withOpacity(.22))),
      ),
      SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            _lanePad, minValue == null ? 6 : 22, _lanePad, 18),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var l = 0; l < _lanes; l++)
            SizedBox(
              width: _laneW,
              child: Column(children: [
                for (var k = l; k < items.length; k += _lanes)
                  Padding(padding: const EdgeInsets.only(bottom: 5), child: items[k]),
              ]),
            ),
        ]),
      ),
      if (minValue != null) _minChip(minValue),
    ]);
  }

  Widget _minChip(int v) => Positioned(
        left: 4,
        top: 4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(.35),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.gold.withOpacity(.7)),
          ),
          child: Text('MİN $v',
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .8,
                  color: AppColors.gold)),
        ),
      );

  Widget _pairMeld(int i) {
    final m = widget.melds[i];
    final hot = widget.highlight?.call(m) ?? false;
    return GestureDetector(
      key: _keys[i],
      onTap: widget.onTapMeld == null ? null : () => widget.onTapMeld!(i),
      child: Container(
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
              color: hot ? AppColors.gold : Colors.transparent, width: 1.5),
          color: hot ? AppColors.gold.withOpacity(.15) : null,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final t in m.tiles) _tw(t, _tileW),
        ]),
      ),
    );
  }

  Widget _pendingMeld(List<Tile> g, {bool vertical = false}) => Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.bad, width: 1.5),
          color: AppColors.bad.withOpacity(.18),
        ),
        child: vertical
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                for (final t in g) TileWidget(tile: t, width: _tileW),
              ])
            : Row(mainAxisSize: MainAxisSize.min, children: [
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
          for (final t in m.tiles) _tw(t, 20),
        ]),
      ),
    );
  }
}

class _LanesPainter extends CustomPainter {
  final double laneW, pad;
  final int lanes;
  const _LanesPainter(this.laneW, this.pad, this.lanes);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withOpacity(.12)
      ..strokeWidth = 1;
    for (var k = 1; k < lanes; k++) {
      final x = pad + laneW * k - 1;
      canvas.drawLine(Offset(x, 6), Offset(x, size.height - 6), p);
    }
  }

  @override
  bool shouldRepaint(_LanesPainter old) => false;
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
