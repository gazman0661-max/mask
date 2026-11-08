/// Mağazadaki çip paketi. Fiyat BURADA tutulmaz: Google Play'den (ürün kimliğiyle) çekilip
/// ekrana `prices[productId]` olarak verilir. Gelene kadar butonda "SATIN AL" yazar.
class StorePack {
  /// Play Console'daki uygulama içi ürün kimliği (tüketilebilir ürün).
  final String productId;
  final int chips;

  /// Kartın köşesindeki kırmızı etiket (ör. "POPÜLER"); yoksa null.
  final String? badge;
  const StorePack({required this.productId, required this.chips, this.badge});
}

/// Paket listesi (küçükten büyüğe). Play Console'da aynı ürün kimlikleriyle tanımla.
/// Miktarlar ekonomi ayarıdır: en düşük masa 2.000 çip, günlük ödül 2.000-4.000, reklam 4.000 (15 dk).
const List<StorePack> kStorePacks = [
  StorePack(productId: 'chips_25k', chips: 25000),
  StorePack(productId: 'chips_60k', chips: 60000),
  StorePack(productId: 'chips_150k', chips: 150000, badge: 'POPÜLER'),
  StorePack(productId: 'chips_400k', chips: 400000),
  StorePack(productId: 'chips_1m', chips: 1000000, badge: 'AVANTAJLI'),
];
