import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Hazır avatar sayısı. Sunucu (`AVATAR_COUNT`) ve Supabase (`avatar between 0 and 19`) ile AYNI olmalı.
const int kAvatarCount = 20;

// GEÇİCİ avatarlar: emoji + renk. Kendi resimlerini hazırlayınca SADECE [AvatarWidget]'in
// içini değiştir (örn. Image.asset('assets/avatars/a${index}.png')); başka hiçbir yere dokunmana gerek yok.
const List<String> _emojis = [
  '🦁', '🐯', '🦊', '🐺', '🐻', '🐼', '🦅', '🦉', '🐎', '🐆',
  '🐘', '🦌', '🐢', '🐬', '🦈', '🐙', '🦋', '🐝', '🦄', '🐲',
];
const List<Color> _colors = [
  Color(0xFF8A5A33), Color(0xFFB85E08), Color(0xFF9C4A1A), Color(0xFF4B5563), Color(0xFF6B4226),
  Color(0xFF3B5E8E), Color(0xFF1B5C74), Color(0xFF55193F), Color(0xFF7A5C1E), Color(0xFF8A3B12),
  Color(0xFF4B5E6B), Color(0xFF5E7A2A), Color(0xFF1F7A25), Color(0xFF1E6BD0), Color(0xFF39506B),
  Color(0xFF7A2A5A), Color(0xFF9A3C8A), Color(0xFFB8860B), Color(0xFF5B4B9A), Color(0xFF0F3B4E),
];

class AvatarWidget extends StatelessWidget {
  final int index;
  final double size;
  final bool selected;
  const AvatarWidget({super.key, required this.index, this.size = 40, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final i = index < 0 || index >= kAvatarCount ? 0 : index;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _colors[i],
        border: Border.all(
            color: selected ? AppColors.goldLight : Colors.white24,
            width: selected ? 3 : 1.5),
      ),
      child: Text(_emojis[i], style: TextStyle(fontSize: size * 0.52, height: 1)),
    );
  }
}
