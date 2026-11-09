import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../diagnostics/app_log.dart';
import '../theme/app_theme.dart';
import 'game_popup.dart';
import 'lobby_widgets.dart' show CandyKind;

/// İnternet var mı? İki farklı adresin DNS çözümlemesine AYNI ANDA bakar; biri çözülürse hemen true döner
/// (en kötü durumda 4 sn). Not: DNS çözülmesi bağlantının çalıştığını %100 garanti etmez; sunucuya gerçek
/// bağlantı zaten oyun açılınca denenir.
/// Web önizlemesinde (dart:io lookup yok) her zaman true döner.
Future<bool> hasInternet() async {
  if (kIsWeb) return true;
  Future<bool> tryHost(String host) async {
    try {
      final r = await InternetAddress.lookup(host).timeout(const Duration(seconds: 4));
      return r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  final result = Completer<bool>();
  var pending = 2;
  void done(bool ok) {
    if (ok && !result.isCompleted) result.complete(true);
    if (--pending == 0 && !result.isCompleted) result.complete(false);
  }

  tryHost('google.com').then(done);
  tryHost('cloudflare.com').then(done);
  return result.future;
}

/// Açılış internet kapısı: internet varsa [child]'ı gösterir; yoksa "İnternet yok" penceresi açar.
/// TEKRAR DENE yeniden bakar (bağlantı gelmişse oyun açılır), ÇIK uygulamayı kapatır.
class InternetGate extends StatefulWidget {
  final Widget child;

  /// Test için değiştirilebilir.
  final Future<bool> Function() check;
  final VoidCallback? onQuit;
  const InternetGate({super.key, required this.child, this.check = hasInternet, this.onQuit});

  @override
  State<InternetGate> createState() => _InternetGateState();
}

enum _Net { checking, ok, offline }

class _InternetGateState extends State<InternetGate> {
  _Net _net = _Net.checking;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final ok = await widget.check();
    if (!mounted) return;
    Log.i('internet', ok ? 'açılışta internet var' : 'açılışta internet YOK: uyarı gösterilecek');
    setState(() => _net = ok ? _Net.ok : _Net.offline);
    if (!ok) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showOffline();
      });
    }
  }

  void _retry(BuildContext popupContext) {
    Navigator.of(popupContext).pop();
    Log.i('internet', 'TEKRAR DENE');
    setState(() => _net = _Net.checking);
    _run();
  }

  void _quit() {
    Log.i('internet', 'ÇIK: uygulama kapatılıyor');
    final q = widget.onQuit;
    if (q != null) {
      q();
    } else {
      SystemNavigator.pop();
    }
  }

  void _showOffline() {
    showGamePopup<void>(
      context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false, // geri tuşu ile kaçılamaz
        child: GamePopup(
          title: 'İNTERNET YOK',
          icon: Icons.wifi_off_rounded,
          maxWidth: 400,
          actions: [
            PopupButton(label: 'ÇIK', kind: CandyKind.red, width: 120, height: 46, onTap: _quit),
            PopupButton(label: 'TEKRAR DENE', kind: CandyKind.green, width: 170, height: 46, onTap: () => _retry(ctx)),
          ],
          child: const Text(
              'İnternet bağlantın görünmüyor. İnternete bağlanıp TEKRAR DENE\'ye bas.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.white70)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (_net) {
      case _Net.ok:
        return widget.child;
      case _Net.checking:
        return const Scaffold(
          backgroundColor: AppColors.bg,
          body: Center(child: CircularProgressIndicator(color: AppColors.gold)),
        );
      case _Net.offline:
        return const Scaffold(backgroundColor: AppColors.bg, body: SizedBox.expand());
    }
  }
}
