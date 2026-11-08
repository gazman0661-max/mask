import 'package:flutter/foundation.dart' show kReleaseMode;

/// Derleme zamanı ayarları. Boşsa uygulama SAHTE servislerle (önizleme/FlutLab) çalışır.
///
/// Gerçek sunucuyla derlemek için:
///   flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=... \
///               --dart-define=WS_URL=wss://ws.alanadin.com/ws \
///               --dart-define=GUEST_DOMAIN=alanadin.com
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL',
      defaultValue: 'https://kmgyfebytujexbxzqdmv.supabase.co');
  // Publishable key herkese açık olabilir (RLS ile korunur). SECRET key buraya ASLA yazılmaz.
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY',
      defaultValue: 'sb_publishable_788hs4eOGkTJ2mNT3lsOwA_rBQKTuYE');
  static const wsUrl = String.fromEnvironment('WS_URL',
      defaultValue: 'wss://okey101-server.610gastille.workers.dev/ws');

  /// Misafir hesaplarının sahte e-posta alan adı (`g-<özet>@<alan>`). E-posta HİÇ gönderilmez
  /// ama Supabase alan adının geçerli olmasını (DNS kaydı) isteyebilir: kendi alan adını kullan.
  static const guestDomain =
      String.fromEnvironment('GUEST_DOMAIN', defaultValue: 'misafir.okey101.app');

  /// Unity LevelPlay (ironSource) kimlikleri. Varsayılan olarak koda yazıldı (App Key/ad unit ID'ler zaten
  /// APK'nın içinde görünür, gizli değil); istenirse --dart-define ile ezilir. BOŞKEN reklam SAHTE kalır
  /// (banner = yer tutucu şerit, ödüllü = 5 sn'lik sahte pencere). Okey için LevelPlay panelinde AYRI
  /// uygulama açıp (Android) şunları al:
  ///   --dart-define=LEVELPLAY_APP_KEY=...        (App Key)
  ///   --dart-define=LEVELPLAY_BANNER_ID=...      (Banner ad unit)
  ///   --dart-define=LEVELPLAY_REWARDED_ID=...    (Rewarded ad unit)
  /// Geçiş (interstitial) reklamı bu oyunda YOK.
  static const levelPlayAppKey = String.fromEnvironment('LEVELPLAY_APP_KEY', defaultValue: '2734447fd');
  static const levelPlayBannerId = String.fromEnvironment('LEVELPLAY_BANNER_ID', defaultValue: '49c6c5wjz2gagjlb');
  static const levelPlayRewardedId = String.fromEnvironment('LEVELPLAY_REWARDED_ID', defaultValue: '2eiwf0yysehblsw1');

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

  /// Worker'ın hesap silme adresi: WS_URL'den türetilir (wss://host/ws -> https://host/account/delete).
  static String get accountDeleteUrl {
    var u = wsUrl.trim();
    if (u.isEmpty) return '';
    if (u.startsWith('wss://')) {
      u = 'https://${u.substring(6)}';
    } else if (u.startsWith('ws://')) {
      u = 'http://${u.substring(5)}';
    }
    u = u.split('?').first.replaceFirst(RegExp(r'/ws/?$'), '').replaceFirst(RegExp(r'/+$'), '');
    return '$u/account/delete';
  }

  /// Worker'ın ülke sorgu adresi (https://host/geo): WS_URL'den türetilir. Boşsa Worker adımı atlanır.
  static String get geoUrl {
    final d = accountDeleteUrl;
    if (d.isEmpty) return '';
    return d.replaceFirst(RegExp(r'/account/delete$'), '/geo');
  }

  /// Mağaza (sepet) butonu. Şimdilik KAPALI: çip yalnız reklam ve günlük ödülle kazanılır.
  /// İleride Google Play satın alma açılırsa true yap; mağaza ekranı (lib/screens/store_screen.dart) hazır bekliyor.
  static const bool storeEnabled = false;

  static bool get backendReady =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty && wsUrl.isNotEmpty;
}
