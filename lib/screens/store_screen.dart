import '../widgets/responsive_shell.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../diagnostics/app_log.dart';
import '../models/store_pack.dart';
import '../theme/app_theme.dart';
import '../widgets/lobby_widgets.dart';
import '../widgets/player_badge.dart' show formatChips;
import '../widgets/chip_icon.dart';

/// Mağaza: çip paketleri. Şimdilik yalnız arayüz; satın alma ve fiyatlar Google Play'e bağlanınca dolacak.
///  - [prices]: ürün kimliği → Play'in yerel fiyat metni (örn. "₺49,99"). Boşsa butonda "SATIN AL" yazar.
///  - [onBuy]: pakete / butona dokunulunca çağrılır. Null ise "yakında" bildirimi çıkar.
class StoreScreen extends StatefulWidget {
  final int? chips;
  final Map<String, String> prices;
  final void Function(StorePack pack)? onBuy;
  const StoreScreen({super.key, this.chips, this.prices = const {}, this.onBuy});

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> with TickerProviderStateMixin {
  /// Kartlar sırayla yukarı kayarak belirir.
  late final AnimationController _in =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..forward();

  /// Öne çıkan kartın altın parıltısı.
  late final AnimationController _glow =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    _in.dispose();
    _glow.dispose();
    super.dispose();
  }

  void _buy(StorePack p) {
    Log.i('market', 'paket seçildi: ${p.productId} (${p.chips} çip)');
    final cb = widget.onBuy;
    if (cb != null) {
      cb(p);
    } else {
      showToast(context, 'Satın alma çok yakında geliyor.');
    }
  }

  Widget _header() => Row(children: [
        RoundBtn(icon: Icons.arrow_back, onTap: () => Navigator.of(context).pop()),
        const SizedBox(width: 12),
        const Icon(Icons.storefront_rounded, color: AppColors.goldLight, size: 26),
        const SizedBox(width: 8),
        const Text('MAĞAZA',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: AppColors.goldLight)),
        if (BannerSlotMarker.isAvailable(context))
          const Expanded(child: Center(child: BannerSlotMarker()))
        else
          const Spacer(),
        Container(
          padding: const EdgeInsets.fromLTRB(10, 5, 12, 5),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF7A1E38), AppColors.navy]),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black38),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const ChipIcon(size: 20),
            const SizedBox(width: 6),
            Text(widget.chips == null ? '-' : formatChips(widget.chips!),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          ]),
        ),
      ]);

  Widget _packs() {
    final n = kStorePacks.length;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 190.0 * 5),
        child: AnimatedBuilder(
          animation: _in,
          builder: (_, __) => Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < n; i++)
              Expanded(
                child: Builder(builder: (_) {
                  // her kart bir öncekinden .1 geç başlar
                  final t = Curves.easeOutBack.transform(((_in.value - i * .1) / .5).clamp(0.0, 1.0).toDouble());
                  return Opacity(
                    opacity: t.clamp(0.0, 1.0).toDouble(),
                    child: Transform.translate(
                      offset: Offset(0, 28 * (1 - t)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        child: _PackCard(
                          pack: kStorePacks[i],
                          fan: i + 1,
                          price: widget.prices[kStorePacks[i].productId],
                          glow: _glow,
                          onTap: () => _buy(kStorePacks[i]),
                        ),
                      ),
                    ),
                  );
                }),
              ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Column(children: [
              _header(),
              const SizedBox(height: 6),
              Expanded(child: _packs()),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Tek paket kartı: üstte "N ÇİP", ortada paketle büyüyen çip yığını, altta satın al butonu.
class _PackCard extends StatelessWidget {
  final StorePack pack;
  final int fan; // yığındaki çip sayısı 1..5 (paket büyüdükçe artar)
  final String? price;
  final Animation<double> glow;
  final VoidCallback onTap;
  const _PackCard({required this.pack, required this.fan, required this.price, required this.glow, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hot = pack.badge != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedBuilder(
        animation: glow,
        builder: (_, child) => Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF7A1E38), AppColors.navy]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: hot ? AppColors.goldLight : AppColors.gold.withOpacity(.55), width: hot ? 2.5 : 1.5),
            boxShadow: [
              if (hot)
                BoxShadow(color: AppColors.goldLight.withOpacity(.25 + .35 * glow.value), blurRadius: 10 + 10 * glow.value)
              else
                const BoxShadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 3)),
            ],
          ),
          child: child,
        ),
        child: Stack(clipBehavior: Clip.none, children: [
          Column(children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(.28),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Text('${formatChips(pack.chips)} ÇİP',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: .6)),
            ),
            Expanded(
              child: Stack(alignment: Alignment.center, children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(colors: [
                        AppColors.goldLight.withOpacity(.32),
                        AppColors.goldLight.withOpacity(0),
                      ], radius: .75),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: FittedBox(fit: BoxFit.scaleDown, child: _CoinFan(count: fan)),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
              child: CandyButton(
                onTap: onTap,
                kind: CandyKind.green,
                radius: 12,
                height: 38,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(price ?? 'SATIN AL',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: .4)),
                ),
              ),
            ),
          ]),
          if (pack.badge != null)
            Positioned(
              top: -9,
              left: -7,
              child: Transform.rotate(
                angle: -.14,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB3221A),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: AppColors.goldLight, width: 1.2),
                  ),
                  child: Text(pack.badge!,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: .8)),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Yelpaze gibi açılmış çip yığını; [count] arttıkça yığın büyür.
class _CoinFan extends StatelessWidget {
  final int count;
  const _CoinFan({required this.count});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 84,
      child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
        for (var j = 0; j < count; j++)
          Builder(builder: (_) {
            final k = j - (count - 1) / 2; // ortaya göre konum
            return Transform.translate(
              offset: Offset(k * 15, k.abs() * 3),
              child: Transform.rotate(
                angle: k * .26,
                child: const ChipIcon(size: 58, shadow: true),
              ),
            );
          }),
        if (count >= 5) ...[
          Positioned(top: 0, right: 6, child: Transform.rotate(angle: math.pi / 10, child: const _Sparkle(18))),
          const Positioned(top: 8, left: 8, child: _Sparkle(14)),
        ],
      ]),
    );
  }
}

class _Sparkle extends StatelessWidget {
  final double size;
  const _Sparkle(this.size);
  @override
  Widget build(BuildContext context) => Icon(Icons.auto_awesome, size: size, color: Colors.white);
}
