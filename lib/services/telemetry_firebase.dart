import 'dart:async';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'telemetry.dart';

/// Firebase Analytics + Crashlytics. Web/FlutLab önizlemede ve google-services.json yoksa kendini kapatır
/// (init hata fırlatır, [Telemetry.init] yakalayıp Noop'a döner).
class FirebaseTelemetry implements TelemetryBackend {
  @override
  Future<void> init() async {
    if (kIsWeb) throw UnsupportedError('web önizlemede kapalı');
    await Firebase.initializeApp();
    // Hata raporu yalnız yayın/profil derlemesinde (geliştirme çökmeleri panele karışmasın).
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
  }

  @override
  void event(String name, [Map<String, Object>? params]) {
    unawaited(FirebaseAnalytics.instance
        .logEvent(name: name, parameters: params)
        .catchError((Object e) => debugPrint('analytics: $e')));
  }

  @override
  void error(Object error, StackTrace? stack, {bool fatal = false}) {
    unawaited(FirebaseCrashlytics.instance
        .recordError(error, stack, fatal: fatal)
        .catchError((Object e) => debugPrint('crashlytics: $e')));
  }
}
