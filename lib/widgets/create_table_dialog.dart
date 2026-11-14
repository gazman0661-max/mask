import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../diagnostics/app_log.dart';
import '../models/table_models.dart';
import '../models/rooms.dart';
import '../theme/app_theme.dart';
import 'game_popup.dart';
import 'lobby_widgets.dart';
import 'player_badge.dart' show formatChips;
import 'chip_icon.dart';

// --------------------------------------------------------------- masa kur

class NewTable {
  final String name;
  final TableSettings settings;
  const NewTable(this.name, this.settings);
}

/// Masa kurma penceresi. [showGamePopup] ile açılır, [NewTable] döner (vazgeçilirse null).
///
/// Sol: oda (ok tuşlarıyla değişir), GİRİŞ BAHSİ (odanın min-max aralığında kaydırıcıyla ya da klavye düğmesiyle elle yazılır),
/// oturmak için gereken çip (bahis x oda çarpanı) ve masa adı (otomatik: masa_1, masa_2...). Oda, kurulan masanın
/// [TableSettings.room]'udur; bahis [TableSettings.entry] olarak sunucuya gider (aralık dışını sunucu reddeder).
/// Sağ: kural seçenekleri (Tek/Eşli, Katlamalı, Yardım, El, Hız) ve MASAYI KUR düğmesi.
class CreateDialog extends StatefulWidget {
  final TableSettings? initial;
  const CreateDialog({super.key, this.initial});

  @override
  State<CreateDialog> createState() => CreateDialogState();
}

class CreateDialogState extends State<CreateDialog> {
  late TableSettings _s = widget.initial ?? const TableSettings();
  late int _bet = roomById(_s.room).clampBet(_s.bet);

  Room get _room => roomById(_s.room);

  /// Ok tuşları: bir önceki / sonraki oda; bahis yeni odanın aralığına çekilir (en düşük bahse döner).
  void _stepRoom(int d) {
    final i = (_room.id - 1 + d).clamp(0, kRooms.length - 1);
    final r = kRooms[i];
    if (r.id == _room.id) return;
    setState(() {
      _s = _s.copyWith(room: r.id);
      _bet = r.minBet;
    });
  }

  /// Klavye düğmesi: bahsi elle yaz. Aralık dışı kabul edilmez (hata yazısı çıkar), TAMAM'da bahis ayarlanır.
  Future<void> _typeBet() async {
    final r = _room;
    final ctrl = TextEditingController(text: '$_bet');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) {
        String? err;
        return StatefulBuilder(builder: (ctx, setD) {
          void ok() {
            final n = int.tryParse(ctrl.text.replaceAll(RegExp(r'[^0-9]'), ''));
            if (n == null || !r.hasBet(n)) {
              setD(() => err = '${formatChips(r.minBet)} ile ${formatChips(r.maxBet)} arası yaz');
              return;
            }
            Navigator.pop(ctx, n);
          }

          return AlertDialog(
            backgroundColor: AppColors.navy,
            title: Text('Bahis (${r.name})', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
              decoration: InputDecoration(
                hintText: '${formatChips(r.minBet)} - ${formatChips(r.maxBet)}',
                hintStyle: const TextStyle(color: Colors.white38),
                errorText: err,
                prefixIcon: const Padding(padding: EdgeInsets.all(12), child: ChipIcon(size: 24)),
              ),
              onSubmitted: (_) => ok(),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İPTAL')),
              TextButton(onPressed: ok, child: const Text('TAMAM')),
            ],
          );
        });
      },
    );
    if (v != null && mounted) setState(() => _bet = v);
  }

  void _submit() {
    Log.i('masa kur', 'gönder: oda=${_room.id} bahis=$_bet');
    Navigator.pop(context, NewTable('', _s.copyWith(entry: _bet))); // ad sunucuda otomatik verilir
  }

  /// Oda değiştirici: ‹ Oda adı (bahis aralığı) ›
  Widget _roomSwitcher() {
    final r = _room;
    Widget arrow(IconData ic, bool on, VoidCallback f) => GestureDetector(
          onTap: on ? f : null,
          child: Container(
            width: 34,
            height: 40,
            decoration: BoxDecoration(color: Colors.black.withOpacity(on ? .34 : .15), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
            child: Icon(ic, color: on ? AppColors.goldLight : Colors.white24, size: 26),
          ),
        );
    return Row(children: [
      arrow(Icons.chevron_left_rounded, r.id > 1, () => _stepRoom(-1)),
      Expanded(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text('${r.emoji} ${r.name}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white))),
          Text('${formatChips(r.minBet)} - ${formatChips(r.maxBet)} · seviye ${r.minLevel}+', style: const TextStyle(fontSize: 10, color: Colors.white60)),
        ]),
      ),
      arrow(Icons.chevron_right_rounded, r.id < kRooms.length, () => _stepRoom(1)),
    ]);
  }

  /// BAHİS: değer kutusu (dokununca elle yaz) + klavye düğmesi + min-max kaydırıcı.
  Widget _betPicker() {
    final r = _room;
    return Column(children: [
      GestureDetector(
        onTap: _typeBet,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: Colors.black.withOpacity(.34), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
          child: Row(children: [
            const ChipIcon(size: 22),
            const SizedBox(width: 6),
            const Text('BAHİS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: .6, color: Colors.white60)),
            Expanded(
              child: Text(formatChips(_bet),
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Colors.white)),
            ),
            const Icon(Icons.keyboard_alt_outlined, color: Colors.white70, size: 22),
          ]),
        ),
      ),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(activeTrackColor: AppColors.gold, thumbColor: AppColors.goldLight, inactiveTrackColor: Colors.white24, trackHeight: 4),
        child: Slider(
          value: _bet.toDouble().clamp(r.minBet.toDouble(), r.maxBet.toDouble()),
          min: r.minBet.toDouble(),
          max: r.maxBet.toDouble(),
          onChanged: (v) => setState(() => _bet = r.snapBet(v)),
        ),
      ),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(formatChips(r.minBet), style: const TextStyle(fontSize: 10, color: Colors.white54)),
        Text(formatChips(r.maxBet), style: const TextStyle(fontSize: 10, color: Colors.white54)),
      ]),
    ]);
  }

  // ---------------------------------------------------------------- parçalar

  Widget _row(String label, List<_SegOpt> opts) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(children: [
          SizedBox(
              width: 74,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .6,
                      color: Colors.white70))),
          Expanded(child: _Seg(opts: opts)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return GamePopup(
      title: 'MASA KUR',
      icon: Icons.style_rounded,
      maxWidth: 690,
      onClose: () => Navigator.pop(context),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 236,
          child: Column(children: [
            _roomSwitcher(),
            const SizedBox(height: 6),
            _betPicker(),
            const SizedBox(height: 4),
            InfoPlate(label: 'OTURMAK İÇİN', value: '${formatChips(_room.chipsFor(_bet))} çip'),
            const SizedBox(height: 8),
            const InfoPlate(label: 'MASA ADI', value: 'Otomatik'),
          ]),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(children: [
            _row('OYUN', [
              _SegOpt('Tek', !_s.team, () => setState(() => _s = _s.copyWith(team: false))),
              _SegOpt('Eşli', _s.team, () => setState(() => _s = _s.copyWith(team: true)),
                  sub: "2'ye 2"),
            ]),
            _row('AÇIŞ', [
              _SegOpt('Katlamalı', _s.folding,
                  () => setState(() => _s = _s.copyWith(folding: true)),
                  sub: 'baraj artar'),
              _SegOpt('Katlamasız', !_s.folding,
                  () => setState(() => _s = _s.copyWith(folding: false)),
                  sub: '101 sabit'),
            ]),
            _row('YARDIM', [
              _SegOpt('Yardımlı', _s.assisted,
                  () => setState(() => _s = _s.copyWith(assisted: true))),
              _SegOpt('Yardımsız', !_s.assisted,
                  () => setState(() => _s = _s.copyWith(assisted: false))),
            ]),
            _row('EL SAYISI', [
              for (final h in const [1, 2, 3, 4])
                _SegOpt('$h', _s.hands == h,
                    () => setState(() => _s = _s.copyWith(hands: h))),
            ]),
            _row('HIZ', [
              _SegOpt('Standart', !_s.turbo,
                  () => setState(() => _s = _s.copyWith(turbo: false)),
                  sub: '30 sn'),
              _SegOpt('Hızlı', _s.turbo,
                  () => setState(() => _s = _s.copyWith(turbo: true)),
                  sub: '15 sn'),
            ]),
            const SizedBox(height: 2),
            PopupButton(
              label: 'MASAYI KUR',
              icon: Icons.check_rounded,
              sub: '${formatChips(_bet)} çip giriş',
              kind: CandyKind.green,
              width: double.infinity,
              height: 54,
              onTap: _submit,
            ),
          ]),
        ),
      ]),
    );
  }
}

// -------------------------------------------------------------- yardımcılar

class _SegOpt {
  final String label;
  final String? sub;
  final bool on;
  final VoidCallback onTap;
  const _SegOpt(this.label, this.on, this.onTap, {this.sub});
}

/// Yan yana seçenek şeridi: seçili olan altın dolgulu.
class _Seg extends StatelessWidget {
  final List<_SegOpt> opts;
  const _Seg({required this.opts});

  @override
  Widget build(BuildContext context) => Container(
        height: 38,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.34),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(children: [
          for (final o in opts)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: o.onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: o.on
                        ? const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFFFFE9A8), AppColors.gold])
                        : null,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: o.on
                        ? const [BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(0, 1.5))]
                        : null,
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(o.label,
                          style: TextStyle(
                              fontSize: 12.5,
                              height: 1.1,
                              fontWeight: FontWeight.w900,
                              color: o.on ? AppColors.navy : Colors.white)),
                    ),
                    if (o.sub != null)
                      Text(o.sub!,
                          style: TextStyle(
                              fontSize: 8.5,
                              height: 1.1,
                              fontWeight: FontWeight.w700,
                              color: o.on ? AppColors.navy.withOpacity(.7) : Colors.white54)),
                  ]),
                ),
              ),
            ),
        ]),
      );
}
