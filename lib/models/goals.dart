/// Günlük görevler, başarımlar ve haftalık lig sıralaması modelleri.
/// Hedef/ödül sayıları sunucudaki `migration-015.sql` ile AYNI olmalı (sunucu ödülü kendisi doğrular).

/// Günlük görev tanımı. [stat]: TasksStatus içindeki sayaç ('played' | 'wins' | 'pts').
class TaskDef {
  final String id;
  final String title;
  final String stat;
  final int target;
  final int reward; // bilet
  const TaskDef(this.id, this.title, this.stat, this.target, this.reward);
}

const List<TaskDef> kDailyTasks = [
  TaskDef('play3', '3 maç bitir', 'played', 3, 1),
  TaskDef('win1', '1 maç kazan', 'wins', 1, 1),
  TaskDef('pts150', '150 lig puanı topla', 'pts', 150, 1),
];

class TasksStatus {
  final int played;
  final int wins;
  final int pts;
  final Set<String> claimed;
  const TasksStatus({this.played = 0, this.wins = 0, this.pts = 0, this.claimed = const {}});

  factory TasksStatus.fromJson(Map<String, dynamic> j) => TasksStatus(
        played: (j['played'] as num?)?.toInt() ?? 0,
        wins: (j['wins'] as num?)?.toInt() ?? 0,
        pts: (j['pts'] as num?)?.toInt() ?? 0,
        claimed: ((j['claimed'] as List?) ?? const []).map((e) => e.toString()).toSet(),
      );

  int valueOf(TaskDef t) => switch (t.stat) {
        'played' => played,
        'wins' => wins,
        _ => pts,
      };

  bool done(TaskDef t) => valueOf(t) >= t.target;
  bool isClaimed(TaskDef t) => claimed.contains(t.id);
}

/// Başarım tanımı: 4 kademe. [stat]: AchStatus içindeki sayaç ('played' | 'wins' | 'xp').
class AchDef {
  final String id;
  final String icon;
  final String title;
  final String desc; // {n} = hedef
  final String stat;
  final List<int> targets;
  const AchDef(this.id, this.icon, this.title, this.desc, this.stat, this.targets);

  String describe(int target) => desc.replaceAll('{n}', '$target');
}

/// Kademe ödülleri (bilet): 1. 2. 3. 4. kademe.
const List<int> kAchRewards = [1, 1, 2, 3];
const List<String> kTierIcons = ['🥉', '🥈', '🥇', '💎'];

const List<AchDef> kAchDefs = [
  AchDef('played', '🎴', 'Masa Kurdu', 'Toplam {n} maç bitir', 'played', [5, 25, 100, 500]),
  AchDef('wins', '🏆', 'Şampiyon', 'Toplam {n} maç kazan', 'wins', [1, 10, 50, 200]),
  AchDef('xp', '⭐', 'Tecrübe', 'Toplam {n} XP topla', 'xp', [200, 1000, 5000, 20000]),
];

class AchStatus {
  final int played;
  final int wins;
  final int xp;
  final Map<String, int> claimed; // başarım -> alınan en yüksek kademe (0-4)
  const AchStatus({this.played = 0, this.wins = 0, this.xp = 0, this.claimed = const {}});

  factory AchStatus.fromJson(Map<String, dynamic> j) {
    final raw = (j['claimed'] as Map?) ?? const {};
    return AchStatus(
      played: (j['played'] as num?)?.toInt() ?? 0,
      wins: (j['wins'] as num?)?.toInt() ?? 0,
      xp: (j['xp'] as num?)?.toInt() ?? 0,
      claimed: {for (final e in raw.entries) e.key.toString(): (e.value as num).toInt()},
    );
  }

  int valueOf(AchDef a) => switch (a.stat) {
        'played' => played,
        'wins' => wins,
        _ => xp,
      };

  int claimedTier(AchDef a) => claimed[a.id] ?? 0;

  /// Hedefi tamamlanmış ama ödülü alınmamış kademe sayısı (rozet için).
  int pendingTiers(AchDef a) {
    final v = valueOf(a);
    var done = 0;
    for (final t in a.targets) {
      if (v >= t) done++;
    }
    final p = done - claimedTier(a);
    return p < 0 ? 0 : p;
  }
}

/// Görev / başarım ödülü alınınca dönen sonuç.
class GoalClaim {
  final int amount;
  final int tickets;
  const GoalClaim({required this.amount, required this.tickets});

  factory GoalClaim.fromJson(Map<String, dynamic> j) =>
      GoalClaim(amount: (j['amount'] as num).toInt(), tickets: (j['tickets'] as num).toInt());
}

/// Haftalık lig sıralaması satırı (sunucu `league_top`).
class LeagueRow {
  final int pos;
  final String userId;
  final String name;
  final int avatar;
  final int points;
  const LeagueRow({required this.pos, required this.userId, required this.name, required this.avatar, required this.points});

  factory LeagueRow.fromJson(Map<String, dynamic> j) => LeagueRow(
        pos: (j['pos'] as num).toInt(),
        userId: (j['user_id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        avatar: (j['avatar'] as num?)?.toInt() ?? 0,
        points: (j['points'] as num?)?.toInt() ?? 0,
      );
}
