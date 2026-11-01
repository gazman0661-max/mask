import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../config.dart';
import '../diagnostics/app_log.dart';
import '../services/banner_gate.dart';
import 'ad_banner_placeholder.dart';

/// Üst banner şeridinin içeriği. Yerleşimi [ResponsiveShell] yapar (320x50, oyun alanının dışında).
class AdBannerStrip {
  /// `--dart-define=ADS=...` değerine göre: `mock` sahte şerit, `admob` gerçek reklam, diğerleri reklamsız.
  static Widget? fromConfig() {
    switch (AppConfig.adMode) {
      case 'mock':
        return const _HideWhileRewarded(child: AdBannerPlaceholder());
      case 'admob':
        return const AdMobBanner();
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

/// Gerçek AdMob banner (320x50). Yüklenemezse şerit boş kalır ve 60 sn sonra yeniden dener;
/// yüklenmeden hiçbir şey çizilmez (oyunu etkilemez).
class AdMobBanner extends StatefulWidget {
  const AdMobBanner({super.key});

  @override
  State<AdMobBanner> createState() => _AdMobBannerState();
}

class _AdMobBannerState extends State<AdMobBanner> {
  static Future<InitializationStatus>? _init;

  BannerAd? _ad;
  bool _loaded = false;
  Timer? _retry;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _init ??= MobileAds.instance.initialize();
      await _init;
    } catch (e) {
      Log.w('reklam', 'AdMob başlatılamadı: $e');
      _scheduleRetry();
      return;
    }
    if (!mounted) return;
    final ad = BannerAd(
      adUnitId: AppConfig.bannerUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (a) {
          if (!mounted) {
            a.dispose();
            return;
          }
          setState(() => _loaded = true);
        },
        onAdFailedToLoad: (a, error) {
          a.dispose();
          Log.w('reklam', 'banner yüklenemedi: ${error.code} ${error.message}');
          if (!mounted) return;
          setState(() {
            _ad = null;
            _loaded = false;
          });
          _scheduleRetry();
        },
      ),
    );
    _ad = ad;
    await ad.load();
  }

  void _scheduleRetry() {
    _retry?.cancel();
    if (!mounted) return;
    _retry = Timer(const Duration(seconds: 60), _load);
  }

  @override
  void dispose() {
    _retry?.cancel();
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_loaded || ad == null) return const SizedBox.shrink();
    // Ödüllü reklam sürerken gizle; reklam nesnesi atılmaz, bitince aynı banner geri gelir.
    return ValueListenableBuilder<bool>(
      valueListenable: BannerGate.hidden,
      builder: (_, hidden, __) => hidden ? const SizedBox.shrink() : AdWidget(ad: ad),
    );
  }
}
