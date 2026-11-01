import 'package:flutter/material.dart';
import '../diagnostics/app_log.dart';
import '../models/table_models.dart';
import '../theme/app_theme.dart';
import 'game_popup.dart';
import 'lobby_widgets.dart';

// --------------------------------------------------------------- masa kur

class NewTable {
  final String name;
  final TableSettings settings;
  const NewTable(this.name, this.settings);
}

/// Masa kurma penceresi. [showGamePopup] ile açılır, [NewTable] döner (vazgeçilirse null).
///
/// Sol: giriş bileti + masa adı (otomatik, değiştirilemez: masa_1, masa_2...).
/// Sağ: kural seçenekleri (Tek/Eşli, Katlamalı, Yardım, El, Hız) ve MASAYI KUR düğmesi.
class CreateDialog extends StatefulWidget {
  final TableSettings? initial;
  const CreateDialog({super.key, this.initial});

  @override
  State<CreateDialog> createState() => CreateDialogState();
}

class CreateDialogState extends State<CreateDialog> {
  late TableSettings _s = widget.initial ?? const TableSettings();

  void _submit() {
    Log.i('masa kur', 'gönder');
    Navigator.pop(context, NewTable('', _s)); // ad sunucuda otomatik verilir
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
            const InfoPlate(label: 'GİRİŞ', value: '1 bilet'),
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
              _SegOpt('Normal', !_s.turbo,
                  () => setState(() => _s = _s.copyWith(turbo: false)),
                  sub: '30 sn'),
              _SegOpt('Turbo', _s.turbo,
                  () => setState(() => _s = _s.copyWith(turbo: true)),
                  sub: '15 sn'),
            ]),
            const SizedBox(height: 2),
            PopupButton(
              label: 'MASAYI KUR',
              icon: Icons.check_rounded,
              sub: '1 bilet',
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
