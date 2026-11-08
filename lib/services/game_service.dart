import '../models/goals.dart';
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

  /// Reklam çipini ([kAdChips], 15 dk'da bir) alır; reklam izlendikten SONRA çağrılır. Oyun sonu "çipin bitti" reklamı da bunu kullanır. Erken çağrılırsa [JoinException].
  Future<AdStatus> claimAdChips();

  /// Çip bakiyesi + seviye/XP durumu.
  Future<ChipStatus> fetchChipStatus();

  /// Seviye atlama hediyesi: atlanan her seviye için [kLevelUpChips] çip. Bekleyen yoksa [JoinException].
  Future<LevelClaim> claimLevelRewards();

  /// Günlük görevlerin bugünkü ilerlemesi (sunucu hesaplar, Türkiye günü).
  Future<TasksStatus> fetchTasks();

  /// Biten günlük görevin ödülünü (çip) alır. Bitmediyse / alındıysa [JoinException].
  Future<GoalClaim> claimTask(String taskId);

  /// Başarım ilerlemesi (oynanan/kazanılan maç, XP) ve alınan kademeler.
  Future<AchStatus> fetchAchievements();

  /// Başarım kademesinin ödülünü (çip) alır; kademeler sırayla alınır. Olmazsa [JoinException].
  Future<GoalClaim> claimAchievement(String id, int tier);

  /// Bu haftanın lig sıralaması (en çok [limit] kişi, puanı olanlar).
  Future<List<LeagueRow>> fetchLeague({int limit = 50});

  /// Benim kullanıcı kimliğim (sıralamada kendimi işaretlemek için); bilinmiyorsa null.
  String? get myUserId;

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

  /// Geri sayım bitince oyun BAŞLARKEN çağrılır: giriş çipi burada düşer (masaya oturmak/masa kurmak çip düşürmez,
  /// yalnız oda şartını ister: min çip, min seviye, çip tavanı). Çipi yetmiyorsa [JoinException]. Gerçek sunucuda çip
  /// `start_match` içinde düştüğü için Cloudflare servisinde yapılacak iş yoktur.
  Future<void> beginMatch();

  /// Oturduğum masanın değişen durumu: biri oturdu/kalktı, geri sayım başladı/iptal oldu ([TableSnapshot.emptySeats],
  /// [TableSnapshot.startsInMs]). Masada değilsek olay gelmez.
  Stream<TableSnapshot> get tableUpdates;

  /// Maç bitti, aynı masada yeni oyun: masada kalır (botlar da kalır, kalkan insanların yerine yeni oyuncu/bot gelir).
  /// Yeni oyun için oda şartı yeniden aranır (giriş çipi oyun başlarken düşer). Masa artık yoksa ya da şart tutmuyorsa [JoinException].
  Future<TableSnapshot> stayAtTable();

  /// Masadan kalkar. Oyun başlamadıysa bedava; maç sürüyorsa giriş çipi yanar (ekran önce onay alır).
  void leaveTable();

  /// Maç sırasında sunucudan gelen mesajlar: `state` (maçın TEK doğru kaynağı: el, sıra, per, puan), `say` (bilgi),
  /// `err` (hamle hatası, ör. "Sıra sende değil.") ve `final` (maç sonu). Kural, dağıtım, süre ve botlar sunucudadır.
  Stream<Map<String, dynamic>> get matchEvents;

  /// Oturduğum masanın son `state` mesajı (ekran açılmadan önce gelmişse kaçırılmasın); maç yoksa null.
  Map<String, dynamic>? get latestMatchState;

  /// Oyun hamlesi yollar (`{t:'draw'}`, `{t:'discard', id}` ...). Yollandıysa true; masada değilsek / bağlantı yoksa false.
  bool sendMatch(Map<String, dynamic> msg);
}
