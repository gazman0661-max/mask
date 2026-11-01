import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'lobby_widgets.dart' show CandyButton, CandyKind;

/// Oyunun tüm pencereleri için ortak açılış: koyu perde + hafif büyüyerek belirme.
/// Sistem `showDialog` yerine bu kullanılır; içerik [GamePopup] ile çerçevelenir.
Future<T?> showGamePopup<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Alignment alignment = Alignment.center,
}) =>
    showGeneralDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel: 'Kapat',
      barrierColor: Colors.black.withOpacity(.68),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (ctx, _, __) => Align(alignment: alignment, child: builder(ctx)),
      transitionBuilder: (ctx, anim, _, child) {
        final curved =
            CurvedAnimation(parent: anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: ScaleTransition(
              scale: Tween<double>(begin: .88, end: 1).animate(curved), child: child),
        );
      },
    );

/// Altın çipin çizimi (Material ikonu yerine): parlak, kenarlı, ortasında yıldız.
class CoinIcon extends StatelessWidget {
  final double size;
  const CoinIcon({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    const rim = Color(0xFF9A6A12);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
            center: Alignment(-.35, -.45),
            radius: 1.0,
            colors: [Color(0xFFFFEFB0), AppColors.goldLight, Color(0xFFC08A22)]),
        border: Border.all(color: rim, width: (size * .07).clamp(1.0, 4.0)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(.35),
              blurRadius: size * .12,
              offset: Offset(0, size * .06))
        ],
      ),
      child: Center(
        child: Container(
          width: size * .64,
          height: size * .64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: rim.withOpacity(.55), width: (size * .045).clamp(.8, 3.0)),
          ),
          child: Icon(Icons.star_rounded, size: size * .38, color: rim.withOpacity(.85)),
        ),
      ),
    );
  }
}

/// Pencere çerçevesi: bordo gövde, çift altın kenar, üstte altın başlık şeridi,
/// sağ üstte kapatma düğmesi, altta eylem düğmeleri.
///
/// İçerik tek bir `SizedBox(width: maxWidth)` içindedir ve `FittedBox(scaleDown)` ile
/// sarılıdır: dar/alçak ekranda taşmaz, küçülür.
class GamePopup extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final IconData? icon;

  /// Başlık şeridinin içi (oda seçicideki oklu başlık gibi). Verilirse [title] yok sayılır.
  final Widget? ribbon;
  final Widget child;
  final List<Widget> actions;
  final VoidCallback? onClose;
  final double maxWidth;

  const GamePopup({
    super.key,
    this.title,
    this.subtitle,
    this.icon,
    this.ribbon,
    required this.child,
    this.actions = const [],
    this.onClose,
    this.maxWidth = 560,
  });

  Widget _ribbonBody() {
    if (ribbon != null) return ribbon!;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[
        Icon(icon, size: 22, color: AppColors.navy),
        const SizedBox(width: 8),
      ],
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text(title ?? '',
            style: const TextStyle(
                fontSize: 20,
                height: 1.1,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.6,
                color: AppColors.navy)),
        if (subtitle != null)
          Text(subtitle!,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy.withOpacity(.75))),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final panel = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.goldLight, Color(0xFFB98A2E)]),
        boxShadow: const [
          BoxShadow(color: Colors.black87, blurRadius: 28, offset: Offset(0, 10))
        ],
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 36, 18, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const RadialGradient(
              center: Alignment(0, -.6),
              radius: 1.3,
              colors: [Color(0xFF6A1B33), AppColors.surface, AppColors.bg]),
          border: Border.all(color: Colors.black54, width: 1.5),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          child,
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 14),
            // Dar ekranda düğmeler taşmasın (Right overflowed): sığmazsa birlikte küçülür.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 14),
                      actions[i],
                    ]
                  ]),
            ),
          ],
        ]),
      ),
    );

    final ribbonPlate = Container(
      constraints: const BoxConstraints(minWidth: 210),
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFE9A8), AppColors.goldLight, Color(0xFFD6A03A)]),
        border: Border.all(color: const Color(0xFF3A0B19), width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 3))
        ],
      ),
      child: _ribbonBody(),
    );

    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: maxWidth,
            child: Stack(clipBehavior: Clip.none, children: [
              Padding(padding: const EdgeInsets.only(top: 22), child: panel),
              Positioned(
                  top: 0, left: 0, right: 0, child: Center(child: ribbonPlate)),
              if (onClose != null)
                Positioned(
                  top: 20,
                  right: -8,
                  child: CandyButton(
                      onTap: onClose,
                      kind: CandyKind.red,
                      circle: true,
                      width: 36,
                      height: 36,
                      child: const Icon(Icons.close_rounded, size: 22)),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Pencere altındaki büyük eylem düğmesi (isteğe bağlı alt satırlı).
class PopupButton extends StatelessWidget {
  final String label;
  final String? sub;
  final IconData? icon;
  final CandyKind kind;
  final VoidCallback? onTap;
  final double width, height;

  /// Köşede küçük kırmızı etiket (ör. "2×").
  final String? tag;

  const PopupButton({
    super.key,
    required this.label,
    required this.onTap,
    this.sub,
    this.icon,
    this.kind = CandyKind.green,
    this.width = 200,
    this.height = 52,
    this.tag,
  });

  @override
  Widget build(BuildContext context) {
    final btn = CandyButton(
      onTap: onTap,
      kind: kind,
      radius: 16,
      width: width,
      height: height,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 6)],
          Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, height: 1.1))),
        ]),
        if (sub != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const CoinIcon(size: 14),
              const SizedBox(width: 4),
              Text(sub!, style: const TextStyle(fontSize: 12.5, height: 1)),
            ]),
          ),
      ]),
    );
    if (tag == null) return btn;
    return Stack(clipBehavior: Clip.none, children: [
      btn,
      Positioned(
        top: -8,
        right: -6,
        child: Transform.rotate(
          angle: .16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE5392F),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white, width: 1.4),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 3)],
            ),
            child: Text(tag!,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white)),
          ),
        ),
      ),
    ]);
  }
}

/// Evet/hayır onayı. Onaylanırsa true, vazgeçilirse/dışarı dokunulursa false döner.
Future<bool> showConfirmPopup(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'TAMAM',
  String cancelLabel = 'VAZGEÇ',
  IconData icon = Icons.help_outline_rounded,
  bool danger = false,
}) async {
  final r = await showGamePopup<bool>(
    context,
    builder: (ctx) => GamePopup(
      title: title,
      maxWidth: 400,
      onClose: () => Navigator.of(ctx).pop(false),
      actions: [
        PopupButton(
            label: cancelLabel,
            kind: CandyKind.gray,
            width: 150,
            height: 46,
            onTap: () => Navigator.of(ctx).pop(false)),
        PopupButton(
            label: confirmLabel,
            kind: danger ? CandyKind.red : CandyKind.green,
            width: 150,
            height: 46,
            onTap: () => Navigator.of(ctx).pop(true)),
      ],
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black26,
            border: Border.all(
                color: danger ? AppColors.bad : AppColors.gold, width: 2),
          ),
          child: Icon(icon, size: 30, color: danger ? AppColors.bad : AppColors.goldLight),
        ),
        const SizedBox(height: 10),
        Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14.5, height: 1.35, color: Colors.white)),
      ]),
    ),
  );
  return r == true;
}

/// Koyu "krater" zeminli bilgi plakası (etiket + değer), pencerelerde sık kullanılır.
class InfoPlate extends StatelessWidget {
  final String label;
  final String value;
  final bool coin;
  final bool bad;
  final IconData? trailing;
  const InfoPlate(
      {super.key,
      required this.label,
      required this.value,
      this.coin = false,
      this.bad = false,
      this.trailing});

  @override
  Widget build(BuildContext context) => Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.32),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: bad ? AppColors.bad.withOpacity(.8) : Colors.white12),
        ),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .4,
                      color: Colors.white70))),
          if (coin) ...[const CoinIcon(size: 17), const SizedBox(width: 5)],
          Text(value,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: bad ? AppColors.bad : Colors.white)),
          if (trailing != null) ...[
            const SizedBox(width: 5),
            Icon(trailing, size: 16, color: bad ? AppColors.bad : Colors.white70)
          ],
        ]),
      );
}
