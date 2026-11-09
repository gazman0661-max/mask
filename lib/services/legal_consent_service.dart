import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';
import '../diagnostics/app_log.dart';
import 'app_update_service.dart';
import 'levelplay_service.dart';
import 'region_service.dart';
import 'telemetry.dart';

/// İlk açılışta Hizmet Şartları + Gizlilik Politikası (+ AB/AEA/BK için GDPR reklam izni) onayı.
/// Onay verilmeden oyun açılmaz; reklam SDK'sı (LevelPlay) ve analitik/çökme (Telemetry)
/// onaydan ÖNCE başlatılmaz.
///
/// Metinler değişip yeniden onay gerekirse [version] sayısını artır: pencere bir daha çıkar.
class LegalConsentService {
  LegalConsentService._();
  static final LegalConsentService I = LegalConsentService._();

  static const int version = 1;
  static const _kVersion = 'legal_consent_version_v1';
  static const _kTime = 'legal_consent_time_v1';
  static const _kAds = 'legal_gdpr_consent_v1';

  bool _accepted = false;
  bool _adConsent = false;
  bool _started = false;

  /// İnternetten (IP) bulunan ülke AB/AEA/BK/İsviçre mi? null = bulunamadı, telefon diline bakılır.
  bool? _inGdprRegion;

  bool get accepted => _accepted;

  /// AB/AEA/BK'de açık reklam izni (pencerenin GDPR kutusu). Ayarlar > Reklam İzni ile değişir.
  bool get adConsent => _adConsent;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getInt(_kVersion);
      _accepted = (v ?? 0) >= version;
      _adConsent = p.getBool(_kAds) ?? false;
      Log.i('onay', 'yüklendi: kayıtlıSürüm=$v gerekli=$version kabul=$_accepted reklamİzni=$_adConsent');
    } catch (e, s) {
      _accepted = false;
      _adConsent = false;
      Log.e('onay', 'onay okunamadı', e, s);
    }
  }

  /// Oyuncu KABUL ET'e bastı: kaydet, sonra onay gerektiren servisleri başlat.
  Future<void> accept({required bool adConsent}) async {
    _accepted = true;
    _adConsent = adConsent;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_kVersion, version);
      await p.setString(_kTime, DateTime.now().toUtc().toIso8601String());
      await p.setBool(_kAds, adConsent);
      Log.i('onay', 'kabul kaydedildi (sürüm $version, reklamİzni=$adConsent)');
    } catch (e, s) {
      Log.e('onay', 'kabul kaydedilemedi', e, s);
    }
    startConsentGatedServices();
  }

  /// Ayarlar > Reklam İzni: izni ver / geri çek (GDPR). Reklam SDK'sına da iletilir.
  Future<void> setAdConsent(bool value) async {
    _adConsent = value;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kAds, value);
    } catch (e, s) {
      Log.e('onay', 'reklam izni kaydedilemedi', e, s);
    }
    unawaited(LevelPlayHub.I.applyConsent(value));
    Telemetry.event('ad_consent_changed', {'on': value ? 1 : 0});
  }

  /// Onay varsa (ya da yeni verildiyse) bir kez çalışır: analitik, zorunlu güncelleme kontrolü, reklam SDK'sı.
  void startConsentGatedServices() {
    if (_started || !_accepted) return;
    _started = true;
    Log.i('onay', 'onay sonrası servisler başlıyor');
    unawaited(Telemetry.init());
    // Play'de yeni sürüm varsa tam ekran güncelleme penceresi çıkar (yalnız Play'den kurulu sürümde).
    unawaited(AppUpdateService.I.check());
    // Reklam SDK'sı: AB/AEA/BK'de GDPR izni init'ten ÖNCE iletilir (bkz. LevelPlayHub.init).
    unawaited(LevelPlayHub.I.init());
  }

  static const Set<String> _gdprRegions = {
    // AB üyeleri
    'AT', 'BE', 'BG', 'HR', 'CY', 'CZ', 'DK', 'EE', 'FI', 'FR', 'DE', 'GR', 'HU', 'IE',
    'IT', 'LV', 'LT', 'LU', 'MT', 'NL', 'PL', 'PT', 'RO', 'SK', 'SI', 'ES', 'SE',
    // AEA + Birleşik Krallık + İsviçre
    'IS', 'LI', 'NO', 'GB', 'UK', 'CH',
  };

  static bool isGdprCountry(String cc) => _gdprRegions.contains(cc.toUpperCase());

  /// Oyuncunun ülkesini internetten bulur (bkz. [RegionService]): Cloudflare trace -> Worker /geo.
  /// Açılışta, onay penceresi ve reklam SDK'sından ÖNCE bir kez çağrılır. Bulunamazsa [showGdpr]
  /// telefon diline bakar. Toplam en fazla 5 sn bekler, hata fırlatmaz.
  Future<void> resolveRegion({Future<String?> Function()? lookup}) async {
    try {
      final cc = await (lookup ?? RegionService.resolveCountry)().timeout(const Duration(seconds: 5));
      if (cc != null && cc.isNotEmpty) {
        _inGdprRegion = isGdprCountry(cc);
        Log.i('onay', 'bölge: $cc -> GDPR kutusu=${_inGdprRegion!}');
      } else {
        Log.w('onay', 'bölge bulunamadı, telefon diline bakılacak');
      }
    } catch (e) {
      Log.w('onay', 'bölge çözülemedi: $e');
    }
  }

  /// İnternetten bulunan ülke AB/AEA/BK/İsviçre ise açık GDPR izin kutusu gösterilir ve Ayarlar'da
  /// "Reklam İzni" düğmesi çıkar. Ülke bulunamadıysa telefonun dil/bölge ayarına bakılır; o da yoksa
  /// (temkinli) gösterilir.
  bool get showGdpr {
    final r = _inGdprRegion;
    if (r != null) return r;
    final cc = ui.PlatformDispatcher.instance.locale.countryCode;
    if (cc == null || cc.isEmpty) return true;
    return isGdprCountry(cc);
  }

  /// Yalnız testler için.
  @visibleForTesting
  void debugReset({bool accepted = false, bool adConsent = false, bool? gdprRegion}) {
    _accepted = accepted;
    _adConsent = adConsent;
    _inGdprRegion = gdprRegion;
    _started = true; // testte gerçek servisler başlamasın
  }
}
