import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../diagnostics/app_log.dart';
import '../models/rewards.dart';
import '../services/game_service.dart';
import '../services/sfx.dart';
import '../theme/app_theme.dart';
import 'game_popup.dart';
import 'lobby_widgets.dart';

/// Seviye atlama kutlaması: konfeti + dönen ışınlı rozet + hediye bilet(ler). AL'a basınca bilet hesaba geçer.
/// Bilet alındıysa [LevelClaim], alınamadan kapatıldıysa null döner (hediye kaybolmaz, bir sonraki açılışta yine çıkar).
Future<LevelClaim?> showLevelUp(
  BuildContext context, {
  required GameService service,
  required int level,
  required int pending,
}) =>
    showGamePopup<LevelClaim>(
      context,
      barrierDismissible: false,
      builder: (_) => _LevelUpDialog(service: service, level: level, pending: pending),
    );

class _LevelUpDialog extends StatefulWidget {
  final GameService service;
  final int level;
  final int pending;
  const _LevelUpDialog({required this.service, required this.level, required this.pending});

  @override
  State<_LevelUpDialog> createState() => _LevelUpDialogState();
}

class _LevelUpDialogState extends State<_LevelUpDialog> with TickerProviderStateMixin {
  bool _busy = false;
  bool _done = false; // bilet alındı, pencere kapanmak üzere
  String? _error;

  final math.Random _rnd = math.Random();

  /// Rozetin nabız gibi parlaması + yıldız parıltıları.
  late final AnimationController _glow =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  /// Arkadaki ışınların yavaş dönüşü.
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 9))..repeat();

  /// Açılış: rozet yaylanarak büyür, sonra bilet satırı belirir.
  late final AnimationController _enter =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..forward();

  /// Konfeti (açılışta iki alt köşeden, AL'a basınca ortadan patlar).
  late final AnimationController _conf =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));

  /// AL'a basınca bilet satırı yukarı uçup kaybolur.
  late final AnimationController _fly =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 650));

  late List<_Piece> _pieces;

  @override
  void initState() {
    super.initState();
    _pieces = [
      ..._burst(count: 45, ox: .06, oy: 1.0, aim: -math.pi / 2 + .55, spread: .5),
      ..._burst(count: 45, ox: .94, oy: 1.0, aim: -math.pi / 2 - .55, spread: .5),
    ];
    _conf.forward(from: 0);
    // Kutlama sesi + titreşim (ses/titreşim ayarları Sfx içinde kontrol edilir).
    Sfx.I.cheer(okey: false, mine: true);
  }

  @override
  void dispose() {
    Sfx.I.stopCheer();
    _glow.dispose();
    _spin.dispose();
    _enter.dispose();
    _conf.dispose();
    _fly.dispose();
    super.dispose();
  }

  static const _palette = [
    Color(0xFFF0C25A),
    Color(0xFFFFE9A8),
    Color(0xFFD0342C),
    Color(0xFF1E6BD0),
    Color(0xFF3FBF3F),
    Color(0xFFF08A1C),
    Colors.white,
  ];

  /// [count] parça: başlangıç noktası ekranın oransal (ox, oy) konumu, [aim] yönü etrafında [spread] açıyla saçılır.
  List<_Piece> _burst({
    required int count,
    required double ox,
    required double oy,
    required double aim,
    required double spread,
    double maxDelay = .35,
  }) =>
      List.generate(count, (_) {
        return _Piece(
          ox: ox,
          oy: oy,
          angle: aim + (_rnd.nextDouble() * 2 - 1) * spread,
          speed: .75 + _rnd.nextDouble() * .85,
          spin: (_rnd.nextDouble() * 2 - 1) * 9,
          flip: 4 + _rnd.nextDouble() * 6,
          phase: _rnd.nextDouble() * math.pi * 2,
          size: 6 + _rnd.nextDouble() * 6,
          delay: _rnd.nextDouble() * maxDelay,
          color: _palette[_rnd.nextInt(_palette.length)],
          circle: _rnd.nextInt(5) == 0,
        );
      });

  Future<void> _claim() async {
    if (_busy || _done) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.service.claimLevelRewards();
      if (!mounted) return;
      Log.i('ödül', 'seviye hediyesi alındı: +${r.amount} bilet seviye=${r.level}');
      HapticFeedback.mediumImpact().catchError((Object _) {});
      setState(() {
        _busy = false;
        _done = true;
        // Ortadan her yöne ikinci patlama.
        _pieces = _burst(count: 90, ox: .5, oy: .48, aim: -math.pi / 2, spread: math.pi, maxDelay: .12);
      });
      _conf.forward(from: 0);
      _fly.forward(from: 0);
      await Future<void>.delayed(const Duration(milliseconds: 850));
      if (!mounted) return;
      Navigator.of(context).pop(r);
    } on JoinException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e, s) {
      Log.e('ödül', 'seviye hediyesi alınamadı', e, s);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Hediye alınamadı. Bağlantını kontrol edip tekrar dene.';
      });
    }
  }

  Widget _spark(double left, double top, double size, double phase) {
    final t = (_glow.value + phase) % 1.0;
    final k = .35 + .65 * math.sin(t * math.pi); // 0.35..1 arası titreşir
    return Positioned(
      left: left,
      top: top,
      child: Opacity(
        opacity: k.clamp(0.0, 1.0).toDouble(),
        child: Transform.scale(
          scale: .7 + .5 * k,
          child: Icon(Icons.star_rounded, size: size, color: AppColors.goldLight),
        ),
      ),
    );
  }

  Widget _badge() {
    final pop = CurvedAnimation(parent: _enter, curve: const Interval(0, .6, curve: Curves.elasticOut));
    return SizedBox(
      width: 260,
      height: 190,
      child: AnimatedBuilder(
        animation: Listenable.merge([_glow, _spin, _enter]),
        builder: (_, __) => Stack(alignment: Alignment.center, children: [
          // dönen ışınlar
          Opacity(
            opacity: Curves.easeOut.transform((_enter.value * 2).clamp(0.0, 1.0).toDouble()),
            child: CustomPaint(size: const Size(190, 190), painter: _RaysPainter(_spin.value)),
          ),
          _spark(22, 28, 22, 0),
          _spark(212, 40, 18, .3),
          _spark(36, 138, 16, .6),
          _spark(204, 146, 24, .15),
          // rozet
          Transform.scale(
            scale: pop.value,
            child: Container(
              width: 112,
              height: 112,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFFE9A8), AppColors.goldLight, AppColors.gold]),
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                      color: AppColors.goldLight.withOpacity(.3 + .4 * _glow.value),
                      blurRadius: 14 + 14 * _glow.value)
                ],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('SEVİYE',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: .6, color: AppColors.navy)),
                Text('${widget.level}',
                    style: const TextStyle(
                        fontSize: 44, height: 1.0, fontWeight: FontWeight.w900, color: AppColors.navy)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _ticketRow() {
    final appear = CurvedAnimation(parent: _enter, curve: const Interval(.45, 1, curve: Curves.easeOutBack));
    final fade = CurvedAnimation(parent: _enter, curve: const Interval(.45, .8, curve: Curves.easeOut));
    return AnimatedBuilder(
      animation: Listenable.merge([_enter, _fly]),
      builder: (_, child) {
        final f = Curves.easeIn.transform(_fly.value);
        return Opacity(
          opacity: (fade.value * (1 - f)).clamp(0.0, 1.0).toDouble(),
          child: Transform.translate(
            offset: Offset(0, -46 * f),
            child: Transform.scale(scale: appear.value * (1 + .25 * f), child: child),
          ),
        );
      },
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.confirmation_number_rounded, size: 30, color: AppColors.goldLight),
        const SizedBox(width: 8),
        Text('+${widget.pending} BİLET HEDİYE',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final multi = widget.pending > 1;
    final popup = GamePopup(
      title: 'SEVİYE ATLADIN!',
      icon: Icons.emoji_events_rounded,
      maxWidth: 520,
      onClose: null, // AL'a basmadan kapanmaz: hediye teslim alınsın
      actions: [
        PopupButton(
          label: 'AL',
          kind: CandyKind.green,
          width: 220,
          height: 58,
          onTap: (_busy || _done) ? null : _claim,
        ),
      ],
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _badge(),
        const SizedBox(height: 6),
        _ticketRow(),
        const SizedBox(height: 6),
        Text(
          multi
              ? 'Tebrikler! ${widget.pending} seviye atladın, her seviye için 1 bilet kazandın.'
              : 'Tebrikler! Her yeni seviye için 1 bilet hediye.',
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

    // Konfeti tüm ekranı kaplar ve dokunuşu engellemez; pencere üstte.
    return SizedBox.expand(
      child: Stack(alignment: Alignment.center, children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _ConfettiPainter(_pieces, _conf)),
          ),
        ),
        popup,
      ]),
    );
  }
}

/// Tek konfeti parçası (başlangıç, yön ve hız; konum zamandan hesaplanır).
class _Piece {
  final double ox, oy; // başlangıç, ekranın oransal konumu (0..1)
  final double angle; // radyan
  final double speed; // ekran yüksekliği / sn
  final double spin, flip, phase, size, delay;
  final Color color;
  final bool circle;
  const _Piece({
    required this.ox,
    required this.oy,
    required this.angle,
    required this.speed,
    required this.spin,
    required this.flip,
    required this.phase,
    required this.size,
    required this.delay,
    required this.color,
    required this.circle,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_Piece> pieces;
  final AnimationController c;
  _ConfettiPainter(this.pieces, this.c) : super(repaint: c);

  static const _life = 2.7; // sn: parça bu sürede söner
  static const _drag = 1.3;

  @override
  void paint(Canvas canvas, Size size) {
    final now = c.value * (c.duration!.inMilliseconds / 1000.0);
    final u = size.height; // hız birimi
    final g = .75 * u; // yerçekimi
    final paint = Paint();
    for (final p in pieces) {
      final t = now - p.delay;
      if (t <= 0 || t >= _life) continue;
      final dist = p.speed * u * (1 - math.exp(-_drag * t)) / _drag;
      final x = p.ox * size.width + math.cos(p.angle) * dist;
      final y = p.oy * size.height + math.sin(p.angle) * dist + .5 * g * t * t;
      if (y > size.height + 30 || x < -30 || x > size.width + 30) continue;
      final fade = t > _life * .7 ? (1 - (t - _life * .7) / (_life * .3)) : 1.0;
      paint.color = p.color.withOpacity(fade.clamp(0.0, 1.0).toDouble());
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.phase + p.spin * t);
      if (p.circle) {
        canvas.drawCircle(Offset.zero, p.size * .45, paint);
      } else {
        // dönerken şeridin ince/kalın görünmesi (havada takla)
        final h = p.size * .55 * (math.cos(p.phase + p.flip * t).abs() * .85 + .15);
        canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.size, height: h), paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.pieces != pieces;
}

/// Rozetin arkasında dönen altın ışınlar.
class _RaysPainter extends CustomPainter {
  final double turn; // 0..1
  const _RaysPainter(this.turn);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    final paint = Paint()
      ..shader = RadialGradient(colors: [
        AppColors.goldLight.withOpacity(.65),
        AppColors.goldLight.withOpacity(0),
      ]).createShader(rect);
    const n = 12;
    const step = math.pi * 2 / n;
    for (var i = 0; i < n; i++) {
      final start = turn * math.pi * 2 + i * step;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..arcTo(rect, start, step * .5, false)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RaysPainter old) => old.turn != turn;
}
