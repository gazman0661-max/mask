import 'package:flutter/material.dart';
import '../logic/okey_rules.dart';
import '../models/player.dart';
import '../models/table_models.dart';
import '../models/tile.dart';
import '../theme/app_theme.dart';
import 'avatar.dart';
import 'player_badge.dart' show formatChips;
import 'rack_widget.dart';
import 'responsive_shell.dart';
import 'chip_icon.dart';

/// Masa bekleme / "OYUN BAŞLIYOR" ekranı. Arkada bordo çuha masa görünür, dört koltuk masanın etrafındadır
/// (ben altta, rakipler sol/üst/sağ); ortada küçük bir pencere durur.
///
/// [waiting] true iken masa henüz dolmamıştır: "OYUNCU BEKLENİYOR" (sayaç yok), çemberde dönen gösterge ve oturan sayısı
/// (örn. 2/4) çıkar; boş koltuklar nabız atar ve "Bekleniyor" yazar, biri oturunca avatarı büyüyerek gelir.
/// Masa dolunca ekran bu pencereyi geri sayımlı hâline çevirir: [seconds] çemberin içinde görünür, son 3 saniyede
/// çember kırmızıya döner. Geri sayım bitince ekran oyunu başlatır (başlama zili + giriş çipi düşer). Çip henüz düşmedi:
/// bu pencerede çıkan kimse bir şey kaybetmez. Biri kalkıp yerine başkası oturursa sayaç [kStartCountdownSeconds]'den
/// yeniden başlar. [onLeave] doluysa "MASADAN AYRIL" düğmesi çıkar (başlamadan kalkan hiçbir şey kaybetmez).
class GameStartPopup extends StatefulWidget {
  final int seconds;
  final TableSnapshot table;
  final bool waiting;
  final VoidCallback? onLeave;
  const GameStartPopup(
      {super.key, required this.seconds, required this.table, this.waiting = false, this.onLeave});

  @override
  State<GameStartPopup> createState() => _GameStartPopupState();
}

class _GameStartPopupState extends State<GameStartPopup> with SingleTickerProviderStateMixin {
  /// Boş koltuk nabzı (0..1 tekrar eder).
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Player _player(Seat s) {
    final t = widget.table;
    switch (s) {
      case Seat.me:
        return t.me;
      case Seat.left:
        return t.left;
      case Seat.top:
        return t.top;
      case Seat.right:
        return t.right;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(
        child: Stack(fit: StackFit.expand, children: [
          _felt(),
          const ColoredBox(color: Colors.black26),
          Align(alignment: Alignment.topCenter, child: Padding(padding: const EdgeInsets.only(top: 2), child: _seat(Seat.top, side: false))),
          Align(alignment: Alignment.bottomCenter, child: Padding(padding: const EdgeInsets.only(bottom: 2), child: _seat(Seat.me, side: false))),
          Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(left: 6), child: _seat(Seat.left, side: true))),
          Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.only(right: 6), child: _seat(Seat.right, side: true))),
          // Pencere, üst ve alt koltuğun arasına sığacak kadar küçülür (ıstaka yer kapladığı için).
          Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 50), child: _window())),
          // Banner: üst koltuğun sağında, sağ koltuğun üstünde (üst koltuk ve pencere ile çakışmaz)
          if (BannerSlotMarker.isAvailable(context))
            const Positioned(top: 0, right: 40, child: BannerSlotMarker()),
        ]),
      ),
      // Boş ıstaka: oyundakiyle aynı boy/konum (yan düğmeler kadar boşluk bırakılır), dokunulmaz.
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
        child: Row(children: [
          const SizedBox(width: 54),
          const SizedBox(width: 4),
          Expanded(
            child: IgnorePointer(
              child: RackWidget(
                key: const ValueKey<String>('bos-istaka'),
                slots: List<Tile?>.filled(32, null),
                columns: 16,
                okey: const Okey(1, TileColor.yellow),
                onMove: (_, __) {},
                onTapTile: (_) {},
              ),
            ),
          ),
          const SizedBox(width: 4),
          const SizedBox(width: 54),
        ]),
      ),
    ]);
  }

  // ------------------------------------------------------------ masa

  Widget _felt() => Padding(
        padding: const EdgeInsets.fromLTRB(62, 34, 62, 34),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: AppColors.feltDark, borderRadius: BorderRadius.circular(38)),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.felt,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: AppColors.gold.withOpacity(.5), width: 1),
            ),
          ),
        ),
      );

  // ------------------------------------------------------------ koltuk

  /// [side] true: sol/sağ koltuk (avatar üstte, isim altta). false: üst/alt koltuk (avatar solda, isim yanında).
  Widget _seat(Seat seat, {required bool side}) {
    final empty = widget.table.emptySeats.contains(seat);
    final p = _player(seat);
    final avatar = empty ? _emptyAvatar(seat) : _filledAvatar(p, seat == Seat.me);
    // Oturan insanın çip bakiyesi (bot ve bilinmeyende yok).
    final showChips = !empty && p.chipCount >= 0 && p.avatar != kBotAvatar;
    final name = SizedBox(
      width: side ? 76 : 88,
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: side ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            Text(empty ? 'Bekleniyor' : p.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: side ? TextAlign.center : TextAlign.start,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: empty ? Colors.white54 : Colors.white)),
            if (showChips)
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const ChipIcon(size: 10),
                  const SizedBox(width: 2),
                  Text(formatChips(p.chipCount),
                      style: const TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.goldLight)),
                ]),
              ),
          ]),
    );
    final child = side
        ? Column(mainAxisSize: MainAxisSize.min, children: [avatar, const SizedBox(height: 3), name])
        : Row(mainAxisSize: MainAxisSize.min, children: [avatar, const SizedBox(width: 6), name]);
    // Biri oturunca/kalkınca koltuk büyüyerek değişir.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      transitionBuilder: (w, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: w)),
      child: KeyedSubtree(
          key: ValueKey<String>('${seat.name}-${empty ? 'bos' : p.name}-${p.avatar}'), child: child),
    );
  }

  Widget _filledAvatar(Player p, bool me) => Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: me ? AppColors.goldLight : AppColors.gold.withOpacity(.6), width: 2)),
        child: AvatarWidget(index: p.avatar ?? 0, size: 40),
      );

  /// Boş koltuk: soluk daire + dışa doğru yayılan nabız halkası.
  Widget _emptyAvatar(Seat seat) => SizedBox(
        key: ValueKey<String>('bos-${seat.name}'),
        width: 48,
        height: 48,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) {
            final t = _pulse.value;
            return Stack(alignment: Alignment.center, children: [
              Container(
                width: 40 + 8 * t,
                height: 40 + 8 * t,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.gold.withOpacity(.35 * (1 - t)), width: 1.5)),
              ),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(.08),
                    border: Border.all(color: AppColors.gold.withOpacity(.55), width: 1.5)),
                child: const Icon(Icons.person_outline, size: 20, color: Colors.white38),
              ),
            ]);
          },
        ),
      );

  // ------------------------------------------------------------ pencere

  Widget _window() {
    final waiting = widget.waiting;
    final seconds = widget.seconds;
    final seated = 4 - widget.table.emptySeats.length;
    final urgent = !waiting && seconds <= 3;
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.surfaceLight, AppColors.surface, AppColors.bg]),
        border: Border.all(color: AppColors.gold, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 18)],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(waiting ? 'OYUNCU BEKLENİYOR' : 'OYUN BAŞLIYOR',
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                  color: AppColors.goldLight)),
          const SizedBox(height: 10),
          AnimatedContainer(
            key: const ValueKey<String>('geri-sayim'),
            duration: const Duration(milliseconds: 300),
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.bg,
              border: Border.all(color: urgent ? AppColors.bad : AppColors.goldLight, width: 4),
            ),
            child: waiting
                ? Column(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.goldLight)),
                    const SizedBox(height: 3),
                    Text('$seated/4',
                        key: const ValueKey<String>('oturan'),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
                  ])
                : AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (w, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: w)),
                    child: Text('$seconds',
                        key: ValueKey<int>(seconds),
                        style: TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w900,
                            color: urgent ? AppColors.bad : Colors.white)),
                  ),
          ),
          const SizedBox(height: 10),
          Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 4, children: [
            for (final r in widget.table.rules)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: r.on ? AppColors.good.withOpacity(.85) : Colors.black26,
                ),
                child: Text(r.label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: r.on ? Colors.white : Colors.white54)),
              ),
          ]),
          const SizedBox(height: 8),
          // Masanın giriş çipi ve havuz: bekleme / geri sayım penceresinde hep görünür.
          Container(
            key: const ValueKey<String>('masa-cipi'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Colors.black.withOpacity(.35),
              border: Border.all(color: AppColors.gold.withOpacity(.8)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const ChipIcon(size: 16),
              const SizedBox(width: 5),
              Text('MASA ${formatChips(widget.table.settings.bet)} ÇİP',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: .6, color: AppColors.goldLight)),
              const SizedBox(width: 8),
              Text('HAVUZ ${formatChips(widget.table.settings.bet * 4)}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white70)),
            ]),
          ),
          const SizedBox(height: 6),
          const Text('Giriş çipi oyun başlayınca düşer',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white60)),
          if (widget.onLeave != null) ...[
            const SizedBox(height: 10),
            ElevatedButton(
              key: const ValueKey<String>('masadan-ayril'),
              onPressed: widget.onLeave,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.bad,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
              child: const Text('MASADAN AYRIL',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: .8)),
            ),
          ],
        ]),
      ),
    );
  }
}
