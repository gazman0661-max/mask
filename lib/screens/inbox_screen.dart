import '../widgets/responsive_shell.dart';
import 'package:flutter/material.dart';
import '../diagnostics/app_log.dart';
import '../models/inbox_message.dart';
import '../services/inbox_service.dart';
import '../theme/app_theme.dart';
import '../widgets/lobby_widgets.dart';
import '../widgets/player_badge.dart' show formatChips;
import '../widgets/reward_popup.dart';

/// Mesaj kutusu: sunucu hatası iadeleri burada bekler, AL'a basınca bilet/çipler hesaba geçer.
class InboxScreen extends StatefulWidget {
  final InboxService service;
  const InboxScreen({super.key, required this.service});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  List<InboxMessage> _items = const [];
  bool _loading = true;
  String? _error;
  final Set<String> _claiming = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.service.fetch();
      Log.i('kutu', 'mesajlar yüklendi: ${list.length}');
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e, s) {
      Log.e('kutu', 'mesajlar yüklenemedi', e, s);
      if (!mounted) return;
      setState(() {
        _error = e is InboxException ? e.message : 'Mesajlar alınamadı.';
        _loading = false;
      });
    }
  }

  Future<void> _claim(InboxMessage m) async {
    if (_claiming.contains(m.id)) return;
    setState(() => _claiming.add(m.id));
    try {
      final got = await widget.service.claim(m.id);
      Log.i('kutu', 'AL: ${m.id} -> $got ${m.unit}');
      if (!mounted) return;
      setState(() {
        _claiming.remove(m.id);
        _items = [
          for (final x in _items)
            if (x.id == m.id) x.copyWith(claimedAt: DateTime.now()) else x
        ];
      });
      if (got > 0 && m.isTicket) {
        showToast(context, '+$got bilet hesabına geçti.', kind: ToastKind.success);
      } else if (got > 0) {
        await showRewardReceived(context, amount: got, title: 'MESAJ ÖDÜLÜ');
      } else {
        showToast(context, 'Bunu zaten almıştın.', kind: ToastKind.warn);
      }
    } catch (e, s) {
      Log.e('kutu', 'AL başarısız: ${m.id}', e, s);
      if (!mounted) return;
      setState(() => _claiming.remove(m.id));
      showToast(context, e is InboxException ? e.message : 'Alınamadı.',
          kind: ToastKind.error);
    }
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'şimdi';
    if (d.inMinutes < 60) return '${d.inMinutes} dk önce';
    if (d.inHours < 24) return '${d.inHours} sa önce';
    return '${d.inDays} gün önce';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Column(children: [
              Row(children: [
                RoundBtn(
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.of(context).pop()),
                const SizedBox(width: 12),
                const Text('MESAJ KUTUSU',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppColors.goldLight)),
                if (BannerSlotMarker.isAvailable(context))
                  const Expanded(child: Center(child: BannerSlotMarker()))
                else
                  const Spacer(),
                RoundBtn(icon: Icons.refresh, onTap: _load),
              ]),
              const SizedBox(height: 8),
              Expanded(child: _body()),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
          child: Text(_error!,
              style: const TextStyle(fontSize: 16, color: Colors.white70)));
    }
    if (_items.isEmpty) {
      return const Center(
          child: Text('Mesaj kutun boş.',
              style: TextStyle(fontSize: 16, color: Colors.white70)));
    }
    return ListView.separated(
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _card(_items[i]),
    );
  }

  Widget _card(InboxMessage m) {
    final busy = _claiming.contains(m.id);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: m.claimed ? const Color(0xFF4F1022) : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: m.claimable ? AppColors.gold : Colors.white24, width: 1.5),
      ),
      child: Row(children: [
        Icon(m.amount > 0 ? Icons.redeem : Icons.mail_outline,
            size: 34, color: m.claimable ? AppColors.gold : Colors.white38),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(m.title,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: m.claimed ? Colors.white54 : Colors.white)),
                  ),
                  Text(_ago(m.createdAt),
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white38)),
                ]),
                const SizedBox(height: 3),
                Text(m.body,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: m.claimed ? Colors.white38 : Colors.white70)),
              ]),
        ),
        const SizedBox(width: 10),
        if (m.claimable)
          SizedBox(
            width: 110,
            child: CandyButton(
              onTap: busy ? null : () => _claim(m),
              kind: CandyKind.green,
              radius: 14,
              height: 50,
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(busy ? '...' : 'AL',
                        style: const TextStyle(fontSize: 20, height: 1.1)),
                    Text('+${formatChips(m.amount)} ${m.unit}',
                        style: const TextStyle(
                            fontSize: 10.5, fontWeight: FontWeight.w700)),
                  ]),
            ),
          )
        else if (m.claimed)
          const Text('Alındı ✓',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.good)),
      ]),
    );
  }
}
