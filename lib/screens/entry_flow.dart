import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../diagnostics/app_log.dart';
import '../services/account_service.dart';
import '../services/auth_service.dart' show AuthException;
import '../services/legal_consent_service.dart';
import '../widgets/legal_gate_dialog.dart';
import '../widgets/responsive_shell.dart';

/// İkonla aynı palet: bordo zemin, altın çerçeve/yazı, fildişi taş.
class Brand {
  static const wine = Color(0xFF5B1528);
  static const wineDark = Color(0xFF3A0B19);
  static const wineLight = Color(0xFF7A1E38);
  static const ribbon = Color(0xFF4A0F21);
  static const gold = Color(0xFFE3B24E);
  static const goldLight = Color(0xFFF0C25A);
  static const ivory = Color(0xFFF7EFDD);
  static const ink = Color(0xFF2E0914);
}

/// Açılış akışı: 2-3 sn'lik açılış ekranı (splash) -> (ilk açılışta) giriş ekranı -> [builder] (oyun).
/// Giriş ekranı yalnız ilk açılışta çıkar: seçilen hesap (Misafir/Google) cihazda hatırlanır, sonraki açılışlarda
/// açılış ekranından doğrudan oyuna geçilir. Hesap değiştirmek için Ayarlar > HESABIM kullanılır.
/// [builder] ancak giriş seçildikten sonra kurulur (profil yükleme/misafir girişi o zaman başlar).
class EntryFlow extends StatefulWidget {
  final AccountService? account;
  final WidgetBuilder builder;
  final Duration splash;
  const EntryFlow(
      {super.key,
      this.account,
      required this.builder,
      this.splash = const Duration(milliseconds: 2600)});

  @override
  State<EntryFlow> createState() => _EntryFlowState();
}

enum _Step { splash, login, done }

class _EntryFlowState extends State<EntryFlow> {
  static const _kDone = 'entry_done';
  _Step _step = _Step.splash;
  bool? _chosen; // daha önce hesap seçildi mi (null: henüz okunmadı)
  bool _timerDone = false;
  bool _legalBusy = false; // onay penceresi açıkken ikinci kez açılmasın
  bool _busy = false;
  bool _googleBusy = false;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.splash, () {
      _timerDone = true;
      _advance();
    });
    _readPrefs();
    // Açılış ve giriş ekranlarında banner yok (uygulama başında zaten gizli başlar; burada sahipliği alırız).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _step != _Step.done) ResponsiveShell.hideBanner(this);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) => ResponsiveShell.showBanner(this));
    super.dispose();
  }

  Future<void> _readPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      _chosen = p.getBool(_kDone) ?? false;
    } catch (e, s) {
      Log.e('giris', 'giriş tercihi okunamadı', e, s);
      _chosen = false;
    }
    _advance();
  }

  Future<void> _advance() async {
    if (!mounted || !_timerDone || _chosen == null || _step != _Step.splash || _legalBusy) return;
    // İlk açılış: Hizmet Şartları + Gizlilik (+ AB için GDPR) onayı. Onay yoksa devam yok.
    if (!LegalConsentService.I.accepted) {
      _legalBusy = true;
      await LegalGateDialog.show(context);
      _legalBusy = false;
      if (!mounted || _step != _Step.splash) return;
    }
    setState(() => _step = _chosen! ? _Step.done : _Step.login);
    if (_step == _Step.done) ResponsiveShell.showBanner(this);
  }

  Future<void> _finish() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kDone, true);
    } catch (e, s) {
      Log.e('giris', 'giriş tercihi kaydedilemedi', e, s);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _googleBusy = false;
      _step = _Step.done;
    });
    ResponsiveShell.showBanner(this);
  }

  Future<void> _google() async {
    final a = widget.account;
    if (a == null || _busy) return;
    setState(() {
      _busy = true;
      _googleBusy = true;
      _error = null;
    });
    try {
      final ok = await a.signInGoogle();
      if (!mounted) return;
      if (ok) {
        await _finish();
      } else {
        setState(() {
          _busy = false;
          _googleBusy = false;
        });
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _googleBusy = false;
        _error = e.message;
      });
    } catch (e, s) {
      Log.e('giris', 'Google girişi başarısız', e, s);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _googleBusy = false;
        _error = 'Google ile girilemedi. Tekrar dene ya da misafir olarak gir.';
      });
    }
  }

  Future<void> _guest() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.account?.useGuest();
      await _finish();
    } catch (e, s) {
      Log.e('giris', 'misafir girişi başarısız', e, s);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Giriş yapılamadı. Tekrar dene.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget page = switch (_step) {
      _Step.splash => _Splash(key: const ValueKey('splash'), duration: widget.splash),
      _Step.login => _Login(
          key: const ValueKey('login'),
          busy: _busy,
          googleBusy: _googleBusy,
          error: _error,
          showGoogle: widget.account != null,
          onGoogle: _google,
          onGuest: _guest),
      _Step.done => KeyedSubtree(key: const ValueKey('app'), child: widget.builder(context)),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      child: page,
    );
  }
}

/// Bordo zemin + altın çerçeve (ikondaki halka).
class _Backdrop extends StatelessWidget {
  final Widget child;
  const _Backdrop({required this.child});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Brand.wine,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
                center: Alignment(0, -.2),
                radius: 1.1,
                colors: [Brand.wineLight, Brand.wine, Brand.wineDark]),
          ),
          child: SafeArea(
            minimum: const EdgeInsets.all(8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Brand.gold, width: 2.5),
                borderRadius: BorderRadius.circular(28),
              ),
              child: child,
            ),
          ),
        ),
      );
}

class _Logo extends StatelessWidget {
  final double height;
  const _Logo({required this.height});

  @override
  Widget build(BuildContext context) => Image.asset('assets/brand/logo.png',
      height: height, fit: BoxFit.contain, filterQuality: FilterQuality.high);
}

class _Title extends StatelessWidget {
  final double size;
  const _Title({this.size = 30});

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text('YÜZBİR ARENA',
            style: TextStyle(
                fontSize: size,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                color: Brand.goldLight,
                shadows: const [Shadow(color: Brand.ink, offset: Offset(0, 2), blurRadius: 3)])),
        const SizedBox(height: 2),
        Text('101 OKEY',
            style: TextStyle(
                fontSize: size * .45,
                fontWeight: FontWeight.w800,
                letterSpacing: 4,
                color: Brand.gold.withOpacity(.9))),
      ]);
}

class _Splash extends StatefulWidget {
  final Duration duration;
  const _Splash({super.key, required this.duration});

  @override
  State<_Splash> createState() => _SplashState();
}

class _SplashState extends State<_Splash> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration)..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logo = CurvedAnimation(parent: _c, curve: const Interval(0, .3, curve: Curves.easeOutBack));
    final title = CurvedAnimation(parent: _c, curve: const Interval(.2, .5, curve: Curves.easeOut));
    return _Backdrop(
      child: LayoutBuilder(builder: (context, box) {
        final h = box.maxHeight;
        return Center(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) => Column(mainAxisSize: MainAxisSize.min, children: [
                Opacity(
                  opacity: logo.value.clamp(0.0, 1.0),
                  child: Transform.scale(
                      scale: .8 + .2 * logo.value, child: _Logo(height: h * .52)),
                ),
                SizedBox(height: h * .04),
                Opacity(opacity: title.value.clamp(0.0, 1.0), child: _Title(size: h * .09)),
                SizedBox(height: h * .06),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: 170,
                    height: 6,
                    child: LinearProgressIndicator(
                        value: _c.value,
                        backgroundColor: Brand.wineDark,
                        valueColor: const AlwaysStoppedAnimation(Brand.gold)),
                  ),
                ),
              ]),
            ),
          ),
        );
      }),
    );
  }
}

class _Login extends StatelessWidget {
  final bool busy, googleBusy, showGoogle;
  final String? error;
  final VoidCallback onGoogle, onGuest;
  const _Login(
      {super.key,
      required this.busy,
      required this.googleBusy,
      required this.showGoogle,
      required this.error,
      required this.onGoogle,
      required this.onGuest});

  @override
  Widget build(BuildContext context) {
    return _Backdrop(
      child: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth > box.maxHeight;
        final logoH = wide ? box.maxHeight * .6 : box.maxWidth * .5;
        final panel = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _Title(size: wide ? 26 : 30),
            const SizedBox(height: 18),
            if (showGoogle) ...[
              _BrandButton(
                label: 'GOOGLE İLE GİRİŞ',
                filled: true,
                loading: googleBusy,
                onTap: busy ? null : onGoogle,
                leading: Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: const Text('G',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF4285F4))),
                ),
              ),
              const SizedBox(height: 12),
            ],
            _BrandButton(
              label: 'MİSAFİR GİRİŞİ',
              filled: false,
              onTap: busy ? null : onGuest,
              leading: const Icon(Icons.person_outline, size: 24, color: Brand.goldLight),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFFFFA897))),
            ],
            const SizedBox(height: 12),
            Text(
                showGoogle
                    ? 'Google ile girersen hesabın yeni telefonda da seni bekler.'
                    : 'Misafir hesabı bu telefona bağlıdır.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: Brand.ivory.withOpacity(.7))),
          ]),
        );
        final logo = _Logo(height: logoH);
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: wide
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    logo,
                    const SizedBox(width: 40),
                    panel,
                  ])
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    logo,
                    const SizedBox(height: 16),
                    panel,
                  ]),
          ),
        );
      }),
    );
  }
}

/// İkondaki taş (fildişi) ve kurdele (koyu bordo) tarzında, altın çerçeveli buton.
class _BrandButton extends StatelessWidget {
  final String label;
  final Widget leading;
  final bool filled; // true: fildişi zemin, false: koyu bordo zemin
  final bool loading;
  final VoidCallback? onTap;
  const _BrandButton(
      {required this.label,
      required this.leading,
      required this.filled,
      required this.onTap,
      this.loading = false});

  @override
  Widget build(BuildContext context) {
    final bg = filled ? Brand.ivory : Brand.ribbon;
    final fg = filled ? Brand.wine : Brand.goldLight;
    return Opacity(
      opacity: onTap == null && !loading ? .6 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Brand.gold, width: 2.5),
            ),
            child: Row(children: [
              SizedBox(width: 28, child: Center(child: leading)),
              Expanded(
                child: Center(
                  child: loading
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: fg))
                      : Text(label,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                              color: fg)),
                ),
              ),
              const SizedBox(width: 28),
            ]),
          ),
        ),
      ),
    );
  }
}
