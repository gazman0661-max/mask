import '../models/tile.dart';

/// Gösterge taşından okey (joker) taşını türetir.
/// Okey = göstergenin bir fazlası, aynı renk (13'ün fazlası 1).
/// - Gerçek okey taşı: JOKER (her taşın yerine geçer)
/// - Sahte okey: okeyin kendi sayı/rengindeki sıradan taş gibi davranır
class Okey {
  final int number;
  final TileColor color;
  const Okey(this.number, this.color);

  factory Okey.fromIndicator(Tile i) =>
      Okey(i.number == 13 ? 1 : i.number + 1, i.color);

  bool isWild(Tile t) =>
      !t.isFakeJoker && t.number == number && t.color == color;
  int numberOf(Tile t) => t.isFakeJoker ? number : t.number;
  TileColor colorOf(Tile t) => t.isFakeJoker ? color : t.color;
}

/// 101 Okey per kuralları:
/// - Küt: aynı sayı, FARKLI renkler, 3 veya 4 taş.
/// - Seri (el): aynı renk, ardışık sayılar, en az 3 taş.
///   1 SADECE en küçük taştır (1-2-3 geçerli).
///   12-13-1 ve 13-1-2 GEÇERSİZDİR.
/// - Joker (okey) eksik taşın yerine geçer ve temsil ettiği taşın puanını taşır.
/// Elde kalan taşın ceza değeri: okey 101, sahte okey okeyin sayısı, diğerleri yüz değeri.
int tileValue(Tile t, Okey okey) => okey.isWild(t) ? 101 : okey.numberOf(t);

class GroupRules {
  static const int minGroup = 3;
  static const int maxSet = 4;
  static const int maxRun = 13;

  /// Yan yana dizilmiş taşlar geçerli bir per ise puanı, değilse 0.
  static int valueOf(List<Tile> g, Okey okey) {
    final len = g.length;
    if (len < minGroup) return 0;
    final real = <MapEntry<int, Tile>>[];
    for (var i = 0; i < len; i++) {
      if (!okey.isWild(g[i])) real.add(MapEntry(i, g[i]));
    }
    if (real.isEmpty) return 0;

    // Küt: aynı sayı, farklı renk. Okeylerle hem küt hem seri olabilen gruplarda
    // (Meld.fromGroup gibi) yüksek olan sayılır.
    var setValue = 0;
    if (len <= maxSet) {
      final n = okey.numberOf(real.first.value);
      final colors = real.map((e) => okey.colorOf(e.value)).toSet();
      if (real.every((e) => okey.numberOf(e.value) == n) &&
          colors.length == real.length) {
        setValue = n * len;
      }
    }

    // Seri: aynı renk, ardışık; 1 yalnızca başta (1-2-3...).
    final start = runStart(g, okey);
    if (start == null) return setValue;
    var sum = 0;
    for (var j = 0; j < len; j++) {
      sum += faceOf(start + j);
    }
    return sum > setValue ? sum : setValue;
  }

  /// Seri konumu -> taşın yüzündeki sayı (konumlar 1..13, sayıyla aynı).
  static int faceOf(int pos) => pos;

  /// Dizilimin geçerli bir seri olarak başladığı sayı (1..11); seri değilse
  /// null. Okey boşlukları doldurur. 13'ü aşan dizilimler (12-13-1) geçersizdir.
  static int? runStart(List<Tile> g, Okey okey) {
    final len = g.length;
    if (len < minGroup || len > maxRun) return null;
    var first = -1;
    for (var i = 0; i < len; i++) {
      if (!okey.isWild(g[i])) {
        first = i;
        break;
      }
    }
    if (first < 0) return null;
    final c = okey.colorOf(g[first]);
    final n0 = okey.numberOf(g[first]);
    for (final p in [n0]) {
      final start = p - first;
      if (start < 1 || start + len - 1 > 13) continue;
      var ok = true;
      for (var i = 0; i < len && ok; i++) {
        if (okey.isWild(g[i])) continue;
        if (okey.colorOf(g[i]) != c || okey.numberOf(g[i]) != faceOf(start + i)) {
          ok = false;
        }
      }
      if (ok) return start;
    }
    return null;
  }
}
