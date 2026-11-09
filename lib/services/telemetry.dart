import 'dart:async';
import 'package:flutter/foundation.dart';

/// Analytics + çökme raporu için arka uç. Varsayılan [NoopTelemetry] hiçbir şey yapmaz:
/// Firebase paketi ve google-services.json olmadan uygulama aynen çalışır.
/// Yayında Firebase açılır: docs/FIREBASE_KURULUM.md.
abstract class TelemetryBackend {
  /// Kuruluma hazırlanır. Hata fırlatırsa [Telemetry] sessizce Noop'a döner (oyun etkilenmez).
  Future<void> init();

  /// Olay adı: ASCII harf/rakam/alt çizgi, harfle başlar, en fazla 40 karakter (Firebase kuralı).
  void event(String name, [Map<String, Object>? params]);

  void error(Object error, StackTrace? stack, {bool fatal = false});
}

class NoopTelemetry implements TelemetryBackend {
  const NoopTelemetry();
  @override
  Future<void> init() async {}
  @override
  void event(String name, [Map<String, Object>? params]) {}
  @override
  void error(Object error, StackTrace? stack, {bool fatal = false}) {}
}

/// Uygulamanın kullandığı tek kapı. Hiçbir çağrı istisna fırlatmaz, oyunu bekletmez.
class Telemetry {
  Telemetry._();

  static TelemetryBackend _b = const NoopTelemetry();
  static bool _ready = false;
  static int _errorsSent = 0;

  /// Bir oturumda en fazla bu kadar hata raporlanır (hata fırtınasında kota/pil harcanmasın).
  static const int maxErrorsPerSession = 25;

  /// Arka ucu seç (Firebase açılınca main.dart'tan, init'ten ÖNCE çağrılır).
  static void use(TelemetryBackend backend) {
    _b = backend;
    _ready = false;
  }

  static bool get active => _ready && _b is! NoopTelemetry;

  /// Yalnız testler için: her şeyi başlangıç durumuna (Noop, sayaç sıfır) döndürür.
  @visibleForTesting
  static void reset() {
    _b = const NoopTelemetry();
    _ready = false;
    _errorsSent = 0;
  }

  /// Arka ucu başlatır. Başarısız olur ya da 5 sn'de bitmezse Noop'a döner; asla fırlatmaz.
  static Future<void> init() async {
    try {
      await _b.init().timeout(const Duration(seconds: 5));
      _ready = true;
    } catch (e) {
      debugPrint('Telemetry kapalı: $e');
      _b = const NoopTelemetry();
      _ready = false;
    }
  }

  static void event(String name, [Map<String, Object>? params]) {
    if (!_ready) return;
    try {
      _b.event(name, params);
    } catch (e) {
      debugPrint('Telemetry.event hata: $e');
    }
  }

  static void error(Object error, StackTrace? stack, {bool fatal = false}) {
    if (!_ready) return;
    if (!fatal && _errorsSent >= maxErrorsPerSession) return;
    _errorsSent++;
    try {
      _b.error(error, stack, fatal: fatal);
    } catch (e) {
      debugPrint('Telemetry.error hata: $e');
    }
  }
}
