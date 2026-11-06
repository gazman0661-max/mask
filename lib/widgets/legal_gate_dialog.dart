import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../screens/legal_screen.dart';
import '../services/legal_consent_service.dart';
import '../theme/app_theme.dart';
import 'game_popup.dart';
import 'lobby_widgets.dart' show CandyKind;

/// İlk açılış zorunlu onay penceresi. Kapatılamaz: ya KABUL ET ya da REDDET (uygulamadan çıkış).
/// AB/AEA/BK cihazlarında ek olarak açık GDPR reklam izni kutusu çıkar.
class LegalGateDialog extends StatefulWidget {
  const LegalGateDialog({super.key});

  static Future<void> show(BuildContext context) => showGamePopup<void>(
        context,
        barrierDismissible: false,
        builder: (_) => const LegalGateDialog(),
      );

  @override
  State<LegalGateDialog> createState() => _LegalGateDialogState();
}

class _LegalGateDialogState extends State<LegalGateDialog> {
  bool _terms = false;
  bool _privacy = false;
  bool _age = false;
  bool _gdpr = false;
  bool _busy = false;
  final _termsTap = TapGestureRecognizer();
  final _privacyTap = TapGestureRecognizer();
  late final bool _showGdpr = LegalConsentService.I.showGdpr;

  @override
  void initState() {
    super.initState();
    _termsTap.onTap = () => _open(LegalKind.terms);
    _privacyTap.onTap = () => _open(LegalKind.privacy);
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  void _open(LegalKind k) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LegalScreen(kind: k)));

  bool get _ready => _terms && _privacy && _age && (!_showGdpr || _gdpr);

  Future<void> _accept() async {
    if (!_ready || _busy) return;
    setState(() => _busy = true);
    await LegalConsentService.I.accept(adConsent: _showGdpr && _gdpr);
    if (mounted) Navigator.of(context).pop();
  }

  void _decline() => SystemNavigator.pop();

  Widget _check(bool value, ValueChanged<bool> onChanged, InlineSpan label) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 26,
              height: 26,
              child: Checkbox(
                value: value,
                activeColor: AppColors.green,
                checkColor: Colors.white,
                side: const BorderSide(color: AppColors.gold, width: 2),
                visualDensity: VisualDensity.compact,
                onChanged: (v) => onChanged(v ?? false),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(label,
                  style: const TextStyle(
                      fontSize: 13.5, height: 1.3, color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      );

  TextSpan _link(String text, TapGestureRecognizer r) => TextSpan(
        text: text,
        recognizer: r,
        style: const TextStyle(
            color: AppColors.goldLight, decoration: TextDecoration.underline, fontWeight: FontWeight.w900),
      );

  Widget _left() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
            'Oynamak için Hizmet Şartları\'nı ve Gizlilik Politikası\'nı kabul etmen gerekiyor. '
            'Altı çizili yazılara dokunarak okuyabilirsin.',
            style: TextStyle(fontSize: 13, height: 1.3, color: Colors.white70)),
        const SizedBox(height: 8),
        _check(_terms, (v) => setState(() => _terms = v), TextSpan(children: [
          _link('Hizmet Şartları', _termsTap),
          const TextSpan(text: '\'nı okudum ve kabul ediyorum.'),
        ])),
        _check(_privacy, (v) => setState(() => _privacy = v), TextSpan(children: [
          _link('Gizlilik Politikası', _privacyTap),
          const TextSpan(text: '\'nı okudum ve kabul ediyorum.'),
        ])),
        _check(_age, (v) => setState(() => _age = v), const TextSpan(
            text: '13 yaşından büyük olduğumu onaylıyorum. 18 yaşından küçüksem ebeveynimin izniyle oynuyorum.')),
      ]);

  Widget _gdprBox() => Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.gold.withOpacity(.7), width: 1.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('AB / AEA / BK (GDPR)',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: AppColors.goldLight)),
          const SizedBox(height: 3),
          const Text(
              'Hesabın ve oyun verilerin sunucuda tutulur. Reklam ortaklarımız (ör. Unity LevelPlay) reklam '
              'kimliği ve cihaz bilgisi gibi verileri işleyebilir. İznini istediğin zaman Ayarlar > Reklam İzni '
              'bölümünden geri alabilirsin. Veri erişim ve silme haklarını Gizlilik Politikası\'ndaki adres '
              'üzerinden kullanabilirsin.',
              style: TextStyle(fontSize: 12, height: 1.3, color: Colors.white70)),
          _check(_gdpr, (v) => setState(() => _gdpr = v),
              const TextSpan(text: 'Kişisel verilerimin yukarıda anlatıldığı şekilde işlenmesine açıkça izin veriyorum.')),
        ]),
      );

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        child: GamePopup(
          title: 'BAŞLAMADAN ÖNCE',
          icon: Icons.verified_user_rounded,
          maxWidth: _showGdpr ? 640 : 440,
          actions: [
            PopupButton(
                label: 'REDDET (ÇIK)',
                kind: CandyKind.gray,
                width: 170,
                height: 46,
                onTap: _decline),
            PopupButton(
                label: 'KABUL ET',
                kind: CandyKind.green,
                width: 170,
                height: 46,
                onTap: _ready && !_busy ? _accept : null),
          ],
          child: _showGdpr
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: _left()),
                  const SizedBox(width: 14),
                  Expanded(child: _gdprBox()),
                ])
              : _left(),
        ),
      );
}
