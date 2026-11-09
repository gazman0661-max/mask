/// Bot koltuğunun avatarı (sunucu `bots` bayrağını yollar); hazır avatarlar 0-19, bu onların dışında.
const int kBotAvatar = 99;

class Player {
  final String id;
  final String name;
  final int chipCount;
  final String? avatarUrl;
  /// Hazır avatar sırası (0-19). null ise baş harf gösterilir.
  final int? avatar;
  final int level;

  const Player({
    required this.id,
    required this.name,
    required this.chipCount,
    this.avatarUrl,
    this.avatar,
    this.level = 1,
  });

  factory Player.fromJson(Map<String, dynamic> j) => Player(
        id: j['id'] as String,
        name: j['name'] as String,
        chipCount: j['chipCount'] as int,
        avatarUrl: j['avatarUrl'] as String?,
        avatar: (j['avatar'] as num?)?.toInt(),
        level: (j['level'] ?? 1) as int,
      );
}
