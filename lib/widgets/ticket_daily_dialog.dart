import 'package:flutter/material.dart';
import '../diagnostics/app_log.dart';
import '../models/rewards.dart';
import '../services/ad_service.dart';
import '../services/game_service.dart';
import '../theme/app_theme.dart';
import 'game_popup.dart';
import 'lobby_widgets.dart';

/// Günlük bilet penceresi: günde bir kez [kDailyTickets] bilet, reklam izlenirse 2 katı.
/// Bilet alındıysa [TicketClaim], pencere kapatıldıysa null döner.
Future<TicketClaim?> showTicketDaily(
  BuildContext context, {
  required GameService service,
  AdService ads = const MockAdService(),
}) =>
    showGamePopup<TicketClaim>(
      context,
      barrierDismissible: false,
      builder: (_) => _TicketDailyDialog(service: service, ads: ads),
    );

class _TicketDailyDialog extends StatefulWidget {
  final GameService service;
  final AdService ads;
  const _TicketDailyDialog({required this.service, required this.ads});

  @override
  State<_TicketDailyDialog> createState() => _TicketDailyDialogState();
}

class _TicketDailyDialogState extends State<_TicketDailyDialog> {
  bool _busy = false;
  String? _error;

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
            _error = 'Reklam tamamlanmadı, 2 katı bilet verilmedi.';
          });
          return;
        }
      }
      final r = await widget.service.claimDailyTickets(doubled: doubled);
      if (!mounted) return;
      Log.i('ödül', 'günlük bilet alındı: +${r.amount} 2x=$doubled bilet=${r.tickets}');
      Navigator.of(context).pop(r);
    } on JoinException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e, s) {
      Log.e('ödül', 'günlük bilet alınamadı', e, s);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Bilet alınamadı. Bağlantını kontrol edip tekrar dene.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GamePopup(
      title: 'GÜNLÜK BİLET',
      icon: Icons.confirmation_number_rounded,
      maxWidth: 520,
      onClose: _busy ? null : () => Navigator.of(context).pop(),
      actions: [
        PopupButton(
          label: 'BİLETİ AL',
          sub: '+$kDailyTickets bilet',
          kind: CandyKind.green,
          width: 220,
          height: 58,
          onTap: _busy ? null : () => _claim(doubled: false),
        ),
        PopupButton(
          label: 'REKLAM İZLE',
          icon: Icons.play_circle_fill_rounded,
          sub: '+${kDailyTickets * 2} bilet',
          kind: CandyKind.orange,
          tag: '2×',
          width: 240,
          height: 58,
          onTap: _busy ? null : () => _claim(doubled: true),
        ),
      ],
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.confirmation_number_rounded, size: 56, color: AppColors.goldLight),
        const SizedBox(height: 10),
        Text(
          'Masaya oturmak 1 bilet. Masayı kuran tek bilet öder, maç başlayınca tekrar düşmez.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, height: 1.3, color: Colors.white.withOpacity(.78)),
        ),
        if (_busy || _error != null) ...[
          const SizedBox(height: 10),
          if (_busy)
            const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.goldLight))
          else
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white)),
        ],
      ]),
    );
  }
}
