import '../models/tile.dart';
import 'meld.dart';
import 'okey_rules.dart';

class HandScorer {
  /// Gruplar boş yuva ile ayrılır, satır sınırını geçmez.
  static List<List<Tile>> segments(List<Tile?> slots, int columns) {
    final out = <List<Tile>>[];
    for (var start = 0; start < slots.length; start += columns) {
      var run = <Tile>[];
      for (final t in [...slots.sublist(start, start + columns), null]) {
        if (t != null) {
          run.add(t);
        } else {
          if (run.isNotEmpty) out.add(run);
          run = <Tile>[];
        }
      }
    }
    return out;
  }

  /// Istakada yan yana duran geçerli seri/küt grupları.
  static List<List<Tile>> validSeries(
          List<Tile?> slots, int columns, Okey okey) =>
      segments(slots, columns)
          .where((g) => GroupRules.valueOf(g, okey) > 0)
          .toList();

  /// Istakada yan yana duran geçerli çiftler.
  static List<List<Tile>> validPairs(
          List<Tile?> slots, int columns, Okey okey) =>
      segments(slots, columns)
          .where((g) => g.length == 2 && Meld.pairFrom(g, okey, 0) != null)
          .toList();

  /// Geçerli perlerin toplam puanı (101 barajı için).
  static int score(List<Tile?> slots, int columns, Okey okey) =>
      validSeries(slots, columns, okey)
          .fold<int>(0, (s, g) => s + GroupRules.valueOf(g, okey));

  /// Yan yana duran GEÇERLİ çift sayısı (çift açmak için 5 gerekir).
  static int pairCount(List<Tile?> slots, int columns, Okey okey) =>
      validPairs(slots, columns, okey).length;
}
