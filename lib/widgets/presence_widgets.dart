import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Sunucu bağlantısı koptuğunda ekranın üstünde görünen şerit. Dokunmaları engellemez.
/// Bu sürede yerine bot oynar; [graceSeconds] içinde dönmezsen koltuğun bota kalır, biletin yanar.
class ConnectionBanner extends StatelessWidget {
  final int graceSeconds;
  const ConnectionBanner({super.key, this.graceSeconds = 90});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.orange,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 8),
            Text(
              'Bağlantı koptu, yeniden bağlanılıyor... ($graceSeconds sn içinde dönmezsen koltuğun bota kalır)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Oyuncu bağlıyken boşta sayıldığında (üst üste 2 tur kaçırdı) tam ekran uyarı:
/// "OYUNA DÖN" bota bırakılan koltuğu geri alır.
class AwayOverlay extends StatelessWidget {
  final VoidCallback onBack;
  final int graceSeconds;
  const AwayOverlay({super.key, required this.onBack, this.graceSeconds = 90});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.surfaceLight, AppColors.surface]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.gold, width: 1.5),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('BOŞTASIN',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.goldLight)),
            const SizedBox(height: 4),
            Text(
              'Yerine bot oynuyor. $graceSeconds sn içinde dönmezsen\nkoltuğun bota kalır ve biletin yanar.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: onBack,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.navy,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
                shape: const StadiumBorder(),
              ),
              child: const Text('OYUNA DÖN',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
            ),
          ]),
        ),
      ),
    );
  }
}
