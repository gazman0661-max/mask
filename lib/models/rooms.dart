/// Kademeli odalar. Sunucudaki `_room_def` (migration-017.sql) ve Worker `src/rooms.ts` ile AYNI olmalı: üç yeri birlikte değiştir.
/// Masayı kuran GİRİŞ BAHSİNİ odanın [minBet]-[maxBet] aralığında kendisi belirler (kaydırıcı ya da elle yazma).
/// Oturmak için gereken çip = masanın bahsi x [mult]. Havuz = bahis x 4. KOMİSYON YOK. Giriş çipi maç başlarken düşer.
/// Asıl denetimi SUNUCU yapar ([checkRoom] yalnız ekranda butonu/uyarıyı önceden göstermek içindir).
class Room {
  final int id;
  final String name;
  final String emoji;

  /// En düşük / en yüksek giriş bahsi (çip).
  final int minBet;
  final int maxBet;

  /// Oturmak için gereken çip = bahis x [mult].
  final int mult;

  /// Oturmak için en az seviye.
  final int minLevel;

  /// Acemi koruması: çipin bunu aşıyorsa (ve girebileceğin daha üst bir oda varsa) bu odaya oturamazsın. null = tavan yok.
  final int? maxChips;
  const Room(this.id, this.name, this.emoji, this.minBet, this.maxBet, this.mult, this.minLevel, this.maxChips);

  /// [bet] bahisli masaya oturmak için gereken çip.
  int chipsFor(int bet) => bet * mult;

  /// En ucuz masaya (en düşük bahis) oturmak için gereken çip.
  int get minChips => chipsFor(minBet);

  bool hasBet(int bet) => bet >= minBet && bet <= maxBet;

  int clampBet(int bet) => bet < minBet ? minBet : (bet > maxBet ? maxBet : bet);

  /// Kaydırıcının adımı (elle yazmada adım yok, her tamsayı geçerli).
  int get betStep => maxBet < 10000 ? 50 : (maxBet < 100000 ? 500 : 5000);

  /// Kaydırıcı değerini adıma yuvarlar; uçlar tam [minBet] ve [maxBet] olur.
  int snapBet(double v) {
    final s = betStep;
    if (v <= minBet + s / 2) return minBet;
    if (v >= maxBet - s / 2) return maxBet;
    return clampBet((v / s).round() * s);
  }
}

const List<Room> kRooms = [
  Room(1, 'Çay Bahçesi', '🍵', 2000, 4999, 1, 1, 60000),
  Room(2, 'Kıraathane', '📜', 5000, 9999, 1, 3, 200000),
  Room(3, 'Mahalle Kahvesi', '☕', 10000, 24999, 1, 6, 600000),
  Room(4, 'Meydan', '⛲', 25000, 49999, 1, 10, 2000000),
  Room(5, 'Yalı', '🌊', 50000, 99999, 1, 15, 5000000),
  Room(6, 'Konak', '🏛️', 100000, 249999, 1, 22, 12000000),
  Room(7, 'Saray', '👑', 250000, 1000000, 1, 30, null),
];

const int kDefaultRoom = 1;

/// Yeni hesabın başlangıç çipi (sunucu: profiles.chips default 7500).
const int kStartChips = 7500;

/// [id] numaralı oda; geçersizse ilk oda.
Room roomById(int id) => kRooms.firstWhere((r) => r.id == id, orElse: () => kRooms.first);

enum RoomCheck {
  ok,

  /// Çipin odanın en az çipinden az.
  tooFewChips,

  /// Seviyen odanın en az seviyesinden düşük.
  tooLowLevel,

  /// Çipin odanın tavanını aşıyor ve girebileceğin daha üst bir oda var.
  tooManyChips,
}

/// Sunucudaki `can_sit` ile AYNI sıra ve mantık: önce çip (bahis x çarpan; [bet] yoksa en düşük bahis), sonra seviye, sonra tavan.
/// Tavan yalnız oyuncunun (çip + seviye olarak) girebildiği DAHA ÜST bir oda varsa uygulanır; yoksa boşluk kalmasın diye uygulanmaz.
RoomCheck checkRoom(Room r, {required int chips, required int level, int? bet}) {
  if (chips < r.chipsFor(bet ?? r.minBet)) return RoomCheck.tooFewChips;
  if (level < r.minLevel) return RoomCheck.tooLowLevel;
  final cap = r.maxChips;
  if (cap != null && chips > cap) {
    final hasHigher = kRooms.any((x) => x.id > r.id && x.minLevel <= level && x.minChips <= chips); // üst odanın en ucuz masası
    if (hasHigher) return RoomCheck.tooManyChips;
  }
  return RoomCheck.ok;
}

/// "Hemen Oyna" için çipine ve seviyene uygun EN YÜKSEK oda; hiçbirine giremiyorsa null.
Room? bestRoom({required int chips, required int level}) {
  for (final r in kRooms.reversed) {
    if (checkRoom(r, chips: chips, level: level) == RoomCheck.ok) return r;
  }
  return null;
}

/// Odaya girilemiyorsa kullanıcıya gösterilecek kısa neden (girilebiliyorsa null).
String? roomBlockReason(Room r, {required int chips, required int level, int? bet}) => switch (checkRoom(r, chips: chips, level: level, bet: bet)) {
      RoomCheck.ok => null,
      RoomCheck.tooFewChips => 'En az ${_n(r.chipsFor(bet ?? r.minBet))} çip gerekir',
      RoomCheck.tooLowLevel => 'En az seviye ${r.minLevel} gerekir',
      RoomCheck.tooManyChips => 'Çipin bu oda için fazla, üst odalara geç',
    };

/// 1234567 -> 1.234.567
String _n(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}
