import 'dart:async';
import 'dart:io' show Platform;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import '../diagnostics/app_log.dart';
import '../models/app_settings.dart';

/// Ses efektleri. Ayarlardaki "Ses" kapalıysa hiçbir şey çalmaz.
///
/// Sesler `assets/sounds/` altında; kendi sesini aynı dosya adıyla üstüne koyman yeter.
///  * tas.mp3: taş atma, çekme, soldan alma, per açma/işleme
///  * okey_alkis.mp3: okey atarak bitirme alkışı
///  * normal_alkis.mp3: normal el bitişi alkışı
///  * sira.mp3: sıra bana gelince
///  * ceza.mp3: +101 ceza yazılınca (kim yerse)
///  * uyari.mp3 / acil.mp3: süre bitmeye yaklaşırken (son 10 sn tık, son 3 sn acil çift bip)
///  * baslama.mp3: "OYUN BAŞLIYOR" geri sayımı bitip oyun başlarken çalan çan (ding-DING)
///  * muzik.mp3: arka plan müziği (döngü, düşük ses). Ayarlardaki "Müzik" anahtarı açıp kapatır; uygulama
///    arka plana gidince durur, dönünce devam eder.
///
/// Titreşim: Ayarlardaki "Titreşim" anahtarı. Ses kapalı olsa da çalışır. Yalnız SENİN hamlelerinde
/// (taş çekme/atma/işleme, sıra sana geldi, kendi cezan, kazandığın el); botların hamlesi titretmez.
///
/// Ses hiçbir zaman oyunu bozmaz: dosya ya da eklenti sorunu olursa bir kez loglanır, sonra sessiz kalınır.
/// `flutter test` altında kapalıdır.
class Sfx with WidgetsBindingObserver {
  Sfx._();
  static final Sfx I = Sfx._();

  static const _tile = 'sounds/tas.mp3'; // assets/ öneki audioplayers tarafından eklenir
  static const _cheerOkey = 'sounds/okey_alkis.mp3';
  static const _cheerNormal = 'sounds/normal_alkis.mp3';
  static const _turnS = 'sounds/sira.mp3';
  static const _penaltyS = 'sounds/ceza.mp3';
  static const _warnS = 'sounds/uyari.mp3';
  static const _urgentS = 'sounds/acil.mp3';
  static const _startS = 'sounds/baslama.mp3';
  static const _musicS = 'sounds/muzik.mp3';
  static const _musicVolume = 0.28; // efektlerin altında kalsın
  AudioPool? _tilePool, _turnPool, _penaltyPool, _warnPool, _urgentPool, _startPool;
  AudioPlayer? _cheer; // alkış tek oynatıcıda: yeni el başlayınca kesilebilsin
  AudioPlayer? _music;
  bool _musicWanted = false, _inBackground = false, _hooked = false;
  Future<void>? _init;
  bool _broken = Platform.environment.containsKey('FLUTTER_TEST');

  /// Açılışta çağır: ilk sesin gecikmesini önler.
  Future<void> preload() => _ready();

  /// Taş sesi (atma, çekme, per). [mine] true ise (senin hamlen) hafif titreşim de verir.
  void tile({bool mine = false}) {
    if (mine) _buzz(HapticFeedback.selectionClick);
    if (_broken || !AppSettings.I.sound) return;
    unawaited(_playTile());
  }

  /// Sıra bana geldi.
  void myTurn() {
    _buzz(HapticFeedback.mediumImpact);
    _fx(() => _turnPool);
  }

  /// +101 ceza yazıldı. [mine] true ise (ceza sana yazıldı) güçlü titreşim de verir.
  void penalty({bool mine = false}) {
    if (mine) _buzz(HapticFeedback.heavyImpact);
    _fx(() => _penaltyPool);
  }

  /// Geri sayım bitti, oyun başlıyor: başlama zili + güçlü titreşim.
  void matchStart() {
    _buzz(HapticFeedback.heavyImpact);
    _fx(() => _startPool);
  }

  /// Süre azalıyor: [urgent] true ise son saniyeler (daha tiz çift bip).
  void warn({bool urgent = false}) => _fx(() => urgent ? _urgentPool : _warnPool);

  void _fx(AudioPool? Function() pool) {
    if (_broken || !AppSettings.I.sound) return;
    unawaited(() async {
      try {
        await _ready();
        await pool()?.start();
      } catch (e) {
        _broken = true;
        Log.w('ses', 'ses çalınamadı, sessiz devam: $e');
      }
    }());
  }

  /// El bitişi alkışı: [okey] true ise okey atarak bitirme, değilse normal bitiş.
  /// [mine] true ise eli SEN kazandın: titreşim de verir. Alkış yalnız o zaman çalar (çağıran karar verir).
  void cheer({required bool okey, bool mine = false}) {
    if (mine) {
      _buzz(HapticFeedback.heavyImpact);
      if (okey) Future<void>.delayed(const Duration(milliseconds: 180), () => _buzz(HapticFeedback.heavyImpact));
    }
    if (_broken || !AppSettings.I.sound) return;
    unawaited(_playCheer(okey));
  }

  /// Alkış sürerken yeni el başlarsa ya da masadan çıkılırsa keser.
  void stopCheer() {
    final p = _cheer;
    if (p == null) return;
    unawaited(p.stop().catchError((Object _) {}));
  }

  void _buzz(Future<void> Function() f) {
    if (_testing || !AppSettings.I.vibration) return;
    unawaited(f().catchError((Object _) {}));
  }

  bool get _testing => Platform.environment.containsKey('FLUTTER_TEST');

  // ------------------------------------------------------------ arka plan müziği

  /// Açılışta bir kez çağır: müzik ayarını dinler ve uygulama arka plana gidince durdurur.
  void startMusic() {
    if (_testing || _hooked) return;
    _hooked = true;
    WidgetsBinding.instance.addObserver(this);
    AppSettings.I.addListener(_syncMusic);
    _syncMusic();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _inBackground = state != AppLifecycleState.resumed;
    _syncMusic();
  }

  void _syncMusic() {
    final want = AppSettings.I.music && !_inBackground;
    if (want == _musicWanted) return;
    _musicWanted = want;
    unawaited(_applyMusic());
  }

  Future<void> _applyMusic() async {
    if (_broken) return;
    try {
      final p = _music ??= AudioPlayer();
      if (_musicWanted) {
        await p.setReleaseMode(ReleaseMode.loop);
        await p.setVolume(_musicVolume);
        if (p.state == PlayerState.paused) {
          await p.resume();
        } else {
          await p.play(AssetSource(_musicS), volume: _musicVolume);
        }
      } else {
        await p.pause();
      }
    } catch (e) {
      Log.w('ses', 'müzik çalınamadı, sessiz devam: $e');
    }
  }

  Future<void> _ready() => _init ??= () async {
        if (_broken) return;
        try {
          // Telefonda çalan müziği durdurma: oyun sesi üstüne karışsın.
          await AudioPlayer.global.setAudioContext(
              AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build());
          _tilePool = await AudioPool.createFromAsset(path: _tile, maxPlayers: 4);
          _turnPool = await AudioPool.createFromAsset(path: _turnS, maxPlayers: 1);
          _penaltyPool = await AudioPool.createFromAsset(path: _penaltyS, maxPlayers: 2);
          _warnPool = await AudioPool.createFromAsset(path: _warnS, maxPlayers: 2);
          _urgentPool = await AudioPool.createFromAsset(path: _urgentS, maxPlayers: 2);
          _startPool = await AudioPool.createFromAsset(path: _startS, maxPlayers: 1);
        } catch (e) {
          _broken = true;
          Log.w('ses', 'ses yüklenemedi, sessiz devam: $e');
        }
      }();

  Future<void> _playCheer(bool okey) async {
    try {
      await _ready();
      final p = _cheer ??= AudioPlayer();
      await p.stop();
      await p.play(AssetSource(okey ? _cheerOkey : _cheerNormal));
    } catch (e) {
      _broken = true;
      Log.w('ses', 'alkış çalınamadı, sessiz devam: $e');
    }
  }

  Future<void> _playTile() async {
    try {
      await _ready();
      await _tilePool?.start();
    } catch (e) {
      _broken = true;
      Log.w('ses', 'ses çalınamadı, sessiz devam: $e');
    }
  }
}
