import 'package:flutter/material.dart';
import '../diagnostics/app_log.dart';
import '../models/profile.dart';
import '../services/account_service.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';
import '../widgets/lobby_widgets.dart';
import 'profile_screen.dart';

/// Açılış kapısı: profili yükler (misafir girişi bu sırada sessizce yapılır).
/// Takma ad seçilmemişse [ProfileScreen] (ilk kurulum), seçilmişse [builder] (lobi).
class StartupGate extends StatefulWidget {
  final ProfileService profiles;

  /// Profil hazır olunca (yüklenince ve değişince) çağrılır: servisler adı/avatarı buradan öğrenir.
  final void Function(Profile) onProfile;
  final WidgetBuilder builder;

  /// Verilirse ilk kurulum ekranında "Google ile giriş" bağlantısı çıkar (yeni telefonda Google hesabına girmek için).
  final AccountService? account;

  /// Google'a geçilince çağrılır. Verilmezse bu ekran profili kendisi yeniden yükler;
  /// verilirse (ör. [OkeyApp]) ekranı yeniden kurmak çağıranın işidir.
  final VoidCallback? onAccountSwitched;
  const StartupGate(
      {super.key,
      required this.profiles,
      required this.onProfile,
      required this.builder,
      this.account,
      this.onAccountSwitched});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

enum _Stage { loading, error, setup, ready }

class _StartupGateState extends State<StartupGate> {
  _Stage _stage = _Stage.loading;
  Profile _profile = Profile.empty;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _stage = _Stage.loading);
    try {
      final p = await widget.profiles.load();
      if (!mounted) return;
      _profile = p;
      if (p.named) {
        widget.onProfile(p);
        setState(() => _stage = _Stage.ready);
      } else {
        setState(() => _stage = _Stage.setup);
      }
    } catch (e, s) {
      Log.e('giris', 'profil yüklenemedi', e, s);
      if (!mounted) return;
      setState(() {
        _error = e is Exception ? e.toString() : 'Bağlanılamadı.';
        _stage = _Stage.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_stage) {
      case _Stage.ready:
        return widget.builder(context);
      case _Stage.setup:
        return ProfileScreen(
          service: widget.profiles,
          initial: _profile,
          first: true,
          account: widget.account,
          onAccountSwitched: () {
            final cb = widget.onAccountSwitched;
            if (cb != null) {
              cb();
            } else {
              _load();
            }
          },
          onDone: (p) {
            widget.onProfile(p);
            setState(() {
              _profile = p;
              _stage = _Stage.ready;
            });
          },
        );
      case _Stage.error:
        return Scaffold(
          body: AppBackground(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off, size: 44, color: Colors.white70),
                const SizedBox(height: 8),
                Text(_error, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 12),
                CandyButton(
                    onTap: _load,
                    kind: CandyKind.green,
                    width: 160,
                    height: 44,
                    child: const Text('TEKRAR DENE')),
              ]),
            ),
          ),
        );
      case _Stage.loading:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: AppColors.gold)),
        );
    }
  }
}
