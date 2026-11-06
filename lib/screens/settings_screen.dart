import '../widgets/responsive_shell.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../diagnostics/app_log.dart';
import '../widgets/about_box.dart';
import '../models/app_settings.dart';
import '../models/player.dart';
import '../services/account_service.dart';
import '../widgets/account_dialog.dart';
import '../theme/app_theme.dart';
import '../widgets/game_popup.dart';
import '../services/legal_consent_service.dart';
import 'legal_screen.dart';
import '../widgets/lobby_widgets.dart';

/// Ayarlar: genel ayarlar.
class SettingsScreen extends StatelessWidget {
  final Player? player;

  /// Verilirse sağ üstteki "HESABIM" düğmesi Misafir/Google hesap penceresini açar.
  final AccountService? account;

  /// Başka hesaba geçilince çağrılır (soket kapanır, uygulama yeni hesapla yeniden kurulur).
  final VoidCallback? onAccountSwitched;
  const SettingsScreen({super.key, this.player, this.account, this.onAccountSwitched});

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
                  child: _general(context, s),
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

  Widget _header(BuildContext c) {
    final back = RoundBtn(icon: Icons.arrow_back, kind: CandyKind.red, size: 40, onTap: () => Navigator.of(c).pop());
    final account = CandyButton(
        onTap: () => _account(c),
        kind: CandyKind.orange,
        radius: 10,
        width: 150,
        height: 36,
        child: const Text('HESABIM', style: TextStyle(fontSize: 13)));
    // Banner varsa başlık sola, banner ortaya: [geri] [AYARLAR] [banner boşluğu] [HESABIM]
    if (BannerSlotMarker.isAvailable(c)) {
      return SizedBox(
        height: math.max(48, BannerSlot.maybeOf(c)!.slotHeight),
        child: Row(children: [
          back,
          const SizedBox(width: 12),
          const Text('AYARLAR', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 2)),
          const Expanded(child: Center(child: BannerSlotMarker())),
          account,
        ]),
      );
    }
    return SizedBox(
      height: 48,
      child: Stack(alignment: Alignment.center, children: [
        const Text('AYARLAR', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 2)),
        Align(alignment: Alignment.centerLeft, child: back),
        Align(alignment: Alignment.centerRight, child: account),
      ]),
    );
  }

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
                child: Row(children: [
                  _label('SOHBET:'),
                  _Toggle(
                      icon: Icons.chat_bubble,
                      value: s.chat,
                      onChanged: (v) => s.update(() => s.chat = v)),
                  const Spacer(),
                  _label('DİL:'),
                  _LangBox(onTap: () => showToast(c, 'Şimdilik sadece Türkçe.')),
                ]),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _btn(c, 'Gizlilik Politikası', onTap: () => _legal(c, LegalKind.privacy))),
                const SizedBox(width: 6),
                Expanded(child: _btn(c, 'Hizmet Şartları', onTap: () => _legal(c, LegalKind.terms))),
                const SizedBox(width: 6),
                Expanded(child: AboutTapBox(playerId: player?.id)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: _btn(c, 'Kurallar')),
                const SizedBox(width: 6),
                Expanded(child: _btn(c, 'Nasıl Oynanır?')),
                const SizedBox(width: 6),
                Expanded(child: _btn(c, 'Hesabı Sil', onTap: () => _confirmDelete(c))),
              ]),
              // AB/AEA/BK: reklam izni (GDPR) istenen zaman geri alınabilir.
              if (LegalConsentService.I.showGdpr) ...[
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: _btn(c, 'Reklam İzni', onTap: () => _adConsent(c))),
                ]),
              ],
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

  void _legal(BuildContext c, LegalKind k) =>
      Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => LegalScreen(kind: k)));

  Future<void> _adConsent(BuildContext c) async {
    final on = LegalConsentService.I.adConsent;
    final ok = await showConfirmPopup(
      c,
      title: 'REKLAM İZNİ',
      message: on
          ? 'Reklam izni şu an AÇIK. Geri çekersen reklam ortakları verilerini işlemez.'
          : 'Reklam izni şu an KAPALI. İzin verirsen reklam ortakları reklam kimliğini işleyebilir.',
      confirmLabel: on ? 'GERİ ÇEK' : 'İZİN VER',
      icon: Icons.privacy_tip_rounded,
    );
    if (!ok) return;
    await LegalConsentService.I.setAdConsent(!on);
    if (c.mounted) showToast(c, on ? 'Reklam izni geri çekildi.' : 'Reklam izni verildi.');
  }

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
