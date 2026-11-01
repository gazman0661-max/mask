import 'package:flutter/foundation.dart';

/// Banner reklamı geçici gizler. Ödüllü reklam izlenirken banner görünmesin diye
/// [whileRewarded] ile sarılır. Şerit yer tutmaya devam eder (oyun alanı kaymaz), yalnızca içeriği boşalır.
/// Gerçek (AdMob) ödüllü reklam servisi de `showRewarded` içinde aynısını yapmalı.
class BannerGate {
  static final ValueNotifier<bool> hidden = ValueNotifier<bool>(false);
  static int _depth = 0;

  static Future<T> whileRewarded<T>(Future<T> Function() body) async {
    _depth++;
    hidden.value = true;
    try {
      return await body();
    } finally {
      _depth--;
      if (_depth <= 0) {
        _depth = 0;
        hidden.value = false;
      }
    }
  }
}
