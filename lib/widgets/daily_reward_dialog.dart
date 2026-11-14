import 'package:flutter/material.dart';
import '../diagnostics/app_log.dart';
import '../models/rewards.dart';
import '../services/ad_service.dart';
import '../services/game_service.dart';
import '../theme/app_theme.dart';
import 'ad_confirm_dialog.dart';
import 'game_popup.dart';
import 'lobby_widgets.dart';
import 'player_badge.dart' show formatChips;
import '../services/reminders.dart';

/// Günlük ödül penceresi. Ödül alındıysa [DailyClaim], pencere kapatıldıysa null döner.
/// Giriş yapılınca (günde bir kez) ve lobideki GÜNLÜK ÖDÜL kartından açılır.
Future<DailyClaim?> showDailyReward(
  BuildContext context, {
  required GameService service,
  required DailyStatus status,
  AdService ads = const MockAdService(),
}) =>
    showGamePopup<DailyClaim>(
      context,
      barrierDismissible: false,
      builder: (_) => DailyRewardDialog(service: service, status: status, ads: ads),
    );

class DailyRewardDialog extends StatefulWidget {
  final GameService service;
  final DailyStatus status;
  final AdService ads;
  const DailyRewardDialog(
      {super.key, required this.service, required this.status, required this.ads});

  @override
  State<DailyRewardDialog> createState() => _DailyRewardDialogState();
}

class _DailyRewardDialogState extends State<DailyRewardDialog>
    with SingleTickerProviderStateMixin {
  bool _busy = false;
  String? _error;

  /// Bugünün kutusunun nabız gibi parlaması.
  late final AnimationController _glow = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  Future<void> _claim({required bool doubled}) async {
    if (_busy) return;
    if (doubled) {
      // Reklamdan önce onay: "Kısa bir reklam izle, X çip kazan" (İZLE / VAZGEÇ). Onay açıkken ikinci dokunuş engellenir.
      setState(() => _busy = true);
      final ok = await showAdConfirm(context,
          amount: widget.status.amount * 2, note: 'Günlük ödülün 2 katı');
      if (!mounted) return;
      setState(() => _busy = false);
      if (!ok) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (doubled) {
        final watched = await widget.ads.showRewarded(context);
        if (!mounted) return;
        if (!watched) {
          setState(() {
            _busy = false;
            _error = 'Reklam tamamlanmadı, 2x ödül verilmedi.';
          });
          return;
        }
      }
      final r = await widget.service.claimDaily(doubled: doubled);
      if (!mounted) return;
      Reminders.I.update(dailyClaimed: true);
      Log.i('ödül', 'günlük ödül alındı: gün=${r.day} +${r.amount} 2x=$doubled');
      Navigator.of(context).pop(r);
    } on JoinException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e, s) {
      Log.e('ödül', 'günlük ödül alınamadı', e, s);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Ödül alınamadı. Bağlantını kontrol edip tekrar dene.';
      });
    }
  }

  /// Referanstaki gibi yatay çubuk: solda taşan ikon, ortada etiket, sağda yeşil tutar.
  /// [glowV] 0'dan büyükse çubuk altın nabız gibi parlar (bugünün ödülü).
  Widget _bar({
    required Widget icon,
    required String label,
    required int amount,
    double height = 36,
    double glowV = -1,
  }) {
    final glow = glowV >= 0;
    return SizedBox(
      height: height + 10,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(
          left: 24,
          top: 5,
          right: 0,
          bottom: 5,
          child: Container(
            padding: const EdgeInsets.only(left: 30, right: 14),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(.38),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: glow ? AppColors.goldLight : Colors.white24,
                  width: glow ? 1.6 : 1),
              boxShadow: glow
                  ? [
                      BoxShadow(
                          color: AppColors.goldLight.withOpacity(.2 + .35 * glowV),
                          blurRadius: 6 + 8 * glowV)
                    ]
                  : null,
            ),
            child: Row(children: [
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label,
                        style: TextStyle(
                            fontSize: height > 40 ? 17 : 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .8,
                            color: Colors.white.withOpacity(glow ? 1 : .85))),
                  ),
                ),
              ),
              Text(formatChips(amount),
                  style: TextStyle(
                      fontSize: height > 40 ? 22 : 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.good)),
            ]),
          ),
        ),
        Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Align(widthFactor: 1, alignment: Alignment.center, child: icon)),
      ]),
    );
  }

  /// Takvim ikonu (SONRAKİ satırı için): krem kart, kırmızı takvim.
  Widget _calendarIcon() => Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white, Color(0xFFE3D5B8)]),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.gold, width: 1.5),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
        ),
        child: const Icon(Icons.calendar_month_rounded, size: 28, color: AppColors.bad),
      );

  Widget _sumCol(String value, String label, {Color? color}) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text(value,
            style: TextStyle(
                fontSize: 19,
                height: 1.1,
                fontWeight: FontWeight.w900,
                color: color ?? AppColors.good)),
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                height: 1.2,
                letterSpacing: .6,
                fontWeight: FontWeight.w800,
                color: Colors.white70)),
      ]);

  Widget _op(String t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Text(t,
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white54)),
      );

  /// Referanstaki "A + B + C = TOPLAM" satırı: günlük ödül + reklam bonusu = reklamla alınacak toplam.
  Widget _sumRow(int a) => Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.3),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _sumCol(formatChips(a), 'GÜNLÜK'),
            _op('+'),
            _sumCol(formatChips(a), 'REKLAM BONUSU'),
            _op('='),
            _sumCol(formatChips(a * 2), 'TOPLAM', color: AppColors.goldLight),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = widget.status;
    final next = nextDay(s.day);
    return GamePopup(
      title: 'GÜNLÜK ÖDÜL',
      subtitle: 'Her gün gir, ödül büyüsün!',
      icon: Icons.card_giftcard_rounded,
      maxWidth: 520,
      onClose: _busy ? null : () => Navigator.of(context).pop(),
      actions: [
        PopupButton(
          label: 'ÖDÜLÜ AL',
          sub: '+${formatChips(s.amount)}',
          kind: CandyKind.green,
          width: 210,
          height: 58,
          onTap: _busy ? null : () => _claim(doubled: false),
        ),
        PopupButton(
          label: 'REKLAM İZLE',
          icon: Icons.play_circle_fill_rounded,
          sub: '+${formatChips(s.amount * 2)}',
          kind: CandyKind.orange,
          tag: '2×',
          width: 230,
          height: 58,
          onTap: _busy ? null : () => _claim(doubled: true),
        ),
      ],
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Yarının (sonraki günün) ödülü: biraz dar, üstte.
        FractionallySizedBox(
          widthFactor: .84,
          child: _bar(
            icon: _calendarIcon(),
            label: s.day >= 7 ? 'SONRAKİ · 7. GÜN' : 'SONRAKİ · $next. GÜN',
            amount: dailyAmount(next),
          ),
        ),
        // Bugünün ödülü: geniş, altın nabız gibi parlar.
        AnimatedBuilder(
          animation: _glow,
          builder: (_, __) => _bar(
            icon: const CoinIcon(size: 46),
            label: s.day >= 7 ? 'BUGÜN · 7. GÜN · BÜYÜK ÖDÜL' : 'BUGÜN · ${s.day}. GÜN',
            amount: s.amount,
            height: 44,
            glowV: _glow.value,
          ),
        ),
        const SizedBox(height: 6),
        _sumRow(s.amount),
        if (_busy || _error != null) ...[
          const SizedBox(height: 10),
          if (_busy)
            const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.goldLight))
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.bad.withOpacity(.16),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.bad.withOpacity(.7)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline_rounded, size: 16, color: AppColors.bad),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(_error!,
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
              ]),
            ),
        ],
      ]),
    );
  }
}
