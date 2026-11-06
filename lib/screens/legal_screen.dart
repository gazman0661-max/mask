import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../theme/app_theme.dart';
import '../widgets/lobby_widgets.dart';

enum LegalKind { terms, privacy }

/// Yayınlanan hukuki sayfaların adresleri. BOŞKEN ekran "yakında yayınlanacak" der.
/// Sayfaları yükleyince SADECE burayı doldur (örn. GitHub Pages / Cloudflare Pages adresi).
/// Play Console'daki gizlilik politikası alanı da aynı adresi kullanmalı.
class LegalLinks {
  LegalLinks._();
  static const String privacy = ''; // örn. https://alanadin.com/gizlilik-politikasi.html
  static const String terms = ''; // örn. https://alanadin.com/hizmet-sartlari.html

  static String of(LegalKind k) => k == LegalKind.terms ? terms : privacy;
}

/// Hizmet Şartları / Gizlilik Politikası: yayındaki web sayfasını uygulamanın İÇİNDE (WebView) açar.
class LegalScreen extends StatefulWidget {
  final LegalKind kind;
  const LegalScreen({super.key, required this.kind});

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  WebViewController? _c;
  bool _loading = true;
  bool _failed = false;

  String get _url => LegalLinks.of(widget.kind);
  String get _title => widget.kind == LegalKind.terms ? 'HİZMET ŞARTLARI' : 'GİZLİLİK POLİTİKASI';

  @override
  void initState() {
    super.initState();
    _open();
  }

  void _open() {
    if (_url.isEmpty) {
      _loading = false;
      return;
    }
    _loading = true;
    _failed = false;
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled) // sayfalar statik HTML
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        onWebResourceError: (e) {
          if (mounted && (e.isForMainFrame ?? true)) {
            setState(() {
              _loading = false;
              _failed = true;
            });
          }
        },
      ))
      ..loadRequest(Uri.parse(_url));
  }

  Widget _message(String text, {bool retry = false}) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: Colors.white70)),
          if (retry) ...[
            const SizedBox(height: 12),
            CandyButton(
                onTap: () => setState(_open),
                kind: CandyKind.orange,
                width: 150,
                height: 42,
                child: const Text('TEKRAR DENE')),
          ],
        ]),
      );

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_url.isEmpty) {
      body = _message('Bu sayfa yakında yayınlanacak.');
    } else if (_failed) {
      body = _message('Sayfa açılamadı. İnternet bağlantını kontrol et.', retry: true);
    } else {
      body = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(children: [
          WebViewWidget(controller: _c!),
          if (_loading) const Center(child: CircularProgressIndicator(color: AppColors.gold)),
        ]),
      );
    }
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
            child: Column(children: [
              SizedBox(
                height: 48,
                child: Stack(alignment: Alignment.center, children: [
                  Text(_title,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 2)),
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
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.gold, width: 2),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: body,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
