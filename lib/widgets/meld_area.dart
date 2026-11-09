import 'dart:math' as math;
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

  /// YERLEŞİM (referans masa gibi SABİT SATIRLI ızgara):
  /// - Her per / çift kendi SATIRINA oturur; seri ve çift bölgesinin satırları aynı hizadadır.
  /// - SERİ bölgesi bölümlere ayrılır (normalde 2, çok per varsa 3). Bölümün sol üstünden aşağı dizilir,
  ///   bölüm dolunca sonrakinin en üstünden devam edilir.
  /// - ÇİFT bölgesi 3 şerittir; çiftin iki taşı yan yana, şerit dolunca sonrakine geçilir.
  /// Satır aralığı çok dar tutulur (taş boyu + 3 px); böylece aynı yükseklikte referanstaki gibi çok satır sığar.
  /// Taş genişliği masaya göre [_maxTile] ile [_minTile] arasında ayarlanır; sığmazsa son bölüm kayar.
  static const double _maxTile = 20;
  static const double _minTile = 10;
  static const double _lanePad = 4;
  static const int _lanes = 3; // çift şeridi sayısı
  static const double _meldPad = 1; // perin taşlara iç payı (her kenar)
  static const double _rowGap = 1.5; // satırlar arası boşluk
  static const double _secPad = 5; // seri bölümü iç boşluğu (sol/sağ)
  static const double _baseTop = 4; // ızgaranın üst payı
  static const double _chipTop = 20; // katlamalı "MİN" etiketi varken üst pay
  static const double _bottomPad = 4;
  double _tileW = _maxTile;
  int _sections = 2; // seri bölümü sayısı
  int _serCap = 99; // bir seri bölümündeki satır (per) kapasitesi
  int _pairCap = 99; // bir çift şeridindeki çift kapasitesi

  double _laneWFor(double tw) => tw * 2 + 2 * _meldPad + 3;
  double get _laneW => _laneWFor(_tileW);
  double _rowHFor(double tw) => tw * 1.35 + 2 * _meldPad + _rowGap;
  double get _rowH => _rowHFor(_tileW);

  /// Şu an masadaki taşın genişliği (uçuş animasyonu hedef boyutu için).
  double get tileWidth => _tileW;

  /// Bir seri bölümüne / çift şeridine sığan satır sayısı (testler ve ekran için).
  int get rowCapacity => _serCap;

  /// Şu an kaç seri bölümü kullanılıyor (2, çok per varsa 3).
  int get sectionCount => _sections;

  double _top() =>
      (widget.seriesMin != null || widget.pairsMin != null) ? _chipTop : _baseTop;

  /// Bir bölüme / şeride sığan satır sayısı (seri ve çift satırları aynı hizada).
  int _capFor(double tw, double h) =>
      math.max(1, ((h - _top() - _bottomPad) / _rowHFor(tw)).floor());

  /// Seri bölgesinin (tüm bölümler) toplam genişliği.
  double _seriesWidth(double tw, double w) {
    final pairW = _lanes * _laneWFor(tw) + 2 * _lanePad;
    final centerW = widget.center != null ? widget.centerWidth + 1.5 : 0.0;
    return w - pairW - centerW - 1.5 - 2;
  }

  /// Verilen taş genişliği ve bölüm sayısıyla tüm perler + çiftler alana sığar mı?
  bool _fits(double tw, int sections, double w, double h, int pairCount) {
    final lens = _seriesLens();
    final cap = _capFor(tw, h);
    if (lens.isNotEmpty) {
      final secInner = (_seriesWidth(tw, w) - (sections - 1)) / sections - 2 * _secPad;
      final longest = lens.reduce(math.max) * tw + 2 * _meldPad;
      if (longest > secInner) return false;
      if (lens.length > sections * cap) return false;
    }
    if (pairCount > 0 && pairCount > _lanes * cap) return false;
    return true;
  }

  List<int> _seriesLens() => <int>[
        for (final m in widget.melds)
          if (m.kind != MeldKind.pair) m.tiles.length,
        if (!widget.pendingPairs)
          for (final g in widget.pending) g.length,
      ];

  /// Taş bu genişliğin altına inecekse 2 bölüm yerine 3 bölüm açılır (okunaklı kalsın).
  static const double _comfortTile = 12;

  /// En büyük taşı ve gereken bölüm sayısını seçer: önce 2 bölüm (taş 20 -> 12), sığmazsa 3 bölüm
  /// (taş 20 -> 10), o da olmadı 2 bölüm ile en küçük taşlar.
  void _pickLayout(double w, double h) {
    var pairCount = 0;
    for (final m in widget.melds) {
      if (m.kind == MeldKind.pair) pairCount++;
    }
    pairCount += widget.pendingPairs ? widget.pending.length : 0;
    bool tryIt(int sec, double from, double to) {
      for (var tw = from; tw >= to; tw -= 1) {
        if (_fits(tw, sec, w, h, pairCount)) {
          _tileW = tw;
          _sections = sec;
          return true;
        }
      }
      return false;
    }

    if (tryIt(2, _maxTile, _comfortTile)) return;
    if (tryIt(3, _maxTile, _minTile)) return;
    if (tryIt(2, _comfortTile - 1, _minTile)) return;
    // Hiçbiri sığmadı: en küçük taş. Per sayısı 2 bölüme sığmıyorsa 3 bölüm, aksi halde 2 bölüm.
    _tileW = _minTile;
    _sections = _seriesLens().length > 2 * _capFor(_minTile, h) ? 3 : 2;
  }

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

  /// Ekran koordinatının denk geldiği per. Satırlar sık olduğu için önce tam isabet aranır,
  /// yoksa kenarlardan en çok 6 px içindeki en yakın per seçilir. Yoksa null.
  /// [front]: noktanın perin sol yarısında olup olmadığı.
  MeldHit? hitMeld(Offset g) {
    int? best;
    var bestD = double.infinity;
    var bestFront = true;
    for (var i = 0; i < widget.melds.length && i < _keys.length; i++) {
      final ctx = _keys[i].currentContext;
      if (ctx == null) continue;
      final rb = ctx.findRenderObject();
      if (rb is! RenderBox || !rb.hasSize) continue;
      final local = rb.globalToLocal(g);
      final rect = Offset.zero & rb.size;
      if (rect.contains(local)) return MeldHit(i, local.dx < rb.size.width / 2);
      if (rect.inflate(6).contains(local)) {
        final d = (local - rect.center).distance;
        if (d < bestD) {
          best = i;
          bestD = d;
          bestFront = local.dx < rb.size.width / 2;
        }
      }
    }
    return best == null ? null : MeldHit(best, bestFront);
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
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth.isFinite && box.maxHeight.isFinite) {
        _pickLayout(box.maxWidth, box.maxHeight);
        _serCap = _capFor(_tileW, box.maxHeight);
        _pairCap = _serCap;
      }
      return ClipRRect(
        key: _areaKey,
        borderRadius: BorderRadius.circular(10),
        child: CustomPaint(
          painter: _GridPainter(rowH: _rowH, top: _top()),
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
    });
  }

  /// Bir ızgara satırı: sabit yükseklikte, içerik solda; uzun per sığmazsa küçülür (kırpılmaz).
  Widget _row(Widget w, {bool shrink = true}) => SizedBox(
        height: _rowH,
        child: Align(
          alignment: Alignment.centerLeft,
          child: shrink
              ? FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: w)
              : w,
        ),
      );

  /// Seri bölgesi: bölümler yan yana. Her per bir satır; satırlar bölümün sol üstünden aşağı dizilir,
  /// bölüm dolunca sonrakinin en üstünden devam eder (son bölüm taşarsa kayar).
  Widget _zone(String label, List<int> indexes, bool withPending, [int? minValue]) {
    final items = <Widget>[
      for (final i in indexes) _meldBox(i),
      if (withPending)
        for (final g in widget.pending) _pendingMeld(g),
    ];
    final secs = List.generate(_sections, (_) => <Widget>[]);
    for (var k = 0; k < items.length; k++) {
      secs[math.min(k ~/ _serCap, _sections - 1)].add(items[k]);
    }
    return Stack(children: [
      Positioned(
        right: 6,
        bottom: 3,
        child: Text(label,
            style: TextStyle(
                fontSize: 10,
                letterSpacing: 2,
                fontWeight: FontWeight.w800,
                color: Colors.white.withOpacity(.2))),
      ),
      Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var s = 0; s < _sections; s++) ...[
          if (s > 0)
            Container(
                width: 1,
                margin: const EdgeInsets.symmetric(vertical: 8),
                color: Colors.white.withOpacity(.14)),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(_secPad, _top(), _secPad, _bottomPad),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final w in secs[s]) _row(w),
              ]),
            ),
          ),
        ],
      ]),
      if (minValue != null) _minChip(minValue),
    ]);
  }

  /// Çift bölgesi: 3 şerit; çiftler (iki taş yan yana) 1. şeridin üstünden aşağı dizilir, dolunca 2. şeride geçer.
  Widget _pairZone(List<int> indexes, bool withPending, int? minValue) {
    final items = <Widget>[
      for (final i in indexes) _meldBox(i),
      if (withPending)
        for (final g in widget.pending) _pendingMeld(g),
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
                color: Colors.white.withOpacity(.2))),
      ),
      SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(_lanePad, _top(), _lanePad, _bottomPad),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var l = 0; l < _lanes; l++)
            SizedBox(
              width: _laneW,
              child: Column(children: [
                // Şerit yukarıdan aşağı dolar; dolunca sonrakinin en üstünden devam (son şerit kayar).
                for (var k = 0; k < items.length; k++)
                  if (math.min(k ~/ _pairCap, _lanes - 1) == l) _row(items[k], shrink: false),
              ]),
            ),
        ]),
      ),
      if (minValue != null) _minChip(minValue),
    ]);
  }

  Widget _minChip(int v) => Positioned(
        left: 4,
        top: 2,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
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

  /// Hatalı açılıp GERİ TOPLA bekleyen grup (kırmızı çerçeve). Çerçeve yer kaplamaz (satır yüksekliği sabit kalır).
  Widget _pendingMeld(List<Tile> g) => Container(
        padding: const EdgeInsets.all(_meldPad),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          color: AppColors.bad.withOpacity(.18),
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: AppColors.bad, width: 1.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final t in g) TileWidget(tile: t, width: _tileW),
        ]),
      );

  /// Masadaki per ya da çift: taşlar yan yana. İşlenebilirse altın çerçeve (çerçeve yer kaplamaz).
  Widget _meldBox(int i) {
    final m = widget.melds[i];
    final hot = widget.highlight?.call(m) ?? false;
    final radius = BorderRadius.circular(5);
    return GestureDetector(
      key: _keys[i],
      onTap: widget.onTapMeld == null ? null : () => widget.onTapMeld!(i),
      child: Container(
        padding: const EdgeInsets.all(_meldPad),
        decoration: BoxDecoration(
          borderRadius: radius,
          color: hot ? AppColors.gold.withOpacity(.15) : null,
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
              color: hot ? AppColors.gold : Colors.transparent, width: 1.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final t in m.tiles) _tw(t, _tileW),
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
  bool shouldRepaint(_LanesPainter old) =>
      old.laneW != laneW || old.pad != pad || old.lanes != lanes;
}

/// Izgara satır çizgileri: her satırın alt sınırında silik bir çizgi (defter çizgisi gibi).
class _GridPainter extends CustomPainter {
  final double rowH, top;
  const _GridPainter({required this.rowH, required this.top});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withOpacity(.05)
      ..strokeWidth = 1;
    for (double y = top + rowH; y < size.height; y += rowH) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.rowH != rowH || old.top != top;
}
