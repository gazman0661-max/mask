import '../models/tile.dart';

/// Istakada tek taş taşıma kuralı: taş bırakılan yuvada başka taş varsa takas
/// YAPILMAZ; komşu taşlar kayıp yer açar, taş araya girer (perin ortasına
/// bile bırakılabilir). Önizleme (sürüklerken) ve gerçek taşıma aynı
/// fonksiyonu kullanır, bu yüzden gördüğün sonuç = olan sonuçtur.
///
/// Kurallar:
/// - Hedef yuva boşsa taş oraya gider.
/// - Aynı satırda: taşın geldiği yuva boşalır; aradaki komşular o boşluğa
///   doğru bir yuva kayar (ilk boş yuvada kayma durur, yani araya giren boşluklar korunur).
/// - Başka satırda: hedef satırda en yakın boş yuva aranır (eşitse sağ),
///   komşular o boşluğa doğru kayar.
/// - Hedef satır tamamen doluysa son çare takas.
class RackShift {
  RackShift._();

  /// [slots] değişmez; yeni dizilim döner. [cols] satır başına yuva sayısı.
  static List<Tile?> move(List<Tile?> slots, int cols, int from, int to) {
    final out = List<Tile?>.of(slots);
    if (from < 0 || to < 0 || from >= out.length || to >= out.length) return out;
    final tile = out[from];
    if (tile == null || from == to) return out;
    if (out[to] == null) {
      out[from] = null;
      out[to] = tile;
      return out;
    }
    out[from] = null;
    final rowStart = (to ~/ cols) * cols;
    final rowEnd = rowStart + cols - 1;
    int gap;
    int dir;
    if (from ~/ cols == to ~/ cols) {
      dir = from > to ? 1 : -1;
      gap = _firstEmpty(out, to, dir, rowStart, rowEnd) ?? from;
    } else {
      final r = _firstEmpty(out, to, 1, rowStart, rowEnd);
      final l = _firstEmpty(out, to, -1, rowStart, rowEnd);
      if (r == null && l == null) {
        out[from] = out[to]; // satır dolu: takas
        out[to] = tile;
        return out;
      }
      if (l == null || (r != null && r - to <= to - l)) {
        dir = 1;
        gap = r!;
      } else {
        dir = -1;
        gap = l;
      }
    }
    for (var k = gap; k != to; k -= dir) {
      out[k] = out[k - dir];
    }
    out[to] = tile;
    return out;
  }

  static int? _firstEmpty(List<Tile?> s, int start, int dir, int lo, int hi) {
    for (var k = start; k >= lo && k <= hi; k += dir) {
      if (s[k] == null) return k;
    }
    return null;
  }
}
