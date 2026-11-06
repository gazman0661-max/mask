import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'responsive_shell.dart';
import '../models/player.dart';
import '../theme/app_theme.dart';
import 'avatar.dart';
import 'game_toast.dart';

export 'game_toast.dart' show ToastKind;

/// Kısa bildirim. Alttan çıkan sistem şeridi yerine oyunun kendi kapsülü ([GameToast]).
void showToast(BuildContext context, String m,
        {ToastKind kind = ToastKind.info, IconData? icon}) =>
    GameToast.show(context, m, kind: kind, icon: icon);

/// Petrol mavisi zemin + dekoratif sonbahar yaprakları.
class AppBackground extends StatelessWidget {
  final Widget child;
  const AppBackground({super.key, required this.child});

  Widget _leaf(double size, double angle, Color c) => Transform.rotate(
      angle: angle, child: Icon(Icons.eco, size: size, color: c));

  @override
  Widget build(BuildContext context) => Stack(children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                  center: Alignment(0, -.3),
                  radius: 1.2,
                  colors: [AppColors.teal, AppColors.tealDark, AppColors.bg]),
            ),
          ),
        ),
        Positioned(
            left: -14,
            bottom: -16,
            child: _leaf(120, .6, AppColors.orange.withOpacity(.22))),
        Positioned(
            right: -10,
            bottom: -20,
            child: _leaf(130, -.7, AppColors.gold.withOpacity(.2))),
        Positioned(
            left: 8,
            top: 70,
            child: _leaf(60, -.4, AppColors.orange.withOpacity(.16))),
        Positioned(
            right: 14,
            top: 80,
            child: _leaf(50, .8, AppColors.gold.withOpacity(.14))),
        Positioned.fill(child: child),
      ]);
}

enum CandyKind { green, orange, blue, red, gray, navy }

/// Parlak, hafif 3B görünümlü oyun butonu.
class CandyButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final CandyKind kind;
  final double? width, height;
  final double radius;
  final bool circle;
  const CandyButton(
      {super.key,
      required this.child,
      required this.onTap,
      this.kind = CandyKind.green,
      this.width,
      this.height,
      this.radius = 14,
      this.circle = false});

  (Color, Color) get _c => switch (kind) {
        CandyKind.green => (AppColors.green, AppColors.greenDark),
        CandyKind.orange => (AppColors.orange, AppColors.orangeDark),
        CandyKind.blue => (AppColors.blueBtn, AppColors.blueBtnDark),
        CandyKind.red => (const Color(0xFFE5392F), const Color(0xFF9B1710)),
        CandyKind.gray => (const Color(0xFF6B7780), const Color(0xFF3E474E)),
        CandyKind.navy => (const Color(0xFF7A1E38), AppColors.navy),
      };

  @override
  Widget build(BuildContext context) {
    final (top, bottom) = _c;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? .55 : 1,
        child: Container(
          width: width,
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: circle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: circle ? null : BorderRadius.circular(radius),
            gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [top, bottom]),
            border: Border.all(color: Colors.black.withOpacity(.55), width: 2),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black45, offset: Offset(0, 3), blurRadius: 4)
            ],
          ),
          child: DefaultTextStyle(
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: .5,
                shadows: [Shadow(color: Colors.black54, offset: Offset(0, 1.5))]),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Alt çubuktaki yuvarlak ikon butonu.
class RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final CandyKind kind;
  final double size;
  const RoundBtn(
      {super.key,
      required this.icon,
      required this.onTap,
      this.kind = CandyKind.navy,
      this.size = 42});

  @override
  Widget build(BuildContext context) => CandyButton(
      onTap: onTap,
      kind: kind,
      circle: true,
      width: size,
      height: size,
      child: Icon(icon, color: Colors.white, size: size * .52));
}

/// Üst çubuk: profil, logo, bilet ve market.
class TopHud extends StatelessWidget {
  final Player? player;
  /// Avatara dokununca (profil düzenleme).
  final VoidCallback? onProfile;
  /// Sağ üstteki mağaza (sepet) butonu. Null ise "yakında" bildirimi çıkar.
  final VoidCallback? onShop;
  /// Bilet bakiyesi (null = henüz bilinmiyor).
  final int? tickets;

  /// Sunucudaki seviye (null ise oyuncunun yerel seviyesi) ve seviye ilerlemesi 0..1.
  final int? level;
  final double? levelProgress;
  const TopHud(
      {super.key, this.player, this.tickets, this.level, this.levelProgress, this.onProfile, this.onShop});

  Widget _plate(Widget child, {EdgeInsets? pad}) => Container(
        padding: pad ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF7A1E38), AppColors.navy]),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black38),
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final p = player;
    final left = Row(mainAxisSize: MainAxisSize.min, children: [
      GestureDetector(
        onTap: onProfile,
        child: p?.avatar != null
            ? AvatarWidget(index: p!.avatar!, size: 46, selected: true)
            : Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF7A1E38),
                  border: Border.all(color: AppColors.goldLight, width: 2),
                ),
                child: const Icon(Icons.person, color: Colors.white70, size: 30),
              ),
      ),
      const SizedBox(width: 6),
      Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _plate(Text(p?.name ?? '...', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            pad: const EdgeInsets.symmetric(horizontal: 10, vertical: 3)),
        const SizedBox(height: 3),
        Row(children: [
          const Icon(Icons.star, color: AppColors.gold, size: 16),
          const SizedBox(width: 3),
          Text('Seviye: ${level ?? p?.level ?? 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          if (levelProgress != null) ...[
            const SizedBox(width: 6),
            SizedBox(
              width: 44,
              height: 5,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                    value: levelProgress, backgroundColor: Colors.black38, color: AppColors.goldLight),
              ),
            ),
          ],
        ]),
      ]),
    ]);
    final right = Row(mainAxisSize: MainAxisSize.min, children: [
      _plate(
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.confirmation_number_rounded, color: AppColors.goldLight, size: 20),
            const SizedBox(width: 5),
            Text(tickets == null ? '-' : '$tickets', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          ]),
          pad: const EdgeInsets.fromLTRB(10, 5, 10, 5)),
      const SizedBox(width: 8),
      RoundBtn(
          icon: Icons.shopping_cart,
          kind: CandyKind.green,
          size: 44,
          onTap: onShop ?? () => showToast(context, 'Market yakında geliyor.')),
    ]);

    // Banner varsa: [profil] [logo] [banner boşluğu] [bilet + market]. Banner 320 birim genişliğinde olduğu için
    // logo ortadan profilin yanına çekilir; banner logo ile bilet arasındaki boşluğun tam ortasına oturur.
    if (BannerSlotMarker.isAvailable(context)) {
      return SizedBox(
        height: math.max(52, BannerSlot.maybeOf(context)!.slotHeight),
        child: Row(children: [
          left,
          const SizedBox(width: 10),
          const _Logo(),
          const Expanded(child: Center(child: BannerSlotMarker())),
          right,
        ]),
      );
    }
    return SizedBox(
      height: 52,
      child: Stack(children: [
        Align(alignment: Alignment.centerLeft, child: left),
        const Align(alignment: Alignment.center, child: _Logo()),
        Align(alignment: Alignment.centerRight, child: right),
      ]),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();
  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShaderMask(
            shaderCallback: (r) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.goldLight, AppColors.gold]).createShader(r),
            child: const Text('101',
                style: TextStyle(
                    fontSize: 28,
                    height: .95,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    color: Colors.white,
                    shadows: [Shadow(color: Colors.black87, blurRadius: 3)])),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFFB3221A),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.goldLight, width: 1),
            ),
            child: const Text('OKEY',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3)),
          ),
        ],
      );
}
