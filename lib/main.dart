import 'dart:async';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'diagnostics/app_log.dart';
import 'diagnostics/diagnostics.dart';
import 'diagnostics/logging_game_service.dart';
import 'config.dart';
import 'models/profile.dart';
import 'screens/entry_flow.dart';
import 'screens/lobby_screen.dart';
import 'widgets/ad_banner.dart';
import 'screens/startup_gate.dart';
import 'services/account_service.dart';
import 'services/ad_service.dart';
import 'services/auth_service.dart';
import 'services/device_id.dart';
import 'services/sfx.dart';
import 'services/telemetry.dart';
import 'services/cloudflare_game_service.dart';
import 'services/game_socket.dart';
import 'services/profile_service.dart';
import 'services/game_service.dart';
import 'services/inbox_service.dart';
import 'services/push_service.dart';
import 'services/levelplay_service.dart';
import 'services/mock_game_service.dart';
import 'theme/app_theme.dart';
import 'widgets/ban_gate.dart';
import 'widgets/responsive_shell.dart';

Future<void> main() => bootstrapDiagnostics(() async {
      await SystemChrome.setPreferredOrientations(
          [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      // Analytics + Crashlytics: şimdilik KAPALI (NoopTelemetry, google-services.json gerekmez, çökmez).
      // Yayında docs/FIREBASE_KURULUM.md'ye göre buraya `Telemetry.use(FirebaseTelemetry());` eklenir.
      unawaited(Telemetry.init());
      // Reklam (LevelPlay): kimlikler (--dart-define) doluysa SDK'yı başlat; boşsa hiçbir şey yapmaz, reklam sahte kalır.
      unawaited(LevelPlayHub.I.init());
      Sfx.I.startMusic(); // arka plan müziği (Ayarlar > Müzik)
      unawaited(Sfx.I.preload()); // ses dosyasını önceden yükle (ilk taş sesi gecikmesin)

      // İki mod (bkz. config.dart): --dart-define ile SUPABASE_URL / SUPABASE_ANON_KEY / WS_URL verilirse
      // GERÇEK sunucu (misafir girişi + Supabase profili + Cloudflare soketi), verilmezse SAHTE servisler (önizleme).
      // NOT: gerçek modda lobi/masa kurma/oturma sunucuyla çalışır; oyun ekranı hâlâ yerel GameController ile
      // oynar. GameScreen'i sunucunun 'state' mesajlarına bağlamadan canlıya alma (YAPILACAKLAR.md #1).
      final GameService service;
      final InboxService inbox;
      final ProfileService profiles;
      final void Function(Profile) onProfile;
      final void Function(Profile) onProfileChanged;
      final AccountService account;
      final VoidCallback onAccountSwitched;
      ValueListenable<Map<String, dynamic>?>? banNotice;
      VoidCallback? onBanRetry;

      if (AppConfig.backendReady) {
        final auth = GuestAuthService(
            supabaseUrl: AppConfig.supabaseUrl,
            anonKey: AppConfig.supabaseAnonKey,
            guestDomain: AppConfig.guestDomain);
        final socket = GameSocket(url: AppConfig.wsUrl, token: auth.accessToken, device: DeviceId.get);
        final cf = CloudflareGameService(
            socket: socket,
            supabaseUrl: AppConfig.supabaseUrl,
            anonKey: AppConfig.supabaseAnonKey,
            accessToken: auth.accessToken)
          ..attachLifecycle();
        service = LoggingGameService(cf);
        inbox = SupabaseInboxService(
            url: AppConfig.supabaseUrl,
            anonKey: AppConfig.supabaseAnonKey,
            accessToken: auth.accessToken);
        profiles = SupabaseProfileService(
            auth: auth,
            supabaseUrl: AppConfig.supabaseUrl,
            anonKey: AppConfig.supabaseAnonKey);
        account = auth;
        // Hesap değişti: eski kullanıcının soketini kapat; bir sonraki istek yeni token'la yeniden bağlanır.
        onAccountSwitched = socket.disconnect;
        banNotice = socket.ban;
        onBanRetry = () {
          socket.ban.value = null;
          unawaited(socket.connect());
        };
        onProfile = (_) {}; // sunucu adı/avatarı bağlanırken Supabase'ten kendisi okur
        onProfileChanged = (_) => socket.send({'t': 'profile'}); // açık bağlantıya "yeniden oku" de
        Log.i('app', 'servis hazır: GERÇEK sunucu (misafir girişi)');
      } else {
        final mock = MockGameService();
        service = LoggingGameService(mock);
        inbox = MockInboxService(onCredit: (n) => mock.tickets += n);
        profiles = LocalProfileService();
        account = MockAccountService();
        onAccountSwitched = () {};
        onProfile = (p) {
          mock.myName = p.name;
          mock.myAvatar = p.avatar;
        };
        onProfileChanged = onProfile;
        Log.i('app', 'servis hazır: MockGameService (günlük sarmalayıcılı)');
      }

      // Push: Firebase kurulunca docs/PUSH_KURULUM.md'deki FcmPushService buraya gelir.
      const PushService push = NoopPushService();

      runApp(OkeyApp(
          ads: createAdService(),
          banNotice: banNotice,
          onBanRetry: onBanRetry,
          service: service,
          inbox: inbox,
          push: push,
          profiles: profiles,
          onProfile: onProfile,
          onProfileChanged: onProfileChanged,
          account: account,
          onAccountSwitched: onAccountSwitched));
    });

class OkeyApp extends StatefulWidget {
  final GameService service;
  final InboxService inbox;
  final PushService push;
  final ProfileService profiles;
  final void Function(Profile) onProfile;
  final void Function(Profile) onProfileChanged;
  final AccountService? account;

  /// Ödüllü reklam servisi: LevelPlay kimlikleri doluysa gerçek, değilse sahte ([createAdService]).
  final AdService ads;

  /// Hesap (Misafir/Google) değişince çağrılır: eski hesabın soketini kapatmak gibi. Ardından uygulama
  /// yeni hesapla yeniden kurulur (profil yüklenir, takma adı yoksa ilk kurulum ekranı gelir).
  final VoidCallback? onAccountSwitched;

  /// Hesap/cihaz kapatılınca dolan bilgi (sunucu 'banned' mesajı); null değilse tam ekran uyarı çıkar.
  final ValueListenable<Map<String, dynamic>?>? banNotice;

  /// Geçici kapatma bitince oyuncunun "Tekrar dene" dokunuşu.
  final VoidCallback? onBanRetry;
  const OkeyApp(
      {super.key,
      this.banNotice,
      this.onBanRetry,
      required this.service,
      required this.inbox,
      required this.profiles,
      required this.onProfile,
      required this.onProfileChanged,
      this.account,
      this.onAccountSwitched,
      this.ads = const MockAdService(),
      this.push = const NoopPushService()});

  @override
  State<OkeyApp> createState() => _OkeyAppState();
}

class _OkeyAppState extends State<OkeyApp> with WidgetsBindingObserver {
  int _epoch = 0;

  static void _immersive() =>
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Durum/gezinme çubuğu bir şekilde çıkarsa (kenardan çekme, bildirim perdesi) kısa süre sonra tekrar gizle.
    SystemChrome.setSystemUIChangeCallback((visible) async {
      if (!visible) return;
      await Future<void>.delayed(const Duration(seconds: 2));
      if (mounted) _immersive();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setSystemUIChangeCallback(null);
    super.dispose();
  }

  // Arka plandan dönünce (arama, bildirim, uygulama değiştirme) tam ekranı geri getir.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _immersive();
  }

  void _switched() {
    widget.onAccountSwitched?.call();
    setState(() => _epoch++); // StartupGate yeni anahtarla yeniden kurulur: yeni hesabın profili yüklenir
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Yüzbir Arena',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        navigatorObservers: [LogNavigatorObserver()],
        // Yazı boyutu / kalın yazı sistem ayarı en dışta da sabitlenir (BanGate dahil her şey).
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.noScaling, boldText: false),
            child: BanGate(
                notice: widget.banNotice,
                onRetry: widget.onBanRetry,
                child: ResponsiveShell(
                    banner: AdBannerStrip.fromConfig(),
                    child: child ?? const SizedBox()))),
        home: EntryFlow(
          account: widget.account,
          builder: (_) => StartupGate(
            key: ValueKey(_epoch),
            profiles: widget.profiles,
            onProfile: widget.onProfile,
            onAccountSwitched: _switched,
            builder: (_) => LobbyScreen(
                service: widget.service,
                inbox: widget.inbox,
                push: widget.push,
                profiles: widget.profiles,
                onProfileChanged: widget.onProfileChanged,
                account: widget.account,
                ads: widget.ads,
                onAccountSwitched: _switched),
          ),
        ),
      );
}
