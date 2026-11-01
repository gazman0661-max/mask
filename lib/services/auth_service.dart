import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'account_service.dart';
import 'device_id.dart';

/// Giriş yapılamadı. [message] kullanıcıya olduğu gibi gösterilir.
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}

/// Oturum sağlayıcı. Sunucu ve Supabase çağrıları [accessToken] ile kimlik doğrular.
/// Giriş yöntemi (misafir, Google) bu arayüzün arkasında değişir; oyunun geri kalanı bilmez.
abstract class AuthService {
  /// Geçerli Supabase access_token (süresi dolmak üzereyse yenisini alır).
  Future<String> accessToken();

  /// Giriş yapılmışsa kullanıcı kimliği (JWT `sub`).
  String? get userId;
}

/// İki AYRI hesap: misafir ve Google. Birbirine bağlanmaz; çip/seviye/ilerleme her hesapta ayrıdır.
///
/// Misafir: cihaz kimliğinden türetilen e-posta + şifreyle Supabase'e girer; hesap yoksa açar.
/// Aynı cihaz = aynı misafir hesabı (uygulama silinse bile). Ekranda hiçbir şey sorulmaz.
///
/// Google: Supabase OAuth (PKCE, tarayıcı penceresi). Google'a girilince AYRI bir Supabase kullanıcısı
/// olur; yenileme anahtarı cihazda saklanır, böylece hesaplar arası geçiş tarayıcı açmadan yapılır.
/// Hangi hesabın aktif olduğu da saklanır: uygulama kaldığın hesapla açılır.
///
/// Supabase panelinde:
///  * Authentication → Providers → Email → "Confirm email" KAPALI
///  * Authentication → Providers → Google AÇIK (Web OAuth istemcisi: Client ID + Secret)
///  * Authentication → URL Configuration → Redirect URLs: `okey101://login-callback`
class GuestAuthService implements AuthService, AccountService {
  final String supabaseUrl;
  final String anonKey;
  final String guestDomain;
  final http.Client _http;

  GuestAuthService({
    required this.supabaseUrl,
    required this.anonKey,
    required this.guestDomain,
    http.Client? client,
  }) : _http = client ?? http.Client();

  // Uygulamanın içinde durduğu için gizli değildir; misafir hesabı için kabul edilebilir
  // (kimlik cihazdan çıkmaz, kullanıcıya gösterilmez). Değiştirirsen eski misafir hesapları açılamaz.
  static const _pepper = 'okey101-misafir-v1';

  /// AndroidManifest.xml'deki callback etkinliğinin şeması ve Supabase'e kayıtlı yönlendirme adresi.
  static const callbackScheme = 'okey101';
  static const _redirect = '$callbackScheme://login-callback';
  static const _kMode = 'auth_mode';
  static const _kGoogleRefresh = 'auth_google_refresh';
  static const _kGoogleEmail = 'auth_google_email';

  String? _token;
  String? _uid;
  DateTime _exp = DateTime.fromMillisecondsSinceEpoch(0);
  Future<String>? _inflight;

  AccountMode _mode = AccountMode.guest;
  String? _googleRefresh;
  String? _googleEmail;
  bool _stateLoaded = false;

  @override
  String? get userId => _uid;

  @override
  AccountMode get mode => _mode;

  @override
  String? get googleEmail => _googleEmail;

  @override
  bool get hasGoogle => _googleEmail != null;

  // ------------------------------------------------------------ kayıtlı durum

  Future<void> _loadState() async {
    if (_stateLoaded) return;
    final p = await SharedPreferences.getInstance();
    _mode = p.getString(_kMode) == 'google' ? AccountMode.google : AccountMode.guest;
    _googleRefresh = p.getString(_kGoogleRefresh);
    _googleEmail = p.getString(_kGoogleEmail);
    if (_googleRefresh == null) _mode = AccountMode.guest;
    _stateLoaded = true;
  }

  Future<void> _saveMode() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kMode, _mode == AccountMode.google ? 'google' : 'guest');
  }

  Future<void> _saveGoogle(String refresh, String? email) async {
    _googleRefresh = refresh;
    if (email != null && email.isNotEmpty) _googleEmail = email;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kGoogleRefresh, refresh);
    final e = _googleEmail;
    if (e != null) await p.setString(_kGoogleEmail, e);
  }

  /// Google oturumu geçersiz oldu (başka yerden çıkış vb.): unut, misafire dön.
  Future<void> _forgetGoogle() async {
    _googleRefresh = null;
    _googleEmail = null;
    _mode = AccountMode.guest;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kGoogleRefresh);
    await p.remove(_kGoogleEmail);
    await _saveMode();
  }

  void _clearSession() {
    _token = null;
    _uid = null;
    _exp = DateTime.fromMillisecondsSinceEpoch(0);
    _inflight = null;
  }

  @override
  Future<void> refresh() => _loadState();

  // ------------------------------------------------------------ oturum

  @override
  Future<String> accessToken() {
    final t = _token;
    if (t != null && _exp.isAfter(DateTime.now().add(const Duration(seconds: 60)))) {
      return Future.value(t);
    }
    // Aynı anda gelen çağrılar tek girişi paylaşır (çift hesap açılmasın, yenileme anahtarı yanmasın).
    return _inflight ??= _session().whenComplete(() => _inflight = null);
  }

  Future<String> _session() async {
    await _loadState();
    if (_mode == AccountMode.google) {
      final rt = _googleRefresh;
      if (rt != null) {
        final r = await _post('/auth/v1/token?grant_type=refresh_token', {'refresh_token': rt});
        if (r.statusCode == 200) return _adopt(r.body, AccountMode.google);
        if (r.statusCode >= 500 || r.statusCode == 429) {
          // Geçici sunucu sorunu: Google oturumunu atma, misafire de düşme (başka hesaba geçmiş gibi olur).
          throw AuthException('Sunucuya ulaşılamadı (${r.statusCode}). Biraz sonra tekrar dene.');
        }
      }
      // Anahtar geçersiz (400/401) ya da yok: Google oturumu bitti, misafire dön.
      await _forgetGoogle();
    }
    return _guestLogin();
  }

  Future<String> _guestLogin() async {
    final id = await DeviceId.get();
    final email = 'g-${_hex('$id|e').substring(0, 32)}@$guestDomain';
    final password = _hex('$id|p|$_pepper');

    var r = await _post('/auth/v1/token?grant_type=password', {'email': email, 'password': password});
    if (r.statusCode == 400) {
      // Hesap henüz yok: aç (ilk açılış).
      r = await _post('/auth/v1/signup', {'email': email, 'password': password});
    }
    if (r.statusCode != 200) {
      throw AuthException('Giriş yapılamadı (${r.statusCode}). Bağlantını kontrol edip tekrar dene.');
    }
    return _adopt(r.body, AccountMode.guest);
  }

  /// Supabase oturum cevabını alır: token, kullanıcı kimliği, süre; Google ise yenileme anahtarı ve e-posta.
  Future<String> _adopt(String body, AccountMode m) async {
    final j = jsonDecode(body) as Map<String, dynamic>;
    final tok = j['access_token'];
    if (tok is! String) {
      // Kayıt oldu ama oturum yok: e-posta onayı açık demektir.
      throw const AuthException('Sunucu ayarı eksik: Supabase\'te "Confirm email" kapatılmalı.');
    }
    final user = j['user'] is Map ? j['user'] as Map : null;
    _token = tok;
    _uid = user?['id'] as String?;
    final secs = (j['expires_in'] as num?)?.toInt() ?? 3600;
    _exp = DateTime.now().add(Duration(seconds: secs));
    if (m == AccountMode.google) {
      final rt = j['refresh_token'];
      if (rt is String && rt.isNotEmpty) await _saveGoogle(rt, user?['email'] as String?);
    }
    return tok;
  }

  // ------------------------------------------------------------ hesap değiştirme

  @override
  Future<void> useGuest() async {
    await _loadState();
    _mode = AccountMode.guest;
    await _saveMode();
    _clearSession(); // sıradaki istek misafir olarak girer
  }

  @override
  Future<bool> signInGoogle({bool fresh = false}) async {
    await _loadState();
    final rt = _googleRefresh;
    if (!fresh && rt != null) {
      // Bu cihazda daha önce girilmiş: tarayıcı açmadan saklı oturumu yenile.
      final r = await _post('/auth/v1/token?grant_type=refresh_token', {'refresh_token': rt});
      if (r.statusCode == 200) {
        _mode = AccountMode.google;
        _clearSession();
        await _adopt(r.body, AccountMode.google);
        await _saveMode();
        return true;
      }
      if (r.statusCode >= 500 || r.statusCode == 429) {
        throw AuthException('Sunucuya ulaşılamadı (${r.statusCode}). Biraz sonra tekrar dene.');
      }
      // Geçersiz: unut ve Google penceresiyle gir.
      await _forgetGoogle();
    }

    final pkce = _Pkce();
    final url = Uri.parse('$supabaseUrl/auth/v1/authorize').replace(queryParameters: {
      'provider': 'google',
      'redirect_to': _redirect,
      'code_challenge': pkce.challenge,
      'code_challenge_method': 's256',
      'prompt': 'select_account',
    });
    final cb = await _browse(url.toString());
    if (cb == null) return false;
    final q = _params(cb);
    final code = q['code'];
    if (code == null) {
      final err = '${q['error'] ?? ''} ${q['error_description'] ?? ''}'.toLowerCase();
      if (err.contains('access_denied')) return false;
      throw const AuthException('Google ile giriş yapılamadı, tekrar dene.');
    }
    final r = await _post('/auth/v1/token?grant_type=pkce', {'auth_code': code, 'code_verifier': pkce.verifier});
    if (r.statusCode != 200) {
      throw AuthException('Google girişi tamamlanamadı (${r.statusCode}). Tekrar dene.');
    }
    _mode = AccountMode.google;
    _clearSession();
    await _adopt(r.body, AccountMode.google);
    await _saveMode();
    return true;
  }

  /// Tarayıcı penceresini açar, dönüş adresini bekler. Kullanıcı kapatırsa null.
  Future<Uri?> _browse(String url) async {
    try {
      final res = await FlutterWebAuth2.authenticate(url: url, callbackUrlScheme: callbackScheme);
      return Uri.parse(res);
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED') return null;
      throw const AuthException('Google penceresi açılamadı.');
    }
  }

  /// Dönüş adresindeki parametreler (PKCE'de sorguda, hata durumunda bazen parçada gelir).
  static Map<String, String> _params(Uri u) {
    final m = <String, String>{...u.queryParameters};
    if (u.fragment.isNotEmpty) {
      try {
        m.addAll(Uri.splitQueryString(u.fragment));
      } catch (_) {}
    }
    return m;
  }

  Future<http.Response> _post(String path, Map<String, String> body) => _http
      .post(Uri.parse('$supabaseUrl$path'),
          headers: {'apikey': anonKey, 'Content-Type': 'application/json'},
          body: jsonEncode(body))
      .timeout(const Duration(seconds: 15));

  static String _hex(String s) => sha256.convert(utf8.encode(s)).toString();
}

/// PKCE: rastgele doğrulayıcı + SHA-256 özeti (base64url, dolgusuz).
class _Pkce {
  static const _chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
  late final String verifier = () {
    final r = math.Random.secure();
    return List.generate(64, (_) => _chars[r.nextInt(_chars.length)]).join();
  }();
  String get challenge =>
      base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
}
