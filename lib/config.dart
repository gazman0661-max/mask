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

  /// Banner reklam: `off` (varsayılan, testler/önizleme), `mock` (320x50 sahte şerit, yerleşimi görmek için),
  /// `admob` (gerçek AdMob). Örn: `--dart-define=ADS=admob --dart-define=ADMOB_BANNER_ID=ca-app-pub-xxx/yyy`
  static const adMode = String.fromEnvironment('ADS', defaultValue: 'off');

  /// AdMob banner birim kimliği. Varsayılan Google'ın TEST kimliğidir (Android); canlıda kendininkini ver.
  static const bannerUnitId = String.fromEnvironment('ADMOB_BANNER_ID',
      defaultValue: 'ca-app-pub-3940256099942544/6300978111');

  static bool get backendReady =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty && wsUrl.isNotEmpty;
}
