import 'dart:async';
import 'package:flutter/material.dart';
import '../diagnostics/app_log.dart';
import '../theme/app_theme.dart';
import 'chip_icon.dart';

/// Kısa bildirimin türü: rengi ve ikonu buna göre değişir.
enum ToastKind { info, success, warn, error }

/// Oyunun kendi bildirimi. Sistem SnackBar'ı (alttan çıkan tam genişlikli şerit)
/// yerine üstten kayarak inen, altın çerçeveli yuvarlak bir kapsül gösterir.
/// Aynı anda tek bildirim vardır; yenisi eskisinin yerine geçer. Dokunuşları engellemez.
class GameToast {
  GameToast._();

  static OverlayEntry? _entry;
  static Timer? _timer;

  static void show(
    BuildContext context,
    String message, {
    ToastKind kind = ToastKind.info,
    IconData? icon,
    Duration duration = const Duration(milliseconds: 2600),
  }) {
    Log.i('bildirim', 'kullanıcıya gösterildi: $message');
    OverlayState? overlay;
    try {
      overlay = Overlay.maybeOf(context, rootOverlay: true);
    } catch (_) {
      overlay = null; // bağlam artık ekranda değil
    }
    if (overlay == null) return;
    _removeNow();

    final key = GlobalKey<_ToastViewState>();
    late final OverlayEntry entry;
    entry = OverlayEntry(
        builder: (_) => _ToastView(
            key: key, message: message, kind: kind, icon: icon));
    _entry = entry;
    overlay.insert(entry);
    _timer = Timer(duration, () async {
      await key.currentState?.hide();
      if (identical(_entry, entry)) _removeNow();
    });
  }

  static void _removeNow() {
    _timer?.cancel();
    _timer = null;
    final e = _entry;
    _entry = null;
    try {
      e?.remove();
    } catch (_) {}
  }
}

class _ToastView extends StatefulWidget {
  final String message;
  final ToastKind kind;
  final IconData? icon;
  const _ToastView({super.key, required this.message, required this.kind, this.icon});

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 220))
    ..forward();

  Future<void> hide() async {
    if (!mounted) return;
    try {
      await _c.reverse();
    } catch (_) {}
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  (Color, IconData) get _style => switch (widget.kind) {
        ToastKind.info => (AppColors.gold, Icons.info_rounded),
        ToastKind.success => (AppColors.good, Icons.check_rounded),
        ToastKind.warn => (AppColors.orange, Icons.priority_high_rounded),
        ToastKind.error => (AppColors.bad, Icons.close_rounded),
      };

  @override
  Widget build(BuildContext context) {
    final (color, defIcon) = _style;
    final curved = CurvedAnimation(
        parent: _c, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 60, left: 16, right: 16),
          child: FadeTransition(
            opacity: _c,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, -1.4), end: Offset.zero)
                  .animate(curved),
              child: Material(
                type: MaterialType.transparency,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(6, 6, 18, 6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [AppColors.surfaceLight, AppColors.bg]),
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(color: color.withOpacity(.9), width: 1.6),
                      boxShadow: [
                        const BoxShadow(
                            color: Colors.black54, blurRadius: 14, offset: Offset(0, 5)),
                        BoxShadow(color: color.withOpacity(.25), blurRadius: 16),
                      ],
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [color, Color.lerp(color, Colors.black, .35)!]),
                          border: Border.all(color: Colors.black45, width: 1.2),
                        ),
                        child: widget.icon == Icons.monetization_on_rounded
                            ? const Center(child: ChipIcon(size: 20))
                            : Icon(widget.icon ?? defIcon,
                                size: 19,
                                color: widget.kind == ToastKind.info
                                    ? AppColors.navy
                                    : Colors.white),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(widget.message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13.5,
                                height: 1.2,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
