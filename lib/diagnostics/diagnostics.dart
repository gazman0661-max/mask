import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'app_log.dart';

/// Sayfa geçişlerini (açılış/kapanış/değişim) ve diyalogları günlüğe yazar.
class LogNavigatorObserver extends NavigatorObserver {
  static String _n(Route<dynamic>? r) =>
      r == null ? '-' : (r.settings.name ?? r.runtimeType.toString());

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      Log.i('sayfa', 'AÇILDI ${_n(route)}  (altında: ${_n(previousRoute)})');

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      Log.i('sayfa', 'KAPANDI ${_n(route)}  (dönülen: ${_n(previousRoute)})');

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      Log.i('sayfa', 'DEĞİŞTİ ${_n(oldRoute)} → ${_n(newRoute)}');

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      Log.i('sayfa', 'KALDIRILDI ${_n(route)}');
}

/// Uygulama arka plana gitti mi, bellek baskısı, ekran ölçüsü değişimi.
class AppLifecycleLogger with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    Log.i('yaşam', 'uygulama durumu: ${state.name}');
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      Log.flush();
    }
  }

  @override
  void didHaveMemoryPressure() =>
      Log.w('bellek', 'sistem bellek baskısı bildirdi');

  @override
  void didChangeMetrics() {
    try {
      final v = WidgetsBinding.instance.platformDispatcher.views.first;
      Log.d('ekran',
          'ölçüler değişti: ${v.physicalSize.width.round()}x${v.physicalSize.height.round()} px, dpr=${v.devicePixelRatio.toStringAsFixed(2)}');
    } catch (_) {}
  }
}

/// 50 ms üzeri süren kareleri "yavas kare" olarak yazar.
void _installJankLogger() {
  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      final total = t.totalSpan.inMilliseconds;
      if (total >= 50) {
        Log.w('jank',
            'yavas kare: toplam=${total}ms build=${t.buildDuration.inMilliseconds}ms raster=${t.rasterDuration.inMilliseconds}ms');
      }
    }
  });
}

/// Uygulamayı tüm hata yakalayıcılar kurulu olarak başlatır:
/// Flutter hataları, async/platform hataları, zone hataları, çizim hataları.
Future<void> bootstrapDiagnostics(Future<void> Function() body) async {
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Log.init();

    FlutterError.onError = (d) {
      Log.e('flutter', '${d.library ?? 'flutter'}: ${d.exceptionAsString()}',
          null, d.stack);
      FlutterError.presentError(d);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      Log.e('platform', 'yakalanmayan hata', error, stack);
      return true;
    };
    final original = ErrorWidget.builder;
    ErrorWidget.builder = (details) {
      Log.e('widget', 'çizim hatası: ${details.exceptionAsString()}', null,
          details.stack);
      return original(details);
    };

    WidgetsBinding.instance.addObserver(AppLifecycleLogger());
    _installJankLogger();

    Log.i('app', '=== 101 Okey başladı === önceki oturum kaydı: ${Log.previous.isEmpty ? 'yok' : '${Log.previous.length} karakter'}');
    await body();
  }, (error, stack) {
    Log.e('zone', 'yakalanmayan zone hatası', error, stack);
  });
}
