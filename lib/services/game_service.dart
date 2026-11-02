import 'dart:async';
import '../models/player.dart';
import '../models/quick_chat.dart';
import '../models/rewards.dart';
import '../models/table_models.dart';

/// Masaya girilemedi / masa kurulamadı (masa dolu, çip yetmiyor...).
/// [message] kullanıcıya olduğu gibi gösterilir.
class JoinException implements Exception {
  final String message;
  const JoinException(this.message);
  @override
  String toString() => message;
}

/// Arayüzün tek bağımlılığı. Backend (Cloudflare Workers) için
/// bu sınıfı implement eden yeni bir sınıf yazmak yeterli.
abstract class GameService {
  /// Lobi sunucu tarafında değişince tetiklenir. null ise servis bildirim vermez ve
  /// ekran kendi zamanlayıcısıyla yeniler (yalnız sahte servis için).
  Stream<void>? get tablesChanged;

  /// Lobide gösterilecek sunucu uyarısı (kota doldu / bu saatin masa tavanı doldu). Yoksa null.
  String? get lobbyNotice;

  /// Masadaki DİĞER oyuncuların hazır mesajları/emojileri ([ChatEvent.seat] bana göre koltuk: 1 sağ, 2 karşı, 3 sol).
  /// Kendi mesajım buraya düşmez: ekran kendi balonunu hemen gösterir.
  Stream<ChatEvent> get chatEvents;

  /// Hazır mesaj/emoji yollar ([QuickChat.id]). Masada değilsek ya da bekleme süresi dolmadıysa sessizce yok sayılır.
  void sendChat(int id);

  /// Masadaki koltukların "bağlantısı koptu / boşta, yerine bot oynuyor" durumu (her `table`/`state` mesajında).
  /// Sahte servis hiç olay yollamaz.
  Stream<Presence> get presence;

  /// Sunucuyla bağlantı durumu (true = bağlı). Kopunca ekran "bağlanıyor" şeridi gösterir.
  Stream<bool> get connection;

  /// Şu an sunucuya bağlı mıyız? (Sahte servis her zaman true.)
  bool get isConnected;

  /// "OYUNA DÖN": boşta sayılan oyuncu döndüğünü bildirir (`{t:'here'}`); bot bırakır, süre yeniden başlar.
  /// Masada değilsek sessizce yok sayılır.
  void imHere();

  Future<Player> fetchMyProfile();

  /// Günlük ödül durumu (bugün alınabilir mi, kaçıncı gün, ne kadar).
  Future<DailyStatus> fetchDailyStatus();

  /// Günlük ödülü alır. [doubled] true ise 2x (reklam izlendikten SONRA çağrılır). Bugün alınmışsa [JoinException].
  Future<DailyClaim> claimDaily({bool doubled = false});

  /// "Reklam izle çip kazan" durumu: [AdStatus.waitSeconds] 0 ise hazır (15 dakikada bir).
  Future<AdStatus> fetchAdStatus();

  /// Reklam çipini ([kAdChips]) alır; reklam izlendikten SONRA çağrılır. Erken çağrılırsa [JoinException].
  Future<AdStatus> claimAdChips();

  /// Bilet bakiyesi + günlük bilet / reklam bileti durumu.
  Future<TicketStatus> fetchTicketStatus();

  /// Günlük bileti alır ([kDailyTickets], [doubled] ise 2 katı: reklam izlendikten SONRA çağrılır). Bugün alındıysa [JoinException].
  Future<TicketClaim> claimDailyTickets({bool doubled = false});

  /// Masada (oyun sonu skor tablosu) reklam izleyerek +1 bilet; reklam izlendikten SONRA çağrılır. [kAdTicketCooldown] (10 dk)
  /// UYGULANMAZ; yalnız [kTableAdGap] kadar bekleme ve günlük [kTableAdDailyCap] sınırı vardır. Aşılırsa [JoinException].
  Future<TicketClaim> claimTableAdTicket();

  /// Seviye atlama hediyesi: atlanan her seviye için 1 bilet. Bekleyen yoksa [JoinException].
  Future<LevelClaim> claimLevelRewards();

  /// Reklam biletini (+1) alır; reklam izlendikten SONRA çağrılır. Erken ([kAdTicketCooldown]) basılırsa [JoinException].
  Future<TicketClaim> claimAdTicket();

  /// Açık masaların listesi (lobi).
  Future<List<TableInfo>> fetchTables();

  /// Yeni masa kurar (kurucu masaya ayrıca [joinTable] ile oturur).
  /// Yetersiz çipte [JoinException] fırlatır.
  Future<TableInfo> createTable({
    required String name,
    required TableSettings settings,
  });

  /// [tableId] verilirse o masaya, null ise "Hemen Oyna" (otomatik eşleştirme,
  /// [quick] ayarlarına uygun masa). Başarısızlıkta [JoinException].
  Future<TableSnapshot> joinTable({
    String? tableId,
    TableSettings? quick,
  });

  /// Geri sayım bitince oyun BAŞLARKEN çağrılır: 1 bilet burada düşer (masaya oturmak/masa kurmak bilet düşürmez,
  /// yalnız en az 1 bilet ister). Bileti yoksa [JoinException]. Gerçek sunucuda bilet `start_match` içinde düştüğü
  /// için Cloudflare servisinde yapılacak iş yoktur.
  Future<void> beginMatch();

  /// Oturduğum masanın değişen durumu: biri oturdu/kalktı, geri sayım başladı/iptal oldu ([TableSnapshot.emptySeats],
  /// [TableSnapshot.startsInMs]). Masada değilsek olay gelmez.
  Stream<TableSnapshot> get tableUpdates;

  /// Maç bitti, aynı masada yeni oyun: masada kalır (botlar da kalır, kalkan insanların yerine yeni oyuncu/bot gelir).
  /// Yeni oyun için en az 1 bilet gerekir (bilet oyun başlarken düşer). Masa artık yoksa ya da bilet yoksa [JoinException].
  Future<TableSnapshot> stayAtTable();

  /// Masadan kalkar. Oyun başlamadıysa bedava; maç sürüyorsa bilet yanar (ekran önce onay alır).
  void leaveTable();
}
