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

  static bool get backendReady =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty && wsUrl.isNotEmpty;
}
