import 'package:flutter/material.dart';
import '../models/nick_words.dart';
import '../models/profile.dart';
import '../services/account_service.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar.dart';
import '../widgets/lobby_widgets.dart';

/// Takma ad + avatar seçimi. İlk açılışta ([first] = true) zorunlu, geri butonu yok;
/// sonradan lobiden avatara dokununca düzenleme olarak açılır.
class ProfileScreen extends StatefulWidget {
  final ProfileService service;
  final Profile initial;
  final bool first;

  /// [first] iken kayıttan sonra çağrılır. Değilse ekran kapanır ve kaydedilen [Profile] döner.
  final void Function(Profile)? onDone;

  /// Yalnız ilk kurulumda: "Zaten hesabın var mı? Google ile giriş" bağlantısı. Giriş yapılırsa [onAccountSwitched] çağrılır.
  final AccountService? account;
  final VoidCallback? onAccountSwitched;
  const ProfileScreen(
      {super.key,
      required this.service,
      required this.initial,
      this.first = false,
      this.onDone,
      this.account,
      this.onAccountSwitched});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late int? _word = widget.initial.named ? nickWordIndex(widget.initial.name) : null; // seçili isim kelimesi
  late int _avatar = widget.initial.avatar;
  int _tab = 0; // 0 = isim, 1 = avatar
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _googleSignIn() async {
    final a = widget.account;
    if (a == null) return;
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final ok = await a.signInGoogle();
      if (!mounted) return;
      if (ok) {
        widget.onAccountSwitched?.call();
        return;
      }
      setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _busy = false;
      });
    }
  }

  Future<void> _save() async {
    if (_word == null && !widget.initial.named) {
      setState(() {
        _error = 'Listeden bir isim seç.';
        _tab = 0;
      });
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      // İsim değişmediyse yalnız avatar gönderilir (sunucu numarayı korur).
      final changed = _word != null && _word != nickWordIndex(widget.initial.name);
      final p = await widget.service.save(word: changed ? _word : null, avatar: _avatar);
      if (!mounted) return;
      if (widget.first) {
        widget.onDone?.call(p);
      } else {
        Navigator.of(context).pop(p);
      }
    } on ProfileException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Profil kaydedilemedi, tekrar dene.';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !widget.first, // ilk kurulumda geri ile kaçılamaz
        child: Scaffold(
          body: AppBackground(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                child: Column(children: [
                  SizedBox(
                    height: 44,
                    child: Stack(alignment: Alignment.center, children: [
                      Text(widget.first ? 'HOŞ GELDİN' : 'PROFİL',
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 2)),
                      if (!widget.first)
                        Align(
                            alignment: Alignment.centerLeft,
                            child: RoundBtn(
                                icon: Icons.arrow_back,
                                kind: CandyKind.red,
                                size: 38,
                                onTap: () => Navigator.of(context).pop())),
                    ]),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(flex: 5, child: SingleChildScrollView(child: _left())),
                      const SizedBox(width: 14),
                      Expanded(flex: 6, child: _right()),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );

  Widget _left() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: AvatarWidget(index: _avatar, size: 76, selected: true)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white24)),
          child: Column(children: [
            const Text('İSMİN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: Colors.white54)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                  _word == null
                      ? 'İsim seç  →'
                      : (_word == nickWordIndex(widget.initial.name) && widget.initial.named
                          ? widget.initial.name
                          : '${kNickWords[_word!]}_????'),
                  style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      color: _word == null ? Colors.white38 : Colors.white)),
            ),
            const SizedBox(height: 2),
            const Text('Sayıyı sistem verir', style: TextStyle(fontSize: 10.5, color: Colors.white54)),
          ]),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_error!, style: const TextStyle(color: AppColors.bad, fontSize: 12)),
          ),
        const SizedBox(height: 10),
        CandyButton(
          onTap: _busy ? null : _save,
          kind: CandyKind.green,
          height: 46,
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
              : Text(widget.first ? 'BAŞLA' : 'KAYDET', style: const TextStyle(fontSize: 16)),
        ),
        if (widget.first && widget.account != null)
          TextButton(
              onPressed: _busy ? null : _googleSignIn,
              child: const Text('Zaten hesabın var mı? Google ile giriş yap',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12))),
      ]);

  Widget _tabBtn(String label, int i) => Expanded(
        child: GestureDetector(
          onTap: _busy ? null : () => setState(() => _tab = i),
          child: Container(
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _tab == i ? AppColors.goldLight : Colors.black26,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: _tab == i ? AppColors.navy : Colors.white70)),
          ),
        ),
      );

  Widget _right() => Column(children: [
        Row(children: [
          _tabBtn('İSİM SEÇ', 0),
          const SizedBox(width: 8),
          _tabBtn('AVATAR', 1),
        ]),
        const SizedBox(height: 8),
        Expanded(child: _tab == 0 ? _nameGrid() : _grid()),
      ]);

  Widget _nameGrid() => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
        child: SingleChildScrollView(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < kNickWords.length; i++)
                GestureDetector(
                  onTap: _busy
                      ? null
                      : () => setState(() {
                            _word = i;
                            _error = null;
                          }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: i == _word ? AppColors.goldLight : Colors.white10,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: i == _word ? AppColors.gold : Colors.white24),
                    ),
                    child: Text(kNickWords[i],
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: i == _word ? AppColors.navy : Colors.white)),
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _grid() => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
        child: LayoutBuilder(builder: (context, box) {
          const cols = 5;
          const gap = 8.0;
          final cell = ((box.maxWidth - gap * (cols - 1)) / cols).clamp(30.0, 64.0);
          return SingleChildScrollView(
            child: Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (var i = 0; i < kAvatarCount; i++)
                  GestureDetector(
                    onTap: _busy ? null : () => setState(() => _avatar = i),
                    child: AvatarWidget(index: i, size: cell, selected: i == _avatar),
                  ),
              ],
            ),
          );
        }),
      );
}
