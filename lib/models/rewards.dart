/// Günlük ödül tablosu (7 günlük seri): 1. gün 2000 ... 7. gün 4000. 7. güne ulaşan, her gün girmeye devam ettikçe 7. gün ödülünü sabit alır; yalnız gün atlarsa 1. güne döner.
/// Sunucudaki `_daily_amount` (migration-006.sql) ile AYNI olmalı.
const List<int> kDailyRewards = [2000, 2250, 2500, 2750, 3000, 3500, 4000];

/// "Reklam izle çip kazan" ödülü ve bekleme süresi (sunucudaki `claim_ad_chips` ile aynı).
const int kAdChips = 4000;
const Duration kAdCooldown = Duration(minutes: 15);

/// [day] 1-7 arası gün numarasının ödülü.
int dailyAmount(int day) => kDailyRewards[(day - 1).clamp(0, 6).toInt()];

/// Bir sonraki günün numarası (7. günde kalır, başa dönmez; başa dönüş yalnız gün atlayınca olur).
int nextDay(int day) => day >= 7 ? 7 : day + 1;

/// Bugünkü günlük ödülün durumu.
class DailyStatus {
  /// Bugün alınabilir mi?
  final bool canClaim;

  /// Alınacak (ya da bugün alınmış) günün numarası, 1-7.
  final int day;

  /// O günün ödülü (2x değil).
  final int amount;
  const DailyStatus({required this.canClaim, required this.day, required this.amount});

  factory DailyStatus.fromJson(Map<String, dynamic> j) => DailyStatus(
        canClaim: j['can_claim'] as bool,
        day: (j['day'] as num).toInt(),
        amount: (j['amount'] as num).toInt(),
      );
}

/// Alınan günlük ödülün sonucu.
class DailyClaim {
  final int day;

  /// Hesaba geçen çip (2x seçildiyse ikiye katlanmış hali).
  final int amount;

  /// Ödülden sonraki çip bakiyesi.
  final int chips;
  const DailyClaim({required this.day, required this.amount, required this.chips});

  factory DailyClaim.fromJson(Map<String, dynamic> j) => DailyClaim(
        day: (j['day'] as num).toInt(),
        amount: (j['amount'] as num).toInt(),
        chips: (j['chips'] as num).toInt(),
      );
}

/// "Reklam izle çip kazan" durumu: [waitSeconds] 0 ise hazır.
class AdStatus {
  final int amount;
  final int waitSeconds;
  const AdStatus({required this.amount, required this.waitSeconds});

  factory AdStatus.fromJson(Map<String, dynamic> j) => AdStatus(
        amount: (j['amount'] as num).toInt(),
        waitSeconds: (j['wait_seconds'] as num).toInt(),
      );
}

// ---------------------------------------------------------------- ÇİP SİSTEMİ (migration-017.sql)
// Giriş çipi oyun BAŞLARKEN düşer, havuz (giriş x 4) kazanana gider, KOMİSYON YOK. Lig puanı + XP ayrıca yazılır.

/// Seviye atlama hediyesi: atlanan her seviye için bu kadar çip. Sunucudaki `claim_level_rewards` ile AYNI.
const int kLevelUpChips = 2000;

/// Oyun sonunda çipi biten oyuncuya REKLAM İZLE / LOBİYE DÖN seçeneği için bekleme (sn). Süre dolunca lobiye alınır
/// (çip/puan kaybı yok). Reklam izlenirken sayaç durur. Reklam, anasayfadaki reklam çipiyle ([kAdChips], 15 dk) AYNI sayaçtır.
const int kNoChipWaitSeconds = 15;

/// Seviye eğrisi: L'den L+1'e geçmek için 100 × L XP. Seviye L'ye ulaşmak için TOPLAM 50 × L × (L-1) XP.
/// Sunucudaki `_xp_for_level` / `_level_of` (migration-009.sql) ile AYNI olmalı. Seviye XP'den hesaplanır, hiç düşmez.
int xpForLevel(int level) => 50 * (level < 1 ? 1 : level) * ((level < 1 ? 1 : level) - 1);

/// [xp] için seviye (en az 1).
int levelOfXp(int xp) {
  var l = 1;
  while (xp >= xpForLevel(l + 1)) {
    l++;
  }
  return l;
}

/// Çip bakiyesi + seviye/XP durumu (`chip_status`).
class ChipStatus {
  final int chips;
  final int xp;
  final int leaguePoints;

  /// Şimdiki seviye ve hediyesi alınmış en yüksek seviye (fark = bekleyen seviye hediyesi sayısı).
  final int level;
  final int levelClaimed;
  const ChipStatus({
    required this.chips,
    this.xp = 0,
    this.leaguePoints = 0,
    this.level = 1,
    this.levelClaimed = 1,
  });

  /// Seviye atlama hediyesi: alınmamış her seviye [kLevelUpChips] çip.
  int get pendingLevels => level > levelClaimed ? level - levelClaimed : 0;

  /// Bu seviyedeki ilerleme, 0..1 (ilerleme çubuğu).
  double get levelProgress {
    final start = xpForLevel(level), next = xpForLevel(level + 1);
    return ((xp - start) / (next - start)).clamp(0.0, 1.0).toDouble();
  }

  factory ChipStatus.fromJson(Map<String, dynamic> j) => ChipStatus(
        chips: (j['chips'] as num).toInt(),
        xp: (j['xp'] as num?)?.toInt() ?? 0,
        leaguePoints: (j['league_points'] as num?)?.toInt() ?? 0,
        level: (j['level'] as num?)?.toInt() ?? levelOfXp((j['xp'] as num?)?.toInt() ?? 0),
        levelClaimed: (j['level_claimed'] as num?)?.toInt() ?? 1,
      );
}

/// Seviye hediyesinin sonucu: [amount] çip eklendi, [chips] yeni bakiye, [level] şimdiki seviye.
class LevelClaim {
  final int amount;
  final int chips;
  final int level;
  const LevelClaim({required this.amount, required this.chips, required this.level});

  factory LevelClaim.fromJson(Map<String, dynamic> j) => LevelClaim(
        amount: (j['amount'] as num).toInt(),
        chips: (j['chips'] as num).toInt(),
        level: (j['level'] as num).toInt(),
      );
}
