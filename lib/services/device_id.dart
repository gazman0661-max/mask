import 'dart:math' as math;
import 'package:android_id/android_id.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bu cihaza ait kalıcı kimlik (misafir hesabını geri bulmak için).
///
/// Android'de `ANDROID_ID`: uygulama verisi silinse ya da uygulama yeniden yüklense de AYNI kalır
/// (yalnız telefon fabrika ayarlarına dönünce ya da uygulama imza anahtarı değişince değişir).
/// Android dışında (önizleme/web, iOS) yedek: rastgele üretilip saklanan kimlik; veri silinince yenilenir.
class DeviceId {
  static const _key = 'device_fallback_id';
  static String? _cached;

  static Future<String> get() async {
    final c = _cached;
    if (c != null) return c;
    String? id;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        id = await const AndroidId().getId();
      } catch (_) {
        id = null;
      }
    }
    if (id == null || id.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      id = prefs.getString(_key);
      if (id == null || id.isEmpty) {
        final r = math.Random.secure();
        id = List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
        await prefs.setString(_key, id);
      }
    }
    return _cached = id;
  }
}
