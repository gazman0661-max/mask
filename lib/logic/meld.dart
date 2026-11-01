import '../models/tile.dart';
import 'okey_rules.dart';

enum MeldKind { set, run, pair }

/// Perdeki okeyin yerine gerçek taş koyup okeyi almanın sonucu (okey çalma).
class JokerSwap {
  final Meld meld;
  final Tile joker;
  const JokerSwap(this.meld, this.joker);
}

/// Masaya açılmış bir per. Okey (joker), yerine temsil ettiği gerçek taş
/// konarak çalınabilir (bkz. [Meld.trySwap]).
class Meld {
  final MeldKind kind;
  final List<Tile> tiles;

  /// Küt/çift: sayı. Seri: ilk taşın konumu (1..11).
  final int number;

  /// Seri/çift rengi (küt için anlamsız).
  final TileColor color;

  /// Perı açan koltuk.
  final int owner;

  Meld._(this.kind, this.tiles, this.number, this.color, this.owner);

  int get value {
    if (kind == MeldKind.set) return number * tiles.length;
    if (kind == MeldKind.pair) return number * 2;
    var s = 0;
    for (var i = 0; i < tiles.length; i++) {
      s += GroupRules.faceOf(number + i);
    }
    return s;
  }

  /// Yan yana dizilmiş taşlar geçerli küt/seri ise Meld, değilse null.
  /// 1 yalnızca başta olabilir (12-13-1 geçersiz).
  static Meld? fromGroup(List<Tile> g, Okey okey, int owner) {
    final a = _asSet(g, okey, owner);
    final b = _asRun(g, okey, owner);
    if (a == null) return b;
    if (b == null) return a;
    return a.value >= b.value ? a : b;
  }

  static Meld? _asSet(List<Tile> g, Okey okey, int owner) {
    if (g.length < 3 || g.length > 4) return null;
    final real = g.where((t) => !okey.isWild(t)).toList();
    if (real.isEmpty) return null;
    final n = okey.numberOf(real.first);
    final colors = <TileColor>{};
    for (final t in real) {
      if (okey.numberOf(t) != n) return null;
      if (!colors.add(okey.colorOf(t))) return null;
    }
    return Meld._(MeldKind.set, List<Tile>.of(g), n, okey.colorOf(real.first), owner);
  }

  static Meld? _asRun(List<Tile> g, Okey okey, int owner) {
    final start = GroupRules.runStart(g, okey);
    if (start == null) return null;
    // Azalan dizilmiş seri (4-3-2-1) masaya artan sırayla konur.
    final tiles = GroupRules.orient(g, okey);
    var first = 0;
    while (okey.isWild(tiles[first])) {
      first++;
    }
    return Meld._(
        MeldKind.run, tiles, start, okey.colorOf(tiles[first]), owner);
  }

  /// Aynı sayı ve renkte iki taş (biri okey olabilir).
  static Meld? pairFrom(List<Tile> g, Okey okey, int owner) {
    if (g.length != 2) return null;
    final a = g[0], b = g[1];
    final wa = okey.isWild(a), wb = okey.isWild(b);
    if (wa && wb) {
      return Meld._(MeldKind.pair, List<Tile>.of(g), okey.number, okey.color, owner);
    }
    final base = wa ? b : a;
    if (!wa && !wb) {
      if (okey.numberOf(a) != okey.numberOf(b) ||
          okey.colorOf(a) != okey.colorOf(b)) {
        return null;
      }
    }
    return Meld._(MeldKind.pair, List<Tile>.of(g), okey.numberOf(base),
        okey.colorOf(base), owner);
  }

  /// Taşı pere işlemeyi dener; olmazsa null.
  /// [front]: yalnızca seride okey için anlamlıdır; true = başa, false = sona
  /// eklemeyi tercih eder (mümkün değilse diğer uç denenir).
  Meld? tryAdd(Tile t, Okey okey, {bool? front}) {
    if (kind == MeldKind.pair) return null;
    final wild = okey.isWild(t);
    if (kind == MeldKind.set) {
      if (tiles.length >= 4) return null;
      if (!wild) {
        if (okey.numberOf(t) != number) return null;
        for (final x in tiles) {
          if (!okey.isWild(x) && okey.colorOf(x) == okey.colorOf(t)) return null;
        }
      }
      return Meld._(kind, [...tiles, t], number, color, owner);
    }
    // seri: 1 yalnızca başta; konumlar 1..13
    if (tiles.length >= GroupRules.maxRun) return null;
    final end = number + tiles.length;
    if (wild) {
      final canEnd = end <= 13;
      final canFront = number > 1;
      if (front == true && canFront) {
        return Meld._(kind, [t, ...tiles], number - 1, color, owner);
      }
      if (canEnd) return Meld._(kind, [...tiles, t], number, color, owner);
      if (canFront) {
        return Meld._(kind, [t, ...tiles], number - 1, color, owner);
      }
      return null;
    }
    if (okey.colorOf(t) != color) return null;
    final n = okey.numberOf(t);
    if (end <= 13 && n == end) {
      return Meld._(kind, [...tiles, t], number, color, owner);
    }
    if (number > 1 && n == number - 1) {
      return Meld._(kind, [t, ...tiles], number - 1, color, owner);
    }
    return null;
  }

  /// Okey çalma: perdeki bir okeyin temsil ettiği gerçek taşı [t] verip okeyi
  /// alır. Seride okeyin durduğu konumdaki taş, kütte perde olmayan bir renkteki
  /// aynı sayılı taş, çiftte ise okeyin eşi olan aynı sayı+renkteki taş uyar.
  /// Olmazsa null.
  JokerSwap? trySwap(Tile t, Okey okey) {
    if (okey.isWild(t)) return null;
    for (var i = 0; i < tiles.length; i++) {
      final j = tiles[i];
      if (!okey.isWild(j)) continue;
      final bool fits;
      if (kind == MeldKind.run) {
        fits = okey.colorOf(t) == color &&
            okey.numberOf(t) == GroupRules.faceOf(number + i);
      } else if (kind == MeldKind.pair) {
        fits = okey.numberOf(t) == number && okey.colorOf(t) == color;
      } else {
        fits = okey.numberOf(t) == number &&
            !tiles.any((x) =>
                !okey.isWild(x) && okey.colorOf(x) == okey.colorOf(t));
      }
      if (!fits) continue;
      final next = List<Tile>.of(tiles);
      next[i] = t;
      return JokerSwap(Meld._(kind, next, number, color, owner), j);
    }
    return null;
  }

  bool accepts(Tile t, Okey okey) => tryAdd(t, okey) != null;
}
