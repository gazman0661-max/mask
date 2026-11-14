/// Arkadaş daveti modelleri (Supabase: migration-019.sql). Asıl değerler SUNUCUDAN gelir; buradakiler yalnız
/// ağ yokken / önizlemede (Mock) gösterilen varsayılanlardır ve migration-019'daki ayarlarla AYNI tutulmalıdır.
const int kInviteQualifyLevel = 4;
const int kInviteMax = 5;
const int kInviteeBonus = 10000;

/// Davet edene verilen kademe ödülleri: {arkadaş sayısı: çip}.
const Map<int, int> kInviteTierChips = {1: 10000, 3: 25000, 5: 50000};

/// Davet kodunu "ABCD-EFGH" biçiminde gösterir (sunucu 8 harfi ham verir).
String formatInviteCode(String raw) {
  final c = raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  return c.length == 8 ? '${c.substring(0, 4)}-${c.substring(4)}' : c;
}

/// Kademe ödülü: [count] kadar arkadaş seviyeye ulaşınca davet edene [chips] çip mesaj kutusuna düşer.
class InviteTier {
  final int count;
  final int chips;

  /// Yeterli arkadaş seviyeye ulaştı.
  final bool reached;

  /// Ödül mesaj kutusuna gönderildi.
  final bool sent;

  /// Mesaj kutusundan AL'a basılıp alındı.
  final bool claimed;
  const InviteTier({
    required this.count,
    required this.chips,
    required this.reached,
    required this.sent,
    required this.claimed,
  });

  factory InviteTier.fromJson(Map<String, dynamic> j) => InviteTier(
        count: (j['count'] as num).toInt(),
        chips: (j['chips'] as num).toInt(),
        reached: j['reached'] == true,
        sent: j['sent'] == true,
        claimed: j['claimed'] == true,
      );
}

/// Davet ekranının durumu (sunucudaki `invite_status()` yanıtı).
class InviteStatus {
  /// Ham 8 harfli kod (gösterirken [formatInviteCode]).
  final String code;
  final int level;
  final int qualifyLevel;
  final int xp;
  final int xpQualify;
  final int maxInvites;

  /// Seviyeye ulaşıp sayılan arkadaş sayısı.
  final int count;

  /// Kodunu girmiş ama henüz seviyeye ulaşmamış arkadaşlar.
  final int pending;

  /// Kod girme kutusu açık mı (hiç kod girilmemiş ve seviye hedefin altında).
  final bool canRedeem;

  /// Bu oyuncu bir davetle gelmiş mi.
  final bool invited;

  /// Davetle gelen oyuncu hedef seviyeye ulaştı mı (hediyesi gönderildi).
  final bool inviteeQualified;
  final int inviteeBonus;
  final bool bonusSent;
  final bool bonusClaimed;
  final List<InviteTier> tiers;

  const InviteStatus({
    required this.code,
    required this.level,
    required this.qualifyLevel,
    required this.xp,
    required this.xpQualify,
    required this.maxInvites,
    required this.count,
    required this.pending,
    required this.canRedeem,
    required this.invited,
    required this.inviteeQualified,
    required this.inviteeBonus,
    required this.bonusSent,
    required this.bonusClaimed,
    required this.tiers,
  });

  /// Hedef seviyeye kalan XP (0 = ulaşıldı).
  int get xpLeft => xp >= xpQualify ? 0 : xpQualify - xp;

  /// Ödülü gelmemiş bir sonraki kademe (hepsi bittiyse null).
  InviteTier? get nextTier {
    for (final t in tiers) {
      if (!t.reached) return t;
    }
    return null;
  }

  factory InviteStatus.fromJson(Map<String, dynamic> j) => InviteStatus(
        code: (j['code'] ?? '') as String,
        level: (j['level'] as num?)?.toInt() ?? 1,
        qualifyLevel: (j['qualify_level'] as num?)?.toInt() ?? kInviteQualifyLevel,
        xp: (j['xp'] as num?)?.toInt() ?? 0,
        xpQualify: (j['xp_qualify'] as num?)?.toInt() ?? 0,
        maxInvites: (j['max'] as num?)?.toInt() ?? kInviteMax,
        count: (j['count'] as num?)?.toInt() ?? 0,
        pending: (j['pending'] as num?)?.toInt() ?? 0,
        canRedeem: j['can_redeem'] == true,
        invited: j['invited'] == true,
        inviteeQualified: j['invitee_qualified'] == true,
        inviteeBonus: (j['invitee_bonus'] as num?)?.toInt() ?? kInviteeBonus,
        bonusSent: j['bonus_sent'] == true,
        bonusClaimed: j['bonus_claimed'] == true,
        tiers: [
          for (final t in (j['tiers'] as List<dynamic>? ?? const []))
            InviteTier.fromJson((t as Map).cast<String, dynamic>())
        ],
      );
}
