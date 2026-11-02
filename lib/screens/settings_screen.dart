import 'package:flutter/material.dart';
import '../diagnostics/app_log.dart';
import '../widgets/about_box.dart';
import '../models/app_settings.dart';
import '../models/player.dart';
import '../services/account_service.dart';
import '../widgets/account_dialog.dart';
import '../theme/app_theme.dart';
import '../widgets/game_popup.dart';
import '../widgets/lobby_widgets.dart';

/// Ayarlar: sol tarafta genel ayarlar, sağda "Hemen Oyna" tercihleri.
class SettingsScreen extends StatelessWidget {
  final Player? player;

  /// Verilirse sağ üstteki "HESABIM" düğmesi Misafir/Google hesap penceresini açar.
  final AccountService? account;

  /// Başka hesaba geçilince çağrılır (soket kapanır, uygulama yeni hesapla yeniden kurulur).
  final VoidCallback? onAccountSwitched;
  const SettingsScreen({super.key, this.player, this.account, this.onAccountSwitched});

  static const _hands = [1, 2, 3, 4];

  void _soon(BuildContext c) => showToast(c, 'Çok yakında!');

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.I;
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: AnimatedBuilder(
            animation: s,
            builder: (_, __) => Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              child: Column(children: [
                _header(context),
                const SizedBox(height: 4),
                Expanded(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 11, child: _general(context, s)),
                    const SizedBox(width: 12),
                    Expanded(flex: 8, child: _quickSettings(context, s)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _account(BuildContext c) async {
    final a = account;
    if (a == null) return _soon(c);
    final switched = await showGamePopup<bool>(c,
        builder: (_) => AccountDialog(account: a, onSwitched: onAccountSwitched ?? () {}));
    // Hesap değişti: ayarlar eski oyuncuyu gösterir, kapat. Uygulama yeni hesapla yeniden kurulur.
    if (switched == true && c.mounted) Navigator.of(c).pop();
  }

  Widget _header(BuildContext c) => SizedBox(
        height: 48,
        child: Stack(alignment: Alignment.center, children: [
          const Text('AYARLAR',
              style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 2)),
          Align(
              alignment: Alignment.centerLeft,
              child: RoundBtn(
                  icon: Icons.arrow_back,
                  kind: CandyKind.red,
                  size: 40,
                  onTap: () => Navigator.of(c).pop())),
          Align(
              alignment: Alignment.centerRight,
              child: CandyButton(
                  onTap: () => _account(c),
                  kind: CandyKind.orange,
                  radius: 10,
                  width: 150,
                  height: 36,
                  child: const Text('HESABIM',
                      style: TextStyle(fontSize: 13)))),
        ]),
      );

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 1)),
      );

  BoxDecoration get _panel => BoxDecoration(
        color: const Color(0xFF4A0F21),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3B24E), width: 2),
        boxShadow: [
          BoxShadow(color: const Color(0xFFE3B24E).withOpacity(.35), blurRadius: 8)
        ],
      );

  // ------------------------------------------------------------ genel

  Widget _general(BuildContext c, AppSettings s) => Column(children: [
        _title('GENEL AYARLAR'),
        Expanded(
          child: Container(
            decoration: _panel,
            padding: const EdgeInsets.all(10),
            child: SingleChildScrollView(child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _Toggle(
                    icon: Icons.music_note,
                    value: s.music,
                    onChanged: (v) => s.update(() => s.music = v)),
                _Toggle(
                    icon: Icons.volume_up,
                    value: s.sound,
                    onChanged: (v) => s.update(() => s.sound = v)),
                _Toggle(
                    icon: Icons.vibration,
                    value: s.vibration,
                    onChanged: (v) => s.update(() => s.vibration = v)),
              ]),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.04),
                    borderRadius: BorderRadius.circular(8)),
                child: Column(children: [
                  Row(children: [
                    _label('ARKADAŞLIK:'),
                    _Toggle(
                        icon: Icons.group_add,
                        value: s.friends,
                        onChanged: (v) => s.update(() => s.friends = v)),
                    const Spacer(),
                    _label('SOHBET:'),
                    _Toggle(
                        icon: Icons.chat_bubble,
                        value: s.chat,
                        onChanged: (v) => s.update(() => s.chat = v)),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    _label('MASA DAVETİ:'),
                    _Toggle(
                        icon: Icons.mail,
                        value: s.invites,
                        onChanged: (v) => s.update(() => s.invites = v)),
                    const Spacer(),
                    _label('DİL:'),
                    _LangBox(onTap: () => showToast(c, 'Şimdilik sadece Türkçe.')),
                  ]),
                ]),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _btn(c, 'Gizlilik Politikası')),
                const SizedBox(width: 6),
                Expanded(child: _btn(c, 'Hizmet Şartları')),
                const SizedBox(width: 6),
                Expanded(child: AboutTapBox(playerId: player?.id)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: _btn(c, 'Öneriler')),
                const SizedBox(width: 6),
                Expanded(child: _btn(c, 'Veri Talebi')),
                const SizedBox(width: 6),
                Expanded(child: _btn(c, 'Hesabı Sil', onTap: () => _confirmDelete(c))),
              ]),
            ])),
          ),
        ),
      ]);

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Text(t,
            style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white)),
      );

  Widget _btn(BuildContext c, String t, {VoidCallback? onTap}) => CandyButton(
      onTap: onTap ?? () => _soon(c),
      kind: CandyKind.navy,
      radius: 9,
      height: 42,
      child: Text(t, style: const TextStyle(fontSize: 12)));

  void _confirmDelete(BuildContext c) {
    Log.i('ayar', 'Hesabı Sil penceresi açıldı');
    _confirmDeleteDialog(c);
  }

  Future<void> _confirmDeleteDialog(BuildContext c) async {
    final ok = await showConfirmPopup(
      c,
      title: 'HESABI SİL',
      message: 'Hesabın ve tüm verilerin kalıcı olarak silinir.\nEmin misin?',
      confirmLabel: 'SİL',
      icon: Icons.delete_forever_rounded,
      danger: true,
    );
    if (!ok) {
      Log.i('ayar', 'hesap silme: vazgeçildi');
      return;
    }
    Log.w('ayar', 'hesap silme: ONAYLANDI (backend yok, işlem yapılmadı)');
    if (c.mounted) {
      showToast(c, 'Hesap silme backend bağlanınca çalışacak.', kind: ToastKind.warn);
    }
  }

  // ------------------------------------------------------- hemen oyna

  Widget _quickSettings(BuildContext c, AppSettings s) {
    String tri(bool? v, String a, String b) =>
        v == null ? 'FARK ETMEZ' : (v ? a : b).toUpperCase();
    bool? cycle(bool? v) => v == null ? true : (v ? false : null);
    bool? cycleBack(bool? v) => v == null ? false : (v ? null : true);
    final hi = _hands.indexOf(s.hands);
    return Column(children: [
      _title('HEMEN OYNA AYARLARI'),
      Expanded(
        child: Column(children: [
          Expanded(
            child: Container(
              decoration: _panel,
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: SingleChildScrollView(child: Column(children: [
                const Text('Hızlı başlangıçta oyun bu ayarlarla açılır.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Color(0xFFE8D9B8))),
                const SizedBox(height: 4),
                _stepRow(
                    '${s.hands} EL',
                    hi > 0 ? () => s.update(() => s.hands = _hands[hi - 1]) : null,
                    hi < _hands.length - 1
                        ? () => s.update(() => s.hands = _hands[hi + 1])
                        : null,
                    plusMinus: true),
                _sel('Tek / Eşli', tri(s.team, 'Eşli', 'Tek'),
                    () => s.update(() => s.team = cycleBack(s.team)),
                    () => s.update(() => s.team = cycle(s.team))),
                _sel('Yardımlı / Yardımsız', tri(s.assisted, 'Yardımlı', 'Yardımsız'),
                    () => s.update(() => s.assisted = cycleBack(s.assisted)),
                    () => s.update(() => s.assisted = cycle(s.assisted))),
                _sel('Katlamalı / Katlamasız', tri(s.folding, 'Katlamalı', 'Katlamasız'),
                    () => s.update(() => s.folding = cycleBack(s.folding)),
                    () => s.update(() => s.folding = cycle(s.folding))),
              ])),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            decoration: _panel,
            padding: const EdgeInsets.all(6),
            child: Row(children: [
              Expanded(child: _btn(c, 'Kurallar')),
              const SizedBox(width: 6),
              Expanded(child: _btn(c, 'Nasıl Oynanır?')),
            ]),
          ),
        ]),
      ),
    ]);
  }

  Widget _valueBox(String t) => Expanded(
        child: Container(
          height: 28,
          alignment: Alignment.center,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
              color: const Color(0xFF3A0B19),
              borderRadius: BorderRadius.circular(6)),
          child: Text(t,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
        ),
      );

  Widget _stepRow(String t, VoidCallback? minus, VoidCallback? plus,
          {bool plusMinus = false}) =>
      Row(children: [
        CandyButton(
            onTap: minus,
            kind: CandyKind.gray,
            radius: 7,
            width: 36,
            height: 30,
            child: const Icon(Icons.remove, size: 20)),
        _valueBox(t),
        CandyButton(
            onTap: plus,
            kind: CandyKind.navy,
            radius: 7,
            width: 36,
            height: 30,
            child: const Icon(Icons.add, size: 20)),
      ]);

  Widget _sel(String label, String value, VoidCallback prev, VoidCallback next,
          {VoidCallback? onBlocked}) =>
      Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Column(children: [
          Text(label,
              style: const TextStyle(fontSize: 11.5, color: Color(0xFFE8D9B8))),
          Row(children: [
            CandyButton(
                onTap: prev,
                kind: CandyKind.navy,
                radius: 7,
                width: 36,
                height: 30,
                child: const Icon(Icons.chevron_left, size: 24)),
            _valueBox(value),
            CandyButton(
                onTap: onBlocked ?? next,
                kind: CandyKind.navy,
                radius: 7,
                width: 36,
                height: 30,
                child: const Icon(Icons.chevron_right, size: 24)),
          ]),
        ]),
      );
}

/// Yeşil açık/kapalı çubuğu + sağında ikonlu düğme.
class _Toggle extends StatelessWidget {
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _Toggle(
      {required this.icon, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: SizedBox(
          width: 104,
          height: 40,
          child: Stack(alignment: Alignment.centerRight, children: [
            Container(
              width: 80,
              height: 28,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 18),
              decoration: BoxDecoration(
                color: value ? const Color(0xFF2E7D32) : const Color(0xFF8E2A2A),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: Colors.black38),
              ),
              child: Text(value ? 'I' : 'O',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900)),
            ),
            CandyButton(
                onTap: () => onChanged(!value),
                kind: CandyKind.navy,
                radius: 9,
                width: 42,
                height: 40,
                child: Icon(icon, size: 22, color: value ? Colors.white : Colors.white54)),
          ]),
        ),
      );
}

class _LangBox extends StatelessWidget {
  final VoidCallback onTap;
  const _LangBox({required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Row(children: [
          Container(
            width: 70,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: const Color(0xFF3A0B19),
                borderRadius: BorderRadius.circular(6)),
            child: const Text('TÜRKÇE',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 4),
          CandyButton(
              onTap: onTap,
              kind: CandyKind.navy,
              radius: 8,
              width: 34,
              height: 32,
              child: const Icon(Icons.expand_more, size: 22)),
        ]),
      );
}
