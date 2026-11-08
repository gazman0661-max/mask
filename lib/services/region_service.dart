import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import '../diagnostics/app_log.dart';

/// Oyuncunun ÜLKESİNİ internetten (IP) bulur; AB/AEA/BK'de reklam izni kutusunu göstermek için kullanılır.
/// Sıra (her adım 2 sn'de vazgeçer):
///   1) Cloudflare'in herkese açık adresi (`cdn-cgi/trace`, `loc=DE`): Worker kotasına yazılmaz.
///   2) Kendi Worker'ımız (`/geo`): 1. adım ulaşılamazsa.
///   3) Hiçbiri olmazsa null döner; çağıran telefon diline bakar ([LegalConsentService.showGdpr]).
/// Sonuç telefona kaydedilir ve [maxAge] süresince yeniden sorulmaz (kurulum başına ayda ~1 istek).
class RegionService {
  RegionService._();

  static const traceUrl = 'https://www.cloudflare.com/cdn-cgi/trace';
  static const _kCountry = 'region_country_v1';
  static const _kTime = 'region_time_v1';
  static const maxAge = Duration(days: 30);
  static const _step = Duration(seconds: 2);

  /// İki harfli büyük ülke kodu mu? (Cloudflare'in "XX" bilinmiyor ve "T1" Tor değerleri geçersiz.)
  static String? cleanCode(String? v) {
    final c = (v ?? '').trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(c) || c == 'XX' || c == 'T1') return null;
    return c;
  }

  /// `trace` yanıtındaki `loc=XX` satırından ülkeyi okur.
  static String? parseTrace(String body) {
    for (final line in const LineSplitter().convert(body)) {
      if (line.startsWith('loc=')) return cleanCode(line.substring(4));
    }
    return null;
  }

  static Future<String?> _fromTrace() async {
    try {
      final r = await http.get(Uri.parse(traceUrl)).timeout(_step);
      if (r.statusCode != 200) return null;
      return parseTrace(r.body);
    } catch (e) {
      Log.w('bölge', 'trace alınamadı: $e');
      return null;
    }
  }

  static Future<String?> _fromWorker() async {
    final u = AppConfig.geoUrl;
    if (u.isEmpty) return null;
    try {
      final r = await http.get(Uri.parse(u)).timeout(_step);
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body);
      return j is Map ? cleanCode(j['country']?.toString()) : null;
    } catch (e) {
      Log.w('bölge', 'Worker /geo alınamadı: $e');
      return null;
    }
  }

  /// Ülke kodu ya da bulunamazsa null. Kayıt tazeyse ağa hiç çıkmaz; bayatsa eskisini hemen verir,
  /// yenisini arka planda arar (açılış beklemez). Hiç kayıt yoksa ağdan bekler.
  /// [trace] / [worker] yalnız testler için.
  static Future<String?> resolveCountry({Future<String?> Function()? trace, Future<String?> Function()? worker}) async {
    String? cached;
    int? at;
    SharedPreferences? p;
    try {
      p = await SharedPreferences.getInstance();
      cached = cleanCode(p.getString(_kCountry));
      at = p.getInt(_kTime);
    } catch (e) {
      Log.w('bölge', 'kayıt okunamadı: $e');
    }
    final age = at == null ? null : DateTime.now().millisecondsSinceEpoch - at;
    final fresh = cached != null && age != null && age >= 0 && age < maxAge.inMilliseconds;
    if (fresh) return cached;

    Future<String?> lookup() async {
      final c = await (trace ?? _fromTrace)() ?? await (worker ?? _fromWorker)();
      if (c != null && p != null) {
        try {
          await p.setString(_kCountry, c);
          await p.setInt(_kTime, DateTime.now().millisecondsSinceEpoch);
        } catch (e) {
          Log.w('bölge', 'kayıt yazılamadı: $e');
        }
      }
      return c;
    }

    if (cached != null) {
      unawaited(lookup()); // bayat kayıt: şimdilik onu kullan, yenisi sonraki açılışa hazır olsun
      return cached;
    }
    return lookup();
  }
}
