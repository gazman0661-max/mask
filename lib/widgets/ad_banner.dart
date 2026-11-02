import 'dart:async';
import 'package:flutter/material.dart';
import 'package:unity_levelplay_mediation/unity_levelplay_mediation.dart';
import '../config.dart';
import '../diagnostics/app_log.dart';
import '../services/banner_gate.dart';
import '../services/levelplay_service.dart';
import 'ad_banner_placeholder.dart';

/// Üst banner şeridinin içeriği. Yerleşimi [ResponsiveShell] yapar (320x50, oyun alanının dışında).
class AdBannerStrip {
  /// [AppConfig.adMode]: `mock` sahte şerit, `levelplay` gerçek reklam (kimlikler doluysa), `off` reklamsız.
  static Widget? fromConfig() {
    switch (AppConfig.adMode) {
      case 'mock':
        return const _HideWhileRewarded(child: AdBannerPlaceholder());
      case 'levelplay':
        return AppConfig.levelPlayBannerOn ? const LevelPlayBanner() : null;
      default:
        return null;
    }
  }
}

/// Ödüllü reklam izlenirken içeriği gizler ([BannerGate]); şerit yerinde kalır.
class _HideWhileRewarded extends StatelessWidget {
  final Widget child;
  const _HideWhileRewarded({required this.child});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: BannerGate.hidden,
        builder: (_, hidden, c) => hidden ? const SizedBox.shrink() : c!,
        child: child,
      );
}

/// Gerçek LevelPlay banner (320x50). SDK hazır olana kadar ve yüklenemezse şerit boş kalır
/// (oyunu etkilemez), yüklenemezse 60 sn sonra yeniden dener. Ödüllü reklam sürerken
/// ([BannerGate]) yenilenmesi durur; gerçek ödüllü reklam zaten tam ekran açılır, banner'ın altında kalır.
class LevelPlayBanner extends StatefulWidget {
  const LevelPlayBanner({super.key});

  @override
  State<LevelPlayBanner> createState() => _LevelPlayBannerState();
}

class _LevelPlayBannerState extends State<LevelPlayBanner> implements LevelPlayBannerAdViewListener {
  final _bannerKey = GlobalKey<LevelPlayBannerAdViewState>();
  Timer? _retry;
  bool _alive = true;

  @override
  void initState() {
    super.initState();
    LevelPlayHub.I.ready.addListener(_rebuild);
    BannerGate.hidden.addListener(_gateChanged);
    unawaited(LevelPlayHub.I.init()); // kimlikler boşsa hiçbir şey yapmaz
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  // Ödüllü reklam başlayınca yenilemeyi durdur, bitince sürdür.
  void _gateChanged() {
    final s = _bannerKey.currentState;
    if (s == null) return;
    try {
      if (BannerGate.hidden.value) {
        s.pauseAutoRefresh();
      } else {
        s.resumeAutoRefresh();
      }
    } catch (e) {
      Log.w('reklam', 'banner duraklatma/sürdürme hatası: $e');
    }
  }

  void _load() => _bannerKey.currentState?.loadAd();

  @override
  void dispose() {
    _alive = false;
    _retry?.cancel();
    LevelPlayHub.I.ready.removeListener(_rebuild);
    BannerGate.hidden.removeListener(_gateChanged);
    try {
      _bannerKey.currentState?.destroy();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!LevelPlayHub.I.ready.value) return const SizedBox.shrink();
    final size = LevelPlayAdSize.BANNER; // 320x50
    return SizedBox(
      width: size.width.toDouble(),
      height: size.height.toDouble(),
      child: LevelPlayBannerAdView(
        key: _bannerKey,
        adUnitId: AppConfig.levelPlayBannerId,
        adSize: size,
        listener: this,
        onPlatformViewCreated: _load,
      ),
    );
  }

  // --- LevelPlayBannerAdViewListener
  @override
  void onAdLoaded(LevelPlayAdInfo adInfo) => Log.i('reklam', 'banner YÜKLENDİ');

  @override
  void onAdLoadFailed(LevelPlayAdError error) {
    Log.w('reklam', 'banner YÜKLENEMEDİ: $error');
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 60), () {
      if (_alive) _load();
    });
  }

  @override
  void onAdDisplayed(LevelPlayAdInfo adInfo) {}

  @override
  void onAdDisplayFailed(LevelPlayAdInfo adInfo, LevelPlayAdError error) =>
      Log.w('reklam', 'banner GÖSTERİM BAŞARISIZ: $error');

  @override
  void onAdClicked(LevelPlayAdInfo adInfo) {}

  @override
  void onAdExpanded(LevelPlayAdInfo adInfo) {}

  @override
  void onAdCollapsed(LevelPlayAdInfo adInfo) {}

  @override
  void onAdLeftApplication(LevelPlayAdInfo adInfo) {}
}
