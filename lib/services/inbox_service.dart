import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/inbox_message.dart';

/// Mesaj kutusu işlemi başarısız oldu. [message] kullanıcıya olduğu gibi gösterilir.
class InboxException implements Exception {
  final String message;
  const InboxException(this.message);
  @override
  String toString() => message;
}

/// Mesaj kutusu servisi. Arayüzün tek bağımlılığı.
abstract class InboxService {
  /// En yeni mesaj en üstte.
  Future<List<InboxMessage>> fetch();

  /// AL butonu: çipler hesaba geçer. Dönüş: geçen çip (mesaj zaten alınmışsa 0).
  Future<int> claim(String id);
}

/// Önizleme (FlutLab) için bellek içi kutu. Uygulama başında örnek bir iade mesajı vardır.
class MockInboxService implements InboxService {
  /// AL'a basılınca biletin/çipin hesaba eklenmesi için (MockGameService).
  final void Function(int amount) onCredit;

  MockInboxService({required this.onCredit}) {
    _items.add(InboxMessage(
      id: 'demo-1',
      kind: 'ticket_refund',
      amount: 1,
      title: 'Biletin iade edildi',
      body: 'Sunucu hatası nedeniyle maçınız tamamlanamadı. 1 bilet iade '
          'edilmiştir, özür dileriz. Hesabınıza geçmesi için AL\'a dokunun.',
      createdAt: DateTime.now().subtract(const Duration(minutes: 12)),
    ));
  }

  final List<InboxMessage> _items = [];

  @override
  Future<List<InboxMessage>> fetch() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return List.of(_items);
  }

  @override
  Future<int> claim(String id) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final i = _items.indexWhere((m) => m.id == id);
    if (i < 0) throw const InboxException('Mesaj bulunamadı.');
    if (_items[i].claimed) return 0;
    _items[i] = _items[i].copyWith(claimedAt: DateTime.now());
    onCredit(_items[i].amount);
    return _items[i].amount;
  }
}

/// Gerçek kutu: Supabase REST. [accessToken] giriş yapmış oyuncunun Supabase
/// access_token'ını döndürmelidir (RLS: oyuncu yalnız kendi mesajlarını görür).
class SupabaseInboxService implements InboxService {
  final String url; // https://xxxx.supabase.co
  final String anonKey; // herkese açık anon anahtarı (service_role ASLA)
  final Future<String> Function() accessToken;
  final http.Client _client;

  SupabaseInboxService({
    required this.url,
    required this.anonKey,
    required this.accessToken,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Future<Map<String, String>> _headers() async => {
        'apikey': anonKey,
        'Authorization': 'Bearer ${await accessToken()}',
        'Content-Type': 'application/json',
      };

  @override
  Future<List<InboxMessage>> fetch() async {
    final r = await _client.get(
        Uri.parse('$url/rest/v1/inbox'
            '?select=id,kind,amount,title,body,created_at,claimed_at'
            '&order=created_at.desc&limit=50'),
        headers: await _headers());
    if (r.statusCode != 200) {
      throw InboxException('Mesajlar alınamadı (${r.statusCode}).');
    }
    final list = jsonDecode(r.body) as List<dynamic>;
    return list
        .map((e) => InboxMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<int> claim(String id) async {
    final r = await _client.post(Uri.parse('$url/rest/v1/rpc/claim_inbox'),
        headers: await _headers(), body: jsonEncode({'p_id': id}));
    if (r.statusCode != 200) {
      throw InboxException('Çip alınamadı (${r.statusCode}). Tekrar dene.');
    }
    return (jsonDecode(r.body) as num).toInt();
  }

  /// Push için: FCM token'ını bu hesaba bağlar (Supabase register_device).
  Future<void> registerDevice(String token, {String platform = 'android'}) async {
    final r = await _client.post(Uri.parse('$url/rest/v1/rpc/register_device'),
        headers: await _headers(),
        body: jsonEncode({'p_token': token, 'p_platform': platform}));
    if (r.statusCode != 200 && r.statusCode != 204) {
      throw InboxException('Cihaz kaydedilemedi (${r.statusCode}).');
    }
  }
}
