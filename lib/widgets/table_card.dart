import 'package:flutter/material.dart';
import '../models/table_models.dart';
import '../theme/app_theme.dart';
import 'lobby_widgets.dart';

/// Oda listesindeki tek bir masanın görseli: ahşap kenarlı çuha, 4 koltuk,
/// ortada kural etiketleri, sol üstte bahis. Koltuk sırası: üst (masa sahibi),
/// alt, sol, sağ.
class TableCard extends StatelessWidget {
  final TableInfo table;
  final void Function(TableInfo) onSit;
  const TableCard({super.key, required this.table, required this.onSit});

  String _name(int i) {
    if (i < table.seatNames.length) return table.seatNames[i];
    return i == 0 ? table.hostName : 'Oyuncu';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final h = box.maxHeight;
      final double r = (h * .1).clamp(17.0, 28.0).toDouble();
      return Stack(clipBehavior: Clip.none, children: [
        // ahşap çerçeve
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(h * .26),
              gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.woodLight, AppColors.wood, AppColors.woodDark]),
              border: Border.all(color: Colors.black54, width: 2),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black54, offset: Offset(0, 5), blurRadius: 8)
              ],
            ),
          ),
        ),
        // çuha
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(h * .22),
                gradient: const RadialGradient(
                    radius: .9,
                    colors: [AppColors.wine, AppColors.wineDark]),
                border: Border.all(color: Colors.black38, width: 2),
              ),
            ),
          ),
        ),
        // koltuklar
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, h * .07, 18, h * .07),
            child: Stack(children: [
              Align(alignment: Alignment.topCenter, child: _seat(0, r)),
              Align(alignment: Alignment.bottomCenter, child: _seat(1, r)),
              Align(alignment: Alignment.centerLeft, child: _seat(2, r)),
              Align(
                  alignment: Alignment.centerRight,
                  child: _seat(3, r, reverse: true)),
            ]),
          ),
        ),
        // kurallar
        Align(alignment: Alignment.center, child: _rules()),
      ]);
    });
  }

  Widget _rules() {
    final labels = table.settings.chips;
    return SizedBox(
      width: 150,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final c in labels)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (c.label == 'Katlamalı' ||
                        c.label == 'Turbo' ||
                        c.label == 'Şifreli')
                    ? const Color(0xFFC4262E)
                    : Colors.black38,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(c.label,
                  style: const TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w800)),
            ),
        ],
      ),
    );
  }

  Widget _seat(int i, double r, {bool reverse = false}) {
    if (i >= table.playerCount) {
      final d = r * 2.1;
      return CandyButton(
          onTap: () => onSit(table),
          kind: CandyKind.green,
          circle: true,
          width: d,
          height: d,
          child: Text('OTUR', style: TextStyle(fontSize: r * .5)));
    }
    final avatar = Container(
      width: r * 2,
      height: r * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF7A1E38),
        border: Border.all(color: const Color(0xFF4A0F21), width: 3),
      ),
      child: Icon(Icons.person, color: Colors.white70, size: r * 1.3),
    );
    final label = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          reverse ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (i == 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
                color: const Color(0xFFB02A6B),
                borderRadius: BorderRadius.circular(4)),
            child: const Text('Masa Sahibi',
                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800)),
          ),
        Container(
          constraints: const BoxConstraints(maxWidth: 74),
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
              color: AppColors.navy, borderRadius: BorderRadius.circular(6)),
          child: Text(_name(i),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        ),
      ],
    );
    return Row(
        mainAxisSize: MainAxisSize.min,
        children: reverse
            ? [label, const SizedBox(width: 4), avatar]
            : [avatar, const SizedBox(width: 4), label]);
  }
}
