import 'package:flutter/material.dart';
import '../diagnostics/app_log.dart';
import '../models/rewards.dart';
import '../services/ad_service.dart';
import '../services/game_service.dart';
import '../theme/app_theme.dart';
import 'game_popup.dart';
import 'lobby_widgets.dart';
import 'player_badge.dart' show formatChips;

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

  Widget _dayTile(int day) {
    final s = widget.status;
    final past = day < s.day;
    final today = day == s.day;
    final big = day == 7;
    final amount = dailyAmount(day);

    final Widget icon;
    if (past) {
      icon = Stack(alignment: Alignment.center, children: [
        const Opacity(opacity: .35, child: CoinIcon(size: 30)),
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.good,
              border: Border.all(color: Colors.black54, width: 1.5)),
          child: const Icon(Icons.check_rounded, size: 17, color: Colors.white),
        ),
      ]);
    } else if (big) {
      icon = Icon(Icons.redeem_rounded,
          size: 32, color: today ? AppColors.orangeDark : AppColors.goldLight);
    } else {
      icon = Opacity(opacity: today ? 1 : .8, child: CoinIcon(size: today ? 32 : 28));
    }

    final tile = AnimatedBuilder(
      animation: _glow,
      builder: (_, child) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          boxShadow: today
              ? [
                  BoxShadow(
                      color: AppColors.goldLight.withOpacity(.25 + .4 * _glow.value),
                      blurRadius: 8 + 10 * _glow.value)
                ]
              : null,
        ),
        child: child,
      ),
      child: Container(
        height: 96,
        padding: const EdgeInsets.fromLTRB(2, 7, 2, 6),
        decoration: BoxDecoration(
          gradient: today
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFFE9A8), AppColors.goldLight, AppColors.gold])
              : LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.surfaceLight.withOpacity(past ? .45 : 1),
                    AppColors.surface.withOpacity(past ? .45 : 1)
                  ]),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
              color: today
                  ? Colors.white
                  : big
                      ? AppColors.gold.withOpacity(.8)
                      : Colors.white12,
              width: today ? 2 : 1.2),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(big ? '7. GÜN' : '$day. GÜN',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .3,
                  color: today ? AppColors.navy : Colors.white70)),
          icon,
          Text(formatChips(amount),
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                  color: today
                      ? AppColors.navy
                      : (past ? Colors.white38 : Colors.white))),
        ]),
      ),
    );

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3.5),
        child: Transform.scale(scale: today ? 1.07 : 1, child: tile),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.status;
    return GamePopup(
      title: 'GÜNLÜK ÖDÜL',
      icon: Icons.card_giftcard_rounded,
      maxWidth: 640,
      onClose: _busy ? null : () => Navigator.of(context).pop(),
      actions: [
        PopupButton(
          label: 'ÖDÜLÜ AL',
          sub: '+${formatChips(s.amount)}',
          kind: CandyKind.green,
          width: 230,
          height: 58,
          onTap: _busy ? null : () => _claim(doubled: false),
        ),
        PopupButton(
          label: 'REKLAM İZLE',
          icon: Icons.play_circle_fill_rounded,
          sub: '+${formatChips(s.amount * 2)}',
          kind: CandyKind.orange,
          tag: '2×',
          width: 250,
          height: 58,
          onTap: _busy ? null : () => _claim(doubled: true),
        ),
      ],
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
          'Her gün gir, seriyi bozma. Ödül her gün büyür; gün atlarsan 1. güne dönersin.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 12.5, height: 1.3, color: Colors.white.withOpacity(.78)),
        ),
        const SizedBox(height: 12),
        Row(children: [for (var d = 1; d <= 7; d++) _dayTile(d)]),
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
