import 'package:flutter/material.dart';

/// Gerçek reklam SDK'sı (AdMob vb.) bu widget'ın içine bağlanacak.
class AdBannerPlaceholder extends StatelessWidget {
  const AdBannerPlaceholder({super.key});

  @override
  Widget build(BuildContext context) => Container(
        height: 50,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white10,
          border: Border.all(color: Colors.white24),
        ),
        child: const Text('REKLAM ALANI (320x50)',
            style: TextStyle(color: Colors.white38, letterSpacing: 2)),
      );
}
