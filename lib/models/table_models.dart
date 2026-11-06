import 'player.dart';
import 'tile.dart';

/// Masadaki 4 koltuk. Sıra: sol -> ben -> sağ -> üst -> sol
enum Seat { me, right, top, left }

/// Masa kuralı etiketi (Tek, Yardımlı, Katlamasız, 1 El ...)
class RuleChip {
  final String label;
  final bool on;
  const RuleChip(this.label, {this.on = false});
}

/// Bir masanın ayarları. Backend'e JSON olarak gider/gelir.
/// Masa dolunca "OYUN BAŞLIYOR" geri sayımı (sn). Sunucudaki `START_COUNTDOWN_MS` (8000) ile aynı.
/// Biri kalkıp yerine başkası oturursa SIFIRDAN başlar; bilet bu süre bitince (oyun başlarken) düşer.
const int kStartCountdownSeconds = 8;

/// Masaya oturunca ilk botun gelmesi (sn) ve sonraki botlar arası (sn). Sunucudaki FIRST_BOT_MS (12000) / NEXT_BOT_MS (3500) ile aynı;
/// yalnız sahte servis kullanır (gerçek sunucuda bot oturuşunu sunucu yollar).
const Duration kFirstBotDelay = Duration(seconds: 12);
const Duration kNextBotDelay = Duration(milliseconds: 3500);

class TableSettings {
  /// Eşli (2'ye 2) oyun: karşılıklı oturanlar takım olur, puan takım toplamıdır.
  final bool team;

  /// Katlamalı: açış barajı artar (biri 110 ile açtıysa sonraki seri açış
  /// en az 111 olmalı). Katlamasızda baraj hep 101'dir. Okeyle/çiftle/elden
  /// bitirme puanı her masada katlanır.
  final bool folding;

  /// Yardımlı: puan balonu ve işlenebilir per vurgusu açık.
  final bool assisted;

  /// Turbo: tur süresi 15 sn (normal 30 sn).
  final bool turbo;

  /// Kaç el oynanacak (1, 3, 5, 7).
  final int hands;

  const TableSettings({
    this.team = false,
    this.folding = true,
    this.assisted = true,
    this.turbo = false,
    this.hands = 1,
  });

  int get turnSeconds => turbo ? 15 : 30;
  List<RuleChip> get chips => [
        RuleChip(team ? 'Eşli' : 'Tek'),
        RuleChip(assisted ? 'Yardımlı' : 'Yardımsız', on: assisted),
        RuleChip(folding ? 'Katlamalı' : 'Katlamasız', on: folding),
        RuleChip('$hands El', on: true),
        if (turbo) const RuleChip('Hızlı', on: true),
      ];

  TableSettings copyWith(
          {bool? team,
          bool? folding,
          bool? assisted,
          bool? turbo,
          int? hands}) =>
      TableSettings(
        team: team ?? this.team,
        folding: folding ?? this.folding,
        assisted: assisted ?? this.assisted,
        turbo: turbo ?? this.turbo,
        hands: hands ?? this.hands,
      );

  Map<String, dynamic> toJson() => {
        'team': team,
        'folding': folding,
        'assisted': assisted,
        'turbo': turbo,
        'hands': hands,
      };

  factory TableSettings.fromJson(Map<String, dynamic> j) => TableSettings(
        team: (j['team'] ?? false) as bool,
        folding: (j['folding'] ?? true) as bool,
        assisted: (j['assisted'] ?? true) as bool,
        turbo: (j['turbo'] ?? false) as bool,
        hands: (j['hands'] ?? 1) as int,
      );
}

/// Oda listesindeki bir masa.
class TableInfo {
  final String id;
  final String name;
  final String hostName;
  final TableSettings settings;
  final int playerCount; // 0..4

  /// Koltuk sırası: üst (masa sahibi), alt, sol, sağ. Eksikse "Oyuncu" yazılır.
  final List<String> seatNames;

  const TableInfo({
    required this.id,
    required this.name,
    required this.hostName,
    required this.settings,
    required this.playerCount,
    this.seatNames = const [],
  });

  bool get isFull => playerCount >= 4;

  factory TableInfo.fromJson(Map<String, dynamic> j) => TableInfo(
        id: j['id'] as String,
        name: j['name'] as String,
        hostName: (j['hostName'] ?? '') as String,
        settings:
            TableSettings.fromJson(j['settings'] as Map<String, dynamic>),
        playerCount: j['playerCount'] as int,
        seatNames: ((j['seatNames'] ?? const []) as List).cast<String>(),
      );
}

/// Bir masaya girildiğinde arayüzün ihtiyaç duyduğu tüm veri.
class TableSnapshot {
  final String tableId;
  final TableSettings settings;
  final Player me;
  final Player left;
  final Player top;
  final Player right;

  /// 32 yuvalık ıstaka (2 satır x 16). Boş yuva = null.
  final List<Tile?> rack;
  final Tile indicator; // gösterge taşı
  final int deckCount;

  /// Her oyuncunun attığı son taş (yığının en üstü).
  final Map<Seat, Tile?> discards;

  /// Masaya açılmış perler.
  final List<List<Tile>> openedMelds;

  /// Masadaki taşı kimin koyduğu: taş id → koltuk sırası (0 ben, 1 sağ, 2 karşı, 3 sol).
  /// Başkasının perine işleyen oyuncunun uçuş animasyonu için (sunucu `layers`).
  final Map<int, int> meldLayers;
  final Seat activeSeat;

  /// Henüz kimsenin oturmadığı koltuklar (oyuncu bekleniyor). Hepsi doluysa boş.
  final Set<Seat> emptySeats;

  /// Sunucu geri sayımın kaç ms'sinin kaldığını yolladıysa (`table.startsIn`), yoksa 0 (yerel geri sayım [kStartCountdownSeconds]).
  final int startsInMs;

  const TableSnapshot({
    required this.tableId,
    required this.settings,
    required this.me,
    required this.left,
    required this.top,
    required this.right,
    required this.rack,
    required this.indicator,
    required this.deckCount,
    required this.discards,
    required this.openedMelds,
    this.meldLayers = const <int, int>{},
    required this.activeSeat,
    this.emptySeats = const <Seat>{},
    this.startsInMs = 0,
  });

  /// Dört koltuk da dolu mu? (dolunca geri sayım başlar)
  bool get isSeated => emptySeats.isEmpty;

  List<RuleChip> get rules => settings.chips;
  int get turnSeconds => settings.turnSeconds;
}

/// Masadaki koltukların "yerine bot oynuyor" durumu; sıra [Seat] sırasıyla (ben, sağ, karşı, sol).
/// [away]: bağlantısı koptu ya da boşta. [afk]: away içinde, bağlantı kopmadı, oyuncu boşta.
/// Sunucu: `state.table.away` / `state.table.afk` (koltuk sırası sunucudadır, burada bana göre çevrilmiş halidir).
class Presence {
  final List<bool> away;
  final List<bool> afk;
  const Presence({
    this.away = const [false, false, false, false],
    this.afk = const [false, false, false, false],
  });

  static const Presence none = Presence();

  bool isAway(Seat s) => s.index < away.length && away[s.index];
  bool isAfk(Seat s) => s.index < afk.length && afk[s.index];
}
