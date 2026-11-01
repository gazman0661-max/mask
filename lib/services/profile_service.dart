import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;
import '../models/nick_words.dart';
import '../models/profile.dart';
import 'auth_service.dart';

/// Takma ad + avatar. Arayüzün tek bağımlılığı.
abstract class ProfileService {
  Future<Profile> load();

  /// Kaydeder. [word] = `kNickWords` sırası; sunucu sonuna sayı ekler (Kartal_4821). `null` = ismi değiştirme,
  /// yalnız avatarı güncelle. Kural ihlalinde [ProfileException] (mesaj kullanıcıya gösterilir).
  Future<Profile> save({int? word, required int avatar});
}

/// Gerçek: Supabase. Okuma RLS ile yalnız kendi satırı; yazma yalnız `set_profile` fonksiyonuyla.
class SupabaseProfileService implements ProfileService {
  final AuthService auth;
  final String supabaseUrl;
  final String anonKey;
  final http.Client _http;

  SupabaseProfileService(
      {required this.auth, required this.supabaseUrl, required this.anonKey, http.Client? client})
      : _http = client ?? http.Client();

  Future<Map<String, String>> _headers() async => {
        'apikey': anonKey,
        'Authorization': 'Bearer ${await auth.accessToken()}',
        'Content-Type': 'application/json',
      };

  @override
  Future<Profile> load() async {
    final r = await _http
        .get(Uri.parse('$supabaseUrl/rest/v1/profiles?select=name,avatar,named&limit=1'),
            headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw const ProfileException('Profil alınamadı. Bağlantını kontrol et.');
    final list = jsonDecode(r.body) as List<dynamic>;
    if (list.isEmpty) return Profile.empty;
    final j = list.first as Map<String, dynamic>;
    return Profile(
        name: (j['name'] ?? '') as String,
        avatar: ((j['avatar'] ?? 0) as num).toInt(),
        named: (j['named'] ?? false) as bool);
  }

  @override
  Future<Profile> save({int? word, required int avatar}) async {
    final r = await _http
        .post(Uri.parse('$supabaseUrl/rest/v1/rpc/set_profile'),
            headers: await _headers(), body: jsonEncode({'p_word': word, 'p_avatar': avatar}))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      var code = '';
      try {
        code = ((jsonDecode(r.body) as Map)['message'] ?? '') as String;
      } catch (_) {}
      throw ProfileException(profileErrorText(code));
    }
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return Profile(name: j['name'] as String, avatar: (j['avatar'] as num).toInt(), named: true);
  }
}

/// Önizleme (FlutLab): cihazda saklanır, sunucu yok. Sayı rastgele; benzersizlik burada denetlenmez.
class LocalProfileService implements ProfileService {
  static const _kName = 'profile_name';
  static const _kAvatar = 'profile_avatar';

  @override
  Future<Profile> load() async {
    final p = await SharedPreferences.getInstance();
    final n = p.getString(_kName);
    if (n == null || n.isEmpty) return Profile.empty;
    return Profile(name: n, avatar: p.getInt(_kAvatar) ?? 0, named: true);
  }

  @override
  Future<Profile> save({int? word, required int avatar}) async {
    final p = await SharedPreferences.getInstance();
    var n = p.getString(_kName) ?? '';
    if (word != null) {
      if (word < 0 || word >= kNickWords.length) throw const ProfileException('Listeden bir isim seç.');
      if (nickWordIndex(n) != word) {
        n = '${kNickWords[word]}_${1000 + math.Random().nextInt(9000)}'; // sayıyı sunucu verir (burada sahte)
      }
    } else if (n.isEmpty) {
      throw const ProfileException('Listeden bir isim seç.');
    }
    await p.setString(_kName, n);
    await p.setInt(_kAvatar, avatar);
    return Profile(name: n, avatar: avatar, named: true);
  }
}
