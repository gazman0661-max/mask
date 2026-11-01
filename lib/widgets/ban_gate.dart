import 'dart:async';
import 'dart:ui' show FontFeature;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Hesap ya da cihaz kapatılınca (sunucu `banned` mesajı, bkz. GameSocket.ban) uygulamanın üstüne
/// tam ekran uyarı koyar. Geçici kapatmada kalan süre geri sayar. Bilgi yoksa çocuğu olduğu gibi gösterir.
class BanGate extends StatelessWidget {
  final ValueListenable<Map<String, dynamic>?>? notice;
  final VoidCallback? onRetry;
  final Widget child;
  const BanGate({super.key, required this.notice, required this.onRetry, required this.child});

  @override
  Widget build(BuildContext context) {
    final n = notice;
    if (n == null) return child;
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: n,
      builder: (context, ban, _) {
        if (ban == null) return child;
        return Stack(children: [
          child,
          Positioned.fill(child: _BanScreen(key: ValueKey(ban.hashCode), ban: ban, onRetry: onRetry)),
        ]);
      },
    );
  }
}

class _BanScreen extends StatefulWidget {
  final Map<String, dynamic> ban;
  final VoidCallback? onRetry;
  const _BanScreen({super.key, required this.ban, required this.onRetry});

  @override
  State<_BanScreen> createState() => _BanScreenState();
}

class _BanScreenState extends State<_BanScreen> {
  Timer? _tick;
  DateTime? _until;
  int _totalDays = 0; // ilk gösterilen süre (gün): "3 gün boyunca" metni geri sayarken değişmez

  bool get _perm => widget.ban['perm'] == true;
  bool get _wiped => widget.ban['wiped'] == true;

  @override
  void initState() {
    super.initState();
    final u = widget.ban['until'];
    if (!_perm && u is String) {
      _until = DateTime.tryParse(u)?.toLocal();
      final left = _until?.difference(DateTime.now()) ?? Duration.zero;
      _totalDays = (left.inMinutes / 1440).round().clamp(1, 3650).toInt();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Duration get _left {
    final d = _until?.difference(DateTime.now()) ?? Duration.zero;
    return d.isNegative ? Duration.zero : d;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  String get _countdown {
    final d = _left;
    final days = d.inDays;
    final h = d.inHours % 24, m = d.inMinutes % 60, s = d.inSeconds % 60;
    return '${days > 0 ? '$days gün ' : ''}${_two(h)}:${_two(m)}:${_two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.ban['device'] == true;
    final over = !_perm && _left == Duration.zero;
    final String body;
    if (_perm) {
      body = 'Hesabınızda kötüye kullanım tespit edilmiştir.\nHesabınız Süresiz Askıya alınmıştır.';
    } else {
      body = 'Hesabınızda kötüye kullanım tespit edilmiştir.\n'
          '${_wiped ? 'Biletlerin ve lig puanın silinmiştir ve hesabınız' : 'Hesabınız'} $_totalDays gün boyunca kapatılmıştır.';
    }
    return Material(
      color: AppColors.bg.withOpacity(.97),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.block, size: 54, color: Color(0xFFE5484D)),
                const SizedBox(height: 12),
                Text(_perm ? 'Hesap Askıya Alındı' : (device ? 'Cihaz Geçici Olarak Kapatıldı' : 'Hesap Geçici Olarak Kapatıldı'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                const SizedBox(height: 12),
                Text(body,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, height: 1.4, color: Colors.white70)),
                if (!_perm) ...[
                  const SizedBox(height: 18),
                  const Text('Kalan süre', style: TextStyle(fontSize: 12, color: Colors.white54)),
                  const SizedBox(height: 4),
                  Text(over ? '00:00:00' : _countdown,
                      style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: AppColors.goldLight,
                          fontFeatures: [FontFeature.tabularFigures()])),
                  const SizedBox(height: 18),
                  ElevatedButton(
                      onPressed: over ? widget.onRetry : null,
                      child: Text(over ? 'Süre doldu, oyuna gir' : 'Süre dolunca girebilirsin')),
                ] else ...[
                  const SizedBox(height: 14),
                  const Text('Haksız bir işlem olduğunu düşünüyorsan destek ile iletişime geç.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.white54)),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
