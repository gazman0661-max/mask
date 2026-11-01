/// Hazır mesaj ve emoji listesi. Serbest yazı YOK: ağdan yalnız [QuickChat.id] gider,
/// metni/emojiyi her cihaz kendi gösterir (küfür/hakaret/moderasyon derdi yok, mesaj küçük kalır).
///
/// UYARI: numaralar sunucuyla ve eski sürümlerle ortak sözleşmedir. Var olan numarayı
/// ASLA değiştirme/silme; yeni mesaj için boş numara kullan (sunucu 0..31 arasını kabul eder,
/// `shard.ts` içindeki `CHAT_COUNT`).
class QuickChat {
  final int id;

  /// Hazır cümle (null ise emoji).
  final String? text;

  /// Emoji (null ise cümle). Flutter/Android sistem emoji yazı tipiyle çizilir, paket gerekmez.
  final String? emoji;
  const QuickChat.text(this.id, String this.text) : emoji = null;
  const QuickChat.emoji(this.id, String this.emoji) : text = null;

  bool get isEmoji => emoji != null;

  /// Balonda ve düğmede görünen yazı.
  String get label => text ?? emoji!;
}

/// Hazır cümleler (numara 0-7 ve 18).
const List<QuickChat> kQuickPhrases = [
  QuickChat.text(0, 'Seriii'),
  QuickChat.text(1, 'Okey attın!'),
  QuickChat.text(2, 'Bu el benim'),
  QuickChat.text(3, 'Elin nasıl?'),
  QuickChat.text(4, 'Bitiyim mi?'),
  QuickChat.text(5, 'Evet'),
  QuickChat.text(6, 'Hayır'),
  QuickChat.text(7, 'Tebrikler'),
  QuickChat.text(18, 'Teşekkürler'), // 18: emoji aralığındaki boş numara; sözleşme gereği numara değişmez
];

/// Emojiler (numara 8-17; 19 boş).
const List<QuickChat> kQuickEmojis = [
  QuickChat.emoji(8, '😂'),
  QuickChat.emoji(9, '😎'),
  QuickChat.emoji(10, '😡'),
  QuickChat.emoji(11, '😭'),
  QuickChat.emoji(12, '👏'),
  QuickChat.emoji(13, '👍'),
  QuickChat.emoji(14, '🔥'),
  QuickChat.emoji(15, '🤔'),
  QuickChat.emoji(16, '😱'),
  QuickChat.emoji(17, '🙏'),
];

/// Numaradan mesajı bulur; bilinmeyen numara (yeni sürümden gelen) null döner ve yok sayılır.
QuickChat? quickChatById(int id) {
  for (final c in kQuickPhrases) {
    if (c.id == id) return c;
  }
  for (final c in kQuickEmojis) {
    if (c.id == id) return c;
  }
  return null;
}

/// Bir oyuncunun mesajı. [seat] gönderenin BANA göre koltuğu: 0 ben, 1 sağ, 2 karşı, 3 sol
/// (oyun ekranındaki koltuk sırasıyla aynı).
class ChatEvent {
  final int seat;
  final int id;
  const ChatEvent(this.seat, this.id);
}

/// Balon ekranda bu kadar kalır.
const Duration kChatShowTime = Duration(milliseconds: 2600);

/// Aynı oyuncu bu süreden sık mesaj atamaz (sunucudaki `EMO_COOLDOWN_MS` ile aynı: 3 sn).
const Duration kChatCooldown = Duration(seconds: 3);

/// 60 sn'de en fazla bu kadar mesaj (sunucudaki `EMO_PER_MIN` ile aynı).
const int kChatPerMinute = 8;

/// İstemci tarafı hız sınırı: bekleme süresi + dakikalık sınır. Sunucuyla AYNI kurallar, böylece normal
/// oyuncu sunucunun sessizce atacağı mesajı hiç yollamaz (gelen her mesaj kotadan sayılır).
class ChatLimiter {
  final List<DateTime> _sent = [];

  /// Şimdi mesaj atılabilir mi? (atılamıyorsa [wait] ne kadar beklenmesi gerektiğini söyler)
  bool canSend(DateTime now) => wait(now) == Duration.zero;

  /// Atılabilene kadar kalan süre (Duration.zero = şimdi atılabilir).
  Duration wait(DateTime now) {
    _sent.removeWhere((t) => now.difference(t) >= const Duration(seconds: 60));
    var w = Duration.zero;
    if (_sent.isNotEmpty) {
      final c = _sent.last.add(kChatCooldown).difference(now);
      if (c > w) w = c;
    }
    if (_sent.length >= kChatPerMinute) {
      final m = _sent[_sent.length - kChatPerMinute].add(const Duration(seconds: 60)).difference(now);
      if (m > w) w = m;
    }
    return w;
  }

  /// Mesaj atıldı olarak kaydeder (önce [canSend] true olmalı).
  void record(DateTime now) => _sent.add(now);
}
