import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'banner_gate.dart';
import '../widgets/game_popup.dart';
import '../widgets/lobby_widgets.dart' show CandyKind;

/// Ödüllü reklam. [showRewarded] reklam SONUNA kadar izlenirse true, yarıda kapatılırsa false döner.
///
/// Gerçek reklam servisi `showRewarded` içinde reklamı `BannerGate.whileRewarded(...)` ile sarmalı (banner gizlensin).
///
/// ŞİMDİLİK SAHTE ([MockAdService]): 5 saniyelik sahte bir reklam penceresi gösterir. Gerçek reklam için
/// (AdMob `google_mobile_ads`) bu sınıfı extend eden yeni bir sınıf yazıp [LobbyScreen.ads]'e ver.
/// DİKKAT: gerçek reklamda ödül, istemcinin "izledim" demesine değil AdMob sunucu doğrulamasına (SSV) bağlanmalı
/// (bkz. migration-006.sql başındaki güvenlik notu ve YAPILACAKLAR.md).
abstract class AdService {
  const AdService();
  Future<bool> showRewarded(BuildContext context);
}

class MockAdService extends AdService {
  const MockAdService();

  @override
  Future<bool> showRewarded(BuildContext context) async {
    // Reklam sürerken üstteki banner gizlenir.
    final ok = await BannerGate.whileRewarded(() => showGamePopup<bool>(context,
        barrierDismissible: false, builder: (_) => const _MockAdDialog()));
    return ok ?? false;
  }
}

class _MockAdDialog extends StatefulWidget {
  const _MockAdDialog();

  @override
  State<_MockAdDialog> createState() => _MockAdDialogState();
}

class _MockAdDialogState extends State<_MockAdDialog> {
  static const _seconds = 5;
  int _left = _seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _left = _left > 0 ? _left - 1 : 0);
      if (_left == 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final done = _left == 0;
    return GamePopup(
      title: 'REKLAM (ÖRNEK)',
      icon: Icons.play_circle_fill,
      maxWidth: 420,
      onClose: () => Navigator.of(context).pop(false),
      actions: [
        PopupButton(
            label: 'KAPAT',
            kind: CandyKind.gray,
            width: 150,
            height: 46,
            onTap: () => Navigator.of(context).pop(false)),
        PopupButton(
            label: 'ÖDÜLÜ AL',
            kind: CandyKind.green,
            width: 170,
            height: 46,
            onTap: done ? () => Navigator.of(context).pop(true) : null),
      ],
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Align(
          alignment: Alignment.centerRight,
          child: Text(done ? 'Ödül hazır' : 'Ödüle $_left sn',
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white70)),
        ),
        const SizedBox(height: 8),
        Container(
          height: 120,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF7A1E38), Color(0xFF4F1022)]),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          child: const Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.play_circle_fill, size: 40, color: Colors.white70),
            SizedBox(height: 6),
            Text('Burada gerçek reklam oynayacak',
                style: TextStyle(fontSize: 13, color: Colors.white70)),
          ]),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (_seconds - _left) / _seconds,
            minHeight: 6,
            backgroundColor: Colors.white12,
            valueColor: const AlwaysStoppedAnimation(AppColors.gold),
          ),
        ),
        const SizedBox(height: 8),
        const Text('Reklamı kapatırsan ödül verilmez.',
            style: TextStyle(fontSize: 10.5, color: Colors.white54)),
      ]),
    );
  }
}
