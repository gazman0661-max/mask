import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Oyundaki TÜM çip göstergelerinin tek ikonu: kenarında krem şeritli altın madeni çip.
/// Eskiden bazı yerlerde `$` madeni para, bazı yerlerde bilet ikonu vardı; hepsi bunun yerine geçti.
/// Boyut dışında ayar yoktur (renk sabit), böylece her ekranda aynı görünür.
class ChipIcon extends StatelessWidget {
  final double size;

  /// Büyük gösterimlerde (mağaza yığını gibi) altına gölge çizer.
  final bool shadow;

  const ChipIcon({super.key, this.size = 18, this.shadow = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ChipPainter(shadow: shadow)),
    );
  }
}

class _ChipPainter extends CustomPainter {
  final bool shadow;
  const _ChipPainter({required this.shadow});

  static const _body = Color(0xFFE3B24E); // AppColors.gold
  static const _bodyDark = Color(0xFFA9781F);
  static const _bodyLight = Color(0xFFF7D77A);
  static const _cream = Color(0xFFFFF4CC);

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final c = Offset(size.width / 2, size.height / 2);
    final r = s / 2;

    if (shadow) {
      canvas.drawCircle(c + Offset(0, s * .05), r, Paint()
        ..color = Colors.black54
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * .06));
    }

    // Gövde: üstten alta hafif renk geçişi.
    final bodyRect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = const LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_bodyLight, _body])
              .createShader(bodyRect));

    // Kenar şeritleri: 8 krem yay.
    final edgeW = r * .26;
    final edgeR = r - edgeW / 2;
    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = edgeW
      ..color = _cream;
    const sweep = math.pi / 8;
    for (var i = 0; i < 8; i++) {
      final start = i * math.pi / 4 - sweep / 2;
      canvas.drawArc(Rect.fromCircle(center: c, radius: edgeR), start, sweep, false, edgePaint);
    }

    // İç halka ve orta disk.
    canvas.drawCircle(
        c,
        r * .62,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(.6, r * .09)
          ..color = _bodyDark);
    canvas.drawCircle(c, r * .38, Paint()..color = _bodyDark.withOpacity(.55));

    // Dış çizgi.
    canvas.drawCircle(
        c,
        r - math.max(.4, r * .03),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(.6, r * .07)
          ..color = _bodyDark);
  }

  @override
  bool shouldRepaint(covariant _ChipPainter old) => old.shadow != shadow;
}
