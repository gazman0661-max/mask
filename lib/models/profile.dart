/// Oyuncunun takma adı (listeden seçilen kelime + sunucunun verdiği sayı: Kartal_4821) ve avatarı. [named] false ise oyuncu henüz takma ad seçmemiştir.
class Profile {
  final String name;
  final int avatar; // 0..kAvatarCount-1
  final bool named;
  const Profile({required this.name, required this.avatar, required this.named});

  static const empty = Profile(name: '', avatar: 0, named: false);
}

/// Profil kaydedilemedi. [message] kullanıcıya olduğu gibi gösterilir.
class ProfileException implements Exception {
  final String message;
  const ProfileException(this.message);
  @override
  String toString() => message;
}

/// Sunucunun hata kodları → Türkçe mesaj.
String profileErrorText(String code) {
  switch (code) {
    case 'gecersiz_isim':
      return 'Listeden bir isim seç.';
    case 'ad_alinmis':
      return 'Şu an bu isim için numara bulunamadı, tekrar dene.';
    case 'ad_sik_degisti':
      return 'İsmini haftada bir kez değiştirebilirsin. Avatarı istediğin zaman değiştirebilirsin.';
    case 'gecersiz_avatar':
      return 'Geçersiz avatar.';
    case 'giris_gerekli':
      return 'Oturum süresi dolmuş, uygulamayı yeniden aç.';
    default:
      return 'Profil kaydedilemedi, bağlantını kontrol edip tekrar dene.';
  }
}
