import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'game_popup.dart';
import 'player_badge.dart' show formatChips;

/// Çip hesaba yattığında gösterilen kutlama penceresi (günlük ödül, reklam ödülü,
/// kutudan alınan çip ...). Arkada dönen ışınlar, sayarak büyüyen miktar,
/// istenirse yeni bakiye ve bir sonraki ödül notu gösterir.
Future<void> showRewardReceived(
  BuildContext context, {
  required int amount,
  String title = 'ÖDÜL KAZANDIN!',
  String? message,
  int? balance,
  String buttonLabel = 'HARİKA!',
}) =>
    showGamePopup<void>(
      context,
      builder: (ctx) => _RewardPopup(
          amount: amount,
          title: title,
          message: message,
          balance: balance,
          buttonLabel: buttonLabel),
    );

class _RewardPopup extends StatefulWidget {
  final int amount;
  final String title;
  final String? message;
  final int? balance;
  final String buttonLabel;
  const _RewardPopup(
      {required this.amount,
      required this.title,
      required this.message,
      required this.balance,
      required this.buttonLabel});

  @override
  State<_RewardPopup> createState() => _RewardPopupState();
}

class _RewardPopupState extends State<_RewardPopup> with SingleTickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 16))..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GamePopup(
      title: widget.title,
      icon: Icons.emoji_events_rounded,
      maxWidth: 540,
      onClose: () => Navigator.of(context).pop(),
      actions: [
        PopupButton(
            label: widget.buttonLabel,
            icon: Icons.check_rounded,
            width: 220,
            onTap: () => Navigator.of(context).pop()),
      ],
      child: SizedBox(
        height: 170,
        child: Row(children: [
          // sol: dönen ışınlar + çip yığını
          SizedBox(
            width: 200,
            child: Stack(alignment: Alignment.center, children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _spin,
                  builder: (_, __) => CustomPaint(painter: _RaysPainter(_spin.value)),
                ),
              ),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 750),
                curve: Curves.elasticOut,
                builder: (_, v, __) => Transform.scale(scale: v, child: const _CoinPile()),
              ),
            ]),
          ),
          const SizedBox(width: 6),
          // sağ: miktar ve notlar
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('HESABINA YATTI',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: Colors.white70)),
              const SizedBox(height: 2),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: widget.amount.toDouble()),
                duration: const Duration(milliseconds: 1000),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('+${formatChips(v.round())}',
                      style: const TextStyle(
                          fontSize: 50,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                          color: AppColors.goldLight,
                          shadows: [
                            Shadow(color: Colors.black87, offset: Offset(0, 3), blurRadius: 4),
                            Shadow(color: Color(0x88F0C25A), blurRadius: 18),
                          ])),
                ),
              ),
              const Text('ÇİP',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 6,
                      color: Colors.white)),
              if (widget.balance != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(.32),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Text('Yeni bakiye',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white70)),
                    const SizedBox(width: 8),
                    const CoinIcon(size: 18),
                    const SizedBox(width: 4),
                    Text(formatChips(widget.balance!),
                        style:
                            const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                  ]),
                ),
              ],
              if (widget.message != null) ...[
                const SizedBox(height: 8),
                Text(widget.message!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12.5, height: 1.3, color: Colors.white70)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Üst üste üç çip.
class _CoinPile extends StatelessWidget {
  const _CoinPile();

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 130,
        height: 120,
        child: Stack(alignment: Alignment.center, children: const [
          Positioned(left: 4, bottom: 6, child: CoinIcon(size: 56)),
          Positioned(right: 4, bottom: 10, child: CoinIcon(size: 52)),
          Positioned(top: 4, child: CoinIcon(size: 84)),
        ]),
      );
}

/// Çipin arkasında dönen, kenarlara doğru sönen altın ışınlar.
class _RaysPainter extends CustomPainter {
  final double t;
  _RaysPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = math.min(size.width, size.height) * .62;
    final paint = Paint()
      ..shader = RadialGradient(colors: [
        AppColors.goldLight.withOpacity(.55),
        AppColors.goldLight.withOpacity(0),
      ]).createShader(Rect.fromCircle(center: c, radius: r));
    const n = 12;
    final base = t * 2 * math.pi;
    for (var i = 0; i < n; i++) {
      final a = base + i * 2 * math.pi / n;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + r * math.cos(a - .09), c.dy + r * math.sin(a - .09))
        ..lineTo(c.dx + r * math.cos(a + .09), c.dy + r * math.sin(a + .09))
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_RaysPainter old) => old.t != t;
}
