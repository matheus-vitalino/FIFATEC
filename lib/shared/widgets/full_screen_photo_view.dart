import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class FullScreenPhotoView extends StatelessWidget {
  final String photoPath;
  final String title;

  const FullScreenPhotoView({super.key, required this.photoPath, required this.title});

  @override
  Widget build(BuildContext context) {
    final exists = File(photoPath).existsSync();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: Center(
        child: Hero(
          tag: photoPath,
          child: InteractiveViewer(
            minScale: 0.9,
            maxScale: 4,
            child: exists
                ? Image.file(
                    File(photoPath),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: AppColors.textHint, size: 60),
                  )
                : const Icon(Icons.broken_image_outlined, color: AppColors.textHint, size: 60),
          ),
        ),
      ),
    );
  }
}
