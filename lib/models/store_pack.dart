/// Mağazadaki bilet paketi. Fiyat BURADA tutulmaz: Google Play'den (ürün kimliğiyle) çekilip
/// ekrana `prices[productId]` olarak verilir. Gelene kadar butonda "SATIN AL" yazar.
class StorePack {
  /// Play Console'daki uygulama içi ürün kimliği (tüketilebilir ürün).
  final String productId;
  final int tickets;

  /// Kartın köşesindeki kırmızı etiket (ör. "POPÜLER"); yoksa null.
  final String? badge;
  const StorePack({required this.productId, required this.tickets, this.badge});
}

/// Paket listesi (küçükten büyüğe). Play Console'da aynı ürün kimlikleriyle tanımla.
const List<StorePack> kStorePacks = [
  StorePack(productId: 'ticket_5', tickets: 5),
  StorePack(productId: 'ticket_10', tickets: 10),
  StorePack(productId: 'ticket_15', tickets: 15, badge: 'POPÜLER'),
  StorePack(productId: 'ticket_30', tickets: 30),
  StorePack(productId: 'ticket_50', tickets: 50, badge: 'AVANTAJLI'),
];
