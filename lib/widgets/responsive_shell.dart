import 'dart:math' as math;
import '../diagnostics/app_log.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Tüm uygulamayı her ekran boyutuna uyduran kabuk.
/// - Hep YATAY: telefon dikeyse içerik 90° döndürülür.
/// - Tasarım alanı en az 700x360; ekran oranına göre bu alan uzar,
///   sonra ekrana oranlı (bozulmadan) ölçeklenir. Taşma olmaz.
/// - Sistem yazı boyutu (ve "kalın yazı") oyun arayüzünü bozmasın diye sabitlenir.
/// - Çentik/kesik alanı güvenli alan olarak ayrılır; arka plan kenarlara kadar dolar.
///
/// [banner] verilirse (320x50) en üstte, oyun alanının DIŞINDA kendi şeridinde durur: hiçbir ekranın
/// üstüne binmez, oyun alanı yalnızca bu şerit kadar küçülür (bozulmadan). Şerit yer tutmaya her zaman
/// devam eder, böylece reklam geç yüklenince ya da yenilenince oyun alanı kaymaz. Reklam SDK'sı
/// gerçek piksel boyutunda çizilmeli, o yüzden ölçeklenen alanın içine konmaz. Dikeyde (döndürülmüş
/// içerik) gösterilmez.
class ResponsiveShell extends StatelessWidget {
  final Widget child;
  final Widget? banner;
  const ResponsiveShell({super.key, required this.child, this.banner});

  static const double minW = 700, minH = 360;
  static const double bannerWidth = 320, bannerHeight = 50;

  static String _lastInfo = '', _lastScale = '';

  static void _logMetrics(MediaQueryData mq, bool portrait) {
    final info =
        'Ekran: ${mq.size.width.toStringAsFixed(0)}x${mq.size.height.toStringAsFixed(0)} dp, dpr=${mq.devicePixelRatio.toStringAsFixed(2)}, ${portrait ? 'DİKEY (içerik döndürülüyor)' : 'yatay'}, güvenli alan=${mq.padding}';
    if (info != _lastInfo) {
      _lastInfo = info;
      Log.deviceInfo = info;
      Log.i('ekran', info);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final portrait = mq.size.height > mq.size.width;
    _logMetrics(mq, portrait);

    // Dikeyde içerik 90° (saat yönü) döndürülür: cihazın üstü içeriğin soluna, sağı içeriğin üstüne düşer.
    final insets = portrait
        ? EdgeInsets.fromLTRB(mq.padding.top, mq.padding.right, mq.padding.bottom, mq.padding.left)
        : mq.padding;

    final body = LayoutBuilder(builder: (context, box) {
      final pad = insets;
      final bh = (banner != null && !portrait) ? bannerHeight : 0.0;
      final aw = box.maxWidth - pad.horizontal;
      final ah = box.maxHeight - pad.vertical - bh;
      // İlk karede / pencere geçişlerinde ölçü 0 gelebilir; bölme hatası olmasın.
      if (!aw.isFinite || !ah.isFinite || aw < 1 || ah < 1) {
        return const SizedBox.shrink();
      }
      final s = math.min(ah / minH, aw / minW);
      final w = aw / s, h = ah / s;
      final sc = 'ölçek=${s.toStringAsFixed(2)} tasarım alanı=${w.round()}x${h.round()}';
      if (sc != _lastScale) {
        _lastScale = sc;
        Log.i('ekran', sc);
      }
      final game = FittedBox(
        fit: BoxFit.fill,
        child: SizedBox(
          width: w,
          height: h,
          child: MediaQuery(
            data: mq.copyWith(
              size: Size(w, h),
              padding: EdgeInsets.zero,
              viewPadding: EdgeInsets.zero,
              viewInsets: EdgeInsets.zero,
              textScaler: TextScaler.noScaling,
              boldText: false,
            ),
            child: child,
          ),
        ),
      );
      return Padding(
        padding: pad,
        child: bh == 0
            ? game
            : Column(children: [
                SizedBox(
                  width: aw,
                  height: bh,
                  child: Center(
                    child: SizedBox(
                        key: const ValueKey('ad-banner-slot'),
                        width: bannerWidth,
                        height: bannerHeight,
                        child: banner),
                  ),
                ),
                SizedBox(width: aw, height: ah, child: game),
              ]),
      );
    });

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => Log.d(
          'dokunma', 'dokunuş (${e.position.dx.round()}, ${e.position.dy.round()})'),
      child: ColoredBox(
        color: AppColors.bg,
        child: portrait ? RotatedBox(quarterTurns: 1, child: body) : body,
      ),
    );
  }
}
