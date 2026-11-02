import 'package:flutter/material.dart';
import '../models/quick_chat.dart';
import '../theme/app_theme.dart';

/// Hazır mesaj + emoji paneli. Bir şeye dokununca [onPick] çağrılır (panelin kapanması üstteki ekranın işi).
/// [ready] false ise (bekleme süresi dolmadı) düğmeler soluk görünür ve dokunuş yok sayılır.
class ChatPanel extends StatelessWidget {
  final void Function(QuickChat) onPick;
  final VoidCallback onClose;
  final bool ready;
  const ChatPanel({super.key, required this.onPick, required this.onClose, this.ready = true});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 330),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.surfaceLight, AppColors.surface]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.gold, width: 2),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12)],
        ),
        child: Opacity(
          opacity: ready ? 1 : .45,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(ready ? 'HIZLI MESAJ' : 'BİRAZ BEKLE...',
                      style: const TextStyle(
                          fontSize: 11,
                          letterSpacing: .8,
                          fontWeight: FontWeight.w800,
                          color: AppColors.goldLight))),
              GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  child: const Padding(
                      padding: EdgeInsets.all(2), child: Icon(Icons.close_rounded, size: 18, color: Colors.white70))),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final c in kQuickPhrases) _phrase(c),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final c in kQuickEmojis) _emoji(c),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _phrase(QuickChat c) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: ready ? () => onPick(c) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(.32),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.gold.withOpacity(.6)),
          ),
          child: Text(c.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ),
      );

  Widget _emoji(QuickChat c) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: ready ? () => onPick(c) : null,
        child: Container(
          width: 40,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(.32),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Text(c.label, style: const TextStyle(fontSize: 22)),
        ),
      );
}

/// Oyuncunun yanında çıkan konuşma balonu. Cümle: krem zeminde koyu yazı; emoji: büyük, zeminsiz.
class ChatBubble extends StatelessWidget {
  final QuickChat chat;
  const ChatBubble({super.key, required this.chat});

  @override
  Widget build(BuildContext context) {
    if (chat.isEmoji) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.55),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.gold.withOpacity(.8), width: 1.5),
        ),
        child: Text(chat.label, style: const TextStyle(fontSize: 34)),
      );
    }
    return Container(
      constraints: const BoxConstraints(maxWidth: 160),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.tileCream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
      ),
      child: Text(chat.label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.tileBlack)),
    );
  }
}

/// [chat] null ise hiçbir şey çizmez; yeni mesaj gelince ([gen] değişince) balon yumuşakça belirir,
/// süre dolunca ([chat] null olunca) küçülerek kaybolur. Dokunuşları geçirir.
class ChatBubbleSlot extends StatelessWidget {
  final QuickChat? chat;
  final int gen;
  const ChatBubbleSlot({super.key, required this.chat, required this.gen});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(
                scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn),
                child: child)),
        child: chat == null
            ? const SizedBox.shrink(key: ValueKey('chat-none'))
            : ChatBubble(key: ValueKey('chat-$gen'), chat: chat!),
      ),
    );
  }
}
