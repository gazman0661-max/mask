import 'package:flutter/material.dart';
import '../diagnostics/app_log.dart';
import '../services/account_service.dart';
import '../theme/app_theme.dart';
import 'game_popup.dart';
import 'lobby_widgets.dart';

/// "Hesabım" penceresi: Misafir ve Google AYRI hesaplardır (çip/ilerleme paylaşılmaz).
/// İstenen hesaba geçilirse [onSwitched] çağrılır ve pencere `true` ile kapanır.
class AccountDialog extends StatefulWidget {
  final AccountService account;
  final VoidCallback onSwitched;
  const AccountDialog({super.key, required this.account, required this.onSwitched});

  @override
  State<AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<AccountDialog> {
  bool _busy = false;
  bool _loading = true;
  String? _error;

  AccountService get _a => widget.account;

  @override
  void initState() {
    super.initState();
    _a.refresh().catchError((Object e, StackTrace s) {
      Log.w('hesap', 'hesap durumu okunamadı: $e');
    }).whenComplete(() {
      if (mounted) setState(() => _loading = false);
    });
  }

  Future<void> _switch(Future<bool> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await action();
      if (!mounted) return;
      if (ok) {
        widget.onSwitched();
        Navigator.of(context).pop(true);
        return;
      }
    } catch (e, s) {
      Log.e('hesap', 'hesap değiştirme hatası', e, s);
      if (mounted) _error = e.toString();
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<bool> _toGuest() async {
    await _a.useGuest();
    return true;
  }

  Widget _card({
    required IconData icon,
    required String title,
    required String sub,
    required bool active,
    required String actionLabel,
    required CandyKind kind,
    required VoidCallback onAction,
  }) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? AppColors.goldLight : Colors.white12, width: active ? 2 : 1),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 32, color: active ? AppColors.goldLight : Colors.white70),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1)),
            const SizedBox(height: 2),
            Text(sub,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.white70)),
            const SizedBox(height: 8),
            if (active)
              Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
                Icon(Icons.check_circle, color: AppColors.good, size: 18),
                SizedBox(width: 4),
                Text('Şu an bu hesaptasın', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
              ])
            else
              CandyButton(
                  onTap: _busy ? null : onAction,
                  kind: kind,
                  radius: 10,
                  height: 36,
                  child: Text(actionLabel, style: const TextStyle(fontSize: 12))),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final guestActive = _a.mode == AccountMode.guest;
    return GamePopup(
      title: 'HESABIM',
      icon: Icons.account_circle,
      maxWidth: 520,
      onClose: _busy ? null : () => Navigator.of(context).pop(false),
      actions: [
        PopupButton(
            label: 'KAPAT',
            kind: CandyKind.gray,
            width: 150,
            height: 44,
            onTap: _busy ? null : () => Navigator.of(context).pop(false)),
      ],
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_loading)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.gold)))
        else
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _card(
                icon: Icons.person_outline,
                title: 'MİSAFİR',
                sub: 'Bu telefona özel hesap',
                active: guestActive,
                actionLabel: 'MİSAFİR OLARAK OYNA',
                kind: CandyKind.blue,
                onAction: () => _switch(_toGuest),
              ),
              const SizedBox(width: 10),
              _card(
                icon: Icons.account_circle,
                title: 'GOOGLE',
                sub: _a.googleEmail ?? 'Telefon değişse de kaybolmaz',
                active: !guestActive,
                actionLabel: _a.hasGoogle ? 'GOOGLE HESABINA GEÇ' : 'GOOGLE İLE GİRİŞ',
                kind: CandyKind.green,
                onAction: () => _switch(() => _a.signInGoogle()),
              ),
            ]),
          ),
        const SizedBox(height: 8),
        const Text(
            'İki hesabın çipleri ve ilerlemesi ayrı tutulur, birbirine taşınmaz. İstediğin zaman aralarında geçiş yapabilirsin.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.white70)),
        if (_busy)
          const Padding(
              padding: EdgeInsets.only(top: 8),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.gold))),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.bad)),
          ),
        if (!_loading && _a.hasGoogle)
          TextButton(
              onPressed: _busy ? null : () => _switch(() => _a.signInGoogle(fresh: true)),
              child: const Text('Başka bir Google hesabıyla gir', style: TextStyle(fontSize: 12))),
      ]),
    );
  }
}
