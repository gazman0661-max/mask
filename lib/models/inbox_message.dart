/// Mesaj kutusundaki bir mesaj. Sunucu hatası iadesinde [amount] > 0 olur ve
/// oyuncu AL'a basınca o kadar bilet (ya da eski çip iadesi) hesaba geçer (Supabase: inbox + claim_inbox).
class InboxMessage {
  final String id;
  final String kind; // 'ticket_gift' | 'ticket_refund' | 'refund' ...
  final int amount; // AL'a basınca hesaba geçecek bilet/çip, birim için [unit] (0 = sadece bilgi)
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

  /// Bilet mesajı mı (hediye bilet / sunucu hatası bilet iadesi)? Değilse [amount] çiptir.
  bool get isTicket => kind == 'ticket_gift' || kind == 'ticket_refund';

  /// Düğmede ve bildirimde görünen birim.
  String get unit => isTicket ? 'bilet' : 'çip';

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
        amount: ((j['amount'] ?? 0) as num).toInt(),
        title: (j['title'] ?? '') as String,
        body: (j['body'] ?? '') as String,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        claimedAt: j['claimed_at'] == null
            ? null
            : DateTime.parse(j['claimed_at'] as String).toLocal(),
      );
}
