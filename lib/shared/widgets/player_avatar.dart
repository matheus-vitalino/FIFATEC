import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class PlayerAvatar extends StatelessWidget {
  final String? photoPath;
  final String name;
  final double size;
  final bool showBorder;
  final Color? borderColor;
  final VoidCallback? onTap;

  const PlayerAvatar({
    super.key,
    this.photoPath,
    required this.name,
    this.size = 48,
    this.showBorder = false,
    this.borderColor,
    this.onTap,
  });

  bool get _hasPhoto => photoPath != null && File(photoPath!).existsSync();

  String get _initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Color get _avatarColor {
    final colors = [
      const Color(0xFF1B5E20), const Color(0xFF0D47A1),
      const Color(0xFF4A148C), const Color(0xFFE65100),
      const Color(0xFF880E4F), const Color(0xFF006064),
    ];
    final idx = name.codeUnits.fold(0, (a, b) => a + b) % colors.length;
    return colors[idx];
  }

  @override
  Widget build(BuildContext context) {
    Widget avatar;
    if (_hasPhoto) {
      avatar = ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: Image.file(
          File(photoPath!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildInitials(),
        ),
      );
    } else {
      avatar = _buildInitials();
    }

    if (showBorder) {
      avatar = Container(
        width: size + 4,
        height: size + 4,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: borderColor ?? AppColors.accent,
            width: 2,
          ),
        ),
        child: avatar,
      );
    }

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: avatar);
    }
    return avatar;
  }

  Widget _buildInitials() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _avatarColor,
        gradient: LinearGradient(
          colors: [_avatarColor, _avatarColor.withOpacity(0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          _initials,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: size * 0.38,
          ),
        ),
      ),
    );
  }
}