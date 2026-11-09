import 'dart:math' as math;
import '../diagnostics/app_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
///
/// SATIR İÇİ MOD: bir ekran kendi başlığında [BannerSlotMarker] ile banner'a yer ayırırsa o ekranda ayrı şerit
/// kalkar, oyun alanı ekranın tamamını kullanır ve banner gerçek boyutuyla (320x50) tam o boşluğa biner.
/// Marker'ı olmayan ekranlar eskisi gibi üstteki şeritle çalışır. Banner iki modda da aynı Stack konumunda
/// durur, bu yüzden mod değişince reklam yeniden yüklenmez. Hangi ekranın marker'ı geçerli olacağını
/// [BannerRouteObserver] bulur (en üstteki sayfa; diyaloglar sayılmaz).
class ResponsiveShell extends StatelessWidget {
  final Widget child;
  final Widget? banner;
  const ResponsiveShell({super.key, required this.child, this.banner});

  /// Bir ekranın banner için ayrılmış boşluğu (marker) var mı? Varsa şerit kalkar.
  static final ValueNotifier<bool> inlineBanner = ValueNotifier<bool>(false);

  /// Banner'ı tamamen gizleyen ekranlar (açılış, giriş) için: true iken şerit de banner da yoktur.
  static final ValueNotifier<bool> bannerHidden = ValueNotifier<bool>(false);
  static final Set<Object> _hiders = <Object>{};

  /// [owner] banner'ı gizlemek istiyor. Ağaç kurulurken çağrılmamalı (kare sonunda ya da olay içinde çağır).
  static void hideBanner(Object owner) {
    _hiders.add(owner);
    if (!bannerHidden.value) bannerHidden.value = true;
  }

  /// [owner] artık gizlemek istemiyor; kimse kalmadıysa banner geri gelir.
  static void showBanner(Object owner) {
    _hiders.remove(owner);
    final hidden = _hiders.isNotEmpty;
    if (bannerHidden.value != hidden) bannerHidden.value = hidden;
  }

  /// Marker'ın ekran koordinatındaki merkezi (mantıksal piksel). Banner'ın merkezi buraya konur.
  static final ValueNotifier<Offset?> bannerCenter = ValueNotifier<Offset?>(null);
  static Object? _owner;

  /// Yalnız testler için: şu anki sahip.
  static Object? get debugOwnerForTest => _owner;

  /// Aktif ekranın marker'ı konumunu bildirir (her karede çağrılabilir; değişmediyse bir şey yapmaz).
  static void publish(Object owner, Offset center) {
    _owner = owner;
    if (!inlineBanner.value) inlineBanner.value = true;
    final c = bannerCenter.value;
    if (c == null || (c - center).distance > 0.5) bannerCenter.value = center;
  }

  /// Marker'ın sahibi çekilirse şeride dönülür. Başkası devraldıysa dokunmaz.
  static void release(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    inlineBanner.value = false;
    bannerCenter.value = null;
  }

  /// Masa ekranı üst çubuğunun en az yüksekliği (tasarım birimi).
  static const double barMinHeight = 36;

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

    final body = ValueListenableBuilder<bool>(
      valueListenable: bannerHidden,
      builder: (context, hidden, _) => ValueListenableBuilder<bool>(
      valueListenable: inlineBanner,
      builder: (context, wantInline, _) => LayoutBuilder(builder: (context, box) {
        final pad = insets;
        final hasBanner = banner != null && !portrait && !hidden;
        final inline = hasBanner && wantInline;
        final bh = (hasBanner && !inline) ? bannerHeight : 0.0;
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
              child: BannerSlot(available: hasBanner, scale: s, child: child),
            ),
          ),
        );
        final gameBox = Positioned(left: pad.left, top: pad.top + bh, width: aw, height: ah, child: game);
        if (!hasBanner) return Stack(children: [gameBox]);
        // Banner: ekranın marker'ı varsa orada (merkezi marker'ın merkezi), yoksa üstteki şeritte.
        return ValueListenableBuilder<Offset?>(
          valueListenable: bannerCenter,
          child: gameBox,
          builder: (context, c, gameChild) {
            var left = pad.left + (aw - bannerWidth) / 2;
            var top = pad.top;
            if (inline && c != null) {
              left = c.dx - bannerWidth / 2;
              top = c.dy - bannerHeight / 2;
            }
            // Ekran dışına taşmasın
            final maxLeft = math.max(pad.left, box.maxWidth - pad.right - bannerWidth);
            final maxTop = math.max(0.0, box.maxHeight - bannerHeight);
            left = left.clamp(pad.left, maxLeft).toDouble();
            top = top.clamp(0.0, maxTop).toDouble();
            return Stack(children: [
              gameChild!,
              Positioned(
                left: left,
                top: top,
                width: bannerWidth,
                height: bannerHeight,
                child: SizedBox(key: const ValueKey('ad-banner-slot'), child: banner),
              ),
            ]);
          },
        );
      }),
      ),
    );

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

/// Ekranlara ekran ölçeğini ve "bu cihazda banner var mı" bilgisini taşır.
/// [scale]: tasarım biriminden gerçek piksele çarpan; 320x50'lik banner tasarım biriminde 320/scale x 50/scale yer kaplar.
class BannerSlot extends InheritedWidget {
  final bool available;
  final double scale;
  const BannerSlot({super.key, required this.available, required this.scale, required super.child});

  static BannerSlot? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<BannerSlot>();

  /// Ekranın başlığında banner için ayrılacak boşluk (tasarım birimi).
  double get slotWidth => ResponsiveShell.bannerWidth / scale;
  double get slotHeight => ResponsiveShell.bannerHeight / scale;

  @override
  bool updateShouldNotify(BannerSlot old) => old.available != available || old.scale != scale;
}

/// Ekranın başlığında banner'ın duracağı boş yer. Tam banner boyutunda (tasarım biriminde) yer tutar;
/// konumunu her karede kabuğa bildirir, banner onun üstüne biner. Yalnız en üstteki sayfanın marker'ı
/// geçerlidir. Cihazda banner yoksa (ya da testte) hiç yer tutmaz.
class BannerSlotMarker extends StatefulWidget {
  const BannerSlotMarker({super.key});

  /// Marker'ın gerçekten yer tutup tutmayacağını ekranlar buradan öğrenir (başlık düzenini seçmek için).
  static bool isAvailable(BuildContext context) => BannerSlot.maybeOf(context)?.available ?? false;

  @override
  State<BannerSlotMarker> createState() => _BannerSlotMarkerState();
}

class _BannerSlotMarkerState extends State<BannerSlotMarker> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => _sync());

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  void _sync() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    final active = route == null || BannerRouteObserver.isTop(route);
    if (!active) {
      ResponsiveShell.release(this);
      return;
    }
    final ro = context.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) return;
    ResponsiveShell.publish(this, ro.localToGlobal(ro.size.center(Offset.zero)));
  }

  @override
  void dispose() {
    _ticker.dispose();
    // Ağaç kilitliyken dinleyicileri tetiklemeyelim.
    WidgetsBinding.instance.addPostFrameCallback((_) => ResponsiveShell.release(this));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slot = BannerSlot.maybeOf(context);
    if (slot == null || !slot.available) return const SizedBox.shrink();
    return SizedBox(width: slot.slotWidth, height: slot.slotHeight);
  }
}

/// En üstteki SAYFA rotasını izler (diyaloglar/menüler sayılmaz), böylece bir ekranın üstünde diyalog
/// açılınca banner şeride dönmez. MaterialApp.navigatorObservers'a eklenmeli.
class BannerRouteObserver extends NavigatorObserver {
  static final List<Route<dynamic>> _pages = [];

  static bool isTop(Route<dynamic> r) => _pages.isNotEmpty && identical(_pages.last, r);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) _pages.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _pages.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _pages.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _pages.indexOf(oldRoute);
    if (i >= 0) {
      _pages.removeAt(i);
      if (newRoute is PageRoute) _pages.insert(i, newRoute);
    } else if (newRoute is PageRoute) {
      _pages.add(newRoute);
    }
  }
}
