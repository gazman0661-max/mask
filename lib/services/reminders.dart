import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../diagnostics/app_log.dart';

/// Tek bir planlı hatırlatma.
class PlannedReminder {
  final int id;
  final DateTime at;
  final String title;
  final String body;
  const PlannedReminder(this.id, this.at, this.title, this.body);
}

const int kRemDaily = 1;
const int kRemIdle2 = 2;
const int kRemIdle5 = 3;
const int kRemAd = 4;

/// Hangi hatırlatma ne zaman gösterilecek (saf hesap; eklentiye bağlı değil, testte doğrudan çağrılır).
///
/// - Günlük hediye: bugün alınmadıysa bugün 19:00 (geçtiyse yarın 19:00), alındıysa yarın 19:00.
/// - Uzun süre girmeyene: 2. ve 5. günün 20:00'sinde "Masalar seni bekliyor".
/// - Reklam çipi: bekleme süresi bitince ([adReadyAt] gelecekteyse).
List<PlannedReminder> planReminders({
  required DateTime now,
  required bool dailyClaimedToday,
  DateTime? adReadyAt,
}) {
  DateTime day(int plus, int hour) => DateTime(now.year, now.month, now.day + plus, hour);
  var daily = day(0, 19);
  if (dailyClaimedToday || !daily.isAfter(now)) daily = day(1, 19);
  return [
    PlannedReminder(kRemDaily, daily, 'Günlük hediyeni aldın mı? 🎁', 'Çiplerin seni bekliyor, serini bozma!'),
    PlannedReminder(kRemIdle2, day(2, 20), 'Masalar seni bekliyor 🃏', "101'e dön! Eğlenceyi kaçırma"),
    PlannedReminder(kRemIdle5, day(5, 20), 'Masalar seni bekliyor 🃏', "101'e dön! Eğlenceyi kaçırma"),
    if (adReadyAt != null && adReadyAt.isAfter(now))
      PlannedReminder(kRemAd, adReadyAt, 'Bedava çipin hazır 🪙', 'Kısa bir reklam izle, çipini kap!'),
  ];
}

/// Cihazda planlanan yerel bildirimler (sunucu / Firebase GEREKTİRMEZ, limit yemez).
/// Uygulama arka plana geçince plan kurulur, öne gelince iptal edilir (oyuncu içerideyken bildirim çıkmaz).
class Reminders {
  Reminders._();
  static final Reminders I = Reminders._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  DateTime? _claimedOn; // günlük hediyenin alındığı yerel gün
  DateTime? _adReadyAt;

  bool get _supported => defaultTargetPlatform == TargetPlatform.android;

  /// Hata verirse oyunu bozmaz.
  Future<void> init() async {
    if (!_supported || _ready) return;
    try {
      tzdata.initializeTimeZones();
      await _plugin.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      _ready = true;
      await _plugin.cancelAll();
    } catch (e, s) {
      Log.e('bildirim', 'hatırlatma başlatılamadı', e, s);
    }
  }

  /// Android 13+ bildirim izni; yalnız BİR kez sorulur (reddederse bir daha rahatsız edilmez).
  Future<void> askPermissionOnce() async {
    if (!_ready) return;
    try {
      final p = await SharedPreferences.getInstance();
      if (p.getBool('rem_asked') ?? false) return;
      await p.setBool('rem_asked', true);
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e, s) {
      Log.e('bildirim', 'bildirim izni istenemedi', e, s);
    }
  }

  /// Durumu not eder (planı arka plana geçerken kurar).
  void update({bool? dailyClaimed, int? adWaitSeconds}) {
    final now = DateTime.now();
    if (dailyClaimed != null) _claimedOn = dailyClaimed ? now : null;
    if (adWaitSeconds != null) _adReadyAt = adWaitSeconds > 0 ? now.add(Duration(seconds: adWaitSeconds)) : null;
  }

  Future<void> onForeground() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (e, s) {
      Log.e('bildirim', 'hatırlatmalar iptal edilemedi', e, s);
    }
  }

  Future<void> onBackground() async {
    if (!_ready) return;
    try {
      final now = DateTime.now();
      final c = _claimedOn;
      final claimedToday = c != null && c.year == now.year && c.month == now.month && c.day == now.day;
      final plan = planReminders(now: now, dailyClaimedToday: claimedToday, adReadyAt: _adReadyAt);
      await _plugin.cancelAll();
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'reminders',
          'Hatırlatmalar',
          channelDescription: 'Günlük hediye, bedava çip ve masa hatırlatmaları',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      );
      for (final r in plan) {
        await _plugin.zonedSchedule(
          r.id,
          r.title,
          r.body,
          tz.TZDateTime.from(r.at, tz.UTC), // aynı an; yerel saat DateTime.now() ile zaten hesaplandı
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle, // tam alarm izni gerekmez
        );
      }
      Log.i('bildirim', '${plan.length} hatırlatma kuruldu');
    } catch (e, s) {
      Log.e('bildirim', 'hatırlatmalar kurulamadı', e, s);
    }
  }
}
