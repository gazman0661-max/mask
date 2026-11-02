import 'package:flutter/foundation.dart' show kReleaseMode;

/// Derleme zamanı ayarları. Boşsa uygulama SAHTE servislerle (önizleme/FlutLab) çalışır.
///
/// Gerçek sunucuyla derlemek için:
///   flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=... \
///               --dart-define=WS_URL=wss://ws.alanadin.com/ws \
///               --dart-define=GUEST_DOMAIN=alanadin.com
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const wsUrl = String.fromEnvironment('WS_URL');

  /// Misafir hesaplarının sahte e-posta alan adı (`g-<özet>@<alan>`). E-posta HİÇ gönderilmez
  /// ama Supabase alan adının geçerli olmasını (DNS kaydı) isteyebilir: kendi alan adını kullan.
  static const guestDomain =
      String.fromEnvironment('GUEST_DOMAIN', defaultValue: 'misafir.okey101.app');

  /// Unity LevelPlay (ironSource) kimlikleri. KODA YAZILMAZ, derlemede verilir; BOŞKEN reklam SAHTE kalır
  /// (banner = yer tutucu şerit, ödüllü = 5 sn'lik sahte pencere). Okey için LevelPlay panelinde AYRI
  /// uygulama açıp (Android) şunları al:
  ///   --dart-define=LEVELPLAY_APP_KEY=...        (App Key)
  ///   --dart-define=LEVELPLAY_BANNER_ID=...      (Banner ad unit)
  ///   --dart-define=LEVELPLAY_REWARDED_ID=...    (Rewarded ad unit)
  /// Geçiş (interstitial) reklamı bu oyunda YOK.
  static const levelPlayAppKey = String.fromEnvironment('LEVELPLAY_APP_KEY');
  static const levelPlayBannerId = String.fromEnvironment('LEVELPLAY_BANNER_ID');
  static const levelPlayRewardedId = String.fromEnvironment('LEVELPLAY_REWARDED_ID');

  /// Banner gerçek reklam mı gösterir? (App Key + banner kimliği dolu)
  static bool get levelPlayBannerOn =>
      levelPlayAppKey.isNotEmpty && levelPlayBannerId.isNotEmpty;

  /// Ödüllü reklam gerçek mi? (App Key + rewarded kimliği dolu)
  static bool get levelPlayRewardedOn =>
      levelPlayAppKey.isNotEmpty && levelPlayRewardedId.isNotEmpty;

  /// Reklam modu: `off` (reklamsız), `mock` (320x50 sahte şerit + sahte ödüllü, yerleşimi görmek için),
  /// `levelplay` (gerçek LevelPlay; kimlikler dolu olmalı).
  /// `--dart-define=ADS=...` verilmezse: App Key doluysa `levelplay`; boşsa debug/profile derlemede `mock`
  /// (yer tutucu hep görünür), release derlemede `off`.
  static const _adsDefine = String.fromEnvironment('ADS');
  static String get adMode {
    if (_adsDefine.isNotEmpty) return _adsDefine;
    if (levelPlayAppKey.isNotEmpty) return 'levelplay';
    return kReleaseMode ? 'off' : 'mock';
  }

  static bool get backendReady =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty && wsUrl.isNotEmpty;
}
