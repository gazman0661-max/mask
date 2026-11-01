enum TileColor { yellow, blue, black, red }

class Tile {
  final int id;
  final int number; // 1..13 (sahte okeyde anlamsız, 0)
  final TileColor color;
  final bool isFakeJoker;

  const Tile({
    required this.id,
    required this.number,
    required this.color,
    this.isFakeJoker = false,
  });

  /// Sahte okey: okey taşının kendi yerine geçen, sayısız taş.
  const Tile.fake(int id)
      : this(id: id, number: 0, color: TileColor.red, isFakeJoker: true);

  // Backend JSON'u geldiğinde kullanılacak.
  factory Tile.fromJson(Map<String, dynamic> j) => Tile(
        id: j['id'] as int,
        number: j['number'] as int,
        color: TileColor.values.byName(j['color'] as String),
        isFakeJoker: (j['fakeJoker'] ?? false) as bool,
      );
}
