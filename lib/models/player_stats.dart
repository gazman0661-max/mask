import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../diagnostics/app_log.dart';

/// Oyuncunun kişisel istatistikleri ve rekorları (cihazda saklanır, sunucu gerektirmez).
/// Maç/el sonunda [GameController] kaydeder; "İstatistiklerim" ekranı gösterir.
/// NOT: yalnız bu cihazda tutulur (uygulama verisi silinirse sıfırlanır).
class PlayerStats extends ChangeNotifier {
  static final PlayerStats I = PlayerStats._();
  PlayerStats._();

  static const _key = 'okey_player_stats_v1';

  int matchesPlayed = 0; // sonuna kadar oynanan (hükümsüz olmayan) maç
  int matchesWon = 0;
  int handsPlayed = 0; // sonuçlanan el (hükümsüz hariç)
  int handsWon = 0; // eli ben bitirdim
  int okeyFinishes = 0; // okey atarak bitirme
  int eldenFinishes = 0; // elden bitirme (hiçbir şey açmadan)
  int pairFinishes = 0; // çiftle bitirme
  int curWinStreak = 0; // üst üste kazanılan maç
  int bestWinStreak = 0;
  int? bestHand; // en iyi el puanı (en düşük = en iyi, örn. -202)

  bool _loaded = false;

  double get winRate => matchesPlayed == 0 ? 0 : matchesWon * 100 / matchesPlayed;
  bool get isEmpty => matchesPlayed == 0 && handsPlayed == 0;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      int n(String k) => (j[k] as num?)?.toInt() ?? 0;
      matchesPlayed = n('mp');
      matchesWon = n('mw');
      handsPlayed = n('hp');
      handsWon = n('hw');
      okeyFinishes = n('of');
      eldenFinishes = n('ef');
      pairFinishes = n('pf');
      curWinStreak = n('cs');
      bestWinStreak = n('bs');
      bestHand = (j['bh'] as num?)?.toInt();
      notifyListeners();
    } catch (e) {
      Log.w('istatistik', 'yüklenemedi: $e');
    }
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
          _key,
          jsonEncode({
            'mp': matchesPlayed,
            'mw': matchesWon,
            'hp': handsPlayed,
            'hw': handsWon,
            'of': okeyFinishes,
            'ef': eldenFinishes,
            'pf': pairFinishes,
            'cs': curWinStreak,
            'bs': bestWinStreak,
            'bh': bestHand,
          }));
    } catch (e) {
      Log.w('istatistik', 'kaydedilemedi: $e');
    }
  }

  /// Bir el sonuçlandı (hükümsüz eller çağrılmaz). [myDelta] bu eldeki puanım (negatif = iyi).
  Future<void> recordHand({
    required bool iWon,
    required bool okey,
    required bool elden,
    required bool pairs,
    required int myDelta,
  }) async {
    await load();
    handsPlayed++;
    if (iWon) {
      handsWon++;
      if (okey) okeyFinishes++;
      if (elden) eldenFinishes++;
      if (pairs) pairFinishes++;
    }
    if (bestHand == null || myDelta < bestHand!) bestHand = myDelta;
    notifyListeners();
    unawaited(_save());
  }

  /// Maç sonuna kadar oynandı (hükümsüz değil).
  Future<void> recordMatch({required bool won}) async {
    await load();
    matchesPlayed++;
    if (won) {
      matchesWon++;
      curWinStreak++;
      if (curWinStreak > bestWinStreak) bestWinStreak = curWinStreak;
    } else {
      curWinStreak = 0;
    }
    notifyListeners();
    unawaited(_save());
  }
}
