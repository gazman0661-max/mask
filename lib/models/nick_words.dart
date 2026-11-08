// OTOMATİK ÜRETİLDİ: scripts/gen_nick_words.py — elle düzenleme. Sunucudaki (migration-011.sql) liste AYNI sıradadır.
// Takma ad serbest yazı DEĞİL: oyuncu bu listeden bir kelime seçer, sunucu sonuna sayı ekler (Kartal_4821).

const List<String> kNickWords = [
  'Kartal', 'Şahin', 'Doğan', 'Atmaca', 'Pars', 'Vaşak', 'Ceylan', 'Kuğu', 'Turna', 'Leylek',
  'Serçe', 'Bülbül', 'Kırlangıç', 'Martı', 'Yunus', 'Balina', 'Gelincik', 'Papatya', 'Lale',
  'Sümbül', 'Menekşe', 'Yasemin', 'Nergis', 'Zambak', 'Kardelen', 'Çınar', 'Meşe', 'Selvi',
  'Ihlamur', 'Söğüt', 'Defne', 'Akasya', 'Orkide', 'Nilüfer', 'Yıldız', 'Güneş', 'Bulut',
  'Yağmur', 'Fırtına', 'Rüzgar', 'Şimşek', 'Gökkuşağı', 'Şafak', 'Samanyolu', 'Gezegen',
  'Meltem', 'Poyraz', 'Lodos', 'Karayel', 'Bora', 'Bozkır', 'Dağ', 'Deniz', 'Nehir', 'Göl',
  'Ova', 'Vadi', 'Orman', 'Çöl', 'Ada', 'Pınar', 'Çağlayan', 'Şelale', 'Kıyı', 'Zirve',
  'Yayla', 'Tuna', 'Ege', 'Aras', 'Dicle', 'Fırat', 'Cesur', 'Yürek', 'Vefa', 'Umut', 'Dürüst',
  'Mert', 'Yiğit', 'Bilge', 'Kudret', 'Erdem', 'Onur', 'Sakin', 'Zarif', 'Asil', 'Özgür',
  'Gönül', 'Huzur', 'Neşe', 'Sefa', 'Safa', 'Cömert', 'Dost', 'Sadık', 'Badem', 'Nar', 'Çilek',
  'Kiraz', 'Vişne', 'Erik', 'Elma', 'Limon', 'Zeytin', 'İncir', 'Üzüm', 'Karpuz', 'Şeftali',
  'Kayısı', 'Nane', 'Biberiye', 'Lavanta', 'Ahenk', 'Ezgi', 'Nağme', 'Türkü', 'Saz', 'Keman',
  'Ney', 'Bağlama', 'Davul', 'Zurna', 'Kaval', 'Pusula', 'Fener', 'Kervan', 'Mavi', 'Turkuaz',
  'Lacivert', 'Zümrüt', 'Yakut', 'Elmas', 'İnci', 'Mercan', 'Kehribar', 'Gümüş', 'Altın',
  'Bakır', 'CesurKartal', 'AltınKartal', 'GümüşKurt', 'KarKaplanı', 'MaviTurna', 'SessizGöl',
  'NeşeliSerçe', 'UmutYıldızı', 'GeceKuşu', 'GüneşKuşu', 'BozkırKedi', 'KaraBulut', 'AkŞahin',
  'CoşkuRüzgar', 'SakinDeniz', 'GizliBahçe', 'AltınBaşak', 'YeşilÇınar', 'DağÇiçeği',
  'KutupYıldız', 'UçanKaplan', 'HızlıAtmaca', 'YalnızKurt', 'TatlıKiraz', 'MutluBaykuş',
  'SarıLale', 'MorMenekşe', 'BeyazKuğu', 'KızılElma', 'GökTurna', 'DenizKızı', 'RüzgarGülü',
  'Ayışığı', 'Gündoğumu', 'Baykuş', 'Karaca', 'Geyik', 'Tilki', 'Sincap', 'Kunduz', 'Yaban',
  'Doğa', 'Çimen', 'Çiçek', 'Bahar', 'Yaz', 'Güz', 'Kış', 'Gece', 'Sabah', 'Akşam', 'Gün',
  'Ay', 'Tan', 'Seher', 'Kuzey', 'Güney', 'Doğu', 'Batı', 'Anadolu', 'Toros', 'Ağrı',
  'Erciyes', 'Uludağ', 'Munzur', 'Kaçkar', 'Palandöken', 'Kuzgun', 'Albatros', 'Flamingo',
  'Pelikan', 'Karakuş', 'Doğru', 'Kardan', 'Buzul', 'Kutup', 'Yelken', 'Kaptan', 'Dümen',
  'Liman', 'Fırtınalı', 'Usta', 'Çırak', 'Ozan', 'Âşık',
];

/// Kayıtlı addan (Kartal_4821) kelimenin sırasını bulur; bulunamazsa null.
int? nickWordIndex(String name) {
  final base = name.replaceFirst(RegExp(r'_[0-9]{4}$'), '');
  final i = kNickWords.indexOf(base);
  return i < 0 ? null : i;
}
