import 'dart:async';
import 'package:flutter/foundation.dart'
    show ValueNotifier, defaultTargetPlatform, kIsWeb, kReleaseMode, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:unity_levelplay_mediation/unity_levelplay_mediation.dart';
import '../config.dart';
import '../diagnostics/app_log.dart';
import '../widgets/game_popup.dart';
import '../widgets/lobby_widgets.dart' show CandyKind;
import 'ad_service.dart';
import 'legal_consent_service.dart';
import 'banner_gate.dart';

/// Unity LevelPlay (ironSource) mediation. Worlds Merge oyunuyla AYNI eklenti/adaptör sürümleri
/// (bkz. pubspec.yaml ve android/app/build.gradle). Bu oyunda yalnız BANNER + ÖDÜLLÜ reklam vardır;
/// GEÇİŞ (interstitial) reklamı YOKTUR.
///
/// Kimlikler koda yazılmaz: `--dart-define=LEVELPLAY_APP_KEY / LEVELPLAY_BANNER_ID / LEVELPLAY_REWARDED_ID`
/// ([AppConfig]). Boşken buradaki hiçbir şey çalışmaz, reklam SAHTE kalır ([MockAdService] + yer tutucu şerit).

bool get _androidOnly => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// SDK'yı bir kez başlatır; banner ve ödüllü reklam bunun hazır olmasını bekler.
class LevelPlayHub {
  LevelPlayHub._();
  static final LevelPlayHub I = LevelPlayHub._();

  /// `true` = init başarılı, reklam yüklenebilir.
  final ValueNotifier<bool> ready = ValueNotifier<bool>(false);

  bool _started = false;
  Timer? _retry;
  String? lastError;

  /// Kimlikler boşsa ya da Android değilse hiçbir şey yapmaz. BEKLENMEZ, hata fırlatmaz.
  Future<void> init() async {
    if (_started || ready.value) return;
    // Kullanıcı Hizmet Şartları/Gizlilik (+ AB'de reklam izni) penceresini kabul etmeden SDK başlamaz.
    if (!LegalConsentService.I.accepted) return;
    if (AppConfig.levelPlayAppKey.isEmpty || !_androidOnly) return;
    _started = true;
    try {
      Log.i('reklam', 'LevelPlay.init başlıyor');
      // Gizlilik ayarları init'ten ÖNCE verilmelidir (AB/AEA/BK'de GDPR izni).
      if (LegalConsentService.I.showGdpr) {
        try {
          await LevelPlayPrivacySettings.setGDPRConsent(LegalConsentService.I.adConsent);
        } catch (e) {
          Log.w('reklam', 'GDPR bayrağı verilemedi: $e');
        }
      }
      if (!kReleaseMode) {
        try {
          await LevelPlay.setAdaptersDebug(true);
          LevelPlay.validateIntegration(); // beklenmez; sonuç Logcat'te
        } catch (e) {
          Log.w('reklam', 'LevelPlay debug açılamadı: $e');
        }
      }
      final request = LevelPlayInitRequest.builder(AppConfig.levelPlayAppKey).build();
      await LevelPlay.init(initRequest: request, initListener: _InitListener(this));
    } catch (e) {
      _failed(e.toString());
    }
  }

  /// Ayarlar > Reklam İzni: izin değişince SDK'ya iletir (SDK henüz başlamadıysa init'te okunur).
  Future<void> applyConsent(bool value) async {
    if (AppConfig.levelPlayAppKey.isEmpty || !_androidOnly) return;
    try {
      await LevelPlayPrivacySettings.setGDPRConsent(value);
    } catch (e) {
      Log.w('reklam', 'GDPR izni iletilemedi: $e');
    }
  }

  void _success() {
    Log.i('reklam', 'LevelPlay init tamam');
    lastError = null;
    ready.value = true;
  }

  void _failed(String error) {
    _started = false; // tekrar denenebilsin
    lastError = error;
    Log.w('reklam', 'LevelPlay init hatası: $error');
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 60), () => unawaited(init()));
  }
}

class _InitListener implements LevelPlayInitListener {
  _InitListener(this._hub);
  final LevelPlayHub _hub;

  @override
  void onInitSuccess(LevelPlayConfiguration configuration) => _hub._success();

  @override
  void onInitFailed(LevelPlayInitError error) => _hub._failed(error.toString());
}

/// Gerçek ödüllü reklam. [showRewarded] reklam SONUNA kadar izlenirse (ödül hakkı doğarsa) true,
/// yarıda kapatılırsa / reklam yoksa false döner; reklam yoksa bedava ödül VERİLMEZ.
///
/// DİKKAT: ödül şimdilik istemcinin "izledim" bilgisine dayanır. Canlıdan önce LevelPlay'in sunucudan
/// sunucuya (server-to-server) ödüllü geri çağırması Worker'a bağlanmalı (bkz. YAPILACAKLAR.md).
class LevelPlayAdService extends AdService {
  LevelPlayAdService() {
    LevelPlayHub.I.ready.addListener(_onHubReady);
    _onHubReady();
  }

  LevelPlayRewardedAd? _ad;
  Completer<bool>? _pending;
  bool _rewarded = false, _closed = false, _shown = false;
  Timer? _notShownWatchdog, _closeGrace, _retry;
  int _retries = 0;

  void _onHubReady() {
    if (!LevelPlayHub.I.ready.value || _ad != null) return;
    if (AppConfig.levelPlayRewardedId.isEmpty) return;
    try {
      _ad = LevelPlayRewardedAd(adUnitId: AppConfig.levelPlayRewardedId)
        ..setListener(_RewardedListener(this));
      unawaited(_preload());
    } catch (e) {
      Log.w('reklam', 'ödüllü reklam nesnesi kurulamadı: $e');
    }
  }

  Future<void> _preload() async {
    final ad = _ad;
    if (ad == null) return;
    try {
      if (await ad.isAdReady()) return;
      await ad.loadAd();
    } catch (e) {
      Log.w('reklam', 'ödüllü yüklenemedi: $e');
    }
  }

  // Yükleme başarısızsa 15/30/60/120 sn aralıkla tekrar dene.
  void _scheduleReload() {
    _retry?.cancel();
    final step = _retries > 3 ? 3 : _retries;
    _retries++;
    _retry = Timer(Duration(seconds: 15 * (1 << step)), () => unawaited(_preload()));
  }

  /// Ödüllü reklam şu an gösterilmeye hazır mı?
  Future<bool> isReady() async {
    final ad = _ad;
    if (ad == null) return false;
    try {
      return await ad.isAdReady();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> showRewarded(BuildContext context) async {
    final ad = _ad;
    if (ad == null || !await isReady()) {
      unawaited(_preload());
      if (context.mounted) await _noAdPopup(context);
      return false;
    }
    _rewarded = false;
    _closed = false;
    _shown = false;
    final c = Completer<bool>();
    _pending = c;
    // Banner'ın yenilenmesi reklam sürerken durur (gerçek reklam zaten tam ekran, banner'ın altında kalır).
    final granted = await BannerGate.whileRewarded(() async {
      try {
        await ad.showAd();
      } catch (e) {
        Log.w('reklam', 'ödüllü gösterilemedi: $e');
        _finish(false);
      }
      // 15 sn içinde "gösterildi" gelmezse takılı kalma.
      _notShownWatchdog = Timer(const Duration(seconds: 15), () {
        if (!_shown) {
          Log.w('reklam', 'ödüllü 15 sn içinde gösterilmedi (watchdog)');
          _finish(false);
        }
      });
      return c.future;
    });
    unawaited(_preload());
    return granted;
  }

  void _finish(bool result) {
    _notShownWatchdog?.cancel();
    _closeGrace?.cancel();
    final c = _pending;
    if (c != null && !c.isCompleted) c.complete(result);
  }

  // --- LevelPlay olayları
  void _loaded() {
    _retries = 0;
    Log.i('reklam', 'ödüllü YÜKLENDİ');
  }

  void _loadFailed(LevelPlayAdError error) {
    Log.w('reklam', 'ödüllü YÜKLENEMEDİ (doluluk yok / ağ): $error');
    _scheduleReload();
  }

  void _displayed() {
    _shown = true;
    _notShownWatchdog?.cancel();
  }

  void _displayFailed(LevelPlayAdError error) {
    Log.w('reklam', 'ödüllü GÖSTERİM BAŞARISIZ: $error');
    _finish(false);
  }

  void _gotReward() {
    _rewarded = true;
    // Dokümana göre onAdRewarded, onAdClosed'dan SONRA da gelebilir: kapanmışsa hemen bitir.
    if (_closed) _finish(true);
  }

  void _onClosed() {
    _closed = true;
    if (_rewarded) {
      _finish(true);
    } else {
      // Ödül olayı kapanıştan hemen sonra gelebilir; kısa süre bekle, gelmezse izlenmedi say.
      _closeGrace?.cancel();
      _closeGrace = Timer(const Duration(seconds: 2), () => _finish(_rewarded));
    }
  }

  Future<void> _noAdPopup(BuildContext context) => showGamePopup<void>(
        context,
        builder: (ctx) => GamePopup(
          title: 'REKLAM YOK',
          icon: Icons.videocam_off,
          maxWidth: 380,
          onClose: () => Navigator.of(ctx).pop(),
          actions: [
            PopupButton(
                label: 'TAMAM',
                kind: CandyKind.green,
                width: 150,
                height: 46,
                onTap: () => Navigator.of(ctx).pop()),
          ],
          child: const Text('Şu an gösterilecek reklam bulunamadı. Biraz sonra tekrar dene.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.white70)),
        ),
      );
}

class _RewardedListener implements LevelPlayRewardedAdListener {
  _RewardedListener(this._s);
  final LevelPlayAdService _s;

  @override
  void onAdLoaded(LevelPlayAdInfo adInfo) => _s._loaded();

  @override
  void onAdLoadFailed(LevelPlayAdError error) => _s._loadFailed(error);

  @override
  void onAdDisplayed(LevelPlayAdInfo adInfo) => _s._displayed();

  @override
  void onAdDisplayFailed(LevelPlayAdError error, LevelPlayAdInfo adInfo) => _s._displayFailed(error);

  @override
  void onAdClicked(LevelPlayAdInfo adInfo) {}

  @override
  void onAdClosed(LevelPlayAdInfo adInfo) => _s._onClosed();

  @override
  void onAdInfoChanged(LevelPlayAdInfo adInfo) {}

  @override
  void onAdRewarded(LevelPlayReward reward, LevelPlayAdInfo adInfo) => _s._gotReward();
}

/// Ayara göre ödüllü reklam servisi: kimlikler doluysa gerçek LevelPlay, değilse sahte.
AdService createAdService() {
  if (AppConfig.adMode == 'levelplay' && AppConfig.levelPlayRewardedOn && _androidOnly) {
    return LevelPlayAdService();
  }
  return const MockAdService();
}
