import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../diagnostics/app_log.dart';
import '../screens/log_screen.dart';
import 'lobby_widgets.dart' show showToast;

/// Ayarlar'daki "HAKKINDA" kutusu. 7 kez art arda dokununca gizli
/// tanı günlüğü (LogScreen) açılır. 2 sn dokunmazsan sayaç sıfırlanır.
class AboutTapBox extends StatefulWidget {
  final String? playerId;
  const AboutTapBox({super.key, this.playerId});

  @override
  State<AboutTapBox> createState() => _AboutTapBoxState();
}

class _AboutTapBoxState extends State<AboutTapBox> {
  static const _need = 7;
  int _taps = 0;
  Timer? _reset;

  void _tap() {
    _reset?.cancel();
    _taps++;
    if (_taps >= _need) {
      _taps = 0;
      HapticFeedback.mediumImpact();
      Log.i('ayar', 'gizli tanı günlüğü açıldı (Hakkında x7)');
      Navigator.of(context).push(MaterialPageRoute(
          settings: const RouteSettings(name: 'LogScreen'),
          builder: (_) => const LogScreen()));
      return;
    }
    if (_taps >= 4) {
      showToast(context, 'Tanı günlüğü için ${_need - _taps} dokunuş daha');
    }
    _reset = Timer(const Duration(seconds: 2), () => _taps = 0);
  }

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _tap,
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
              color: const Color(0xFF3A0B19),
              borderRadius: BorderRadius.circular(8)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('HAKKINDA',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            Text('v0.1.0 · ${widget.playerId ?? '-'}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Colors.white54)),
          ]),
        ),
      );
}
