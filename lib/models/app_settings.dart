import 'package:flutter/foundation.dart';
import '../diagnostics/app_log.dart';
import 'table_models.dart';

/// Uygulama ayarları (şimdilik bellekte; kalıcı olması için
/// shared_preferences eklenip load/save bağlanacak).
class AppSettings extends ChangeNotifier {
  static final AppSettings I = AppSettings._();
  AppSettings._();

  // genel
  bool music = true, sound = true, vibration = true;
  bool friends = true, chat = true, invites = true;

  // hemen oyna tercihleri (null = fark etmez)
  int hands = 1;
  bool? team, assisted, folding;

  void update(VoidCallback change) {
    change();
    Log.d('ayar', 'ayar değişti: müzik=$music ses=$sound titreşim=$vibration arkadaş=$friends sohbet=$chat davet=$invites | hemen oyna: el=$hands eşli=$team yardımlı=$assisted katlamalı=$folding');
    notifyListeners();
  }

  /// "Hemen Oyna" için masa ayarı.
  TableSettings quick({bool turbo = false}) => TableSettings(
        turbo: turbo,
        hands: hands,
        team: team ?? false,
        assisted: assisted ?? true,
        folding: folding ?? true,
      );
}
