/// Push bildirimi (uygulama kapalıyken gelen iade bildirimi).
/// Varsayılan [NoopPushService] hiçbir şey yapmaz; Firebase kurulunca
/// docs/PUSH_KURULUM.md içindeki FcmPushService ile değiştirilir.
abstract class PushService {
  /// [onOpenInbox]: oyuncu bildirime dokundu (mesaj kutusunu aç).
  /// [onInboxChanged]: uygulama açıkken yeni mesaj geldi (rozeti yenile).
  Future<void> init({
    required void Function() onOpenInbox,
    required void Function() onInboxChanged,
  });
}

class NoopPushService implements PushService {
  const NoopPushService();
  @override
  Future<void> init({
    required void Function() onOpenInbox,
    required void Function() onInboxChanged,
  }) async {}
}
