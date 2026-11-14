import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../diagnostics/app_log.dart';
import '../models/invite.dart';
import '../services/invite_service.dart';
import '../theme/app_theme.dart';
import '../widgets/chip_icon.dart';
import '../widgets/lobby_widgets.dart';
import '../widgets/player_badge.dart' show formatChips;
import '../widgets/responsive_shell.dart';

/// Arkadaş davet ekranı: davet kodum, kademeli ödüller ve (4. seviyeye kadar) kod girme kutusu.
/// Ödüller oyuncunun MESAJ KUTUSUNA düşer; çipi oradan AL'a basarak alır.
class InviteScreen extends StatefulWidget {
  final InviteService service;

  /// Mesaj kutusunu açar (ödül gelince buraya yönlendirmek için).
  final VoidCallback? onOpenInbox;
  const InviteScreen({super.key, required this.service, this.onOpenInbox});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  static const _channel = MethodChannel('okey101/share');
  static const _storeLink = 'https://play.google.com/store/apps/details?id=com.astrofelyx.pro';

  final _codeCtl = TextEditingController();
  InviteStatus? _st;
  bool _loading = true;
  bool _redeeming = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await widget.service.status();
      Log.i('davet', 'durum: arkadaş=${s.count}/${s.maxInvites} kodGirilebilir=${s.canRedeem}');
      if (!mounted) return;
      setState(() {
        _st = s;
        _loading = false;
      });
    } catch (e, st) {
      Log.e('davet', 'durum alınamadı', e, st);
      if (!mounted) return;
      setState(() {
        _error = e is InviteException ? e.message : 'Davet bilgisi alınamadı.';
        _loading = false;
      });
    }
  }

  Future<void> _redeem() async {
    final raw = _codeCtl.text.trim();
    if (raw.isEmpty || _redeeming) return;
    FocusScope.of(context).unfocus();
    setState(() => _redeeming = true);
    try {
      await widget.service.redeem(raw);
      Log.i('davet', 'kod kabul edildi');
      if (!mounted) return;
      _codeCtl.clear();
      final s = _st;
      await _load();
      if (!mounted) return;
      setState(() => _redeeming = false);
      showToast(
          context,
          'Kod kabul edildi! ${s?.qualifyLevel ?? kInviteQualifyLevel}. seviyeye ulaşınca '
          '${formatChips(s?.inviteeBonus ?? kInviteeBonus)} çip mesaj kutuna gelecek.',
          kind: ToastKind.success);
    } catch (e, st) {
      Log.e('davet', 'kod girilemedi', e, st);
      if (!mounted) return;
      setState(() => _redeeming = false);
      showToast(context, e is InviteException ? e.message : 'Kod girilemedi.', kind: ToastKind.error);
    }
  }

  String _shareText(InviteStatus s) =>
      '101 Okey\'de masaya otur, benimle oyna! 🃏\n'
      'Davet kodum: ${formatInviteCode(s.code)}\n'
      'Uygulamada ARKADAŞ DAVET ET ekranından kodu gir; ${s.qualifyLevel}. seviyeye ulaşınca '
      '${formatChips(s.inviteeBonus)} çip hediye kazanırsın.\n'
      'İndir: $_storeLink';

  Future<void> _share() async {
    final s = _st;
    if (s == null || s.code.isEmpty) return;
    final text = _shareText(s);
    try {
      await _channel.invokeMethod<bool>('shareText', {'text': text, 'subject': '101 Okey daveti'});
      Log.i('davet', 'paylaşım menüsü açıldı');
    } on MissingPluginException {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) showToast(context, 'Davet mesajı panoya kopyalandı.');
    } on PlatformException catch (e, st) {
      Log.e('davet', 'paylaşım hatası', e, st);
      if (mounted) showToast(context, 'Paylaşılamadı.', kind: ToastKind.error);
    }
  }

  Future<void> _copy() async {
    final s = _st;
    if (s == null || s.code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: formatInviteCode(s.code)));
    if (mounted) showToast(context, 'Kod kopyalandı.');
  }

  // ------------------------------------------------------------------ iskelet

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Column(children: [
              Row(children: [
                RoundBtn(icon: Icons.arrow_back, onTap: () => Navigator.of(context).pop()),
                const SizedBox(width: 12),
                const Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('ARKADAŞ DAVET ET',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.goldLight)),
                  ),
                ),
                if (BannerSlotMarker.isAvailable(context))
                  const Expanded(child: Center(child: BannerSlotMarker()))
                else
                  const Spacer(),
                if (widget.onOpenInbox != null) ...[
                  RoundBtn(icon: Icons.mail_outline, onTap: widget.onOpenInbox!),
                  const SizedBox(width: 6),
                ],
                RoundBtn(icon: Icons.refresh, onTap: _load),
              ]),
              const SizedBox(height: 8),
              Expanded(child: _body()),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading && _st == null) return const Center(child: CircularProgressIndicator());
    if (_st == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error ?? 'Davet bilgisi alınamadı.',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Colors.white70)),
          const SizedBox(height: 12),
          CandyButton(
            onTap: _load,
            kind: CandyKind.orange,
            width: 160,
            height: 46,
            child: const Text('TEKRAR DENE', style: TextStyle(fontSize: 15)),
          ),
        ]),
      );
    }
    final s = _st!;
    return Column(children: [
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(children: [
                _codeCard(s),
                const SizedBox(height: 8),
                _progressCard(s),
                if (s.canRedeem || s.invited) ...[
                  const SizedBox(height: 8),
                  s.canRedeem ? _redeemCard(s) : _invitedCard(s),
                ],
              ]),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 8),
              child: _tiersPanel(s),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 6),
      SizedBox(
        width: 280,
        child: CandyButton(
          onTap: s.code.isEmpty ? null : _share,
          kind: CandyKind.orange,
          radius: 20,
          height: 54,
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.share_rounded, size: 24),
            SizedBox(width: 10),
            Text('DAVET ET', style: TextStyle(fontSize: 22)),
          ]),
        ),
      ),
    ]);
  }

  // ------------------------------------------------------------------ kartlar

  BoxDecoration _panel({bool glow = false}) => BoxDecoration(
        gradient: const LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AppColors.surfaceLight, AppColors.surface]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: glow ? AppColors.goldLight : AppColors.gold.withOpacity(.55), width: glow ? 2 : 1.5),
        boxShadow: glow ? [BoxShadow(color: AppColors.gold.withOpacity(.35), blurRadius: 8)] : null,
      );

  /// Davet kodu: her harf bir okey taşı.
  Widget _codeCard(InviteStatus s) {
    final code = formatInviteCode(s.code);
    const colors = [AppColors.tileRed, AppColors.tileBlue, AppColors.tileBlack, AppColors.tileYellow];
    var k = 0;
    final tiles = <Widget>[];
    for (final ch in code.characters) {
      if (ch == '-') {
        tiles.add(const SizedBox(width: 12));
        continue;
      }
      tiles.add(Container(
        width: 30,
        height: 40,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.tileCream,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: AppColors.tileEdge, width: 1.5),
          boxShadow: const [BoxShadow(color: Colors.black45, offset: Offset(0, 2), blurRadius: 2)],
        ),
        child: Text(ch,
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: colors[k++ % colors.length])),
      ));
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: _panel(glow: true),
      child: Column(children: [
        const Text('DAVET KODUN',
            style: TextStyle(fontSize: 12, letterSpacing: 1.6, fontWeight: FontWeight.w900, color: AppColors.goldLight)),
        const SizedBox(height: 6),
        FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisSize: MainAxisSize.min, children: tiles)),
        const SizedBox(height: 8),
        CandyButton(
          onTap: s.code.isEmpty ? null : _copy,
          kind: CandyKind.blue,
          radius: 12,
          width: 150,
          height: 34,
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.copy_rounded, size: 16),
            SizedBox(width: 6),
            Text('KOPYALA', style: TextStyle(fontSize: 13)),
          ]),
        ),
      ]),
    );
  }

  /// Seviyeye ulaşan arkadaş sayısı (en çok maxInvites).
  Widget _progressCard(InviteStatus s) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: _panel(),
      child: Column(children: [
        Row(children: [
          const Expanded(
            child: Text('ARKADAŞLARIN',
                style: TextStyle(fontSize: 12, letterSpacing: 1.6, fontWeight: FontWeight.w900, color: AppColors.goldLight)),
          ),
          Text('${s.count} / ${s.maxInvites}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
        ]),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < s.maxInvites; i++)
            Container(
              width: 30,
              height: 30,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < s.count ? AppColors.good.withOpacity(.25) : Colors.black26,
                border: Border.all(color: i < s.count ? AppColors.good : Colors.white24, width: 1.5),
              ),
              child: Icon(i < s.count ? Icons.check_rounded : Icons.person_outline,
                  size: 18, color: i < s.count ? AppColors.good : Colors.white38),
            ),
        ]),
        const SizedBox(height: 6),
        Text(
          s.pending > 0
              ? '${s.pending} arkadaşın daha ${s.qualifyLevel}. seviyeye ulaşmayı bekliyor.'
              : 'Arkadaşın kodunu girip ${s.qualifyLevel}. seviyeye ulaşınca sayılır.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11.5, color: Colors.white60),
        ),
      ]),
    );
  }

  /// Kod girme kutusu: yalnız hiç kod girilmemişse ve seviye hedefin altındaysa görünür.
  Widget _redeemCard(InviteStatus s) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: _panel(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('DAVET KODU GİR',
            style: TextStyle(fontSize: 12, letterSpacing: 1.6, fontWeight: FontWeight.w900, color: AppColors.goldLight)),
        const SizedBox(height: 4),
        Text(
          'Bir arkadaşın seni davet ettiyse kodunu gir. ${s.qualifyLevel}. seviyeye ulaşınca '
          '${formatChips(s.inviteeBonus)} çip hediyen mesaj kutuna gelir. Kod yalnızca ${s.qualifyLevel}. seviyeye kadar girilebilir.',
          style: const TextStyle(fontSize: 11.5, height: 1.3, color: Colors.white70),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _codeCtl,
              enabled: !_redeeming,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: (_) => _redeem(),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
                LengthLimitingTextInputFormatter(9),
                TextInputFormatter.withFunction((o, n) => n.copyWith(text: n.text.toUpperCase())),
              ],
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 3, color: Colors.white),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'ABCD-EFGH',
                hintStyle: const TextStyle(fontSize: 18, letterSpacing: 2, color: Colors.white24),
                filled: true,
                fillColor: Colors.black.withOpacity(.32),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.gold, width: 1.5)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          CandyButton(
            onTap: _redeeming ? null : _redeem,
            kind: CandyKind.green,
            radius: 12,
            width: 104,
            height: 42,
            child: Text(_redeeming ? '...' : 'KODU GİR', style: const TextStyle(fontSize: 14)),
          ),
        ]),
      ]),
    );
  }

  /// Kod girilmiş: ilerleme ya da hediye durumu.
  Widget _invitedCard(InviteStatus s) {
    final String title;
    final String text;
    final IconData icon;
    final Color color;
    if (!s.inviteeQualified) {
      title = 'DAVETİN KABUL EDİLDİ';
      text = '${s.qualifyLevel}. seviyeye ${s.xpLeft > 0 ? '${formatChips(s.xpLeft)} XP kaldı' : 'ulaşmak üzeresin'}. '
          'Ulaşınca ${formatChips(s.inviteeBonus)} çip hediyen mesaj kutuna gelir.';
      icon = Icons.hourglass_bottom_rounded;
      color = AppColors.gold;
    } else if (s.bonusClaimed) {
      title = 'DAVET HEDİYEN ALINDI';
      text = '${formatChips(s.inviteeBonus)} çip hesabına geçti. İyi oyunlar!';
      icon = Icons.check_circle_rounded;
      color = AppColors.good;
    } else {
      title = 'DAVET HEDİYEN HAZIR';
      text = '${formatChips(s.inviteeBonus)} çip mesaj kutunda seni bekliyor. AL\'a dokun!';
      icon = Icons.redeem_rounded;
      color = AppColors.goldLight;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: _panel(glow: s.inviteeQualified && !s.bonusClaimed),
      child: Row(children: [
        Icon(icon, size: 30, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(fontSize: 13, letterSpacing: 1.2, fontWeight: FontWeight.w900, color: color)),
            const SizedBox(height: 3),
            Text(text, style: const TextStyle(fontSize: 11.5, height: 1.3, color: Colors.white70)),
            if (s.inviteeQualified && !s.bonusClaimed && widget.onOpenInbox != null) ...[
              const SizedBox(height: 6),
              CandyButton(
                onTap: widget.onOpenInbox,
                kind: CandyKind.green,
                radius: 10,
                width: 150,
                height: 32,
                child: const Text('MESAJ KUTUSU', style: TextStyle(fontSize: 12.5)),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------------ kademeler

  Widget _tiersPanel(InviteStatus s) {
    final tiers = s.tiers.isNotEmpty
        ? s.tiers
        : [
            for (final e in kInviteTierChips.entries)
              InviteTier(count: e.key, chips: e.value, reached: false, sent: false, claimed: false)
          ];
    final next = s.nextTier;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Padding(
        padding: EdgeInsets.only(bottom: 6),
        child: Text('ARKADAŞ ÖDÜLLERİ',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, letterSpacing: 2, fontWeight: FontWeight.w900, color: AppColors.goldLight)),
      ),
      for (final t in tiers) ...[
        _tierCard(s, t, isNext: next != null && next.count == t.count),
        const SizedBox(height: 8),
      ],
      Text(
        'Arkadaşın kodunu girip ${s.qualifyLevel}. seviyeye ulaşınca sayılır. En fazla ${s.maxInvites} arkadaş '
        'sayılır. Ödüller mesaj kutuna düşer, AL\'a basınca çipin hesabına geçer.',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, height: 1.3, color: Colors.white54),
      ),
    ]);
  }

  Widget _tierCard(InviteStatus s, InviteTier t, {required bool isNext}) {
    final String stateText;
    final Color stateColor;
    final IconData stateIcon;
    if (t.claimed) {
      stateText = 'ALINDI';
      stateColor = AppColors.good;
      stateIcon = Icons.check_circle_rounded;
    } else if (t.sent) {
      stateText = 'MESAJ KUTUSUNDA';
      stateColor = AppColors.goldLight;
      stateIcon = Icons.mail_rounded;
    } else if (t.reached) {
      stateText = 'HAZIRLANIYOR';
      stateColor = AppColors.goldLight;
      stateIcon = Icons.hourglass_bottom_rounded;
    } else {
      stateText = '${s.count}/${t.count}';
      stateColor = Colors.white54;
      stateIcon = Icons.lock_outline_rounded;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: _panel(glow: isNext),
      child: Row(children: [
        // Sayı taşı
        Container(
          width: 38,
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.tileCream,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.tileEdge, width: 1.5),
            boxShadow: const [BoxShadow(color: Colors.black45, offset: Offset(0, 2), blurRadius: 2)],
          ),
          child: Text('${t.count}',
              style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: t.claimed ? AppColors.tileEdge : AppColors.tileRed)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${t.count} ARKADAŞ',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: t.claimed ? Colors.white54 : Colors.white)),
            const SizedBox(height: 2),
            Row(children: [
              const ChipIcon(size: 18),
              const SizedBox(width: 5),
              Flexible(
                child: Text('+${formatChips(t.chips)}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: t.claimed ? Colors.white38 : AppColors.goldLight)),
              ),
            ]),
          ]),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(.3),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: stateColor.withOpacity(.8)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(stateIcon, size: 15, color: stateColor),
            const SizedBox(width: 4),
            Text(stateText, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: stateColor)),
          ]),
        ),
      ]),
    );
  }
}
