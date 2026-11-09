import 'game_controller.dart' show OpenMode;

/// El sonu puanlaması (saf fonksiyon; test edilebilir, sunucuya taşınabilir).
///
/// Kaynak: Türkiye standartları 101 Okey Plus kural kitapçığı, bölüm 6.
/// "Katlı" = okeyle VEYA elden bitirme (ikisi birden olsa da tek kat sayılır).
///
///  - Bitiren: -101 (katlı: -202)
///  - Elini hiç açamayan: +202 (katlı: +404); elindeki okey ayrıca yazılmaz
///  - Seri açıp bitiremeyen: elde kalan sayı toplamı (katlı: 2 katı)
///  - Çift açıp bitiremeyen: elde kalan sayı toplamının 2 katı (katlı: 4 katı)
///  - Eli açmış olup elinde okey kalan: +101 ekstra (okeyle bitirildiyse +202)
///  - Eşli oyunda bitirenin eşi bu elde hiç ceza/ödül almaz: el değeri, açmama
///    cezası ve kendi +101 cezaları dahil hepsi silinir (0).
///  - Diğer oyuncularda ceza puanları (+101'ler) kendi sahibine yazılır.
class RoundScoring {
  RoundScoring._();

  /// [handValues]: her koltuğun elde kalan taş toplamı (OKEY HARİÇ; okey için
  /// [okeyLeft] verilir). [penalty]: bu elde yazılan +101 cezalar.
  /// Dönen liste: koltuk başına bu elin puan değişimi (negatif = iyi).
  static List<int> compute({
    required int winner,
    required bool joker,
    required bool elden,
    required bool teamMode,
    required List<OpenMode?> opened,
    required List<int> handValues,
    required List<int> penalty,
    List<bool>? okeyLeft,
  }) {
    final doubled = joker || elden;
    final delta = List<int>.filled(4, 0);
    for (var s = 0; s < 4; s++) {
      if (s == winner) {
        delta[s] = -(doubled ? 202 : 101) + penalty[s];
        continue;
      }
      // Eşli oyunda bitirenin eşinin bu eldeki cezası tamamen silinir
      // (açmamış olsa, elinde taş kalsa ya da +101 yazılmış olsa bile).
      if (teamMode && s == (winner + 2) % 4) {
        delta[s] = 0;
        continue;
      }
      int d;
      if (opened[s] == null) {
        d = doubled ? 404 : 202;
      } else {
        final mult = opened[s] == OpenMode.series
            ? (doubled ? 2 : 1)
            : (doubled ? 4 : 2);
        d = handValues[s] * mult;
        if (okeyLeft != null && okeyLeft[s]) d += joker ? 202 : 101;
      }
      delta[s] = d + penalty[s];
    }
    return delta;
  }
}
