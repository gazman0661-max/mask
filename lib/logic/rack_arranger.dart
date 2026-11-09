import '../models/tile.dart';
import 'okey_rules.dart';

class SeriResult {
  final List<List<Tile>> groups;
  final List<Tile> leftover;
  final int value;
  const SeriResult(this.groups, this.leftover, this.value);
}

class PairResult {
  final List<List<Tile>> pairs;
  final List<Tile> leftover;
  const PairResult(this.pairs, this.leftover);
}

class _Ch {
  final int kind; // 0 atla, 1 seri, 2 küt
  final int c, n, len, wilds, start;
  final List<int> others;
  const _Ch(this.kind, this.c, this.n,
      {this.len = 0, this.start = 0, this.wilds = 0, this.others = const []});
}

class _St {
  final List<int> cnt;
  final int w, value;
  _St(this.cnt, this.w, this.value);
}

/// Sayaç dizisi: index = renk*15 + sayı (1..13). 1 yalnızca başta olabilir.
class _Solver {
  final memo = <String, int>{};
  final choice = <String, _Ch>{};

  static String key(List<int> cnt, int w) => '${cnt.join(",")}|$w';

  static int? pivot(List<int> cnt) {
    for (var n = 1; n <= 13; n++) {
      for (var c = 0; c < 4; c++) {
        if (cnt[c * 15 + n] > 0) return c * 15 + n;
      }
    }
    return null;
  }

  static _St? apply(List<int> cnt, int w, _Ch ch) {
    final x = List<int>.of(cnt);
    var value = 0;
    if (ch.kind == 0) {
      x[ch.c * 15 + ch.n]--;
    } else if (ch.kind == 1) {
      for (var p = ch.start; p < ch.start + ch.len; p++) {
        final f = GroupRules.faceOf(p);
        final i = ch.c * 15 + f;
        if (x[i] > 0) {
          x[i]--;
        } else if (w > 0) {
          w--;
        } else {
          return null;
        }
        value += f;
      }
    } else {
      x[ch.c * 15 + ch.n]--;
      for (final d in ch.others) {
        if (x[d * 15 + ch.n] <= 0) return null;
        x[d * 15 + ch.n]--;
      }
      if (w < ch.wilds) return null;
      w -= ch.wilds;
      value = ch.n * (1 + ch.others.length + ch.wilds);
    }
    return _St(x, w, value);
  }

  static List<_Ch> candidates(int c, int n, List<int> cnt) {
    final out = <_Ch>[_Ch(0, c, n)];
    // Seri pivot taşı içerir; pivottan önceki boşlukları joker doldurabilir.
    for (var st = (n - 2 < 1 ? 1 : n - 2); st <= n; st++) {
      for (var len = 3; st + len - 1 <= 13; len++) {
        if (st + len - 1 < n) continue;
        out.add(_Ch(1, c, n, len: len, start: st));
      }
    }
    final avail = [
      for (var d = 0; d < 4; d++)
        if (d != c && cnt[d * 15 + n] > 0) d
    ];
    for (var mask = 0; mask < (1 << avail.length); mask++) {
      final s = [
        for (var i = 0; i < avail.length; i++)
          if (mask & (1 << i) != 0) avail[i]
      ];
      for (final size in [3, 4]) {
        final need = size - 1 - s.length;
        if (need < 0 || need > 2) continue;
        out.add(_Ch(2, c, n, wilds: need, others: s));
      }
    }
    return out;
  }

  int solve(List<int> cnt, int w) {
    final k = key(cnt, w);
    final m = memo[k];
    if (m != null) return m;
    final p = pivot(cnt);
    if (p == null) return memo[k] = 0;
    final c = p ~/ 15, n = p % 15;
    var best = -1;
    _Ch? bc;
    for (final ch in candidates(c, n, cnt)) {
      final r = apply(cnt, w, ch);
      if (r == null) continue;
      final v = r.value + solve(r.cnt, r.w);
      if (v > best) {
        best = v;
        bc = ch;
      }
    }
    choice[k] = bc!;
    return memo[k] = best;
  }
}

/// "Seri diz" / "Çift diz" mantığı. Gerçek per kurallarına göre en yüksek
/// puanlı düzeni bulur; perleri boşlukla ayırıp ıstakaya yerleştirir.
class RackArranger {
  /// Verilen taşlardan en yüksek puanlı küt/seri düzenini çıkarır.
  static SeriResult solveSeri(List<Tile> tiles, Okey okey) {
    final stacks = List.generate(60, (_) => <Tile>[]);
    final wilds = <Tile>[];
    for (final t in tiles) {
      if (okey.isWild(t)) {
        wilds.add(t);
      } else {
        stacks[okey.colorOf(t).index * 15 + okey.numberOf(t)].add(t);
      }
    }
    var cnt = stacks.map((s) => s.length).toList();
    var w = wilds.length;
    final solver = _Solver()..solve(cnt, w);

    final groups = <List<Tile>>[];
    final leftover = <Tile>[];
    while (true) {
      final p = _Solver.pivot(cnt);
      if (p == null) break;
      final ch = solver.choice[_Solver.key(cnt, w)]!;
      if (ch.kind == 0) {
        leftover.add(stacks[ch.c * 15 + ch.n].removeLast());
      } else if (ch.kind == 1) {
        final g = <Tile>[];
        for (var q = ch.start; q < ch.start + ch.len; q++) {
          final s = stacks[ch.c * 15 + GroupRules.faceOf(q)];
          g.add(s.isNotEmpty ? s.removeLast() : wilds.removeLast());
        }
        groups.add(g);
      } else {
        final g = <Tile>[stacks[ch.c * 15 + ch.n].removeLast()];
        for (final d in ch.others) {
          g.add(stacks[d * 15 + ch.n].removeLast());
        }
        for (var i = 0; i < ch.wilds; i++) {
          g.add(wilds.removeLast());
        }
        groups.add(g);
      }
      final r = _Solver.apply(cnt, w, ch)!;
      cnt = r.cnt;
      w = r.w;
    }
    for (final s in stacks) {
      leftover.addAll(s);
    }
    leftover.sort((a, b) {
      final d = okey.numberOf(a).compareTo(okey.numberOf(b));
      return d != 0 ? d : okey.colorOf(a).index.compareTo(okey.colorOf(b).index);
    });
    leftover.addAll(wilds);
    final value =
        groups.fold<int>(0, (s, g) => s + GroupRules.valueOf(g, okey));
    return SeriResult(groups, leftover, value);
  }

  /// Aynı taşlardan çiftler (okey, tek kalanla çift olur); tekler artan.
  static PairResult solvePairs(List<Tile> tiles, Okey okey) {
    final byKey = <String, List<Tile>>{};
    final wilds = <Tile>[];
    for (final t in tiles) {
      if (okey.isWild(t)) {
        wilds.add(t);
      } else {
        byKey
            .putIfAbsent('${okey.numberOf(t)}-${okey.colorOf(t).index}', () => [])
            .add(t);
      }
    }
    final pairs = <List<Tile>>[];
    final singles = <Tile>[];
    for (final l in byKey.values) {
      while (l.length >= 2) {
        pairs.add([l.removeLast(), l.removeLast()]);
      }
      singles.addAll(l);
    }
    singles.sort((a, b) => okey.numberOf(b).compareTo(okey.numberOf(a)));
    while (wilds.isNotEmpty && singles.isNotEmpty) {
      pairs.add([singles.removeAt(0), wilds.removeLast()]);
    }
    while (wilds.length >= 2) {
      pairs.add([wilds.removeLast(), wilds.removeLast()]);
    }
    pairs.sort((a, b) => okey.numberOf(a.first).compareTo(okey.numberOf(b.first)));
    final leftover = singles.reversed.toList()..addAll(wilds);
    return PairResult(pairs, leftover);
  }

  static List<Tile?> seriDiz(List<Tile?> slots, int columns, Okey okey) {
    final r = solveSeri(slots.whereType<Tile>().toList(), okey);
    return _layout(r.groups, r.leftover, slots.length, columns);
  }

  static List<Tile?> ciftDiz(List<Tile?> slots, int columns, Okey okey) {
    final r = solvePairs(slots.whereType<Tile>().toList(), okey);
    return _layout(r.pairs, r.leftover, slots.length, columns);
  }

  /// Gruplar bir satırda yan yana (aralarında 1 boş yuva) durur, satırı aşmaz.
  /// Artan tekler gruplardan 1 boşlukla ayrılarak satır sonlarına dizilir.
  static List<Tile?> _layout(
      List<List<Tile>> groups, List<Tile> leftover, int total, int columns) {
    final rows = total ~/ columns;
    final out = List<Tile?>.filled(total, null);
    final used = List<int>.filled(rows, 0);
    final rest = <Tile>[...leftover];
    final sorted = [...groups]..sort((a, b) => b.length.compareTo(a.length));
    for (final g in sorted) {
      var placed = false;
      for (var r = 0; r < rows && !placed; r++) {
        final start = used[r] == 0 ? 0 : used[r] + 1;
        if (start + g.length <= columns) {
          for (var i = 0; i < g.length; i++) {
            out[r * columns + start + i] = g[i];
          }
          used[r] = start + g.length;
          placed = true;
        }
      }
      if (!placed) rest.addAll(g);
    }
    for (var r = 0; r < rows && rest.isNotEmpty; r++) {
      final start = used[r] == 0 ? 0 : used[r] + 1;
      for (var i = start; i < columns && rest.isNotEmpty; i++) {
        out[r * columns + i] = rest.removeAt(0);
      }
    }
    for (var i = 0; i < total && rest.isNotEmpty; i++) {
      if (out[i] == null) out[i] = rest.removeAt(0);
    }
    return out;
  }
}
