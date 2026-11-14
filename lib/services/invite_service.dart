import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/invite.dart';

/// Davet işlemi başarısız oldu. [message] kullanıcıya olduğu gibi gösterilir.
class InviteException implements Exception {
  final String message;
  const InviteException(this.message);
  @override
  String toString() => message;
}

/// Sunucu hata kodlarının (migration-019.sql) Türkçe karşılıkları.
const Map<String, String> kInviteErrors = {
  'davet_zaten_girdi': 'Zaten bir davet kodu girdin.',
  'davet_seviye_gecti': 'Kod girme süresi doldu. Kod yalnızca 4. seviyeye kadar girilebilir.',
  'davet_kod_gecersiz': 'Bu kod geçerli değil. Kodu kontrol et.',
  'davet_kendi_kodu': 'Kendi kodunu giremezsin.',
  'davet_ayni_cihaz': 'Aynı cihazdaki hesapların kodu girilemez.',
  'davet_kontenjan_dolu': 'Bu kodun davet kontenjanı doldu.',
  'giris_gerekli': 'Oturum süresi doldu, uygulamayı yeniden aç.',
  'profil_yok': 'Profil bulunamadı.',
};

/// Arkadaş daveti servisi. Arayüzün tek bağımlılığı.
abstract class InviteService {
  /// Davet kodum, sayaçlar, kademeler ve kod girme kutusunun açık olup olmadığı.
  Future<InviteStatus> status();

  /// Bir arkadaşın davet kodunu girer. Başarısızsa [InviteException] fırlatır.
  Future<void> redeem(String code);
}

/// Önizleme (FlutLab) için bellek içi davet. Gerçek sunucu yokken ekranı denemek içindir.
class MockInviteService implements InviteService {
  bool _redeemed = false;
  final int _level = 2;
  final int _xp = 180;

  @override
  Future<InviteStatus> status() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return InviteStatus(
      code: 'DEMO2K9X',
      level: _level,
      qualifyLevel: kInviteQualifyLevel,
      xp: _xp,
      xpQualify: 600,
      maxInvites: kInviteMax,
      count: 1,
      pending: 1,
      canRedeem: !_redeemed,
      invited: _redeemed,
      inviteeQualified: false,
      inviteeBonus: kInviteeBonus,
      bonusSent: false,
      bonusClaimed: false,
      tiers: [
        for (final e in kInviteTierChips.entries)
          InviteTier(
              count: e.key, chips: e.value, reached: e.key <= 1, sent: e.key <= 1, claimed: false)
      ],
    );
  }

  @override
  Future<void> redeem(String code) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final c = code.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (c.length != 8) throw InviteException(kInviteErrors['davet_kod_gecersiz']!);
    if (c.toUpperCase() == 'DEMO2K9X') throw InviteException(kInviteErrors['davet_kendi_kodu']!);
    _redeemed = true;
  }
}

/// Gerçek servis: Supabase RPC (`invite_status`, `redeem_invite_code`). Ödüller sunucuda hesaplanır ve mesaj
/// kutusuna düşer; istemci hiçbir çip eklemez.
class SupabaseInviteService implements InviteService {
  final String url; // https://xxxx.supabase.co
  final String anonKey; // herkese açık anon anahtarı (service_role ASLA)
  final Future<String> Function() accessToken;
  final http.Client _client;

  SupabaseInviteService({
    required this.url,
    required this.anonKey,
    required this.accessToken,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Future<Map<String, dynamic>> _rpc(String fn, [Map<String, dynamic>? body]) async {
    final http.Response r;
    try {
      r = await _client.post(Uri.parse('$url/rest/v1/rpc/$fn'),
          headers: {
            'apikey': anonKey,
            'Authorization': 'Bearer ${await accessToken()}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body ?? <String, dynamic>{}));
    } catch (_) {
      throw const InviteException('Bağlantı kurulamadı. İnternetini kontrol et.');
    }
    if (r.statusCode != 200) {
      var code = '';
      try {
        code = ((jsonDecode(r.body) as Map)['message'] ?? '').toString();
      } catch (_) {}
      throw InviteException(kInviteErrors[code] ?? 'İşlem yapılamadı (${r.statusCode}). Tekrar dene.');
    }
    return (jsonDecode(r.body) as Map).cast<String, dynamic>();
  }

  @override
  Future<InviteStatus> status() async => InviteStatus.fromJson(await _rpc('invite_status'));

  @override
  Future<void> redeem(String code) async {
    await _rpc('redeem_invite_code', {'p_code': code});
  }
}
