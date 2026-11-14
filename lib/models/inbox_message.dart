/// Mesaj kutusundaki bir mesaj. Sunucu hatası iadesinde [amount] > 0 olur ve
/// oyuncu AL'a basınca o kadar çip hesaba geçer (Supabase: inbox + claim_inbox).
class InboxMessage {
  final String id;
  final String kind; // 'gift' | 'refund' | 'cheat_refund' | (eski) 'ticket_gift' | 'ticket_refund' ...
  final int amount; // AL'a basınca hesaba geçecek ÇİP (0 = sadece bilgi). Eski bilet mesajları bilet başına [kLegacyTicketChips] çipe çevrilir.
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime? claimedAt;

  const InboxMessage({
    required this.id,
    required this.kind,
    required this.amount,
    required this.title,
    required this.body,
    required this.createdAt,
    this.claimedAt,
  });

  bool get claimed => claimedAt != null;

  /// Düğmede ve bildirimde görünen birim.
  String get unit => 'çip';

  /// AL butonu gösterilsin mi?
  bool get claimable => !claimed && amount > 0;

  InboxMessage copyWith({DateTime? claimedAt}) => InboxMessage(
        id: id,
        kind: kind,
        amount: amount,
        title: title,
        body: body,
        createdAt: createdAt,
        claimedAt: claimedAt ?? this.claimedAt,
      );

  factory InboxMessage.fromJson(Map<String, dynamic> j) => InboxMessage(
        id: j['id'] as String,
        kind: (j['kind'] ?? 'info') as String,
        amount: _chips((j['kind'] ?? 'info') as String, ((j['amount'] ?? 0) as num).toInt()),
        title: (j['title'] ?? '') as String,
        body: (j['body'] ?? '') as String,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        claimedAt: j['claimed_at'] == null
            ? null
            : DateTime.parse(j['claimed_at'] as String).toLocal(),
      );
}

/// Eski bilet mesajlarının (henüz alınmamış) çip karşılığı: bilet başına 2.000 çip. Sunucudaki `claim_inbox` ile AYNI.
const int kLegacyTicketChips = 2000;

int _chips(String kind, int amount) => kind == 'ticket_gift' || kind == 'ticket_refund' ? amount * kLegacyTicketChips : amount;
