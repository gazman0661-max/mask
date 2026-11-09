import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:in_app_update/in_app_update.dart';
import '../diagnostics/app_log.dart';
import 'telemetry.dart';

/// ZORUNLU GÜNCELLEME (Google Play In-App Updates).
///
/// Oyun açılırken Play'de yeni sürüm varsa Google'ın tam ekran "Güncelle" penceresi çıkar;
/// oyuncu güncelleyince oyun kendini yeniden açar.
///  - Yalnız Play'den kurulu sürümde çalışır. APK / debug ile kurulu sürümde sessizce atlanır.
///  - Yeni sürüm Play'de "yayında" olmalı; yüklenip yayına girmesi saatler sürebilir.
///  - Hiçbir hata oyunu engellemez (her şey try/catch içinde).
class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService I = AppUpdateService._();

  /// true: tam ekran, zorunlu (immediate). false: arka planda indirir, hazır olunca kurar (flexible).
  static const bool forceImmediate = true;

  /// Yayınlanmasından beri bu kadar gün geçmeden zorlama yapma (0 = hemen).
  /// Örnek: 2 yaparsan yeni sürüm çıkınca oyunculara 2 gün süre tanınır.
  static const int minStalenessDays = 0;

  bool _checked = false;

  Future<void> check() async {
    if (_checked || kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _checked = true;
    try {
      // Arayüz/Activity hazır olsun.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      final info = await InAppUpdate.checkForUpdate().timeout(const Duration(seconds: 8));
      Log.i('güncelleme', 'checkForUpdate: ${info.updateAvailability} immediate=${info.immediateUpdateAllowed}');
      if (info.updateAvailability != UpdateAvailability.updateAvailable) return;
      final stale = info.clientVersionStalenessDays ?? 0;
      if (stale < minStalenessDays) return;
      final immediate = forceImmediate && info.immediateUpdateAllowed;
      Telemetry.event('update_available', {'stale_days': stale, 'mode': immediate ? 'immediate' : 'flexible'});
      if (immediate) {
        final r = await InAppUpdate.performImmediateUpdate();
        Log.i('güncelleme', 'performImmediateUpdate sonuç: ${r.name}');
        Telemetry.event('update_result', {'result': r.name});
      } else if (info.flexibleUpdateAllowed) {
        final r = await InAppUpdate.startFlexibleUpdate();
        Telemetry.event('update_result', {'result': r.name});
        if (r == AppUpdateResult.success) await InAppUpdate.completeFlexibleUpdate();
      }
    } catch (e) {
      // Play'den kurulu değil / Play Hizmetleri yok / zaman aşımı: oyun normal açılır.
      Log.w('güncelleme', 'kontrol atlandı: $e');
    }
  }
}
