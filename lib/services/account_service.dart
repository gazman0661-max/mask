import 'dart:async';

/// Şu an hangi hesapla oynanıyor.
enum AccountMode { guest, google }

/// İki AYRI hesap: Misafir (cihaza özel) ve Google. Çipler, seviye ve ilerleme hesaplar arasında
/// paylaşılmaz/taşınmaz; oyuncu istediği zaman birinden diğerine geçebilir (ikisi de kendi ilerlemesini korur).
/// Arayüzün tek bağımlılığı; oturum işleri [AuthService] tarafında kalır.
abstract class AccountService {
  /// Şu an aktif hesap.
  AccountMode get mode;

  /// Bu cihazda Google ile girilmişse o hesabın e-postası (hiç girilmediyse null).
  String? get googleEmail;

  /// Bu cihazda daha önce Google ile girilmiş mi?
  bool get hasGoogle => googleEmail != null;

  /// Kayıtlı durumu okur (pencere açılırken çağrılır).
  Future<void> refresh();

  /// Misafir hesabına geçer (tarayıcı açmaz). Google hesabı bu cihazda hatırlanır.
  Future<void> useGuest();

  /// Google hesabına geçer. Bu cihazda daha önce girilmişse tarayıcı açmadan, değilse (ya da [fresh] ise,
  /// yani başka bir Google hesabı seçilecekse) Google penceresiyle girer.
  /// true = geçildi, false = kullanıcı iptal etti. Hata olursa [AuthException] fırlatır.
  Future<bool> signInGoogle({bool fresh = false});
}

/// Önizleme (sunucu yok): hesaplar arası geçişi taklit eder, hiçbir şey saklamaz.
class MockAccountService implements AccountService {
  AccountMode _mode = AccountMode.guest;
  String? _email;

  @override
  AccountMode get mode => _mode;

  @override
  String? get googleEmail => _email;

  @override
  bool get hasGoogle => _email != null;

  @override
  Future<void> refresh() async {}

  @override
  Future<void> useGuest() async => _mode = AccountMode.guest;

  @override
  Future<bool> signInGoogle({bool fresh = false}) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    _mode = AccountMode.google;
    _email = 'ornek@gmail.com';
    return true;
  }
}
