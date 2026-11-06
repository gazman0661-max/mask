import 'package:flutter/material.dart';
import '../diagnostics/app_log.dart';
import '../models/goals.dart';
import '../services/game_service.dart';
import '../theme/app_theme.dart';
import '../widgets/game_toast.dart';
import '../widgets/lobby_widgets.dart';

/// Günlük görevler + başarımlar. İlerleme sunucuda hesaplanır; "AL" bileti sunucudan alır.
class GoalsScreen extends StatefulWidget {
  final GameService service;
  final int initialTab; // 0 = günlük görevler, 1 = başarımlar
  const GoalsScreen({super.key, required this.service, this.initialTab = 0});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  late int _tab = widget.initialTab;
  TasksStatus? _tasks;
  AchStatus? _ach;
  bool _failed = false;
  String? _busy; // ödül alınırken tekrar basılmasın

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await widget.service.fetchTasks();
      final a = await widget.service.fetchAchievements();
      if (!mounted) return;
      setState(() {
        _tasks = t;
        _ach = a;
        _failed = false;
      });
    } catch (e) {
      Log.w('hedefler', 'yüklenemedi: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _claim(String key, Future<GoalClaim> Function() call) async {
    if (_busy != null) return;
    setState(() => _busy = key);
    try {
      final c = await call();
      if (!mounted) return;
      showToast(context, '+${c.amount} bilet kazandın!', kind: ToastKind.success, icon: Icons.confirmation_number_rounded);
      await _load();
    } on JoinException catch (e) {
      if (mounted) showToast(context, e.message, kind: ToastKind.error);
    } catch (e) {
      Log.w('hedefler', 'ödül alınamadı: $e');
      if (mounted) showToast(context, 'Ödül alınamadı, tekrar dene.', kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  // ------------------------------------------------------------------ parçalar

  Widget _header() => Row(children: [
        RoundBtn(icon: Icons.arrow_back, onTap: () => Navigator.of(context).pop()),
        const SizedBox(width: 12),
        const Icon(Icons.flag_rounded, color: AppColors.goldLight, size: 26),
        const SizedBox(width: 8),
        const Text('GÖREVLER',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: AppColors.goldLight)),
        const Spacer(),
        _tabBtn('Günlük', 0, _pendingTasks()),
        const SizedBox(width: 8),
        _tabBtn('Başarımlar', 1, _pendingAch()),
      ]);

  int _pendingTasks() {
    final t = _tasks;
    if (t == null) return 0;
    return kDailyTasks.where((d) => t.done(d) && !t.isClaimed(d)).length;
  }

  int _pendingAch() {
    final a = _ach;
    if (a == null) return 0;
    return kAchDefs.fold<int>(0, (s, d) => s + a.pendingTiers(d));
  }

  Widget _tabBtn(String label, int i, int pending) {
    final on = _tab == i;
    return GestureDetector(
      onTap: () => setState(() => _tab = i),
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: on ? AppColors.gold : Colors.black26,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: on ? AppColors.goldLight : Colors.white24),
          ),
          child: Text(label,
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: on ? Colors.black87 : Colors.white70)),
        ),
        if (pending > 0)
          Positioned(
            right: -4,
            top: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: AppColors.bad, borderRadius: BorderRadius.circular(9)),
              child: Text('$pending', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
            ),
          ),
      ]),
    );
  }

  Widget _card({required Widget child, bool done = false}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: done ? const Color(0xFF2E5A2E) : Colors.black.withOpacity(.28),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: done ? AppColors.green : Colors.white24, width: done ? 1.6 : 1),
        ),
        child: child,
      );

  Widget _bar(double v, {Color color = AppColors.goldLight}) => ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: LinearProgressIndicator(
          value: v.clamp(0.0, 1.0).toDouble(),
          minHeight: 8,
          backgroundColor: Colors.white12,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      );

  Widget _claimBtn(String label, VoidCallback? onTap) => CandyButton(
        onTap: onTap,
        kind: onTap == null ? CandyKind.gray : CandyKind.green,
        radius: 10,
        height: 34,
        child: Text(label, style: const TextStyle(fontSize: 13)),
      );

  Widget _tasksView(TasksStatus st) => Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final t in kDailyTasks) ...[
          Expanded(child: _taskCard(t, st)),
          if (t != kDailyTasks.last) const SizedBox(width: 10),
        ],
      ]);

  Widget _taskCard(TaskDef t, TasksStatus st) {
    final v = st.valueOf(t);
    final claimed = st.isClaimed(t);
    final ready = st.done(t) && !claimed;
    return _card(
      done: claimed,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(claimed ? Icons.check_circle_rounded : Icons.flag_rounded,
            size: 34, color: claimed ? AppColors.green : AppColors.goldLight),
        const SizedBox(height: 6),
        Text(t.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        _bar(v / t.target),
        const SizedBox(height: 4),
        Text('${v > t.target ? t.target : v} / ${t.target}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.confirmation_number_rounded, size: 16, color: AppColors.goldLight),
          const SizedBox(width: 4),
          Text('+${t.reward} bilet', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 8),
        if (claimed)
          const Text('Alındı ✓', style: TextStyle(fontSize: 13, color: Colors.white60))
        else
          _claimBtn(ready ? 'AL' : 'Devam et',
              ready ? () => _claim('t:${t.id}', () => widget.service.claimTask(t.id)) : null),
      ]),
    );
  }

  Widget _achView(AchStatus st) => Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final a in kAchDefs) ...[
          Expanded(child: _achCard(a, st)),
          if (a != kAchDefs.last) const SizedBox(width: 10),
        ],
      ]);

  Widget _achCard(AchDef a, AchStatus st) {
    final v = st.valueOf(a);
    final claimedTier = st.claimedTier(a); // 0-4
    final maxed = claimedTier >= a.targets.length;
    final next = maxed ? a.targets.last : a.targets[claimedTier]; // alınacak / sıradaki kademe hedefi
    final ready = !maxed && v >= next;
    final prev = claimedTier == 0 ? 0 : a.targets[claimedTier - 1];
    final frac = maxed ? 1.0 : ((v - prev) / (next - prev)).clamp(0.0, 1.0).toDouble();
    return _card(
      done: maxed,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(a.icon, style: const TextStyle(fontSize: 30)),
        const SizedBox(height: 4),
        Text(a.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < a.targets.length; i++)
            Opacity(opacity: i < claimedTier ? 1 : .25, child: Text(kTierIcons[i], style: const TextStyle(fontSize: 15))),
        ]),
        const SizedBox(height: 6),
        Text(maxed ? 'Tüm kademeler tamam!' : a.describe(next),
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.white70)),
        const SizedBox(height: 8),
        _bar(frac),
        const SizedBox(height: 4),
        Text(maxed ? '' : '${v > next ? next : v} / $next', style: const TextStyle(fontSize: 12, color: Colors.white70)),
        const SizedBox(height: 8),
        if (!maxed)
          _claimBtn(ready ? 'AL  +${kAchRewards[claimedTier]} bilet' : '+${kAchRewards[claimedTier]} bilet',
              ready ? () => _claim('a:${a.id}', () => widget.service.claimAchievement(a.id, claimedTier + 1)) : null),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _tasks, a = _ach;
    Widget body;
    if (_failed) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Yüklenemedi', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 10),
          CandyButton(onTap: _load, kind: CandyKind.orange, width: 140, height: 38, child: const Text('Tekrar dene')),
        ]),
      );
    } else if (t == null || a == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = SingleChildScrollView(
        child: Column(children: [
          if (_tab == 0)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Görevler her gün (Türkiye saati) yenilenir.', style: TextStyle(fontSize: 12, color: Colors.white60)),
            ),
          SizedBox(height: 230, child: _tab == 0 ? _tasksView(t) : _achView(a)),
        ]),
      );
    }
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Column(children: [
              _header(),
              const SizedBox(height: 12),
              Expanded(child: body),
            ]),
          ),
        ),
      ),
    );
  }
}
