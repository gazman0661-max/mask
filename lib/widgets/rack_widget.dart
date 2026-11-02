import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import '../logic/hand_scorer.dart';
import '../logic/meld.dart';
import '../models/app_settings.dart';
import '../logic/okey_rules.dart';
import '../logic/rack_shift.dart';
import '../models/tile.dart';
import '../theme/app_theme.dart';
import 'tile_widget.dart';

/// 2 satır x [columns] yuvalık ahşap ıstaka. Taş sürüklenirken komşular kayıp
/// Taş sürüklenirken diğer taşlar yerinde durur; bırakılınca komşular kayıp yer açar
/// ve taş araya oturur (takas yok, bkz. [RackShift]); dokununca seçilir. Dokunma/sürükleme, döndürülmüş ve
/// ölçeklenmiş (RotatedBox/FittedBox) ekranlarda da, tarayıcıda da kesin
/// çalışsın diye jest sistemi (GestureDetector) yerine ham işaretçi
/// olayları (Listener) ile yapılır. Tüm ıstaka TEK bir Listener altındadır;
/// bu yüzden sürükleme sırasında olayları alan widget asla yok edilmez.
class RackWidget extends StatefulWidget {
  final List<Tile?> slots;
  final int columns;
  final double maxTileWidth;
  final Okey okey;
  final int? selectedId;
  final int? markedId;

  /// Yardımlı masada işlenebilir taşları işaretlemek için (null = işaret yok).
  final bool Function(Tile tile)? isLayable;
  final void Function(int from, int to) onMove;

  /// KALIP taşıma: bir per ya da çifte (yan yana duran geçerli grup) ~0,4 sn basılı tutup sürükleyince
  /// grup bütün olarak taşınır. [from] grubun yuvaları (soldan sağa), [to] yeni yuvaları.
  final void Function(List<int> from, List<int> to)? onMoveGroup;
  final void Function(Tile tile) onTapTile;

  /// Taş ıstaka dışına bırakılınca (örn. atık yuvasına) çağrılır.
  final void Function(Tile tile, Offset global)? onDropOutside;

  /// Sürükleme başlayınca / parmak hareket edince / bırakılınca (hedef
  /// vurgulamak için). onDragEnd, onMove/onDropOutside'dan ÖNCE çağrılır.
  final void Function(Tile tile)? onDragStart;
  final void Function(Offset global)? onDragMove;
  final VoidCallback? onDragEnd;

  const RackWidget(
      {super.key,
      required this.slots,
      required this.okey,
      required this.onMove,
      this.onMoveGroup,
      required this.onTapTile,
      this.onDropOutside,
      this.onDragStart,
      this.onDragMove,
      this.onDragEnd,
      this.selectedId,
      this.markedId,
      this.isLayable,
      this.columns = 16,
      this.maxTileWidth = 34});

  @override
  State<RackWidget> createState() => RackWidgetState();
}

class RackWidgetState extends State<RackWidget> {
  static const _padX = 8.0, _padY = 4.0, _border = 1.5, _slop = 6.0;
  final _key = GlobalKey();
  int? _drag, _hover, _ext;
  Offset _lastGlobal = Offset.zero;
  Offset _pos = Offset.zero;

  // Ham işaretçi takibi
  int? _pointer; // aktif parmak
  int? _cand; // parmağın bastığı yuva
  Offset _downGlobal = Offset.zero;
  bool _moved = false;

  // Kalıp (grup) taşıma: basılı tutunca per/çift bütün olarak sürüklenir
  static const _holdTime = Duration(milliseconds: 380);
  Timer? _holdTimer;
  List<int>? _grp; // kalıbın yuvaları (aynı satır, soldan sağa); null = tek taş modu
  List<int>? _grpDest; // sürüklerken kalıbın bırakılacağı yuvalar

  // Kayma animasyonu: taşın bir önceki çizimdeki yuvası; yuva değişince eski yerinden yenisine kayar.
  Map<int, int> _prevSlot = {}, _nowSlot = {};
  final Map<int, int> _slideSlot = {}; // taş -> kaymanın hedef yuvası
  final Map<int, Offset> _slideFrom = {}; // taş -> kaymanın başlangıç farkı
  static const _slideTime = Duration(milliseconds: 200);
  // Bırakılan taş: parmağın olduğu yerden yuvasına oturur (komşular aynı anda kayar).
  int? _dropId;
  Offset _dropFrom = Offset.zero;

  // Sürükleme önizlemesi: komşular kaymış, tutulan taş çıkarılmış dizilim
  List<Tile?> _view = const [];

  // Çizim sırasında hesaplanan geometri
  double _tileW = 30, _cell = 32, _cellH = 44, _left = 8;

  Offset _local(Offset global) =>
      (_key.currentContext!.findRenderObject() as RenderBox).globalToLocal(global);

  /// Ekran koordinatındaki noktanın hangi yuvaya denk geldiği (ızgara dışıysa null).
  int? slotAt(Offset global) {
    if (_key.currentContext == null) return null;
    return _indexAt(_local(global));
  }

  /// Dışarıdan sürüklenen taş (deste/atık) için hedef yuvayı vurgular.
  void setExternalHover(int? i) {
    if (_ext != i) setState(() => _ext = i);
  }

  int? _indexAt(Offset p) {
    final col = ((p.dx - _left) / _cell).floor();
    final row = ((p.dy - _border - _padY) / _cellH).floor();
    if (col < 0 || col >= widget.columns || row < 0 || row >= 2) return null;
    return row * widget.columns + col;
  }

  void _reset() {
    final wasDrag = _drag != null && _grp == null;
    _holdTimer?.cancel();
    _pointer = null;
    _cand = null;
    _moved = false;
    if (_drag != null || _hover != null || _grp != null) {
      setState(() {
        _drag = _hover = null;
        _grp = null;
        _grpDest = null;
      });
    }
    if (wasDrag) widget.onDragEnd?.call();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  /// [slot]taki taşın bulunduğu geçerli per/çiftin yuvaları (yoksa null).
  /// Grup = aralarında boşluk olmayan, aynı satırdaki taşlar; yalnız geçerli seri/küt ya da çift sayılır.
  List<int>? _groupAt(int slot) {
    final cols = widget.columns;
    if (slot < 0 || slot >= widget.slots.length || widget.slots[slot] == null) return null;
    final row = slot ~/ cols;
    var a = slot, b = slot;
    while (a > row * cols && widget.slots[a - 1] != null) {
      a--;
    }
    while (b < row * cols + cols - 1 && widget.slots[b + 1] != null) {
      b++;
    }
    if (b - a + 1 < 2) return null;
    final tiles = [for (var i = a; i <= b; i++) widget.slots[i]!];
    final ok = GroupRules.valueOf(tiles, widget.okey) > 0 ||
        (tiles.length == 2 && Meld.pairFrom(tiles, widget.okey, 0) != null);
    if (!ok) return null;
    return [for (var i = a; i <= b; i++) i];
  }

  /// Parmak [hover] yuvasındayken kalıbın yeni yuvaları: satır parmağın satırı, sütun kaydırılır ama satıra sığar.
  List<int> _destFor(List<int> grp, int anchor, int hover) {
    final cols = widget.columns;
    final dRow = hover ~/ cols - anchor ~/ cols;
    var dCol = hover % cols - anchor % cols;
    final minCol = grp.first % cols, maxCol = grp.last % cols;
    if (minCol + dCol < 0) dCol = -minCol;
    if (maxCol + dCol > cols - 1) dCol = cols - 1 - maxCol;
    final row = grp.first ~/ cols + dRow;
    return [for (final i in grp) row * cols + (i % cols) + dCol];
  }

  void _holdFired() {
    final c = _cand;
    if (_pointer == null || _moved || c == null) return;
    final g = widget.onMoveGroup == null ? null : _groupAt(c);
    if (g == null) return;
    if (AppSettings.I.vibration) HapticFeedback.selectionClick().catchError((Object _) {});
    setState(() {
      _grp = g;
      _grpDest = g;
    });
  }

  void _onDown(PointerDownEvent e) {
    if (_pointer != null) return;
    if (_key.currentContext == null) return;
    final i = _indexAt(_local(e.position));
    if (i == null || widget.slots[i] == null) return;
    _dropId = null;
    _pointer = e.pointer;
    _cand = i;
    _downGlobal = e.position;
    _lastGlobal = e.position;
    _moved = false;
    _grp = null;
    _grpDest = null;
    _holdTimer?.cancel();
    _holdTimer = Timer(_holdTime, _holdFired);
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    _lastGlobal = e.position;
    if (!_moved) {
      if ((e.position - _downGlobal).distance < _slop) return;
      _holdTimer?.cancel(); // tutma süresi dolmadan kaydı: tek taş sürüklemesi
      _moved = true;
      _drag = _cand;
      final t = _drag == null ? null : widget.slots[_drag!];
      if (t != null && _grp == null) widget.onDragStart?.call(t);
    }
    final p = _local(e.position);
    final h = _indexAt(p);
    setState(() {
      _pos = p;
      _hover = h;
      if (_grp != null && _cand != null && h != null) _grpDest = _destFor(_grp!, _cand!, h);
    });
    if (_grp == null) widget.onDragMove?.call(e.position);
  }

  void _onUp(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    _holdTimer?.cancel();
    final cand = _cand, wasDrag = _moved, from = _drag, to = _hover;
    final grp = _grp, dest = _grpDest;
    _pointer = null;
    _cand = null;
    _moved = false;
    if (grp != null) {
      // Kalıp: bırakılan yere taşı (ıstaka dışında bırakılırsa iptal)
      setState(() {
        _drag = _hover = null;
        _grp = null;
        _grpDest = null;
      });
      if (wasDrag) {
        if (to != null && dest != null) widget.onMoveGroup?.call(grp, dest);
      } else {
        final t = cand == null ? null : widget.slots[cand]; // sürüklemeden bırakıldı: dokunuş say
        if (t != null) widget.onTapTile(t);
      }
      return;
    }
    if (!wasDrag) {
      // Dokunuş: taşı seç / bırak
      final t = cand == null ? null : widget.slots[cand];
      if (t != null) widget.onTapTile(t);
      return;
    }
    // Bırakılan taşın parmak konumu: yuvasına oturma animasyonu buradan başlar.
    final dropTile = from == null ? null : widget.slots[from];
    if (to != null && dropTile != null) {
      final cols = widget.columns;
      final cellCenter = Offset(_left + (to % cols) * _cell + _cell / 2,
          _border + _padY + (to ~/ cols) * _cellH + 2 + _tileW * 1.35 / 2);
      _dropId = dropTile.id;
      _dropFrom = _pos - cellCenter;
    }
    setState(() => _drag = _hover = null);
    widget.onDragEnd?.call();
    if (from == null) return;
    if (to != null) {
      if (from != to) widget.onMove(from, to);
    } else {
      final t = widget.slots[from];
      if (t != null) widget.onDropOutside?.call(t, _lastGlobal);
    }
  }

  void _onCancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _reset();
  }

  /// Ekranda gösterilecek dizilim. Tek taş sürüklenirken tutulan taş yerinden
  /// çıkar ama komşular YERİNDE durur (sürüklerken kayma yok). Taş bırakılınca
  /// gerçek taşıma [RackShift.move] ile olur; komşular yumuşakça kayar, bırakılan
  /// taş da parmağın olduğu yerden yuvasına oturur (bkz. [_slid]).
  List<Tile?> _computeView() {
    final s = widget.slots;
    final d = _drag;
    if (_grp != null || d == null || d < 0 || d >= s.length || s[d] == null) return s;
    final o = List<Tile?>.of(s);
    o[d] = null;
    return o;
  }

  @override
  Widget build(BuildContext context) {
    final cols = widget.columns;
    _view = _computeView();
    _prevSlot = _nowSlot;
    _nowSlot = {};
    // Görünümden çıkan taşın (sürüklenen) eski kayma kaydı silinir; geri gelince eski yerinden kaymasın.
    _slideSlot.removeWhere((id, _) => !_prevSlot.containsKey(id));
    _slideFrom.removeWhere((id, _) => !_prevSlot.containsKey(id));
    return LayoutBuilder(builder: (context, box) {
      // Kenarlık (1.5 x 2) ve iç boşluk düşülür; yoksa satır 3 px taşar.
      final inner = box.maxWidth - _border * 2 - _padX * 2;
      _tileW = (inner / cols - 2).clamp(14.0, widget.maxTileWidth).toDouble();
      _cell = _tileW + 2;
      _cellH = _tileW * 1.35 + 4;
      _left = _border + _padX + (inner - cols * _cell) / 2;

      return Stack(clipBehavior: Clip.none, children: [
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onDown,
          onPointerMove: _onMove,
          onPointerUp: _onUp,
          onPointerCancel: _onCancel,
          child: Container(
          key: _key,
          width: box.maxWidth,
          padding: const EdgeInsets.symmetric(horizontal: _padX, vertical: _padY),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.woodLight, AppColors.wood, AppColors.woodDark]),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black54, width: 1.5),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 3))
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (var row = 0; row < 2; row++)
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var col = 0; col < cols; col++) _cellAt(row * cols + col),
              ]),
          ]),
        )),
        if (_grp != null && _drag != null)
          Positioned(
            left: _pos.dx - (_cand! - _grp!.first) * _cell - _tileW * .6,
            top: _pos.dy - _tileW * .8,
            // Not: taş 1.1x büyük olduğu için aralık (_cell - 1.1*_tileW) eksiye düşebilir; eksi Padding
            // çizim hatası (kırmızı kutu) verir. Bu yüzden her taş kendi yuva genişliğinde bir
            // kutuya konur, taşma OverflowBox ile olur.
            child: IgnorePointer(
                child: SizedBox(
              width: _cell * _grp!.length + _tileW * .2,
              height: _tileW * 1.35 * 1.1,
              child: Stack(clipBehavior: Clip.none, children: [
                for (var k = 0; k < _grp!.length; k++)
                  Positioned(
                      left: k * _cell,
                      top: 0,
                      child: TileWidget(
                          tile: widget.slots[_grp![k]]!,
                          width: _tileW * 1.1,
                          hidden: widget.okey.isWild(widget.slots[_grp![k]]!))),
              ]),
            )),
          )
        else if (_drag != null && widget.slots[_drag!] != null)
          Positioned(
            left: _pos.dx - _tileW * .6,
            top: _pos.dy - _tileW * .8,
            child: IgnorePointer(
                child: TileWidget(
                    tile: widget.slots[_drag!]!,
                    width: _tileW * 1.2,
                    hidden: widget.okey.isWild(widget.slots[_drag!]!))),
          ),
      ]);
    });
  }

  /// Taş yuvası değiştiyse eski yerinden yenisine kayar (komşular açılan boşluğa, taş araya).
  Widget _slid(Tile tile, int i, Widget face) {
    final id = tile.id;
    _nowSlot[id] = i;
    final prev = _prevSlot[id];
    if (id == _dropId) {
      // Az önce bırakılan taş: parmaktan yuvasına kay.
      _dropId = null;
      _slideSlot[id] = i;
      _slideFrom[id] = _dropFrom;
    } else if (prev != null && prev != i && _slideSlot[id] != i) {
      final cols = widget.columns;
      _slideSlot[id] = i;
      _slideFrom[id] = Offset(((prev % cols) - (i % cols)) * _cell,
          ((prev ~/ cols) - (i ~/ cols)) * _cellH);
    }
    final from = _slideSlot[id] == i ? _slideFrom[id]! : Offset.zero;
    return TweenAnimationBuilder<Offset>(
      key: ValueKey('$id@$i'),
      tween: Tween<Offset>(begin: from, end: Offset.zero),
      duration: _slideTime,
      curve: Curves.easeOut,
      builder: (context, o, child) => Transform.translate(offset: o, child: child),
      child: face,
    );
  }

  Widget _cellAt(int i) {
    final tile = i < _view.length ? _view[i] : null;
    final inGrp = _grp != null && _grp!.contains(i);
    final hover = _grp != null
        ? (_drag != null ? (_grpDest?.contains(i) ?? false) : inGrp) // basılı tutunca kalıp parlar
        : ((_drag != null && _hover == i) || _ext == i);
    final selected = tile != null && tile.id == widget.selectedId;
    return Container(
      width: _tileW,
      height: _tileW * 1.35,
      margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(hover ? .4 : .22),
        borderRadius: BorderRadius.circular(_tileW * .16),
        border: hover ? Border.all(color: AppColors.gold, width: 2) : null,
      ),
      child: (tile == null || (_grp != null && _drag != null && inGrp))
          ? null
          : _slid(
              tile,
              i,
              Transform.translate(
                offset: Offset(0, selected ? -6 : 0),
                child: TileWidget(
                    tile: tile,
                    width: _tileW,
                    hidden: widget.okey.isWild(tile),
                    layable: widget.isLayable?.call(tile) ?? false,
                    selected: selected,
                    glow: tile.id == widget.markedId),
              )),
    );
  }
}
