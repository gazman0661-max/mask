import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../diagnostics/app_log.dart';
import '../widgets/game_popup.dart' show showConfirmPopup;
import '../widgets/lobby_widgets.dart' show showToast;

enum _Tab { session, errors, previous }

class _Line {
  final String text;
  final Color color;
  const _Line(this.text, this.color);
}

/// Gizli tanı günlüğü ekranı (Ayarlar > Hakkında'ya 7 kez dokununca açılır).
/// Sekmeler: Bu oturum / Hatalar / Önceki. Kopyala, Paylaş, Temizle.
class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  static const _orange = Color(0xFFF47B20);
  static const _brown = Color(0xFF8E4B3B);
  static const _cream = Color(0xFFFBF1E6);
  static const _channel = MethodChannel('okey101/share');
  static const _maxRows = 2000;

  _Tab _tab = _Tab.session;

  String get _exportText => switch (_tab) {
        _Tab.session => Log.sessionText(),
        _Tab.errors => Log.errorsText(),
        _Tab.previous => Log.previousText(),
      };

  Color _levelColor(LogLevel l) => switch (l) {
        LogLevel.debug => const Color(0xFF8F8F8F),
        LogLevel.info => const Color(0xFFE8E8E8),
        LogLevel.warn => const Color(0xFFFFC857),
        LogLevel.error => const Color(0xFFFF6B6B),
      };

  Color _textColor(String line) {
    if (line.startsWith(' ')) return const Color(0xFF8F8F8F);
    if (line.contains(' ERROR [')) return _levelColor(LogLevel.error);
    if (line.contains(' WARN [')) return _levelColor(LogLevel.warn);
    if (line.contains(' DEBUG [')) return _levelColor(LogLevel.debug);
    return _levelColor(LogLevel.info);
  }

  /// En yeni satır altta görünsün diye liste ters çevrilir (reverse: true).
  List<_Line> _lines() {
    List<_Line> out;
    switch (_tab) {
      case _Tab.session:
        out = Log.entries.reversed
            .take(_maxRows)
            .map((e) => _Line(e.format(), _levelColor(e.level)))
            .toList();
      case _Tab.errors:
        out = Log.errors.reversed
            .take(_maxRows)
            .map((e) => _Line(e.format(), _levelColor(e.level)))
            .toList();
      case _Tab.previous:
        out = Log.previous.isEmpty
            ? [const _Line('Önceki oturum kaydı yok.', Color(0xFF8F8F8F))]
            : Log.previous
                .split('\n')
                .reversed
                .take(_maxRows)
                .map((l) => _Line(l, _textColor(l)))
                .toList();
    }
    return out;
  }

  Future<void> _copy() async {
    final text = _exportText;
    await Clipboard.setData(ClipboardData(text: text));
    Log.i('günlük', 'kopyalandı: sekme=${_tab.name} ${text.length} karakter');
    if (mounted) showToast(context, 'Kopyalandı (${text.length} karakter)');
  }

  Future<void> _share() async {
    var text = _exportText;
    if (text.length > 150000) {
      text = '... (başı kısaltıldı) ...\n${text.substring(text.length - 150000)}';
    }
    try {
      await _channel.invokeMethod<bool>(
          'shareText', {'text': text, 'subject': '101 Okey tanı kaydı'});
      Log.i('günlük', 'paylaşıldı: sekme=${_tab.name} ${text.length} karakter');
    } on MissingPluginException {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) showToast(context, 'Paylaşım bu cihazda yok, panoya kopyalandı.');
    } on PlatformException catch (e, s) {
      Log.e('günlük', 'paylaşım hatası', e, s);
      if (mounted) showToast(context, 'Paylaşılamadı.');
    }
  }

  Future<void> _clear() async {
    final ok = await showConfirmPopup(
      context,
      title: 'KAYITLAR SİLİNSİN Mİ?',
      message: _tab == _Tab.previous
          ? 'Önceki oturumun kaydı silinecek.'
          : 'Bu oturumun kayıtları ve hata listesi silinecek.',
      confirmLabel: 'TEMİZLE',
      icon: Icons.delete_sweep_rounded,
      danger: true,
    );
    if (!ok) return;
    if (_tab == _Tab.previous) {
      Log.clearPrevious();
    } else {
      Log.clearSession();
    }
    Log.i('günlük', 'temizlendi (sekme=${_tab.name})');
  }

  Widget _tabBtn(String label, _Tab t) {
    final on = _tab == t;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = t),
        child: Container(
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? _orange : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? _orange : _brown, width: 2),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: on ? Colors.white : const Color(0xFF3B2A20))),
          ),
        ),
      ),
    );
  }

  Widget _actionBtn(String label, IconData icon, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 38,
            decoration: BoxDecoration(color: _brown, borderRadius: BorderRadius.circular(19)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cream,
      body: ValueListenableBuilder<int>(
        valueListenable: Log.revision,
        builder: (_, __, ___) {
          final lines = _lines();
          return Column(children: [
            Container(
              height: 46,
              color: _orange,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                ),
                const SizedBox(width: 6),
                const Text('Hata Kayıtları',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                const Spacer(),
                Text('${Log.entries.length} satır',
                    style: const TextStyle(fontSize: 12, color: Colors.white)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
              child: Row(children: [
                _tabBtn('Bu oturum', _Tab.session),
                const SizedBox(width: 6),
                _tabBtn('Hatalar (${Log.errors.length})', _Tab.errors),
                const SizedBox(width: 6),
                _tabBtn('Önceki', _Tab.previous),
                const SizedBox(width: 14),
                _actionBtn('Kopyala', Icons.copy, _copy),
                const SizedBox(width: 6),
                _actionBtn('Paylaş', Icons.share, _share),
                const SizedBox(width: 6),
                _actionBtn('Temizle', Icons.delete_outline, _clear),
              ]),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(10),
                    itemCount: lines.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(lines[i].text,
                          style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              height: 1.25,
                              color: lines[i].color)),
                    ),
                  ),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}
